#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PROFILE=${MINIKUBE_PROFILE:-friendly-e-shop}

if [ "$(minikube --profile "$PROFILE" status --format '{{.Host}}' 2>/dev/null)" = "Running" ]; then
  echo "Backing up product images before destroy..."
  "$ROOT/scripts/backup-images.sh" || echo "Product image backup failed; continuing with destroy."
else
  echo "Minikube '$PROFILE' is not running; skipping product image backup."
fi

minikube delete --profile "$PROFILE"
