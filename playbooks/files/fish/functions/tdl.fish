# Managed by omarchy-setup (playbooks/user/fish.yml) — port of
# $OMARCHY_PATH/default/bash/fns/tmux

# Create a Tmux Dev Layout with editor, ai, and terminal
# Usage: tdl <c|cx|codex|other_ai> [<second_ai>]
function tdl --description 'Tmux dev layout: editor, AI and terminal'
    if test -z "$argv[1]"
        echo "Usage: tdl <c|cx|codex|other_ai> [<second_ai>]"
        return 1
    end
    if test -z "$TMUX"
        echo "You must start tmux to use tdl."
        return 1
    end

    set -l current_dir $PWD
    set -l ai $argv[1]
    set -l ai2 $argv[2]

    # Use TMUX_PANE for the pane we're running in (stable even if active window changes)
    set -l editor_pane $TMUX_PANE

    # Name the current window after the base directory name
    tmux rename-window -t $editor_pane "$(path basename -- $current_dir)"

    # Split window vertically - top 85%, bottom 15% (target editor pane explicitly)
    tmux split-window -v -p 15 -t $editor_pane -c $current_dir

    # Split editor pane horizontally - AI on right 30% (capture new pane ID directly)
    set -l ai_pane (tmux split-window -h -p 30 -t $editor_pane -c $current_dir -P -F '#{pane_id}')

    # If second AI provided, split the AI pane vertically
    if test -n "$ai2"
        set -l ai2_pane (tmux split-window -v -t $ai_pane -c $current_dir -P -F '#{pane_id}')
        tmux send-keys -t $ai2_pane $ai2 C-m
    end

    # Run ai in the right pane
    tmux send-keys -t $ai_pane $ai C-m

    # Run nvim in the left pane
    tmux send-keys -t $editor_pane "$EDITOR ." C-m

    # Select the nvim pane for focus. (The bash original selects
    # "$opencode_pane", which tdl never sets; the comment says the editor.)
    tmux select-pane -t $editor_pane
end
