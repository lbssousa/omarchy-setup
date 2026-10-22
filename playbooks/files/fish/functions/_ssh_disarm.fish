# Managed by omarchy-setup (playbooks/user/fish.yml) — port of
# $OMARCHY_PATH/default/bash/fns/ssh-reconnect

# Disarm mouse tracking (1000/1002/1003, 1006 encoding), focus reporting
# (1004), and the alternate screen (1049), and show the cursor again.
function _ssh_disarm
    printf '\e[?1000l\e[?1002l\e[?1003l\e[?1006l\e[?1004l\e[?1049l\e[?25h'
end
