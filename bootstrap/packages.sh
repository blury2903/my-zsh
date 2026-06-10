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

# Package name == command name for every entry, so `have` can detect each one.
pkgs=(zsh git curl fzf zoxide)

missing=()
for p in "${pkgs[@]}"; do
  have "$p" || missing+=("$p")
done

# eza (modern ls) only landed in apt on Ubuntu 24.04+ / Debian 13+. Install it
# when the repos offer it, but never abort the bootstrap on older distros.
want_eza=0
have eza || want_eza=1

if [ "${#missing[@]}" -eq 0 ] && [ "$want_eza" -eq 0 ]; then
  log "skip (already installed): ${pkgs[*]} eza"
  exit 0
fi

if [ "$DRY_RUN" = "1" ]; then
  log "(dry-run) would run: sudo apt-get update && sudo apt-get install -y ${missing[*]} (plus eza if apt offers it)"
  exit 0
fi

sudo apt-get update

if [ "${#missing[@]}" -gt 0 ]; then
  log "Installing packages: ${missing[*]}"
  sudo apt-get install -y "${missing[@]}"
fi

if [ "$want_eza" -eq 1 ]; then
  if apt-cache show eza >/dev/null 2>&1; then
    log "Installing packages: eza"
    sudo apt-get install -y eza
  else
    warn "eza not available in apt for this distro (needs Ubuntu 24.04+/Debian 13+); skipping. The 'ls' aliases fall back to plain ls."
  fi
fi

log "Packages installed."
