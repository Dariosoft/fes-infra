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
	@set -eu; \
	postgres_pid=; \
	minio_pid=; \
	ingress_pid=; \
	cleanup() { \
		[ -z "$$postgres_pid" ] || kill "$$postgres_pid" 2>/dev/null || true; \
		[ -z "$$minio_pid" ] || kill "$$minio_pid" 2>/dev/null || true; \
		[ -z "$$ingress_pid" ] || sudo -n kill "$$ingress_pid" 2>/dev/null || true; \
	}; \
	trap cleanup EXIT; \
	trap 'exit 130' INT; \
	trap 'exit 143' TERM; \
	sudo -v; \
	kubectl -n platform port-forward service/postgresql 5432:5432 & \
	postgres_pid=$$!; \
	kubectl -n platform port-forward service/minio 9000:9000 & \
	minio_pid=$$!; \
	sudo -n kubectl -n ingress-nginx port-forward service/ingress-nginx-controller 80:80 443:443 & \
	ingress_pid=$$!; \
	wait "$$ingress_pid"

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
	@profile="$${MINIKUBE_PROFILE:-friendly-e-shop}"; \
	if [ "$$(minikube --profile "$$profile" status --format '{{.Host}}' 2>/dev/null)" = "Running" ]; then \
		echo "Backing up product images before destroy..."; \
		./scripts/backup-images.sh || echo "Product image backup failed; continuing with destroy."; \
	else \
		echo "Minikube '$$profile' is not running; skipping product image backup."; \
	fi
	minikube delete --profile "$${MINIKUBE_PROFILE:-friendly-e-shop}"
