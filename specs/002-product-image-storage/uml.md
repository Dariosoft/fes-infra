# UML 002 — Almacenamiento de imágenes de producto en MinIO y cableado

Diagramas del despliegue **as-built** descrito por `plan.md` y `tasks.md` para `infra`: aprovisionamiento idempotente del bucket y las credenciales dedicadas, MinIO sobre PVC con respaldo/restauración automatizados, cableado S3 de catalog-api / panel-api, depuración local JDWP en Minikube y convenciones de estructura de scripts y parches.

Los diagramas muestran relaciones operativas relevantes del despliegue y omiten dependencias transitivas o detalles repetidos cuando ya están explicados por un recurso dueño, overlay o manifiesto principal.

## Estructura — scripts y parches (convenciones)

```mermaid
flowchart TB
  subgraph scripts["scripts/ (por responsabilidad + lib compartida)"]
    LIB["lib/\ncommon.sh · kube.sh · minio.sh"]
    SETUP["setup/bootstrap.sh"]
    CLUSTER["cluster/\ncreate · start · stop · destroy · tunnel · mount · tls"]
    BUILD["build/images.sh"]
    DEPLOY["deploy/deploy.sh"]
    RUNTIME["runtime/java-dev-reload.sh (#!/bin/sh, dentro del contenedor)"]
    STORAGE["storage/\nensure-bucket · backup-images · restore-images"]
    DBS["databases/backup.sh · restore.sh"]
    SECRETS["secrets/encrypt.sh · load-google-oauth.sh"]
    CHECKS["checks/doctor · validate · smoke-test · status"]
    TOOLS["tools/observability.sh"]
  end
  MAKEFILE["Makefile\ntargets delegan en scripts (sin lógica multilínea)"]
  MAKEFILE --> CLUSTER
  MAKEFILE --> SETUP
  MAKEFILE --> DEPLOY
  MAKEFILE --> STORAGE
  MAKEFILE --> DBS
  MAKEFILE --> CHECKS
  MAKEFILE --> TOOLS
  LIB -.->|source| CLUSTER
  LIB -.->|source| DEPLOY
  LIB -.->|source| STORAGE

  subgraph patches["kubernetes/overlays/minikube/patches/"]
    SHARED["shared/\napps-namespace.yaml · otel-config-patch.yaml"]
    PERPROJ["<proyecto>/\naccount-api · catalog-api · order-api · payment-api · panel-api · client-web · panel-web\n(env-patch · debug · image-pull · live según aplique)"]
  end
```

La skill `k8s-custom-good-practices` documenta estas reglas. No existe la carpeta `patches/live/`: los parches de recarga local viven dentro de la carpeta de su proyecto.

## Secuencia — `make deploy` aprovisiona el bucket y las credenciales

```mermaid
sequenceDiagram
  actor OP as Operador
  participant D as scripts/deploy/deploy.sh
  participant M as scripts/cluster/mount.sh
  participant K as kubectl (overlay minikube)
  participant S as scripts/storage/ensure-bucket.sh
  participant PS as platform-secrets
  participant AS as app-secrets
  participant MO as MinIO (platform, PVC)

  OP->>D: make deploy
  D->>M: montar workspace → /friendly-e-shop
  D->>K: apply kustomize minikube
  K-->>D: minio sobre PVC + env S3 + PUBLIC_API_BASE_URL + JAVA_DEBUG_OPTS
  D->>D: rollout status statefulset/minio
  D->>S: ejecutar aprovisionamiento
  S->>PS: leer minio-root-user / minio-root-password (minio_forward)
  S->>MO: mc mb --ignore-existing product-images
  S->>MO: recrear policy product-images-rw
  S->>AS: leer product-images-access-key / product-images-secret-key
  S->>MO: mc admin user add + policy attach
  S-->>D: bucket y usuario dedicado listos
  D->>D: restore faltantes (storage/restore-images.sh, RESTORE_OVERWRITE=0)
  D->>K: rollout status deployment/catalog-api
```

Nota: MinIO conserva su `volumeClaimTemplates` (PVC) en Minikube y Hostinger; el overlay Minikube **no** parchea el volumen a `hostPath`. La librería `scripts/lib/minio.sh` abre el port-forward con credenciales raíz solo para administración, nunca dentro de la aplicación. Si las claves dedicadas no existen en `app-secrets`, no inventa valores.

