#!/bin/bash
# Shared OS-detection and package-manager helpers, sourced by every
# install-*.sh script and by the bin/update-* helpers.
#
# Vendored from lbssousa/distrobox-typesetting (scripts/lib/common.sh),
# unchanged: this machine is Arch-based (is_arch_like/pacman), but the
# other branches are kept so these scripts stay portable if ever reused
# elsewhere.
#
# Requires bash (uses arrays). Callers on a POSIX /bin/sh must bootstrap
# into bash before sourcing this file.

# ---------------------------------------------------------------------------
# OS detection
# ---------------------------------------------------------------------------
# Sets the OS_ID/OS_ID_LIKE globals directly (rather than via a subshell'd
# `echo`) so OS_ID_LIKE survives: distros derived from a base distro (e.g.
# Omarchy, ID=omarchy/ID_LIKE=arch) report their own ID, and the is_*_like
# checks below fall back to ID_LIKE to still recognise them.
detect_os() {
    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        OS_ID="${ID:-linux}"
        OS_ID_LIKE="${ID_LIKE:-}"
    elif [ -f /etc/alpine-release ]; then
        OS_ID="alpine"
        OS_ID_LIKE=""
    else
        OS_ID="linux"
        OS_ID_LIKE=""
    fi
}

detect_os

is_debian_like() {
    case "${OS_ID}" in
        debian|ubuntu|mint|pop|kali|raspbian) return 0 ;;
    esac
    case " ${OS_ID_LIKE} " in
        *" debian "*) return 0 ;;
    esac
    return 1
}

is_redhat_like() {
    case "${OS_ID}" in
        rhel|centos|fedora|rocky|almalinux|ol) return 0 ;;
    esac
    case " ${OS_ID_LIKE} " in
        *" rhel "*|*" fedora "*) return 0 ;;
    esac
    return 1
}

is_alpine() {
    [ "${OS_ID}" = "alpine" ]
}

is_arch_like() {
    case "${OS_ID}" in
        arch|archarm|manjaro|manjaro-arm|endeavouros|garuda|arcolinux|cachyos|omarchy) return 0 ;;
    esac
    case " ${OS_ID_LIKE} " in
        *" arch "*) return 0 ;;
    esac
    return 1
}

# ---------------------------------------------------------------------------
# Package manager helpers
# ---------------------------------------------------------------------------
# pacman/apt-get/dnf/apk each check their own real/effective UID and refuse
# to run under `run0 --empower`, which deliberately keeps the caller's UID
# and only grants Linux capabilities (see ../../../run-empowered.sh and
# running_privileged() in the calling install-*.sh — capabilities are
# enough for plain filesystem writes, but not for these tools' own "must be
# root" checks). A nested, bare `run0` (no --empower) escalates the UID to
# root for just this one command; since the enclosing --empower process is
# already polkit-authorized, this does not prompt again — the same pattern
# bin/update-texlive uses (`exec run0 "$0" "$@"`) and that Ansible's run0
# become plugin uses for every `become: true` task.
run_as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        run0 "$@"
    fi
}

pkg_install() {
    if is_debian_like; then
        run_as_root env DEBIAN_FRONTEND=noninteractive \
            apt-get install -y --no-install-recommends "$@"
    elif is_redhat_like; then
        if command -v dnf &>/dev/null; then
            run_as_root dnf install -y "$@"
        else
            run_as_root yum install -y "$@"
        fi
    elif is_alpine; then
        run_as_root apk add --no-cache "$@"
    elif is_arch_like; then
        run_as_root pacman -S --needed --noconfirm "$@"
    else
        echo "Unsupported OS: ${OS_ID}" >&2
        exit 1
    fi
}

pkg_remove() {
    if is_debian_like; then
        run_as_root env DEBIAN_FRONTEND=noninteractive apt-get purge -y "$@"
        run_as_root env DEBIAN_FRONTEND=noninteractive apt-get autoremove -y
    elif is_redhat_like; then
        local pkgs=()
        for pkg in "$@"; do
            [ "${pkg}" = "pkgconf" ] && continue
            pkgs+=("${pkg}")
        done
        if [ "${#pkgs[@]}" -eq 0 ]; then
            return
        fi
        if command -v dnf &>/dev/null; then
            run_as_root dnf remove -y --setopt=clean_requirements_on_remove=False "${pkgs[@]}"
        else
            run_as_root yum remove -y "${pkgs[@]}"
        fi
    elif is_alpine; then
        run_as_root apk del "$@"
    elif is_arch_like; then
        # No-op by design, same rationale as distrobox-typesetting: Arch
        # doesn't split a library from its headers, so there is no safe way
        # to remove "build-only" packages here without risking a runtime
        # library some later step still needs. This is a desktop install
        # anyway (not a throwaway image layer), so the extra disk space is
        # a non-issue.
        echo "Keeping build-only packages installed (Arch has no safe way to remove them): $*"
    fi
}

update_pkg_index() {
    if is_debian_like; then
        run_as_root apt-get update -y
    elif is_redhat_like; then
        : # dnf/yum resolve on install
    elif is_alpine; then
        run_as_root apk update
    elif is_arch_like; then
        # Arch never supports a partial upgrade (syncing the database without
        # also upgrading), so always pair -Sy with -u.
        run_as_root pacman -Syu --noconfirm
    fi
}

upgrade_pkgs() {
    if is_debian_like; then
        run_as_root env DEBIAN_FRONTEND=noninteractive apt-get update -y
        run_as_root env DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
    elif is_redhat_like; then
        if command -v dnf &>/dev/null; then
            run_as_root dnf upgrade -y
        else
            run_as_root yum update -y
        fi
    elif is_alpine; then
        run_as_root apk update
        run_as_root apk upgrade
    elif is_arch_like; then
        run_as_root pacman -Syu --noconfirm
    else
        echo "Unsupported OS: ${OS_ID}" >&2
        exit 1
    fi
}

is_pkg_installed() {
    local pkg="$1"
    if is_debian_like; then
        dpkg-query -W -f='${Status}' "${pkg}" 2>/dev/null | grep -q "install ok installed"
    elif is_redhat_like; then
        rpm -q "${pkg}" &>/dev/null
    elif is_alpine; then
        apk info -e "${pkg}" &>/dev/null
    elif is_arch_like; then
        pacman -Q "${pkg}" &>/dev/null
    else
        return 1
    fi
}

# Install packages, recording only newly-installed ones (in the caller's
# _BUILD_PKGS_TO_REMOVE array) for removal after a build via remove_build_deps.
install_build_deps() {
    local to_install=()
    for pkg in "$@"; do
        if is_pkg_installed "${pkg}"; then
            echo "  (already present, will not remove later: ${pkg})"
        else
            _BUILD_PKGS_TO_REMOVE+=("${pkg}")
            to_install+=("${pkg}")
        fi
    done
    if [ "${#to_install[@]}" -gt 0 ]; then
        pkg_install "${to_install[@]}"
    fi
}

remove_build_deps() {
    if [ "${#_BUILD_PKGS_TO_REMOVE[@]}" -eq 0 ]; then
        return
    fi
    echo "Removing build-only packages: ${_BUILD_PKGS_TO_REMOVE[*]}"
    pkg_remove "${_BUILD_PKGS_TO_REMOVE[@]}"
    _BUILD_PKGS_TO_REMOVE=()
}
