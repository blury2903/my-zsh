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

1. `apt` installs `zsh`, `git`, `curl`, plus the CLI tools `fzf` (fuzzy finder),
   `zoxide` (`z` directory jumping), and `eza` (modern `ls`; needs Ubuntu 24.04+/Debian 13+).
2. Installs oh-my-zsh (keeping this repo's `.zshrc`).
3. Clones `zsh-autosuggestions`, `zsh-syntax-highlighting`, and `zsh-history-substring-search`.
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
ls -1 ~/.zshrc.backup.* ~/.config/starship.toml.backup.* 2>/dev/null
```

## Tests

```bash
bats tests/helpers.bats     # unit tests for the install helpers
./tests/fresh-machine.sh    # full new-machine run in a Docker container (skips if no docker)
```
