# Validation Record

Validated on 2026-09-19 using macOS ARM64, Docker Desktop, Minikube 1.39.0 and Kubernetes 1.37.0.

- The test cluster used 6 CPUs and 6 GiB because Docker Desktop was configured with 7.65 GiB total memory. The repository default remains the approved 8 GiB.
- All six application images built successfully for ARM64.
- All three Spring Boot unit tests passed under Java 25.
- Django system checks and its initial test passed under Python 3.14.
- React and Angular production builds passed.
- Both npm dependency trees reported zero known vulnerabilities.
- Kubeconform accepted all 50 Minikube resources and 33 standard Hostinger resources; the cert-manager CRD resource was intentionally skipped without a live CRD schema.
- Terraform 1.16.3 initialized with Hostinger provider 0.1.23 and validated without creating or changing infrastructure.
- Every application, platform and observability pod reached Ready state.
- Storefront, seller panel and the four API routes passed ingress smoke tests.
- PostgreSQL backups were written to MinIO and the catalog database was restored successfully.
- OpenTelemetry Collector accepted application telemetry and sent spans to Tempo and logs to Loki.
- Prometheus, Loki and Tempo health endpoints returned Ready.

## Post-rename verification

Re-validated on 2026-09-19 after renaming `backoffice-backend` → `panel-api`, `backoffice-frontend` → `panel-web`, `catalog-service` → `catalog-api`, `order-service` → `order-api`, `payment-service` → `payment-api` and `main-frontend` → `client-web`.

- No leftover Kubernetes Deployments, Services, ConfigMaps or Ingresses used the old names. Minikube contained only `friendly-e-shop/{catalog-api,order-api,payment-api,client-web,panel-api,panel-web}:dev` application images.
- All six application pods were Ready as `catalog-api`, `order-api`, `payment-api`, `panel-api`, `client-web` and `panel-web`. Ingress smoke tests passed for the storefront, seller panel and `/catalog`, `/orders`, `/payments`, `/panel`.
- Kubeconform again accepted 50 Minikube resources and 33 standard Hostinger resources (one cert-manager CRD skipped). Terraform 1.16.3 validated with Hostinger provider 0.1.23.
- Spring Boot unit tests passed under Java 25. Django system checks and its test passed. React and Angular production builds passed. `npm audit` could not be re-run because registry.npmjs.org returned HTTP 503 maintenance.
- PostgreSQL backups for `catalog`, `orders`, `payments` and `panel` were written to MinIO; `catalog-20260919T172402Z.dump` restored successfully and `/catalog` stayed Ready.
- OpenTelemetry Collector accepted spans and logs and exported them to Tempo and Loki. Live traces used the new service names (`catalog-api`, `order-api`, `payment-api`, `panel-api`). Loki still lists historical `service_name` values from before the rename (`backoffice-backend`, `catalog-service`, `order-service`, `payment-service`) because log retention is 24 hours; those are not leftover workloads.
- Prometheus, Loki and Tempo health endpoints returned Ready.
