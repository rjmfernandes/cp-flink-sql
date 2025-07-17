# CP Flink SQL

- [CP Flink SQL](#cp-flink-sql)
  - [Disclaimer](#disclaimer)
- [Setup](#setup)
  - [Start Kind K8s Cluster](#start-kind-k8s-cluster)
  - [Start Kafka](#start-kafka)
  - [Install Confluent Manager for Apache Flink](#install-confluent-manager-for-apache-flink)
- [Flink SQL](#flink-sql)
  - [Let's Play](#lets-play)
    - [Control Center UI Stops Displaying Issue](#control-center-ui-stops-displaying-issue)
  - [Cleanup](#cleanup)

## Disclaimer

The code and/or instructions here available are **NOT** intended for production usage.
It's only meant to serve as an example or reference and does not replace the need to follow actual and official documentation of referenced products.

# Setup

## Start Kind K8s Cluster

```shell
kind create cluster --image kindest/node:v1.31.0
```

In order to run the k8s dashboard:

```shell
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml --context kind-kind
kubectl create serviceaccount -n kubernetes-dashboard admin-user
kubectl create clusterrolebinding -n kubernetes-dashboard admin-user --clusterrole cluster-admin --serviceaccount=kubernetes-dashboard:admin-user
token=$(kubectl -n kubernetes-dashboard create token admin-user)
echo $token
kubectl proxy
```

Copy the token displayed on output and use it to login in K8s dashboard at http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/#/login

You may need to wait a couple of seconds for dashboard to become available.

Let it run and open another terminal.

In case you are logged out cause of inactivity you may see errors as:

```
E0225 13:50:19.136484   67149 proxy_server.go:147] Error while proxying request: context canceled
```

Just stop the proxy before and execute again and login with the new token.

## Start Kafka

Run:

```shell
kubectl create namespace confluent
kubectl config set-context --current --namespace=confluent
helm repo add confluentinc https://packages.confluent.io/helm
helm repo update
helm upgrade --install operator confluentinc/confluent-for-kubernetes
```

Check pod is ready:

```shell
watch kubectl get pods
```

Once the operator pod is ready we install our CP nodes:

```shell
kubectl apply -f kafka/kafka.yaml
```

And wait for all pods (1 kraft, 1 broker, 1 SR, 1 C3) to be ready (it will take some time...):

```shell
watch kubectl -n confluent get pods
```

Once everything is completely ready you should have something like this:

```
NAME                                  READY   STATUS    RESTARTS        AGE
confluent-operator-66c65956d5-jdw9x   1/1     Running   0               6m36s
controlcenter-ng-0                    3/3     Running   0               5m54s
kafka-0                               1/1     Running   0               2m38s
kraftcontroller-0                     1/1     Running   0               5m54s
schemaregistry-0                      1/1     Running   5 (2m35s ago)   5m54s
```

Now we can forward the port of Control Center Next Generation:

```shell
kubectl -n confluent port-forward controlcenter-ng-0 9021:9021 > /dev/null 2>&1 &
```

And then open http://localhost:9021 and check topics `flink-input` and `message-count` have been already created with their corresponding schemas as per `kafka/kafka.yaml` file.

You should see an error stating `The system cannot connect to Confluent Manager for Apache Flink.`. It's expected cause we didnt install it yet.

## Install Confluent Manager for Apache Flink

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
kubectl config set-context --current --namespace=confluent
helm upgrade --install cp-flink-kubernetes-operator --version "~1.120.0" confluentinc/flink-kubernetes-operator --set watchNamespaces="{confluent}"
```

Install Confluent Manager for Apache Flink:

```shell
helm upgrade --install cmf confluentinc/confluent-manager-for-apache-flink \
    --set cmf.sql.production=false \
    --namespace confluent
```

Check pods are ready (CFO and CMF):

```shell
watch kubectl -n confluent get pods
```

Open port forwarding for CMF:

```shell
kubectl port-forward service/cmf-service 8080:80 -n confluent > /dev/null 2>&1 &
```

# Flink SQL

Let's first create our environment:

```shell
confluent flink environment create env1 --url http://localhost:8080 --kubernetes-namespace confluent
```

In case you get an error like this:

```
Error: you must log out of Confluent Cloud to use this command

Suggestions:
    Log out with `confluent logout`.
```

Make sure to login into confluent cloud `confluent login` and logout after `confluent logout` (in case doing the logout only gives you an error), and execute again the creation of environment.

We can list it:

```shell
confluent flink environment list --url http://localhost:8080
```

It should also be listed from the Control Center UI (with no more errors stating it cannot connect to Confluent Manager for Apache Flink SQL).

Now we can create our catalog (basically allowing Flink to automatically recognize our kafka cluster, topics and schema registry - no need to create tables and specify Flink connectors as usual with Apache Flink):

```shell
confluent flink catalog create flink/catalog.json --url http://localhost:8080
```

Now we can create our compute pool:

```shell
confluent flink compute-pool create flink/compute-pool.json --environment env1 --url http://localhost:8080
```

We won't be able to see the compute pool listed in Control Center UI (at least on the current version) but we can list it:

```shell
confluent flink compute-pool list --environment env1 --url http://localhost:8080
```

Now we can submit our sql statement to the compute pool:

```shell
confluent --environment env1 flink statement create flink-statement \
  --catalog kafka-cat \
  --database main-kafka-cluster \
  --compute-pool pool \
  --parallelism 1 \
--sql $'INSERT INTO `message-count`
/*+ OPTIONS(\'properties.transaction.timeout.ms\'=\'300000\') */
SELECT
  CAST(itemid AS BYTES) AS `key_key`,
  itemid AS `id`,
  CAST(CHAR_LENGTH(itemid) AS BIGINT) AS `count`
FROM `flink-input`;' \
  --url http://localhost:8080
```

You should get as response something like this:

```
+---------------+-------------------------------------------------------+
| Creation Date | 2025-07-17T00:17:12.247Z                              |
| Name          | flink-statement                                       |
| Statement     | INSERT INTO `message-count` /*+                       |
|               | OPTIONS('properties.transaction.timeout.ms'='300000') |
|               | */ SELECT   CAST(itemid AS BYTES) AS `key_key`,       |
|               | itemid AS `id`,   CAST(CHAR_LENGTH(itemid) AS BIGINT) |
|               | AS `count` FROM `flink-input`;                        |
| Compute Pool  | pool                                                  |
| Status        | PENDING                                               |
| Status Detail | Statement execution pending.                          |
| Parallelism   | 1                                                     |
| Stopped       | false                                                 |
| SQL Kind      | INSERT_INTO                                           |
| Append Only   | true                                                  |
+---------------+-------------------------------------------------------+
```

You can check the start of the pods (jobmanager and taskmanager) for the execution of our statement with:

```shell
watch kubectl -n confluent get pods
```

This statement job is basically counting the numbers of characters on the `itemid` field of the json messages entering the topic `flink-input` and sinking the `count` into the `message-count` topic. Using the `itemid` value for the `key` and the field `id` of the message in `message-count`.

## Let's Play

You can have open one browser window of control center on the `flink-input` messages tab and the other into the `message-count` topic:

- As you produce a message using the sample message of Control Center into the `flink-input` topic, you should see the count for the `itemid` field show up on `message-count` topic.
- You can try changing the value of the `itemid` field in other entries of `flink-input` and see the `count` change for `message-count`.

You can check the status of the statement execution by running:

```shell
confluent flink statement list --environment env1 --url http://localhost:8080
```

You can also open the Flink UI by executing:

```shell
kubectl port-forward service/flink-statement-rest 8081:8081 -n confluent > /dev/null 2>&1 &
```

And then access http://localhost:8081

If you wish to delete the statement just execute:

```shell
confluent --environment env1 flink statement delete flink-statement --url http://localhost:8080
```

You should see the pods getting terminated with:

```shell
watch kubectl -n confluent get pods
```

After you can also delete the compute pool with:

```shell
confluent flink compute-pool delete pool --environment env1 --url http://localhost:8080
```

### Control Center UI Stops Displaying Issue

You may loose access to Control Center UI. In such cases you will need to stop the process ocuppying the port 9021 (the forward of the C3 pod) and restart the forwarding. If you are on a mac do as follows:

```shell
sudo lsof -i :9021
```

This will give you the PID of the process that you need to kill.

Then reexecute:

```shell
kubectl -n confluent port-forward controlcenter-ng-0 9021:9021 > /dev/null 2>&1 &
```

## Cleanup

```shell
kind delete cluster
```
