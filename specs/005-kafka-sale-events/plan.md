# Plan 005 — Kafka KRaft, topic de pedidos y despliegue de analítica y notificaciones

## 1. Resumen

Agregar a `kubernetes/base/platform/` un broker Kafka en KRaft (`kafka.yaml`), un `Job` idempotente
que declara el topic `orders.events` (`kafka-topology.yaml`) y las bases `analytics` y `notifications`
en el init de PostgreSQL. Agregar a `kubernetes/base/` los despliegues `analytics-api` y
`notifications-api`, sus ConfigMaps y sus esperas al `Job`. Actualizar RBAC de espera, secretos,
NetworkPolicies, envs de `order-api` y `panel-api`, `deploy.sh` y la documentación.

Ningún repo de aplicación declara topología: este repo posee Kafka, topics, colas y secretos.
Cubre RF-1 … RF-19.

## 2. Kafka en KRaft

`kubernetes/base/platform/kafka.yaml`:

- `Service` `kafka` (ClusterIP) puerto `9092` nombre `plaintext`.
- `StatefulSet` `kafka`, 1 réplica, `serviceName: kafka`.
- Imagen fijada `apache/kafka:4.1.0` (sin `latest`).
- `securityContext` no root, seccomp `RuntimeDefault`, capacidades `ALL` descartadas.
- Env KRaft combinado:
  - `KAFKA_NODE_ID=1`
  - `KAFKA_PROCESS_ROLES=broker,controller`
  - `KAFKA_CONTROLLER_QUORUM_VOTERS=1@kafka.platform.svc.cluster.local:9093`
  - `KAFKA_LISTENERS=PLAINTEXT://0.0.0.0:9092,CONTROLLER://0.0.0.0:9093`
  - `KAFKA_ADVERTISED_LISTENERS=PLAINTEXT://kafka.platform.svc.cluster.local:9092`
  - `KAFKA_CONTROLLER_LISTENER_NAMES=CONTROLLER`
  - `KAFKA_LISTENER_SECURITY_PROTOCOL_MAP=CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT`
  - `KAFKA_INTER_BROKER_LISTENER_NAME=PLAINTEXT`
  - `KAFKA_LOG_DIRS=/var/lib/kafka/data`
  - `KAFKA_AUTO_CREATE_TOPICS_ENABLE=false`
  - `KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR=1`
  - `KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR=1`
  - `KAFKA_TRANSACTION_STATE_LOG_MIN_ISR=1`
  - `KAFKA_GROUP_INITIAL_REBALANCE_DELAY_MS=0`
  - `KAFKA_HEAP_OPTS=-Xms512m -Xmx512m`
- `resources` requests `cpu: 200m, memory: 768Mi`, limits `cpu: "1", memory: 1536Mi`.
- Sondas TCP `9092`.
- `volumeClaimTemplates` `data` de `10Gi`.
- `automountServiceAccountToken: false`.

## 3. Declaración del topic

`kubernetes/base/platform/kafka-topology.yaml`:

- `ConfigMap` `kafka-topology` con `topology.sh`:
  1. espera `kafka:9092` con `kafka-topics.sh --list` y reintentos acotados;
  2. `kafka-topics.sh --create --if-not-exists --bootstrap-server kafka:9092 --topic orders.events --partitions 3 --replication-factor 1 --config retention.ms=604800000 --config cleanup.policy=delete`;
  3. lista el topic para dejar evidencia en logs.
- `Job` `kafka-topology` en `platform`, `backoffLimit: 6`, `activeDeadlineSeconds: 600`, sin
  `ttlSecondsAfterFinished`. Usa la misma imagen `apache/kafka:4.1.0`, `automountServiceAccountToken:
  false`, no root y límites. El script se monta desde el `ConfigMap`.
- Idempotente: `--if-not-exists`; si existe con otra configuración, el comando falla visiblemente.

`kubernetes/base/platform/rabbitmq-topology.yaml` agrega las colas `seller.notify.retry`
(TTL 30 s, DLX por defecto → `seller.notify`) y `seller.notify.dlq` (14 días) para el consumidor
de `notifications-api`. No se tocan los argumentos de `seller.notify` para no recrear la cola
existente: el consumidor republica explícitamente en la cola de reintento y confirma el original.

## 4. Bases de datos

`kubernetes/base/platform/postgresql.yaml`:

