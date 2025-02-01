# CP Flink SQL

- [CP Flink SQL](#cp-flink-sql)
  - [Disclaimer](#disclaimer)
  - [Setup](#setup)
    - [Start Kind K8s Cluster](#start-kind-k8s-cluster)
    - [Start Kafka](#start-kafka)
    - [Install Confluent Manager for Apache Flink](#install-confluent-manager-for-apache-flink)
  - [Flink SQL](#flink-sql)
  - [Let's Play](#lets-play)
  - [Cleanup](#cleanup)

## Disclaimer

The code and/or instructions here available are **NOT** intended for production usage. 
It's only meant to serve as an example or reference and does not replace the need to follow actual and official documentation of referenced products.

## Setup

### Start Kind K8s Cluster

```shell
kind create cluster
```

In order to run the k8s dashboard:

```shell
k apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml --context kind-kind
k create serviceaccount -n kubernetes-dashboard admin-user
k create clusterrolebinding -n kubernetes-dashboard admin-user --clusterrole cluster-admin --serviceaccount=kubernetes-dashboard:admin-user
token=$(kubectl -n kubernetes-dashboard create token admin-user)
echo $token
k proxy 
```

Copy the token displayed on output and use it to login in K8s dashboard at http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/#/login

You may need to wait a couple of seconds for dashboard to become available.

Let it run and open another terminal.

### Start Kafka

Run:

```shell
kubectl create namespace confluent
kubectl config set-context --current --namespace=confluent
helm repo add confluentinc https://packages.confluent.io/helm
helm upgrade --install operator confluentinc/confluent-for-kubernetes
```

Check pod is ready:

```shell
watch kubectl get pods
```

Once the operator pod is ready we install kafka cluster:

```shell
kubectl apply -f kafka/kafka.yaml
```

And wait for all pods (1 kraft, 3 kafka) to be ready:

```shell
watch kubectl get pods
```

Now deploy control center:

```shell
kubectl apply -f kafka/controlcenter.yaml
```

And wait for pod to be ready:

```shell
watch kubectl get pods
```

Now we can forward the port of control center:

```shell
kubectl -n confluent port-forward controlcenter-0 9021:9021 > /dev/null 2>&1 &
```

And then open http://localhost:9021 and create a topic named `flink-input` and another named `message-count`.

###  Install Confluent Manager for Apache Flink

Install certificate manager:

```shell
kubectl create -f https://github.com/jetstack/cert-manager/releases/download/v1.8.2/cert-manager.yaml
```

Wait until an endpoint IP is assigned when executing the following:

```shell
watch kubectl get endpoints -n cert-manager cert-manager-webhook
```

Install Flink Kubernetes Operator:

```shell
kubectl config set-context --current --namespace=default
helm upgrade --install cp-flink-kubernetes-operator confluentinc/flink-kubernetes-operator
```

Install Confluent Manager for Apache Flink:

```shell
helm upgrade --install cmf \
confluentinc/confluent-manager-for-apache-flink 
```

Check pods are ready:

```shell
watch kubectl get pods
```

Open port forwarding for CMF:

```shell
kubectl port-forward svc/cmf-service 8080:80 > /dev/null 2>&1 &
```

## Flink SQL

We will be leveraging the standard `flink-sql-runner-example` (https://github.com/apache/flink-kubernetes-operator/tree/main/examples/flink-sql-runner-example).

Compile:

```shell
cd flink-sql/flink-sql-runner-example
mvn clean verify
```

Build the docker image and load in kind (it may take a bit to load cause the flink image is not so small):

```shell
DOCKER_BUILDKIT=1 docker build . -t flink-sql-runner-example:latest
kind load docker-image flink-sql-runner-example:latest
```

And now create our CP Flink environment and application:

```shell
cd ..
confluent flink environment create env1 --url http://localhost:8080 --kubernetes-namespace default 
confluent flink application create application-sql.json --environment env1 --url http://localhost:8080
```

Check pods are ready (1 job manager and 3 task managers):

```shell
watch kubectl get pods
```

We can check the Flink dashboard if we execute:

```shell
cd ..
confluent flink application web-ui-forward sql-example --environment env1 --port 8090 --url http://localhost:8080 > /dev/null 2>&1 &
```

And after a couple of seconds visit http://localhost:8090

## Let's Play

Now you can start producing with Control Center into the topic `flink-input` (just use the default example payload) and in parallel see the new count messages arriving at the `message-count`.

## Cleanup

```shell
kind delete cluster
```