# Architecture

Friendly E-Shop uses seven independently deployable applications and one infrastructure repository.

| Component | Runtime | Responsibility |
|---|---|---|
| account-api | Java 25 / Spring Boot | Accounts |
| catalog-api | Java 25 / Spring Boot | Products, prices and initial stock |
| order-api | Java 25 / Spring Boot | Orders and agreed purchase state |
| payment-api | Java 25 / Spring Boot | Payment attempts and idempotency |
| panel-api | Python / Django REST Framework | Shops and seller-panel APIs |
| client-web | React | Public storefront |
| panel-web | Angular LTS | Seller administration |

PostgreSQL is physically shared but each backend receives a separate database and credential. Services never write another service's tables. RabbitMQ provides asynchronous delivery and MinIO provides S3-compatible object storage.

Kubernetes resources are split into `apps`, `platform` and `observability` namespaces. Minikube runs the complete LGTM stack. Hostinger keeps only the OpenTelemetry Collector and forwards telemetry to Grafana Cloud.

The Hostinger topology is a single K3s node. It is appropriate for a learning environment and MVP, but it is not highly available.
