#!/usr/bin/env bash
set -euo pipefail

if [ -z "${AGE_RECIPIENT:-}" ]; then
  echo "Set AGE_RECIPIENT to your age public key." >&2
  exit 1
fi

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SOURCE="$ROOT/kubernetes/overlays/hostinger/secrets.placeholder.yaml"
TARGET="$ROOT/kubernetes/overlays/hostinger/secrets.enc.yaml"
sops --encrypt --age "$AGE_RECIPIENT" --encrypted-regex '^(data|stringData)$' "$SOURCE" > "$TARGET"
echo "Encrypted secrets written to $TARGET. Update kustomization.yaml to reference it."
