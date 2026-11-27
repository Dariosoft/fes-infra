# UML 004 — Topología RabbitMQ para la venta asíncrona

Diagramas del desarrollo descrito por `plan.md` y `tasks.md` en la rama
`004/feat-rabbitmq-sale-topology`. El corte es de infraestructura: no agrega clases ni capas de
aplicación, sino un recurso de base que declara exchanges, colas, argumentos y enlaces en el
RabbitMQ existente. Los diagramas muestran la estructura de esa declaración y los flujos de
publicación, reintento y agotado.

Los nombres reales del contrato se conservan: exchange `orders` (topic, durable) con routing key
`order.placed`; colas `stock.reserve` y `seller.notify`; exchange `stock` (topic, durable) con
routing keys `stock.reserved` y `stock.rejected`; cola `order.stock-results`; usuario `app` y vhost
`friendly` en el puerto AMQP `5672`. No se agregan exchanges nuevos: los reintentos y las colas de
agotados usan el exchange por defecto (`""`).

## Estructura: base, overlays y recursos de topología

```mermaid
flowchart TB
  subgraph base["kubernetes/base/platform"]
    KUST["kustomization.yaml<br/>resources: ... rabbitmq-topology.yaml"]
    RB["rabbitmq.yaml<br/>StatefulSet rabbitmq<br/>app / vhost friendly / AMQP 5672"]
    NP["network-policies.yaml<br/>platform-ingress<br/>5672 desde apps y platform"]
    TOPO["rabbitmq-topology.yaml<br/>ConfigMap rabbitmq-topology<br/>Job rabbitmq-topology"]
    SEC["platform-secrets<br/>rabbitmq-password"]
  end

  subgraph mk["kubernetes/overlays/minikube"]
    DEP["scripts/deploy/deploy.sh<br/>aplica overlay y espera el Job"]
    MKS["resources/secrets.yaml<br/>platform-secrets local"]
  end

  subgraph ho["kubernetes/overlays/hostinger"]
    HOD["docs/hostinger.md<br/>apply manual y verificación"]
    HOS["secrets.placeholder.yaml<br/>rabbitmq-password: REPLACE_ME"]
  end

  KUST --> TOPO
  TOPO -->|"AMQP 5672"| RB
  RB --- NP
  TOPO -->|"secretKeyRef"| SEC
  MKS -.->|"mismo contrato"| SEC
  HOS -.->|"mismo contrato"| SEC
  DEP -.->|"make deploy"| KUST
  HOD -.->|"kubectl apply"| KUST
```

Nota: el `Job` vive en la base y hereda a ambos overlays; no se duplica la definición. La imagen
`python:3.12.7-alpine` instala `pika==1.3.2` en `/tmp/deps` y ejecuta el script del `ConfigMap`.
La NetworkPolicy no se modifica: la declaración usa `5672`, no el puerto de management `15672`.

## Flujo principal: despliegue y declaración idempotente

```mermaid
sequenceDiagram
  autonumber
  actor OP as Operador
  participant KZ as kustomize build
  participant API as API server
  participant CM as ConfigMap rabbitmq-topology
  participant JOB as Job rabbitmq-topology (platform)
  participant RMQ as RabbitMQ rabbitmq.platform:5672

  OP->>KZ: make deploy / kubectl apply (overlay del entorno)
  KZ-->>API: StatefulSet rabbitmq + ConfigMap + Job
  API->>CM: monta topology.py en /opt/rabbitmq-topology
  API->>JOB: crea el Job (platform)
  JOB->>JOB: pip install pika==1.3.2 en /tmp/deps
  loop hasta conectar o agotar reintentos
    JOB->>RMQ: AMQP connect (app / friendly)
  end
  JOB->>RMQ: declare exchange orders (topic, durable)
  JOB->>RMQ: declare exchange stock (topic, durable)
  JOB->>RMQ: declare colas + x-message-ttl + x-dead-letter-*
  JOB->>RMQ: queue_bind (order.placed, stock.reserved, stock.rejected)
  JOB-->>API: exit 0, Job Completed
  Note over JOB,RMQ: Reaplicar la misma declaración no duplica recursos.<br/>Si los argumentos no coinciden, el broker responde PRECONDITION_FAILED.
```

