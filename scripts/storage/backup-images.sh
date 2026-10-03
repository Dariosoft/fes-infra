#!/usr/bin/env bash
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/minio.sh"

DEST=${PRODUCT_IMAGES_DIR:-"$WORKSPACE/media/images"}

mkdir -p "$DEST"

minio_forward
mc mirror --overwrite "friendly/$MINIO_BUCKET" "$DEST" >/dev/null

log_info "Product images mirrored to $DEST"
