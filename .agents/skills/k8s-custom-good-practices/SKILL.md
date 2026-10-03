---
name: k8s-custom-good-practices
description: Convenciones propias de infra para el Makefile y los parches de Kustomize del overlay de Minikube. Úsala al agregar o editar targets del Makefile o parches de Minikube.
---

# K8s custom good practices

1. **Makefile delega en `scripts/`.** Cada target del `Makefile` invoca un script dentro de `scripts/` cuando la acción requiere más de una línea. El Makefile no contiene lógica multilínea inline.
2. **Parches de Minikube por proyecto.** Los parches de `kubernetes/overlays/minikube/patches/` van en una carpeta por proyecto: `account-api/`, `catalog-api/`, `order-api/`, `payment-api/`, `panel-api/`, `client-web/` y `panel-web/`. Los parches transversales (namespace, telemetría, etc.) van en `shared/`. No existe la carpeta `live/`: los parches de recarga local viven dentro de la carpeta de su proyecto.
