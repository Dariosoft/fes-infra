# Plan 004 — Topología RabbitMQ para la venta asíncrona

## Resumen

Declarar la topología de la Fase 1 como un recurso común de la base de plataforma,
`kubernetes/base/platform/rabbitmq-topology.yaml`, heredado por los overlays de Minikube y
Hostinger. La declaración se ejecuta con un Job idempotente que habla AMQP 0-9-1 contra el broker
existente por el puerto `5672` (ya permitido por la NetworkPolicy `platform-ingress`), sin exponer
el puerto de administración `15672`, sin tocar `kubernetes/base/platform/rabbitmq.yaml`, sus
sondeos ni las políticas de red, y reutilizando el usuario `app`, el vhost `friendly` y el secreto
`platform-secrets`/`rabbitmq-password` que ya existen.

El Job no implementa productores ni consumidores: solo declara exchanges, colas, argumentos y
enlaces. El reintento diferido se apoya en colas de reintento con TTL y el destino de agotados en
una cola durable por cola de consumo. El conteo de intentos (máximo 5) y el envío a la cola de
agotados al quinto fallo es un contrato de los consumidores de `fes-catalog-api` y
`fes-order-api`; este repositorio declara y documenta la topología que lo hace posible.

## Estado de partida

- `kubernetes/base/platform/rabbitmq.yaml` define el `Service` y el `StatefulSet` de RabbitMQ
  (`rabbitmq:4.2.9-management-alpine`, PVC de 5 Gi, probes `rabbitmq-diagnostics`). **No** declara
  exchanges, colas ni enlaces.
- `kubernetes/base/platform/network-policies.yaml` (`platform-ingress`) permite el puerto `5672`
  desde los namespaces `apps` y `platform`, y el `15672` solo desde `observability`. Por eso la
  declaración usa AMQP `5672` y no la API de management.
- `kubernetes/base/platform/kustomization.yaml` lista `postgresql.yaml`, `rabbitmq.yaml`,
  `minio.yaml` y `network-policies.yaml`; no incluye topología de mensajería.
- El usuario `app` y el vhost `friendly` vienen de `RABBITMQ_DEFAULT_USER` y
  `RABBITMQ_DEFAULT_VHOST` en `rabbitmq.yaml`. La contraseña vive en
  `platform-secrets`/`rabbitmq-password` en ambos overlays (Minikube local y Hostinger con
  `REPLACE_ME`); no se crea un secreto nuevo.
- `kubernetes/base/order-api/deployment.yaml` y `kubernetes/base/catalog-api/deployment.yaml` ya
  reciben `RABBITMQ_HOST`, `RABBITMQ_USERNAME=app` y `RABBITMQ_PASSWORD` desde `app-secrets`. No
  existe `RABBITMQ_PORT` ni `RABBITMQ_VHOST`; el plan no los agrega a las aplicaciones.
- `kubernetes/base/kustomization.yaml` incluye `platform`; ambos overlays heredan la base. La
  estructura base/overlay es la vía natural para una definición única (RF-23).
- `make verify` ejecuta `validate`, `lint`, `policy` y `consistency`; `policy/k8s.rego` exige
  límites, requests, `readinessProbe` y `runAsNonRoot` a todo workload, y
  `policy/production.rego` exige `livenessProbe` en Hostinger. `scripts/checks/consistency.py`
  valida `secretKeyRef` contra el placeholder de Hostinger.
- `docs/stack.md` (sección «Mensajería») y `docs/validation.md` son los lugares vigentes para
  documentar la topología y su verificación. Nada de esto se implementa en los repositorios de las
  aplicaciones.

## Alcance y límites

**En alcance (este repositorio `infra`):**

- `kubernetes/base/platform/rabbitmq-topology.yaml`: `ConfigMap` con el declarador idempotente y
  `Job` que lo ejecuta.
- `kubernetes/base/platform/kustomization.yaml`: agregar el recurso anterior.
- Ajuste de `scripts/deploy/deploy.sh` para esperar a que el Job termine en Minikube.
- Documentación operativa en `docs/` (topología, TTL, reintento, agotados y contrato de
  consumidores).
- Verificación con `make validate`, `make policy`, `make consistency`, `make deploy`,
  `make smoke-test` y pruebas manuales contra RabbitMQ.

**Fuera de alcance (respeta la spec):**

- Implementar productores, consumidores, outbox o el conteo de intentos en `fes-order-api` o
  `fes-catalog-api`.
- Cambiar `kubernetes/base/platform/rabbitmq.yaml` (imagen, recursos, PVC, probes, usuario o
  vhost).
- Cambiar `kubernetes/base/platform/network-policies.yaml`, exponer `15672` o crear
  NetworkPolicies.
