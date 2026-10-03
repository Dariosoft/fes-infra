# UML 002 — Almacenamiento de imágenes de producto en MinIO y cableado

Diagramas del despliegue **as-built** descrito por `plan.md` y `tasks.md` para `infra`: aprovisionamiento idempotente del bucket y las credenciales dedicadas, MinIO sobre PVC con respaldo/restauración a demanda, cableado S3 de catalog-api / panel-api y depuración local JDWP en Minikube.

Los diagramas muestran relaciones operativas relevantes del despliegue y omiten dependencias transitivas o detalles repetidos cuando ya están explicados por un recurso dueño, overlay o manifiesto principal.

## Secuencia — `make deploy` aprovisiona el bucket y las credenciales

```mermaid
sequenceDiagram
  actor OP as Operador
  participant D as scripts/deploy.sh
  participant M as scripts/ensure-minikube-mount.sh
  participant K as kubectl (overlay minikube)
  participant S as scripts/ensure-product-images-bucket.sh
  participant PS as platform-secrets
  participant AS as app-secrets
  participant MO as MinIO (platform, PVC)

  OP->>D: make deploy
  D->>M: montar workspace → /friendly-e-shop
  D->>K: apply kustomize minikube
  K-->>D: minio sobre PVC + env S3 + PUBLIC_API_BASE_URL + JAVA_DEBUG_OPTS
  D->>D: rollout status statefulset/minio
  D->>S: ejecutar aprovisionamiento
  S->>PS: leer minio-root-user / minio-root-password
  S->>MO: port-forward 19001 + mc alias set
  S->>MO: mc mb --ignore-existing product-images
  S->>MO: recrear policy product-images-rw
  S->>AS: leer product-images-access-key / product-images-secret-key
  S->>MO: mc admin user add + policy attach
  S-->>D: bucket y usuario dedicado listos
  D->>K: rollout status deployment/catalog-api
```

Nota: MinIO conserva su `volumeClaimTemplates` (PVC) en Minikube y Hostinger; el overlay Minikube **no** parchea el volumen a `hostPath`. El script usa las credenciales raíz solo para administración vía port-forward, nunca dentro de la aplicación. Si las claves dedicadas no existen en `app-secrets`, no inventa valores.

## Secuencia — respaldo y restauración a demanda (Minikube)

```mermaid
sequenceDiagram
  actor OP as Operador
  participant B as scripts/backup-images.sh
  participant R as scripts/restore-images.sh
  participant PS as platform-secrets
  participant MO as MinIO (bucket product-images)
  participant FS as carpeta local media/images

  OP->>B: make backup-images
  B->>PS: leer credenciales raíz (administración)
  B->>FS: mkdir -p media/images
  B->>MO: port-forward 19000 + mc alias set
  B->>FS: mc mirror friendly/product-images → carpeta
  OP->>R: make restore-images
  R->>PS: leer credenciales raíz (administración)
  R->>MO: port-forward 19000 + mc mb --ignore-existing
  R->>MO: mc mirror carpeta → friendly/product-images
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
    MKENV["patches/catalog-api-env-patch.yaml\nPUBLIC_API_BASE_URL"]
    MKDBG["patches/*-debug.yaml\nJAVA_DEBUG_OPTS 5005-5008"]
    MKREL["configMapGenerator java-dev-reload\nscripts/java-dev-reload.sh"]
    MKDEPLOY["scripts/deploy.sh\ninvoca el aprovisionamiento"]
    MKSCRIPT["scripts/ensure-product-images-bucket.sh"]
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
  HSPH -->|scripts/encrypt-secrets.sh| HSENC
```

## Entorno Minikube — datos y respaldo

```mermaid
flowchart LR
  CAT["catalog-api\nS3_ENDPOINT / S3_BUCKET / S3_ACCESS_KEY / S3_SECRET_KEY\nPUBLIC_API_BASE_URL = api.friendly-e-shop.duckdns.org"]
  MINIO["MinIO (platform)\nPVC local del nodo\n(datos vivos)"]
  BACKUP["Carpeta host macOS\n/Users/dariogutierrez/projects/friendly-e-shop/media/images\n(respaldo a demanda)"]
  ROOT["platform-secrets\nminio-root-*"]
  AS["app-secrets (dev)\nproduct-images-*"]

  CAT -->|S3 sobre :9000| MINIO
  CAT -.->|secretKeyRef| AS
  BACKUP <-->|"make backup-images / make restore-images\nmc mirror, port-forward 19000"| MINIO
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
  RELOAD["scripts/java-dev-reload.sh\nJAVA_DEBUG_OPTS en jvmArguments"] -->|arranque/recarga| POD
  DBGP["patches/catalog-api-debug.yaml\naccount/order/payment-api-debug.yaml"] -->|JAVA_DEBUG_OPTS| POD
```

El overlay Hostinger no incluye los patches `*-debug.yaml`, así que el depurador queda deshabilitado. El agente escucha en `127.0.0.1` dentro del pod y solo se alcanza por port-forward.

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
| URL pública por entorno | `kubernetes/overlays/minikube/patches/catalog-api-env-patch.yaml`, `kubernetes/overlays/hostinger/catalog-api-env-patch.yaml` |
| Depuración JDWP (Minikube) | `kubernetes/overlays/minikube/patches/{catalog,account,order,payment}-api-debug.yaml` |
| Recarga Java + `JAVA_DEBUG_OPTS` | `scripts/java-dev-reload.sh` |
| Secretos Minikube | `kubernetes/overlays/minikube/resources/secrets.yaml` |
| Secretos Hostinger | `kubernetes/overlays/hostinger/secrets.placeholder.yaml` → `secrets.enc.yaml` |
| Aprovisionamiento idempotente | `scripts/ensure-product-images-bucket.sh` |
| Respaldo / restauración | `scripts/backup-images.sh`, `scripts/restore-images.sh` |
| Invocación | `scripts/deploy.sh` |
| Documentación manual | `docs/product-images.md` (y `README.md` para debugging) |

No hay cambios de Terraform en este corte: PVC y secretos viven en Kustomize. Si un cambio futuro lo requiriera, se respetarían `/terraform-style-guide` y `/terraform-module-library`.
