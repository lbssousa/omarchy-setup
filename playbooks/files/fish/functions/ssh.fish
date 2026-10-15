# Managed by omarchy-setup (playbooks/fish.yml) — port of
# $OMARCHY_PATH/default/bash/fns/ssh-reconnect

# Wrap ssh to clean up the terminal and reconnect when a connection drops.
#
# A remote tmux, herdr, or editor arms terminal modes over the SSH pipe (mouse
# tracking, focus reporting, the alternate screen) that only it can disarm. If
# the connection dies instead of exiting cleanly, those modes stay armed on the
# local terminal, and every mouse move floods the prompt with escape junk.
function ssh --wraps ssh --description 'ssh that cleans up the terminal and reconnects dropped sessions'
    set -l started (date +%s)
    command ssh $argv
    set -l rc $status

    isatty stdout; or return $rc
    _ssh_disarm

    # Reconnect only when an interactive session drops: ssh exits 255 for
    # transport failures, but a fast 255 with no established session is a
    # connect/auth failure, a remote command's own 255 passes through
    # indistinguishably and must not replay its side effects, and redirected
    # stdin would feed the remaining piped input to a fresh remote shell.
    if test $rc -ne 255; or not isatty stdin; or not _ssh_interactive $argv
        or test (math (date +%s) - $started) -lt 30
        return $rc
    end

    # Ctrl-C reaches the whole foreground process group, and fish stops the
    # running function when a child dies of SIGINT, so it cancels both the
    # in-flight attempt and the loop (bash needs a subshell for that). Keep
    # retrying fast failures, since a rebooting server refuses connections too.
    while true
        echo "Connection lost. Reconnecting (Ctrl-C to stop)..."
        sleep 2
        command ssh $argv
        set rc $status
        _ssh_disarm
        test $rc -ne 255; and return $rc
    end
end
