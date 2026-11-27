# Managed by omarchy-setup (playbooks/user/fish.yml) — port of
# $OMARCHY_PATH/default/bash/aliases

# Open a fuzzy-found file in the editor
function eff --description 'Open a fuzzy-found file in $EDITOR'
    # The pick is quoted for eval, so names with spaces open intact, a
    # cancelled pick opens nothing, and any arguments go to the editor
    # after the file, as Omarchy's eff does since 4.6.
    set -l file (ff); or return
    test -n "$file"; or return
    eval $EDITOR (string escape -- $file $argv)
end
