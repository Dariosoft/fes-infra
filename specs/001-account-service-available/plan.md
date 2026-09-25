# Plan 001 — Dejar el servicio de cuentas disponible

## Resumen

Incorporar `account-api` al despliegue de Friendly E-Shop (Minikube y Hostinger) como una API más del namespace `apps`: imagen, Deployment/Service, base PostgreSQL propia, secretos, ruta pública en el Ingress de API y cobertura en la misma comprobación automática (`smoke-test`) que ya cubre al resto. No se define autenticación, flujos de entrada ni pantallas.

## Alcance y límites

**En alcance (este repositorio `infra`):**
- Manifiestos Kustomize base y overlays Minikube/Hostinger.
- Scripts operativos (`images-build`, `deploy`, `smoke-test`, backup si aplica).
- Documentación de arquitectura/stack/README que hoy enumera las seis apps, para reflejar la séptima.
- Exposición homogénea con el resto de APIs públicas (`api.*` + path prefix).

**Fuera de alcance (respeta RF-4 y la spec):**
- Cómo se entra con Google o cualquier otro proveedor.
- Qué se ve en tienda o panel.
- Lógica de negocio de `account-api`, `client-web`, `panel-api` o `panel-web`.
- Inventar un `docs/constitution.md` (no existe en este proyecto).

## Desglose técnico por RF

### 1. Servicio de cuentas junto al resto de la aplicación (RF-1)

Replicar el patrón de las APIs Java existentes (`catalog-api` / `order-api` / `payment-api`):

1. **Kustomize base** `kubernetes/base/account-api/`:
   - `Deployment` en namespace `apps`, imagen `friendly-e-shop/account-api:dev`, puerto HTTP `8080`.
   - Variables alineadas con `account-api` (JDBC a base/usuario `accounts`, RabbitMQ, OTEL).
   - Probes Actuator: `/actuator/health/liveness` y `/actuator/health/readiness`.
   - Misma postura de seguridad que el resto (non-root, `automountServiceAccountToken: false`, límites de recursos, filesystem de solo lectura con `emptyDir` en `/tmp`).
   - `Service` ClusterIP que seleccione el Deployment.
   - `kustomization.yaml` que declare deployment + service.
2. **Incluir el recurso** en `kubernetes/base/kustomization.yaml` junto a las demás apps.
3. **PostgreSQL compartido, datos separados** (`kubernetes/base/platform/postgresql.yaml`):
   - Usuario y base `accounts` en el script de init, con contraseña vía secret (mismo modelo que `catalog` / `orders` / `payments` / `panel`).
4. **Secretos**:
   - Minikube: clave `account-db-password` (o nombre equivalente coherente) en `app-secrets` y `platform-secrets`.
   - Hostinger: el mismo placeholder en `secrets.placeholder.yaml` para cifrado SOPS posterior.
5. **Build y despliegue local**:
   - Añadir `account-api` a la lista de `scripts/images-build.sh` (hoy son seis; pasa a siete).
   - Esperar `rollout status` de `deployment/account-api` en `scripts/deploy.sh`.
6. **Overlay Hostinger**:
   - Entrada `images` en `overlays/hostinger/kustomization.yaml` para remapear a GHCR (`account-api`, tag alineado al resto).
7. **Operación auxiliar coherente**:
   - Incluir la base `accounts` en `scripts/backup.sh` (y restore documentado/script si lista DBs explícitamente).
   - Observabilidad local: añadir `account-api.apps.svc.cluster.local:8080` al scrape Prometheus de servicios Java, si se mantiene esa lista estática.
8. **Documentación**: actualizar `docs/architecture.md`, `docs/stack.md` y menciones en `README.md` / validación para que el inventario deje de decir “seis aplicaciones” e incluya `account-api` como dueño de cuentas, sin describir pantallas ni login.

Con esto el servicio queda desplegado y listo junto al resto en local y en el despliegue previsto fuera de local (RNF de la spec).

### 2. La tienda puede usar el servicio cuando la app está en marcha (RF-2)

La tienda (`client-web`) ya consume APIs vía el host público de API. Para que pueda apoyarse en cuentas **sin una vía improvisada**:

