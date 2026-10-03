SHELL := /usr/bin/env bash

.PHONY: bootstrap doctor minikube-create start stop images-build deploy status smoke-test tunnel observability backup restore backup-images restore-images validate destroy

# Installs the required local CLI tools with Homebrew.
bootstrap:
	./scripts/bootstrap.sh

# Checks that the required tools and Docker are available.
doctor:
	./scripts/doctor.sh

# Creates the Minikube cluster and enables its required addons. Run 'make deploy' next to restore saved product images.
minikube-create:
	./scripts/minikube-create.sh

# Starts a stopped Minikube profile and mounts the local checkouts again.
start:
	./scripts/minikube-start.sh

# Stops the Minikube profile, the source mount, and the tunnel. Disk data is kept.
stop:
	./scripts/minikube-stop.sh

# Builds all application container images inside Minikube.
images-build:
	./scripts/images-build.sh

# Mounts local checkouts, applies the Minikube overlay, and waits for the applications.
deploy:
	./scripts/deploy.sh

# Forces a redeploy of the LOCAL applications, even if the manifests have not changed.
force-deploy:
	FORCE_LIVE_BUILD=1 ./scripts/deploy.sh

# Shows the current state of pods, ingress routes, and storage.
status:
	./scripts/status.sh

# Verifies that the public application routes respond correctly.
smoke-test:
	./scripts/smoke-test.sh

# Exposes local ingress routes and development dependencies until Ctrl+C.
tunnel:
	./scripts/minikube-tunnel.sh

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

# Mirrors the product-images bucket from MinIO to the local media/images folder.
backup-images:
	./scripts/backup-images.sh

# Uploads the local media/images folder back into the MinIO product-images bucket.
restore-images:
	./scripts/restore-images.sh

# Validates the Kubernetes manifests and Terraform configuration.
validate:
	./scripts/validate.sh

# Backs up product images (best effort) and permanently deletes the local Minikube profile and its data.
destroy:
	./scripts/minikube-destroy.sh
