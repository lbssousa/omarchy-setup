# Managed by omarchy-setup (playbooks/fish.yml) — port of
# $OMARCHY_PATH/default/bash/fns/tmux

# Create multiple tdl windows with one per subdirectory in the current directory
# Usage: tdlm <c|cx|codex|other_ai> [<second_ai>]
function tdlm --description 'One tdl window per subdirectory'
    if test -z "$argv[1]"
        echo "Usage: tdlm <c|cx|codex|other_ai> [<second_ai>]"
        return 1
    end
    if test -z "$TMUX"
        echo "You must start tmux to use tdlm."
        return 1
    end

    set -l base_dir $PWD
    set -l first true

    # The command typed into each pane, quoted for the fish running there.
    # (The bash original pastes the arguments unquoted and the directory
    # between single quotes, which breaks on names holding a quote.)
    set -l tdl_command (string join ' ' tdl (string escape -- $argv[1..2]))

    # Rename the session to the current directory name (replace dots/colons which tmux disallows)
    tmux rename-session "$(path basename -- $base_dir | string replace -a -r '[.:]' -)"

    for dir in $base_dir/*/
        test -d $dir; or continue
        set -l dirpath (string replace -r '/$' '' -- $dir)

        if test $first = true
            # Reuse the current window for the first project
            tmux send-keys -t $TMUX_PANE "cd "(string escape -- $dirpath)" && $tdl_command" C-m
            set first false
        else
            set -l pane_id (tmux new-window -c $dirpath -P -F '#{pane_id}')
            tmux send-keys -t $pane_id $tdl_command C-m
        end
    end
end
