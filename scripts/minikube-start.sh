#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PROFILE=${MINIKUBE_PROFILE:-friendly-e-shop}

status_output=$(minikube --profile "$PROFILE" status 2>&1 || true)
if echo "$status_output" | grep -Eqi "not found|does not exist|machine does not exist"; then
  echo "Minikube profile '$PROFILE' does not exist. Run make minikube-create first." >&2
  exit 1
fi

"$ROOT/scripts/minikube-create.sh"
"$ROOT/scripts/ensure-minikube-mount.sh"
echo "Minikube profile '$PROFILE' is running with the local checkouts mounted."
echo "Run make tunnel if you use the local HTTPS names."
