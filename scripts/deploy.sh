#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
"$ROOT/scripts/minikube-tls.sh"
kubectl apply -k "$ROOT/kubernetes/overlays/minikube"
"$ROOT/scripts/load-google-oauth.sh"

kubectl -n platform rollout status statefulset/postgresql --timeout=300s
kubectl -n platform rollout status statefulset/rabbitmq --timeout=300s
kubectl -n platform rollout status statefulset/minio --timeout=300s
kubectl -n observability rollout status deployment/otel-collector --timeout=300s
kubectl -n observability rollout status deployment/prometheus --timeout=300s
kubectl -n observability rollout status deployment/loki --timeout=300s
kubectl -n observability rollout status deployment/tempo --timeout=300s
kubectl -n observability rollout status deployment/grafana --timeout=300s
kubectl -n apps rollout status deployment/account-api --timeout=300s
kubectl -n apps rollout status deployment/catalog-api --timeout=300s
kubectl -n apps rollout status deployment/order-api --timeout=300s
kubectl -n apps rollout status deployment/payment-api --timeout=300s
kubectl -n apps rollout status deployment/panel-api --timeout=300s
kubectl -n apps rollout status deployment/client-web --timeout=300s
kubectl -n apps rollout status deployment/panel-web --timeout=300s
