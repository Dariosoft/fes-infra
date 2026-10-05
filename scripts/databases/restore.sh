#!/usr/bin/env bash
. "$(dirname "$0")/../lib/common.sh"
. "$(dirname "$0")/../lib/minio.sh"

if [ "$#" -ne 2 ]; then
  log_error "Usage: $0 <database> <object-name>"
  exit 1
fi

DATABASE=$1
OBJECT=$2
case "$DATABASE" in accounts|catalog|orders|payments|panel) ;; *) log_error "Unsupported database"; exit 1 ;; esac

minio_forward

log_info "Restoring $DATABASE from $OBJECT"
mc cat "friendly/backups/$OBJECT" | kubectl -n platform exec -i postgresql-0 -- pg_restore -U postgres --clean --if-exists --no-owner --dbname "$DATABASE"
