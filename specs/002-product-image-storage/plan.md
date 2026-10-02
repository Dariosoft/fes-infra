# Plan 002 — Almacenamiento de imágenes de producto en MinIO y cableado

## Resumen

Aprovisionar el bucket `product-images` en MinIO y cablearlo hasta catalog-api y panel-api. En Minikube el bucket se crea de forma idempotente con un script del repositorio y los objetos se respaldan en la ruta local del nodo `/friendly-e-shop/media/images`, reutilizando el montaje existente del workspace (`ensure-minikube-mount.sh`, workspace → `/friendly-e-shop`). En Hostinger se conserva el PVC de MinIO y las credenciales dedicadas viajan cifradas por SOPS. catalog-api recibe `S3_ENDPOINT`, `S3_BUCKET`, `S3_ACCESS_KEY` y `S3_SECRET_KEY` con credenciales dedicadas limitadas al bucket (no las raíz); panel-api recibe `CATALOG_API_BASE_URL`. La ruta, el bucket, la política y las credenciales se documentan manualmente en `docs/product-images.md`. No se implementa lógica de imágenes en las aplicaciones ni se toca Terraform.

## Estado de partida

- MinIO existe en la base: `kubernetes/base/platform/minio.yaml` (Service `minio` puerto `api/9000` y StatefulSet `minio` en `platform`, datos en `volumeClaimTemplates` → PVC).
- La NetworkPolicy `platform-ingress` (`kubernetes/base/platform/network-policies.yaml`) ya permite el puerto 9000 desde `apps` (RF-11 se verifica, no se modifica).
- `catalog-api` (`kubernetes/base/catalog-api/deployment.yaml`) no tiene hoy variables S3.
- `panel-api` (`kubernetes/base/panel-api/deployment.yaml`) ya expone el ConfigMap `panel-api-config` con `ACCOUNT_API_BASE_URL`; falta `CATALOG_API_BASE_URL`.
- Secretos por overlay: `app-secrets` en Minikube (`kubernetes/overlays/minikube/resources/secrets.yaml`) y placeholder Hostinger (`kubernetes/overlays/hostinger/secrets.placeholder.yaml`). `platform-secrets` ya tiene `minio-root-user` / `minio-root-password`.
- El montaje del workspace ya lo garantiza `scripts/ensure-minikube-mount.sh` en `/friendly-e-shop`; `scripts/deploy.sh` lo invoca antes de aplicar.
- No hay Terraform involucrado: MinIO, PVC y secretos viven en Kustomize.

## Alcance y límites

**En alcance (este repositorio `infra`):**
- Script idempotente de aprovisionamiento del bucket y de la política/credenciales dedicadas en Minikube.
- Patch del overlay Minikube para respaldar el volumen de datos de MinIO en la ruta local del nodo.
- Variables de entorno S3 de `catalog-api` en la base (endpoint y bucket no secretos; claves desde `app-secrets`).
- `CATALOG_API_BASE_URL` de `panel-api` en el ConfigMap de la base.
- Claves de credenciales dedicadas en `app-secrets` de Minikube y en el placeholder de Hostinger (SOPS).
- Documento operativo `docs/product-images.md`.
- Validación con `make validate` y verificación local con el script de bucket + `make smoke-test` si Minikube está disponible.

**Fuera de alcance (respeta la spec):**
- Lógica de subida/listado/borrado de imágenes dentro de catalog-api (repo propietario).
- Aprovisionar MinIO o cambiar su Service/StatefulSet más allá del volumen de datos de Minikube.
- Modificar la NetworkPolicy `platform-ingress`.
- Cambios de Terraform del VPS Hostinger.
- Fijar el valor real de las credenciales: son configuración manual documentada.

## Skills y convenciones a respetar

