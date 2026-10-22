# Managed by omarchy-setup (playbooks/user/fish.yml) — port of
# $OMARCHY_PATH/default/bash/fns/drives

# Format an entire drive for a single partition using exFAT
function format-drive --description 'Format a whole drive as one exFAT partition'
    if test (count $argv) -ne 2
        echo "Usage: format-drive <device> <name>"
        echo "Example: format-drive /dev/sda 'My Stuff'"
        printf '\nAvailable drives:\n'
        lsblk -d -o NAME -n | awk '{print "/dev/"$1}'
    else
        echo "WARNING: This will completely erase all data on $argv[1] and label it '$argv[2]'."
        read -P "Are you sure you want to continue? (y/N): " confirm

        if string match -rq '^[Yy]$' -- $confirm
            sudo wipefs -a $argv[1]
            sudo dd if=/dev/zero of=$argv[1] bs=1M count=100 status=progress
            sudo parted -s $argv[1] mklabel gpt
            sudo parted -s $argv[1] mkpart primary 1MiB 100%
            sudo parted -s $argv[1] set 1 msftdata on

            set -l partition $argv[1]1
            string match -q '*nvme*' -- $argv[1]; and set partition $argv[1]p1
            sudo partprobe $argv[1]; or true
            sudo udevadm settle; or true

            sudo mkfs.exfat -n $argv[2] $partition

            echo "Drive $argv[1] formatted as exFAT and labeled '$argv[2]'."
        end
    end
end
