#!/usr/bin/env bash
# Shared helpers for the my-zsh install scripts.
# Sourced by install.sh and each bootstrap/*.sh (guarded against double-sourcing).

[ -n "${MYZSH_HELPERS_SOURCED:-}" ] && return 0
MYZSH_HELPERS_SOURCED=1

# May be set/exported by install.sh --dry-run.
DRY_RUN="${DRY_RUN:-0}"

# Colors only when stdout is a TTY.
if [ -t 1 ]; then
  _c_reset=$'\033[0m'; _c_blue=$'\033[34m'; _c_yellow=$'\033[33m'; _c_red=$'\033[31m'
else
  _c_reset=''; _c_blue=''; _c_yellow=''; _c_red=''
fi

log()   { printf '%s[my-zsh]%s %s\n' "$_c_blue"   "$_c_reset" "$*"; }
warn()  { printf '%s[my-zsh]%s %s\n' "$_c_yellow" "$_c_reset" "$*" >&2; }
error() { printf '%s[my-zsh]%s %s\n' "$_c_red"    "$_c_reset" "$*" >&2; }

# have CMD -> success if CMD is on PATH.
have() { command -v "$1" >/dev/null 2>&1; }

# backup_and_link SRC DEST
# Create symlink DEST -> SRC. If DEST already points at SRC, skip. If DEST
# otherwise exists, move it to DEST.backup.<timestamp> first. Honors DRY_RUN.
backup_and_link() {
  local src="$1" dest="$2"

  if [ "$DRY_RUN" = "1" ]; then
    log "(dry-run) would link $dest -> $src"
    return 0
  fi

  mkdir -p "$(dirname "$dest")"

  if [ -L "$dest" ] && [ "$(readlink -f "$dest")" = "$(readlink -f "$src")" ]; then
    log "skip (already linked): $dest"
    return 0
  fi

  if [ -e "$dest" ] || [ -L "$dest" ]; then
    local backup
    backup="${dest}.backup.$(date +%Y%m%d%H%M%S%N)"
    mv "$dest" "$backup"
    warn "backed up $dest -> $backup"
  fi

  ln -s "$src" "$dest"
  log "linked $dest -> $src"
}
