#!/usr/bin/env bash
set -euo pipefail
kubectl get pods -A
kubectl get ingress -A
kubectl get pvc -A