- Cambiar `platform-secrets` / `app-secrets`, SOPS o cualquier credencial.
- Cambiar los TTL acordados (`30 s`, `7 días`, `14 días`) o el máximo de 5 intentos.
- Declarar exchanges, colas o enlaces fuera del contrato de la spec.
- Kafka, pagos, storefront o detalle de producto.

## Topología declarada

### Exchanges

| Exchange | Tipo | Durable | Uso |
|---|---|---|---|
| `orders` | topic | sí | Eventos de pedido; routing key `order.placed` |
| `stock` | topic | sí | Resultados de stock; routing keys `stock.reserved` y `stock.rejected` |

No se agregan exchanges nuevos: las colas de reintento y de agotados se resuelven con el exchange
por defecto (`""`), que enruta por nombre de cola. Así `orders` y `stock` conservan exactamente su
contrato actual (RF-1, RF-6, RF-23).

### Colas y argumentos

| Cola | Durable | Argumentos | Enlaces |
|---|---|---|---|
| `stock.reserve` | sí | `x-dead-letter-exchange: ""`, `x-dead-letter-routing-key: stock.reserve.retry` | `orders` / `order.placed` |
| `seller.notify` | sí | `x-message-ttl: 604800000` (7 días) | `orders` / `order.placed` |
| `order.stock-results` | sí | `x-dead-letter-exchange: ""`, `x-dead-letter-routing-key: order.stock-results.retry` | `stock` / `stock.reserved` y `stock` / `stock.rejected` |
| `stock.reserve.retry` | sí | `x-message-ttl: 30000` (30 s), `x-dead-letter-exchange: ""`, `x-dead-letter-routing-key: stock.reserve` | implícito por exchange por defecto |
| `stock.reserve.dlq` | sí | `x-message-ttl: 1209600000` (14 días) | implícito por exchange por defecto |
| `order.stock-results.retry` | sí | `x-message-ttl: 30000` (30 s), `x-dead-letter-exchange: ""`, `x-dead-letter-routing-key: order.stock-results` | implícito por exchange por defecto |
| `order.stock-results.dlq` | sí | `x-message-ttl: 1209600000` (14 días) | implícito por exchange por defecto |

Los valores de TTL se expresan en milisegundos, que es la unidad que espera RabbitMQ en
`x-message-ttl`: `30 000`, `604 800 000` y `1 209 600 000`.

### Reintento y agotados

1. Un consumidor de `stock.reserve` u `order.stock-results` que falla hace `basic_nack`/`reject`
   con `requeue=false` (o publica explícitamente en la cola de reintento).
2. La cola principal tiene como DLX el exchange por defecto y como routing key su cola
   `.retry`; el mensaje queda retenido 30 segundos en `stock.reserve.retry` o
   `order.stock-results.retry`.
3. Al expirar el TTL, la cola de reintento lo devuelve por el exchange por defecto a su cola
   principal (`stock.reserve` u `order.stock-results`).
4. RabbitMQ acumula la traza en la cabecera `x-death` en cada ciclo. El consumidor calcula
   `intentos = entradas de x-death de la cola .retry + 1`; al quinto fallo publica el mensaje en la
   cola de agotados correspondiente (`stock.reserve.dlq` u `order.stock-results.dlq`) por el
   exchange por defecto y luego hace ACK, para no reintentarlo indefinidamente.
5. Las colas de agotados son durables y retienen sus mensajes 14 días para inspección.

La topología no puede contar intentos por sí sola sin consumidores; por eso la spec deja el
consumo fuera de alcance. El plan fija el contrato observable y deja las colas listas para que los
consumidores lo cumplan (RF-14 a RF-18).

### `seller.notify`

- Existe sin consumidor en Fase 1 (RF-4, RF-19).
- `x-message-ttl` de 7 días: los mensajes no se descartan por falta de consumidor antes de ese
  plazo y caducan al cumplirlo (RF-19, RF-20).

## Diseño de la declaración

### `ConfigMap` `rabbitmq-topology`

- Namespace `platform`, nombre `rabbitmq-topology`, clave `topology.py`.
- Script Python con `pika` que:
  1. Espera la conexión AMQP con reintentos acotados (por ejemplo, 60 intentos cada 2 s).
  2. Declara `orders` y `stock` como topic durables.
  3. Declara las siete colas con `durable=True` y los argumentos de la tabla.
  4. Declara los cuatro enlaces del contrato.
  5. No declara consumidores ni publica mensajes de negocio.
- Es idempotente: volver a declarar los mismos exchanges, colas, argumentos y enlaces no crea
  duplicados; RabbitMQ devuelve el mismo recurso (RF-31).
