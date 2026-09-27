#!/usr/bin/env bash
set -euo pipefail

PROFILE=${MINIKUBE_PROFILE:-friendly-e-shop}
CPUS=${MINIKUBE_CPUS:-6}
MEMORY=${MINIKUBE_MEMORY:-8192}

docker info >/dev/null
minikube start --profile "$PROFILE" --driver docker --cpus "$CPUS" --memory "$MEMORY"
minikube --profile "$PROFILE" addons enable ingress
minikube --profile "$PROFILE" addons enable metrics-server
kubectl config use-context "$PROFILE" >/dev/null

ip=$(minikube --profile "$PROFILE" ip)
echo "Minikube node IP: $ip"
echo "On macOS with the Docker driver, run 'minikube tunnel -p $PROFILE' and map the local names to 127.0.0.1."
echo "127.0.0.1 market.friendly-e-shop.duckdns.org panel.friendly-e-shop.duckdns.org api.friendly-e-shop.duckdns.org grafana.friendly-e-shop.test"
