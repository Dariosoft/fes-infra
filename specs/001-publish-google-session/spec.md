# Spec 001 — Publicar cuentas y el secreto de Google

## Contexto y objetivo

La sesión compartida con Google exige que account-api sea alcanzable desde el exterior en la API pública y que reciba, por entorno, el identificador y el secreto de Google, el dominio de la cookie de sesión y los orígenes del navegador permitidos. panel-api debe poder hablar con account-api dentro del clúster. Sin esa publicación y esa configuración, el resto de repositorios no puede completar el login ni la sesión compartida.

## Usuarios / actores

- Operador de infraestructura que despliega Minikube o Hostinger.
- account-api, que consume las variables y la ruta pública acordadas.
- panel-api, que consume la URL interna de account-api.
- Personas que usan la tienda (`shop.*`) y el panel (`panel.*`) a través de la API (`api.*`).

## Historias de usuario

- H1: Como operador quiero publicar account-api en la ruta pública de cuentas para que tienda y panel puedan iniciar y consultar la sesión compartida.
- H2: Como account-api quiero recibir el identificador y el secreto de Google, el dominio de cookie y los orígenes del navegador del entorno para poder completar el login sin configuración manual dentro del servicio.
- H3: Como panel-api quiero conocer la URL interna de account-api para resolver la sesión y el cierre sin salir del clúster.
- H4: Como operador quiero que en Hostinger el secreto de cliente de Google no viaje en claro para no exponer credenciales en el repositorio ni en plantillas desplegables.

## Requisitos funcionales (criterios de aceptación en EARS)

- RF-1: CUANDO se publica la API del entorno, EL SISTEMA expondrá account-api en el host `api.*` bajo la ruta `/accounts` hacia el puerto 8080.
- RF-2: MIENTRAS la API del entorno esté publicada, EL SISTEMA mantendrá alcanzables en el mismo host `api.*` las rutas `/catalog`, `/orders`, `/payments` y `/panel`.
- RF-3: EL SISTEMA inyectará en account-api el valor del secreto `google-client-id` como `GOOGLE_CLIENT_ID`.
- RF-4: EL SISTEMA inyectará en account-api el valor del secreto `google-client-secret` como `GOOGLE_CLIENT_SECRET`.
- RF-5: DONDE el entorno sea el local (Minikube), EL SISTEMA entregará a account-api `SESSION_COOKIE_DOMAIN` con el valor `.friendly-e-shop.test`.
- RF-6: DONDE el entorno use un dominio distinto del local, EL SISTEMA entregará a account-api `SESSION_COOKIE_DOMAIN` con el dominio padre de ese entorno precedido de un punto inicial. El nombre concreto del dominio no se fija en esta spec.
- RF-7: EL SISTEMA entregará a account-api `BROWSER_ORIGINS` como orígenes completos con esquema, separados por coma, correspondientes a `shop.*` y `panel.*` del mismo entorno.
- RF-8: EL SISTEMA entregará a panel-api `ACCOUNT_API_BASE_URL` con el valor `http://account-api.apps.svc.cluster.local:8080`.
- RF-9: DONDE el entorno sea Minikube, EL SISTEMA permitirá que los valores locales de Google y de sesión residan en el secreto de desarrollo.
- RF-10: DONDE el entorno sea Hostinger, EL SISTEMA no dejará el client secret de Google en claro.

## Requisitos no funcionales

- Los hosts públicos cambian entre Minikube (`*.friendly-e-shop.test`) y el dominio futuro de cada entorno; la configuración debe seguir el entorno activo sin fijar un único dominio en todos los despliegues.
- El client id y el client secret de Google los crea una persona; esta especificación no define su valor concreto.
- En Hostinger, el client secret de Google no puede persistirse ni entregarse en texto legible sin cifrar.

## Casos límite

- Un entorno con dominio distinto de `*.friendly-e-shop.test` debe recibir `SESSION_COOKIE_DOMAIN` y `BROWSER_ORIGINS` coherentes con ese dominio, no con los valores locales.
- Si faltan `google-client-id` o `google-client-secret` en el entorno, account-api no dispondrá de `GOOGLE_CLIENT_ID` o `GOOGLE_CLIENT_SECRET` válidos; el despliegue no debe inventar credenciales.
- Las rutas ya existentes de la API (`/catalog`, `/orders`, `/payments`, `/panel`) no deben dejar de responder al añadir `/accounts`.

## Fuera de alcance

- Implementar el login con Google ni la lógica de sesión en account-api.
- Dibujar pantallas en client-web o panel-web.
- Implementar la puerta de login del panel en panel-api.
- Crear en Google Cloud el client id y el client secret; el procedimiento permanece en `account-api/docs/google-oauth.md`.
- Cambiar el comportamiento de catálogo, pedidos, pagos u otras rutas más allá de conservarlas publicadas.

## Criterios de finalización

- Todos los RF verificables en el entorno local (Minikube): `/accounts` responde a través de `api.*`, las rutas previas siguen disponibles, account-api recibe las variables acordadas y panel-api recibe `ACCOUNT_API_BASE_URL`.
- Comprobado que, en la configuración de Hostinger, el client secret de Google no aparece en claro.
- Dudas abiertas resueltas o aceptadas explícitamente antes de cerrar la implementación.

## Dudas abiertas

Ninguna.
