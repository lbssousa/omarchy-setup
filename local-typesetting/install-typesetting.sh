#!/usr/bin/env bash
# Installs a typesetting/music-engraving toolchain directly on this machine
# (no containers): TeX Live and LilyPond under /opt, Gregorio built from
# source and wired into TeX Live, with TeX Live's bundled fonts registered
# with fontconfig — the same font integration
# lbssousa/distrobox-typesetting's container image gets, just applied to the
# host instead of a distrobox image.
#
# Run `./install-typesetting.sh --help` for usage.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/opt/local-typesetting"

# ---------------------------------------------------------------------------
# Defaults, overridden by local-typesetting.env, overridden by CLI flags.
# ---------------------------------------------------------------------------
TEXLIVE_RELEASE="latest"
# "full" avoids having to hand-maintain a package list (see
# TEXLIVE_PACKAGES below) — this is a one-time, permanent install, not a
# container image rebuilt on every iteration, so the extra size/time is a
# non-issue. scheme-full already includes gregoriotex, musixtex and every
# other CTAN package omarchy-setup's old playbooks/tex.yml used to
# hand-pick for the AISCGre-BR projects.
TEXLIVE_SCHEME="full"
# Extra packages on top of TEXLIVE_SCHEME, space/comma-separated. Only
# useful with a lighter scheme (e.g. --texlive-scheme minimal).
TEXLIVE_PACKAGES=""
# Same CTAN mirror omarchy-setup's group_vars used for the AUR
# texlive-installer play this script replaces.
TEXLIVE_MIRROR="https://linorg.usp.br"
# Empty (disabled) by default. Set to a root-writable path (e.g.
# /var/cache/omarchy-setup/texlive-downloads) to keep downloaded TeX Live
# packages around across retried/rebuilt installs — see
# scripts/lib/texlive-cached-download.sh.
TEXLIVE_CACHE_DIR=""
LILYPOND_VERSION="latest"
GREGORIO_HOST="github"
GREGORIO_REPOSITORY="lbssousa/gregorio"
# Kept in sync by hand with gregorio_ref in omarchy-setup's
# group_vars/all/main.yml (also used by the AISCGre-BR devcontainers).
GREGORIO_REF="bdb4eedbc2eb0521c3e040811f7d70a99b6fa639"

for candidate in "${PWD}/local-typesetting.env" "${SCRIPT_DIR}/local-typesetting.env"; do
    if [ -f "${candidate}" ]; then
        # shellcheck disable=SC1090
        . "${candidate}"
        break
    fi
