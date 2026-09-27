# Plan 001 — Publicar cuentas y el secreto de Google

## Resumen

Publicar `account-api` en la puerta pública de API (`api.*` + `/accounts`) y cablear, por overlay, el identificador y el secreto de Google, el dominio de cookie de sesión, los orígenes de navegador y la URL interna que `panel-api` usa para hablar con cuentas dentro del clúster. En Hostinger el client secret de Google no debe quedar en claro en el repositorio ni en plantillas desplegables: se sigue el flujo SOPS + age ya documentado. No se implementa login, pantallas ni lógica de sesión en las aplicaciones.

## Alcance y límites

**En alcance (este repositorio `infra`):**
- Rutas de Ingress Minikube y Hostinger para `/accounts`, conservando las rutas ya publicadas.
- Variables de entorno de `account-api` y `panel-api` vía Deployment / ConfigMap y secretos de overlay.
- Claves `google-client-id` y `google-client-secret` en secretos de desarrollo (Minikube) y placeholders + cifrado SOPS (Hostinger).
- Parches Kustomize por entorno para `SESSION_COOKIE_DOMAIN` y `BROWSER_ORIGINS`.
- Validación con `make validate` y, si el despliegue local está disponible, `make smoke-test` (incluye `/accounts` y el resto de rutas).

**Fuera de alcance (respeta la spec):**
- Login con Google, cookie `fes_session` o endpoints de sesión dentro de `account-api`.
- Pantallas en `client-web` / `panel-web` o puerta de login en `panel-api`.
- Crear el client id / client secret en Google Cloud (`account-api/docs/google-oauth.md`).
- Cambiar el comportamiento de catálogo, pedidos, pagos u otras rutas más allá de mantenerlas publicadas.
- Cambios de Terraform del VPS Hostinger (no aplica a esta spec).

**Dependencia de layout:**
- Este plan asume (o exige como prerrequisito) la base `kubernetes/base/account-api/` (Deployment + Service ClusterIP en `apps`, puerto `8080`) y la base/usuario PostgreSQL `accounts`, alineados con el patrón de las demás APIs Java. Si en la rama de trabajo aún no están (p. ej. viven en el corte `001-account-service-available`), hay que incorporarlos antes o junto a la publicación; no se reinventan passwords ni topología fuera de ese patrón.
- NetworkPolicy de `apps` ya permite tráfico desde el Ingress y entre pods del namespace; no se espera una política nueva solo para esta spec, salvo que un cambio futuro restrinja peero-a-peero.

## Skills y convenciones a respetar

- **k8s-manifest-generator / base+overlay:** no duplicar manifiestos enteros entre Minikube y Hostinger; diferencias de dominio, esquema HTTP/HTTPS y secretos van en overlays o patches.
- **secrets-management / `docs/secrets.md`:** Minikube puede llevar valores de desarrollo en `secrets.yaml`; Hostinger usa `secrets.placeholder.yaml` → `scripts/encrypt-secrets.sh` → `secrets.enc.yaml` referenciado en el kustomization; nunca commitear el secreto de Google en claro ni la clave privada age.
- Postura de seguridad existente de los Deployments (non-root, límites, probes, `readOnlyRootFilesystem`) se conserva; solo se añaden env y keys de Secret.

## Desglose técnico por RF

### 1. Publicar account-api en `api.*` / `/accounts` (RF-1)

1. En `kubernetes/overlays/minikube/ingress.yaml`, en el Ingress `api` (`host: api.friendly-e-shop.test`), añadir (o confirmar) el path Prefix `/accounts` con backend Service `account-api`, puerto `8080`, **sin** sustituir el resto de paths.
2. En `kubernetes/overlays/hostinger/ingress.yaml`, bajo `host: api.REPLACE_BASE_DOMAIN`, la misma ruta `/accounts` → `account-api:8080`.
3. El Service ClusterIP `account-api` en namespace `apps` debe existir y apuntar al puerto nombrado `http` / `8080` (base Kustomize). DNS interno esperado: `account-api.apps.svc.cluster.local`.
4. Overlay Hostinger: entrada `images` para `friendly-e-shop/account-api` → `ghcr.io/REPLACE_GITHUB_OWNER/account-api:0.1.0` si aún no está, para no romper el remap de imágenes de producción.

### 2. Conservar las rutas API ya publicadas (RF-2)

1. Al editar los Ingress, mantener en el mismo host `api.*` los paths existentes:
   - `/catalog` → `catalog-api:8080`
   - `/orders` → `order-api:8080`
   - `/payments` → `payment-api:8080`
   - `/panel` → `panel-api:8000`
