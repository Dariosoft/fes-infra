#!/usr/bin/env bash
. "$(dirname "$0")/../lib/common.sh"

if [ -z "${AGE_RECIPIENT:-}" ]; then
  log_error "Set AGE_RECIPIENT to your age public key."
  exit 1
fi

SOURCE="$INFRA_ROOT/kubernetes/overlays/hostinger/secrets.placeholder.yaml"
TARGET="$INFRA_ROOT/kubernetes/overlays/hostinger/secrets.enc.yaml"
sops --encrypt --age "$AGE_RECIPIENT" --encrypted-regex '^(data|stringData)$' "$SOURCE" > "$TARGET"
log_info "Encrypted secrets written to $TARGET. Update kustomization.yaml to reference it."
