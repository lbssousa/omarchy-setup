# Managed by omarchy-setup (playbooks/fish.yml) — port of
# $OMARCHY_PATH/default/bash/fns/herdr

# Echo a split ratio as a float
# Usage: _herdr_ratio <numerator> <denominator>
function _herdr_ratio
    awk -v a=$argv[1] -v b=$argv[2] 'BEGIN { printf "%.4f", a / b }'
end
