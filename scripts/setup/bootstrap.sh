#!/usr/bin/env bash
. "$(dirname "$0")/../lib/common.sh"

if ! command -v brew >/dev/null 2>&1; then
  log_error "Homebrew is required: https://brew.sh"
  exit 1
fi

brew trust --formula hashicorp/tap/terraform
brew bundle --file="$INFRA_ROOT/Brewfile"
