# Plan 003 — Entregar el origen del Storefront a catalog-api

## Resumen

Entregar a `catalog-api` la variable de entorno `BROWSER_ORIGINS` con el origen público del
Storefront de cada entorno, para que el navegador pueda leer la respuesta del catálogo público
cuando el Storefront lo consulte. Solo se agrega una variable de configuración pública:

- **Minikube:** `BROWSER_ORIGINS=https://market.friendly-e-shop.duckdns.org`.
- **Hostinger:** `BROWSER_ORIGINS=https://market.REPLACE_BASE_DOMAIN`, expresado sobre el mismo
  marcador de dominio base que ya usa el Ingress de ese overlay.

El valor vive en los patches de `env` de `catalog-api` que **ya existen** en cada overlay
(`kubernetes/overlays/minikube/patches/catalog-api/env-patch.yaml` y
`kubernetes/overlays/hostinger/catalog-api-env-patch.yaml`), junto a `PUBLIC_API_BASE_URL`; la
base compartida no fija dominios de ningún entorno. No se crean secretos, no se toca la
configuración de otros servicios y no se duplica ningún manifiesto completo.

Este repositorio solo entrega configuración: el endpoint público, la grilla y el buscador viven en
los repositorios de las aplicaciones (fuera de alcance por spec).

## Estado de partida

- `kubernetes/base/catalog-api/deployment.yaml` entrega hoy `DATABASE_URL`,
  `DATABASE_USERNAME`, `DATABASE_PASSWORD`, `RABBITMQ_HOST`, `RABBITMQ_USERNAME`,
  `RABBITMQ_PASSWORD`, `S3_ENDPOINT`, `S3_BUCKET`, `S3_ACCESS_KEY`, `S3_SECRET_KEY` y
  `OTEL_RESOURCE_ATTRIBUTES`. **No** tiene `BROWSER_ORIGINS`.
- `kubernetes/overlays/minikube/patches/catalog-api/env-patch.yaml` ya entrega
  `PUBLIC_API_BASE_URL=https://api.friendly-e-shop.duckdns.org`; el overlay lo referencia en
  `kubernetes/overlays/minikube/kustomization.yaml`.
- `kubernetes/overlays/hostinger/catalog-api-env-patch.yaml` ya entrega
  `PUBLIC_API_BASE_URL=https://api.REPLACE_BASE_DOMAIN`; el overlay lo referencia en
  `kubernetes/overlays/hostinger/kustomization.yaml`.
- El Storefront de Minikube se publica en `market.friendly-e-shop.duckdns.org` con TLS
  (`friendly-e-shop-tls`) en `kubernetes/overlays/minikube/resources/ingress.yaml`; `make
  smoke-test` usa exactamente ese host (`scripts/checks/smoke-test.sh`). El de Hostinger es
  `market.REPLACE_BASE_DOMAIN` (`kubernetes/overlays/hostinger/ingress.yaml`).
- Precedente vigente: `account-api` ya recibe `BROWSER_ORIGINS` por overlay con el host
  `market.*` de su entorno (`patches/account-api/env-patch.yaml` y
  `account-api-env-patch.yaml`). `catalog-api` debe recibir **solo** el origen del Storefront
  (el panel queda fuera de alcance).
- `docs/product-images.md` («Environment wiring») documenta el env de `catalog-api` por overlay;
  `docs/hostinger.md` documenta la sustitución de `REPLACE_BASE_DOMAIN`.
- No hay Terraform involucrado: el cambio es exclusivamente Kustomize.

## Alcance y límites

**En alcance (este repositorio `infra`):**

- `BROWSER_ORIGINS` en el patch de `env` de `catalog-api` del overlay Minikube.
- `BROWSER_ORIGINS` en el patch de `env` de `catalog-api` del overlay Hostinger, sobre el
  marcador de dominio base.
