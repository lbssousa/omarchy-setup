# Managed by omarchy-setup (playbooks/fish.yml) — port of
# $OMARCHY_PATH/default/bash/fns/herdr

# Create a Herdr Dev Square layout with editor, diff watch, terminal, and opencode
# Usage: hds
function hds --description 'Herdr dev square: editor, diff watch, terminal and opencode'
    if test -n "$argv[1]"
        echo "Usage: hds"
        return 1
    end
    if test -z "$HERDR_PANE_ID"
        echo "You must start herdr to use hds."
        return 1
    end

    set -l current_dir $PWD
    set -l editor_pane $HERDR_PANE_ID

    herdr tab rename $HERDR_TAB_ID "$(path basename -- $current_dir)" >/dev/null

    set -l terminal_pane (_herdr_split $editor_pane down 0.5 $current_dir)
    set -l diff_pane (_herdr_split $editor_pane right 0.5 $current_dir)
    set -l opencode_pane (_herdr_split $terminal_pane right 0.5 $current_dir)

    herdr pane run $editor_pane "nvim ." >/dev/null
    herdr pane run $diff_pane "hunk diff --watch" >/dev/null
    herdr pane run $opencode_pane opencode >/dev/null
end
