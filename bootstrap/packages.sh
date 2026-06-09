#!/usr/bin/env bash
# Install base packages via apt: zsh, git, curl.
set -euo pipefail

REPO="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
# shellcheck source=../lib/helpers.sh
source "$REPO/lib/helpers.sh"

if ! have apt-get; then
  error "apt-get not found. This repo targets Debian/Ubuntu (apt) only."
  exit 1
fi

pkgs=(zsh git curl)

if have zsh && have git && have curl; then
  log "skip (already installed): ${pkgs[*]}"
  exit 0
fi

if [ "$DRY_RUN" = "1" ]; then
  log "(dry-run) would run: sudo apt-get update && sudo apt-get install -y ${pkgs[*]}"
  exit 0
fi

log "Installing packages: ${pkgs[*]}"
sudo apt-get update
sudo apt-get install -y "${pkgs[@]}"
log "Packages installed."
