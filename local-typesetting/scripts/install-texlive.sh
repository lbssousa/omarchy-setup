#!/bin/sh
# Installs TeX Live via the official TUG network installer into /opt/texlive.
#
# Adapted from lbssousa/distrobox-typesetting (scripts/install-texlive.sh):
# same installer/profile logic, meant to be run with root privileges
# directly on the host (e.g. via run0) instead of inside a container build.
#
# bash is required for array-based Perl module tracking (see common.sh).
SCHEME="${SCHEME:-full}"
# Normalise: accept space- or comma-separated package lists.
PACKAGES="$(printf '%s' "${PACKAGES:-}" | tr ',' ' ')"
RELEASE="${RELEASE:-latest}"
MIRROR="${MIRROR:-}"

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
    echo "ERROR: install-texlive.sh must run as root, or with full capabilities (e.g. via run0 --empower — it writes to /opt and /usr/local/bin)." >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "${SCRIPT_DIR}/lib/common.sh"

INSTALL_TL_DIR="$(mktemp -d)"
TEXLIVE_PREFIX="/opt/texlive"

# Optional persistent download cache (see lib/texlive-cached-download.sh).
# Unset by default; set TEXLIVE_CACHE_DIR to a root-writable path (e.g.
# /var/cache/omarchy-setup/texlive-downloads) to keep packages around across
# retried/rebuilt installs.
TEXLIVE_CACHE_DIR="${TEXLIVE_CACHE_DIR:-}"
TEXLIVE_CACHE_STATS=""

