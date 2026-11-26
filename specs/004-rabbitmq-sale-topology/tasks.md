# Tareas 004 — Topología RabbitMQ para la venta asíncrona

Ordenadas por dependencia. Cada tarea ~20–30 min. Solo se declara topología y cableado; no se
implementan productores ni consumidores.

## Relevamiento y diseño

- [x] **T1. Confirmar contratos, credenciales y restricciones de plataforma**
  - Cubierta: RF-1, RF-2, RF-4, RF-6, RF-7, RF-24, RF-25, RF-26, RF-27, RF-28, RF-29, RF-30
  - Revisar `kubernetes/base/platform/rabbitmq.yaml`, `network-policies.yaml`, las
    `kustomization.yaml` de base y overlays, y `platform-secrets` en Minikube y Hostinger.
    Confirmar usuario `app`, vhost `friendly`, puerto `5672`, PVC de 5 Gi y que la NetworkPolicy
    solo permite `15672` desde `observability`.
  - Done when: quedan anotados los nombres, argumentos y restricciones exactas, y se confirma que
    no existe ninguna declaración previa de exchanges, colas o enlaces.

- [x] **T2. Fijar la tabla de topología y los TTL en milisegundos**
  - Cubierta: RF-1 a RF-9, RF-13 a RF-20
  - Escribir la tabla definitiva de exchanges, colas, argumentos y enlaces con los valores
    `30000`, `604800000` y `1209600000` ms y las routing keys `order.placed`, `stock.reserved` y
    `stock.rejected`.
  - Done when: la tabla coincide con la spec y no aparecen exchanges ni colas fuera del contrato.

## Declaración de topología

- [x] **T3. Crear el script declarativo idempotente `topology.py`**
  - Cubierta: RF-1 a RF-10, RF-13 a RF-20, RF-31, RF-32
  - En `kubernetes/base/platform/rabbitmq-topology.yaml`, crear el `ConfigMap` con un script
    Python que use `pika`, espere la conexión AMQP, declare `orders` y `stock`, declare las siete
    colas con sus argumentos y cree los cuatro enlaces exactos. Sin consumidores ni publicación de
    mensajes de negocio, sin routing keys comodín.
  - Done when: el script declara toda la tabla, usa el exchange por defecto para reintentos y
    agotados, y una segunda ejecución no produce duplicados ni `PRECONDITION_FAILED`.

- [x] **T4. Crear el `Job` `rabbitmq-topology` con postura de seguridad**
  - Cubierta: RF-21, RF-22, RF-23, RF-24, RF-25, RF-26, RF-27, RF-28, RF-29, RF-30
  - En el mismo archivo, agregar el `Job` en `platform`: imagen `python:3.12.7-alpine`, instalación
    fijada `pika==1.3.2` en `/tmp/deps`, variables `RABBITMQ_HOST`, `RABBITMQ_USERNAME` y
    `RABBITMQ_PASSWORD` desde `platform-secrets`; `HOME=/tmp`, `PIP_CACHE_DIR=/tmp/pip`,
    `PYTHONPATH=/tmp/deps`, `PYTHONDONTWRITEBYTECODE=1`, `emptyDir` en `/tmp`, `runAsNonRoot`,
    `automountServiceAccountToken: false`, límites/requests, `readinessProbe`, `livenessProbe`,
    `backoffLimit` y `ttlSecondsAfterFinished`.
  - Done when: `kubeconform -strict` acepta el Job y `make policy` no reporta hallazgos para él en
    ninguno de los dos overlays.

- [x] **T5. Registrar el recurso en la base de plataforma**
  - Cubierta: RF-21, RF-22, RF-23
  - Agregar `rabbitmq-topology.yaml` a `kubernetes/base/platform/kustomization.yaml` sin duplicar
    la definición en los overlays ni crear directorios de base nuevos.
  - Done when: `kustomize build kubernetes/overlays/minikube` y `kustomize build
    kubernetes/overlays/hostinger` muestran exactamente un `ConfigMap` y un `Job` de topología.

- [ ] **T6. Integrar la espera del Job en el despliegue local**
  - Cubierta: RF-21, RF-23
  - En `scripts/deploy/deploy.sh`, después de `wait_rollout platform statefulset/rabbitmq`,
    esperar a que `job/rabbitmq-topology` complete; si el Job no existe todavía, aplicar primero y
    luego esperar.
  - Done when: `make deploy` no termina hasta que la topología está declarada y el Job queda
    `Completed`.

## Salvaguardas de la entrega

- [x] **T7. Verificar que no se tocan broker, probes ni red**
  - Cubierta: RF-24 a RF-30
  - Comparar `kubernetes/base/platform/rabbitmq.yaml` y `network-policies.yaml` con el estado
    previo; revisar que no haya cambios en imagen, recursos, PVC, probes, usuario, vhost ni reglas
    de red, y que no se agreguen claves a `platform-secrets` o `app-secrets`.
  - Done when: el diff del corte no incluye `rabbitmq.yaml`, `network-policies.yaml` ni secretos, y
    solo agrega el archivo de topología, su entrada en la kustomization, la espera del script y la
    documentación.