## Flujo de negocio: pedido, reserva y resultados

```mermaid
flowchart LR
  OA["fes-order-api"] -->|"order.placed"| OE[["orders<br/>topic durable"]]
  OE -->|"order.placed"| SQ["stock.reserve"]
  OE -->|"order.placed"| SN["seller.notify<br/>x-message-ttl=604800000"]
  SQ --> CA["fes-catalog-api"]
  CA -->|"stock.reserved"| SE[["stock<br/>topic durable"]]
  CA -->|"stock.rejected"| SE
  SE -->|"stock.reserved"| OSR["order.stock-results"]
  SE -->|"stock.rejected"| OSR
  OSR --> OA
  SN -.->|"sin consumidor en Fase 1"| F2["Fase 2 / feed del vendedor"]
```

## Secuencia de reintento y agotado

```mermaid
sequenceDiagram
  autonumber
  participant C as Consumidor (catalog-api u order-api)
  participant Q as Cola principal (stock.reserve / order.stock-results)
  participant R as Cola .retry (TTL 30000)
  participant D as Cola .dlq (TTL 1209600000)

  C->>Q: deliver (intento 1)
  C->>Q: basic_nack requeue=false
  Q->>R: dead-letter (exchange "" / routing key cola.retry)
  Note over R: retiene el mensaje 30 segundos
  R->>Q: dead-letter al expirar (exchange "" / routing key cola)
  C->>Q: deliver (intentos 2 a 5)
  alt quinto fallo
    C->>D: publish en cola.dlq (exchange "")
    Note over D: retiene 14 días para inspección
  else fallo antes del quinto
    C->>Q: basic_nack requeue=false
    Q->>R: nuevo ciclo de 30 segundos
  end
```

El conteo de intentos es un contrato del consumidor: RabbitMQ acumula la traza en la cabecera
`x-death` y el consumidor decide el paso a la `.dlq` al quinto fallo. La topología no ejecuta
consumidores; solo declara la ruta de reintento, la demora y el destino de agotados.

## Secuencia de `seller.notify` sin consumidor

```mermaid
sequenceDiagram
  autonumber
  participant OA as fes-order-api
  participant OE as orders
  participant SN as seller.notify
  participant F2 as Consumidor Fase 2 (ausente)

  OA->>OE: publish order.placed
  OE->>SN: copia (routing key order.placed)
  Note over SN: x-message-ttl=604800000 (7 días)
  alt antes de 7 días
    Note over SN: el mensaje se retiene; no se descarta por falta de consumidor
  else al cumplir 7 días
    SN-->>SN: el mensaje caduca y se descarta
  end
  F2--xSN: consumo solo en Fase 2
```

## Recurso declarado

| Elemento | Tipo | Durable | Argumentos / enlace |
|---|---|---|---|
| `orders` | exchange topic | sí | routing key `order.placed` |
| `stock` | exchange topic | sí | routing keys `stock.reserved`, `stock.rejected` |
| `stock.reserve` | cola | sí | DLX `""` → `stock.reserve.retry`; bound a `orders`/`order.placed` |
| `seller.notify` | cola | sí | `x-message-ttl: 604800000`; bound a `orders`/`order.placed` |
| `order.stock-results` | cola | sí | DLX `""` → `order.stock-results.retry`; bound a `stock`/`stock.reserved` y `stock`/`stock.rejected` |
| `stock.reserve.retry` | cola | sí | `x-message-ttl: 30000`; DLX `""` → `stock.reserve` |
| `stock.reserve.dlq` | cola | sí | `x-message-ttl: 1209600000` |
| `order.stock-results.retry` | cola | sí | `x-message-ttl: 30000`; DLX `""` → `order.stock-results` |
| `order.stock-results.dlq` | cola | sí | `x-message-ttl: 1209600000` |

Variables reutilizadas por el `Job`: `RABBITMQ_HOST=rabbitmq.platform.svc.cluster.local`,
`RABBITMQ_USERNAME=app` y `RABBITMQ_PASSWORD` desde `platform-secrets`/`rabbitmq-password`. El
puerto `5672` y el vhost `friendly` quedan fijos en el script, igual que en la plataforma actual.
No se crean secretos, usuarios ni exchanges nuevos.
