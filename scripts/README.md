# Scripts

Automatización de `fes-infra`, agrupada por responsabilidad. Cada script es invocado por el
`Makefile` o por otro script, y comparte utilidades desde `lib/`.

## Carpetas

| Carpeta | Propósito |
|---|---|
| `lib/` | Librería compartida (`common.sh`, `kube.sh`, `minio.sh`). No se ejecuta sola: se sourcea. |
| `setup/` | Preparación del entorno local. |
| `cluster/` | Ciclo de vida del clúster Minikube y sus accesos. |
| `build/` | Construcción de imágenes dentro de Minikube. |
| `deploy/` | Despliegue del overlay de Minikube. |
| `runtime/` | Scripts que corren dentro de los contenedores. |
| `storage/` | Bucket y respaldo/restauración de imágenes de producto. |
| `databases/` | Respaldo y restauración de PostgreSQL. |
| `secrets/` | Cifrado y carga de secretos. |
| `checks/` | Diagnóstico, validación y pruebas de humo. |
| `tools/` | Utilidades de operación puntuales. |

## Scripts

| Script | Propósito |
|---|---|
| `setup/bootstrap.sh` | Instala las CLIs locales con Homebrew (`brew bundle`). |
| `cluster/create.sh` | Crea el perfil de Minikube y habilita ingress + metrics-server. |
| `cluster/start.sh` | Arranca un perfil detenido y monta los checkouts locales. |
| `cluster/stop.sh` | Detiene el perfil, el montaje y el tunnel, conservando datos. |
| `cluster/destroy.sh` | Respalda las imágenes (best effort) y borra el perfil. |
| `cluster/tunnel.sh` | Port-forward del Ingress, PostgreSQL y MinIO. |
| `cluster/mount.sh` | Garantiza el montaje del workspace en el nodo. |
| `cluster/tls.sh` | Genera e instala el certificado TLS local. |
| `build/images.sh` | Construye las siete apps y MinIO dentro de Minikube. |
| `deploy/deploy.sh` | Monta, aplica el overlay de Minikube y espera los rollouts. |
| `runtime/java-dev-reload.sh` | Recarga Java dentro del contenedor (script montado, `#!/bin/sh`). |
| `storage/ensure-bucket.sh` | Crea el bucket, la política y el usuario de product-images. |
| `storage/backup-images.sh` | Espeja product-images de MinIO a la carpeta local. |
| `storage/restore-images.sh` | Espeja la carpeta local al bucket product-images. |
| `databases/backup.sh` | Respalda las bases PostgreSQL a MinIO. |
| `databases/restore.sh` | Restaura una base desde un objeto de MinIO. |
| `secrets/encrypt.sh` | Cifra los secretos de Hostinger con SOPS + age. |
| `secrets/load-google-oauth.sh` | Carga el cliente OAuth de Google en `app-secrets`. |
| `checks/doctor.sh` | Verifica herramientas y el daemon de Docker. |
| `checks/validate.sh` | Valida Kustomize y Terraform. |
| `checks/smoke-test.sh` | Prueba HTTP de las rutas públicas. |
| `checks/status.sh` | Muestra pods, Ingress y PVC. |
| `tools/observability.sh` | Port-forward de Grafana. |
