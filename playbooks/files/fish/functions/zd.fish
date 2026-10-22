# Managed by omarchy-setup (playbooks/user/fish.yml) — port of
# $OMARCHY_PATH/default/bash/aliases

# cd that falls back to zoxide for names that aren't directories
function zd --description 'cd, or jump with zoxide when the argument is not a directory'
    # __zoxide_cd_internal is zoxide's copy of fish's own cd, which
    # (unlike builtin cd) keeps dirprev, so cd -, prevd and cdh work.
    if test (count $argv) -eq 0
        __zoxide_cd_internal ~; or return
    else if test -d "$argv[1]"
        __zoxide_cd_internal $argv[1]; or return
    else
        if not z $argv
            echo 'Error: Directory not found'
            return 1
        end
        printf '\U000F17A9 '
        pwd
    end
end
