#!/usr/bin/env bash
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/kube.sh"

MOUNT_LOG=/tmp/friendly-e-shop-minikube-mount.log
services=(panel-web client-web panel-api account-api catalog-api order-api payment-api)

if [ "$(minikube --profile "$PROFILE" status --format '{{.Host}}')" != "Running" ]; then
  log_error "Minikube profile '$PROFILE' is not running. Run make minikube-create first."
  exit 1
fi

"$INFRA_ROOT/scripts/cluster/mount.sh"

# containerd selects a Dockerfile stage with buildctl --opt target=...
built=()
for service in "${services[@]}"; do
  if [ "${FORCE_LIVE_BUILD:-}" != 1 ] && minikube --profile "$PROFILE" image ls | grep -F "friendly-e-shop/${service}:live" >/dev/null; then
    continue
  fi
  log_info "Building live image friendly-e-shop/${service}:live"
  minikube --profile "$PROFILE" image build \
    --build-opt opt=target=dev \
    -t "friendly-e-shop/${service}:live" \
    "$WORKSPACE/$service"
  built+=("$service")
done

# The patched MinIO release is not an app image and only changes when its pinned tag does,
# so it is built on demand instead of on every deploy.
minio_image=friendly-e-shop/minio:RELEASE.2025-10-15T17-29-55Z
minio_built=0
if ! minikube --profile "$PROFILE" image ls | grep -F "$minio_image" >/dev/null; then
  log_info "Building $minio_image"
  minikube --profile "$PROFILE" image build -t "$minio_image" "$INFRA_ROOT/images/minio"
  minio_built=1
fi

"$INFRA_ROOT/scripts/cluster/tls.sh"
kustomize build --load-restrictor LoadRestrictionsNone "$INFRA_ROOT/kubernetes/overlays/minikube" \
  | kubectl --context "$PROFILE" apply -f -
"$INFRA_ROOT/scripts/secrets/load-google-oauth.sh"

# account-api reads the OAuth client from app-secrets at startup, so it is restarted on
# every deploy. Keeping it out of the loop below avoids annotating its pod template twice
# in the same second, which kubectl rejects.
restart=(deployment/account-api)
if [ "${#built[@]}" -gt 0 ]; then
  for service in "${built[@]}"; do
    if [ "$service" != account-api ]; then
      restart+=("deployment/${service}")
    fi
  done
fi
kubectl --context "$PROFILE" -n apps rollout restart "${restart[@]}"

if [ "$minio_built" = 1 ]; then
  kubectl --context "$PROFILE" -n platform rollout restart statefulset/minio
fi

wait_rollout platform statefulset/postgresql 300s
wait_rollout platform statefulset/rabbitmq 300s
wait_rollout platform statefulset/minio 300s
"$INFRA_ROOT/scripts/storage/ensure-bucket.sh"
if [ -d "$WORKSPACE/media/images" ]; then
  RESTORE_OVERWRITE=0 "$INFRA_ROOT/scripts/storage/restore-images.sh" || log_warn "Product image restore skipped."
fi
wait_rollout observability deployment/otel-collector 300s
wait_rollout observability deployment/prometheus 300s
wait_rollout observability deployment/loki 300s
wait_rollout observability deployment/tempo 300s
wait_rollout observability deployment/grafana 300s
for service in "${services[@]}"; do
  wait_rollout apps "deployment/${service}" 600s
done

log_info "Minikube is serving the mounted checkouts."
log_info "Edit local files; the running services reload without another deploy."
log_info "After a dependency change, rerun make deploy with FORCE_LIVE_BUILD=1."
log_info "The source mount stays up on its own. Its log is $MOUNT_LOG"
