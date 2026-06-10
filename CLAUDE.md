# CLAUDE.md

Portable **zsh-only** dotfiles repo for **WSL2 / Debian / Ubuntu (apt)**. `install.sh`
bootstraps dependencies (zsh, oh-my-zsh, plugins, Starship) and symlinks config onto a
fresh machine. Prompt is **Starship** (not a zsh theme).

## ⚠️ Safety — read before running anything

`install.sh` and `bootstrap/*.sh` MODIFY THE REAL MACHINE: they `sudo apt-get install`,
`curl | sh` installers, clone plugins, and replace `~/.zshrc` / `~/.config/starship.toml`.
- **Never run them without `--dry-run`** unless the user explicitly wants a real install.
- `./install.sh --dry-run` previews every action and changes nothing. Use it to verify.

## Architecture / invariants (don't break these)

- **Exactly two symlinks**: `~/.zshrc → zsh/zshrc`, `~/.config/starship.toml → starship/starship.toml`.
  The `zsh/*.zsh` modules are **sourced**, not symlinked.
- **`zsh/zshrc` self-locates the repo** via `ZSH_DOTFILES="${${(%):-%x}:A:h}"` — this resolves
  the symlink to find the repo from any clone path. Do not "simplify" it to `$0`/`$PWD`.
- **Load order in `zsh/zshrc` matters**: `ZSH_THEME=""`, `plugins=(...)`, and `exports.zsh`
  must come BEFORE `source $ZSH/oh-my-zsh.sh`; `aliases.zsh`/`functions.zsh` AFTER.
- **Every `bootstrap/*.sh` must stay idempotent** (skip if already done) and **honor `DRY_RUN`**
  (exported by `install.sh`). Source `lib/helpers.sh` for `log`/`warn`/`error`/`have`/`backup_and_link`.
- **`install.sh` runs the bootstrap scripts in a fixed order**: `packages → oh-my-zsh → plugins →
  starship`. `plugins.sh` clones into `$ZSH_CUSTOM/plugins/`, so it must run *after* oh-my-zsh exists.
- **Adding a zsh plugin touches two files**: add the name to `plugins=(...)` in `zsh/zshrc` AND a
  matching `clone_plugin` line in `bootstrap/plugins.sh` — oh-my-zsh only loads a plugin that has
  already been cloned, so these must stay in sync.
- **Secrets / machine-specific config** go in `~/.zshrc.local` (sourced last, gitignored via
  `*.local`) — never commit them. `home/zshrc.local.example` is the template.

## Conventions

- **Commits: Conventional Commits, and NO `Co-Authored-By` trailer.**
- **Bash** files (`install.sh`, `lib/`, `bootstrap/`, `tests/*.sh`): `set -euo pipefail`; keep
  `shellcheck -s bash -x` clean (SC1091 on the sourced helper is the only acceptable info).
- **Zsh** files (`zsh/zshrc`, `zsh/*.zsh`): check with **`zsh -n`**, NOT shellcheck (shellcheck
  doesn't understand zsh syntax and will report false errors).

## Testing

```bash
bats tests/helpers.bats     # unit tests for backup_and_link (the only real logic)
shellcheck -s bash -x install.sh lib/helpers.sh bootstrap/*.sh tests/*.sh
for f in zsh/zshrc zsh/*.zsh; do zsh -n "$f"; done
./install.sh --dry-run      # safe end-to-end preview
./tests/fresh-machine.sh    # full Docker E2E; auto-skips if docker is absent
```

Dev tools `bats` and `shellcheck` are required to run the tests. `tests/_in_container.sh` holds the
in-container assertions and runs a **real** (non-`--dry-run`) install — it's only safe because
`fresh-machine.sh` invokes it inside Docker; never run it directly on your host.

## Design docs

Spec and plan live in `docs/superpowers/specs/` and `docs/superpowers/plans/`.
