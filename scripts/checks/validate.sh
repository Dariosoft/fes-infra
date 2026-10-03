#!/usr/bin/env bash
. "$(dirname "$0")/../lib/common.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

kustomize build --load-restrictor LoadRestrictionsNone "$INFRA_ROOT/kubernetes/overlays/minikube" > "$tmp_dir/minikube.yaml"
kustomize build "$INFRA_ROOT/kubernetes/overlays/hostinger" > "$tmp_dir/hostinger.yaml"
kubeconform -strict -summary -ignore-missing-schemas "$tmp_dir/minikube.yaml"
kubeconform -strict -summary -ignore-missing-schemas "$tmp_dir/hostinger.yaml"
terraform -chdir="$INFRA_ROOT/terraform/hostinger" fmt -check -recursive
terraform -chdir="$INFRA_ROOT/terraform/hostinger" init -backend=false
terraform -chdir="$INFRA_ROOT/terraform/hostinger" validate
