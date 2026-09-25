# Tasks 001 — Dejar el servicio de cuentas disponible

## Historias de usuario
- H1: Como operador quiero dejar el servicio de cuentas disponible junto al resto.
- H2: Como tienda quiero poder alcanzar el servicio de cuentas con la aplicación en marcha.
- H3: Como panel quiero poder alcanzar el servicio de cuentas con la aplicación en marcha.

## Requisitos cubiertos
RF-1, RF-2, RF-3, RF-4, RF-5 (todos los de `spec.md`).

## Notas
- Trabajar solo en el repositorio `infra`. No definir login, pantallas ni lógica de negocio.
- Nombre de recurso/imagen: `account-api`. Path público: `/accounts`.
- Tareas en orden de dependencia; cada una ~20–30 min.

---

## Tareas

### Base Kubernetes del servicio (RF-1)

- [x] **T1.** Crear `kubernetes/base/account-api/deployment.yaml` replicando el patrón de `catalog-api` (namespace `apps`, imagen `friendly-e-shop/account-api:dev`, puerto `8080`, JDBC a base/usuario `accounts`, RabbitMQ, OTEL, probes Actuator, non-root, `automountServiceAccountToken: false`, límites, filesystem de solo lectura con `emptyDir` en `/tmp`).
  - **RFs:** RF-1
  - **Done when:** El manifiesto existe y declara Deployment `account-api` con probes `/actuator/health/liveness` y `/actuator/health/readiness`, sin variables de OAuth, login ni pantallas.

- [x] **T2.** Crear `kubernetes/base/account-api/service.yaml` (ClusterIP al Deployment) y `kubernetes/base/account-api/kustomization.yaml` que declare deployment + service.
  - **RFs:** RF-1
  - **Done when:** `kustomize build kubernetes/base/account-api` emite Deployment y Service `account-api` sin errores.

- [x] **T3.** Incluir el directorio `account-api` en `kubernetes/base/kustomization.yaml` junto al resto de apps.
  - **RFs:** RF-1
  - **Done when:** `kustomize build kubernetes/base` incluye los recursos de `account-api` junto a las demás aplicaciones.

### Datos y secretos (RF-1)

- [x] **T4.** Extender el script de init de PostgreSQL en `kubernetes/base/platform/postgresql.yaml` para crear usuario y base `accounts` con contraseña vía secret (mismo modelo que `catalog` / `orders` / `payments` / `panel`).
  - **RFs:** RF-1
  - **Done when:** El init declara usuario y base `accounts` leyendo la clave de secret coherente con el resto (p. ej. `account-db-password`).

- [x] **T5.** Añadir la clave `account-db-password` (o nombre equivalente coherente) en `app-secrets` y `platform-secrets` del overlay Minikube.
  - **RFs:** RF-1
  - **Done when:** Ambos Secret de Minikube contienen la clave de contraseña de la base `accounts`.

- [x] **T6.** Añadir el mismo placeholder de contraseña de `accounts` en `kubernetes/overlays/hostinger/secrets.placeholder.yaml`.
  - **RFs:** RF-1
  - **Done when:** El placeholder de Hostinger lista la clave de `accounts` alineada con Minikube, lista para cifrado SOPS.

### Build, deploy y overlay Hostinger (RF-1)

- [x] **T7.** Añadir `account-api` a la lista de servicios en `scripts/images-build.sh` (de seis a siete).
  - **RFs:** RF-1
  - **Done when:** El script construye también la imagen `friendly-e-shop/account-api:dev` (o el nombre usado por el resto).

- [x] **T8.** Esperar `rollout status` de `deployment/account-api` en `scripts/deploy.sh` junto al resto de apps.
  - **RFs:** RF-1
  - **Done when:** `deploy.sh` falla si `account-api` no queda Ready, igual que con `catalog-api` u otras apps.

- [x] **T9.** Remapear la imagen de `account-api` a GHCR en `kubernetes/overlays/hostinger/kustomization.yaml` (tag alineado al resto).
  - **RFs:** RF-1
  - **Done when:** El overlay Hostinger declara `newName`/`newTag` para `friendly-e-shop/account-api` como las demás APIs.

### Exposición pública homogénea (RF-2, RF-3)

- [x] **T10.** Añadir en el Ingress de API de Minikube el path prefix `/accounts` → Service `account-api:8080` en el mismo host `api.friendly-e-shop.test` que `/catalog`, `/orders`, `/payments` y `/panel`.
  - **RFs:** RF-2, RF-3
  - **Done when:** El Ingress Minikube enruta `/accounts` al Service `account-api` sin hosts, tunnels ni scripts distintos solo para cuentas.

- [x] **T11.** Añadir el mismo path `/accounts` → `account-api:8080` en el Ingress de API de Hostinger bajo `api.REPLACE_BASE_DOMAIN`.
  - **RFs:** RF-3
  - **Done when:** El Ingress Hostinger expone `/accounts` con el mismo esquema que el resto de APIs públicas.

### Operación auxiliar y comprobación (RF-1, RF-5)

- [x] **T12.** Incluir la base `accounts` en `scripts/backup.sh` y en la lista/validación de `scripts/restore.sh` si enumera bases explícitamente.
  - **RFs:** RF-1
  - **Done when:** Backup y restore admiten `accounts` igual que `catalog`, `orders`, `payments` y `panel`.

- [x] **T13.** Añadir `account-api.apps.svc.cluster.local:8080` al scrape estático de Prometheus de servicios Java en el overlay Minikube, si esa lista se mantiene.
  - **RFs:** RF-1
  - **Done when:** La config de scrape de Java incluye `account-api` o se confirma que no hay lista estática que deba actualizarse.

- [x] **T14.** Extender `scripts/smoke-test.sh` con un `curl --fail` a `http://api.friendly-e-shop.test:$PORT/accounts` usando el mismo `--resolve` / port-forward que el resto; si falla, el script debe salir distinto de cero e indicar que el servicio de cuentas no está disponible. Misma entrada `make smoke-test` (sin smoke aparte).
  - **RFs:** RF-5
  - **Done when:** Con el stack completo el curl a `/accounts` forma parte de `smoke-test.sh`; si se omite el servicio o la ruta Ingress, el script falla y el mensaje deja claro que cuentas no está disponible.

### Documentación y límite RF-4

- [x] **T15.** Actualizar `docs/architecture.md`, `docs/stack.md`, menciones en `README.md` y `docs/validation.md` para inventariar siete aplicaciones e incluir `account-api` como dueño de cuentas, sin describir pantallas ni cómo se entra.
  - **RFs:** RF-1, RF-4
  - **Done when:** La documentación deja de decir “seis aplicaciones”, menciona `account-api`, y no introduce flujos de login ni pantallas de tienda/panel.

- [x] **T16.** Revisar el diff de este corte: no hay cambios en manifiestos/scripts de `client-web`/`panel-web` para login o UI, ni ConfigMaps/env de OAuth/pantallas/flujos de acceso; las verificaciones se limitan a disponibilidad, red/Ingress y smoke.
  - **RFs:** RF-4
  - **Done when:** El diff de infra de este corte no define cómo se entra ni qué se ve en pantalla; solo disponibilidad, despliegue, Ingress y comprobación automática.
