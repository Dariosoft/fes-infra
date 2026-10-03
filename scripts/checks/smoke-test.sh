#!/usr/bin/env bash
. "$(dirname "$0")/../lib/common.sh"

INGRESS_PORT=${INGRESS_FORWARD_PORT:-18080}
CATALOG_PORT=${CATALOG_FORWARD_PORT:-18081}
ACCOUNT_PORT=${ACCOUNT_FORWARD_PORT:-18082}
ORDER_PORT=${ORDER_FORWARD_PORT:-18083}
PAYMENT_PORT=${PAYMENT_FORWARD_PORT:-18084}
PANEL_API_PORT=${PANEL_API_FORWARD_PORT:-18085}

pids=()
forward() {  # <namespace> <service> <mapping> <log-name>
  kubectl -n "$1" port-forward "service/$2" "$3" >"/tmp/friendly-e-shop-$4-forward.log" 2>&1 &
  pids+=($!)
}

forward ingress-nginx ingress-nginx-controller "${INGRESS_PORT}:80" ingress
forward apps catalog-api "${CATALOG_PORT}:8080" catalog
forward apps account-api "${ACCOUNT_PORT}:8080" account
forward apps order-api "${ORDER_PORT}:8080" order
forward apps payment-api "${PAYMENT_PORT}:8080" payment
forward apps panel-api "${PANEL_API_PORT}:8000" panel-api
trap 'kill "${pids[@]}" 2>/dev/null || true' EXIT
sleep 4

curl --fail --silent --show-error --resolve "market.friendly-e-shop.duckdns.org:$INGRESS_PORT:127.0.0.1" "http://market.friendly-e-shop.duckdns.org:$INGRESS_PORT/" >/dev/null
curl --fail --silent --show-error --resolve "panel.friendly-e-shop.duckdns.org:$INGRESS_PORT:127.0.0.1" "http://panel.friendly-e-shop.duckdns.org:$INGRESS_PORT/" >/dev/null
log_info "Storefront and panel OK"

check() {  # <description> <url>
  if ! curl --fail --silent --show-error "$2" >/dev/null; then
    log_error "$1 is not available"
    exit 1
  fi
  log_info "$1 OK"
}

check "catalog service" "http://127.0.0.1:$CATALOG_PORT/actuator/health/readiness"
check "account service" "http://127.0.0.1:$ACCOUNT_PORT/actuator/health/readiness"
check "order service" "http://127.0.0.1:$ORDER_PORT/actuator/health/readiness"
check "payment service" "http://127.0.0.1:$PAYMENT_PORT/actuator/health/readiness"
check "panel service" "http://127.0.0.1:$PANEL_API_PORT/health/ready"

log_info "Smoke tests passed"
