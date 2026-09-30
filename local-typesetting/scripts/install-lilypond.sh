#!/bin/sh
# Installs LilyPond from the official precompiled package on x86_64 glibc
# systems, builds from source on non-x86_64 glibc systems and on Alpine when
# TeX Live is present, or falls back to the distro package manager otherwise.
#
# Adapted from lbssousa/distrobox-typesetting (scripts/install-lilypond.sh):
# same install logic, plus VERSION=latest support (resolved against
# LilyPond's own GitLab releases), meant to be run with root privileges
# directly on the host (e.g. via run0) instead of inside a container build.
#
# bash is needed for arrays (_BUILD_PKGS_TO_REMOVE, see common.sh).
VERSION="${VERSION:-latest}"

if [ -z "${BASH_VERSION:-}" ]; then
    if ! command -v bash >/dev/null 2>&1; then
        echo "ERROR: bash is required but not found." >&2
        exit 1
    fi
    exec bash "$0" "$@"
fi

# ---- bash only below this line ----
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
    echo "ERROR: install-lilypond.sh must run as root, or with full capabilities (e.g. via run0 --empower — it writes to /opt and /usr/local/bin)." >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "${SCRIPT_DIR}/lib/common.sh"

DOWNLOAD_DIR="$(mktemp -d)"
_BUILD_PKGS_TO_REMOVE=()

cleanup() {
    rm -rf "${DOWNLOAD_DIR}"
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Resolve VERSION=latest against LilyPond's own GitLab releases, so this
# script never needs a hardcoded version bumped by hand.
# ---------------------------------------------------------------------------
resolve_latest_version() {
    echo "Resolving latest LilyPond release..." >&2
    local tag
    tag="$(curl -sSfL "https://gitlab.com/api/v4/projects/lilypond%2Flilypond/releases" \
        | grep -o '"tag_name":"[^"]*"' | head -1 \
        | sed 's/"tag_name":"\([^"]*\)"/\1/')"
    if [ -z "${tag}" ]; then
        echo "ERROR: could not resolve the latest LilyPond release from GitLab." >&2
        exit 1
    fi
    echo "${tag#v}"
}

