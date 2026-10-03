#!/usr/bin/env bash
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/minio.sh"

STAMP=$(date -u +%Y%m%dT%H%M%SZ)

minio_forward

mc mb --ignore-existing friendly/backups >/dev/null

for database in accounts catalog orders payments panel; do
  log_info "Backing up $database"
  kubectl -n platform exec postgresql-0 -- pg_dump -U postgres -Fc "$database" | mc pipe "friendly/backups/${database}-${STAMP}.dump"
done

log_info "Backups stored under backups/*-${STAMP}.dump"
