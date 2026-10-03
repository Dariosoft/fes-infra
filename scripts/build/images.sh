#!/usr/bin/env bash
. "$(dirname "$0")/../lib/common.sh"

services=(account-api catalog-api order-api payment-api client-web panel-api panel-web)

if [ "$(minikube --profile "$PROFILE" status --format '{{.Host}}')" != "Running" ]; then
  log_error "Minikube profile '$PROFILE' is not running. Run make minikube-create first."
  exit 1
fi

for service in "${services[@]}"; do
  log_info "Building $service"
  minikube --profile "$PROFILE" image build -t "friendly-e-shop/${service}:dev" "$WORKSPACE/$service"
done

log_info "Building patched MinIO release"
minikube --profile "$PROFILE" image build -t "friendly-e-shop/minio:RELEASE.2025-10-15T17-29-55Z" "$WORKSPACE/infra/images/minio"
