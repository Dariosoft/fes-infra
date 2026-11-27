# Spec 005 — Kafka KRaft, topic de pedidos y despliegue de analítica y notificaciones

## Contexto y objetivo

La Fase 2 del proceso de venta asíncrono introduce Kafka como log durable de eventos de dominio.
Este corte despliega un broker Kafka en modo KRaft, declara el topic `orders.events` y pone en
marcha los servicios `analytics-api` y `notifications-api` con sus bases y conexiones, sin
implementar consumidores ni productores. El resultado es la plataforma lista para que `order-api`
publique y los dos servicios nuevos consuman.

## Usuarios / actores

- Operador de infraestructura que despliega Minikube o Hostinger.
- `order-api`, que publica `order.placed` en Kafka.
- `analytics-api` y `notifications-api`, que consumen `orders.events`.
- `notifications-api`, que consume la cola RabbitMQ `seller.notify`.
- `panel-api`, que proxya a los dos servicios nuevos.
- Responsable de seguridad, que administra secretos existentes y nuevos de base de datos.

## Historias de usuario

- H1: Como `order-api` quiero un broker Kafka disponible para publicar eventos de dominio.
- H2: Como `analytics-api` quiero consumir `orders.events` con un topic estable y durable.
- H3: Como `notifications-api` quiero consumir `orders.events` y `seller.notify` con la misma topología en ambos entornos.
- H4: Como `panel-api` quiero URLs de los servicios nuevos para proxyar el panel.
- H5: Como operador quiero que un despliegue limpio arranque Kafka y el topic antes que las aplicaciones.

## Requisitos funcionales (criterios de aceptación en EARS)

- RF-1: EL SISTEMA dispondrá de un broker Kafka en modo KRaft con un único nodo combinado de controller y broker.
- RF-2: EL SISTEMA conservará los datos de Kafka en un volumen persistente al reiniciar el pod.
- RF-3: EL SISTEMA expondrá Kafka en el Service `kafka.platform.svc.cluster.local:9092` para los namespaces de aplicaciones.
- RF-4: CUANDO se aplique la topología, EL SISTEMA declarará el topic `orders.events` con 3 particiones, factor de replicación 1 y retención de 7 días.
- RF-5: CUANDO se aplique la topología más de una vez, EL SISTEMA no duplicará el topic ni fallará por existir.
- RF-6: EL SISTEMA ejecutará la declaración del topic en un `Job` idempotente que espera la readiness de Kafka.
- RF-7: EL SISTEMA creará las bases `analytics` y `notifications` con usuarios propios en el PostgreSQL compartido.
- RF-8: EL SISTEMA desplegará `analytics-api` y `notifications-api` en el namespace `apps`, con puerto 8080 y sondas en `/actuator/health/liveness` y `/actuator/health/readiness`.
- RF-9: CUANDO arranque un pod de `analytics-api`, `notifications-api`, `order-api` o `catalog-api`, EL SISTEMA esperará a que `job/kafka-topology` exista y complete antes de iniciar el contenedor principal.
- RF-10: EL SISTEMA entregará a `order-api` la variable `KAFKA_BOOTSTRAP_SERVERS` con el Service de Kafka.
- RF-11: EL SISTEMA entregará a `analytics-api` `KAFKA_BOOTSTRAP_SERVERS` y `DATABASE_*`.
- RF-12: EL SISTEMA entregará a `notifications-api` `KAFKA_BOOTSTRAP_SERVERS`, `RABBITMQ_*` y `DATABASE_*`.
- RF-13: EL SISTEMA entregará a `panel-api` `ANALYTICS_API_BASE_URL` y `NOTIFICATIONS_API_BASE_URL`.
- RF-14: EL SISTEMA permitirá el tráfico de los pods de `apps` hacia Kafka en el puerto 9092 y de los dos servicios nuevos hacia PostgreSQL y OTel.
- RF-15: EL SISTEMA permitirá a `notifications-api` conectarse a RabbitMQ en el puerto 5672.
- RF-16: CUANDO se ejecute `make deploy`, EL SISTEMA desplegará Kafka y esperará el `Job` de topics antes de aplicar las aplicaciones.
- RF-17: EL SISTEMA aplicará la misma topología de Kafka y los mismos topics en Minikube y Hostinger desde la base, sin duplicar manifiestos.
- RF-18: EL SISTEMA conservará sin cambios los despliegues, sondas y políticas de red existentes que no pertenecen a este corte.
- RF-19: EL SISTEMA no incluirá credenciales en claro en manifiestos ni en logs.
- RF-20: EL SISTEMA declarará las colas durables `seller.notify.retry` (TTL 30 s) y `seller.notify.dlq` (retención 14 días) para el consumidor de `notifications-api`, sin cambiar los argumentos existentes de `seller.notify`.

## Requisitos no funcionales

- Broker único con KRaft, sin Zookeeper.
- Imagen de Kafka fijada por tag; sin `latest`.
- Persistencia durable para el broker.
- Paridad Minikube / Hostinger desde la base Kustomize.
- Sin autenticación SASL ni TLS internos en este corte; el acceso queda dentro del clúster.

## Casos límite

- Reinicio del broker con datos en el volumen: el topic y los mensajes retenidos sobreviven.
- Pérdida del volumen: el `Job` recrea el topic en el siguiente despliegue.
- Aplicación repetida del `Job`: no duplica el topic.
- Kafka no disponible al declarar el topic: el `Job` reintenta y falla visiblemente.
- Pods de aplicaciones creados antes del `Job`: quedan en `Init`, no en `CrashLoopBackOff`.
- Topic con particiones o retención distintas: el `Job` falla visiblemente en lugar de recrear datos.

## Fuera de alcance

- Implementar productores o consumidores en las APIs.
- Declarar topics distintos de `orders.events`.
- Habilitar SASL, TLS o múltiples brokers.
- Schema Registry y contratos Avro/Protobuf.
- Cambiar la topología RabbitMQ existente.
- Cambiar el comportamiento HTTP de las aplicaciones.

## Criterios de finalización

- `kustomize build` de ambos overlays renderiza Kafka, el topic `Job`, las dos bases, los dos despliegues y las envs.
- `make validate`, `make policy`, `make lint` y `make consistency` en verde.
- `make deploy` deja Kafka listo, el `Job` completo y `analytics-api`/`notifications-api` saludables.
- El topic `orders.events` existe con 3 particiones y retención de 7 días.

## Dudas abiertas

Ninguna.
