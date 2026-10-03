#!/usr/bin/env bash
# MinIO helpers. Source after common.sh.

MINIO_FORWARD_PORT=${MINIO_FORWARD_PORT:-19000}
MINIO_BUCKET=${PRODUCT_IMAGES_BUCKET:-product-images}

minio_forward() {
  local port=${1:-$MINIO_FORWARD_PORT}
  local user password
  user=$(kubectl -n platform get secret platform-secrets -o jsonpath='{.data.minio-root-user}' | openssl base64 -d -A)
  password=$(kubectl -n platform get secret platform-secrets -o jsonpath='{.data.minio-root-password}' | openssl base64 -d -A)
  kubectl -n platform port-forward service/minio "${port}:9000" >/tmp/friendly-e-shop-minio-forward.log 2>&1 &
  MINIO_FORWARD_PID=$!
  trap minio_stop EXIT
  sleep 3
  mc alias set friendly "http://127.0.0.1:${port}" "$user" "$password" >/dev/null
}

minio_stop() {
  [ -z "${MINIO_FORWARD_PID:-}" ] || kill "$MINIO_FORWARD_PID" 2>/dev/null || true
}