- `01-create-databases.sh` agrega `ANALYTICS_DB_PASSWORD` y `NOTIFICATIONS_DB_PASSWORD`,
  crea los usuarios `analytics` y `notifications` y sus bases.
- El contenedor recibe las dos contraseñas desde `platform-secrets`.
- Nota operativa: el init solo corre en un volumen nuevo. En Minikube existente se recrea el
  volumen o se crean usuarios/bases a mano; se documenta en `docs/stack.md`.

Secretos:

- `kubernetes/overlays/minikube/resources/secrets.yaml`: claves `analytics-db-password` y
  `notifications-db-password` en `app-secrets` y `platform-secrets`.
- `kubernetes/overlays/hostinger/secrets.placeholder.yaml`: mismas claves con `REPLACE_ME`.
- No se agregan secretos de Kafka: el listener interno es `PLAINTEXT`.

## 5. Despliegues de las aplicaciones

`kubernetes/base/analytics-api/`:

- `deployment.yaml`, `service.yaml`, `configmap.yaml`, `kustomization.yaml`.
- Puerto `8080`, sondas `/actuator/health/live` y `/actuator/health/ready`.
- `initContainers` con `registry.k8s.io/kubectl:v1.37.1` que esperan `job/kafka-topology`
  (`--for=create` y `--for=condition=complete`).
- Env `KAFKA_BOOTSTRAP_SERVERS`, `DATABASE_URL`, `DATABASE_USERNAME`, `DATABASE_PASSWORD`,
  `OTEL_RESOURCE_ATTRIBUTES`.
- `requests {cpu: 100m, memory: 256Mi}`, `limits {cpu: 500m, memory: 512Mi}`.

`kubernetes/base/notifications-api/`: igual, más `RABBITMQ_*` y `DATABASE_*` de `notifications`.

RBAC:

- Extender `rabbitmq-topology-rbac.yaml` (o un recurso equivalente) para que el ServiceAccount
  `rabbitmq-topology-waiter` pueda observar también `kafka-topology` en `platform`.

## 6. Env y red

`kubernetes/base/order-api/deployment.yaml`: agregar `KAFKA_BOOTSTRAP_SERVERS`.

`kubernetes/base/panel-api/deployment.yaml` / `configmap.yaml`: agregar
`ANALYTICS_API_BASE_URL` y `NOTIFICATIONS_API_BASE_URL`.

`kubernetes/base/platform/network-policies.yaml`: permitir `9092` desde `apps` y `platform` hacia
Kafka. Las dos apps nuevas usan la política existente hacia PostgreSQL y OTel; `notifications-api`
usa RabbitMQ `5672`.

`kubernetes/base/kustomization.yaml`: agregar `analytics-api` y `notifications-api`.

## 7. Despliegue local

`scripts/deploy/deploy.sh`:

- sumar `analytics-api` y `notifications-api` a `services`;
- aplicar `kafka.yaml` junto a PostgreSQL/RabbitMQ/MinIO y esperar el StatefulSet;
- borrar y reaplicar `job/kafka-topology` y esperar `Completed` antes de las apps;
- mantener el orden actual de RabbitMQ y su `Job`.

## 8. Documentación

`docs/stack.md`: sección de mensajería con Kafka, topic, grupos, retención y el contrato de
`orders.events`. `docs/hostinger.md`: verificar el `Job` de Kafka antes de cerrar el despliegue.

## 9. Verificación

- `kustomize build` de ambos overlays.
- `make validate`, `make policy`, `make lint`, `make consistency`.
- `make deploy` y `kubectl -n platform wait --for=condition=complete job/kafka-topology`.
- Topic `orders.events` con 3 particiones (`kafka-topics.sh --describe`).
- `kubectl -n apps rollout status deployment/analytics-api deployment/notifications-api`.

## 10. Trazabilidad RF → plan

| RF | Sección |
|---|---|
| RF-1, RF-2 | §2 |
| RF-3 | §2, §6 |
| RF-4, RF-5, RF-6 | §3 |
| RF-7 | §4 |
| RF-8, RF-11, RF-12 | §5 |
| RF-9 | §5 |
| RF-10 | §6 |
| RF-13 | §6 |
| RF-14, RF-15 | §6 |
| RF-16 | §7 |
| RF-17 | §2–§7 (base Kustomize) |
| RF-18 | alcance mínimo; no se tocan manifiestos ajenos |
| RF-19 | §4 (secretos, sin credenciales en logs) |
| RF-20 | §3 (colas de reintento y descarte de `seller.notify`) |
