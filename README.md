# Friendly E-Shop Infrastructure

Portable Kubernetes infrastructure for local Minikube development and a future single-node K3s deployment on Hostinger.

## Local Quick Start

Start Docker Desktop, then run:

```bash
make bootstrap
make doctor
make minikube-create
make images-build
make deploy
make smoke-test
```

The Minikube profile uses 6 CPUs and 8 GiB RAM by default. Override them with `MINIKUBE_CPUS` and `MINIKUBE_MEMORY`.

Local endpoints:

| Endpoint | URL |
|---|---|
| Storefront | http://shop.friendly-e-shop.test |
| Seller panel | http://panel.friendly-e-shop.test |
| API | http://api.friendly-e-shop.test |
| Grafana | http://grafana.friendly-e-shop.test |

On macOS with Docker Desktop, run `minikube tunnel -p friendly-e-shop` and map the four local names to `127.0.0.1` in `/etc/hosts`. `make smoke-test` uses a temporary port-forward and does not require either step. Grafana development credentials are `admin` / `grafana-local`.

RabbitMQ and MinIO management interfaces remain internal. Access them with port forwarding:

```bash
kubectl -n platform port-forward service/rabbitmq 15672:15672
kubectl -n platform port-forward service/minio 9001:9001
```

## Commands

| Command | Action |
|---|---|
| `make bootstrap` | Install required CLI tools with Homebrew |
| `make doctor` | Verify tools and Docker |
| `make minikube-create` | Create the local cluster and addons |
| `make images-build` | Build all seven application images inside Minikube |
| `make deploy` | Apply the Minikube overlay and wait for applications |
| `make status` | Show pods, ingress and storage |
| `make smoke-test` | Test public routes |
| `make tunnel` | Expose local ingress routes until stopped with Ctrl+C |
| `make observability` | Port-forward Grafana |
| `make backup` | Back up PostgreSQL databases to MinIO |
| `make validate` | Validate Kustomize and Terraform |
| `make destroy` | Delete the Minikube profile |

See `docs/architecture.md`, `docs/stack.md`, `docs/secrets.md`, `docs/backups.md`, `docs/hostinger.md`, `docs/validation.md` and `docs/IMPLEMENTATION_PLAN.md` before changing the production-oriented template.
