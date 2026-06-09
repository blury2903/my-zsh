# Zsh Config Repo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a zsh-only dotfiles repo that a single `install.sh` brings fully online on a fresh WSL2/Linux machine — installing zsh, oh-my-zsh, plugins, and Starship, then symlinking the config into place.

**Architecture:** The repo holds the real config files. `install.sh` runs idempotent bootstrap scripts (apt packages, oh-my-zsh, plugins, Starship), then creates exactly two symlinks (`~/.zshrc`, `~/.config/starship.toml`) with automatic backup of anything pre-existing. `~/.zshrc` self-locates the repo by resolving its own symlink and sources the modular `*.zsh` files from there, so the repo works from any clone location.

**Tech Stack:** Bash (install + bootstrap + helpers), Zsh (config), oh-my-zsh, Starship, TOML; tested with `bats`, `shellcheck`, `zsh -n`, and a Docker (`ubuntu:24.04`) fresh-machine harness.

**Reference spec:** `docs/superpowers/specs/2026-06-09-zsh-config-repo-design.md`

**Prerequisites (dev machine, one-time):**
```bash
sudo apt-get update && sudo apt-get install -y bats shellcheck
# zsh and python3 are already present on this machine; docker is optional (Task 6 skips without it).
```

---

## File Structure

| File | Responsibility |
|---|---|
| `.gitignore` | Keep `*.local` / OS cruft out of git. |
| `lib/helpers.sh` | Bash helpers: `log`/`warn`/`error`, `have()`, `backup_and_link()`, `DRY_RUN`. The only file with real logic. |
| `tests/helpers.bats` | Unit tests for `have`/`backup_and_link`. |
| `zsh/zshrc` | Orchestrator → `~/.zshrc`. Self-locates repo, sets theme/plugins, sources modules, inits Starship. |
| `zsh/exports.zsh` | PATH + env (sourced before oh-my-zsh). |
| `zsh/aliases.zsh` | User aliases (sourced after oh-my-zsh). |
| `zsh/functions.zsh` | User functions (sourced after oh-my-zsh). |
| `starship/starship.toml` | → `~/.config/starship.toml`. Minimal seed prompt. |
| `home/zshrc.local.example` | Template for untracked machine-specific/secret overrides. |
| `bootstrap/packages.sh` | apt-install zsh/git/curl. |
| `bootstrap/oh-my-zsh.sh` | Unattended oh-my-zsh install (keeps our `.zshrc`). |
| `bootstrap/plugins.sh` | Clone the two external plugins. |
| `bootstrap/starship.sh` | Install Starship into `~/.local/bin`. |
| `install.sh` | Entry point: parse args, run bootstrap, link config, advise on shell. |
| `tests/_in_container.sh` | In-container assertions for the fresh-machine test. |
| `tests/fresh-machine.sh` | Host-side Docker driver for the end-to-end test. |
| `README.md` | Usage, install, update, uninstall, secrets pattern. |

All bash files use `#!/usr/bin/env bash` and `set -euo pipefail` (except `lib/helpers.sh`, which is sourced). Zsh config files are checked with `zsh -n` (shellcheck does not understand zsh syntax).

---

## Task 1: Library helpers + tests (TDD)

**Files:**
- Create: `.gitignore`
- Create: `lib/helpers.sh`
- Test: `tests/helpers.bats`

- [ ] **Step 1: Create `.gitignore`**

```gitignore
# Local, machine-specific, or secret overrides — never commit these.
*.local

# OS / editor cruft
.DS_Store
*.swp
*~
```

- [ ] **Step 2: Write the failing tests** — `tests/helpers.bats`

