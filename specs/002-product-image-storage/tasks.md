# Tareas 002 — Almacenamiento de imágenes de producto en MinIO y cableado

Ordenadas por dependencia. Cada tarea ~20–30 min. No implementar lógica de imágenes en las aplicaciones ni tocar Terraform.

## Aprovisionamiento del bucket y la política

- [x] **T1. Crear el script idempotente del bucket y las credenciales dedicadas**
  - Cubierta: RF-1, RF-2, RF-7, RF-8, RF-9, RF-13
  - Crear `scripts/ensure-product-images-bucket.sh` (`set -euo pipefail`) siguiendo `scripts/backup.sh`: port-forward a `service/minio` en `platform` (puerto `MINIO_FORWARD_PORT:-19001`), `mc alias set` con `minio-root-user`/`minio-root-password` de `platform-secrets`, `mc mb --ignore-existing friendly/product-images`, y `trap` de limpieza del forward.
  - Done when: ejecutar el script crea el bucket sin fallar y repetirlo no duplica ni falla.

- [x] **T2. Definir la política de mínimo privilegio y el usuario dedicado**
  - Cubierta: RF-7, RF-8, RF-9, RF-13
  - En el mismo script, crear/actualizar la política `product-images-rw` limitada a `arn:aws:s3:::product-images` (ListBucket/GetBucketLocation) y `arn:aws:s3:::product-images/*` (PutObject/GetObject/DeleteObject); leer `product-images-access-key`/`product-images-secret-key` de `app-secrets`, crear el usuario de MinIO sólo si no existe (`mc admin user info`/`mc admin user add`) y `mc admin policy attach … --user`. Si faltan las claves, avisar y no inventar valores.
  - Done when: el usuario dedicado sólo tiene `product-images-rw` y no aparece ninguna credencial raíz en la app ni en el script como valor fijo.

## Respaldo local de las imágenes en Minikube

- [x] **T3. Mantener MinIO sobre su PVC (sin hostPath)**
  - Cubierta: RF-2, RF-3, RF-4
  - No parchear el volumen del StatefulSet `minio` en el overlay Minikube: conserva `volumeClaimTemplates` (PVC) como la base, porque `minikube mount` expone un sistema `9p` y MinIO no puede usar esa ruta como backend vivo (`FATAL ... Rename across devices not allowed`). La carpeta local pasa a ser destino de respaldo, no almacenamiento vivo.
  - Done when: `kustomize build kubernetes/overlays/minikube` no introduce `hostPath` en `minio` y conserva el PVC.

- [x] **T4. Crear los scripts de respaldo y restauración a demanda**
  - Cubierta: RF-3, RF-4, RF-14, RF-17
  - Crear `scripts/backup-images.sh` y `scripts/restore-images.sh` (`mc mirror`) siguiendo `scripts/backup.sh`, con `PRODUCT_IMAGES_DIR` (por defecto `/Users/dariogutierrez/projects/friendly-e-shop/media/images`) y `PRODUCT_IMAGES_BUCKET` (por defecto `product-images`). El respaldo crea la carpeta si no existe.
  - Done when: `make backup-images` copia el bucket a la carpeta local creándola si falta y `make restore-images` lo devuelve al bucket.

- [x] **T5. Invocar el aprovisionamiento en el despliegue Minikube**
  - Cubierta: RF-2, RF-14
  - En `scripts/deploy.sh`, tras `rollout status statefulset/minio` y antes de esperar las apps, invocar `"$ROOT/scripts/ensure-product-images-bucket.sh"`.
  - Done when: `make deploy` crea/verifica el bucket de forma automática y repetir el deploy no falla.

## Secretos

- [x] **T6. Declarar credenciales de desarrollo en el secreto Minikube**
  - Cubierta: RF-7, RF-8, RF-9
  - En `kubernetes/overlays/minikube/resources/secrets.yaml`, dentro de `app-secrets`, añadir `product-images-access-key: catalog-images` y `product-images-secret-key: catalog-images-local` (valores solo de laboratorio, alineados con el script de T1/T2 y con `docs/secrets.md`).
  - Done when: `app-secrets` de Minikube contiene ambas claves y no reutiliza `minio-root-*`.

- [x] **T7. Declarar placeholders en el secreto de Hostinger**
  - Cubierta: RF-13, RF-15
  - En `kubernetes/overlays/hostinger/secrets.placeholder.yaml`, dentro de `app-secrets`, añadir `product-images-access-key` y `product-images-secret-key` con valor `REPLACE_ME`; no commitear credenciales reales.
  - Done when: el placeholder Hostinger tiene ambas claves como `REPLACE_ME` y el árbol versionado no contiene credenciales de imágenes en claro.

