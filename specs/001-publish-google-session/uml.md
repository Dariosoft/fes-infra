# UML 001 — Publicar cuentas y el secreto de Google

Diagrama del despliegue **real** en la rama `001/feat-publish-google-session`: plano público Minikube con DuckDNS + TLS, Ingress `/accounts`, secretos Google y env por overlay.

## Plano público Minikube (DuckDNS + TLS)

```mermaid
flowchart TB
  subgraph dns["Hosts DuckDNS + TLS secret friendly-e-shop-tls"]
    M["market.friendly-e-shop.duckdns.org"]
    P["panel.friendly-e-shop.duckdns.org"]
    A["api.friendly-e-shop.duckdns.org"]
  end

  subgraph ingress["Ingress Nginx — overlays/minikube/resources/ingress.yaml"]
    IS["Ingress storefront → client-web:8080"]
    IP["Ingress panel → panel-web:8080"]
    IA["Ingress api"]
  end

  M --> IS
  P --> IP
  A --> IA

  IA -->|"/accounts"| ACC["account-api:8080"]
  IA -->|"/catalog"| CAT["catalog-api:8080"]
  IA -->|"/orders"| ORD["order-api:8080"]
  IA -->|"/payments"| PAY["payment-api:8080"]
  IA -->|"/panel"| PAN["panel-api:8000"]
```

Nota: el Ingress usa **`market.*`** (no `shop.*`) para la tienda. Grafana local sigue en `grafana.friendly-e-shop.test` (HTTP, Ingress `local-tools`).

## Secretos Google → env de account-api

```mermaid
flowchart LR
  S["Secret app-secrets\noverlays/minikube/resources/secrets.yaml"]
  S -->|"google-client-id"| GID["GOOGLE_CLIENT_ID"]
  S -->|"google-client-secret"| GSEC["GOOGLE_CLIENT_SECRET"]
  GID --> ACC["Deployment account-api"]
  GSEC --> ACC

  OPT["scripts/load-google-oauth.sh\n(opcional)"]
  OPT -->|"patch stringData + rollout restart"| S
```

## Env por overlay — account-api y panel-api

```mermaid
flowchart TB
  subgraph mk["Overlay Minikube"]
    AEP["patches/account-api-env-patch.yaml"]
    AEP --> SCD["SESSION_COOKIE_DOMAIN=.friendly-e-shop.duckdns.org"]
    AEP --> SCS["SESSION_COOKIE_SECURE=true"]
    AEP --> BO["BROWSER_ORIGINS=https://market…,https://panel…"]
    AEP --> PUB["PUBLIC_API_BASE_URL=https://api.friendly-e-shop.duckdns.org"]

    PEP["patches/panel-api-env-patch.yaml"]
    PEP --> PPO["PANEL_PUBLIC_ORIGIN=https://panel.friendly-e-shop.duckdns.org"]
    PEP --> APB["ACCOUNTS_PUBLIC_BASE_URL=https://api.friendly-e-shop.duckdns.org"]
  end

  subgraph base["Base compartida"]
    CM["ConfigMap panel-api-config"]
    CM --> AABU["ACCOUNT_API_BASE_URL=\nhttp://account-api.apps.svc.cluster.local:8080"]
  end
```

## Hostinger — REPLACE_BASE_DOMAIN + SOPS

```mermaid
flowchart LR
  PH["secrets.placeholder.yaml\ngoogle-client-* = REPLACE_ME"]
  OP["Operador sustituye valores\nfuera de git"]
  ENC["scripts/encrypt-secrets.sh\n→ secrets.enc.yaml"]
  K["kustomization Hostinger\nreferencia secrets.enc.yaml"]
  PH --> OP --> ENC --> K

  HAP["account-api-env-patch.yaml"]
  HAP --> H1["SESSION_COOKIE_DOMAIN=.REPLACE_BASE_DOMAIN"]
  HAP --> H2["SESSION_COOKIE_SECURE=true"]
  HAP --> H3["BROWSER_ORIGINS=https://market/panel.REPLACE_BASE_DOMAIN"]
  HAP --> H4["PUBLIC_API_BASE_URL=https://api.REPLACE_BASE_DOMAIN"]

  HPP["panel-api-env-patch.yaml"]
  HPP --> H5["PANEL_PUBLIC_ORIGIN / ACCOUNTS_PUBLIC_BASE_URL\ncon REPLACE_BASE_DOMAIN"]
```

## Rutas de manifiestos (Minikube)

| Recurso | Ruta real |
|---|---|
| Ingress | `kubernetes/overlays/minikube/resources/ingress.yaml` |
| Secretos | `kubernetes/overlays/minikube/resources/secrets.yaml` |
| Env account-api | `kubernetes/overlays/minikube/patches/account-api-env-patch.yaml` |
| Env panel-api | `kubernetes/overlays/minikube/patches/panel-api-env-patch.yaml` |
| OAuth opcional | `scripts/load-google-oauth.sh` |

No existen `overlays/minikube/ingress.yaml` ni `overlays/minikube/secrets.yaml` en la raíz del overlay; viven bajo `resources/`.
