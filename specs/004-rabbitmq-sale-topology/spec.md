# Spec 004 — Topología RabbitMQ para la venta asíncrona

## Contexto y objetivo

La Fase 1 del proceso de venta asíncrono necesita que un pedido recién dado de alta llegue a quien reserva el stock y a la notificación del vendedor, y que el resultado del stock vuelva al servicio de pedidos. Esa entrega es responsabilidad de la mensajería, no de la lógica de negocio de cada servicio. Sin una topología de mensajería declarada, durable y reproducible, el flujo no puede funcionar de forma asíncrona ni sobrevivir a un reinicio del broker. Esta spec cubre únicamente la topología (exchanges, colas, enlaces, reintento diferido con TTL y colas de mensajes agotados) y su cableado en los dos entornos; no implementa productores ni consumidores.

## Usuarios / actores

- Operador de infraestructura que despliega Minikube o Hostinger.
- order-api, que publica `order.placed` y consume los resultados de stock.
- catalog-api, que consume `stock.reserve` y publica los resultados de stock.
- Consumidores de `stock.reserve` y `order.stock-results`, que aplican el reintento y enrutan el mensaje a la cola de agotados al quinto fallo.
- Consumidor futuro del feed del vendedor (Fase 2), que consumirá `seller.notify`.
- RabbitMQ, como broker que retiene y entrega los mensajes.
- Responsable de operación y seguridad, que inspecciona los mensajes agotados y administra las credenciales existentes.

## Historias de usuario

- H1: Como order-api quiero que `order.placed` llegue a la reserva de stock para que la venta avance de forma asíncrona.
- H2: Como order-api quiero que `order.placed` llegue también a la notificación del vendedor para no bloquear el alta del pedido.
- H3: Como catalog-api quiero recibir `order.placed` en `stock.reserve` para reservar el stock de un pedido.
- H4: Como order-api quiero recibir `stock.reserved` y `stock.rejected` en `order.stock-results` para actualizar el pedido con el resultado del stock.
- H5: Como equipo del feed del vendedor quiero que `seller.notify` exista en Fase 1 para consumirla en Fase 2 sin cambiar la topología.
- H6: Como operador quiero que las colas y los mensajes sobrevivan a un reinicio del broker para no perder ventas.
- H7: Como operador quiero reintentos diferidos de 30 segundos con un máximo de 5 intentos y una cola de agotados por cola de consumo, con 14 días de retención, para diagnosticar fallos sin perder mensajes.
- H8: Como operador quiero reproducir la misma topología en Minikube y Hostinger para que ambos entornos se comporten igual.
- H9: Como responsable de seguridad quiero reutilizar el usuario y las credenciales existentes para no introducir secretos nuevos.
- H10: Como operador quiero que `seller.notify` retenga sus mensajes hasta 7 días sin consumidor y luego los descarte para no llenar el almacenamiento del broker.

## Requisitos funcionales (criterios de aceptación en EARS)

