#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
PROFILE=${MINIKUBE_PROFILE:-friendly-e-shop}
services=(catalog-api order-api payment-api client-web panel-api panel-web)

if [ "$(minikube --profile "$PROFILE" status --format '{{.Host}}')" != "Running" ]; then
  echo "Minikube profile '$PROFILE' is not running. Run make minikube-create first." >&2
  exit 1
fi

for service in "${services[@]}"; do
  echo "Building $service"
  minikube --profile "$PROFILE" image build -t "friendly-e-shop/${service}:dev" "$ROOT/$service"
done

echo "Building patched MinIO release"
minikube --profile "$PROFILE" image build -t "friendly-e-shop/minio:RELEASE.2025-10-15T17-29-55Z" "$ROOT/infra/images/minio"
