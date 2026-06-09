#!/usr/bin/env bash
# Install oh-my-zsh unattended, preserving our managed .zshrc.
set -euo pipefail

REPO="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
# shellcheck source=../lib/helpers.sh
source "$REPO/lib/helpers.sh"

if [ -d "$HOME/.oh-my-zsh" ]; then
  log "skip (already installed): oh-my-zsh"
  exit 0
fi

if [ "$DRY_RUN" = "1" ]; then
  log "(dry-run) would install oh-my-zsh (RUNZSH=no KEEP_ZSHRC=yes CHSH=no)"
  exit 0
fi

log "Installing oh-my-zsh..."
curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh \
  | RUNZSH=no KEEP_ZSHRC=yes CHSH=no sh
log "oh-my-zsh installed."