## Secuencia — respaldo y restauración automatizados (Minikube)

```mermaid
sequenceDiagram
  actor OP as Operador
  participant D as scripts/cluster/destroy.sh
  participant B as scripts/storage/backup-images.sh
  participant DP as scripts/deploy/deploy.sh
  participant R as scripts/storage/restore-images.sh
  participant MO as MinIO (bucket product-images)
  participant FS as carpeta local media/images

  OP->>D: make destroy
  D->>B: backup best-effort (si el perfil está Running)
  B->>MO: minio_forward + mc mirror bucket → carpeta
  D->>D: minikube delete
  OP->>DP: make deploy (tras make minikube-create)
  DP->>R: RESTORE_OVERWRITE=0 (si existe la carpeta)
  R->>MO: minio_forward + mc mb --ignore-existing
  R->>MO: mc mirror carpeta → bucket (solo faltantes)
```

## Estructura — base compartida y overlays

```mermaid
flowchart TB
  subgraph base["kubernetes/base (compartido Minikube + Hostinger)"]
    BMIN["platform/minio.yaml\nStatefulSet minio + PVC (volumeClaimTemplates)"]
    BNP["platform/network-policies.yaml\nplatform-ingress: apps → 9000"]
    BCAT["catalog-api/deployment.yaml\nS3_ENDPOINT, S3_BUCKET\nS3_ACCESS_KEY, S3_SECRET_KEY"]
    BPAN["panel-api/deployment.yaml\nConfigMap panel-api-config\nCATALOG_API_BASE_URL"]
  end

  subgraph mk["kubernetes/overlays/minikube"]
    MKRES["resources/secrets.yaml\napp-secrets + product-images-* (dev)"]
    MKENV["patches/catalog-api/env-patch.yaml\nPUBLIC_API_BASE_URL"]
    MKDBG["patches/<proyecto>/debug.yaml\nJAVA_DEBUG_OPTS 5005-5008"]
    MKREL["configMapGenerator java-dev-reload\nscripts/runtime/java-dev-reload.sh"]
    MKDEPLOY["scripts/deploy/deploy.sh\ninvoca el aprovisionamiento"]
    MKSCRIPT["scripts/storage/ensure-bucket.sh"]
  end

  subgraph hs["kubernetes/overlays/hostinger"]
    HSPH["secrets.placeholder.yaml\nproduct-images-* = REPLACE_ME"]
    HSENC["secrets.enc.yaml (SOPS) — despliegue real"]
  end

  BMIN -.->|PVC heredado, sin hostPath| MKRES
  BMIN -.->|PVC heredado, sin hostPath| HSPH
  BCAT -.->|secretKeyRef app-secrets| MKRES
  BCAT -.->|secretKeyRef app-secrets| HSPH
  BCAT -.->|env patch por entorno| MKENV
  BCAT -.->|debug patch solo Minikube| MKDBG
  MKDBG --> MKREL
  MKDEPLOY --> MKSCRIPT
  MKSCRIPT --> BMIN
  HSPH -->|scripts/secrets/encrypt.sh| HSENC
```

## Entorno Minikube — datos y respaldo

```mermaid
flowchart LR
  CAT["catalog-api\nS3_ENDPOINT / S3_BUCKET / S3_ACCESS_KEY / S3_SECRET_KEY\nPUBLIC_API_BASE_URL = api.friendly-e-shop.duckdns.org"]
  MINIO["MinIO (platform)\nPVC local del nodo\n(datos vivos)"]
  BACKUP["Carpeta host macOS\n/Users/dariogutierrez/projects/friendly-e-shop/media/images\n(respaldo automático en destroy / restore en deploy)"]
  ROOT["platform-secrets\nminio-root-*"]
  AS["app-secrets (dev)\nproduct-images-*"]

  CAT -->|S3 sobre :9000| MINIO
  CAT -.->|secretKeyRef| AS
  BACKUP <-->|"make backup-images / make restore-images\nmc mirror (minio_forward), port-forward 19000"| MINIO
  ROOT -.->|mc admin vía port-forward| MINIO
```

MinIO no puede usar el `hostPath` del workspace como backend vivo: `minikube mount` lo expone como `9p` y el backend erasure de MinIO falla con `Rename across devices not allowed`. Por eso el PVC es el almacenamiento vivo y la carpeta local es solo destino de copia.

## Entorno Hostinger — datos

