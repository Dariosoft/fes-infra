#!/usr/bin/env bash
. "$(dirname "$0")/../lib/common.sh"

if [ "$(minikube --profile "$PROFILE" status --format '{{.Host}}' 2>/dev/null)" = "Running" ]; then
  log_info "Backing up product images before destroy..."
  "$INFRA_ROOT/scripts/storage/backup-images.sh" || log_warn "Product image backup failed; continuing with destroy."
else
  log_info "Minikube '$PROFILE' is not running; skipping product image backup."
fi

minikube delete --profile "$PROFILE"
