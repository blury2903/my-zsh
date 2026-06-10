# Personal aliases. Sourced by ~/.zshrc AFTER oh-my-zsh so these win.

# eza (modern ls) — only when installed, so plain `ls` still works otherwise.
if command -v eza >/dev/null; then
  alias ls='eza --group-directories-first'
  alias ll='eza -lh --group-directories-first --git'
  alias la='eza -lah --group-directories-first --git'
  alias lt='eza --tree --level=2 --group-directories-first'
fi

# Examples — uncomment or add your own:
# alias gs='git status'
# alias ..='cd ..'
