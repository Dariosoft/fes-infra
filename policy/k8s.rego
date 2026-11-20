# Políticas de postura comunes a todos los entornos.
#
# kubeconform responde "¿esto es un Deployment válido?". Estas reglas responden
# "¿está configurado como queremos?". Se evalúan sobre `kustomize build`, no
# sobre los archivos sueltos, porque los patches de cada overlay cambian el
# resultado final.
#
# Las reglas que sólo tienen sentido en producción (sin hostPath, con
# livenessProbe) viven en production.rego: el overlay de Minikube monta el
# checkout local a propósito para recargar en caliente.
package main

import rego.v1

# Kinds que envuelven un podspec en spec.template.spec.
workload_kinds := {"Deployment", "StatefulSet", "DaemonSet", "ReplicaSet", "Job"}

pod_specs contains spec if {
	input.kind == "Pod"
	spec := input.spec
}

pod_specs contains spec if {
	workload_kinds[input.kind]
	spec := input.spec.template.spec
}

containers contains container if {
	some spec in pod_specs
	some container in spec.containers
}

name := input.metadata.name

# --- recursos ---------------------------------------------------------------

deny contains msg if {
	some container in containers
	not container.resources.limits.cpu
	msg := sprintf("%s: el contenedor %s no declara resources.limits.cpu", [name, container.name])
}

deny contains msg if {
	some container in containers
	not container.resources.limits.memory
	msg := sprintf("%s: el contenedor %s no declara resources.limits.memory", [name, container.name])
}

deny contains msg if {
	some container in containers
	not container.resources.requests.cpu
	msg := sprintf("%s: el contenedor %s no declara resources.requests.cpu", [name, container.name])
}

deny contains msg if {
	some container in containers
	not container.resources.requests.memory
	msg := sprintf("%s: el contenedor %s no declara resources.requests.memory", [name, container.name])
}

# --- sondas -----------------------------------------------------------------

deny contains msg if {
	some container in containers
	not container.readinessProbe
	msg := sprintf("%s: el contenedor %s no declara readinessProbe", [name, container.name])
}

# --- privilegios ------------------------------------------------------------

deny contains msg if {
	some spec in pod_specs
	not spec.securityContext.runAsNonRoot == true
	msg := sprintf("%s: el pod debe declarar securityContext.runAsNonRoot: true", [name])
}

deny contains msg if {
	some container in containers
	container.securityContext.privileged == true
	msg := sprintf("%s: el contenedor %s corre privilegiado", [name, container.name])
}

deny contains msg if {
	some spec in pod_specs
	spec.hostNetwork == true
	msg := sprintf("%s: usa hostNetwork", [name])
}

deny contains msg if {
	some spec in pod_specs
	spec.hostPID == true
	msg := sprintf("%s: usa hostPID", [name])
}

# --- imágenes ---------------------------------------------------------------

image_tag(image) := tag if {
	segments := split(image, "/")
	last := segments[count(segments) - 1]
	parts := split(last, ":")
	count(parts) == 2
	tag := parts[1]
}

deny contains msg if {
	some container in containers
	not image_tag(container.image)
	msg := sprintf("%s: la imagen %s no declara tag explícito", [name, container.image])
}

deny contains msg if {
	some container in containers
	image_tag(container.image) == "latest"
	msg := sprintf("%s: la imagen %s usa el tag latest", [name, container.image])
}
