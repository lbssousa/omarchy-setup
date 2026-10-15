# Managed by omarchy-setup (playbooks/fish.yml) — port of
# $OMARCHY_PATH/default/bash/fns/herdr

# Create a multi-pane swarm layout with the same command started in each pane (great for AI)
# Usage: hsl <pane_count> <command>
function hsl --description 'Herdr swarm: the same command in an N-pane grid'
    if test -z "$argv[1]"; or test -z "$argv[2]"
        echo "Usage: hsl <pane_count> <command>"
        return 1
    end
    if test -z "$HERDR_PANE_ID"
        echo "You must start herdr to use hsl."
        return 1
    end

    set -l count $argv[1]
    set -l cmd $argv[2]
    set -l current_dir $PWD

    herdr tab rename $HERDR_TAB_ID "$(path basename -- $current_dir)" >/dev/null

    # Tile into a grid: ceil(sqrt(count)) columns, rows spread across them
    set -l cols 1
    while test (math "$cols * $cols") -lt $count
        set cols (math $cols + 1)
    end

    # Even columns come from splitting the rightmost one off at 1/(n-k+1) each time,
    # which keeps the list in left-to-right order
    set -l columns $HERDR_PANE_ID
    for k in (seq 1 (math $cols - 1))
        set -a columns (_herdr_split $columns[-1] right (_herdr_ratio 1 (math $cols - $k + 1)) $current_dir)
    end

    # Split each column into its share of rows, again evenly and top-to-bottom
    set -l panes
    for index in (seq 0 (math $cols - 1))
        set -l col $columns[(math $index + 1)]
        set -l rows (math "floor($count / $cols)")
        if test $index -lt (math "$count % $cols")
            set rows (math $rows + 1)
        end
        set -a panes $col
        set -l last $col
        for j in (seq 1 (math $rows - 1))
            set last (_herdr_split $last down (_herdr_ratio 1 (math $rows - $j + 1)) $current_dir)
            set -a panes $last
        end
    end

    for pane in $panes
        herdr pane run $pane $cmd >/dev/null
    end
end
