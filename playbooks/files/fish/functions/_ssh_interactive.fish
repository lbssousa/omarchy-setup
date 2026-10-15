# Managed by omarchy-setup (playbooks/fish.yml) — port of
# $OMARCHY_PATH/default/bash/fns/ssh-reconnect

# True for an interactive session: a destination and no remote command. The
# letters are the ssh(1) options that consume a value, so their arguments are
# not mistaken for the destination.
function _ssh_interactive
    set -l value_opts (string split '' BbcDEeFIiJLlmOoPpQRSWw)
    set -l all_args $argv
    set -l dest ""
    set -l opts_done ""

    while set -q argv[1]
        set -l arg $argv[1]
        set -e argv[1]

        if test -z "$opts_done"; and test "$arg" = --
            set opts_done 1
        else if test -z "$opts_done"; and string match -qr -- '^-.' $arg
            set -l letters (string split '' -- (string sub -s 2 -- $arg))
            for i in (seq (count $letters))
                if contains -- $letters[$i] $value_opts
                    # The value is glued to the letter (-p2222) unless the letter ends
                    # the argument, in which case it consumes the next one (-p 2222).
                    test $i -eq (count $letters); and set -e argv[1]
                    break
                end
            end
        else if test -z "$dest"
            set dest $arg
        else
            return 1
        end
    end

    test -n "$dest"; or return 1

    # A RemoteCommand from ssh_config or -o replays on reconnect just like a
    # positional command; ssh -G resolves the effective configuration for this
    # exact invocation without connecting. Fail closed when it cannot resolve,
    # since an undetected RemoteCommand must not replay. The explicit "none"
    # cancels a configured command, and some versions emit it when unset.
    set -l resolved (command ssh -G $all_args 2>/dev/null); or return 1
    not string match -ri -- '^remotecommand ' $resolved | string match -qvir -- '^remotecommand none$'
end
