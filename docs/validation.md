# Validation Record

Validated on 2026-09-19 using macOS ARM64, Docker Desktop, Minikube 1.39.0 and Kubernetes 1.37.0.

- The test cluster used 6 CPUs and 6 GiB because Docker Desktop was configured with 7.65 GiB total memory. The repository default remains the approved 8 GiB.
- Seven application images are expected: `account-api`, `catalog-api`, `order-api`, `payment-api`, `client-web`, `panel-api` and `panel-web` (the 2026-09-19 run covered the six apps then present; `account-api` was added later).
- All three Spring Boot unit tests passed under Java 25.
- Django system checks and its initial test passed under Python 3.14.
- React and Angular production builds passed.
- Both npm dependency trees reported zero known vulnerabilities.
- Kubeconform accepted all Minikube and standard Hostinger resources; the cert-manager CRD resource was intentionally skipped without a live CRD schema.
- Terraform 1.16.3 initialized with Hostinger provider 0.1.23 and validated without creating or changing infrastructure.
- Every application, platform and observability pod reached Ready state.
- Storefront, seller panel and the API routes passed ingress smoke tests (including `/accounts` after `account-api` was added).
- PostgreSQL backups were written to MinIO and the catalog database was restored successfully.
- OpenTelemetry Collector accepted application telemetry and sent spans to Tempo and logs to Loki.
- Prometheus, Loki and Tempo health endpoints returned Ready.

## Post-rename verification

Re-validated on 2026-09-19 after standardizing all application names with the `{domain}-{role}` convention.

- No leftover Kubernetes Deployments, Services, ConfigMaps or Ingresses used the old names. Application images follow `friendly-e-shop/{account-api,catalog-api,order-api,payment-api,client-web,panel-api,panel-web}:dev`.
- Application pods are Ready as `account-api`, `catalog-api`, `order-api`, `payment-api`, `panel-api`, `client-web` and `panel-web`. Ingress smoke tests cover the storefront, seller panel and `/accounts`, `/catalog`, `/orders`, `/payments`, `/panel`.
- Kubeconform accepts the Minikube and Hostinger overlays (one cert-manager CRD skipped). Terraform 1.16.3 validates with Hostinger provider 0.1.23.
- Spring Boot unit tests passed under Java 25. Django system checks and its test passed. React and Angular production builds passed. `npm audit` could not be re-run because registry.npmjs.org returned HTTP 503 maintenance.
- PostgreSQL backups for `accounts`, `catalog`, `orders`, `payments` and `panel` are written to MinIO; `catalog-20260919T172402Z.dump` restored successfully and `/catalog` stayed Ready.
- OpenTelemetry Collector accepts spans and logs and exports them to Tempo and Loki using `account-api`, `catalog-api`, `order-api`, `payment-api` and `panel-api` as service names.
- Prometheus, Loki and Tempo health endpoints returned Ready.

## RabbitMQ sale topology (spec 004)

The static checks do not need a cluster:

```bash
kustomize build kubernetes/overlays/minikube | grep -c 'name: rabbitmq-topology'
kustomize build kubernetes/overlays/hostinger | grep -c 'name: rabbitmq-topology'
make validate
make policy
make consistency
```

Both renders must show exactly one `ConfigMap` and one `Job` named `rabbitmq-topology`. In Minikube,
after `make deploy`:

```bash
kubectl -n platform wait --for=condition=complete --timeout=300s job/rabbitmq-topology
kubectl -n platform logs job/rabbitmq-topology
kubectl -n apps get deploy order-api catalog-api -o jsonpath='{range .items[*]}{.metadata.name}{" init="}{.spec.template.spec.initContainers[*].name}{"\n"}{end}'
kubectl -n platform get role,rolebinding rabbitmq-topology-waiter
kubectl -n apps get pods -l 'app.kubernetes.io/name in (order-api,catalog-api)' -o wide
kubectl -n platform port-forward service/rabbitmq 15672:15672 &
RMQ_PASSWORD=$(kubectl -n platform get secret platform-secrets -o jsonpath='{.data.rabbitmq-password}' | base64 -d)
curl -s -u "app:${RMQ_PASSWORD}" http://127.0.0.1:15672/api/exchanges/friendly | jq -r '.[].name'
curl -s -u "app:${RMQ_PASSWORD}" http://127.0.0.1:15672/api/queues/friendly | jq -r '.[] | [.name, .durable, .arguments] | @json'
curl -s -u "app:${RMQ_PASSWORD}" http://127.0.0.1:15672/api/bindings/friendly | jq -r '.[] | select(.source != "") | [.source, .routing_key, .destination] | @json'
```

Expect the exchanges `orders` and `stock` (topic, durable), the seven queues with the arguments in
`docs/stack.md`, and the four bindings `orders/order.placed → stock.reserve`, `orders/order.placed →
seller.notify`, `stock/stock.reserved → order.stock-results` and `stock/stock.rejected →
order.stock-results`.

Publish fan-out and an unbound routing key through the management API:

```bash
publish() { curl -s -u "app:${RMQ_PASSWORD}" -H 'content-type: application/json' \
  -d "{\"properties\":{},\"routing_key\":\"$2\",\"payload\":\"test\",\"payload_encoding\":\"string\"}" \
  "http://127.0.0.1:15672/api/exchanges/friendly/$1/publish"; }
publish orders order.placed
publish stock stock.reserved
publish stock stock.rejected
publish orders order.unbound
curl -s -u "app:${RMQ_PASSWORD}" http://127.0.0.1:15672/api/queues/friendly | jq -r '.[] | [.name, .messages] | @tsv'
```

`stock.reserve` and `seller.notify` receive the `order.placed` copy; `order.stock-results` receives
both stock results; `order.unbound` reaches none of them. To exercise the retry path, reject one
message and confirm it is not redelivered before 30 seconds:

```bash
curl -s -u "app:${RMQ_PASSWORD}" -H 'content-type: application/json' \
  -d '{"count":1,"ackmode":"reject_requeue_false","encoding":"auto"}' \
  http://127.0.0.1:15672/api/queues/friendly/stock.reserve/get
curl -s -u "app:${RMQ_PASSWORD}" http://127.0.0.1:15672/api/queues/friendly/stock.reserve.retry | jq .messages
sleep 30
curl -s -u "app:${RMQ_PASSWORD}" http://127.0.0.1:15672/api/queues/friendly/stock.reserve | jq .messages
```

After the fifth rejected attempt the consumer contract publishes to `stock.reserve.dlq` or
`order.stock-results.dlq`; those queues declare `x-message-ttl` of `1209600000`. Finally, restart
the broker with messages queued and confirm the durable queues and unexpired messages survive:

```bash
kubectl -n platform rollout restart statefulset/rabbitmq
kubectl -n platform rollout status statefulset/rabbitmq --timeout=300s
unset RMQ_PASSWORD
```

Deleting a `Completed` `rabbitmq-topology` `Job` and applying the overlay again must leave the same
exchanges, queues and bindings without duplicates or `PRECONDITION_FAILED`.

On a clean cluster, `make deploy` must apply the platform and the topology Job before creating the
application pods. During that window `order-api` and `catalog-api` remain in `Init` with
`wait-for-rabbitmq-topology-job` / `wait-for-rabbitmq-topology`; once the Job is `Completed`, both
main containers start and the queues show a consumer.
