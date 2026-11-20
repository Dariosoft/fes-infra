# Políticas que sólo aplican al overlay de producción.
#
# El overlay de Minikube monta el checkout local con hostPath para recargar en
# caliente y corre herramientas de observabilidad sin livenessProbe. Eso es
# correcto en desarrollo y no debe replicarse en el nodo de Hostinger, donde un
# contenedor colgado tiene que reiniciarse solo.
package main

import rego.v1

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

deny contains msg if {
	some spec in pod_specs
	some volume in spec.volumes
	volume.hostPath
	msg := sprintf("%s: el volumen %s usa hostPath, que ata el pod a un nodo", [name, volume.name])
}

deny contains msg if {
	some container in containers
	not container.livenessProbe
	msg := sprintf("%s: el contenedor %s no declara livenessProbe", [name, container.name])
}
