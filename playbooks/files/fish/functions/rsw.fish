# Managed by omarchy-setup (playbooks/fish.yml) — port of
# $OMARCHY_PATH/default/bash/fns/rsyncing

# Rsync-on-change watchers: rsw starts one in the background, lsw lists, dsw stops
function rsw --description 'Rsync a directory to a destination on every change, in the background'
    if test (count $argv) -ne 2
        echo "Usage: rsw <source> <destination>"
        return 1
    end
    set -l src (string replace -r '/$' '' -- $argv[1])
    set -l dest $argv[2]
    # Reuse one SSH connection per login, so 1Password only prompts once.
    set -l sockets $XDG_RUNTIME_DIR
    test -n "$sockets"; or set sockets $HOME/.ssh/sockets
    mkdir -p $sockets
    set -l rsh "ssh -o ControlMaster=auto -o ControlPath=$sockets/rsw-%r@%h:%p -o ControlPersist=yes"
    # The watcher itself stays a bash loop named rsw-watch, as in Omarchy's
    # bash function, so lsw/dsw find watchers started from either shell.
    setsid --fork env RSYNC_RSH=$rsh bash -c 'rsync -a "$1/" "$2"; while inotifywait -r -q -e modify,create,delete,move "$1"; do rsync -a "$1/" "$2"; done' rsw-watch $src $dest >/dev/null 2>&1
    echo "Watching $src -> $dest"
end
