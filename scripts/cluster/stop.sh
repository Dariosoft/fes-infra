#!/usr/bin/env bash
. "$(dirname "$0")/../lib/common.sh"

stop_matching() {
  local pattern="$1"
  local pid
  while read -r pid; do
    [ -n "$pid" ] || continue
    [ "$pid" = "$$" ] && continue
    kill "$pid" 2>/dev/null || true
  done < <(pgrep -f "$pattern" || true)
}

stop_matching "minikube --profile ${PROFILE} mount"
stop_matching "minikube --profile ${PROFILE} tunnel"
stop_matching "minikube tunnel --profile ${PROFILE}"

minikube stop --profile "$PROFILE"
log_info "Minikube profile '$PROFILE' is stopped. Disk data is kept."
log_info "Bring it back with make start, then run make tunnel if you use the local HTTPS names."
