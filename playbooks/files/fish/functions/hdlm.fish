# Managed by omarchy-setup (playbooks/user/fish.yml) — port of
# $OMARCHY_PATH/default/bash/fns/herdr

# Create multiple hdl tabs with one per subdirectory in the current directory
# Usage: hdlm <c|cx|codex|other_ai> [<second_ai>]
function hdlm --description 'One hdl tab per subdirectory'
    if test -z "$argv[1]"
        echo "Usage: hdlm <c|cx|codex|other_ai> [<second_ai>]"
        return 1
    end
    if test -z "$HERDR_PANE_ID"
        echo "You must start herdr to use hdlm."
        return 1
    end

    set -l base_dir $PWD
    set -l first true

    # Quoted for the fish running in each pane (bash uses printf %q).
    set -l hdl_command (string join ' ' hdl (string escape -- $argv[1..2]))

    # Rename the workspace to the current directory name
    herdr workspace rename $HERDR_WORKSPACE_ID "$(path basename -- $base_dir)" >/dev/null

    for dir in $base_dir/*/
        test -d $dir; or continue
        set -l dirpath (string replace -r '/$' '' -- $dir)

        if test $first = true
            # Reuse the current tab for the first project
            herdr pane run $HERDR_PANE_ID "cd "(string escape -- $dirpath)" && $hdl_command" >/dev/null
            set first false
        else
            set -l pane_id (herdr tab create --workspace $HERDR_WORKSPACE_ID --cwd $dirpath --no-focus |
                jq -r '.result.root_pane.pane_id')
            herdr pane run $pane_id $hdl_command >/dev/null
        end
    end
end
