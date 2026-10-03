# Plan 002 — Almacenamiento de imágenes de producto en MinIO y cableado

## Resumen

Aprovisionar el bucket `product-images` en MinIO y cablearlo hasta catalog-api y panel-api. En Minikube el bucket se crea de forma idempotente con un script del repositorio y los objetos se pueden respaldar a demanda en la carpeta local `/Users/dariogutierrez/projects/friendly-e-shop/media/images` con `make backup-images`/`make restore-images`, manteniendo MinIO sobre su PVC (el `hostPath` del workspace no es viable porque `minikube mount` lo expone como `9p`). En Hostinger se conserva el PVC de MinIO y las credenciales dedicadas viajan cifradas por SOPS. catalog-api recibe `S3_ENDPOINT`, `S3_BUCKET`, `S3_ACCESS_KEY`, `S3_SECRET_KEY` y `PUBLIC_API_BASE_URL` con credenciales dedicadas limitadas al bucket (no las raíz); panel-api recibe `CATALOG_API_BASE_URL`. La carpeta, el bucket, la política y las credenciales se documentan manualmente en `docs/product-images.md`. El mismo corte añade overlays de depuración local (JDWP) para los APIs Java solo en Minikube, con `JAVA_DEBUG_OPTS` y un puerto por API, más la documentación de VS Code en `README.md`. No se implementa lógica de imágenes en las aplicaciones ni se toca Terraform.

## Estado de partida

- MinIO existe en la base: `kubernetes/base/platform/minio.yaml` (Service `minio` puerto `api/9000` y StatefulSet `minio` en `platform`, datos en `volumeClaimTemplates` → PVC).
- La NetworkPolicy `platform-ingress` (`kubernetes/base/platform/network-policies.yaml`) ya permite el puerto 9000 desde `apps` (RF-11 se verifica, no se modifica).
- `catalog-api` (`kubernetes/base/catalog-api/deployment.yaml`) no tiene hoy variables S3 ni URL pública.
- `panel-api` (`kubernetes/base/panel-api/deployment.yaml`) ya expone el ConfigMap `panel-api-config` con `ACCOUNT_API_BASE_URL`; falta `CATALOG_API_BASE_URL`.
- Secretos por overlay: `app-secrets` en Minikube (`kubernetes/overlays/minikube/resources/secrets.yaml`) y placeholder Hostinger (`kubernetes/overlays/hostinger/secrets.placeholder.yaml`). `platform-secrets` ya tiene `minio-root-user` / `minio-root-password`.
- El montaje del workspace ya lo garantiza `scripts/ensure-minikube-mount.sh` en `/friendly-e-shop`; `scripts/deploy/deploy.sh` lo invoca antes de aplicar. Ese montaje es `9p` y no sirve como backend vivo de MinIO.
- `scripts/runtime/java-dev-reload.sh` ya arranca los APIs Java con recarga en caliente en los pods `:live`; el overlay Minikube monta ese script desde el ConfigMap `java-dev-reload` (`patches/live/*-api.yaml`). Ya existe el patrón de patches de `env` por API (`account-api-env-patch.yaml`, `panel-api-env-patch.yaml`).
- No hay Terraform involucrado: MinIO, PVC y secretos viven en Kustomize.

## Alcance y límites

**En alcance (este repositorio `infra`):**
- Script idempotente de aprovisionamiento del bucket y de la política/credenciales dedicadas en Minikube.
- Scripts de respaldo/restauración a demanda de los objetos del bucket a la carpeta local, y sus targets de Make.
- Variables de entorno S3 y `PUBLIC_API_BASE_URL` de `catalog-api` (endpoint, bucket y URL pública no secretos; claves desde `app-secrets`).
- `CATALOG_API_BASE_URL` de `panel-api` en el ConfigMap de la base.
- Claves de credenciales dedicadas en `app-secrets` de Minikube y en el placeholder de Hostinger (SOPS).
- Overlays de depuración JDWP por API en Minikube (`patches/*-debug.yaml`), el soporte de `JAVA_DEBUG_OPTS` en `scripts/runtime/java-dev-reload.sh` y la sección de VS Code en `README.md`.
- Documento operativo `docs/product-images.md`.
- Validación con `make validate` y verificación local con el script de bucket + `make smoke-test` si Minikube está disponible.

