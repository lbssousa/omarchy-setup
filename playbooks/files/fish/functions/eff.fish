# Managed by omarchy-setup (playbooks/fish.yml) — port of
# $OMARCHY_PATH/default/bash/aliases

# Open a fuzzy-found file in the editor
function eff --description 'Open a fuzzy-found file in $EDITOR'
    # The pick is quoted for eval, so names with spaces open intact,
    # and a cancelled pick opens nothing (bash opens an empty editor).
    set -l file (ff); or return
    eval $EDITOR (string escape -- $file)
end
