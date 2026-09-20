# Friendly E-Shop Infrastructure Implementation Plan

## Scope

Create six independently versioned application skeletons and one infrastructure repository. The first executable environment is Minikube. Hostinger is represented by a K3s-ready overlay and an inert Terraform template.

## Repositories

- `catalog-api`: Java 25 LTS and Spring Boot catalog API.
- `order-api`: Java 25 LTS and Spring Boot order API.
- `payment-api`: Java 25 LTS and Spring Boot payment API.
- `client-web`: React and Vite public storefront.
- `panel-api`: Django LTS and Django REST Framework API.
- `panel-web`: Angular LTS seller panel.
- `infra`: Kubernetes, Kustomize, Terraform and operational scripts.

## Kubernetes

- Build secure Deployments and Services with health probes, resource limits and non-root containers.
- Deploy PostgreSQL, RabbitMQ and MinIO as single-replica stateful workloads.
- Keep one PostgreSQL instance with separate databases and users for each backend.
- Separate resources into `apps`, `platform` and `observability` namespaces.
- Expose local applications through ingress hostnames and path-based API routing.
- Use a complete local Grafana, Prometheus, Loki, Tempo and OpenTelemetry stack.
- Keep only OpenTelemetry Collector in Hostinger and export telemetry to Grafana Cloud.
- Treat the Hostinger one-node topology as non-HA.

## Security And Versions

- Pin stable or LTS dependency and container versions; never use `latest`.
- Use Renovate configurations for controlled updates and digest pinning.
- Keep local development secrets separate from Hostinger secrets.
- Prepare SOPS and age encryption for Hostinger.
- Disable service-account token mounting where it is not required.
- Apply runtime-default seccomp, dropped capabilities and read-only filesystems where supported.

## Hostinger

- Prepare official `hostinger/hostinger` Terraform provider configuration.
- Disable billable VPS provisioning by default.
- Protect managed VPS resources against accidental destruction.
- Provide an idempotent Ubuntu LTS and K3s bootstrap script.
- Parameterize the GHCR owner, domain, Hostinger plan, data center and OS template.
- Do not execute `terraform apply` during initialization.

## Operations

- Supply a Brewfile and diagnostics for required tooling.
- Automate Minikube creation, image builds, deployment, smoke tests and deletion.
- Supply manual PostgreSQL backup and restore scripts using MinIO.
- Validate both Kustomize overlays and Terraform before deployment.
- Initialize each child directory as a separate local Git repository without creating remotes or commits.

## Deferred Work

Jenkins, Kafka, Elasticsearch, Keycloak, Mercado Pago, business workflows, remote GitHub repositories and highly available infrastructure are intentionally deferred.

## Execution Result

This plan was executed and verified on 2026-09-19. The full local stack reached Ready state in Minikube, ingress smoke tests passed, PostgreSQL backup/restore was exercised, and OpenTelemetry delivery to the local Grafana stack was confirmed. Detailed evidence is recorded in `docs/validation.md`.