- RF-1: EL SISTEMA dispondrá del exchange `orders`, de tipo topic y durable, para recibir eventos de pedido.
- RF-2: EL SISTEMA dispondrá de la cola durable `stock.reserve`.
- RF-3: EL SISTEMA enlazará la cola `stock.reserve` al exchange `orders` con la routing key `order.placed`.
- RF-4: EL SISTEMA dispondrá de la cola durable `seller.notify`.
- RF-5: EL SISTEMA enlazará la cola `seller.notify` al exchange `orders` con la routing key `order.placed`.
- RF-6: EL SISTEMA dispondrá del exchange `stock`, de tipo topic y durable, para recibir resultados de stock.
- RF-7: EL SISTEMA dispondrá de la cola durable `order.stock-results`.
- RF-8: EL SISTEMA enlazará la cola `order.stock-results` al exchange `stock` con la routing key `stock.reserved`.
- RF-9: EL SISTEMA enlazará la cola `order.stock-results` al exchange `stock` con la routing key `stock.rejected`.
- RF-10: CUANDO un productor publique un mensaje en una routing key enlazada, EL SISTEMA entregará una copia a cada cola enlazada a esa routing key.
- RF-11: CUANDO el broker se reinicie, EL SISTEMA conservará las colas declaradas.
- RF-12: CUANDO el broker se reinicie, EL SISTEMA conservará los mensajes no consumidos que ya estaban en las colas y que no hayan caducado por su TTL.
- RF-13: EL SISTEMA retendrá todo mensaje publicado en una routing key enlazada hasta que un consumidor lo procese, hasta que caduque por el TTL de su cola o hasta que se agote y quede en la cola de mensajes agotados.
- RF-14: CUANDO falle el procesamiento de un mensaje de `stock.reserve`, EL SISTEMA lo reintentará con un retardo fijo de 30 segundos hasta completar un máximo de 5 intentos en total, mediante la cola durable `stock.reserve.retry`, que retiene el mensaje 30 segundos y lo devuelve a `stock.reserve`.
- RF-15: SI un mensaje de `stock.reserve` alcanza el quinto intento fallido, ENTONCES EL SISTEMA lo dejará en la cola durable `stock.reserve.dlq`, que lo retiene 14 días para inspección.
- RF-16: CUANDO falle el procesamiento de un mensaje de `order.stock-results`, EL SISTEMA lo reintentará con un retardo fijo de 30 segundos hasta completar un máximo de 5 intentos en total, mediante la cola durable `order.stock-results.retry`, que retiene el mensaje 30 segundos y lo devuelve a `order.stock-results`.
- RF-17: SI un mensaje de `order.stock-results` alcanza el quinto intento fallido, ENTONCES EL SISTEMA lo dejará en la cola durable `order.stock-results.dlq`, que lo retiene 14 días para inspección.
- RF-18: EL SISTEMA no entregará un mensaje reintentado antes de que transcurran 30 segundos desde el fallo que lo envió a la cola de reintento.
- RF-19: MIENTRAS `seller.notify` no tenga consumidor en Fase 1, EL SISTEMA no descartará sus mensajes por falta de consumidor antes de que transcurran 7 días desde su publicación.
- RF-20: EL SISTEMA descartará los mensajes que permanezcan en `seller.notify` al cumplirse 7 días desde su publicación.
- RF-21: DONDE el entorno sea Minikube, EL SISTEMA aplicará esta topología.
- RF-22: DONDE el entorno sea Hostinger, EL SISTEMA aplicará esta misma topología.
- RF-23: EL SISTEMA obtendrá la topología de una definición común a ambos entornos, sin duplicar definiciones completas.
- RF-24: EL SISTEMA reutilizará el despliegue de RabbitMQ existente.
- RF-25: EL SISTEMA reutilizará el usuario `app` existente.
- RF-26: EL SISTEMA reutilizará las variables `RABBITMQ_*` existentes.
- RF-27: EL SISTEMA no introducirá secretos nuevos en Fase 1.
- RF-28: EL SISTEMA conservará sin cambios los manifiestos de los componentes de plataforma existentes.
- RF-29: EL SISTEMA conservará sin cambios los sondeos de salud de RabbitMQ.
- RF-30: EL SISTEMA conservará sin cambios las políticas de red de la plataforma.
- RF-31: CUANDO se aplique la topología más de una vez, EL SISTEMA no duplicará exchanges, colas ni enlaces existentes.
- RF-32: SI un mensaje publicado no coincide con ninguna routing key enlazada, ENTONCES EL SISTEMA no lo entregará a `stock.reserve`, `seller.notify` ni `order.stock-results`.

## Requisitos no funcionales

- La mensajería se apoya en el RabbitMQ ya previsto por la plataforma; no se sustituye por otro broker en esta iteración.
- La durabilidad se apoya en el almacenamiento persistente ya existente del broker: las colas declaradas y los mensajes no consumidos se conservan al reiniciar el broker mientras el volumen se mantenga y el mensaje no haya caducado por su TTL.
- El retardo de reintento es fijo en 30 segundos y el máximo es 5 intentos por mensaje en `stock.reserve` y en `order.stock-results`.
- La retención es de 7 días para los mensajes de `seller.notify` y de 14 días para los mensajes de `stock.reserve.dlq` y `order.stock-results.dlq`.
- La topología debe ser idéntica en Minikube y Hostinger; las diferencias entre entornos se limitan a lo propio de cada entorno y no duplican la definición completa.
- No se agregan secretos: se usan el usuario `app` y las variables `RABBITMQ_*` que ya existen.
- El acceso de administración a RabbitMQ sigue siendo interno, como en la plataforma actual.
- Las políticas de postura del repositorio deben seguir cumpliéndose sobre la topología resultante.

## Casos límite

- Reinicio del broker con mensajes en cola: las colas y los mensajes no consumidos que no hayan caducado deben seguir disponibles.
- Consumidor detenido o ausente: los mensajes permanecen en la cola; en `seller.notify` permanecen hasta 7 días y en las colas de reintento hasta 30 segundos.
- Fallo repetido del consumidor: el mensaje se reintenta cada 30 segundos hasta 5 intentos y, al quinto fallo, queda en la cola de mensajes agotados de su cola de origen.
- Quinto fallo: el mensaje queda en una cola de agotados propia de la cola de origen, durable y retenida 14 días para inspección.
- `seller.notify` sin consumidor en Fase 1: los mensajes se acumulan y no se descartan por falta de consumidor antes de 7 días; al cumplirse 7 días caducan y se descartan.
- Publicación con una routing key no enlazada: el mensaje no llega a las colas del flujo y no se inventan rutas adicionales.
- Aplicación repetida de la topología: no debe duplicar exchanges, colas ni enlaces.
- Broker no disponible al aplicar la topología: no deben perderse mensajes ya publicados y la aplicación debe poder repetirse sin duplicar la topología.
- Reinicio del nodo con el volumen persistente conservado: las colas durables y los mensajes no consumidos que no hayan caducado deben recuperarse.

