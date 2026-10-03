#!/usr/bin/env bash
# Shared helpers. Source it from any script: . "$(dirname "$0")/../lib/common.sh"

set -euo pipefail

INFRA_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
WORKSPACE=$(cd "$INFRA_ROOT/.." && pwd)
PROFILE=${MINIKUBE_PROFILE:-friendly-e-shop}

log_info() { printf '%s\n' "$*"; }
log_warn() { printf '%s\n' "$*" >&2; }
log_error() { printf '%s\n' "$*" >&2; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { log_error "Required command not found: $1"; exit 1; }
}