- **k8s-manifest-generator / base+overlay:** los cambios transversales (env S3, ConfigMap, PVC por defecto) van en `kubernetes/base`; la diferencia Minikube (volumen hostPath) va como patch del overlay. No duplicar manifiestos completos entre Minikube y Hostinger. Conservar postura de seguridad, probes, límites y `readOnlyRootFilesystem`.
- **secrets-management / `docs/secrets.md`:** Minikube puede llevar valores de desarrollo en `resources/secrets.yaml`; Hostinger usa `secrets.placeholder.yaml` → `scripts/encrypt-secrets.sh` → `secrets.enc.yaml`. Nunca commitear credenciales de imágenes en claro ni la clave age privada. Las claves dedicadas son distintas de `minio-root-*`.
- **terraform-style-guide / terraform-module-library:** no hay cambios Terraform en este corte; si apareciera alguno, se aplican formato, nombres, `type`/`description`, `sensitive`, `for_each` y organización de módulos según esas skills. Se registra la decisión para dejar constancia.
- Convención del repo: alias `mc` y port-forward a MinIO como en `scripts/backup.sh` (`platform-secrets` sólo para tareas administrativas, nunca en la app).

## Desglose técnico por RF

### 1. Script idempotente del bucket y la política dedicada (RF-1, RF-2, RF-7, RF-8, RF-9, RF-13)

1. Crear `scripts/ensure-product-images-bucket.sh` con `set -euo pipefail`, siguiendo el patrón de `scripts/backup.sh`:
   - `PORT=${MINIO_FORWARD_PORT:-19001}` (distinto del 19000 de `backup.sh`) y port-forward a `service/minio` en `platform`.
   - Leer `minio-root-user` / `minio-root-password` de `platform-secrets` (solo operación administrativa).
   - `mc alias set friendly http://127.0.0.1:$PORT …`.
2. Bucket idempotente: `mc mb --ignore-existing friendly/product-images` (RF-1, RF-2). Rerunable sin fallar (caso límite "ya existe").
3. Política de mínimo privilegio `product-images-rw` (RF-9), limitada al bucket:
   - `s3:GetBucketLocation`, `s3:ListBucket` sobre `arn:aws:s3:::product-images`.
   - `s3:PutObject`, `s3:GetObject`, `s3:DeleteObject` sobre `arn:aws:s3:::product-images/*`.
   - `mc admin policy create` / `mc admin policy info` para no fallar si ya existe.
4. Credenciales dedicadas: leer `product-images-access-key` y `product-images-secret-key` de `app-secrets` (nunca las raíz) y crear el usuario de MinIO (`mc admin user add` sólo si `mc admin user info` falla) más `mc admin policy attach … --user …` (idempotente) (RF-7, RF-8, RF-9).
5. Si faltan las claves en `app-secrets`, el script no inventa valores: avisa y termina sin crear credenciales (RF-13). El bucket puede seguir creándose.
6. `trap` para matar el port-forward, como en `backup.sh`.

### 2. Ejecución en el despliegue Minikube (RF-2, RF-14)

1. En `scripts/deploy.sh`, tras `rollout status statefulset/minio` (MinIO listo) y antes de esperar las apps, invocar `"$ROOT/scripts/ensure-product-images-bucket.sh"`.
2. El directorio del volumen se resuelve con `DirectoryOrCreate` en el patch de MinIO (sección 3), de modo que la primera ejecución crea la carpeta vacía sin impedir el despliegue (RF-4).
3. Documentar en `docs/product-images.md` que el script se puede correr suelto (`./scripts/ensure-product-images-bucket.sh`) y que es seguro repetirlo.

### 3. Respaldo local del volumen de MinIO en Minikube (RF-3, RF-4, RF-14)

1. En `kubernetes/overlays/minikube/kustomization.yaml`, agregar un patch JSON6902 sobre el StatefulSet `minio` (namespace `platform`) que:
   - elimine `/spec/volumeClaimTemplates` (Minikube no usa PVC para MinIO),
   - agregue `/spec/template/spec/volumes` con `{name: data, hostPath: {path: /friendly-e-shop/media/images, type: DirectoryOrCreate}}`.
   - El `volumeMount` `data` → `/data` del contenedor se conserva porque el volumen mantiene el nombre `data`.
2. La ruta cae dentro del montaje del workspace → `/friendly-e-shop` del nodo; el host corresponde a `/Users/dariogutierrez/projects/friendly-e-shop/media/images` (RF-3).
3. `type: DirectoryOrCreate` crea la carpeta vacía si no existe (RF-4) y conserva el contenido entre despliegues mientras el montaje siga activo (RF-14).
4. Riesgo de permisos: MinIO corre como `1000:1000` con `fsGroup: 1000`, y `hostPath` no aplica `fsGroup`. Mitigación documentada en `docs/product-images.md`: crear `media/images` en el host con permisos de escritura antes del primer despliegue y/o agregar un `initContainer` que haga `chown -R 1000:1000 /data`. Se elige la opción documentada + `initContainer` si el volumen queda sin escritura.
5. Hostinger no recibe este patch: conserva `volumeClaimTemplates` de la base (PVC) (RF-15).

