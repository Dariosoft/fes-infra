#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <database> <object-name>" >&2
  exit 1
fi

DATABASE=$1
OBJECT=$2
case "$DATABASE" in accounts|catalog|orders|payments|panel) ;; *) echo "Unsupported database" >&2; exit 1 ;; esac

PORT=${MINIO_FORWARD_PORT:-19000}
USER=$(kubectl -n platform get secret platform-secrets -o jsonpath='{.data.minio-root-user}' | openssl base64 -d -A)
PASSWORD=$(kubectl -n platform get secret platform-secrets -o jsonpath='{.data.minio-root-password}' | openssl base64 -d -A)

kubectl -n platform port-forward service/minio "$PORT:9000" >/tmp/friendly-e-shop-minio-forward.log 2>&1 &
forward_pid=$!
trap 'kill "$forward_pid" 2>/dev/null || true' EXIT
sleep 3
mc alias set friendly "http://127.0.0.1:$PORT" "$USER" "$PASSWORD" >/dev/null

echo "Restoring $DATABASE from $OBJECT"
mc cat "friendly/backups/$OBJECT" | kubectl -n platform exec -i postgresql-0 -- pg_restore -U postgres --clean --if-exists --no-owner --dbname "$DATABASE"
