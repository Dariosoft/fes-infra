#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl unattended-upgrades
systemctl enable --now unattended-upgrades

curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="v1.35.2+k3s1" \
  INSTALL_K3S_EXEC="server --secrets-encryption --write-kubeconfig-mode=600" sh -

kubectl wait --for=condition=Ready node --all --timeout=180s
