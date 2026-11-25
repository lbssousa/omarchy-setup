# Managed by omarchy-setup (playbooks/user/fish.yml) — port of
# $OMARCHY_PATH/default/bash/fns/rsyncing

# List the rsync-on-change watchers started by rsw
function lsw --description 'List rsw watchers'
    set -l found 0
    # The arguments come from /proc/<pid>/cmdline, NUL-separated, so a path
    # with spaces stays one argument.
    for pid in (pgrep -f 'rsw-watch ')
        test -r /proc/$pid/cmdline; or continue
        set -l args (string split0 < /proc/$pid/cmdline)
        set -l i (contains -i -- rsw-watch $args); or continue
        set -l src (math $i + 1)
        set -l dest (math $i + 2)
        test (count $args) -ge $dest; or continue
        echo "$pid: $args[$src] -> $args[$dest]"
        set found 1
    end
    test $found -eq 1; or echo "No active watches"
end
