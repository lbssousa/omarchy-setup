# Managed by omarchy-setup (playbooks/fish.yml) — port of
# $OMARCHY_PATH/default/bash/{env-bootstrap,envs,aliases,init}
#
# Installed as a vendor conf.d file, so it runs before ~/.config/fish/
# config.fish: anything set there overrides what's set here.

# ---- Environment (mirrors env-bootstrap and envs) ----
# /etc/omarchy.conf is written by omarchy-dev-link and reset by
# omarchy-dev-unlink. When absent, force the packaged default instead
# of preserving a stale inherited value. It's shell code, so sh reads it,
# as bash's `source` does.
if test -f /etc/omarchy.conf
    set -gx OMARCHY_PATH (sh -c '. /etc/omarchy.conf; printf %s "${OMARCHY_PATH:-/usr/share/omarchy}"')
else
    set -gx OMARCHY_PATH /usr/share/omarchy
end
# Only prepend in dev-link mode; packaged binaries are already in /usr/bin.
set -l omarchy_bin (string replace -r '/$' '' -- $OMARCHY_PATH)/bin
if test "$OMARCHY_PATH" != /usr/share/omarchy; and not contains -- $omarchy_bin $PATH
    set -gx PATH $omarchy_bin $PATH
end

if not contains $HOME/.local/share/mise/shims $PATH
    set -gx PATH $PATH $HOME/.local/share/mise/shims
end
if not contains $HOME/.local/bin $PATH
    set -gx PATH $PATH $HOME/.local/bin
end

if not set -q EDITOR
    set -gx EDITOR 'omarchy-launch-editor --inline'
end
if not set -q SUDO_EDITOR
    set -gx SUDO_EDITOR $EDITOR
end
if not set -q BROWSER
    set -gx BROWSER omarchy-launch-browser
end
set -gx BAT_THEME ansi
set -gx MANROFFOPT -c
set -gx MANPAGER "sh -c 'col -bx | bat -l man -p'"

if not set -q LANG
    set -gx LANG C.UTF-8
end

# Bash starts without a banner; so does fish.
set -g fish_greeting

# ---- Aliases (mirrors aliases) ----
# An alias is a function defined right here, at startup, so it would win
# over a function file of yours with the same name. Skip the ones you
# define yourself in ~/.config/fish/functions/.
function __omarchy_alias
    test -e $__fish_config_dir/functions/$argv[1].fish; and return
    alias $argv
end

# File system
if command -q eza
    __omarchy_alias ls 'eza -lh --group-directories-first --icons=auto'
    __omarchy_alias lsa 'ls -a'
    __omarchy_alias lt 'eza --tree --level=2 --long --icons --git'
    __omarchy_alias lta 'lt -a'
end

if test "$TERM" = xterm-kitty
    __omarchy_alias ff "fzf --preview 'case \$(file --mime-type -b {}) in image/*) kitty icat --clear --transfer-mode=memory --stdin=no --place=\${FZF_PREVIEW_COLUMNS}x\${FZF_PREVIEW_LINES}@0x0 {} ;; *) bat --style=numbers --color=always {} ;; esac'"
else
    __omarchy_alias ff "fzf --preview 'bat --style=numbers --color=always {}'"
end

# Navigation: cd is zd (autoloaded) when zoxide is around.
if command -q zoxide
    __omarchy_alias cd zd
end

# Directories
__omarchy_alias .. 'cd ..'
__omarchy_alias ... 'cd ../..'
__omarchy_alias .... 'cd ../../..'

# Tools (tdl and the other layouts are autoloaded functions)
__omarchy_alias a 'omarchy-agent --inline'
__omarchy_alias c 'opencode --auto'
__omarchy_alias cx 'printf "\033[2J\033[3J\033[H" && claude --permission-mode auto'
__omarchy_alias cy 'codex --approve-for-me'
__omarchy_alias d docker
__omarchy_alias r rails
__omarchy_alias t 'tmux attach || tmux new -s Work'
__omarchy_alias h herdr
__omarchy_alias ic 'tdl c'
__omarchy_alias ix 'tdl cx'
__omarchy_alias icx 'tdl c cx'
__omarchy_alias mup 'MISE_MINIMUM_RELEASE_AGE=0 mise up'

# Git
__omarchy_alias g git
__omarchy_alias gcm 'git commit -m'
__omarchy_alias gcam 'git commit -a -m'
__omarchy_alias gcad 'git commit -a --amend'

# Compression (compress is autoloaded)
__omarchy_alias decompress 'tar -xzf'

functions -e __omarchy_alias

# ---- Tools (mirrors init; mise activates itself from its own vendor conf.d) ----
if command -q zoxide
    zoxide init fish | source
end

if status is-interactive
    # Prompt: same Starship configuration as Omarchy/bash.
    if command -q starship
        starship init fish | source
    end
    if command -q fzf
        # fzf's own bindings, as Omarchy's bash loads them (Ctrl+R, Ctrl+T, Alt+C).
        functions -q fzf_key_bindings; and fzf_key_bindings
        # fzf.fish (playbooks/fish.yml installs it) bound its keys from its
        # own conf.d before this file ran, and fzf_key_bindings just took
        # Ctrl+R back: bind them again so its history search, with preview,
        # stays on Ctrl+R.
        functions -q fzf_configure_bindings; and fzf_configure_bindings
    end
end
