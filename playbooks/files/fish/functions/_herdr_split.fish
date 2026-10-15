# Managed by omarchy-setup (playbooks/fish.yml) — port of
# $OMARCHY_PATH/default/bash/fns/herdr

# Split a herdr pane and echo the id of the new pane
# Usage: _herdr_split <pane_id> <right|down> <ratio> <cwd>
function _herdr_split
    herdr pane split $argv[1] --direction $argv[2] --ratio $argv[3] --cwd $argv[4] --no-focus |
        jq -r '.result.pane.pane_id'
end
