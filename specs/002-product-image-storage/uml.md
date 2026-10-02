# UML 002 — Almacenamiento de imágenes de producto en MinIO y cableado

Diagramas del despliegue descrito por `plan.md` y `tasks.md` para `infra`: aprovisionamiento idempotente del bucket y las credenciales dedicadas, respaldo local del volumen de MinIO en Minikube y cableado S3 de catalog-api / panel-api.

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
  participant MO as MinIO (platform)

  OP->>D: make deploy
  D->>M: montar workspace → /friendly-e-shop
  M-->>D: /friendly-e-shop/media/images disponible
  D->>K: apply kustomize minikube
  K-->>D: minio con hostPath + env S3 de catalog-api
  D->>D: rollout status statefulset/minio
  D->>S: ejecutar aprovisionamiento
  S->>PS: leer minio-root-user / minio-root-password
  S->>MO: port-forward 19001 + mc alias set
  S->>MO: mc mb --ignore-existing product-images
  S->>MO: mc admin policy create product-images-rw
  S->>AS: leer product-images-access-key / product-images-secret-key
  S->>MO: mc admin user add + policy attach product-images-rw
  S-->>D: bucket y usuario dedicado listos
  D->>K: rollout status deployment/catalog-api
```

Nota: el script usa las credenciales raíz solo para administración vía port-forward, nunca dentro de la aplicación. Si las claves dedicadas no existen en `app-secrets`, no inventa valores.

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
    MKPATCH["patch JSON6902 minio\nalt: hostPath /friendly-e-shop/media/images"]
    MKSCRIPT["scripts/ensure-product-images-bucket.sh"]
    MKDEPLOY["scripts/deploy.sh\ninvoca el aprovisionamiento"]
  end

  subgraph hs["kubernetes/overlays/hostinger"]
    HSPH["secrets.placeholder.yaml\nproduct-images-* = REPLACE_ME"]
    HSENC["secrets.enc.yaml (SOPS) — despliegue real"]
  end

  BMIN -.->|overlay Minikube reemplaza volumen| MKPATCH
  BCAT -.->|secretKeyRef app-secrets| MKRES
  BCAT -.->|secretKeyRef app-secrets| HSPH
  MKDEPLOY --> MKSCRIPT
  MKSCRIPT --> BMIN
  HSPH -->|scripts/encrypt-secrets.sh| HSENC
```

## Datos — respaldo del volumen de MinIO por entorno

```mermaid
flowchart LR
  subgraph minikube["Minikube (hostPath)"]
    HOST["Host macOS\n/Users/dariogutierrez/projects/friendly-e-shop/media/images"]
    NODE["Nodo Minikube\n/friendly-e-shop/media/images"]
    MVOL["StatefulSet minio\nvolumen data (hostPath DirectoryOrCreate)"]
    HOST -->|ensure-minikube-mount.sh\nworkspace → /friendly-e-shop| NODE --> MVOL
  end

  subgraph hostinger["Hostinger (PVC)"]
    PVPVC["volumeClaimTemplates → PVC\nstorage local-path K3s"]
    HENV["app-secrets (SOPS)\nproduct-images-access-key/secret-key"]
  end

  CAT["catalog-api\nS3_ENDPOINT / S3_BUCKET / S3_ACCESS_KEY / S3_SECRET_KEY"]
  VLAN["panel-api\nCATALOG_API_BASE_URL"]

  CAT -->|S3 sobre :9000| MVOL
  CAT -->|S3 sobre :9000| PVPVC
  CAT -.->|credenciales dedicadas| HENV
  VLAN -->|HTTP interna| CAT
```

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
| Volumen MinIO (base) | `kubernetes/base/platform/minio.yaml` |
| NetworkPolicy | `kubernetes/base/platform/network-policies.yaml` |
| Env S3 catalog-api | `kubernetes/base/catalog-api/deployment.yaml` |
| ConfigMap panel-api | `kubernetes/base/panel-api/deployment.yaml` |
| Patch hostPath Minio (Minikube) | `kubernetes/overlays/minikube/kustomization.yaml` |
| Secretos Minikube | `kubernetes/overlays/minikube/resources/secrets.yaml` |
| Secretos Hostinger | `kubernetes/overlays/hostinger/secrets.placeholder.yaml` → `secrets.enc.yaml` |
| Aprovisionamiento idempotente | `scripts/ensure-product-images-bucket.sh` |
| Invocación | `scripts/deploy.sh` |
| Documentación manual | `docs/product-images.md` |

No hay cambios de Terraform en este corte: PVC y secretos viven en Kustomize. Si un cambio futuro lo requiriera, se respetarían `/terraform-style-guide` y `/terraform-module-library`.