**Fuera de alcance (respeta la spec):**
- Lógica de subida/listado/borrado de imágenes dentro de catalog-api (repo propietario).
- Aprovisionar MinIO o cambiar su Service/StatefulSet.
- Modificar la NetworkPolicy `platform-ingress`.
- Cambios de Terraform del VPS Hostinger.
- Fijar el valor real de las credenciales: son configuración manual documentada.

## Skills y convenciones a respetar

- **k8s-manifest-generator / base+overlay:** los cambios transversales (env S3, ConfigMap) van en `kubernetes/base`; la URL pública por entorno va como patch de overlay. No duplicar manifiestos completos entre Minikube y Hostinger. Conservar postura de seguridad, probes, límites y `readOnlyRootFilesystem`.
- **secrets-management / `docs/secrets.md`:** Minikube puede llevar valores de desarrollo en `resources/secrets.yaml`; Hostinger usa `secrets.placeholder.yaml` → `scripts/encrypt-secrets.sh` → `secrets.enc.yaml`. Nunca commitear credenciales de imágenes en claro ni la clave age privada. Las claves dedicadas son distintas de `minio-root-*`.
- **terraform-style-guide / terraform-module-library:** no hay cambios Terraform en este corte; si apareciera alguno, se aplican formato, nombres, `type`/`description`, `sensitive`, `for_each` y organización de módulos según esas skills. Se registra la decisión para dejar constancia.
- Convención del repo: alias `mc` y port-forward a MinIO como en `scripts/backup.sh` (`platform-secrets` sólo para tareas administrativas, nunca en la app).

## Desglose técnico por RF

### 1. Script idempotente del bucket y la política dedicada (RF-1, RF-2, RF-7, RF-8, RF-9, RF-13)

1. Crear `scripts/storage/ensure-bucket.sh` con `set -euo pipefail`, siguiendo el patrón de `scripts/backup.sh`:
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

1. En `scripts/deploy/deploy.sh`, tras `rollout status statefulset/minio` (MinIO listo) y antes de esperar las apps, invocar `"$ROOT/scripts/storage/ensure-bucket.sh"`.
2. La carpeta local de respaldo solo se crea cuando el operador corre `make backup-images` (sección 3); no bloquea el despliegue (RF-4).
3. Documentar en `docs/product-images.md` que el script se puede correr suelto (`./scripts/storage/ensure-bucket.sh`) y que es seguro repetirlo.

### 3. Respaldo local de las imágenes en Minikube (RF-3, RF-4, RF-14, RF-17, RF-25, RF-26)

1. MinIO conserva `volumeClaimTemplates` (PVC) en Minikube y Hostinger. **No** se parchea el volumen a `hostPath`: `minikube mount` expone el workspace como `9p`, que no soporta las semánticas de *rename* del backend de MinIO (`FATAL ... Rename across devices not allowed`), por lo que la carpeta local no puede ser el backend vivo.
2. Crear `scripts/storage/backup-images.sh`: port-forward a `service/minio` (patrón `scripts/backup.sh`), `mc alias set` con las credenciales raíz de `platform-secrets` (administración) y `mc mirror --overwrite friendly/product-images "$PRODUCT_IMAGES_DIR"`, creando la carpeta si no existe. `PRODUCT_IMAGES_DIR` por defecto `/Users/dariogutierrez/projects/friendly-e-shop/media/images` (RF-3, RF-4).
3. Crear `scripts/storage/restore-images.sh`: mismo alias y `mc mirror "$PRODUCT_IMAGES_DIR" friendly/product-images`, tras `mc mb --ignore-existing` (RF-14). Con `RESTORE_OVERWRITE=1` (default) usa `--overwrite`; con `0` copia solo los objetos faltantes (RF-26).
4. Añadir los targets `backup-images`/`restore-images` al `Makefile` y documentar ambos comandos en `docs/product-images.md` (RF-12, RF-17).
5. Automatizar el ciclo de vida (RF-25, RF-26): `make destroy` ejecuta `scripts/storage/backup-images.sh` antes de `minikube delete` solo si el perfil está `Running` y continúa aunque falle; `scripts/deploy/deploy.sh` ejecuta `RESTORE_OVERWRITE=0 scripts/storage/restore-images.sh` tras `ensure-product-images-bucket.sh` si existe la carpeta local (`make deploy` es el paso que sigue a `make minikube-create`; MinIO no existe al crear el clúster).
6. Hostinger no usa la carpeta local: conserva `volumeClaimTemplates` de la base (PVC) (RF-15).

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

