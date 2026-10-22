# Managed by omarchy-setup (playbooks/user/fish.yml) — port of
# $OMARCHY_PATH/default/bash/aliases

# Send a fuzzy-found file (newest first) somewhere with scp
function sff --description 'scp a fuzzy-found file to a destination'
    if test (count $argv) -eq 0
        echo 'Usage: sff <destination> (e.g. sff host:/tmp/)'
        return 1
    end
    set -l file (find . -type f -printf '%T@\t%p\n' | sort -rn | cut -f2- | ff)
    test -n "$file"; and scp "$file" $argv[1]
end
