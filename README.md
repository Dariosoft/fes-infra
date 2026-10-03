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

## Debugging catalog-api

After applying the Minikube overlay with `make deploy`, choose a Java API attach profile in VS Code and press F5. The IDE opens a temporary port-forward to the selected running pod and closes it when the debug session ends. Available profiles are `catalog-api` (5005), `account-api` (5006), `order-api` (5007) and `payment-api` (5008). Minikube enables JDWP only for these local deployments; the Hostinger overlay does not enable the debugger. Requests through the local API Ingress are handled by the same pods attached to VS Code.

RabbitMQ and MinIO management interfaces remain internal. Access them with port forwarding:

```bash
kubectl -n platform port-forward service/rabbitmq 15672:15672
kubectl -n platform port-forward service/minio 9001:9001
```

## Use production

See `docs/architecture.md`, `docs/stack.md`, `docs/secrets.md`, `docs/backups.md`, `docs/hostinger.md`, `docs/validation.md` and `docs/IMPLEMENTATION_PLAN.md` before changing the production-oriented template.
