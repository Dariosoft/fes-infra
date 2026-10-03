#!/usr/bin/env bash
. "$(dirname "$0")/../lib/common.sh"

kubectl get pods -A
kubectl get ingress -A
kubectl get pvc -A
