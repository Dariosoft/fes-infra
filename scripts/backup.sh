#!/usr/bin/env bash
set -euo pipefail

PORT=${MINIO_FORWARD_PORT:-19000}
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
USER=$(kubectl -n platform get secret platform-secrets -o jsonpath='{.data.minio-root-user}' | openssl base64 -d -A)
PASSWORD=$(kubectl -n platform get secret platform-secrets -o jsonpath='{.data.minio-root-password}' | openssl base64 -d -A)

kubectl -n platform port-forward service/minio "$PORT:9000" >/tmp/friendly-e-shop-minio-forward.log 2>&1 &
forward_pid=$!
trap 'kill "$forward_pid" 2>/dev/null || true' EXIT
sleep 3

mc alias set friendly "http://127.0.0.1:$PORT" "$USER" "$PASSWORD" >/dev/null
mc mb --ignore-existing friendly/backups >/dev/null

for database in accounts catalog orders payments panel; do
  echo "Backing up $database"
  kubectl -n platform exec postgresql-0 -- pg_dump -U postgres -Fc "$database" | mc pipe "friendly/backups/${database}-${STAMP}.dump"
done

echo "Backups stored under backups/*-${STAMP}.dump"