2. No reordenar ni renombrar Services de forma que rompa selectores.
3. Criterio: `make smoke-test` (o el equivalente documentado) sigue comprobando esas rutas junto a `/accounts`.

### 3. Inyectar `GOOGLE_CLIENT_ID` desde el secreto (RF-3)

1. En el Deployment base de `account-api`, añadir env:
   - `GOOGLE_CLIENT_ID` ← `secretKeyRef` de `app-secrets`, key `google-client-id`.
2. No inventar un valor por defecto en el manifiesto si la key falta: el pod fallará al montar el Secret o arrancará sin credencial válida según el comportamiento de Kubernetes/`optional`; **no** hardcodear client ids inventados.
3. La key `google-client-id` debe existir en los Secret `app-secrets` de ambos overlays (ver RF-9 y RF-10).

### 4. Inyectar `GOOGLE_CLIENT_SECRET` desde el secreto (RF-4)

1. Mismo patrón que RF-3:
   - `GOOGLE_CLIENT_SECRET` ← `secretKeyRef` de `app-secrets`, key `google-client-secret`.
2. No poner el secret en ConfigMap, anotaciones, README ni valores literales del Deployment.
3. Coordinación con RF-9 (valores locales permitidos) y RF-10 (Hostinger cifrado / placeholder).

### 5. Dominio de cookie en Minikube (RF-5)

1. En el overlay Minikube, entregar a `account-api` la variable de entorno:
   - `SESSION_COOKIE_DOMAIN=.friendly-e-shop.test`
2. Mecanismo preferido: patch estratégico o patch JSON de Kustomize sobre el Deployment `account-api` en `kubernetes/overlays/minikube/`, para no fijar el dominio local en la base compartida con Hostinger.
3. No usar el dominio de Hostinger en este overlay.

### 6. Dominio de cookie en entornos no locales (RF-6)

1. En el overlay Hostinger (y cualquier overlay futuro con dominio distinto), inyectar:
   - `SESSION_COOKIE_DOMAIN=.<dominio-padre>`
2. Con el placeholder actual del repo: `.REPLACE_BASE_DOMAIN` (punto inicial + dominio padre sustituible), coherente con `market.REPLACE_BASE_DOMAIN` / `panel.REPLACE_BASE_DOMAIN` / `api.REPLACE_BASE_DOMAIN` del Ingress.
3. El nombre concreto del dominio real no se fija en este plan; lo sustituye el operador al preparar Hostinger (`docs/hostinger.md`).

### 7. Orígenes de navegador `BROWSER_ORIGINS` (RF-7)

1. Entregar a `account-api` `BROWSER_ORIGINS` como lista separada por comas de orígenes **completos con esquema**, correspondientes a `shop.*` y `panel.*` del mismo entorno:
   - **Minikube (HTTP):** `http://market.friendly-e-shop.test,http://panel.friendly-e-shop.test`
   - **Hostinger (TLS en Ingress):** `https://market.REPLACE_BASE_DOMAIN,https://panel.REPLACE_BASE_DOMAIN`
2. Misma técnica de patch por overlay que RF-5/RF-6; no mezclar orígenes locales en Hostinger ni al revés.
3. No incluir el host `api.*` en esta lista salvo que una spec posterior lo pida; la spec actual pide solo tienda y panel.

### 8. URL interna de account-api para panel-api (RF-8)

1. En la configuración de `panel-api` (ConfigMap `panel-api-config` en base, o env equivalente ya usado por el Deployment), añadir:
   - `ACCOUNT_API_BASE_URL=http://account-api.apps.svc.cluster.local:8080`
2. Valor único para Minikube y Hostinger (DNS de clúster); no usar el host público `api.*` para este cableado.
3. No exponer esta URL en Ingress ni en frontends.

### 9. Secretos de desarrollo en Minikube (RF-9)

1. En `kubernetes/overlays/minikube/secrets.yaml`, dentro de `app-secrets`, añadir keys:
   - `google-client-id`
   - `google-client-secret`
