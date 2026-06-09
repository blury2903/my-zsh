# Zsh Config Repo — Design

- **Date:** 2026-06-09
- **Status:** Approved (design), pending implementation plan
- **Repo:** `git@github.com:blury2903/my-zsh.git`
- **Owner:** Son Tran (`blury2903`)

## 1. Goal

A version-controlled home for the user's **zsh** configuration that can be cloned onto a
fresh machine and brought fully online with a single command — installing any missing
tooling and linking the config into place.

Non-goal: a general-purpose dotfiles manager. Scope is zsh only (see §13).

## 2. Locked decisions

| Decision | Choice | Rationale |
|---|---|---|
| Scope | Zsh only | Matches the request; keeps the repo small and focused. |
| Targets | WSL2 / Linux (Debian/Ubuntu, `apt`) | The user's only environment; avoids cross-platform branching. |
| Bootstrap | Install everything | True one-command setup on a bare machine. |
| Prompt | **Starship** | User's choice; replaces the dormant Powerlevel10k and the active robbyrussell theme. |
| Mechanism | **Symlink via install script** | Single source of truth, clean `git status`, no sync-back step. |
| Clone location | `~/.my-zsh` by convention (any path works) | Native path avoids WSL `/mnt` startup latency; self-locating `.zshrc` makes it path-independent. |

## 3. Repo structure

```
my-zsh/
├── README.md
├── install.sh                  # entry point: bootstrap deps, then link config
├── lib/
│   └── helpers.sh              # log/color output, have(), backup_and_link(), DRY_RUN
├── bootstrap/
│   ├── packages.sh             # apt: zsh, git, curl
│   ├── oh-my-zsh.sh            # unattended OMZ install (keeps our .zshrc)
│   ├── plugins.sh              # clone zsh-autosuggestions + zsh-syntax-highlighting
│   └── starship.sh             # install starship (official installer, sudo-free)
├── zsh/
│   ├── zshrc                   # main config  → ~/.zshrc   (stored dot-less for visibility)
│   ├── exports.zsh             # PATH + env (seeded with existing ~/.local/bin line)
│   ├── aliases.zsh             # user aliases (seeded with commented examples)
│   └── functions.zsh           # user functions (seeded with commented examples)
├── starship/
│   └── starship.toml           # → ~/.config/starship.toml (seeded minimal default)
├── home/
│   └── zshrc.local.example     # template for machine-specific / secret overrides
├── docs/
│   └── superpowers/specs/      # this design doc lives here
└── .gitignore
```

The `exports` / `aliases` / `functions` split is deliberately light — it provides obvious
homes for config to grow into without over-engineering a currently-tiny config.

## 4. How config loads (data flow)

Exactly **two** symlinks are ever created:

| Repo file | Symlinked to |
|---|---|
| `zsh/zshrc` | `~/.zshrc` |
| `starship/starship.toml` | `~/.config/starship.toml` |

The modular `*.zsh` files are **not** symlinked. `~/.zshrc` resolves its own symlink to find
the repo, then sources the modules from there. Adding a new module never requires a new
symlink, and `~` stays clean (one zsh symlink).

`zsh/zshrc` (orchestrator) — load order matters because `ZSH_THEME`/`plugins` must be set
before sourcing oh-my-zsh:

```zsh
# ~/.zshrc is a symlink into the repo; resolve it to locate the repo's zsh/ dir.
ZSH_DOTFILES="${${(%):-%x}:A:h}"        # e.g. ~/.my-zsh/zsh

export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME=""                             # empty: Starship provides the prompt
plugins=(git zsh-autosuggestions zsh-syntax-highlighting)

source "$ZSH_DOTFILES/exports.zsh"       # PATH/env before OMZ
source "$ZSH/oh-my-zsh.sh"
source "$ZSH_DOTFILES/aliases.zsh"       # after OMZ so user aliases can override
source "$ZSH_DOTFILES/functions.zsh"

command -v starship >/dev/null && eval "$(starship init zsh)"
[[ -r "$HOME/.zshrc.local" ]] && source "$HOME/.zshrc.local"   # untracked overrides
```

`${(%):-%x}` is the path of the file currently being sourced; `:A` resolves the symlink to an
absolute real path; `:h` is its directory. Result: the repo is found wherever it was cloned.

## 5. `install.sh` flow

`install.sh` first resolves its **own** directory (same `:A` symlink-resolving trick) so it can be
invoked by absolute path from any working directory (e.g. `~/.my-zsh/install.sh`). All paths below
are relative to that resolved repo root.

```
set -euo pipefail
REPO="$(dirname "$(readlink -f "$0")")"   # repo root, CWD-independent
source "$REPO/lib/helpers.sh"
parse args (--dry-run)

1. bootstrap/packages.sh    # sudo apt-get update && install -y zsh git curl   (idempotent)
2. bootstrap/oh-my-zsh.sh   # install if ~/.oh-my-zsh absent (RUNZSH=no KEEP_ZSHRC=yes)
3. bootstrap/plugins.sh     # clone the 2 plugins into $ZSH_CUSTOM/plugins (if absent)
4. bootstrap/starship.sh    # install if `starship` not on PATH
5. link config:
     backup_and_link  zsh/zshrc               ~/.zshrc
     backup_and_link  starship/starship.toml  ~/.config/starship.toml
6. if login shell isn't zsh: offer `chsh -s "$(command -v zsh)"`
7. print next step: `exec zsh`
```