## Cableado de catalog-api y panel-api

- [x] **T8. Inyectar `S3_ENDPOINT` y `S3_BUCKET` en catalog-api**
  - Cubierta: RF-5, RF-6
  - En `kubernetes/base/catalog-api/deployment.yaml`, añadir env `S3_ENDPOINT=http://minio.platform.svc.cluster.local:9000` y `S3_BUCKET=product-images` (valores no secretos inline, como el resto de la config).
  - Done when: el Deployment base entrega ambos valores y ambos overlays los heredan.

- [x] **T9. Inyectar `S3_ACCESS_KEY` y `S3_SECRET_KEY` desde `app-secrets`**
  - Cubierta: RF-7, RF-8
  - En el mismo Deployment de la base, añadir `S3_ACCESS_KEY` ← `secretKeyRef` `app-secrets`/`product-images-access-key` y `S3_SECRET_KEY` ← `secretKeyRef` `app-secrets`/`product-images-secret-key`, sin valores por defecto ni literales.
  - Done when: el pod `catalog-api` recibe ambas variables desde el secreto y no hay credenciales hardcodeadas.

- [x] **T10. Entregar `CATALOG_API_BASE_URL` a panel-api**
  - Cubierta: RF-10
  - En el ConfigMap `panel-api-config` de `kubernetes/base/panel-api/deployment.yaml`, añadir `CATALOG_API_BASE_URL: http://catalog-api.apps.svc.cluster.local:8080` (mismo valor en Minikube y Hostinger; no usar `api.*` público).
  - Done when: el build de ambos overlays incluye esa URL interna en la configuración de `panel-api`.

- [x] **T16. Entregar `PUBLIC_API_BASE_URL` a catalog-api**
  - Cubierta: RF-16
  - Crear `kubernetes/overlays/minikube/patches/catalog-api-env-patch.yaml` (`https://api.friendly-e-shop.duckdns.org`) y `kubernetes/overlays/hostinger/catalog-api-env-patch.yaml` (`https://api.REPLACE_BASE_DOMAIN`), y referenciarlos en el `kustomization.yaml` de cada overlay (patrón de `account-api-env-patch.yaml`).
  - Done when: el pod `catalog-api` recibe `PUBLIC_API_BASE_URL` por entorno y arranca con el binding de propiedades de configuración registrado.

## NetworkPolicy y documentación

- [x] **T11. Verificar la NetworkPolicy `platform-ingress`**
  - Cubierta: RF-11
  - Confirmar en `kubernetes/base/platform/network-policies.yaml` que la regla del puerto 9000 desde `apps` sigue presente y que los pods de `apps` alcanzan `minio.platform.svc.cluster.local:9000`; no modificar la política.
  - Done when: los dos overlays conservan la regla del puerto 9000 y la conectividad funciona desde un pod de `apps`.

- [x] **T12. Escribir `docs/product-images.md`**
  - Cubierta: RF-12, RF-13, RF-17
  - Documentar: carpeta local Minikube y comandos `make backup-images`/`make restore-images`; volumen PVC (Minikube y Hostinger) y por qué no `hostPath`; bucket `product-images` y política `product-images-rw`; script idempotente y procedimiento manual `mc` para Hostinger; credenciales dedicadas y SOPS; variables S3 y `PUBLIC_API_BASE_URL` de catalog-api y `CATALOG_API_BASE_URL` de panel-api; qué hacer si faltan bucket o credenciales (no inventar valores).
  - Done when: `docs/product-images.md` permite reproducir la configuración manual sin adivinar valores y enlaza con `docs/secrets.md` y `docs/hostinger.md`.

## Depuración local

- [x] **T17. Añadir los overlays de debug JDWP en Minikube**
  - Cubierta: RF-18, RF-19, RF-20, RF-21
  - Crear `kubernetes/overlays/minikube/patches/catalog-api-debug.yaml`, `account-api-debug.yaml`, `order-api-debug.yaml` y `payment-api-debug.yaml` con `JAVA_DEBUG_OPTS=-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=127.0.0.1:<puerto>` (5005–5008) y referenciarlos en el `kustomization.yaml` de Minikube; el overlay Hostinger no los incluye.
  - Done when: el pod de cada API Java en Minikube recibe su `JAVA_DEBUG_OPTS` y Hostinger no define la variable.

