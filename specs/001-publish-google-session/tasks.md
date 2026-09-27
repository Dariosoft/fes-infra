# Tareas 001 — Publicar cuentas y el secreto de Google

Ordenadas por dependencia. Cada tarea ~20–30 min. No implementar login ni lógica de sesión en las aplicaciones.

## Prerrequisito de layout

- [x] **T1. Incorporar la base `account-api` (Deployment + Service ClusterIP)**
  - Cubierta: base necesaria para RF-1, RF-3, RF-4, RF-5, RF-6, RF-7
  - Crear `kubernetes/base/account-api/` con Deployment (puerto `http`/`8080`, postura de seguridad como las demás APIs Java) y Service ClusterIP en `apps`; registrar el recurso en `kubernetes/base/kustomization.yaml`.
  - Done when: `kustomize build kubernetes/base` incluye Deployment y Service `account-api` escuchando en 8080 y el DNS esperado es `account-api.apps.svc.cluster.local`.

- [x] **T2. Añadir usuario/base PostgreSQL `accounts` y clave de secreto alineada**
  - Cubierta: soporte de despliegue para RF-1 (pod listo) y patrón de secretos de RF-9/RF-10
  - Extender el init de PostgreSQL y las keys `accounts-db-password` en secretos de plataforma/`app-secrets` (Minikube y placeholder Hostinger) siguiendo el patrón de las demás APIs; cablear `DATABASE_*` en el Deployment de `account-api` sin inventar passwords fuera del patrón.
  - Done when: el init crea usuario/base `accounts` y los overlays Minikube/Hostinger declaran `accounts-db-password` en los Secret correspondientes.

## Publicación en Ingress

- [x] **T3. Publicar `/accounts` en el Ingress de Minikube sin tocar el resto de rutas**
  - Cubierta: RF-1, RF-2
  - En `kubernetes/overlays/minikube/resources/ingress.yaml`, en el Ingress `api` (`api.friendly-e-shop.duckdns.org` + TLS), añadir path Prefix `/accounts` → Service `account-api` puerto `8080`, conservando `/catalog`, `/orders`, `/payments` y `/panel`.
  - Done when: el manifiesto Minikube lista las cinco rutas en el mismo host `api.friendly-e-shop.duckdns.org` y `/accounts` apunta a `account-api:8080`.

- [x] **T4. Publicar `/accounts` en el Ingress de Hostinger y remap de imagen**
  - Cubierta: RF-1, RF-2
  - En `kubernetes/overlays/hostinger/ingress.yaml`, bajo `api.REPLACE_BASE_DOMAIN`, añadir `/accounts` → `account-api:8080` sin eliminar las rutas existentes; en el kustomization Hostinger, añadir remap `friendly-e-shop/account-api` → `ghcr.io/REPLACE_GITHUB_OWNER/account-api:0.1.0` si falta.
  - Done when: el Ingress Hostinger expone `/accounts` junto a `/catalog`, `/orders`, `/payments` y `/panel`, y el overlay remapea la imagen de `account-api`.

## Secretos e inyección de Google en account-api

- [x] **T5. Declarar keys Google de desarrollo en el secreto Minikube**
  - Cubierta: RF-9 (habilita RF-3, RF-4)
  - En `kubernetes/overlays/minikube/resources/secrets.yaml`, dentro de `app-secrets`, añadir `google-client-id` y `google-client-secret` con valores solo de laboratorio (placeholders locales explícitos, no credenciales reales de producción).
  - Done when: `app-secrets` de Minikube contiene ambas keys y no se reutilizan fuera del overlay local.

- [x] **T6. Declarar placeholders Google en Hostinger sin secreto real en claro**
  - Cubierta: RF-10 (habilita RF-3, RF-4)
  - En `kubernetes/overlays/hostinger/secrets.placeholder.yaml`, añadir `google-client-id` y `google-client-secret` con valor `REPLACE_ME`; no committear un YAML de producción con el client secret legible.
  - Done when: el placeholder Hostinger tiene ambas keys como `REPLACE_ME` y el árbol versionado no contiene el client secret real en texto claro.

- [x] **T7. Inyectar `GOOGLE_CLIENT_ID` desde `app-secrets` en el Deployment**
  - Cubierta: RF-3
  - En el Deployment base de `account-api`, añadir env `GOOGLE_CLIENT_ID` ← `secretKeyRef` de `app-secrets` / `google-client-id`, sin valor por defecto inventado ni literales en el manifiesto.
  - Done when: el Deployment referencia solo `secretKeyRef` para `GOOGLE_CLIENT_ID` y no hay client id hardcodeado.

- [x] **T8. Inyectar `GOOGLE_CLIENT_SECRET` desde `app-secrets` en el Deployment**
  - Cubierta: RF-4
  - Mismo patrón que T7: `GOOGLE_CLIENT_SECRET` ← `app-secrets` / `google-client-secret`; no usar ConfigMap, anotaciones ni literales.
  - Done when: el Deployment monta `GOOGLE_CLIENT_SECRET` únicamente vía `secretKeyRef` y no aparece en ConfigMap ni README.

## Dominio de cookie y orígenes por overlay

