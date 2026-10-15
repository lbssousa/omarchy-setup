# Managed by omarchy-setup (playbooks/fish.yml) — port of
# $OMARCHY_PATH/default/bash/fns/ssh-port-forwarding

# List SSH port forwards started by fip
function lip --description 'List SSH port forwards started by fip'
    pgrep -af "ssh.*-L [0-9]+:localhost:[0-9]+"; or echo "No active forwards"
end