# ---------------------------------------------------------------------------
# TeX Live availability detection
# ---------------------------------------------------------------------------
has_texlive() {
    command -v kpsewhich >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Symlink versioned binaries into /usr/local/bin
# ---------------------------------------------------------------------------
setup_path() {
    for bin in "${LILYPOND_PREFIX}/bin"/*; do
        [ -e "${bin}" ] || continue
        local name
        name="$(basename "${bin}")"
        ln -sf "${bin}" "/usr/local/bin/${name}"
    done
}

# ---------------------------------------------------------------------------
# Installation strategies
# ---------------------------------------------------------------------------

# Primary path: official precompiled tarball (x86_64 glibc systems only).
install_from_official() {
    local version="$1"
    local url="https://gitlab.com/lilypond/lilypond/-/releases/v${version}/downloads/lilypond-${version}-linux-x86_64.tar.gz"

    echo "Installing LilyPond ${version} from official precompiled package."
    update_pkg_index
    # Keep fontconfig at runtime; ca-certificates is build-only. curl itself
    # is already installed system-wide by install-texlive.sh. Downloaded
    # with curl, not wget: Fedora's wget is actually wget2, which mishandles
    # GitLab's release-download redirect (302 to its package registry,
    # which then 404s) even though the URL itself is fine.
    pkg_install fontconfig
    install_build_deps ca-certificates

    echo "Downloading: ${url}"
    curl -sSfL -o "${DOWNLOAD_DIR}/lilypond.tar.gz" "${url}"

    mkdir -p "${LILYPOND_PREFIX}"
    tar -xzf "${DOWNLOAD_DIR}/lilypond.tar.gz" \
        --strip-components=1 \
        -C "${LILYPOND_PREFIX}"

    remove_build_deps
    setup_path
}

# Builds LilyPond from source. Used when the official precompiled binary is not
# available (non-x86_64 architecture) or cannot run (Alpine/musl libc).
#
# LilyPond 2.26.x requires Guile 3.0 >= 3.0.7.
# LilyPond 2.24.x accepts Guile 2.2 or 3.0.
# Build time: ~30 minutes on a typical machine.
install_from_source() {
    local version="$1"
    local url="https://gitlab.com/lilypond/lilypond/-/archive/v${version}/lilypond-v${version}.tar.gz"
    local arch
    arch="$(uname -m)"

    echo "Building LilyPond ${version} from source (arch: ${arch}). This may take 30+ minutes."
    update_pkg_index

    # Runtime dependencies — kept after the build.
    if is_debian_like; then
        pkg_install \
            guile-3.0 ghostscript python3 perl fontconfig \
            libfreetype6 libcairo2 libpango-1.0-0 libglib2.0-0 libpng16-16
    elif is_redhat_like; then
        pkg_install \
            guile ghostscript python3 perl fontconfig \
            freetype cairo pango glib2 libpng
    elif is_alpine; then
        pkg_install \
            guile ghostscript python3 perl \
            fontconfig freetype cairo pango glib libpng
    elif is_arch_like; then
        pkg_install \
            guile ghostscript python perl fontconfig \
            freetype2 cairo pango glib2 libpng
    fi

    # Build-only dependencies — tracked for removal after the build.
    # t1utils provides t1asm, which LilyPond's configure requires for font
    # assembly (checked unconditionally even with --disable-documentation).
    if is_debian_like; then
        install_build_deps \
            g++ make autoconf automake libtool bison flex pkg-config \
            guile-3.0-dev libfreetype-dev libcairo2-dev libpango1.0-dev \
            libglib2.0-dev libfontconfig1-dev libpng-dev zlib1g-dev \
            libgc-dev gettext t1utils ca-certificates
    elif is_redhat_like; then
        install_build_deps \
            gcc-c++ make autoconf automake libtool bison flex pkgconf \
            guile-devel freetype-devel cairo-devel pango-devel glib2-devel \
            fontconfig-devel libpng-devel zlib-devel gc-devel \
            gettext t1utils ca-certificates
    elif is_alpine; then
        install_build_deps \
            g++ musl-dev make autoconf automake libtool \
            bison flex flex-dev pkgconf \
            guile-dev freetype-dev cairo-dev pango-dev glib-dev \
            fontconfig-dev libpng-dev zlib-dev gc-dev gettext-dev \
            t1utils fontforge ca-certificates
    elif is_arch_like; then
        install_build_deps \
            base-devel autoconf automake libtool bison flex pkgconf \
            guile freetype2 cairo pango glib2 fontconfig libpng zlib gc \
            gettext t1utils fontforge ca-certificates
    fi

    echo "Downloading: ${url}"
    curl -sSfL -o "${DOWNLOAD_DIR}/lilypond-src.tar.gz" "${url}"
    mkdir -p "${DOWNLOAD_DIR}/src"
    tar -xzf "${DOWNLOAD_DIR}/lilypond-src.tar.gz" \
        --strip-components=1 \
        -C "${DOWNLOAD_DIR}/src"

    cd "${DOWNLOAD_DIR}/src"
    if [ -x autogen.sh ]; then
        ./autogen.sh --noconfigure
    else
        autoreconf -fi
    fi
    PYTHON=python3 ./configure \
        --prefix="${LILYPOND_PREFIX}" \
        --disable-documentation
    make -j"$(nproc)"
    make install
    cd -

    setup_path
    remove_build_deps
}

# Install from the distribution package manager.
# Fallback for Alpine without TeX Live (the MetaPost CTAN package required by
# LilyPond's configure is not available as a discrete apk package), and for
# unknown OS families. The `version` option is ignored.
install_from_distro() {
    local arch
    arch="$(uname -m)"
    echo "Installing LilyPond from the distribution package manager (arch: ${arch}, OS: ${OS_ID})."
    echo "Note: the VERSION option is ignored for distro-package installs." >&2
    update_pkg_index
    pkg_install lilypond
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    if [ "${VERSION}" = "latest" ]; then
        VERSION="$(resolve_latest_version)"
        echo "  -> ${VERSION}"
    fi

    LILYPOND_PREFIX="/opt/lilypond/${VERSION}"

    # Official precompiled binary: x86_64 + glibc-based distro only.
    if [ "$(uname -m)" = "x86_64" ] && (is_debian_like || is_redhat_like || is_arch_like); then
        install_from_official "${VERSION}"
    elif is_debian_like || is_redhat_like || is_arch_like; then
        # Non-x86_64 glibc distros (e.g. ARM64 Debian/Ubuntu, ARM64 Arch): build from source.
        install_from_source "${VERSION}"
    elif is_alpine && has_texlive; then
        # Alpine (musl) with TeX Live installed: build from source.
        install_from_source "${VERSION}"
    else
        # Alpine without TeX Live, or unknown distros: fall back to the distro
        # package manager. Alpine's community repo ships a current lilypond.
        install_from_distro
    fi

    echo "LilyPond installation complete."
    lilypond --version | head -1 || true
}

main