done

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Installs TeX Live (/opt/texlive), LilyPond (/opt/lilypond), and Gregorio
(built from source, wired into TeX Live) directly on this machine, then
registers TeX Live's fonts with fontconfig. Needs root: every privileged
step runs under a single \`run0 --empower\` (see ../run-empowered.sh), so
you authenticate once (fingerprint or password) for the whole install
instead of once per step.

Options:
  --texlive-release RELEASE     TeX Live release: year or "latest" (default: ${TEXLIVE_RELEASE})
  --texlive-scheme SCHEME       TeX Live scheme (default: ${TEXLIVE_SCHEME})
  --texlive-packages PKGS       Extra TeX Live packages, space/comma-separated (default: none)
  --texlive-mirror URL          TeX Live mirror base URL (default: ${TEXLIVE_MIRROR})
  --texlive-cache-dir DIR       Persistent download cache (default: disabled)
  --lilypond-version VERSION    LilyPond version, or "latest" (default: ${LILYPOND_VERSION})
  --gregorio-repository REPO    GitHub repo to build Gregorio from (default: ${GREGORIO_REPOSITORY})
  --gregorio-ref REF            Branch, tag, or commit to build (default: ${GREGORIO_REF})
  -h, --help                    Show this help

Options default to the values in local-typesetting.env (CWD, then this
script's directory) if present, and to the built-in defaults shown above
otherwise.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --texlive-release) TEXLIVE_RELEASE="$2"; shift 2 ;;
        --texlive-scheme) TEXLIVE_SCHEME="$2"; shift 2 ;;
        --texlive-packages) TEXLIVE_PACKAGES="$2"; shift 2 ;;
        --texlive-mirror) TEXLIVE_MIRROR="$2"; shift 2 ;;
        --texlive-cache-dir) TEXLIVE_CACHE_DIR="$2"; shift 2 ;;
        --lilypond-version) LILYPOND_VERSION="$2"; shift 2 ;;
        --gregorio-repository) GREGORIO_REPOSITORY="$2"; shift 2 ;;
        --gregorio-ref) GREGORIO_REF="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

RUN_EMPOWERED="${SCRIPT_DIR}/../run-empowered.sh"
if [ ! -x "${RUN_EMPOWERED}" ]; then
    echo "ERROR: ${RUN_EMPOWERED} not found (this script must be run from inside the omarchy-setup repo)." >&2
    exit 1
fi
if ! command -v run0 >/dev/null 2>&1; then
    echo "ERROR: run0 not found on PATH (needs systemd 256+)." >&2
    exit 1
fi

# All privileged steps run as one script under a single `run0 --empower`
# call (see run-empowered.sh) instead of one `sudo`/`run0` per step: run0
# doesn't cache authorization between separate invocations the way sudo
# does, so calling it once per step here would mean one polkit prompt per
# step instead of one for the whole install.
#
# run-empowered.sh forwards every exported variable through to the
# elevated process by name (--setenv=NAME), so export the config here
# instead of interpolating values into the script text below — that keeps
# values with quotes/spaces (e.g. --texlive-packages) intact without
# needing extra escaping.
export SCRIPT_DIR INSTALL_DIR \
    TEXLIVE_RELEASE TEXLIVE_SCHEME TEXLIVE_PACKAGES TEXLIVE_MIRROR TEXLIVE_CACHE_DIR \
    LILYPOND_VERSION GREGORIO_HOST GREGORIO_REPOSITORY GREGORIO_REF

PRIVILEGED_SCRIPT="$(mktemp)"
trap 'rm -f "${PRIVILEGED_SCRIPT}"' EXIT

cat > "${PRIVILEGED_SCRIPT}" <<'PRIVILEGED'
set -euo pipefail

echo "==> Installing scripts to ${INSTALL_DIR} (kept there so update-texlive/update-lilypond/update-gregorio work later)"
mkdir -p "${INSTALL_DIR}"
cp -r "${SCRIPT_DIR}/scripts" "${INSTALL_DIR}/"
chmod +x "${INSTALL_DIR}"/scripts/*.sh "${INSTALL_DIR}"/scripts/lib/*.sh

echo "==> Installing TeX Live (scheme: ${TEXLIVE_SCHEME}, release: ${TEXLIVE_RELEASE}) into /opt/texlive"
RELEASE="${TEXLIVE_RELEASE}" \
    SCHEME="${TEXLIVE_SCHEME}" \
    PACKAGES="${TEXLIVE_PACKAGES}" \
    MIRROR="${TEXLIVE_MIRROR}" \
    TEXLIVE_CACHE_DIR="${TEXLIVE_CACHE_DIR}" \
    bash "${INSTALL_DIR}/scripts/install-texlive.sh"

echo "==> Installing LilyPond (version: ${LILYPOND_VERSION}) into /opt/lilypond"
VERSION="${LILYPOND_VERSION}" \
    bash "${INSTALL_DIR}/scripts/install-lilypond.sh"

echo "==> Building and installing Gregorio (${GREGORIO_REPOSITORY}@${GREGORIO_REF})"
HOST="${GREGORIO_HOST}" \
    REPOSITORY="${GREGORIO_REPOSITORY}" \
    REF="${GREGORIO_REF}" \
    bash "${INSTALL_DIR}/scripts/install-gregorio.sh"

echo "==> Registering TeX Live's fonts with fontconfig"
bash "${INSTALL_DIR}/scripts/configure-fonts.sh"

echo "==> Installing update-texlive/update-lilypond/update-gregorio to /usr/local/bin"
cp "${SCRIPT_DIR}/bin/"update-* /usr/local/bin/
chmod +x /usr/local/bin/update-texlive /usr/local/bin/update-lilypond /usr/local/bin/update-gregorio
PRIVILEGED

"${RUN_EMPOWERED}" bash "${PRIVILEGED_SCRIPT}"

cat <<EOF

Done. TeX Live, LilyPond and Gregorio are installed under /opt, and their
binaries are symlinked into /usr/local/bin (already on PATH on Arch/Omarchy).

Check with:

  tex --version
  lilypond --version
  gregorio --version

To pick up TeX Live's man/info pages, add to your shell rc:

  export MANPATH="/opt/texlive/bin/man:\${MANPATH}"
  export INFOPATH="/opt/texlive/bin/info:\${INFOPATH}"

Update later with:

  update-texlive             # tlmgr update --self --all (self-elevates via run0)
  update-lilypond [version]  # defaults to "latest"
  update-gregorio [ref]      # defaults to ${GREGORIO_REF}
EOF
