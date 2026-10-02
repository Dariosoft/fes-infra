#!/usr/bin/env bash
set -euo pipefail

PORT=${MINIO_FORWARD_PORT:-19001}
USER=$(kubectl -n platform get secret platform-secrets -o jsonpath='{.data.minio-root-user}' | openssl base64 -d -A)
PASSWORD=$(kubectl -n platform get secret platform-secrets -o jsonpath='{.data.minio-root-password}' | openssl base64 -d -A)
ACCESS_KEY=$(kubectl -n apps get secret app-secrets -o jsonpath='{.data.product-images-access-key}' 2>/dev/null | openssl base64 -d -A 2>/dev/null || true)
SECRET_KEY=$(kubectl -n apps get secret app-secrets -o jsonpath='{.data.product-images-secret-key}' 2>/dev/null | openssl base64 -d -A 2>/dev/null || true)

POLICY_FILE=$(mktemp)
kubectl -n platform port-forward service/minio "$PORT:9000" >/tmp/friendly-e-shop-minio-forward.log 2>&1 &
forward_pid=$!
trap 'kill "$forward_pid" 2>/dev/null || true; rm -f "$POLICY_FILE"' EXIT
sleep 3

mc alias set friendly "http://127.0.0.1:$PORT" "$USER" "$PASSWORD" >/dev/null
mc mb --ignore-existing friendly/product-images >/dev/null
cat >"$POLICY_FILE" <<'JSON'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:GetBucketLocation", "s3:ListBucket"],
      "Resource": ["arn:aws:s3:::product-images"]
    },
    {
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"],
      "Resource": ["arn:aws:s3:::product-images/*"]
    }
  ]
}
JSON

if mc admin policy info friendly product-images-rw >/dev/null 2>&1; then
  mc admin policy remove friendly product-images-rw >/dev/null 2>&1 || true
fi
mc admin policy create friendly product-images-rw "$POLICY_FILE" >/dev/null

if [ -z "$ACCESS_KEY" ] || [ -z "$SECRET_KEY" ]; then
  echo "Bucket product-images is ready, but product-images-access-key/product-images-secret-key are missing from app-secrets." >&2
  echo "Not inventing credentials: set them and rerun. See docs/product-images.md." >&2
  exit 0
fi

if ! mc admin user info friendly "$ACCESS_KEY" >/dev/null 2>&1; then
  mc admin user add friendly "$ACCESS_KEY" "$SECRET_KEY" >/dev/null
fi
mc admin policy attach friendly product-images-rw --user "$ACCESS_KEY" >/dev/null 2>&1 || true

echo "Bucket product-images, policy product-images-rw and user $ACCESS_KEY are ready in MinIO."
