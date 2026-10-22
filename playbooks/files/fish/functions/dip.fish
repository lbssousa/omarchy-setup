# Managed by omarchy-setup (playbooks/user/fish.yml) — port of
# $OMARCHY_PATH/default/bash/fns/ssh-port-forwarding

# Stop SSH port forwards started by fip
function dip --description 'Stop SSH port forwards started by fip'
    if test (count $argv) -eq 0
        echo "Usage: dip <port1> [port2] ..."
        return 1
    end
    for port in $argv
        if pkill -f "ssh.*-L $port:localhost:$port"
            echo "Stopped forwarding port $port"
        else
            echo "No forwarding on port $port"
        end
    end
end
