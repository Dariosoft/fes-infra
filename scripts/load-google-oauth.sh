#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORKSPACE=$(cd "$ROOT/.." && pwd)
PROFILE=${MINIKUBE_PROFILE:-friendly-e-shop}

if [ -n "${GOOGLE_OAUTH_JSON:-}" ]; then
  JSON=$GOOGLE_OAUTH_JSON
else
  shopt -s nullglob
  matches=("$WORKSPACE"/client_secret_*.apps.googleusercontent.com.json)
  shopt -u nullglob
  if [ "${#matches[@]}" -eq 0 ]; then
    echo "No Google OAuth client JSON next to the apps. Leaving the Minikube placeholders in place." >&2
    exit 0
  fi
  if [ "${#matches[@]}" -gt 1 ]; then
    echo "More than one client_secret JSON in $WORKSPACE. Set GOOGLE_OAUTH_JSON." >&2
    exit 1
  fi
  JSON=${matches[0]}
fi

PATCH=$(python3 - "$JSON" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    web = json.load(handle)["web"]
client_id = web.get("client_id", "")
client_secret = web.get("client_secret", "")
if not client_id or not client_secret:
    sys.exit("JSON is missing web.client_id or web.client_secret")
print(json.dumps({
    "stringData": {
        "google-client-id": client_id,
        "google-client-secret": client_secret,
    }
}))
PY
)

kubectl --context "$PROFILE" -n apps patch secret app-secrets --type merge -p "$PATCH" >/dev/null
kubectl --context "$PROFILE" -n apps rollout restart deployment/account-api >/dev/null
echo "Loaded Google OAuth client into app-secrets and restarted account-api."
