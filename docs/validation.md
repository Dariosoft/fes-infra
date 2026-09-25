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