New-machine setup: `git clone git@github.com:blury2903/my-zsh.git ~/.my-zsh && ~/.my-zsh/install.sh`

### Bootstrap command details

- **packages.sh:** verify `apt-get` exists (else exit with a clear message); `sudo apt-get update`
  then `sudo apt-get install -y zsh git curl`.
- **oh-my-zsh.sh:** if `~/.oh-my-zsh` missing,
  `RUNZSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL .../ohmyzsh/tools/install.sh)"`.
  `KEEP_ZSHRC=yes` is critical so OMZ does not overwrite our `.zshrc`.
- **plugins.sh:** into `${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/`, clone
  `zsh-users/zsh-autosuggestions` and `zsh-users/zsh-syntax-highlighting` if the dirs are absent.
- **starship.sh:** if `starship` not on PATH,
  `curl -sS https://starship.rs/install.sh | sh -s -- -y -b "$HOME/.local/bin"`.
  Installing into `~/.local/bin` (already on PATH via `exports.zsh`) keeps it sudo-free.

## 6. Library helpers (`lib/helpers.sh`)

- `log` / `warn` / `error` — colored, prefixed output.
- `have <cmd>` — `command -v "$1" >/dev/null 2>&1`.
- `backup_and_link <src> <dest>`:
  - `mkdir -p "$(dirname dest)"`.
  - If `dest` already symlinks to `src` → skip (idempotent).
  - Else if `dest` exists (file/dir/other symlink) → `mv` to `dest.backup.<YYYYMMDDHHMMSS>`.
  - `ln -s src dest`.
  - Honors `DRY_RUN`: prints intended action, mutates nothing.
- `DRY_RUN` global toggled by `--dry-run`, **exported** so it propagates to bootstrap scripts.

Sharing model: `install.sh` runs each `bootstrap/*.sh` as a child script. Each bootstrap script
sources `lib/helpers.sh` itself (guarded against double-sourcing) so it also works standalone, and
reads `DRY_RUN` from the environment.

## 7. Error handling & idempotency

- Every script begins with `set -euo pipefail`.
- Re-running `install.sh` is safe: each bootstrap step checks existence first; a second run is
  all no-ops / skips.
- `backup_and_link` never clobbers — pre-existing real files are timestamp-backed-up before linking.
- `--dry-run` previews all actions without touching the system.
- Non-`apt` system → `packages.sh` exits early with an explanatory message (apt is in scope only).

## 8. Secrets / machine-specific values

- `~/.zshrc.local` is sourced if present and is **never** committed. It holds anything machine- or
  work-specific: proxies, tokens, work-only PATH entries.
- `home/zshrc.local.example` documents the pattern.
- `.gitignore` includes `*.local` as a guard against accidental commits.

## 9. Migration on the current machine

- Existing `~/.zshrc` (OMZ default + `export PATH="$HOME/.local/bin:$PATH"`) → backed up to
  `~/.zshrc.backup.<ts>`, replaced by the symlink. The one custom line is preserved in
  `zsh/exports.zsh`. Nothing is lost.
- `~/.p10k.zsh` → left on disk but no longer sourced (it was never sourced anyway). User may
  delete it at will.
- This repo currently lives on `/mnt/d` (Windows mount). Sourcing config from there on every
  shell start is mildly slow under WSL; the README recommends cloning to a native path
  (`~/.my-zsh`) for daily use. Functionally works from either location.

## 10. `starship.toml` seed

A minimal, fast default (the user has no existing `starship.toml`). Starts close to Starship's
stock prompt with light tweaks; the README points to `starship preset` for richer presets the
user can adopt later.

## 11. README contents

- What the repo is and the one-command install.
- The two symlinks it creates and the backup behavior.
- How to add aliases / functions / exports (edit the repo files; changes are live via symlink).
- How to use `~/.zshrc.local` for secrets / machine-specific config.
- How to update (`git pull` — instant, since `~/.zshrc` is a symlink).
- How to uninstall (remove symlinks, restore `*.backup.*`).

## 12. Verification strategy

- **shellcheck** on all `*.sh` scripts (lint).
- **Idempotency test:** run `install.sh` twice; the second run reports only skips/no-ops.
- **Fresh-machine test:** run `install.sh` inside a clean `ubuntu:24.04` Docker container to
  exercise the true "new machine" path end-to-end (zsh installed, OMZ present, plugins active,
  Starship prompt renders) without risking the real `~`.
- **`--dry-run`** as the always-available local smoke test.

## 13. Out of scope (YAGNI)

- Non-zsh dotfiles (git, vim/nvim, tmux, …).
- macOS / Homebrew / non-apt package managers.
- GNU Stow or other symlink frameworks (a transparent hand-rolled loop has zero extra deps).
- Bare-repo or copy-based deployment mechanisms.

## 14. Open questions

None blocking. The `starship.toml` seed contents are a detail to settle during implementation
(start minimal; user iterates).
