#!/usr/bin/env bash
. "$(dirname "$0")/../lib/common.sh"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

cat > "$tmpdir/openssl.cnf" <<'EOF'
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no
[req_distinguished_name]
CN = friendly-e-shop.duckdns.org
[v3_req]
subjectAltName = @alt_names
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
[alt_names]
DNS.1 = friendly-e-shop.duckdns.org
DNS.2 = market.friendly-e-shop.duckdns.org
DNS.3 = panel.friendly-e-shop.duckdns.org
DNS.4 = api.friendly-e-shop.duckdns.org
EOF

openssl req -x509 -nodes -days 825 -newkey rsa:2048 \
  -keyout "$tmpdir/tls.key" -out "$tmpdir/tls.crt" \
  -config "$tmpdir/openssl.cnf" -extensions v3_req >/dev/null 2>&1

kubectl --context "$PROFILE" -n apps create secret tls friendly-e-shop-tls \
  --cert="$tmpdir/tls.crt" --key="$tmpdir/tls.key" \
  --dry-run=client -o yaml | kubectl --context "$PROFILE" apply -f - >/dev/null
log_info "Installed local TLS certificate for friendly-e-shop.duckdns.org."