### 6b. URL pública de catalog-api por entorno (RF-16)

1. Crear `kubernetes/overlays/minikube/patches/catalog-api-env-patch.yaml` con `PUBLIC_API_BASE_URL=https://api.friendly-e-shop.duckdns.org`.
2. Crear `kubernetes/overlays/hostinger/catalog-api-env-patch.yaml` con `PUBLIC_API_BASE_URL=https://api.REPLACE_BASE_DOMAIN`.
3. Referenciar cada patch en el `kustomization.yaml` de su overlay (mismo patrón que `account-api-env-patch.yaml`).
4. catalog-api registra sus `@ConfigurationProperties` por escaneo (`@ConfigurationPropertiesScan`), no con `@Component`, para que el binding de `fes.storage`/`fes.catalog` funcione.

### 7. NetworkPolicy de acceso a MinIO (RF-11)

1. Verificar que `platform-ingress` sigue declarando el puerto 9000 desde `apps`; no se modifica (ya cumple).
2. Criterio: `kustomize build` de ambos overlays conserva la regla del puerto 9000 y la conectividad `apps → minio:9000`.

### 8. Documentación manual (RF-12, RF-13, RF-17)

1. Crear `docs/product-images.md` con:
   - Carpeta local de respaldo (host), comandos `make backup-images`/`make restore-images`, y por qué MinIO no puede vivir en el `hostPath` del workspace.
   - Volumen de MinIO: PVC en Minikube y Hostinger.
   - Bucket `product-images` y política `product-images-rw`: script idempotente de Minikube y procedimiento manual equivalente en Hostinger con `mc`.
   - Credenciales dedicadas: claves `product-images-access-key`/`product-images-secret-key` en `app-secrets`, valores de desarrollo en Minikube, `REPLACE_ME` + SOPS en Hostinger; nunca credenciales raíz.
   - Variables S3 y `PUBLIC_API_BASE_URL` entregadas a catalog-api, y `CATALOG_API_BASE_URL` de panel-api.
2. Actualizar `docs/secrets.md` sólo si hace falta aclarar que las claves de imágenes siguen el mismo flujo SOPS (referencia); sin valores reales.
3. Registrar explícitamente que si faltan bucket o credenciales, el sistema no inventa valores (RF-13).

### 9. Validación y verificación (todos los RF)

1. `make validate` (Kustomize Minikube + Hostinger, kubeconform estricto) tras los cambios.
2. Con Minikube disponible: `make deploy` (dispara el script), `kubectl -n platform exec minio-0 -- mc ls local/product-images` o `mc ls friendly/product-images`, y comprobar el env del pod `catalog-api` (`S3_*`, `PUBLIC_API_BASE_URL`) y el ConfigMap de `panel-api` (`CATALOG_API_BASE_URL`).
3. Inspeccionar que el usuario `catalog-images` sólo tiene `product-images-rw` y no permisos de administración.
4. Comprobar que un objeto de prueba llega a la carpeta local con `make backup-images` y que `make restore-images` lo devuelve al bucket.
5. `git grep` de las claves dedicadas: no deben aparecer en claro fuera de los secretos de desarrollo/placeholder.

