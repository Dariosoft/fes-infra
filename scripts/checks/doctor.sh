#!/usr/bin/env bash
. "$(dirname "$0")/../lib/common.sh"

required=(docker kubectl minikube kustomize kubeconform terraform sops age mc curl)
failed=0
for command_name in "${required[@]}"; do
  if command -v "$command_name" >/dev/null 2>&1; then
    log_info "$(printf 'ok      %s' "$command_name")"
  else
    log_info "$(printf 'missing %s' "$command_name")"
    failed=1
  fi
done

if ! docker info >/dev/null 2>&1; then
  log_error "missing Docker daemon (start Docker Desktop)"
  failed=1
fi

exit "$failed"
