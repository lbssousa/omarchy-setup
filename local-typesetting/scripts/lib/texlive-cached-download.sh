#!/bin/sh
# Download helper for the TeX Live installer and tlmgr. install-texlive.sh
# registers it through TL_DOWNLOAD_PROGRAM, so TeX Live runs it as:
#
#   texlive-cached-download.sh -- DEST URL   (DEST "-" means stdout)
#
# (the "--" is TL_DOWNLOAD_ARGS, which must be set for TeX Live not to warn).
#
# Vendored unchanged from lbssousa/distrobox-typesetting
# (scripts/lib/texlive-cached-download.sh).
#
# Every download is retried and resumed on flaky connections. If
# TEXLIVE_CACHE_DIR is set, package containers (archive/*.tar.xz) are also
# kept in a content-addressed cache there, named by the sha512 that the
# repository's tlpdb publishes for them:
#
#   $TEXLIVE_CACHE_DIR/index/<repo>   container name -> sha512 (from the tlpdb)
#   $TEXLIVE_CACHE_DIR/objects/<sha>  verified container, or <sha>.part while
#                                     downloading (resumed by the next run)
#
# Keying by checksum makes stale entries harmless: when a package is updated
# upstream its checksum changes and it is simply downloaded again, whichever
# mirror or release it came from. Metadata (the tlpdb, signatures, ...) is
# never cached.
#
# If TEXLIVE_CACHE_STATS names a file, "hit"/"miss" lines are appended to it
# for every container served from the cache / from the network.
set -u

[ "${1:-}" = "--" ] && shift
dest="$1"
url="$2"
cache="${TEXLIVE_CACHE_DIR:-}"
tmp=""

trap '[ -z "${tmp}" ] || rm -f "${tmp}"' EXIT

die() {
    echo "texlive-cached-download: $*" >&2
    exit 1
}

# download URL FILE: resumable, retried; FILE keeps its partial content on failure.
download() {
    curl -fsS -C - --retry 10 --retry-delay 10 --retry-connrefused \
        --connect-timeout 30 -o "$2" "$1"
}

# deliver FILE: hand FILE to TeX Live (a copy, since it deletes what it is given).
deliver() {
    if [ "${dest}" = "-" ]; then
        cat "$1"
    else
        cp "$1" "${dest}"
    fi
}

stat_line() {
    [ -z "${TEXLIVE_CACHE_STATS:-}" ] || echo "$1" >> "${TEXLIVE_CACHE_STATS}"
}

# Directory-safe name for a repository URL.
repo_key() {
    printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_'
}

# build_index REPO FILE: record "<container file name> <sha512>" for every
# container in the tlpdb FILE downloaded from REPO (xz-compressed or plain).
build_index() {
    mkdir -p "${cache}/index" || return 0
    idx="${cache}/index/$(repo_key "$1")"
    {
        case "${url}" in
            *.xz) xz -dc "$2" ;;
            *) cat "$2" ;;
        esac | awk '
            /^name /                { name = $2 }
            /^containerchecksum /   { print name ".tar.xz\t" $2 }
            /^doccontainerchecksum /{ print name ".doc.tar.xz\t" $2 }
            /^srccontainerchecksum /{ print name ".source.tar.xz\t" $2 }
        ' > "${idx}.new" && mv "${idx}.new" "${idx}"
    } 2>/dev/null || rm -f "${idx}.new"
}

case "${url}" in
    */archive/*.tar.xz)
        if [ -n "${cache}" ]; then
            sum="$(awk -F'\t' -v n="${url##*/}" '$1 == n { print $2; exit }' \
                "${cache}/index/$(repo_key "${url%/archive/*}")" 2>/dev/null)"
            if [ -n "${sum}" ]; then
                obj="${cache}/objects/${sum}"
                if [ -f "${obj}" ]; then
                    # Refresh the mtime on every use so the age-based prune
                    # only drops entries nobody has asked for lately.
                    touch "${obj}"
                    stat_line hit
                    deliver "${obj}" || die "cannot copy ${obj} to ${dest}"
                    exit 0
                fi
                mkdir -p "${cache}/objects" || die "cannot create ${cache}/objects"
                # The partial file is kept on failure so the next run resumes it.
                download "${url}" "${obj}.part" || die "download failed: ${url}"
                got="$(sha512sum "${obj}.part" | cut -d' ' -f1)"
                if [ "${got}" != "${sum}" ]; then
                    rm -f "${obj}.part"
                    die "checksum mismatch for ${url}"
                fi
                mv "${obj}.part" "${obj}"
                touch "${obj}"
                stat_line miss
                deliver "${obj}" || die "cannot copy ${obj} to ${dest}"
                exit 0
            fi
        fi
        ;;
esac

# Anything else (metadata, or no cache): plain retried download.
tmp="$(mktemp)" || die "mktemp failed"
download "${url}" "${tmp}" || die "download failed: ${url}"
case "${url}" in
    */tlpkg/texlive.tlpdb|*/tlpkg/texlive.tlpdb.xz)
        if [ -n "${cache}" ]; then
            build_index "${url%/tlpkg/texlive.tlpdb*}" "${tmp}"
        fi
        ;;
esac
case "${url}" in
    */archive/*.tar.xz) stat_line miss ;;
esac
deliver "${tmp}" || die "cannot copy download to ${dest}"