### 10. Depuración local de los APIs Java (RF-18 … RF-24)

1. Crear `kubernetes/overlays/minikube/patches/{catalog-api,account-api,order-api,payment-api}/debug.yaml`: patch estratégico sobre el contenedor del API que añade `JAVA_DEBUG_OPTS=-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=127.0.0.1:<puerto>` con 5005/5006/5007/5008 (RF-18, RF-19, RF-20).
2. Referenciar los cuatro patches en `kubernetes/overlays/minikube/kustomization.yaml` (RF-18).
3. En `scripts/runtime/java-dev-reload.sh`, cuando `JAVA_DEBUG_OPTS` no esté vacío, añadirlo a los argumentos de la JVM de Spring Boot (`-Dspring-boot.run.jvmArguments`); si está ausente, no agregar nada (RF-22, RF-23).
4. No tocar el overlay Hostinger: no incluye estos patches, así que el depurador queda deshabilitado (RF-21).
5. Documentar en `README.md` la sección de depuración: perfiles de VS Code, puertos por API y el port-forward temporal que abre el IDE (RF-24).
6. El agente escucha en `127.0.0.1` dentro del pod; el acceso es exclusivamente por port-forward (RF-20).

### 11. Convenciones de estructura: Makefile, scripts y parches (RF-27 … RF-30)

1. Crear la skill `k8s-custom-good-practices` en `.agents/skills/` y referenciarla en `AGENTS.md` (RF-30).
2. `Makefile`: cada target delega en `scripts/`; `tunnel` → `scripts/cluster/tunnel.sh` y `destroy` → `scripts/cluster/destroy.sh`, sin lógica multilínea inline (RF-27).
3. Reorganizar `scripts/` por dominio (`lib`, `setup`, `cluster`, `build`, `deploy`, `runtime`, `storage`, `databases`, `secrets`, `checks`, `tools`) con nombres representativos y una librería compartida `scripts/lib/{common,kube,minio}.sh` reutilizada por `source` (RF-28).
4. Reorganizar `kubernetes/overlays/minikube/patches/` en una carpeta por proyecto más `shared/` (namespace, telemetría); se elimina `live/` y sus parches pasan a la carpeta de su proyecto (RF-29).
5. Actualizar referencias en `Makefile`, `kustomization.yaml`, `docs/*.md` y las llamadas entre scripts; `runtime/java-dev-reload.sh` queda standalone (`#!/bin/sh`, corre dentro del contenedor).

## Mapa RF → trabajo

| RF | Piezas del plan |
|---|---|
| RF-1 | §1 (bucket `mc mb --ignore-existing`), §9 |
| RF-2 | §1 script, §2 invocación en `deploy.sh` |
| RF-3 | §3 scripts de respaldo/restauración (`mc mirror`) |
| RF-4 | §3 crea la carpeta al respaldar; §8 documentación |
| RF-5 | §5 `S3_ENDPOINT` en base |
| RF-6 | §5 `S3_BUCKET` en base |
| RF-7 | §4 secretos, §5 `S3_ACCESS_KEY` ← `product-images-access-key` |
| RF-8 | §4 secretos, §5 `S3_SECRET_KEY` ← `product-images-secret-key` |
| RF-9 | §1 política `product-images-rw` sobre `product-images`, usuario dedicado; §4 sin reutilizar raíz |
| RF-10 | §6 `CATALOG_API_BASE_URL` en `panel-api-config` |
| RF-11 | §7 verificación de `platform-ingress` |
| RF-12 | §8 `docs/product-images.md` |
| RF-13 | §1.5 sin inventar valores; §8 documentación |
| RF-14 | §3 respaldo/restauración a demanda; §9 verificación |
| RF-15 | §3 base conserva PVC; §4 placeholder + SOPS |
| RF-16 | §6b `PUBLIC_API_BASE_URL` por overlay |
| RF-17 | §3 scripts + targets del Makefile |
| RF-18 | §10 patches debug y su referencia en el overlay Minikube |
| RF-19 | §10 puerto JDWP por API (5005–5008) |
| RF-20 | §10 `address=127.0.0.1`, acceso por port-forward |
| RF-21 | §10 el overlay Hostinger no incluye patches de debug |
| RF-22 | §10 `java-dev-reload.sh` añade `JAVA_DEBUG_OPTS` |
| RF-23 | §10 sin `JAVA_DEBUG_OPTS` el API no expone JDWP |
| RF-24 | §10 sección de depuración en `README.md` |
| RF-25 | §3 respaldo automático en `make destroy` |
| RF-26 | §3 restauración de faltantes en `make deploy` |
| RF-27 | §11 Makefile delega `tunnel`/`destroy` en scripts |
| RF-28 | §11 estructura de `scripts/` + `scripts/lib/` |
| RF-29 | §11 parches de Minikube por proyecto + `shared/` |
| RF-30 | §11 skill `k8s-custom-good-practices` |
| Todos (validación) | §9 `make validate` y verificación local |

