# Tasks 005 — Kafka KRaft, topic de pedidos y despliegue de analítica y notificaciones

## Fase A — Kafka y topic

- [ ] **T1. Crear `kubernetes/base/platform/kafka.yaml`.** Cubre RF-1, RF-2, RF-3, RF-18.
  Done when: el StatefulSet KRaft y el Service `kafka:9092` renderizan y `make validate` pasa.
- [ ] **T2. Crear `kafka-topology.yaml` con el `Job` idempotente.** Cubre RF-4, RF-5, RF-6.
  Done when: reaplicar el Job no falla y crea `orders.events` con 3 particiones y retención 7 d.
- [ ] **T2b. Agregar `seller.notify.retry` y `seller.notify.dlq` a la topología RabbitMQ.** Cubre RF-20.
  Done when: el `Job` declara ambas colas durables sin modificar los argumentos de `seller.notify`.
- [ ] **T3. Sumar Kafka al `kustomization.yaml` de plataforma.** Cubre RF-17.
  Done when: ambos overlays renderizan Kafka una sola vez.

## Fase B — Bases, secretos y red

- [ ] **T4. Agregar bases `analytics` y `notifications` al init de PostgreSQL.** Cubre RF-7, RF-19.
  Done when: un volumen nuevo crea usuarios y bases; las claves llegan desde `platform-secrets`.
- [ ] **T5. Agregar claves a los secretos de ambos overlays.** Cubre RF-7, RF-19.
  Done when: `make consistency` pasa y no hay credenciales en claro.
- [ ] **T6. Permitir `9092` en `network-policies.yaml`.** Cubre RF-14, RF-15.
  Done when: `make policy` pasa y las apps alcanzan Kafka.

## Fase C — Despliegues

- [ ] **T7. Crear `kubernetes/base/analytics-api/`.** Cubre RF-8, RF-11, RF-17.
  Done when: Deployment, Service, ConfigMap y kustomization renderizan con sondas de Actuator.
- [ ] **T8. Crear `kubernetes/base/notifications-api/`.** Cubre RF-8, RF-12, RF-17.
  Done when: renderiza con `KAFKA_*`, `RABBITMQ_*` y `DATABASE_*`.
- [ ] **T9. Sumar `initContainers` de `kafka-topology` y el RBAC.** Cubre RF-9.
  Done when: los pods quedan en `Init` hasta que el Job completa.
- [ ] **T10. Agregar envs a `order-api` y `panel-api`.** Cubre RF-10, RF-13.
  Done when: `order-api` ve `KAFKA_BOOTSTRAP_SERVERS` y `panel-api` las dos URLs.

## Fase D — Despliegue y cierre

- [ ] **T11. Actualizar `deploy.sh` y `kustomization.yaml` base.** Cubre RF-16, RF-17.
  Done when: `make deploy` espera Kafka y el Job antes de las apps.
- [ ] **T12. Documentar en `docs/stack.md` y `docs/hostinger.md`.** Cubre RF-17, RF-19.
  Done when: el topic, grupos y verificación quedan documentados.
- [ ] **T13. Ejecutar `make verify` y la demo manual.** Cubre todos los RF.
  Done when: validate, lint, policy, consistency y smoke test en verde.
