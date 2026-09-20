#!/usr/bin/env bash
set -euo pipefail

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required: https://brew.sh" >&2
  exit 1
fi

brew trust --formula hashicorp/tap/terraform
brew bundle --file="$(cd "$(dirname "$0")/.." && pwd)/Brewfile"
