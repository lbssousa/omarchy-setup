# Managed by omarchy-setup (playbooks/user/fish.yml) — port of
# $OMARCHY_PATH/default/bash/fns/compression

# Compress a file or directory into <name>.tar.gz
function compress --description 'tar.gz a file or directory'
    set -l target (string replace -r '/+$' '' $argv[1])
    tar -czf "$target.tar.gz" "$target"
end