### 4. Credenciales dedicadas en los secretos (RF-7, RF-8, RF-9, RF-13, RF-15)

1. En `kubernetes/overlays/minikube/resources/secrets.yaml`, dentro de `app-secrets`, añadir claves de desarrollo:
   - `product-images-access-key: catalog-images`
   - `product-images-secret-key: catalog-images-local`
   Deben coincidir con las que usa el script (sección 1) para que el usuario de MinIO y el env de catalog-api sean el mismo par.
2. En `kubernetes/overlays/hostinger/secrets.placeholder.yaml`, dentro de `app-secrets`, añadir las mismas claves con valor `REPLACE_ME`; el operador sustituye y cifra con SOPS (RF-15).
3. No añadir estas claves a `platform-secrets` (siguen siendo las raíz, solo para administración). No reutilizar `minio-root-*` como credencial de la app (RF-9).
4. Verificar que las claves nuevas existen en ambos overlays para que `secretKeyRef` resuelva y `make validate` no falle.

### 5. Variables S3 de catalog-api en la base (RF-5, RF-6, RF-7, RF-8)

1. En `kubernetes/base/catalog-api/deployment.yaml`, añadir al env del contenedor `catalog-api`:
   - `S3_ENDPOINT=http://minio.platform.svc.cluster.local:9000` (RF-5; mismo DNS interno en Minikube y Hostinger).
   - `S3_BUCKET=product-images` (RF-6).
   - `S3_ACCESS_KEY` ← `secretKeyRef` `app-secrets` / `product-images-access-key` (RF-7).
   - `S3_SECRET_KEY` ← `secretKeyRef` `app-secrets` / `product-images-secret-key` (RF-8).
2. No poner credenciales literales en el manifiesto; endpoint y bucket no son secretos y van inline (como `DATABASE_URL`/`RABBITMQ_HOST`).
3. Las claves se inyectan una sola vez en la base; los overlays heredan y solo cambian el material del secreto (base/overlay).

### 6. URL interna de catalog-api en panel-api (RF-10)

1. En el ConfigMap `panel-api-config` de `kubernetes/base/panel-api/deployment.yaml`, añadir `CATALOG_API_BASE_URL: http://catalog-api.apps.svc.cluster.local:8080`.
2. Valor único para Minikube y Hostinger (DNS de clúster); no usar el host público `api.*`.
3. No duplicar la clave en los patches de `panel-api` (los overlays solo añaden orígenes públicos y `ACCOUNT_API_BASE_URL`, que ya existe).

### 7. NetworkPolicy de acceso a MinIO (RF-11)

1. Verificar que `platform-ingress` sigue declarando el puerto 9000 desde `apps`; no se modifica (ya cumple).
2. Criterio: `kustomize build` de ambos overlays conserva la regla del puerto 9000 y la conectividad `apps → minio:9000`.

### 8. Documentación manual (RF-12, RF-13, RF-15)

1. Crear `docs/product-images.md` con:
   - Ruta local Minikube `/friendly-e-shop/media/images` (host y nodo), montaje reutilizado, creación y permisos, persistencia entre despliegues.
   - Volumen de MinIO: hostPath en Minikube (patch) y PVC en Hostinger.
   - Bucket `product-images` y política `product-images-rw`: script idempotente de Minikube y procedimiento manual equivalente en Hostinger con `mc`.
   - Credenciales dedicadas: claves `product-images-access-key`/`product-images-secret-key` en `app-secrets`, valores de desarrollo en Minikube, `REPLACE_ME` + SOPS en Hostinger; nunca credenciales raíz.
   - Variables S3 entregadas a catalog-api y `CATALOG_API_BASE_URL` de panel-api.
