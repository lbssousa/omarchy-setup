#!/bin/sh
# Builds and installs Gregorio (Gregorian chant score engraver) from source,
# together with its GregorioTeX TeX Live integration files. Defaults to
# lbssousa/gregorio (this project's fork) rather than upstream, at the same
# commit pinned in omarchy-setup's group_vars/all/main.yml (gregorio_ref) —
# keep the two in sync by hand.
#
# Adapted from lbssousa/distrobox-typesetting (scripts/install-gregorio.sh):
# same build logic, meant to be run with root privileges directly on the
# host (e.g. via run0) instead of inside a container build. Build
# dependencies are left installed afterward (see common.sh's Arch branch of
# remove_build_deps) since this is a desktop install, not a throwaway image
# layer.
#
# bash is required for array-based build-dep tracking (see common.sh).
HOST="${HOST:-github}"
REPOSITORY="${REPOSITORY:-lbssousa/gregorio}"
REF="${REF:-bdb4eedbc2eb0521c3e040811f7d70a99b6fa639}"

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
    echo "ERROR: install-gregorio.sh must run as root, or with full capabilities (e.g. via run0 --empower — it writes to /usr/local and TeX Live's TEXMFLOCAL)." >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "${SCRIPT_DIR}/lib/common.sh"

BUILD_DIR="$(mktemp -d)"
_BUILD_PKGS_TO_REMOVE=()

cleanup() {
    rm -rf "${BUILD_DIR}"
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Repository URL construction
# ---------------------------------------------------------------------------
construct_repo_url() {
    local host="$1"
    local repo="$2"

    case "${host}" in
        github)
            echo "https://github.com/${repo}"
            ;;
        gitlab)
            echo "https://gitlab.com/${repo}"
            ;;
        codeberg)
            echo "https://codeberg.org/${repo}"
            ;;
        bitbucket)
            echo "https://bitbucket.org/${repo}"
            ;;
        *)
            echo "Unsupported host: ${host}" >&2
            exit 1
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Tarball URL construction — ref is passed as-is (branch, tag, commit, or empty for HEAD).
# ---------------------------------------------------------------------------
construct_tarball_url() {
    local host="$1"
    local repo="$2"
    local ref="$3"

    case "${host}" in
        github)
            if [ -z "${ref}" ]; then
                echo "https://github.com/${repo}/archive/HEAD.tar.gz"
            else
                echo "https://github.com/${repo}/archive/${ref}.tar.gz"
            fi
            ;;
        gitlab)
            local repo_name="${repo##*/}"
            local git_ref="${ref:-HEAD}"
            echo "https://gitlab.com/${repo}/-/archive/${git_ref}/${repo_name}-${git_ref}.tar.gz"
            ;;
        codeberg)
            echo "https://codeberg.org/${repo}/archive/${ref:-HEAD}.tar.gz"
            ;;
        bitbucket)
            echo "https://bitbucket.org/${repo}/get/${ref:-HEAD}.tar.gz"
            ;;
        *)
            echo "Unsupported host: ${host}" >&2
            exit 1
            ;;
    esac
}

# ---------------------------------------------------------------------------
# GitHub helpers
# ---------------------------------------------------------------------------
resolve_github_latest() {
    local repo_url="$1"
    local repo
    repo="$(printf '%s' "${repo_url}" | sed 's|https://github.com/||')"
    # /releases/latest excludes pre-releases and 404s when none exist.
    # Fall back to /releases?per_page=1 (most recent, pre-release or not).
    local tag
    tag="$(curl -sSL "https://api.github.com/repos/${repo}/releases/latest" \
        | grep '"tag_name"' | head -1 \
        | sed 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"
    if [ -z "${tag}" ]; then
        tag="$(curl -sSfL "https://api.github.com/repos/${repo}/releases?per_page=1" \
            | grep '"tag_name"' | head -1 \
            | sed 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')"
    fi
    printf '%s\n' "${tag}"
}