```mermaid
flowchart LR
  CAT["catalog-api\nS3_ENDPOINT / S3_BUCKET / S3_ACCESS_KEY / S3_SECRET_KEY\nPUBLIC_API_BASE_URL = api.REPLACE_BASE_DOMAIN"]
  MINIO["MinIO (platform)\nPVC local-path K3s\n(datos vivos)"]
  AS["app-secrets (SOPS)\nproduct-images-access-key/secret-key"]

  CAT -->|S3 sobre :9000| MINIO
  CAT -.->|secretKeyRef| AS
```

Hostinger no usa la carpeta local de macOS ni los overlays de debug: las imágenes permanecen en el PVC y las credenciales dedicadas llegan por el secret cifrado.

## Depuración local JDWP (solo Minikube)

```mermaid
flowchart LR
  DEV["Desarrollador\nVS Code"] -->|attach 5005-5008| PF["port-forward temporal\n(abierto por el IDE)"]
  PF --> POD["Pod API Java (minikube)\nJDWP en 127.0.0.1:500x"]
  RELOAD["scripts/runtime/java-dev-reload.sh\nJAVA_DEBUG_OPTS en jvmArguments"] -->|arranque/recarga| POD
  DBGP["patches/<proyecto>/debug.yaml\ncatalog/account/order/payment-api"] -->|JAVA_DEBUG_OPTS| POD
```

El overlay Hostinger no incluye los patches `*/debug.yaml`, así que el depurador queda deshabilitado. El agente escucha en `127.0.0.1` dentro del pod y solo se alcanza por port-forward.

## Flujo de la política dedicada en MinIO

```mermaid
flowchart LR
  ROOT["MinIO root\nplatform-secrets"]
  BUCKET["Bucket product-images"]
  POLICY["Política product-images-rw\n- ListBucket / GetBucketLocation\n- PutObject / GetObject / DeleteObject"]
  USER["Usuario dedicado\ncatalog-images (access key)"]
  APP["catalog-api\nS3_ACCESS_KEY / S3_SECRET_KEY"]

  ROOT -->|mc mb --ignore-existing| BUCKET
  ROOT -->|mc admin policy create| POLICY
  POLICY -->|mc admin policy attach| USER
  BUCKET --- POLICY
  USER -->|S3_ACCESS_KEY / S3_SECRET_KEY| APP
  APP -->|solo product-images| BUCKET
```

## Rutas de archivos

| Recurso | Ruta |
|---|---|
| Volumen MinIO (base, PVC) | `kubernetes/base/platform/minio.yaml` |
| NetworkPolicy | `kubernetes/base/platform/network-policies.yaml` |
| Env S3 catalog-api | `kubernetes/base/catalog-api/deployment.yaml` |
| ConfigMap panel-api | `kubernetes/base/panel-api/deployment.yaml` |
| URL pública por entorno | `kubernetes/overlays/minikube/patches/catalog-api/env-patch.yaml`, `kubernetes/overlays/hostinger/catalog-api-env-patch.yaml` |
| Parche transversal de namespace | `kubernetes/overlays/minikube/patches/shared/apps-namespace.yaml` |
| Depuración JDWP (Minikube) | `kubernetes/overlays/minikube/patches/{catalog-api,account-api,order-api,payment-api}/debug.yaml` |
| Recarga Java + `JAVA_DEBUG_OPTS` | `scripts/runtime/java-dev-reload.sh` |
| Secretos Minikube | `kubernetes/overlays/minikube/resources/secrets.yaml` |
| Secretos Hostinger | `kubernetes/overlays/hostinger/secrets.placeholder.yaml` → `secrets.enc.yaml` |
| Aprovisionamiento idempotente | `scripts/storage/ensure-bucket.sh` |
| Respaldo / restauración | `scripts/storage/backup-images.sh`, `scripts/storage/restore-images.sh` |
| Invocación en deploy / destroy | `scripts/deploy/deploy.sh`, `scripts/cluster/destroy.sh` |
| Librería compartida | `scripts/lib/common.sh`, `scripts/lib/kube.sh`, `scripts/lib/minio.sh` |
| Documentación manual | `docs/product-images.md` (y `README.md` para debugging), `scripts/README.md` |

No hay cambios de Terraform en este corte: PVC y secretos viven en Kustomize. Si un cambio futuro lo requiriera, se respetarían `/terraform-style-guide` y `/terraform-module-library`.