- [x] **T9. Patch Minikube: `SESSION_COOKIE_DOMAIN` local**
  - Cubierta: RF-5
  - Añadir patch Kustomize en `kubernetes/overlays/minikube/patches/account-api-env-patch.yaml` que entregue a `account-api` `SESSION_COOKIE_DOMAIN=.friendly-e-shop.duckdns.org` y `SESSION_COOKIE_SECURE=true` (no fijar estos valores en la base compartida). RF-5 se cumple con el dominio padre del plano público DuckDNS.
  - Done when: el build del overlay Minikube muestra `SESSION_COOKIE_DOMAIN=.friendly-e-shop.duckdns.org` y `SESSION_COOKIE_SECURE=true` en el Deployment `account-api` y la base no los fija.

- [x] **T10. Patch Hostinger: `SESSION_COOKIE_DOMAIN` con dominio padre sustituible**
  - Cubierta: RF-6
  - Añadir patch en `kubernetes/overlays/hostinger/` con `SESSION_COOKIE_DOMAIN=.REPLACE_BASE_DOMAIN` (punto inicial + dominio padre).
  - Done when: el build Hostinger entrega `.REPLACE_BASE_DOMAIN` y no usa `.friendly-e-shop.test`.

- [x] **T11. Patch Minikube: `BROWSER_ORIGINS` HTTPS de tienda y panel**
  - Cubierta: RF-7
  - En el overlay Minikube (`patches/account-api-env-patch.yaml`), entregar `BROWSER_ORIGINS=https://market.friendly-e-shop.duckdns.org,https://panel.friendly-e-shop.duckdns.org` y `PUBLIC_API_BASE_URL=https://api.friendly-e-shop.duckdns.org` (orígenes completos con esquema; tienda = `market.*`, sin incluir `api.*` en `BROWSER_ORIGINS`).
  - Done when: el build Minikube muestra exactamente esos dos orígenes HTTPS separados por coma y `PUBLIC_API_BASE_URL` en `account-api`.

- [x] **T12. Patch Hostinger: `BROWSER_ORIGINS` HTTPS de tienda y panel**
  - Cubierta: RF-7
  - En el overlay Hostinger, entregar `BROWSER_ORIGINS=https://market.REPLACE_BASE_DOMAIN,https://panel.REPLACE_BASE_DOMAIN`.
  - Done when: el build Hostinger muestra esos dos orígenes HTTPS con `REPLACE_BASE_DOMAIN` y no mezcla orígenes locales.

## Panel y cierre operativo Hostinger

- [x] **T13. Entregar `ACCOUNT_API_BASE_URL` interna a `panel-api`**
  - Cubierta: RF-8
  - En el ConfigMap `panel-api-config` (o env equivalente de la base), añadir `ACCOUNT_API_BASE_URL=http://account-api.apps.svc.cluster.local:8080` (mismo valor Minikube/Hostinger; no usar `api.*` público).
  - Done when: el build de ambos overlays incluye esa URL interna en la configuración de `panel-api`.

- [x] **T14. Confirmar flujo SOPS + age para el client secret en Hostinger**
  - Cubierta: RF-10
  - Verificar que el kustomization de despliegue real referencia `secrets.enc.yaml` (no el placeholder con secretos reales), que el operador puede cifrar con `scripts/encrypt-secrets.sh` tras sustituir `REPLACE_ME`, y que no se versiona clave age privada ni secreto descifrado.
  - Done when: queda documentado/comprobado en el overlay que el client secret de Google de producción solo vive cifrado o como placeholder, nunca en claro como fuente de verdad desplegable.

## Validación

- [x] **T15. Validar manifiestos con `make validate`**
  - Cubierta: RF-1 … RF-10 (integridad de manifiestos)
  - Ejecutar `make validate` tras los cambios de Kubernetes/Kustomize.
  - Done when: `make validate` termina en verde (Kustomize + kubeconform) sin secretos descifrados añadidos al árbol.

- [ ] **T16. Prueba de humo local de rutas API (si Minikube está disponible)**
  - Cubierta: RF-1, RF-2
  - Con el stack local desplegado, ejecutar `make smoke-test` y comprobar que `/accounts` responde vía `https://api.friendly-e-shop.duckdns.org` y que `/catalog`, `/orders`, `/payments` y `/panel` siguen OK; opcionalmente inspeccionar env del pod `account-api` (`GOOGLE_*`, `SESSION_COOKIE_DOMAIN`, `SESSION_COOKIE_SECURE`, `BROWSER_ORIGINS`, `PUBLIC_API_BASE_URL`) y de `panel-api` (`ACCOUNT_API_BASE_URL`, `PANEL_PUBLIC_ORIGIN`, `ACCOUNTS_PUBLIC_BASE_URL`).
  - Done when: `make smoke-test` pasa e incluye `/accounts` sin regresión en las rutas previas; si el clúster no está disponible, dejar constancia explícita y diferir solo esta verificación operativa.
  - Skipped: Minikube no está disponible (`minikube status` DOWN); smoke-test operativo diferido.

## Mapa RF → tareas

| RF | Tareas |
|----|--------|
| RF-1 | T1, T3, T4, T16 |
| RF-2 | T3, T4, T16 |
| RF-3 | T5, T6, T7 |
| RF-4 | T5, T6, T8 |
| RF-5 | T9 |
| RF-6 | T10 |
| RF-7 | T11, T12 |
| RF-8 | T13 |
| RF-9 | T5 |
| RF-10 | T6, T14 |
| Todos (validación) | T15 |
