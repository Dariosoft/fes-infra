#!/usr/bin/env bash
. "$(dirname "$0")/../lib/common.sh"

MOUNT_LOG=/tmp/friendly-e-shop-minikube-mount.log

if ! minikube --profile "$PROFILE" ssh -- ls /friendly-e-shop/panel-web/package.json >/dev/null 2>&1; then
  log_info "Mounting $WORKSPACE into the Minikube node at /friendly-e-shop"
  python3 - "$PROFILE" "$WORKSPACE" "$MOUNT_LOG" <<'PY'
import subprocess
import sys

profile, workspace, log_path = sys.argv[1:]
log = open(log_path, "ab", buffering=0)
subprocess.Popen(
    ["minikube", "--profile", profile, "mount", f"{workspace}:/friendly-e-shop"],
    stdout=log,
    stderr=subprocess.STDOUT,
    stdin=subprocess.DEVNULL,
    start_new_session=True,
)
PY
  for _ in $(seq 1 30); do
    if minikube --profile "$PROFILE" ssh -- ls /friendly-e-shop/panel-web/package.json >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done
  if ! minikube --profile "$PROFILE" ssh -- ls /friendly-e-shop/panel-web/package.json >/dev/null 2>&1; then
    log_error "The source mount did not become visible. See $MOUNT_LOG"
    exit 1
  fi
fi
