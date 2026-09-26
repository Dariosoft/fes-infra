# AGENTS.md - infra

## Proyecto
Infraestructura de Friendly E-Shop para desarrollo local con Minikube y despliegue en un nodo K3s de Hostinger.
Gestiona Terraform, manifiestos Kubernetes, secretos cifrados, observabilidad y scripts operativos de los siete servicios.

## Comandos
- Preparar: `make bootstrap`
- Diagnóstico local: `make doctor`
- Desplegar en Minikube: `make deploy`
- Validar Kubernetes y Terraform: `make validate`
- Prueba de humo: `make smoke-test`

## Estilo y convenciones
- Mantén Terraform bajo `terraform/`, bases y overlays de Kubernetes bajo `kubernetes/` y automatización bajo `scripts/`.
- Conserva módulos, variables, outputs y restricciones de versión explícitos; no hardcodees valores propios de un entorno.
- Usa Kustomize para diferencias entre Minikube y Hostinger; no dupliques manifiestos completos entre overlays.
- Documenta en `docs/` cualquier cambio de topología, operación, secretos, backup u observabilidad.

## Reglas
- Lee `/terraform-style-guide` antes de crear o modificar archivos Terraform.
- Usa `/terraform-module-library` al crear o refactorizar módulos Terraform reutilizables.
- Usa `/k8s-manifest-generator` al crear o modificar recursos Kubernetes y conserva la estructura base/overlay.
- Usa `/secrets-management` para cambios de SOPS, credenciales o datos sensibles; nunca confirmes secretos en claro.
- Usa `/opentelemetry` para cambios de telemetría y `/deployment-pipeline-design` para cambios de CI/CD.
- Cada backend conserva su propia base y credenciales; ningún servicio puede acceder a tablas de otro dominio.
- RabbitMQ es la mensajería prevista y MinIO el almacenamiento compatible con S3; no los sustituyas sin una spec.
- Mantén las imágenes y configuración de las aplicaciones coordinadas con sus repositorios propietarios.

## Al terminar cualquier tarea
- Ejecuta `make validate` para cambios en Terraform o Kubernetes.
- Ejecuta `make smoke-test` cuando el cambio afecte rutas, servicios, ingress o despliegues locales.
- Comprueba que no se hayan añadido estados, planes, variables sensibles ni secretos descifrados al repositorio.
