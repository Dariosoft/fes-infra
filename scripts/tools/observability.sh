#!/usr/bin/env bash
. "$(dirname "$0")/../lib/common.sh"

log_info "Grafana: http://localhost:3000 (admin / value in observability-secrets)"
kubectl -n observability port-forward service/grafana 3000:3000
