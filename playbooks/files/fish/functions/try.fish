# Managed by omarchy-setup (playbooks/fish.yml) — port of
# $OMARCHY_PATH/default/bash/init

# Load try's real function on first use, like Omarchy's bash init.
function try --description 'Ephemeral workspace manager (loads try on first use)'
    if not command -q try
        echo "try is not installed" >&2
        return 127
    end
    set -l init (SHELL=/usr/bin/fish command try init ~/Work/tries | string collect)
    # Without a real definition, calling try again would autoload this file
    # and loop forever.
    if not string match -q '*function try*' -- $init
        echo "try init did not produce a fish function" >&2
        return 1
    end
    functions -e try
    echo $init | source
    try $argv
end
