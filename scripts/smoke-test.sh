#!/usr/bin/env bash
set -euo pipefail

PORT=${INGRESS_FORWARD_PORT:-18080}
kubectl -n ingress-nginx port-forward service/ingress-nginx-controller "$PORT:80" >/tmp/friendly-e-shop-ingress-forward.log 2>&1 &
forward_pid=$!
trap 'kill "$forward_pid" 2>/dev/null || true' EXIT
sleep 3

curl --fail --silent --show-error --resolve "shop.friendly-e-shop.test:$PORT:127.0.0.1" "http://shop.friendly-e-shop.test:$PORT/" >/dev/null
curl --fail --silent --show-error --resolve "panel.friendly-e-shop.test:$PORT:127.0.0.1" "http://panel.friendly-e-shop.test:$PORT/" >/dev/null
curl --fail --silent --show-error --resolve "api.friendly-e-shop.test:$PORT:127.0.0.1" "http://api.friendly-e-shop.test:$PORT/catalog" >/dev/null
curl --fail --silent --show-error --resolve "api.friendly-e-shop.test:$PORT:127.0.0.1" "http://api.friendly-e-shop.test:$PORT/orders" >/dev/null
curl --fail --silent --show-error --resolve "api.friendly-e-shop.test:$PORT:127.0.0.1" "http://api.friendly-e-shop.test:$PORT/payments" >/dev/null
curl --fail --silent --show-error --resolve "api.friendly-e-shop.test:$PORT:127.0.0.1" "http://api.friendly-e-shop.test:$PORT/panel" >/dev/null
echo "Checking account service availability"
if ! curl --fail --silent --show-error --resolve "api.friendly-e-shop.test:$PORT:127.0.0.1" "http://api.friendly-e-shop.test:$PORT/accounts" >/dev/null; then
  echo "account service is not available" >&2
  exit 1
fi
echo "Smoke tests passed"
