#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORKSPACE=$(cd "$ROOT/.." && pwd)
PROFILE=${MINIKUBE_PROFILE:-friendly-e-shop}
MOUNT_LOG=/tmp/friendly-e-shop-minikube-mount.log
services=(panel-web client-web panel-api account-api catalog-api order-api payment-api)

if [ "$(minikube --profile "$PROFILE" status --format '{{.Host}}')" != "Running" ]; then
  echo "Minikube profile '$PROFILE' is not running. Run make minikube-create first." >&2
  exit 1
fi

if ! minikube --profile "$PROFILE" ssh -- ls /friendly-e-shop/panel-web/package.json >/dev/null 2>&1; then
  echo "Mounting $WORKSPACE into the Minikube node at /friendly-e-shop"
  python3 - "$PROFILE" "$WORKSPACE" "$MOUNT_LOG" <<'PY'
import subprocess
import sys

profile, workspace, log_path = sys.argv[1:]
log = open(log_path, "ab", buffering=0)
subprocess.Popen(
    ["minikube", "--profile", profile, "mount", f"{workspace}:/friendly-e-shop"],
    stdout=log,
    stderr=subprocess.STDOUT,
    stdin=subprocess.DEVNULL,
    start_new_session=True,
)
PY
  for _ in $(seq 1 30); do
    if minikube --profile "$PROFILE" ssh -- ls /friendly-e-shop/panel-web/package.json >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done
  if ! minikube --profile "$PROFILE" ssh -- ls /friendly-e-shop/panel-web/package.json >/dev/null 2>&1; then
    echo "The source mount did not become visible. See $MOUNT_LOG" >&2
    exit 1
  fi
fi

# containerd selects a Dockerfile stage with buildctl --opt target=...
built=()
for service in "${services[@]}"; do
  if [ "${FORCE_LIVE_BUILD:-}" != 1 ] && minikube --profile "$PROFILE" image ls | grep -F "friendly-e-shop/${service}:live" >/dev/null; then
    continue
  fi
  echo "Building live image friendly-e-shop/${service}:live"
  minikube --profile "$PROFILE" image build \
    --build-opt opt=target=dev \
    -t "friendly-e-shop/${service}:live" \
    "$WORKSPACE/$service"
  built+=("$service")
done

"$ROOT/scripts/minikube-tls.sh"
kustomize build --load-restrictor LoadRestrictionsNone "$ROOT/kubernetes/overlays/minikube" \
  | kubectl --context "$PROFILE" apply -f -
"$ROOT/scripts/load-google-oauth.sh"

if [ "${#built[@]}" -gt 0 ]; then
  restart=()
  for service in "${built[@]}"; do
    restart+=("deployment/${service}")
  done
  kubectl --context "$PROFILE" -n apps rollout restart "${restart[@]}"
fi

kubectl --context "$PROFILE" -n platform rollout status statefulset/postgresql --timeout=300s
kubectl --context "$PROFILE" -n platform rollout status statefulset/rabbitmq --timeout=300s
kubectl --context "$PROFILE" -n platform rollout status statefulset/minio --timeout=300s
kubectl --context "$PROFILE" -n observability rollout status deployment/otel-collector --timeout=300s
kubectl --context "$PROFILE" -n observability rollout status deployment/prometheus --timeout=300s
kubectl --context "$PROFILE" -n observability rollout status deployment/loki --timeout=300s
kubectl --context "$PROFILE" -n observability rollout status deployment/tempo --timeout=300s
kubectl --context "$PROFILE" -n observability rollout status deployment/grafana --timeout=300s
for service in "${services[@]}"; do
  kubectl --context "$PROFILE" -n apps rollout status "deployment/${service}" --timeout=600s
done

echo "Minikube is serving the mounted checkouts."
echo "Edit local files; the running services reload without another deploy."
echo "After a dependency change, rerun make deploy with FORCE_LIVE_BUILD=1."
echo "The source mount stays up on its own. Its log is $MOUNT_LOG"
