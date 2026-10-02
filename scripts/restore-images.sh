#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUCKET=${PRODUCT_IMAGES_BUCKET:-product-images}
SRC=${PRODUCT_IMAGES_DIR:-"$(cd "$ROOT/.." && pwd)/media/images"}
PORT=${MINIO_FORWARD_PORT:-19000}

USER=$(kubectl -n platform get secret platform-secrets -o jsonpath='{.data.minio-root-user}' | openssl base64 -d -A)
PASSWORD=$(kubectl -n platform get secret platform-secrets -o jsonpath='{.data.minio-root-password}' | openssl base64 -d -A)

if [ ! -d "$SRC" ]; then
  echo "Source directory $SRC does not exist" >&2
  exit 1
fi

kubectl -n platform port-forward service/minio "$PORT:9000" >/tmp/friendly-e-shop-minio-forward.log 2>&1 &
forward_pid=$!
trap 'kill "$forward_pid" 2>/dev/null || true' EXIT
sleep 3

mc alias set friendly "http://127.0.0.1:$PORT" "$USER" "$PASSWORD" >/dev/null
mc mb --ignore-existing "friendly/$BUCKET" >/dev/null
mc mirror --overwrite "$SRC" "friendly/$BUCKET" >/dev/null

echo "Product images restored to friendly/$BUCKET"