cleanup() {
    rm -rf "${INSTALL_TL_DIR}"
    if [ -n "${TEXLIVE_CACHE_STATS}" ]; then
        echo "TeX Live download cache: $(grep -c hit "${TEXLIVE_CACHE_STATS}" || true) reused," \
            "$(grep -c miss "${TEXLIVE_CACHE_STATS}" || true) downloaded (kept in ${TEXLIVE_CACHE_DIR})"
        rm -f "${TEXLIVE_CACHE_STATS}"
    fi
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Route every TeX Live download (install-tl and tlmgr) through the caching,
# retrying downloader
# ---------------------------------------------------------------------------
setup_downloader() {
    if [ -n "${TEXLIVE_CACHE_DIR}" ]; then
        mkdir -p "${TEXLIVE_CACHE_DIR}"
        TEXLIVE_CACHE_STATS="$(mktemp)"
        export TEXLIVE_CACHE_DIR TEXLIVE_CACHE_STATS
    fi
    export TL_DOWNLOAD_PROGRAM="${SCRIPT_DIR}/lib/texlive-cached-download.sh"
    # TeX Live warns on every download if this is undefined; the helper ignores it.
    export TL_DOWNLOAD_ARGS="--"
    unset TEXLIVE_DOWNLOADER
}

# Drop cache entries nobody has used for a month, so it cannot grow forever.
prune_cache() {
    if [ -n "${TEXLIVE_CACHE_DIR}" ]; then
        find "${TEXLIVE_CACHE_DIR}" -type f -mtime +30 -delete
    fi
}

# ---------------------------------------------------------------------------
# Install OS prerequisites
# ---------------------------------------------------------------------------
install_prerequisites() {
    echo "Installing prerequisites for OS: ${OS_ID}"
    update_pkg_index

    # latexindent (4.0.2, current as of TeX Live 2026) only hard-requires
    # YAML::Tiny and File::HomeDir; Unicode::GCString (bundled with
    # Unicode::LineBreak) is loaded only behind the optional --GCString
    # switch. Older latexindent releases also needed Log::Dispatch,
    # Log::Log4perl, File::Which and Sub::Identify, but latexindent dropped
    # those in favour of its own LatexIndent::Logger; don't install them
    # (Log::Dispatch in particular has no Arch package, so ensure_latexindent_deps
    # used to fall back to building it via cpanm, which is what broke
    # `just typesetting`).
    if is_debian_like; then
        pkg_install \
            curl ca-certificates fontconfig gnupg xz-utils \
            perl perl-base \
            libyaml-tiny-perl \
            libfile-homedir-perl \
            libunicode-linebreak-perl
    elif is_redhat_like; then
        pkg_install \
            curl ca-certificates fontconfig gnupg2 xz \
            perl \
            perl-YAML-Tiny \
            perl-File-HomeDir \
            perl-Unicode-LineBreak
    elif is_alpine; then
        pkg_install \
            curl ca-certificates fontconfig gnupg xz \
            perl \
            perl-yaml-tiny \
            perl-file-homedir \
            perl-unicode-linebreak
    elif is_arch_like; then
        pkg_install \
            curl ca-certificates fontconfig gnupg xz \
            perl \
            perl-yaml-tiny \
            perl-file-homedir \
            perl-unicode-linebreak
    fi
}

# ---------------------------------------------------------------------------
# Resolve installer URL
# ---------------------------------------------------------------------------
resolve_installer_url() {
    if [ -n "${MIRROR}" ]; then
        echo "${MIRROR%/}/CTAN/systems/texlive/tlnet/install-tl-unx.tar.gz"
        return
    fi

    if [ "${RELEASE}" = "latest" ]; then
        echo "https://mirror.ctan.org/systems/texlive/tlnet/install-tl-unx.tar.gz"
    else
        echo "https://ftp.tug.org/texlive/historic/${RELEASE}/install-tl-unx.tar.gz"
    fi
}

# ---------------------------------------------------------------------------
# Resolve tlnet repository URL (used by tlmgr after install)
# ---------------------------------------------------------------------------
resolve_tlnet_url() {
    if [ -n "${MIRROR}" ]; then
        echo "${MIRROR%/}/CTAN/systems/texlive/tlnet"
        return
    fi

    if [ "${RELEASE}" = "latest" ]; then
        echo "https://mirror.ctan.org/systems/texlive/tlnet"
    else
        echo "https://ftp.tug.org/texlive/historic/${RELEASE}/tlnet"
    fi
}

# ---------------------------------------------------------------------------
# Download and extract installer
# ---------------------------------------------------------------------------
download_installer() {
    local url="$1"
    echo "Downloading TeX Live installer from: ${url}"
    "${TL_DOWNLOAD_PROGRAM}" "${INSTALL_TL_DIR}/install-tl-unx.tar.gz" "${url}"
    tar -xzf "${INSTALL_TL_DIR}/install-tl-unx.tar.gz" \
        --strip-components=1 \
        -C "${INSTALL_TL_DIR}"
}

# ---------------------------------------------------------------------------
# Build install profile
# ---------------------------------------------------------------------------
write_profile() {
    local texdir="$1"

    cat > "${INSTALL_TL_DIR}/texlive.profile" <<EOF
selected_scheme scheme-${SCHEME}
TEXDIR ${texdir}
TEXMFLOCAL ${TEXLIVE_PREFIX}/texmf-local
TEXMFSYSVAR ${texdir}/texmf-var
TEXMFSYSCONFIG ${texdir}/texmf-config
TEXMFVAR ~/.texlive/texmf-var
TEXMFCONFIG ~/.texlive/texmf-config
TEXMFHOME ~/texmf
instopt_adjustpath 0
instopt_adjustrepo 1
instopt_letter 0
instopt_portable 0
instopt_write18_restricted 1
tlpdbopt_autobackup 0
tlpdbopt_create_formats 1
tlpdbopt_install_docfiles 1
tlpdbopt_install_srcfiles 1
tlpdbopt_post_code 1
tlpdbopt_sys_bin /usr/local/bin
tlpdbopt_sys_info /usr/local/share/info
tlpdbopt_sys_man /usr/local/share/man
EOF
}

# ---------------------------------------------------------------------------
# Run the installer
# ---------------------------------------------------------------------------
run_installer() {
    local texdir="$1"
    local repo_url="$2"

    write_profile "${texdir}"

    echo "Running TeX Live installer (scheme: ${SCHEME}, release: ${RELEASE})"
    "${INSTALL_TL_DIR}/install-tl" \
        --profile="${INSTALL_TL_DIR}/texlive.profile" \
        --location="${repo_url}" \
        --no-interaction
}

# ---------------------------------------------------------------------------
# Detect installed bin path and symlink to /usr/local/bin
# ---------------------------------------------------------------------------
setup_path() {
    local texdir="$1"
    local bin_dir
    bin_dir="$(find "${texdir}/bin" -mindepth 1 -maxdepth 1 -type d | head -1)"

    if [ -z "${bin_dir}" ]; then
        echo "WARNING: could not locate TeX Live bin directory under ${texdir}/bin" >&2
        return
    fi

    echo "Linking TeX Live binaries from ${bin_dir} to /usr/local/bin"
    for bin in "${bin_dir}"/*; do
        local name
        name="$(basename "${bin}")"
        if [ ! -e "/usr/local/bin/${name}" ]; then
            ln -s "${bin}" "/usr/local/bin/${name}"
        fi
    done

    # Stable symlink for environment variables
    ln -sfn "${bin_dir}" "${TEXLIVE_PREFIX}/bin"
    local man_dir="${texdir}/texmf-dist/doc/man"
    local info_dir="${texdir}/texmf-dist/doc/info"
    [ -d "${man_dir}" ]  && ln -sfn "${man_dir}"  "${TEXLIVE_PREFIX}/bin/man"
    [ -d "${info_dir}" ] && ln -sfn "${info_dir}" "${TEXLIVE_PREFIX}/bin/info"
}

# ---------------------------------------------------------------------------
# Install extra packages via tlmgr
# ---------------------------------------------------------------------------
install_extra_packages() {
    if [ -z "${PACKAGES}" ]; then
        return
    fi

    echo "Installing additional TeX Live packages: ${PACKAGES}"
    # shellcheck disable=SC2086
    tlmgr install ${PACKAGES}
    # New executables land in bin_dir after tlmgr install; symlink them to sys_bin.
    tlmgr path add
}

# ---------------------------------------------------------------------------
# Verify latexindent's required Perl modules (install via cpanm if missing)
# ---------------------------------------------------------------------------
ensure_latexindent_deps() {
    local missing=()
    local modules=(
        "YAML::Tiny"
        "File::HomeDir"
    )

    for mod in "${modules[@]}"; do
        if ! perl -M"${mod}" -e 1 &>/dev/null; then
            missing+=("${mod}")
        fi
    done

    if [ ${#missing[@]} -eq 0 ]; then
        return
    fi

    echo "Installing missing Perl modules for latexindent: ${missing[*]}"

    if command -v cpanm &>/dev/null; then
        cpanm --notest "${missing[@]}"
    else
        # Fallback: install cpanminus then retry. Both modules are pure
        # Perl, so no compiler toolchain is needed here.
        if is_debian_like; then
            pkg_install cpanminus
        elif is_redhat_like; then
            pkg_install perl-App-cpanminus
        elif is_alpine; then
            pkg_install perl-app-cpanminus
        elif is_arch_like; then
            pkg_install cpanminus
            # Arch installs cpanm under vendor_perl, which isn't on the
            # default PATH.
            export PATH="${PATH}:/usr/bin/vendor_perl"
        fi
        cpanm --notest "${missing[@]}"
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    install_prerequisites
    setup_downloader

    local installer_url
    installer_url="$(resolve_installer_url)"

    local repo_url
    repo_url="$(resolve_tlnet_url)"

    download_installer "${installer_url}"

    # Determine target directory name
    local texdir_name
    if [ "${RELEASE}" = "latest" ]; then
        # The installer creates a directory named after the actual year; use a
        # wildcard after install to discover it.
        texdir_name="current"
    else
        texdir_name="${RELEASE}"
    fi

    local texdir="${TEXLIVE_PREFIX}/${texdir_name}"

    run_installer "${texdir}" "${repo_url}"

    # If we used "current" as placeholder, discover the real dir
    if [ "${texdir_name}" = "current" ]; then
        local real_dir
        real_dir="$(find "${TEXLIVE_PREFIX}" -mindepth 1 -maxdepth 1 -type d ! -name 'texmf-local' | head -1)"
        if [ -n "${real_dir}" ] && [ "${real_dir}" != "${texdir}" ]; then
            texdir="${real_dir}"
        fi
    fi

    setup_path "${texdir}"

    install_extra_packages
    ensure_latexindent_deps
    prune_cache

    echo "TeX Live installation complete."
    tex --version | head -1 || true
}

main