1. Exponer `account-api` en el Ingress de API **igual que el resto de APIs públicas**:
   - Minikube: `api.friendly-e-shop.test` → path prefix `/accounts` → Service `account-api:8080` (el controlador del servicio usa `@RequestMapping("/accounts")`, mismo esquema que `/catalog`).
   - Hostinger: misma ruta bajo `api.REPLACE_BASE_DOMAIN`.
2. No añadir hosts, tunnels ni scripts distintos solo para cuentas.
3. No implementar consumo en `client-web` ni flujos de UI; solo garantizar reachability por la misma puerta pública.

### 3. El panel puede usar el servicio cuando la app está en marcha (RF-3)

Misma puerta pública que RF-2:

1. El path `/accounts` en el Ingress de API es alcanzable desde el entorno donde corre el panel (navegador / `panel-api` según cómo consuman en sus repos).
2. No se define la “puerta” de autenticación del panel ni pantallas de `panel-web`.
3. Criterio de infra: con el stack desplegado, una petición HTTP al path público de cuentas responde a través del mismo Ingress que `/catalog`, `/orders`, `/payments` y `/panel`.

### 4. No definir entrada ni pantallas (RF-4)

Restricciones explícitas de este plan:

- No tocar manifiestos ni scripts de `client-web` / `panel-web` para login, rutas de UI o copy.
- No añadir ConfigMaps/env que describan OAuth, pantallas o flujos de acceso (eso es de `fes-account-api` y frontends).
- El plan y la implementación se limitan a **disponibilidad, despliegue, red/Ingress y comprobación automática**.
- Cualquier verificación se limita a reachability/health del servicio (p. ej. respuesta HTTP del path `/accounts` o probes), no a “entrar” ni a contenido de pantallas.

### 5. Fallo explícito en la comprobación automática si cuentas no está disponible (RF-5)

Extender la misma comprobación que ya cubre al resto:

1. En `scripts/smoke-test.sh`, añadir una petición `curl --fail` a  
   `http://api.friendly-e-shop.test:$PORT/accounts`  
   con el mismo mecanismo `--resolve` / port-forward que el resto.
2. Si el servicio no está desplegado, el Ingress no enruta `/accounts`, o el pod no responde, el script debe **fallar** (exit distinto de cero), igual que con `/catalog` u otras rutas.
3. El mensaje de fallo debe dejar claro que **el servicio de cuentas no está disponible** (p. ej. texto en el error de curl o un `echo` previo al curl de cuentas), cumpliendo el caso límite de la spec.
4. No crear un smoke test aparte; debe ser la misma entrada (`make smoke-test`).

## Mapa RF → trabajo

| RF | Piezas del plan |
|---|---|
| RF-1 | Base K8s `account-api`, kustomization, PostgreSQL `accounts`, secretos, build/deploy, overlay Hostinger, backups/docs/observabilidad alineados |
| RF-2 | Path Ingress `/accounts` en Minikube (tienda alcanza la API pública) |
| RF-3 | Mismo path Ingress `/accounts` en Minikube y Hostinger (panel alcanza la API pública) |
| RF-4 | Límites: sin login, sin pantallas, sin lógica de negocio de cuenta/tienda/panel |
| RF-5 | Extensión de `smoke-test.sh` + fallo explícito si `/accounts` no responde |

## Criterios de verificación (sin código de producto)

- `make images-build` / `make deploy` dejan `account-api` Ready junto al resto.
- `make smoke-test` incluye `/accounts` y pasa con el stack completo.
- Si se omite o rompe `account-api` / la ruta Ingress, `make smoke-test` falla e indica indisponibilidad de cuentas (RF-5).
- Ingress Minikube y Hostinger exponen `/accounts` como el resto de APIs públicas (RNF).
- Ningún cambio de este corte implementa pantallas ni flujos de acceso (RF-4).

## Notas

- Nombre de servicio/imagen en infra: `account-api` (coherente con el repo hermano y con `spring.application.name`); la spec habla de “servicio de cuentas” / `fes-account-api` a nivel de producto.
- Path público propuesto: `/accounts`, alineado al controlador actual del servicio y al patrón `/catalog`, `/orders`, `/payments`.
- No hay dudas abiertas en la spec; este plan no introduce decisiones de login ni de UI.
