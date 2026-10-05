#!/usr/bin/env bash
. "$(dirname "$0")/../lib/common.sh"
MINIO_FORWARD_PORT=${MINIO_FORWARD_PORT:-19001}
. "$(dirname "$0")/../lib/minio.sh"

ACCESS_KEY=$(kubectl -n apps get secret app-secrets -o jsonpath='{.data.product-images-access-key}' 2>/dev/null | openssl base64 -d -A 2>/dev/null || true)
SECRET_KEY=$(kubectl -n apps get secret app-secrets -o jsonpath='{.data.product-images-secret-key}' 2>/dev/null | openssl base64 -d -A 2>/dev/null || true)

POLICY_FILE=$(mktemp)
minio_forward
trap 'rm -f "$POLICY_FILE"; minio_stop' EXIT

mc mb --ignore-existing "friendly/$MINIO_BUCKET" >/dev/null
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
  log_error "Bucket product-images is ready, but product-images-access-key/product-images-secret-key are missing from app-secrets."
  log_error "Not inventing credentials: set them and rerun. See docs/product-images.md."
  exit 0
fi

if ! mc admin user info friendly "$ACCESS_KEY" >/dev/null 2>&1; then
  mc admin user add friendly "$ACCESS_KEY" "$SECRET_KEY" >/dev/null
fi
mc admin policy attach friendly product-images-rw --user "$ACCESS_KEY" >/dev/null 2>&1 || true

log_info "Bucket product-images, policy product-images-rw and user $ACCESS_KEY are ready in MinIO."
