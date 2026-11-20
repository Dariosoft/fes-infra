#!/usr/bin/env bash
. "$(dirname "$0")/../lib/common.sh"

cd "$INFRA_ROOT" || exit 1

log_info "== shellcheck =="
find scripts -name '*.sh' -print0 | xargs -0 shellcheck --severity=warning

log_info "== yamllint =="
yamllint --strict kubernetes .github .sops.yaml

log_info "== hadolint =="
hadolint images/minio/Dockerfile

log_info "== secret-hygiene =="
./scripts/checks/secret-hygiene.sh

log_info "Lint OK"
