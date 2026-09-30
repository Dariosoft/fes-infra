# Friendly E-Shop Infrastructure

Portable Kubernetes infrastructure for local Minikube development and a future single-node K3s deployment on Hostinger.

## Local Quick Start

Start Docker Desktop, then run:

```bash
make bootstrap
make doctor
make minikube-create
make deploy
make smoke-test
```

The Minikube profile uses 6 CPUs and 8 GiB RAM by default. Override them with `MINIKUBE_CPUS` and `MINIKUBE_MEMORY`.

Local endpoints:

| Endpoint | URL |
|---|---|
| Storefront | https://market.friendly-e-shop.duckdns.org |
| Seller panel | https://panel.friendly-e-shop.duckdns.org |
| API | https://api.friendly-e-shop.duckdns.org |
| Grafana | http://grafana.friendly-e-shop.test |

On macOS with Docker Desktop, run `minikube tunnel -p friendly-e-shop` and map `market.friendly-e-shop.duckdns.org`, `panel.friendly-e-shop.duckdns.org`, `api.friendly-e-shop.duckdns.org` and `grafana.friendly-e-shop.test` to `127.0.0.1` in `/etc/hosts`. `make smoke-test` uses a temporary port-forward and does not require either step. Grafana development credentials are `admin` / `grafana-local`. The DuckDNS certificate installed by `make deploy` is local; the browser will ask before trusting HTTPS.

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
| `make stop` | Stop the cluster, the source mount, and the tunnel. Disk data is kept |
| `make start` | Start a stopped cluster and mount the local checkouts again |
| `make images-build` | Build the production-style application images inside Minikube |
| `make deploy` | Mount the local checkouts, apply the Minikube overlay, and wait for the applications |
| `make status` | Show pods, ingress and storage |
| `make smoke-test` | Test public routes |
| `make tunnel` | Expose local ingress routes until stopped with Ctrl+C |
| `make observability` | Port-forward Grafana |
| `make backup` | Back up PostgreSQL databases to MinIO |
| `make validate` | Validate Kustomize and Terraform |
| `make destroy` | Delete the Minikube profile |

See `docs/architecture.md`, `docs/stack.md`, `docs/secrets.md`, `docs/backups.md`, `docs/hostinger.md`, `docs/validation.md` and `docs/IMPLEMENTATION_PLAN.md` before changing the production-oriented template.
