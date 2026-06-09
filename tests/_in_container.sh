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
