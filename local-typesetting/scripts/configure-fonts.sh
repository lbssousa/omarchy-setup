#!/bin/sh
# Exposes TeX Live's bundled fonts to fontconfig, so any other tool on this
# machine that renders text via fontconfig (LilyPond, Inkscape, ...) can find
# and use them — the same font integration distrobox-typesetting's container
# image gets.
#
# Adapted from lbssousa/distrobox-typesetting (scripts/configure-fonts.sh):
# same logic, plus a privilege check that also accepts a capabilities-only
# elevation (e.g. run0 --empower) instead of requiring UID 0. Must run after
# install-texlive.sh.
if [ -z "${BASH_VERSION:-}" ]; then
    if ! command -v bash >/dev/null 2>&1; then
        echo "ERROR: bash is required but not found." >&2
        exit 1
    fi
    exec bash "$0" "$@"
fi

set -euo pipefail

running_privileged() {
    [ "$(id -u)" -eq 0 ] && return 0
    # run0 --empower keeps the caller's UID and only grants full Linux
    # capabilities (see run0(1)), so `id -u` never becomes 0 under it —
    # check CapEff instead of assuming privilege implies UID 0.
    local capeff
    capeff="$(awk '/^CapEff:/{print $2}' /proc/self/status 2>/dev/null)"
    [ -n "${capeff//0/}" ]
}

if ! running_privileged; then
    echo "ERROR: configure-fonts.sh must run as root, or with full capabilities (e.g. via run0 --empower — it writes to /etc/fonts/conf.d)." >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "${SCRIPT_DIR}/lib/common.sh"

main() {
    local tl_fonts_dir
    tl_fonts_dir="$(find /opt/texlive -mindepth 3 -maxdepth 4 -type d \
        -name 'fonts' -path '*/texmf-dist/fonts' 2>/dev/null | head -1 || true)"

    if [ -z "${tl_fonts_dir}" ]; then
        echo "WARNING: TeX Live fonts directory not found under /opt/texlive." >&2
        echo "         Run install-texlive.sh before configure-fonts.sh." >&2
        exit 1
    fi

    if ! command -v fc-cache >/dev/null 2>&1; then
        update_pkg_index
        pkg_install fontconfig
    fi

    echo "Registering TeX Live fonts with fontconfig: ${tl_fonts_dir}"
    mkdir -p /etc/fonts/conf.d
    cat > /etc/fonts/conf.d/09-texlive-fonts.conf <<EOF
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <dir>${tl_fonts_dir}/opentype</dir>
  <dir>${tl_fonts_dir}/truetype</dir>
  <dir>${tl_fonts_dir}/type1</dir>
</fontconfig>
EOF
    fc-cache -f
    echo "TeX Live fonts registered."
}

main
