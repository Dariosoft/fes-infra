#!/usr/bin/env bash
. "$(dirname "$0")/../lib/common.sh"

status_output=$(minikube --profile "$PROFILE" status 2>&1 || true)
if echo "$status_output" | grep -Eqi "not found|does not exist|machine does not exist"; then
  log_error "Minikube profile '$PROFILE' does not exist. Run make minikube-create first."
  exit 1
fi

"$INFRA_ROOT/scripts/cluster/create.sh"
"$INFRA_ROOT/scripts/cluster/mount.sh"
log_info "Minikube profile '$PROFILE' is running with the local checkouts mounted."
log_info "Run make tunnel if you use the local HTTPS names."
