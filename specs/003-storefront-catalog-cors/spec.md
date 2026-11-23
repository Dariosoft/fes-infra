# Spec 003 — Entregar el origen del Storefront a catalog-api

## Contexto y objetivo

El corte del Storefront con todos los productos publicados y buscador por nombre hace que un navegador consuma, por primera vez, una lectura pública de catálogo. Hasta hoy catalog-api sólo era invocado desde otros servicios del clúster, por lo que no necesitaba conocer el origen del navegador. Para que la tienda pueda leer el catálogo público sin que el navegador bloquee la respuesta, catalog-api necesita recibir el origen del Storefront como configuración de cada entorno. Esta spec cubre únicamente esa entrega de configuración: el endpoint público, la grilla y el buscador pertenecen a otros repositorios.

## Usuarios / actores

- Operador de infraestructura que despliega Minikube o Hostinger.
- catalog-api, que consume el origen del Storefront para autorizar la lectura pública desde el navegador.
- Visitante del Storefront, que se beneficia de que su navegador pueda leer el catálogo público.
- Persona que prepara el despliegue en Hostinger y sustituye el dominio base del entorno.

## Historias de usuario

- H1: Como operador quiero que catalog-api reciba el origen del Storefront en Minikube para que el navegador pueda consumir la lectura pública durante el desarrollo local.
- H2: Como operador quiero que catalog-api reciba el origen del Storefront en Hostinger para que la tienda publicada funcione sin ajustes manuales dentro del clúster.
- H3: Como persona que prepara el despliegue en Hostinger quiero que el origen quede expresado sobre el dominio base del entorno para no fijar el dominio de un entorno en otro.
- H4: Como responsable de seguridad quiero que este origen se trate como configuración pública para no crear secretos innecesarios ni tocar los existentes.

## Requisitos funcionales (criterios de aceptación en EARS)

- RF-1: EL SISTEMA entregará a catalog-api la variable `BROWSER_ORIGINS` en el entorno de Minikube.
- RF-2: DONDE el entorno sea Minikube, EL SISTEMA entregará a catalog-api `BROWSER_ORIGINS` con el valor `https://market.friendly-e-shop.duckdns.org`.
- RF-3: DONDE el entorno sea Hostinger, EL SISTEMA entregará a catalog-api `BROWSER_ORIGINS` con el origen del Storefront de ese entorno, expresado sobre el marcador de dominio base del entorno y con esquema `https`.
- RF-4: CUANDO se resuelva el dominio base de Hostinger, EL SISTEMA dejará `BROWSER_ORIGINS` apuntando al origen del Storefront de ese mismo entorno.
- RF-5: EL SISTEMA entregará `BROWSER_ORIGINS` como un origen completo con esquema, sin ruta y sin barra final.
- RF-6: EL SISTEMA tratará `BROWSER_ORIGINS` de catalog-api como configuración pública, sin cifrar y sin declararla como secreto.
- RF-7: EL SISTEMA conservará sin cambios las variables que catalog-api ya recibe en cada entorno.
- RF-8: EL SISTEMA conservará sin cambios la configuración de los demás servicios en ambos entornos.
- RF-9: EL SISTEMA mantendrá la estructura base y overlay, expresando la diferencia de valor del origen por entorno sin duplicar manifiestos completos.
- RF-10: SI el dominio base de un entorno no está determinado, ENTONCES EL SISTEMA dejará el marcador visible en lugar de inventar un origen.
- RF-11: SI un entorno sirve el Storefront en un origen distinto del configurado, ENTONCES EL SISTEMA no entregará un origen inferido ni un comodín que cubra otros orígenes.
- RF-12: CUANDO se despliegue cualquiera de los dos entornos, EL SISTEMA dejará `BROWSER_ORIGINS` disponible en catalog-api sin pasos manuales adicionales dentro del clúster.

## Requisitos no funcionales

- El origen del Storefront es una URL pública: no requiere secreto nuevo ni modifica los secretos existentes.
- La configuración debe seguir el entorno activo; ningún overlay puede fijar el dominio de otro entorno.
- El valor entregado en Minikube debe coincidir con el origen que ya usan los demás servicios de ese mismo entorno para el Storefront, sin introducir un dominio nuevo.
- El cambio no altera topología, publicación, certificados, DNS ni políticas de red.
- Nota de coherencia: la Spec 001 fijaba el dominio local `*.friendly-e-shop.test`, pero los manifiestos vigentes de Minikube usan `*.friendly-e-shop.duckdns.org`; esta spec adopta el valor explícito del issue vigente.

## Casos límite

- Sustitución incompleta del marcador de dominio base en Hostinger: el origen no corresponde al Storefront servido y el navegador no queda autorizado; el marcador debe permanecer visible hasta completarlo.
- Minikube con el Storefront accedido por un host alternativo, por IP y puerto, o con otro esquema: queda fuera del origen configurado y no debe resolverse con comodines.
- Origen escrito con barra final o con ruta: no cumple el requisito de origen completo y debe corregirse al valor sin ruta.
- catalog-api ya recibe otras variables en ambos entornos: la entrega del nuevo valor no debe eliminarlas.
- Aparición de un segundo consumidor de navegador (por ejemplo, el panel) en este corte: no se agrega su origen; se tratará en otra spec.
- Entorno sin el Storefront desplegado: el valor sigue siendo el origen acordado de ese entorno; no se degrada a vacío.

## Fuera de alcance

- Implementar en catalog-api la lectura pública, el filtro por nombre, la paginación y el comportamiento de autorización de navegador.
- Construir en client-web la grilla de productos, el buscador del header, la paginación y los estados de carga, vacío y error.
- Modificar imágenes de contenedor.
- Crear secretos nuevos o modificar los existentes.
- Cambiar la configuración de account-api, order-api, payment-api, panel-api o panel-web.
- Cambiar la publicación pública, los hosts, los certificados, el DNS o las políticas de red.
- Entregar a catalog-api orígenes del panel u otros consumidores de navegador.

## Criterios de finalización

- En Minikube, la configuración de catalog-api contiene `BROWSER_ORIGINS` con el origen del Storefront de ese entorno y conserva sus variables previas.
- En Hostinger, la configuración de catalog-api contiene `BROWSER_ORIGINS` expresado sobre el dominio base de ese entorno, sin ningún dominio de otro entorno.
- La renderización de ambos entornos valida en verde.
- El resultado renderizado no contiene secretos nuevos ni cambios en otros servicios.
- El origen entregado coincide con el que ya usan los demás servicios del mismo entorno para el Storefront.
- Todos los RF quedan verificados sobre la configuración renderizada de cada entorno.

## Dudas abiertas

Ninguna.
