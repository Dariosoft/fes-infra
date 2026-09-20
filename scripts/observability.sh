#!/usr/bin/env bash
set -euo pipefail
echo "Grafana: http://localhost:3000 (admin / value in observability-secrets)"
kubectl -n observability port-forward service/grafana 3000:3000
