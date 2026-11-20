# Tareas 003 — Entregar el origen del Storefront a catalog-api

Ordenadas por dependencia. Cada tarea ~20–30 min. Solo configuración Kustomize y documentación; no
se implementa lógica de catálogo ni CORS dentro de `catalog-api`.

## Relevamiento y decisión del valor

- [ ] **T1. Confirmar el origen del Storefront de cada entorno**
  - Cubierta: RF-2, RF-3, RF-5
  - Verificar en `kubernetes/overlays/minikube/resources/ingress.yaml` (Ingress `storefront`) y en
    `kubernetes/overlays/hostinger/ingress.yaml` que el host del Storefront es
    `market.friendly-e-shop.duckdns.org` y `market.REPLACE_BASE_DOMAIN`; contrastar con el
    `BROWSER_ORIGINS` que ya recibe `account-api` en
    `kubernetes/overlays/minikube/patches/account-api/env-patch.yaml` y
    `kubernetes/overlays/hostinger/account-api-env-patch.yaml`.
  - Done when: quedan anotados los dos valores exactos (`https://market.friendly-e-shop.duckdns.org`
    y `https://market.REPLACE_BASE_DOMAIN`), coincidentes con el Ingress y con el origen de
    Storefront que ya usan los demás servicios del mismo entorno.

## Entrega por overlay

- [ ] **T2. Añadir `BROWSER_ORIGINS` al patch de `catalog-api` en Minikube**
  - Cubierta: RF-1, RF-2, RF-5, RF-12
  - En `kubernetes/overlays/minikube/patches/catalog-api/env-patch.yaml`, dentro del contenedor
    `catalog-api`, añadir `BROWSER_ORIGINS=https://market.friendly-e-shop.duckdns.org` junto a la
    entrada `PUBLIC_API_BASE_URL` existente, sin quitar ni reordenar nada.
  - Done when: `kustomize build kubernetes/overlays/minikube` muestra `BROWSER_ORIGINS` con ese
    valor exacto y también `PUBLIC_API_BASE_URL` en el contenedor `catalog-api`.

- [ ] **T3. Añadir `BROWSER_ORIGINS` al patch de `catalog-api` en Hostinger**
  - Cubierta: RF-3, RF-4, RF-5, RF-10, RF-12
  - En `kubernetes/overlays/hostinger/catalog-api-env-patch.yaml`, dentro del contenedor
    `catalog-api`, añadir `BROWSER_ORIGINS=https://market.REPLACE_BASE_DOMAIN` junto a
    `PUBLIC_API_BASE_URL`, reutilizando el mismo marcador de dominio base del overlay; no fijar
    ningún dominio real ni el de Minikube.
  - Done when: `kustomize build kubernetes/overlays/hostinger` muestra `BROWSER_ORIGINS` con el
    marcador `REPLACE_BASE_DOMAIN` visible, sin dominio `duckdns.org` ni valor inventado.

## Salvaguardas de la entrega

- [ ] **T4. Comprobar que el merge conserva las variables previas (RF-7, RF-9)**
  - Cubierta: RF-7, RF-9
  - Renderizar ambos overlays y contar el `env` del contenedor `catalog-api`: las diez variables de
    `kubernetes/base/catalog-api/deployment.yaml` (`DATABASE_*`, `RABBITMQ_*`, `S3_*`,
    `OTEL_RESOURCE_ATTRIBUTES`) más `PUBLIC_API_BASE_URL` y `BROWSER_ORIGINS` deben seguir
    presentes; comprobar que no se editó la base ni se añadió un Deployment/ConfigMap nuevo.
  - Done when: el env renderizado de cada overlay contiene la unión completa sin duplicados y el
    diff del corte no incluye `kubernetes/base/` ni manifiestos duplicados.

- [ ] **T5. Verificar que no se introducen secretos ni cambios en otros servicios (RF-6, RF-8)**
  - Cubierta: RF-6, RF-8
  - Confirmar que `BROWSER_ORIGINS` se entrega con `value:` literal (sin `valueFrom`/`secretKeyRef`)
    y que no se tocan `kubernetes/overlays/minikube/resources/secrets.yaml`,
    `kubernetes/overlays/hostinger/secrets.placeholder.yaml` ni `secrets.enc.yaml`; revisar que el
    patch no altera `account-api`, `order-api`, `payment-api`, `panel-api`, `panel-web`,
    `client-web` ni `kubernetes/base/platform/`.
  - Done when: `git diff --stat` solo lista los dos patches de `catalog-api` y documentación, y
    `make lint` sigue pasando su chequeo de material sensible.

- [ ] **T6. Confirmar la forma del valor: sin comodines, sin ruta, sin lista (RF-5, RF-10, RF-11)**
  - Cubierta: RF-5, RF-10, RF-11
  - Revisar ambos valores: esquema `https`, sin barra final, sin ruta, sin `*`, sin sufijos comodín y
    sin un segundo origen (el del panel no se agrega); confirmar que el marcador de Hostinger no se
    sustituye por ningún valor por defecto en el repositorio.
  - Done when: un `grep` de `BROWSER_ORIGINS` en los overlays muestra exactamente dos definiciones,
    una por entorno, cada una con un único origen exacto y el marcador visible en Hostinger.

## Documentación y validación

- [ ] **T7. Documentar el nuevo env en `docs/` (RF-4, RF-12)**
  - Cubierta: RF-4, RF-12 (apoyo documental)
  - En `docs/product-images.md` («Environment wiring»), añadir `BROWSER_ORIGINS` con sus dos valores
    por overlay y aclarar que es configuración pública; en `docs/hostinger.md`, indicar que
    sustituir `REPLACE_BASE_DOMAIN` también resuelve el origen del Storefront de `catalog-api`.
  - Done when: ambos documentos describen el valor por entorno sin credenciales ni dominios reales
    de producción y coinciden con lo entregado por los patches.

- [ ] **T8. Ejecutar la verificación completa sin clúster**
  - Cubierta: todos los RF (criterios de finalización)
  - Ejecutar `make verify` (`validate`, `lint`, `policy`, `consistency`) y revisar que el render de
    ambos overlays sigue en verde con la variable nueva.
  - Done when: `make verify` termina sin errores y el render de Minikube y Hostinger muestra
    `BROWSER_ORIGINS` con el valor esperado.

- [ ] **T9. Verificar en Minikube el env efectivo de `catalog-api` (RF-1, RF-12)**
  - Cubierta: RF-1, RF-12 (verificación de aceptación)
  - Con el clúster local disponible: `make deploy`, luego `kubectl -n apps get deployment
    catalog-api -o jsonpath='{.spec.template.spec.containers[0].env}'` y `make smoke-test`.
  - Done when: el contenedor `catalog-api` muestra `BROWSER_ORIGINS` con el origen del Storefront
    de Minikube, conserva el resto de variables y `make smoke-test` pasa sin pasos manuales dentro
    del clúster.