- Si los argumentos de una cola existente no coinciden, el broker responde
  `PRECONDITION_FAILED`; el Job falla de forma visible en lugar de recrear o borrar la cola.

### `Job` `rabbitmq-topology`

- Namespace `platform`, `backoffLimit` acotado, `ttlSecondsAfterFinished` para que un despliegue
  posterior pueda recrearlo y `activeDeadlineSeconds` como cota.
- Imagen pública fijada `python:3.12.7-alpine` (tag explícito, sin `latest`). El contenedor instala
  `pika==1.3.2` en `/tmp/deps` y ejecuta el script montado; no se construye ni publica una imagen
  nueva.
- Variables reutilizadas: `RABBITMQ_HOST=rabbitmq.platform.svc.cluster.local`,
  `RABBITMQ_USERNAME=app` y `RABBITMQ_PASSWORD` desde
  `platform-secrets`/`rabbitmq-password`. El puerto `5672` y el vhost `friendly` quedan como
  valores del script, igual que en la plataforma actual.
- Variables de soporte del contenedor para no escribir en la raíz: `HOME=/tmp`,
  `PIP_CACHE_DIR=/tmp/pip`, `PYTHONPATH=/tmp/deps` y `PYTHONDONTWRITEBYTECODE=1`, con un
  `emptyDir` montado en `/tmp`.
- Postura: `automountServiceAccountToken: false`, `runAsNonRoot`, `runAsUser` no privilegiado,
  `seccompProfile: RuntimeDefault`, capacidades `ALL` descartadas, `resources.requests/limits`,
  `readinessProbe` y `livenessProbe` (`exec: ["true"]`) para cumplir `policy/k8s.rego` y
  `policy/production.rego`.
- `readOnlyRootFilesystem` con `emptyDir` en `/tmp` para la instalación de `pika`.
- El Job se aplica desde la base, de modo que Minikube y Hostinger reciben exactamente la misma
  definición (RF-21, RF-22, RF-23).

### Integración con el despliegue

- `kubernetes/base/platform/kustomization.yaml` agrega `rabbitmq-topology.yaml`; no se duplica en
  los overlays.
- `scripts/deploy/deploy.sh` espera, después del rollout de `statefulset/rabbitmq`, a que el Job
  `rabbitmq-topology` complete. Si RabbitMQ tarda en aceptar conexiones, el script del Job
  reintenta; el Job no se considera exitoso hasta declarar toda la topología.
- En Hostinger, el mismo Job queda en el render del overlay; el procedimiento de
  `docs/hostinger.md` indica verificar su finalización antes de dar por desplegada la topología.
- Si el volumen del broker se pierde y el Job ya está `Completed`, se borra el Job y se vuelve a
  aplicar; no se modifica el broker ni se recrean colas a mano.

## Paridad Minikube / Hostinger

- Una sola definición en `kubernetes/base/platform/rabbitmq-topology.yaml`; ambos overlays la
  heredan (RF-21, RF-22, RF-23).
- La imagen `python:3.12.7-alpine` y la versión `pika==1.3.2` son iguales en ambos entornos.
- No se agrega nada al bloque `images:` de Hostinger porque la imagen no es propia.
- El secreto y las variables reutilizados existen en ambos overlays: Minikube con valores locales
  y Hostinger con `REPLACE_ME` hasta el despliegue real (RF-24 a RF-27).
- No se tocan `rabbitmq.yaml`, sus probes ni `network-policies.yaml` (RF-28 a RF-30).

## Seguridad y postura

- Sin secretos nuevos: se referencia `platform-secrets`/`rabbitmq-password`, ya declarado en el
  placeholder de Hostinger y en el secreto local de Minikube.
- Sin acceso al puerto de management: la declaración usa `5672`, que la NetworkPolicy ya permite
  desde `platform`.
- El Job no monta el token de la cuenta de servicio y corre sin privilegios.
- No se imprime la contraseña en logs; el script solo reporta nombres de recursos declarados.
- `make policy` sigue evaluando el Job con las mismas reglas que el resto de workloads.

## Verificación

1. `kustomize build kubernetes/overlays/minikube` y `kustomize build
   kubernetes/overlays/hostinger` muestran un único `ConfigMap` y un único `Job` de topología.
2. `make validate` (kubeconform estricto) y `make policy` en verde en ambos overlays.
3. `make consistency` en verde: el `secretKeyRef` del Job existe en el placeholder de Hostinger y
   no se agregan directorios de base sin `kustomization`.
4. En Minikube, tras `make deploy`, el Job termina en `Completed`. Con un port-forward temporal a
   `service/rabbitmq 15672:15672` (acceso de inspección que ya documenta el README), listar
   exchanges, colas, argumentos y enlaces y compararlos con la tabla.
