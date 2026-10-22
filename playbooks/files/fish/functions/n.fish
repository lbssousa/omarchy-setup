# Managed by omarchy-setup (playbooks/user/fish.yml) — port of
# $OMARCHY_PATH/default/bash/aliases

# Neovim, on the current directory when given nothing
function n --description 'nvim, or nvim . with no arguments'
    if test (count $argv) -eq 0
        command nvim .
    else
        command nvim $argv
    end
end