## Fuera de alcance

- Implementar en order-api el alta de pedido, el outbox, el relay de publicación de `order.placed` y la actualización del pedido con el resultado del stock.
- Implementar en catalog-api el consumo de `stock.reserve`, la reserva idempotente, la compensación de reservas parciales y la publicación de `stock.reserved` y `stock.rejected`.
- Implementar el consumidor del feed del vendedor que consumirá `seller.notify`; queda para la Fase 2.
- Implementar en cualquier repositorio productores o consumidores de estos eventos, incluido el conteo de intentos y el envío a la cola de agotados al quinto fallo.
- Pagos y todo lo relativo a payment-api.
- Kafka o cualquier sustitución del broker.
- Detalle de producto, tienda o storefront.
- Modificar el despliegue de RabbitMQ, sus recursos, su imagen o sus sondeos, más allá del cableado necesario para declarar la topología.
- Cambiar los manifiestos de los componentes de plataforma existentes o las políticas de red existentes.
- Exponer el puerto de administración de RabbitMQ o crear políticas de red nuevas.
- Declarar exchanges, colas o enlaces distintos de los definidos en esta spec.
- Cambiar los TTL acordados (30 segundos de reintento, 7 días de `seller.notify`, 14 días de las colas de agotados) o el máximo de 5 intentos.
- Crear secretos, usuarios o credenciales nuevos.

## Criterios de finalización

- En Minikube, la topología queda aplicada y se verifica que los exchanges `orders` y `stock`, las colas `stock.reserve`, `seller.notify` y `order.stock-results`, y sus enlaces existen.
- Publicar en `order.placed` entrega copia a `stock.reserve` y a `seller.notify`; publicar en `stock.reserved` o `stock.rejected` entrega en `order.stock-results`.
- Un fallo de consumidor en `stock.reserve` y en `order.stock-results` se reintenta con retardo fijo de 30 segundos, con un máximo de 5 intentos, y al quinto fallo el mensaje queda en `stock.reserve.dlq` u `order.stock-results.dlq` según su origen.
- Las colas de agotados son durables y retienen sus mensajes 14 días para inspección.
- Un reinicio del broker conserva las colas declaradas y los mensajes no consumidos que no hayan caducado.
- `seller.notify` existe sin consumidor en Fase 1, no descarta sus mensajes por falta de consumidor antes de 7 días y los descarta al cumplirse 7 días.
- En Hostinger, la renderización y validación del entorno muestran la misma topología, sin duplicar la definición completa.
- No hay secretos nuevos; se reutilizan el despliegue, el usuario `app` y las variables `RABBITMQ_*` existentes.
- Los sondeos de salud, los manifiestos de los componentes de plataforma y las políticas de red existentes quedan intactos.
- No quedan dudas abiertas: las tres preguntas originales están aceptadas y resueltas.

## Dudas abiertas

Ninguna. Las tres dudas originales quedaron aceptadas y resueltas en la sección «Decisiones resueltas».

## Decisiones resueltas

- ~~¿Cuántos reintentos como máximo y con qué retardo entre intentos deben aplicarse a `stock.reserve` y `order.stock-results`? ¿El retardo es fijo o creciente?~~
  **Respuesta:** máximo 5 intentos por mensaje con retardo fijo de 30 segundos, tanto para `stock.reserve` como para `order.stock-results`. Se usan las colas durables `stock.reserve.retry` y `order.stock-results.retry`, con TTL de 30 segundos, que devuelven el mensaje a su cola principal. Al quinto fallo el mensaje pasa a la cola de agotados correspondiente.
- ~~¿Qué debe ocurrir con los mensajes de `seller.notify` al no tener consumidor en Fase 1: se retienen sin límite, caducan tras un tiempo o tienen un límite de cantidad?~~
  **Respuesta:** `seller.notify` no tiene consumidor en Fase 1 y sus mensajes caducan a los 7 días por TTL de cola. No se descartan antes de esos 7 días solo porque no haya consumidor.
- ~~¿El destino de mensajes agotados debe ser uno por cola o uno compartido, con qué nombre, y cuánto tiempo se retienen esos mensajes para inspección?~~
  **Respuesta:** uno por cola fuente: `stock.reserve.dlq` y `order.stock-results.dlq`, ambos durables y con retención de 14 días para inspección.
