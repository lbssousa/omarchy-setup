# Managed by omarchy-setup (playbooks/user/fish.yml) — port of
# $OMARCHY_PATH/default/bash/aliases

# Open files with the default application, detached from the shell
function open --description 'Open files with xdg-open, detached'
    # disown: no job left behind, like bash's ( … & ) subshell.
    xdg-open $argv >/dev/null 2>&1 &
    disown
end
