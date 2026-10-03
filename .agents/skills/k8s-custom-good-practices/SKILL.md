---
name: k8s-custom-good-practices
description: Convenciones propias de infra para el Makefile, los scripts y los parches de Kustomize de Minikube. Úsala al agregar o editar targets del Makefile, scripts bajo scripts/ o parches de Minikube.
---

# K8s custom good practices

1. **Makefile delega en `scripts/`.** Cada target del `Makefile` llama a un script dentro de `scripts/` cuando la acción requiere más de una línea. El Makefile no contiene lógica multilínea inline.
2. **Scripts por responsabilidad y con librería común.** Bajo `scripts/` se agrupa por dominio: `lib/`, `setup/`, `cluster/`, `build/`, `deploy/`, `runtime/`, `storage/`, `databases/`, `secrets/`, `checks/`, `tools/`. Nombres representativos. El código compartido vive en `scripts/lib/` y se reutiliza con `source` (no se repite boilerplate): `common.sh` (`set -euo pipefail`, `INFRA_ROOT`/`WORKSPACE`/`PROFILE`, `log_*`, `require_cmd`), `minio.sh` (`minio_forward`/`minio_stop`/`MINIO_BUCKET`) y `kube.sh` (`k`/`wait_rollout`).
3. **Parches de Minikube por proyecto.** Los parches de `kubernetes/overlays/minikube/patches/` van en una carpeta por proyecto: `account-api/`, `catalog-api/`, `order-api/`, `payment-api/`, `panel-api/`, `client-web/`, `panel-web/`. Los parches transversales (namespace, telemetría, etc.) van en `shared/`. No existe la carpeta `live/`: los parches de recarga local viven dentro de la carpeta de su proyecto.
