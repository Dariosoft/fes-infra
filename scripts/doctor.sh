#!/usr/bin/env bash
set -euo pipefail

required=(docker kubectl minikube kustomize kubeconform terraform sops age mc curl)
failed=0
for command_name in "${required[@]}"; do
  if command -v "$command_name" >/dev/null 2>&1; then
    printf "ok      %s\n" "$command_name"
  else
    printf "missing %s\n" "$command_name"
    failed=1
  fi
done

if ! docker info >/dev/null 2>&1; then
  echo "missing Docker daemon (start Docker Desktop)"
  failed=1
fi

exit "$failed"
