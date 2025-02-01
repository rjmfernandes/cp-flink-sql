# CP Flink SQL

- [CP Flink SQL](#cp-flink-sql)
  - [Disclaimer](#disclaimer)
  - [Setup](#setup)
    - [Start Kind K8s Cluster](#start-kind-k8s-cluster)
    - [Start Kafka](#start-kafka)
    - [Install Confluent Manager for Apache Flink](#install-confluent-manager-for-apache-flink)
  - [Run the Producer](#run-the-producer)
  - [Flink SQL](#flink-sql)
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

Leave the command running and open another terminal for next commands.

### Start Kafka

Run:

```shell
kubectl create namespace confluent
kubectl config set-context --current --namespace=confluent
helm repo add confluentinc https://packages.confluent.io/helm
helm upgrade --install operator confluentinc/confluent-for-kubernetes
```

Check pods:

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

And then open http://localhost:9021 and create a topic named `input` and another named `output`.

###  Install Confluent Manager for Apache Flink

Install certificate manager:

```shell
kubectl create -f https://github.com/jetstack/cert-manager/releases/download/v1.8.2/cert-manager.yaml
```

In general wait until an endpoint IP is assigned when executing the following:

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

Check pods are deployed correctly:

```shell
watch kubectl get pods
```

Open port forwarding for CMF:

```shell
kubectl port-forward svc/cmf-service 8080:80 > /dev/null 2>&1 &
```

## Run the Producer

The producer we will run is based on original code from https://github.com/apache/flink-playgrounds/tree/master/docker/ops-playground-image/java/flink-playground-clickcountjob (but we are not using the flink code part of that project).

To compile:

```shell
cd kafka/playground-clickcountproducer
mvn clean verify
```

Build the docker image:

```shell
DOCKER_BUILDKIT=1 docker build . -t my-kafka-producer:latest
kind load docker-image my-kafka-producer:latest
```

Deploy the producer:

```shell
kubectl apply -f producer.yaml 
```

You can list the pods:

```shell
kubectl get pods 
```

Copy the producer pod name and check logs:

```shell
kubectl logs -f kafka-producer-589dbb9c7f-tvd2n
```

And also check messages being written to topic `input` either on Control Center or running:

```shell
kubectl exec kafka-0 --namespace=confluent -- kafka-console-consumer --bootstrap-server localhost:9092 --topic input --from-beginning --property print.timestamp=true --property print.key=true --property print.value=true 
```

## Flink SQL

To compile:

```shell
cd ../../flink-sql/flink-sql-runner-example
mvn clean verify
```

Build the docker image and load in kind (this time will take a bit longer cause the flink image is bigger):

```shell
DOCKER_BUILDKIT=1 docker build . -t flink-sql-runner-example:latest
kind load docker-image flink-sql-runner-example:latest
```

And now create our service account, environment and application:

```shell
cd ..
confluent flink environment create env1 --url http://localhost:8080 --kubernetes-namespace default 
confluent flink application create application-sql.json --environment env1 --url http://localhost:8080
```

Check pods:

```shell
kubectl get pods
```

And check the logs of the job manager once running (replace by the name of your pod):

```shell
kubectl logs -f sql-example-7796c7f7c5-gkq2c
```

And now lets check our topic `output` either on Control Center or running:

```shell
kubectl exec kafka-0 --namespace=confluent -- kafka-console-consumer --bootstrap-server localhost:9092 --topic output --from-beginning --property print.timestamp=true --property print.key=true --property print.value=true
```

We can also check the Flink dashboard if we execute:

```shell
cd ..
confluent flink application web-ui-forward sql-example --environment env1 --port 8090 --url http://localhost:8080 > /dev/null 2>&1 &
```

And after a couple of seconds visit http://localhost:8090

## Cleanup

```shell
kind delete cluster
```