- Nota operativa en `docs/` (env de `catalog-api` y sustitución del dominio base).
- Verificación con `make validate`, `make policy`, `make consistency` y, con clúster local,
  `make deploy`/`make smoke-test`.

**Fuera de alcance (respeta la spec):**

- Implementar la lectura pública, el filtro por nombre, la paginación o la autorización de
  navegador dentro de `catalog-api`.
- Grilla, buscador, paginación y estados de UI en `client-web`.
- Nuevos secretos o cambios en `app-secrets` / `platform-secrets` / SOPS.
- Cambios en `account-api`, `order-api`, `payment-api`, `panel-api`, `panel-web`, `client-web` o
  en los recursos de plataforma.
- Ingress, DNS, certificados, publicación o NetworkPolicies.
- Orígenes del panel u otros consumidores de navegador.
- Cambios en `Makefile` o `scripts/`: el corte no requiere targets ni lógica nuevos.

## Skills y convenciones a respetar

- **`k8s-manifest-generator` (base/overlay):** el nombre de la variable es transversal y su
  valor es propio de cada entorno. Se declara únicamente en los patches de overlay para no
  fijar dominios en la base compartida, sin duplicar Deployments ni romper la postura de
  seguridad existente (non-root, límites, probes, `readOnlyRootFilesystem`).
- **`k8s-custom-good-practices`:** los parches de Minikube viven en la carpeta de su proyecto,
  `kubernetes/overlays/minikube/patches/catalog-api/`; no se crean carpetas nuevas y no se toca
  el `Makefile` ni `scripts/`.
- **`secrets-management`:** el origen es público; no entra en Secret, ni en
  `secrets.placeholder.yaml`, ni en SOPS. No se agregan ni modifican credenciales.
- **Kustomize, patch estratégico de `env`:** la lista `env` de un contenedor se fusiona por la
  clave `name`; agregar una entrada conserva las existentes (soporte de RF-7). Varios patches
  del mismo Deployment (`env-patch`, `debug`, `live`) conviven porque declaran nombres distintos.
- **Terraform:** sin cambios en este corte; no aplican `terraform-style-guide` ni
  `terraform-module-library` más allá de no tocar `terraform/`.

## Desglose técnico por RF

### 1. `BROWSER_ORIGINS` en Minikube (RF-1, RF-2, RF-5, RF-12)

1. En `kubernetes/overlays/minikube/patches/catalog-api/env-patch.yaml`, dentro del contenedor
   `catalog-api`, añadir junto a `PUBLIC_API_BASE_URL`:
   ```yaml
   - name: BROWSER_ORIGINS
     value: https://market.friendly-e-shop.duckdns.org
   ```
2. Valor exacto de RF-2: origen completo, esquema `https`, sin ruta y sin barra final (RF-5).
3. El patch ya está referenciado por `kubernetes/overlays/minikube/kustomization.yaml`; no hace
   falta registrar nada nuevo, así que el despliegue entrega la variable sin pasos manuales
   (RF-12).
4. Sin comodines ni lista de orígenes: un único origen de Storefront (ver §6).

### 2. `BROWSER_ORIGINS` en Hostinger sobre el dominio base (RF-3, RF-4, RF-5, RF-10, RF-12)

1. En `kubernetes/overlays/hostinger/catalog-api-env-patch.yaml`, dentro del contenedor
   `catalog-api`, añadir junto a `PUBLIC_API_BASE_URL`:
   ```yaml
   - name: BROWSER_ORIGINS
     value: https://market.REPLACE_BASE_DOMAIN
   ```
2. El valor usa el mismo marcador `REPLACE_BASE_DOMAIN` que el Ingress y el resto de patches del
   overlay, de modo que sustituir el dominio base una sola vez resuelve también este origen
   (RF-4). No se fija ningún dominio real ni el dominio de Minikube.
