# Managed by omarchy-setup (playbooks/fish.yml) — port of
# $OMARCHY_PATH/default/bash/fns/rsyncing

# Stop every rsync-on-change watcher started by rsw
function dsw --description 'Stop rsw watchers'
    set -l found 0
    for pid in (pgrep -f 'rsw-watch ')
        if kill -- -$pid 2>/dev/null
            echo "Stopped watch (pid $pid)"
            set found 1
        end
    end
    test $found -eq 1; or echo "No active watches"
end