## Criterios de verificación

- Kustomize Minikube y Hostinger conservan `volumeClaimTemplates` (PVC) en el StatefulSet `minio`; ninguno introduce `hostPath`.
- `scripts/storage/backup-images.sh` y `scripts/storage/restore-images.sh` copian entre el bucket y la carpeta local; el `Makefile` expone `backup-images`/`restore-images`.
- Pod `catalog-api`: `S3_ENDPOINT=http://minio.platform.svc.cluster.local:9000`, `S3_BUCKET=product-images`, `S3_ACCESS_KEY`/`S3_SECRET_KEY` por `secretKeyRef` a `app-secrets`, y `PUBLIC_API_BASE_URL` por overlay; sin credenciales literales.
- `panel-api-config`: `CATALOG_API_BASE_URL=http://catalog-api.apps.svc.cluster.local:8080`.
- `app-secrets` de Minikube y placeholder Hostinger contienen `product-images-access-key`/`product-images-secret-key`; el árbol versionado no tiene credenciales reales en claro.
- `scripts/storage/ensure-bucket.sh` corre dos veces seguidas sin fallar y deja bucket, política y usuario dedicados.
- `platform-ingress` conserva el puerto 9000 desde `apps`.
- El overlay Minikube habilita `JAVA_DEBUG_OPTS` con puertos 5005–5008 en los cuatro APIs Java; el overlay Hostinger no define `JAVA_DEBUG_OPTS`.
- `scripts/runtime/java-dev-reload.sh` añade `JAVA_DEBUG_OPTS` a la JVM solo cuando está definido.
- `make validate` en verde.
- `make tunnel`/`make destroy` invocan scripts; `scripts/` está agrupado por dominio con `scripts/lib/`; los parches de Minikube están por proyecto + `shared/`; `bash -n`/`sh -n` de todos los scripts queda limpio.

## Notas

- Terraform queda fuera de este corte; se documenta el porqué y se respeta `/terraform-style-guide` y `/terraform-module-library` si un cambio futuro lo requiere.
- No hay dudas abiertas en la spec; el plan no fija valores reales de producción.
- La carpeta local es un destino de respaldo; el almacenamiento vivo de MinIO es el PVC. `make destroy` respalda automáticamente (best-effort) y `make deploy` restaura los faltantes.
- Las credenciales de desarrollo de Minikube y el placeholder `REPLACE_ME` de Hostinger no son secretos de producción.
- `catalog-api` es el dueño de las claves S3 y de la URL pública; este plan sólo las entrega por entorno, sin tocar la lógica del servicio.
- La depuración JDWP es exclusiva de Minikube y escucha en `127.0.0.1`; el overlay Hostinger no la habilita.
