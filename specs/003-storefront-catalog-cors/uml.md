# UML 003 — Entregar el origen del Storefront a catalog-api

Diagramas del desarrollo descrito por `plan.md` y `tasks.md` en la rama
`003/feat-storefront-catalog-cors`. El corte solo agrega la variable de entorno `BROWSER_ORIGINS`
al contenedor `catalog-api` desde los patches de cada overlay; no cambia tipos, capas ni servicios
de aplicación, por lo que el UML se limita a la estructura de configuración y al flujo de consumo
desde el navegador.

Los diagramas muestran las relaciones operativas relevantes y omiten dependencias transitivas que
ya quedan explicadas por el recurso dueño (base, overlay o patch).

## Estructura: base + overlay → env de catalog-api

```mermaid
flowchart TB
  subgraph base["Base compartida"]
    BD["kubernetes/base/catalog-api/deployment.yaml<br/>env: DATABASE_URL, DATABASE_USERNAME,<br/>DATABASE_PASSWORD, RABBITMQ_HOST,<br/>RABBITMQ_USERNAME, RABBITMQ_PASSWORD,<br/>S3_ENDPOINT, S3_BUCKET, S3_ACCESS_KEY,<br/>S3_SECRET_KEY, OTEL_RESOURCE_ATTRIBUTES"]
  end

  subgraph mk["Overlay Minikube"]
    MKP["patches/catalog-api/env-patch.yaml<br/>PUBLIC_API_BASE_URL=https://api.friendly-e-shop.duckdns.org<br/>BROWSER_ORIGINS=https://market.friendly-e-shop.duckdns.org"]
    MKI["resources/ingress.yaml<br/>Ingress storefront<br/>host market.friendly-e-shop.duckdns.org"]
    MKL["patches/catalog-api/live.yaml<br/>patches/catalog-api/debug.yaml<br/>(image, JAVA_DEBUG_OPTS)"]
  end

  subgraph ho["Overlay Hostinger"]
    HOP["catalog-api-env-patch.yaml<br/>PUBLIC_API_BASE_URL=https://api.REPLACE_BASE_DOMAIN<br/>BROWSER_ORIGINS=https://market.REPLACE_BASE_DOMAIN"]
    HOI["ingress.yaml<br/>host market.REPLACE_BASE_DOMAIN"]
  end

  BD -->|"merge por name"| MKP
  BD -->|"merge por name"| HOP
  MKP --> MKENV["env renderizado Minikube<br/>BROWSER_ORIGINS=https://market.friendly-e-shop.duckdns.org"]
  HOP --> HOENV["env renderizado Hostinger<br/>BROWSER_ORIGINS=https://market.REPLACE_BASE_DOMAIN"]
  MKI -.->|"mismo host"| MKENV
  HOI -.->|"mismo marcador"| HOENV
  MKL -.->|"conserva variables y modo local"| MKENV
```

Nota: el merge estratégico de `env` se hace por la clave `name`; la entrada nueva no reemplaza las
diez variables de la base ni `PUBLIC_API_BASE_URL`. El panel no aparece: queda fuera de alcance.

## Flujo principal: render del origen y lectura pública desde el navegador

```mermaid
sequenceDiagram
  autonumber
  actor OP as Operador
  participant KZ as kustomize build
  participant MK as patches/catalog-api/env-patch.yaml (Minikube)
  participant HO as catalog-api-env-patch.yaml (Hostinger)
  participant API as API server (kubectl apply)
  participant DEP as Deployment catalog-api (namespace apps)
  participant POD as Pod catalog-api puerto 8080
  participant BR as Navegador del Storefront
  participant ST as client-web (otro repositorio)

  OP->>KZ: make validate / make deploy (overlay del entorno)
  alt Entorno Minikube
    KZ->>MK: lee patch de env
    MK-->>KZ: BROWSER_ORIGINS=https://market.friendly-e-shop.duckdns.org
  else Entorno Hostinger
    KZ->>HO: lee patch de env
    HO-->>KZ: BROWSER_ORIGINS=https://market.REPLACE_BASE_DOMAIN
  end
  KZ->>KZ: merge base catalog-api + patch (por name)
  KZ-->>API: Deployment renderizado con env completo
  API->>DEP: aplica el Deployment
  DEP->>POD: arranca con BROWSER_ORIGINS
  BR->>ST: abre el Storefront (market.*)
  ST->>POD: GET /catalog (lectura pública) con Origin del Storefront
  alt Origin coincide con BROWSER_ORIGINS
    POD-->>BR: respuesta autorizada para lectura pública
  else Origin distinto, IP/puerto u otro esquema
    POD-->>BR: sin autorización (no hay comodín ni origen inferido)
  end
```

## Secuencia alternativa: Hostinger con el marcador sin sustituir

```mermaid
sequenceDiagram
  autonumber
  actor OP2 as Persona que prepara el despliegue
  participant R as kustomize build kubernetes/overlays/hostinger
  participant D as Deployment catalog-api renderizado
  participant BR2 as Navegador

  OP2->>R: render sin reemplazar REPLACE_BASE_DOMAIN
  R-->>D: BROWSER_ORIGINS=https://market.REPLACE_BASE_DOMAIN (marcador visible)
  BR2->>D: Origin https://market.dominio-real
  D-->>BR2: origen no coincide, no autorizado
  Note over OP2,D: La corrección es sustituir el dominio base una sola vez:<br/>el Ingress y BROWSER_ORIGINS comparten el marcador. No se inventa un valor ni se agrega un comodín.
```

## Valores por entorno

| Entorno | Archivo del patch | `BROWSER_ORIGINS` | Secreto |
|---|---|---|---|
| Minikube | `kubernetes/overlays/minikube/patches/catalog-api/env-patch.yaml` | `https://market.friendly-e-shop.duckdns.org` | No |
| Hostinger | `kubernetes/overlays/hostinger/catalog-api-env-patch.yaml` | `https://market.REPLACE_BASE_DOMAIN` | No |

Ambos valores son orígenes completos: esquema `https`, sin ruta, sin barra final, sin comodines y
sin un segundo origen. `catalog-api` no recibe el origen del panel en este corte.
