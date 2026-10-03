#!/usr/bin/env bash
# Kubernetes helpers. Source after common.sh.

k() { kubectl --context "${PROFILE}" "$@"; }

wait_rollout() {
  k -n "$1" rollout status "$2" --timeout="${3:-300s}"
}