- [x] **T18. Honrar `JAVA_DEBUG_OPTS` en `scripts/java-dev-reload.sh`**
  - Cubierta: RF-22, RF-23
  - Añadir a los argumentos de la JVM (`-Dspring-boot.run.jvmArguments`) el valor de `JAVA_DEBUG_OPTS` solo cuando no esté vacío; sin la variable, el arranque no expone JDWP.
  - Done when: con `JAVA_DEBUG_OPTS` definido el API abre el puerto JDWP y sin él arranca normal.

- [x] **T19. Documentar el debugging en `README.md`**
  - Cubierta: RF-24
  - Añadir la sección de depuración: perfiles de VS Code, puertos por API (`catalog-api` 5005, `account-api` 5006, `order-api` 5007, `payment-api` 5008) y el port-forward temporal que abre el IDE.
  - Done when: `README.md` permite adjuntar VS Code a los APIs sin adivinar puertos.

## Validación

- [x] **T13. Validar manifiestos con `make validate`**
  - Cubierta: RF-1 … RF-24 (integridad de manifiestos)
  - Ejecutar `make validate` (Kustomize Minikube + Hostinger, kubeconform estricto) tras los cambios y comprobar que no se añadieron credenciales descifradas al árbol.
  - Done when: `make validate` termina en verde.

- [x] **T15. Añadir los targets `backup-images` / `restore-images` al Makefile**
  - Cubierta: RF-17
  - Añadir ambos targets a `.PHONY` y sus recetas en `Makefile`, invocando los scripts de T4.
  - Done when: `make backup-images` y `make restore-images` ejecutan los scripts correspondientes.

- [x] **T14. Verificar el aprovisionamiento local end-to-end (si Minikube está disponible)**
  - Cubierta: RF-1, RF-2, RF-3, RF-4, RF-7, RF-8, RF-9, RF-14
  - Con Minikube arriba: comprobar que `mc ls friendly/product-images` funciona, inspeccionar el env `S3_*` y `PUBLIC_API_BASE_URL` del pod `catalog-api`, subir un objeto de prueba y confirmar que `make backup-images` lo copia a la carpeta local; recrear el clúster y confirmar que `make restore-images` lo devuelve al bucket.
  - Done when: bucket, credenciales, env, endpoint y respaldo/restauración quedan comprobados; si el clúster no está disponible, dejar constancia explícita y diferir solo esta verificación operativa.
  - Nota: bucket, política, usuario, env y endpoint se verificaron en el clúster local; `make backup-images`/`make restore-images` quedan implementados y documentados como respaldo a demanda.

- [x] **T20. Automatizar el respaldo al destruir y la restauración al recrear**
  - Cubierta: RF-25, RF-26
  - `make destroy` intenta `scripts/backup-images.sh` (best-effort: solo si el perfil está `Running`) antes de `minikube delete`. `scripts/deploy.sh` restaura los objetos faltantes desde la carpeta local tras `ensure-product-images-bucket.sh` con `RESTORE_OVERWRITE=0` (no sobrescribe existentes). `scripts/restore-images.sh` respeta `RESTORE_OVERWRITE`.
  - Done when: `make destroy` respalda sin bloquear el borrado y `make deploy` restaura solo lo faltante cuando la carpeta local existe.

## Mapa RF → tareas

| RF | Tareas |
|----|--------|
| RF-1 | T1, T5, T14 |
| RF-2 | T1, T5, T14 |
| RF-3 | T3, T4, T14 |
| RF-4 | T3, T4, T14 |
| RF-5 | T8 |
| RF-6 | T8 |
| RF-7 | T2, T6, T9, T14 |
| RF-8 | T2, T6, T9, T14 |
| RF-9 | T2, T6, T14 |
| RF-10 | T10 |
| RF-11 | T11 |
| RF-12 | T12 |
| RF-13 | T2, T7, T12 |
| RF-14 | T4, T5, T14 |
| RF-15 | T7, T12 |
| RF-16 | T16 |
| RF-17 | T4, T15, T12 |
| RF-18 | T17 |
| RF-19 | T17 |
| RF-20 | T17 |
| RF-21 | T17 |
| RF-22 | T18 |
| RF-23 | T18 |
| RF-24 | T19 |
| RF-25 | T20 |
| RF-26 | T20 |
| Todos (validación) | T13 |
