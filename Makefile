SHELL := /usr/bin/env bash

.PHONY: bootstrap doctor minikube-create images-build deploy status smoke-test tunnel observability backup restore validate destroy

# Installs the required local CLI tools with Homebrew.
bootstrap:
	./scripts/bootstrap.sh

# Checks that the required tools and Docker are available.
doctor:
	./scripts/doctor.sh

# Creates the Minikube cluster and enables its required addons.
minikube-create:
	./scripts/minikube-create.sh

# Builds all application container images inside Minikube.
images-build:
	./scripts/images-build.sh

# Mounts local checkouts, applies the Minikube overlay, and waits for the applications.
deploy:
	./scripts/deploy.sh

# Shows the current state of pods, ingress routes, and storage.
status:
	./scripts/status.sh

# Verifies that the public application routes respond correctly.
smoke-test:
	./scripts/smoke-test.sh

# Exposes the local ingress routes until the command is stopped with Ctrl+C.
tunnel:
	minikube tunnel --profile "$${MINIKUBE_PROFILE:-friendly-e-shop}"

# Opens a local port-forward to the Grafana interface.
observability:
	./scripts/observability.sh

# Backs up the PostgreSQL databases to MinIO.
backup:
	./scripts/backup.sh

# Restores DATABASE from a MinIO OBJECT; both variables are required.
restore:
	@test -n "$(DATABASE)" -a -n "$(OBJECT)" || (echo "Use DATABASE=name OBJECT=file make restore"; exit 1)
	./scripts/restore.sh "$(DATABASE)" "$(OBJECT)"

# Validates the Kubernetes manifests and Terraform configuration.
validate:
	./scripts/validate.sh

# Permanently deletes the local Minikube profile and its data.
destroy:
	minikube delete --profile "$${MINIKUBE_PROFILE:-friendly-e-shop}"
