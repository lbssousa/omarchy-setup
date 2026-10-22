# Managed by omarchy-setup (playbooks/user/fish.yml) — port of
# $OMARCHY_PATH/default/bash/fns/rsyncing

# List the rsync-on-change watchers started by rsw
function lsw --description 'List rsw watchers'
    set -l found 0
    for line in (pgrep -af 'rsw-watch ')
        set -l pid (string split -m1 ' ' -- $line)[1]
        set -l rest (string replace -r '.*rsw-watch ' '' -- $line)
        echo "$pid: "(string replace -r ' [^ ]*$' '' -- $rest)" -> "(string replace -r '.* ' '' -- $rest)
        set found 1
    end
    test $found -eq 1; or echo "No active watches"
end