2. Actualizar `docs/secrets.md` sólo si hace falta aclarar que las claves de imágenes siguen el mismo flujo SOPS (referencia); sin valores reales.
3. Registrar explícitamente que si faltan bucket o credenciales, el sistema no inventa valores (RF-13).

### 9. Validación y verificación (todos los RF)

1. `make validate` (Kustomize Minikube + Hostinger, kubeconform estricto) tras los cambios.
2. Con Minikube disponible: `make deploy` (dispara el script), `kubectl -n platform exec minio-0 -- mc ls local/product-images` o `mc ls friendly/product-images`, y comprobar el env del pod `catalog-api` (`S3_*`) y el ConfigMap de `panel-api` (`CATALOG_API_BASE_URL`).
3. Inspeccionar que el usuario `catalog-images` sólo tiene `product-images-rw` y no permisos de administración.
4. Comprobar que `hostPath` escribe en `/friendly-e-shop/media/images` y que un objeto de prueba sobrevive a recrear el clúster (`minikube delete` + `make minikube-create` + `make deploy`, con el montaje de nuevo arriba).
5. `git grep` de las claves dedicadas: no deben aparecer en claro fuera de los secretos de desarrollo/placeholder.

## Mapa RF → trabajo

| RF | Piezas del plan |
|---|---|
| RF-1 | §1 (bucket `mc mb --ignore-existing`), §9 |
| RF-2 | §1 script, §2 invocación en `deploy.sh` |
| RF-3 | §3 patch hostPath Minikube sobre el montaje existente |
| RF-4 | §3 `DirectoryOrCreate`; §8 documentación de permisos |
| RF-5 | §5 `S3_ENDPOINT` en base |
| RF-6 | §5 `S3_BUCKET` en base |
| RF-7 | §4 secretos, §5 `S3_ACCESS_KEY` ← `product-images-access-key` |
| RF-8 | §4 secretos, §5 `S3_SECRET_KEY` ← `product-images-secret-key` |
| RF-9 | §1 política `product-images-rw` sobre `product-images`, usuario dedicado; §4 sin reutilizar raíz |
| RF-10 | §6 `CATALOG_API_BASE_URL` en `panel-api-config` |
| RF-11 | §7 verificación de `platform-ingress` |
| RF-12 | §8 `docs/product-images.md` |
| RF-13 | §1.5 sin inventar valores; §8 documentación |
| RF-14 | §3 hostPath persistente + remontaje; §2.1 |
| RF-15 | §3 base conserva PVC; §4 placeholder + SOPS |
| Todos (validación) | §9 `make validate` y verificación local |

## Criterios de verificación

- Kustomize Minikube incluye el patch hostPath `/friendly-e-shop/media/images` en el StatefulSet `minio` y mantiene el volumen llamado `data`.
- Kustomize Hostinger no incluye el patch hostPath y conserva `volumeClaimTemplates` (PVC).
- Pod `catalog-api`: `S3_ENDPOINT=http://minio.platform.svc.cluster.local:9000`, `S3_BUCKET=product-images`, `S3_ACCESS_KEY`/`S3_SECRET_KEY` por `secretKeyRef` a `app-secrets`; sin credenciales literales.
- `panel-api-config`: `CATALOG_API_BASE_URL=http://catalog-api.apps.svc.cluster.local:8080`.
- `app-secrets` de Minikube y placeholder Hostinger contienen `product-images-access-key`/`product-images-secret-key`; el árbol versionado no tiene credenciales reales en claro.
- `scripts/ensure-product-images-bucket.sh` corre dos veces seguidas sin fallar y deja bucket, política y usuario dedicados.
- `platform-ingress` conserva el puerto 9000 desde `apps`.
- `make validate` en verde.

## Notas

- Terraform queda fuera de este corte; se documenta el porqué y se respeta `/terraform-style-guide` y `/terraform-module-library` si un cambio futuro lo requiere.
- No hay dudas abiertas en la spec; el plan no fija valores reales de producción.
- El `hostPath` depende del montaje del workspace; si el montaje no está activo, el respaldo local no está disponible y `docs/product-images.md` debe indicarlo.
- Las credenciales de desarrollo de Minikube y el placeholder `REPLACE_ME` de Hostinger no son secretos de producción.
- `catalog-api` es el dueño de las claves S3; este plan sólo las entrega por entorno, sin tocar la lógica del servicio.
