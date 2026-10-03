SHELL := /usr/bin/env bash

.PHONY: bootstrap doctor minikube-create start stop images-build deploy status smoke-test tunnel observability backup restore backup-images restore-images validate destroy

# Installs the required local CLI tools with Homebrew.
bootstrap:
	./scripts/setup/bootstrap.sh

# Checks that the required tools and Docker are available.
doctor:
	./scripts/checks/doctor.sh

# Creates the Minikube cluster and enables its required addons. Run 'make deploy' next to restore saved product images.
minikube-create:
	./scripts/cluster/create.sh

# Starts a stopped Minikube profile and mounts the local checkouts again.
start:
	./scripts/cluster/start.sh

# Stops the Minikube profile, the source mount, and the tunnel. Disk data is kept.
stop:
	./scripts/cluster/stop.sh

# Builds all application container images inside Minikube.
images-build:
	./scripts/build/images.sh

# Mounts local checkouts, applies the Minikube overlay, and waits for the applications.
deploy:
	./scripts/deploy/deploy.sh

# Forces a redeploy of the LOCAL applications, even if the manifests have not changed.
force-deploy:
	FORCE_LIVE_BUILD=1 ./scripts/deploy/deploy.sh

# Shows the current state of pods, ingress routes, and storage.
status:
	./scripts/checks/status.sh

# Verifies that the public application routes respond correctly.
smoke-test:
	./scripts/checks/smoke-test.sh

# Exposes local ingress routes and development dependencies until Ctrl+C.
tunnel:
	./scripts/cluster/tunnel.sh

# Opens a local port-forward to the Grafana interface.
observability:
	./scripts/tools/observability.sh

# Backs up the PostgreSQL databases to MinIO.
backup:
	./scripts/databases/backup.sh

# Restores DATABASE from a MinIO OBJECT; both variables are required.
restore:
	@test -n "$(DATABASE)" -a -n "$(OBJECT)" || (echo "Use DATABASE=name OBJECT=file make restore"; exit 1)
	./scripts/databases/restore.sh "$(DATABASE)" "$(OBJECT)"

# Mirrors the product-images bucket from MinIO to the local media/images folder.
backup-images:
	./scripts/storage/backup-images.sh

# Uploads the local media/images folder back into the MinIO product-images bucket.
restore-images:
	./scripts/storage/restore-images.sh

# Validates the Kubernetes manifests and Terraform configuration.
validate:
	./scripts/checks/validate.sh

# Backs up product images (best effort) and permanently deletes the local Minikube profile and its data.
destroy:
	./scripts/cluster/destroy.sh
