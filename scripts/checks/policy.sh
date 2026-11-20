#!/usr/bin/env bash
. "$(dirname "$0")/../lib/common.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

kustomize build --load-restrictor LoadRestrictionsNone "$INFRA_ROOT/kubernetes/overlays/minikube" > "$tmp_dir/minikube.yaml"
kustomize build "$INFRA_ROOT/kubernetes/overlays/hostinger" > "$tmp_dir/hostinger.yaml"

for manifest in minikube hostinger; do
  log_info "== Políticas comunes sobre el overlay $manifest =="
  conftest test --policy "$INFRA_ROOT/policy/k8s.rego" "$tmp_dir/$manifest.yaml"
done

log_info "== Políticas de producción sobre el overlay hostinger =="
conftest test --policy "$INFRA_ROOT/policy/production.rego" "$tmp_dir/hostinger.yaml"

log_info "Políticas OK"