3. Esquema `https`, sin ruta y sin barra final (RF-5), consistente con el TLS de Ingress.
4. El marcador queda visible en el manifiesto renderizado mientras el operador no lo sustituya;
   no se inventa un valor de reemplazo ni un valor por defecto (RF-10). `make validate`,
   `make policy` y `make consistency` no rechazan el marcador, porque no validan dominios.
5. El patch ya está referenciado por `kubernetes/overlays/hostinger/kustomization.yaml`; el
   despliegue no requiere pasos manuales dentro del clúster (RF-12).

### 3. Conservar variables previas y no tocar otros servicios (RF-7, RF-8)

1. Insertar la nueva entrada **sin** reescribir las listas `env` existentes: el patch de
   Minikube conserva `PUBLIC_API_BASE_URL` y el de Hostinger también (RF-7).
2. La base `kubernetes/base/catalog-api/deployment.yaml` no se modifica; sus diez variables y
   `OTEL_RESOURCE_ATTRIBUTES` siguen llegando por merge (RF-7).
3. No se edita `patches/catalog-api/debug.yaml` ni `patches/catalog-api/live.yaml`: mantienen
   `JAVA_DEBUG_OPTS` y el modo de recarga local intactos.
4. No se editan los patches, ConfigMaps, Deployments ni secretos de `account-api`, `order-api`,
   `payment-api`, `panel-api`, `panel-web` o `client-web`, ni los recursos de `platform` (RF-8).
5. Comprobación: el env renderizado de `catalog-api` contiene la unión de base + patch y el diff
   del corte no incluye otros workloads.

### 4. Configuración pública, sin secretos (RF-6)

1. `BROWSER_ORIGINS` se entrega con `value:` literal en el patch del Deployment, no con
   `valueFrom`/`secretKeyRef`.
2. No se añaden claves a `kubernetes/overlays/minikube/resources/secrets.yaml`, a
   `kubernetes/overlays/hostinger/secrets.placeholder.yaml` ni a ningún `secrets.enc.yaml`.
3. No se introduce SOPS ni se descifra nada para este corte; `make lint` sigue pasando su
   chequeo de material sensible porque no aparece nada nuevo.

### 5. Estructura base/overlay sin duplicar manifiestos (RF-9)

1. La diferencia de valor se expresa solo en los dos patches de overlay ya existentes; no se
   copia el Deployment completo ni se crea un `Deployment` nuevo.
2. La base permanece agnóstica al entorno: no contiene dominios ni marcadores.
3. No se crea un `ConfigMap` nuevo solo para esta variable: el patrón vigente del repo para env
   por entorno es el patch estratégico, y un ConfigMap añadiría un recurso sin necesidad.

### 6. Sin inferencias ni comodines (RF-10, RF-11)

1. Ninguno de los dos valores usa `*`, sufijos comodín, `null` ni listas abiertas: solo el
   origen exacto del Storefront de ese entorno.
2. No se deriva el origen desde `PUBLIC_API_BASE_URL` ni desde el Ingress en tiempo de
   despliegue: el valor es explícito, para que un entorno distinto no herede un origen ajeno.
3. Si un entorno sirviera el Storefront en otro origen, la variable seguiría apuntando al origen
   acordado; corregirlo es un cambio de configuración explícito, no un comodín (RF-11).

### 7. Documentación operativa (apoyo a RF-4 y RF-12)

1. `docs/product-images.md`, sección «Environment wiring», amplía la lista del env de
   `catalog-api` por overlay con `BROWSER_ORIGINS` y sus dos valores; deja constancia de que es
   configuración pública y no un secreto.
2. `docs/hostinger.md`, paso de sustitución del dominio base, aclara que reemplazar
   `REPLACE_BASE_DOMAIN` también resuelve `BROWSER_ORIGINS` de `catalog-api`.
3. Sin valores reales de producción y sin credenciales en la documentación.

### 8. Validación y verificación (todos los RF)