```bash
#!/usr/bin/env bats

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  source "$REPO/lib/helpers.sh"
  TMP="$(mktemp -d)"
  SRC="$TMP/source-file"
  echo "new-content" > "$SRC"
}

teardown() {
  rm -rf "$TMP"
}

@test "have: true for an existing command" {
  run have sh
  [ "$status" -eq 0 ]
}

@test "have: false for a missing command" {
  run have definitely-not-a-real-command-xyz
  [ "$status" -ne 0 ]
}

@test "backup_and_link: creates symlink when dest is absent" {
  backup_and_link "$SRC" "$TMP/dest"
  [ -L "$TMP/dest" ]
  [ "$(readlink -f "$TMP/dest")" = "$(readlink -f "$SRC")" ]
}

@test "backup_and_link: backs up an existing file, then links" {
  echo "old-content" > "$TMP/dest"
  backup_and_link "$SRC" "$TMP/dest"
  [ -L "$TMP/dest" ]
  run cat "$TMP"/dest.backup.*
  [ "$status" -eq 0 ]
  [ "$output" = "old-content" ]
}

@test "backup_and_link: idempotent — no backup when already linked" {
  backup_and_link "$SRC" "$TMP/dest"
  backup_and_link "$SRC" "$TMP/dest"
  run bash -c "ls -1 $TMP/dest.backup.* 2>/dev/null | wc -l"
  [ "$output" = "0" ]
}

@test "backup_and_link: DRY_RUN makes no filesystem changes" {
  DRY_RUN=1
  backup_and_link "$SRC" "$TMP/dest"
  [ ! -e "$TMP/dest" ]
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `bats tests/helpers.bats`
Expected: FAIL — `lib/helpers.sh` does not exist yet (source error / all tests error).

- [ ] **Step 4: Implement `lib/helpers.sh`**

```bash
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
# Symlink SRC -> DEST. If DEST already points at SRC, skip. If DEST otherwise
# exists, move it to DEST.backup.<timestamp> first. Honors DRY_RUN.
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
    local backup="${dest}.backup.$(date +%Y%m%d%H%M%S)"
    mv "$dest" "$backup"
    warn "backed up $dest -> $backup"
  fi

  ln -s "$src" "$dest"
  log "linked $dest -> $src"
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bats tests/helpers.bats`
Expected: PASS — 7 tests, 0 failures.

- [ ] **Step 6: Lint**

Run: `shellcheck -s bash lib/helpers.sh`
Expected: no output (clean).

- [ ] **Step 7: Commit**

```bash
git add .gitignore lib/helpers.sh tests/helpers.bats
git commit -m "feat: add install helpers with backup-and-link and tests"
```

---

## Task 2: Zsh config files

**Files:**
- Create: `zsh/exports.zsh`
- Create: `zsh/aliases.zsh`
- Create: `zsh/functions.zsh`
- Create: `zsh/zshrc`

- [ ] **Step 1: Create `zsh/exports.zsh`**

```zsh
# Environment and PATH. Sourced by ~/.zshrc BEFORE oh-my-zsh.

# User-local binaries (Starship, pipx, etc.)
export PATH="$HOME/.local/bin:$PATH"

# Preferred editor (uncomment / adjust):
# export EDITOR='nvim'
```

- [ ] **Step 2: Create `zsh/aliases.zsh`**

```zsh
# Personal aliases. Sourced by ~/.zshrc AFTER oh-my-zsh so these win.

# Examples — uncomment or add your own:
# alias ll='ls -alh'
# alias gs='git status'
# alias ..='cd ..'
```

- [ ] **Step 3: Create `zsh/functions.zsh`**

```zsh
# Personal shell functions. Sourced by ~/.zshrc AFTER oh-my-zsh.

# Example — make a directory and cd into it:
# mkcd() { mkdir -p "$1" && cd "$1"; }
```

- [ ] **Step 4: Create `zsh/zshrc`**

```zsh
# Managed by github.com/blury2903/my-zsh — edit the repo files, not this symlink.
#
# ~/.zshrc is a symlink into the repo; resolve it to locate the repo's zsh/ dir.
ZSH_DOTFILES="${${(%):-%x}:A:h}"

# --- oh-my-zsh base -------------------------------------------------------
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME=""                       # empty: Starship provides the prompt
plugins=(git zsh-autosuggestions zsh-syntax-highlighting)

# --- env / PATH (before oh-my-zsh) ---------------------------------------
[[ -r "$ZSH_DOTFILES/exports.zsh" ]] && source "$ZSH_DOTFILES/exports.zsh"

source "$ZSH/oh-my-zsh.sh"

# --- personal config (after oh-my-zsh so it can override) ----------------
[[ -r "$ZSH_DOTFILES/aliases.zsh" ]]   && source "$ZSH_DOTFILES/aliases.zsh"
[[ -r "$ZSH_DOTFILES/functions.zsh" ]] && source "$ZSH_DOTFILES/functions.zsh"

# --- prompt --------------------------------------------------------------
command -v starship >/dev/null && eval "$(starship init zsh)"

