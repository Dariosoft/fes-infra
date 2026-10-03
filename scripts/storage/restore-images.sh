#!/usr/bin/env bash
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/minio.sh"

SRC=${PRODUCT_IMAGES_DIR:-"$WORKSPACE/media/images"}

if [ ! -d "$SRC" ]; then
  log_error "Source directory $SRC does not exist"
  exit 1
fi

mirror_flags=()
if [ "${RESTORE_OVERWRITE:-1}" = "1" ]; then
  mirror_flags=(--overwrite)
fi

minio_forward
mc mb --ignore-existing "friendly/$MINIO_BUCKET" >/dev/null
mc mirror "${mirror_flags[@]}" "$SRC" "friendly/$MINIO_BUCKET" >/dev/null

log_info "Product images restored to friendly/$MINIO_BUCKET"
