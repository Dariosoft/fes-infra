#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

kustomize build --load-restrictor LoadRestrictionsNone "$ROOT/kubernetes/overlays/minikube" > "$tmp_dir/minikube.yaml"
kustomize build "$ROOT/kubernetes/overlays/hostinger" > "$tmp_dir/hostinger.yaml"
kubeconform -strict -summary -ignore-missing-schemas "$tmp_dir/minikube.yaml"
kubeconform -strict -summary -ignore-missing-schemas "$tmp_dir/hostinger.yaml"
terraform -chdir="$ROOT/terraform/hostinger" fmt -check -recursive
terraform -chdir="$ROOT/terraform/hostinger" init -backend=false
terraform -chdir="$ROOT/terraform/hostinger" validate