# --- machine-specific / secret overrides (untracked) --------------------
[[ -r "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"
```

- [ ] **Step 5: Syntax-check every zsh file**

Run:
```bash
for f in zsh/zshrc zsh/exports.zsh zsh/aliases.zsh zsh/functions.zsh; do
  zsh -n "$f" && echo "OK: $f"
done
```
Expected: `OK: zsh/zshrc` and one `OK:` line per file, no syntax errors.

- [ ] **Step 6: Verify the self-locate expression resolves through a symlink**

Run:
```bash
ln -sf "$PWD/zsh/zshrc" /tmp/zshrc-link
zsh -c 'src=/tmp/zshrc-link; print -r -- "${${src}:A:h}"'
rm -f /tmp/zshrc-link
```
Expected: prints the absolute path to the repo's `zsh` directory (e.g. `/mnt/d/WorkSpace/projects/my-zsh/zsh`), confirming `:A:h` resolves the symlink to the real repo dir.

- [ ] **Step 7: Commit**

```bash
git add zsh/
git commit -m "feat: add zsh config (self-locating zshrc + modular exports/aliases/functions)"
```

---

## Task 3: Starship config + local-overrides template

**Files:**
- Create: `starship/starship.toml`
- Create: `home/zshrc.local.example`

- [ ] **Step 1: Create `starship/starship.toml`**

```toml
# Starship prompt config — https://starship.rs/config/
# Minimal seed (no nerd-font glyphs assumed). Explore richer presets with
# `starship preset --list`, then e.g. `starship preset nerd-font-symbols -o ~/.config/starship.toml`.

add_newline = true

[character]
success_symbol = "[>](bold green)"
error_symbol = "[>](bold red)"

[directory]
truncation_length = 3
truncate_to_repo = true

[cmd_duration]
min_time = 2000
format = "took [$duration](bold yellow) "
```

- [ ] **Step 2: Create `home/zshrc.local.example`**

```zsh
# Copy to ~/.zshrc.local for machine-specific or secret config.
# ~/.zshrc sources ~/.zshrc.local LAST, if it exists. It is NOT tracked in git
# (see .gitignore), so it is safe for tokens, proxies, and work-only settings.
#
# Examples:
# export http_proxy="http://proxy.example.com:8080"
# export GITHUB_TOKEN="..."
# export PATH="$HOME/work/bin:$PATH"
```

- [ ] **Step 3: Validate the TOML parses**

Run: `python3 -c "import tomllib,sys; tomllib.load(open('starship/starship.toml','rb')); print('TOML OK')"`
Expected: `TOML OK` (Python 3.11+ ships `tomllib`).

- [ ] **Step 4: Commit**

```bash
git add starship/starship.toml home/zshrc.local.example
git commit -m "feat: add starship prompt seed and local-overrides template"
```

---

## Task 4: Bootstrap scripts

**Files:**
- Create: `bootstrap/packages.sh`
- Create: `bootstrap/oh-my-zsh.sh`
- Create: `bootstrap/plugins.sh`
- Create: `bootstrap/starship.sh`

Each script resolves the repo root, sources `lib/helpers.sh` (double-source-guarded), is idempotent (checks before acting), and honors `DRY_RUN` from the environment.

- [ ] **Step 1: Create `bootstrap/packages.sh`**

```bash
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

if [ "$DRY_RUN" = "1" ]; then
  log "(dry-run) would run: sudo apt-get update && sudo apt-get install -y ${pkgs[*]}"
  exit 0
fi

log "Installing packages: ${pkgs[*]}"
sudo apt-get update
sudo apt-get install -y "${pkgs[@]}"
log "Packages installed."
```

- [ ] **Step 2: Create `bootstrap/oh-my-zsh.sh`**

```bash
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
RUNZSH=no KEEP_ZSHRC=yes CHSH=no \
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
log "oh-my-zsh installed."
```

- [ ] **Step 3: Create `bootstrap/plugins.sh`**

```bash
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

clone_plugin zsh-autosuggestions     https://github.com/zsh-users/zsh-autosuggestions
clone_plugin zsh-syntax-highlighting https://github.com/zsh-users/zsh-syntax-highlighting
log "Plugins ready."
```

- [ ] **Step 4: Create `bootstrap/starship.sh`**

```bash
#!/usr/bin/env bash
# Install the Starship prompt (sudo-free, into ~/.local/bin).
set -euo pipefail

REPO="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
# shellcheck source=../lib/helpers.sh
source "$REPO/lib/helpers.sh"

if have starship; then
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
```

- [ ] **Step 5: Make scripts executable**

Run: `chmod +x bootstrap/*.sh`

- [ ] **Step 6: Lint all four scripts**

Run: `shellcheck -s bash bootstrap/packages.sh bootstrap/oh-my-zsh.sh bootstrap/plugins.sh bootstrap/starship.sh`
Expected: no output (clean).

- [ ] **Step 7: Dry-run smoke test (must not mutate the system)**

Run:
```bash
DRY_RUN=1 bash bootstrap/packages.sh
DRY_RUN=1 bash bootstrap/oh-my-zsh.sh
DRY_RUN=1 bash bootstrap/plugins.sh
DRY_RUN=1 bash bootstrap/starship.sh
```
Expected: each prints a `(dry-run) would ...` (or `skip (already ...)`) line and exits 0; nothing is installed.

- [ ] **Step 8: Commit**

```bash
git add bootstrap/
git commit -m "feat: add idempotent dependency bootstrap scripts"
```

---

## Task 5: install.sh entry point

**Files:**
- Create: `install.sh`

- [ ] **Step 1: Create `install.sh`**

```bash
#!/usr/bin/env bash
# my-zsh — one-command setup: bootstrap dependencies, then link config.
set -euo pipefail

REPO="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
source "$REPO/lib/helpers.sh"

# --- args ---
export DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) export DRY_RUN=1 ;;
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
if [ -n "$zsh_path" ] && [ "${SHELL:-}" != "$zsh_path" ]; then
  if [ "$DRY_RUN" = "1" ]; then
    log "(dry-run) would advise: chsh -s $zsh_path"
  else
    warn "Your login shell is not zsh. To switch it, run:  chsh -s $zsh_path"
  fi
fi

log "Done. Start a fresh zsh session with:  exec zsh"
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x install.sh`

- [ ] **Step 3: Lint**

Run: `shellcheck -s bash install.sh`
Expected: no output (clean).

- [ ] **Step 4: Dry-run smoke test**

Run: `./install.sh --dry-run`
Expected: prints `DRY RUN — no changes will be made.`, then `(dry-run) would ...`/`skip ...` lines from each bootstrap step and both `would link` lines, exits 0. Confirm nothing changed: `readlink ~/.zshrc` is unchanged from before the run.

- [ ] **Step 5: Commit**

```bash
git add install.sh
git commit -m "feat: add install.sh entry point with --dry-run"
```

---

## Task 6: Fresh-machine integration test (Docker)

**Files:**
- Create: `tests/_in_container.sh`
- Create: `tests/fresh-machine.sh`

- [ ] **Step 1: Create `tests/_in_container.sh`** (runs inside the container as the `tester` user)

```bash
#!/usr/bin/env bash
# Assertions run inside the fresh Ubuntu container by tests/fresh-machine.sh.
set -euo pipefail

cd "$HOME/my-zsh"
./install.sh

echo "--- assertions ---"
command -v zsh
test -d "$HOME/.oh-my-zsh"
test -d "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
test -d "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"
"$HOME/.local/bin/starship" --version
test -L "$HOME/.zshrc"
test -L "$HOME/.config/starship.toml"
# zshrc loads cleanly: empty theme + starship available on PATH.
zsh -i -c 'echo "THEME=[$ZSH_THEME]"; type starship >/dev/null && echo STARSHIP_OK'

echo "--- idempotency: second run ---"
./install.sh | tee /tmp/run2.log
grep -q "already linked" /tmp/run2.log
grep -q "already installed" /tmp/run2.log
grep -q "already cloned" /tmp/run2.log

echo "ALL ASSERTIONS PASSED"
```

- [ ] **Step 2: Create `tests/fresh-machine.sh`** (host-side Docker driver)

```bash
#!/usr/bin/env bash
# End-to-end test: run install.sh in a clean Ubuntu container and assert the
# new-machine path works (and is idempotent). Requires Docker; skips without it.
set -euo pipefail

REPO="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"

if ! command -v docker >/dev/null 2>&1; then
  echo "SKIP: docker not available" >&2
  exit 0
fi

docker run --rm -v "$REPO:/repo:ro" ubuntu:24.04 bash -euo pipefail -c '
  apt-get update -qq
  apt-get install -y -qq sudo git curl ca-certificates >/dev/null
  useradd -m -s /bin/bash tester
  echo "tester ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/tester
  cp -r /repo /home/tester/my-zsh
  chown -R tester:tester /home/tester/my-zsh
  sudo -u tester -H bash /home/tester/my-zsh/tests/_in_container.sh
'
echo "fresh-machine test passed."
```

- [ ] **Step 3: Make the test scripts executable**

Run: `chmod +x tests/fresh-machine.sh tests/_in_container.sh`

- [ ] **Step 4: Lint**

Run: `shellcheck -s bash tests/fresh-machine.sh tests/_in_container.sh`
Expected: no output (clean).

- [ ] **Step 5: Run the end-to-end test**

Run: `./tests/fresh-machine.sh`
Expected (if Docker present): ends with `ALL ASSERTIONS PASSED` then `fresh-machine test passed.`. If Docker is absent: prints `SKIP: docker not available` and exits 0.

- [ ] **Step 6: Commit**

```bash
git add tests/fresh-machine.sh tests/_in_container.sh
git commit -m "test: add docker fresh-machine and idempotency integration test"
```

---

## Task 7: README

**Files:**
- Create: `README.md`

- [ ] **Step 1: Create `README.md`**

````markdown
# my-zsh

My portable zsh configuration. Clone it on a new machine and run one command to
install everything (zsh, oh-my-zsh, plugins, Starship) and link the config.

## Install

```bash
git clone git@github.com:blury2903/my-zsh.git ~/.my-zsh
~/.my-zsh/install.sh
exec zsh
```

`install.sh --dry-run` previews every action without changing anything.

> Targets WSL2 / Debian / Ubuntu (apt). Clone to a Linux-native path like
> `~/.my-zsh` (not a `/mnt/...` Windows mount) for fast shell startup. The config
> works from any location — `~/.zshrc` self-locates the repo.

## What it does

1. `apt` installs `zsh`, `git`, `curl`.
2. Installs oh-my-zsh (keeping this repo's `.zshrc`).
3. Clones `zsh-autosuggestions` and `zsh-syntax-highlighting`.
4. Installs [Starship](https://starship.rs) into `~/.local/bin`.
5. Creates two symlinks (backing up anything already there):
   - `~/.zshrc` → `zsh/zshrc`
   - `~/.config/starship.toml` → `starship/starship.toml`

Re-running is safe — every step is idempotent.

## Layout

- `zsh/zshrc` — main config; sources the modules below.
- `zsh/exports.zsh` — PATH and environment.
- `zsh/aliases.zsh` — your aliases.
- `zsh/functions.zsh` — your functions.
- `starship/starship.toml` — prompt config.

Edit these files directly — they are live via the symlink. `git pull` updates
everything instantly.

## Machine-specific / secret config

Put anything machine-specific or secret (tokens, proxies, work-only PATHs) in
`~/.zshrc.local`. It is sourced last and is never committed. Start from the
template:

```bash
cp ~/.my-zsh/home/zshrc.local.example ~/.zshrc.local
```

## Update

```bash
cd ~/.my-zsh && git pull
exec zsh
```

## Uninstall

```bash
rm ~/.zshrc ~/.config/starship.toml
# restore the most recent backups if you want your previous config:
ls -1 ~/.zshrc.backup.* 2>/dev/null
```

## Tests

```bash
bats tests/helpers.bats     # unit tests for the install helpers
./tests/fresh-machine.sh    # full new-machine run in a Docker container (skips if no docker)
```
````

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add README with install, update, and uninstall instructions"
```

---

## Self-Review

**1. Spec coverage** — every spec section maps to a task:

- §3 repo structure → Tasks 1–7 create every listed file (`docs/` already exists from the spec commit).
- §4 data flow / self-locating zshrc → Task 2 (incl. Step 6 verifying `:A:h`).
- §4 two-symlink map → Task 5 Step 1 + Task 1 `backup_and_link`.
- §5 install flow + bootstrap command details → Tasks 4 & 5.
- §6 helpers → Task 1.
- §7 error handling / idempotency / `--dry-run` → Task 1 (DRY_RUN, backup), Tasks 4–5 (guards + dry-run smoke), Task 6 (idempotency assertions).
- §8 secrets / `.zshrc.local` → Task 3 (template), Task 1 (`.gitignore *.local`), zshrc sources it (Task 2).
- §9 migration/backup → covered by `backup_and_link` (Task 1) + README uninstall notes (Task 7).
- §10 starship seed → Task 3.
- §11 README → Task 7.
- §12 verification (shellcheck / dry-run / idempotency / Docker) → lint+dry-run steps throughout + Task 6.

No gaps found.

**2. Placeholder scan** — no `TBD`/`TODO`/"add error handling"/"similar to Task N"; every code step contains complete content.

**3. Type/name consistency** — `DRY_RUN`, `backup_and_link`, `have`, `MYZSH_HELPERS_SOURCED`, `ZSH_DOTFILES`, `REPO`, and the `bootstrap/<name>.sh` filenames are used identically across all tasks. The two symlink targets (`~/.zshrc`, `~/.config/starship.toml`) match between Task 5 and the README. Bootstrap "skip" messages (`already installed`/`already cloned`/`already linked`) match the grep assertions in Task 6.
