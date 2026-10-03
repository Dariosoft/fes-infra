#!/usr/bin/env bash
. "$(dirname "$0")/../lib/common.sh"

postgres_pid=
minio_pid=
ingress_pid=

cleanup() {
  [ -z "$postgres_pid" ] || kill "$postgres_pid" 2>/dev/null || true
  [ -z "$minio_pid" ] || kill "$minio_pid" 2>/dev/null || true
  [ -z "$ingress_pid" ] || sudo -n kill "$ingress_pid" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

sudo -v
kubectl -n platform port-forward service/postgresql 5432:5432 &
postgres_pid=$!
kubectl -n platform port-forward service/minio 9000:9000 &
minio_pid=$!
sudo -n kubectl -n ingress-nginx port-forward service/ingress-nginx-controller 80:80 443:443 &
ingress_pid=$!
wait "$ingress_pid"