2. Valores solo de desarrollo / laboratorio (nunca reutilizar fuera de Minikube), alineados con `docs/secrets.md`. Pueden ser placeholders locales explícitos que el operador reemplace al probar OAuth real; el despliegue no inventa credenciales de Google Cloud.
3. Las variables de sesión no secretas (`SESSION_COOKIE_DOMAIN`, `BROWSER_ORIGINS`) van por env/patch (RF-5, RF-7), no hace falta meterlas en el Secret salvo que se unifique por decisión operativa posterior; la spec permite que “valores locales de Google y de sesión residan en el secreto de desarrollo” — si se opta por meter también dominio/orígenes en el Secret local, mapearlos con `secretKeyRef` en el overlay Minikube y mantener Hostinger en patches no cifrados de dominio (no son secretos). Preferencia del plan: **Google en Secret; dominio y orígenes en patches de overlay** (más claros y sin cifrar datos no sensibles).

### 10. Hostinger sin client secret en claro (RF-10)

1. En `kubernetes/overlays/hostinger/secrets.placeholder.yaml`, añadir en `app-secrets` las keys `google-client-id` y `google-client-secret` con valor `REPLACE_ME` (mismo estilo que el resto de placeholders).
2. Flujo operativo existente:
   - Sustituir placeholders con valores reales **fuera del git** o en copia de trabajo no commiteada.
   - `AGE_RECIPIENT=… ./scripts/encrypt-secrets.sh` → `secrets.enc.yaml`.
   - Referenciar `secrets.enc.yaml` en el kustomization de Hostinger para despliegue real (no el placeholder).
3. Criterio de aceptación: en la configuración versionada desplegable de Hostinger, el client secret de Google no aparece en texto legible sin cifrar (ni en `stringData` de un YAML plain commiteado como fuente de verdad de producción).
4. El placeholder `REPLACE_ME` puede permanecer para `kustomize build` / `make validate` según la práctica actual del overlay; no constituye el secreto real.

## Mapa RF → trabajo

| RF | Piezas del plan |
|---|---|
| RF-1 | Path Ingress `/accounts` → `account-api:8080` (Minikube y Hostinger); Service/base y remap de imagen Hostinger si faltan |
| RF-2 | Conservar `/catalog`, `/orders`, `/payments`, `/panel` en el mismo host `api.*`; smoke-test sin regresión |
| RF-3 | `GOOGLE_CLIENT_ID` ← `app-secrets` / `google-client-id` en Deployment `account-api` |
| RF-4 | `GOOGLE_CLIENT_SECRET` ← `app-secrets` / `google-client-secret` en Deployment `account-api` |
| RF-5 | Patch overlay Minikube: `SESSION_COOKIE_DOMAIN=.friendly-e-shop.test` |
| RF-6 | Patch overlay Hostinger: `SESSION_COOKIE_DOMAIN=.REPLACE_BASE_DOMAIN` (dominio padre con punto) |
| RF-7 | Patch por overlay: `BROWSER_ORIGINS` con esquema para `shop.*` y `panel.*` |
| RF-8 | `ACCOUNT_API_BASE_URL=http://account-api.apps.svc.cluster.local:8080` en `panel-api` |
| RF-9 | Keys Google en `overlays/minikube/secrets.yaml` (desarrollo) |
| RF-10 | Keys Google en placeholder Hostinger + cifrado SOPS; sin secret en claro en despliegue |

## Criterios de verificación

- Minikube: `api.friendly-e-shop.test/accounts` responde a través del Ingress; `/catalog`, `/orders`, `/payments` y `/panel` siguen respondiendo (`make smoke-test`).
- Pod `account-api`: env `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `SESSION_COOKIE_DOMAIN=.friendly-e-shop.test`, `BROWSER_ORIGINS` con los dos orígenes HTTP locales.
- Pod `panel-api`: `ACCOUNT_API_BASE_URL=http://account-api.apps.svc.cluster.local:8080`.
- Overlay Hostinger: Ingress con `/accounts`; patches de dominio/orígenes con `REPLACE_BASE_DOMAIN` y `https://`; secretos Google solo como placeholder o material cifrado SOPS, sin client secret real en claro en el árbol versionado de producción.
- `make validate` (Kustomize + kubeconform) en verde tras los cambios de manifiestos.
- Sin cambios de lógica de login en repos de aplicación; sin commits de secretos descifrados ni clave age privada.

## Notas

- Terraform (`terraform/hostinger`) no forma parte de este corte: solo provisiona VPS/K3s; la publicación y los secretos de app viven en Kustomize.
- NetworkPolicy actual de Minikube ya permite Ingress → apps y apps → apps; `panel-api` → `account-api:8080` encaja sin cambio salvo que se endurezca la política más adelante.
- No hay dudas abiertas en la spec; este plan no fija el valor real del client id/secret ni el dominio público final de Hostinger.