# ---------------------------------------------------------------------------
# Install Gregorio from source
# ---------------------------------------------------------------------------
install_gregorio() {
    local ref="${REF}"

    local repo_url
    repo_url="$(construct_repo_url "${HOST}" "${REPOSITORY}")"

    echo "Installing prerequisites..."
    update_pkg_index
    pkg_install curl ca-certificates

    # Resolve the ref and tarball URL.
    # Empty ref  → HEAD of the default branch.
    # "latest"   → latest release tag resolved via the forge API.
    # Anything else → used as-is (branch name, tag name, or commit hash).
    local display_ref

    if [ -z "${ref}" ]; then
        display_ref="HEAD"
    elif [ "${ref}" = "latest" ]; then
        echo "Resolving latest Gregorio release..."
        ref="$(resolve_github_latest "${repo_url}")"
        echo "  -> ${ref}"
        display_ref="${ref}"
    else
        display_ref="${ref}"
    fi

    local tarball_url
    tarball_url="$(construct_tarball_url "${HOST}" "${REPOSITORY}" "${ref}")"

    echo "Installing Gregorio build dependencies..."
    if is_debian_like; then
        install_build_deps autoconf automake libtool gcc make flex bison python3 fontforge pkg-config
    elif is_redhat_like; then
        install_build_deps autoconf automake libtool gcc make flex bison python3 fontforge pkgconf
    elif is_alpine; then
        install_build_deps autoconf automake libtool gcc musl-dev make flex bison python3 fontforge pkgconfig
    elif is_arch_like; then
        install_build_deps base-devel autoconf automake libtool flex bison python fontforge pkgconf
    fi

    echo "Downloading Gregorio ${display_ref} from ${tarball_url}..."
    curl -sSfL "${tarball_url}" -o "${BUILD_DIR}/gregorio.tar.gz"

    local src_dir="${BUILD_DIR}/gregorio-src"
    mkdir -p "${src_dir}"
    tar -xzf "${BUILD_DIR}/gregorio.tar.gz" --strip-components=1 -C "${src_dir}"

    (
        cd "${src_dir}"
        echo "Generating autotools build files..."
        autoreconf -fi
        echo "Configuring Gregorio..."
        # Run with bash explicitly: Gregorio's configure uses CFLAGS+= (bash-ism)
        # which breaks under busybox ash (/bin/sh on Alpine).
        # --disable-version-in-exe: install the binary as 'gregorio', not 'gregorio-6_2_0'.
        bash ./configure --prefix=/usr/local --disable-version-in-exe
        echo "Building Gregorio..."
        make -j"$(nproc)"
        echo "Installing Gregorio..."
        make install
    )

    # make install only installs the gregorio binary; the GregorioTeX TeX support
    # files (gregoriotex.sty, .tex, .lua, fonts) are installed by a separate
    # script. Without this step, kpsewhich cannot find gregoriotex and lualatex
    # compilation will fail.
    #
    # install-texlive.sh always uses a fixed TEXMFLOCAL of
    # /opt/texlive/texmf-local (see TEXLIVE_PREFIX there), so when kpsewhich is
    # unavailable we can still target that path directly ("dir:" mode) without
    # needing texhash. ls-R will be stale in that case, but kpathsea falls back
    # to scanning the filesystem for files missing from ls-R, so lookups still
    # succeed -- just slightly slower until the next texhash run.
    if command -v kpsewhich >/dev/null 2>&1; then
        echo "Installing GregorioTeX TeX support files..."
        ( cd "${src_dir}" && SKIP="docs,examples,font-sources" AUTO_UNINSTALL=true bash ./install-gtex.sh system )
    else
        echo "WARNING: kpsewhich not found; installing GregorioTeX TeX support" >&2
        echo "         files directly into /opt/texlive/texmf-local (texhash skipped)." >&2
        ( cd "${src_dir}" && SKIP="docs,examples,font-sources" AUTO_UNINSTALL=true TEXHASH=true bash ./install-gtex.sh dir:/opt/texlive/texmf-local )
    fi

    echo "Gregorio ${display_ref} installed."

    echo "Removing Gregorio build dependencies..."
    remove_build_deps
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    install_gregorio
    echo "Gregorio installation complete."
}

main
