# Managed by omarchy-setup (playbooks/user/fish.yml) — port of
# $OMARCHY_PATH/default/bash/fns/tmux

# Create a multi-pane swarm layout with the same command started in each pane (great for AI)
# Usage: tsl <pane_count> <command>
function tsl --description 'Tmux swarm: the same command in N tiled panes'
    # A positive count, then the command: one argument run as it is, or
    # several, each quoted, as Omarchy's tsl takes them since 4.6.
    if not string match -qr '^[1-9][0-9]*$' -- "$argv[1]"; or test -z "$argv[2]"
        echo "Usage: tsl <pane_count> <command>"
        return 1
    end
    if test -z "$TMUX"
        echo "You must start tmux to use tsl."
        return 1
    end

    set -l count $argv[1]
    set -l cmd $argv[2]
    if test (count $argv) -gt 2
        set cmd (string join -- ' ' (string escape -- $argv[2..]))
    end
    set -l current_dir $PWD
    set -l panes $TMUX_PANE

    tmux rename-window -t $TMUX_PANE "$(path basename -- $current_dir)"

    while test (count $panes) -lt $count
        set -l new_pane (tmux split-window -h -t $panes[-1] -c $current_dir -P -F '#{pane_id}')
        set -a panes $new_pane
        tmux select-layout -t $panes[1] tiled
    end

    for pane in $panes
        tmux send-keys -t $pane $cmd C-m
    end

    tmux select-pane -t $panes[1]
end
