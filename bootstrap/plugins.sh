#!/usr/bin/env bash
# Clone external zsh plugins into the oh-my-zsh custom plugins directory.
set -euo pipefail

REPO="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
# shellcheck source=../lib/helpers.sh
source "$REPO/lib/helpers.sh"

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

clone_plugin() {
  local name="$1" url="$2"
  local dest="$ZSH_CUSTOM/plugins/$name"
  if [ -d "$dest" ]; then
    log "skip (already cloned): $name"
    return 0
  fi
  if [ "$DRY_RUN" = "1" ]; then
    log "(dry-run) would clone $name -> $dest"
    return 0
  fi
  log "Cloning $name..."
  git clone --depth=1 "$url" "$dest"
}

clone_plugin zsh-autosuggestions          https://github.com/zsh-users/zsh-autosuggestions
clone_plugin zsh-syntax-highlighting      https://github.com/zsh-users/zsh-syntax-highlighting
clone_plugin zsh-history-substring-search https://github.com/zsh-users/zsh-history-substring-search
log "Plugins ready."
