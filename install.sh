#!/usr/bin/env bash
# my-zsh — one-command setup: bootstrap dependencies, then link config.
set -euo pipefail

REPO="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
source "$REPO/lib/helpers.sh"

# --- args ---
export DRY_RUN="${DRY_RUN:-0}"
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help) echo "Usage: install.sh [--dry-run]"; exit 0 ;;
    *) error "Unknown argument: $arg"; exit 1 ;;
  esac
done
[ "$DRY_RUN" = "1" ] && log "DRY RUN — no changes will be made."

# --- 1. bootstrap dependencies (DRY_RUN is exported, so children inherit it) ---
bash "$REPO/bootstrap/packages.sh"
bash "$REPO/bootstrap/oh-my-zsh.sh"
bash "$REPO/bootstrap/plugins.sh"
bash "$REPO/bootstrap/starship.sh"

# --- 2. link config ---
backup_and_link "$REPO/zsh/zshrc"              "$HOME/.zshrc"
backup_and_link "$REPO/starship/starship.toml" "$HOME/.config/starship.toml"

# --- 3. default shell advice ---
zsh_path="$(command -v zsh || true)"
shell_real="$(readlink -f "${SHELL:-}" 2>/dev/null || true)"
zsh_real="$(readlink -f "$zsh_path" 2>/dev/null || true)"
if [ -n "$zsh_path" ] && [ "$shell_real" != "$zsh_real" ]; then
  if [ "$DRY_RUN" = "1" ]; then
    log "(dry-run) would advise: chsh -s $zsh_path"
  else
    warn "Your login shell is not zsh. To switch it, run:  chsh -s $zsh_path"
  fi
fi

log "Done. Start a fresh zsh session with:  exec zsh"