5. Publicar un mensaje de prueba en `orders`/`order.placed`: aparece una copia en `stock.reserve` y
   en `seller.notify`. Publicar en `stock`/`stock.reserved` y `stock`/`stock.rejected`: aparece en
   `order.stock-results`. Publicar en una routing key no enlazada: no aparece en ninguna de las
   tres colas (RF-10, RF-32).
6. Simular fallos con un consumidor temporal: cada uno de los primeros `nack` lleva el mensaje a
   la cola `.retry`, se redelivera no antes de 30 segundos y, al quinto fallo, el mensaje se
   publica en la `.dlq`; la `.dlq` declara `x-message-ttl` de 14 días (RF-14 a RF-18).
7. Publicar en `seller.notify` sin consumidor: el mensaje permanece, la cola declara 7 días de TTL
   y no se descarta antes por falta de consumidor (RF-19, RF-20).
8. Reiniciar `statefulset/rabbitmq` con mensajes no consumidos: las colas y los mensajes no
   caducados siguen presentes (RF-11, RF-12).
9. Repetir la aplicación del Job: no aparecen exchanges, colas ni enlaces duplicados y no hay
   `PRECONDITION_FAILED` (RF-31).
10. `make verify` completo en verde, sin cambios en `rabbitmq.yaml`, probes o NetworkPolicies.

## Mapa RF → trabajo

| RF | Piezas del plan |
|---|---|
| RF-1, RF-6 | Exchanges `orders` y `stock` en la tabla y en el script |
| RF-2, RF-4, RF-7 | Colas durables `stock.reserve`, `seller.notify` y `order.stock-results` |
| RF-3, RF-5, RF-8, RF-9 | Enlaces de la tabla y del script |
| RF-10 | Enlaces topic; fan-out verificado con publicación de prueba |
| RF-11, RF-12 | Colas durables y PVC existente; prueba de reinicio del broker |
| RF-13 | Retención por consumo, TTL o paso a agotados |
| RF-14, RF-15 | `stock.reserve.retry` (TTL 30 s) y `stock.reserve.dlq` (14 días) |
| RF-16, RF-17 | `order.stock-results.retry` (TTL 30 s) y `order.stock-results.dlq` (14 días) |
| RF-18 | TTL de 30 s en ambas colas de reintento |
| RF-19 | `seller.notify` sin consumidor y sin descarte por falta de consumidor antes de 7 días |
| RF-20 | `x-message-ttl` de 7 días en `seller.notify` |
| RF-21, RF-22 | Recurso de base heredado por ambos overlays |
| RF-23 | Una sola definición en `kubernetes/base/platform` |
| RF-24, RF-25 | Se reutilizan `rabbitmq.yaml`, usuario `app` y vhost `friendly` |
| RF-26 | `RABBITMQ_HOST`, `RABBITMQ_USERNAME`, `RABBITMQ_PASSWORD` |
| RF-27 | `platform-secrets`/`rabbitmq-password`, sin claves nuevas |
| RF-28, RF-29 | Sin cambios en `rabbitmq.yaml` ni en sus probes |
| RF-30 | Sin cambios en `network-policies.yaml`; AMQP por `5672` |
| RF-31 | Declaración idempotente y Job reaplicable |
| RF-32 | Sin bindings comodín; routing keys exactas |

## Criterios de verificación

- El `ConfigMap` y el `Job` aparecen una sola vez en cada overlay.
- El Job completa contra RabbitMQ sin intervención manual después del rollout del broker.
- La tabla de exchanges, colas, argumentos y enlaces coincide con la observada en el broker.
- Los TTL observados son `30 000`, `604 800 000` y `1 209 600 000` ms.
- No hay exchanges nuevos: los reintentos y los agotados usan el exchange por defecto.
- `rabbitmq.yaml`, sus probes y `network-policies.yaml` quedan idénticos.
- No hay secretos, usuarios ni credenciales nuevos.
- `make verify` en verde; `make smoke-test` sigue en verde cuando el clúster local está disponible.

## Notas

- La spec no tiene dudas abiertas; este plan no introduce decisiones de producto nuevas.
- El conteo de intentos es un contrato de los consumidores: la topología expone la cola de
  reintento y la de agotados, pero no ejecuta lógica de consumo. Esto respeta el fuera de alcance
  de la spec y la propiedad de `fes-order-api` y `fes-catalog-api`.
- No se usa la API de management (`15672`) porque la NetworkPolicy solo la permite desde
  `observability`; el Job declara por AMQP (`5672`), que la plataforma ya abre a `apps` y
  `platform`.
- El exchange por defecto evita agregar exchanges de infraestructura y mantiene `orders` y `stock`
  limitados a su contrato de dominio.