- [ ] **T8. Revisar idempotencia y ausencia de comodines**
  - Cubierta: RF-31, RF-32
  - Repetir la declaración con el Job y comprobar que no se duplican exchanges, colas ni enlaces;
    revisar que las routing keys de los enlaces sean exactamente las cuatro del contrato y que no
    haya `#` ni `*`.
  - Done when: dos ejecuciones seguidas terminan en `Completed` sin errores y la lista de enlaces
    del broker coincide con la tabla, sin entradas adicionales.

## Verificación funcional en Minikube

- [ ] **T9. Verificar exchanges, colas, argumentos y enlaces**
  - Cubierta: RF-1 a RF-10, RF-21
  - Con `make deploy` y un port-forward temporal a `service/rabbitmq 15672:15672`, listar
    exchanges, colas, argumentos y enlaces; comparar con la tabla y con los TTL en milisegundos.
  - Done when: existen `orders`, `stock`, las siete colas y los cuatro enlaces, con los argumentos
    `x-message-ttl` y `x-dead-letter-*` esperados.

- [ ] **T10. Verificar fan-out y routing keys no enlazadas**
  - Cubierta: RF-10, RF-32
  - Publicar un mensaje de prueba en `orders`/`order.placed` y comprobar una copia en
    `stock.reserve` y otra en `seller.notify`; publicar en `stock`/`stock.reserved` y
    `stock`/`stock.rejected` y comprobar `order.stock-results`; publicar en una routing key no
    enlazada y comprobar que no llega a las tres colas.
  - Done when: las tres pruebas muestran el destino esperado y ningún mensaje no enlazado aparece
    en las colas del flujo.

- [ ] **T11. Verificar reintento de 30 segundos y quinto fallo a DLQ**
  - Cubierta: RF-13 a RF-18
  - Con un consumidor temporal, hacer `nack` con `requeue=false` sobre `stock.reserve` y
    `order.stock-results`; medir que la redelivery no ocurre antes de 30 segundos, contar los
    intentos con `x-death` y publicar en `stock.reserve.dlq` u `order.stock-results.dlq` al quinto
    fallo.
  - Done when: los fallos previos al quinto pasan por la cola `.retry`, el retardo es de 30
    segundos y el quinto fallo deja el mensaje en la `.dlq` correspondiente, con `x-message-ttl`
    de 14 días.

- [ ] **T12. Verificar `seller.notify` sin consumidor y TTL de 7 días**
  - Cubierta: RF-19, RF-20
  - Publicar un mensaje en `seller.notify` y comprobar que permanece en la cola sin consumidor;
    revisar que `x-message-ttl` sea `604800000` y que no exista ningún consumidor en Fase 1.
  - Done when: el mensaje no se descarta por falta de consumidor antes de 7 días y la cola declara
    el TTL acordado.

- [ ] **T13. Verificar durabilidad tras reinicio del broker**
  - Cubierta: RF-11, RF-12, RF-13
  - Publicar mensajes de prueba en las colas principales, reiniciar
    `statefulset/rabbitmq` y comprobar que las colas y los mensajes no caducados siguen presentes.
  - Done when: tras el reinicio se conservan las colas declaradas y los mensajes no consumidos que
    no hayan expirado, y el Job puede reaplicarse sin duplicar nada.

## Paridad y cierre

- [x] **T14. Verificar la paridad de Hostinger sin aplicar el entorno**
  - Cubierta: RF-21 a RF-30
  - Ejecutar `kustomize build kubernetes/overlays/hostinger`, `make validate`, `make policy` y
    `make consistency`; comparar la topología renderizada con la de Minikube y confirmar que no
    cambian `rabbitmq.yaml`, probes ni NetworkPolicies.
  - Done when: ambos renders muestran la misma topología, el `secretKeyRef` del Job existe en el
    placeholder y las cuatro verificaciones quedan en verde.

- [x] **T15. Documentar topología, TTL y contrato de consumidores**
  - Cubierta: RF-1 a RF-20 (apoyo documental)
  - En `docs/stack.md` (sección «Mensajería»), documentar exchanges, colas, argumentos, TTL,
    reintento, DLQ y el contrato `x-death`/máximo 5; en `docs/validation.md`, agregar los comandos
    de inspección y prueba; en `docs/hostinger.md`, indicar que la topología se aplica con el mismo
    Job y se verifica antes de cerrar el despliegue.
  - Done when: la documentación refleja los mismos nombres, TTL y routing keys que la spec, sin
    credenciales ni secretos.

- [ ] **T16. Ejecutar la verificación completa**
  - Cubierta: todos los RF (criterios de finalización)
  - Ejecutar `make verify` y, con clúster local, `make deploy` y `make smoke-test`; repetir la
    comprobación de la topología en Minikube y revisar el estado final del Job.
  - Done when: `make verify` y `make smoke-test` terminan sin errores, el Job queda `Completed` y
    no hay secretos, estados ni material sensible agregado al repositorio.
