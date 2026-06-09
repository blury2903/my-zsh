#!/usr/bin/env bash
# Install the Starship prompt (sudo-free, into ~/.local/bin).
set -euo pipefail

REPO="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
# shellcheck source=../lib/helpers.sh
source "$REPO/lib/helpers.sh"

if have starship || [ -x "$HOME/.local/bin/starship" ]; then
  log "skip (already installed): starship"
  exit 0
fi

if [ "$DRY_RUN" = "1" ]; then
  log "(dry-run) would install starship into ~/.local/bin"
  exit 0
fi

mkdir -p "$HOME/.local/bin"
log "Installing starship..."
curl -sS https://starship.rs/install.sh | sh -s -- -y -b "$HOME/.local/bin"
log "starship installed."