1. `kustomize build kubernetes/overlays/minikube` y `kustomize build
   kubernetes/overlays/hostinger`: cada uno debe mostrar exactamente una entrada
   `BROWSER_ORIGINS` en el contenedor `catalog-api`.
2. `make validate` (render de ambos overlays + `kubeconform -strict`) en verde.
3. `make policy` y `make consistency` en verde: no cambian kinds, backends, Services ni
   referencias a secretos.
4. Con Minikube disponible: `make deploy`, `kubectl -n apps get deployment catalog-api
   -o jsonpath='{.spec.template.spec.containers[0].env}'` y comprobar `BROWSER_ORIGINS` junto a
   las variables previas; `make smoke-test` sigue cubriendo el Storefront y `/catalog`.
5. Comparar el valor de Minikube con el host del Ingress `storefront` y con el `BROWSER_ORIGINS`
   ya entregado a `account-api`: debe ser el mismo origen `market.*` de ese entorno.

## Mapa RF → trabajo

| RF | Piezas del plan |
|---|---|
| RF-1 | §1 patch de Minikube referenciado en el kustomization |
| RF-2 | §1 valor `https://market.friendly-e-shop.duckdns.org` |
| RF-3 | §2 valor `https://market.REPLACE_BASE_DOMAIN` |
| RF-4 | §2 mismo marcador que Ingress/`PUBLIC_API_BASE_URL`; §7 docs |
| RF-5 | §1.2, §2.3 valores con esquema, sin ruta ni barra final |
| RF-6 | §4 `value:` literal, sin Secret ni SOPS |
| RF-7 | §3 merge por `name`; base y enlaces `debug`/`live` intactos |
| RF-8 | §3.4 sin cambios en otros servicios ni en `platform` |
| RF-9 | §5 solo patches de overlay; base y manifiestos sin duplicar |
| RF-10 | §2.4 marcador visible, sin valor inventado |
| RF-11 | §6 sin comodines ni orígenes inferidos |
| RF-12 | §1.3/§2.5 patches ya registrados; §8 verificación |
| Todos (validación) | §8 `make validate`, `make policy`, `make consistency`, `make smoke-test` |

## Criterios de verificación

- El render de Minikube muestra `BROWSER_ORIGINS=https://market.friendly-e-shop.duckdns.org` en
  el contenedor `catalog-api` y conserva `PUBLIC_API_BASE_URL` y las variables de la base.
- El render de Hostinger muestra `BROWSER_ORIGINS=https://market.REPLACE_BASE_DOMAIN`, sin
  dominio de Minikube ni dominio real fijado.
- Ningún valor contiene `*`, ruta, barra final ni más de un origen.
- `catalog-api` no recibe `BROWSER_ORIGINS` por `secretKeyRef`; no hay claves nuevas en secretos.
- `account-api`, el resto de servicios y los recursos de `platform` quedan idénticos byte a byte
  en el render.
- Solo cambian `kubernetes/overlays/minikube/patches/catalog-api/env-patch.yaml`,
  `kubernetes/overlays/hostinger/catalog-api-env-patch.yaml` y las notas de `docs/`.
- `make validate`, `make policy` y `make consistency` en verde; `make smoke-test` en verde si el
  clúster local está disponible.

## Notas

- La spec no tiene dudas abiertas; este plan no introduce decisiones de producto nuevas.
- La spec 001 fijaba `*.friendly-e-shop.test`; el plano vigente de Minikube es
  `*.friendly-e-shop.duckdns.org`, valor que este corte adopta (nota de coherencia de la spec).
- `BROWSER_ORIGINS` de `catalog-api` contiene **un** origen (Storefront). `account-api` conserva
  su lista con tienda y panel; no se reutiliza aquí (el panel queda fuera de alcance).
- El marcador `REPLACE_BASE_DOMAIN` es intencional en Hostinger: sustituirlo es parte del
  despliegue documentado, no un defecto del corte.
- Terraform queda fuera del corte y no se toca ningún manifiesto completo.
