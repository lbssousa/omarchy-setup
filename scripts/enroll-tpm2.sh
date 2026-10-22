#!/usr/bin/env bash
# enroll-tpm2.sh — Set up automatic LUKS unlock via the TPM2 chip
#
# Uses systemd-cryptenroll to register the TPM2 chip as an authentication factor
# for the LUKS volume, letting the system automatically unlock the disk at
# boot — as long as integrity measurements (PCRs) match the expected state.
#
# ⚠️  Run this script AFTER the system's first successful boot and after
#     Secure Boot is enabled (if using PCR 7).
#
# Usage:
#   bash scripts/enroll-tpm2.sh [--device <partition>] [--pcrs <pcrs>]
#                               [--wipe] [--help]
#
# Options:
#   --device <partition>  LUKS partition (default: auto-detected root LUKS volume)
#   --pcrs <pcrs>         PCRs to seal against (default: 0+2+7)
#                        0 = UEFI firmware (core firmware code and measurement)
#                        2 = UEFI option ROM code (drivers/hardware add-ons)
#                        7 = Secure Boot state
#   --wipe                Remove the existing TPM2 slot before re-enrolling
#                        (useful after firmware updates or Secure Boot changes)
#   --help, -h            Show help and exit

set -euo pipefail

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET} $*"; }
success() { echo -e "${GREEN}[OK]${RESET}   $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET} $*"; }
error()   { echo -e "${RED}[ERRO]${RESET} $*" >&2; }
die()     { error "$*"; exit 1; }

# ---------------------------------------------------------------------------
# Fast-path --help check (no root needed to read help)
# ---------------------------------------------------------------------------

for arg in "$@"; do
  if [[ "$arg" == "--help" || "$arg" == "-h" ]]; then
    cat <<'EOF'
Usage:
  bash scripts/enroll-tpm2.sh [--device <partition>] [--pcrs <pcrs>]
                              [--wipe] [--help]

Options:
  --device <partition>  LUKS partition (default: auto-detected root LUKS partition)
  --pcrs <pcrs>         PCRs to watch, + separated (default: 0+2+7)
                       0 = UEFI firmware (firmware integrity)
                       2 = UEFI option code (ROM drivers)
                       7 = Secure Boot state
  --wipe                Remove the existing TPM2 slot before re-enrolling.
                       Use after firmware updates or Secure Boot changes
                       that invalidate the current slot.

Examples:
  # Default enrollment (PCRs 0+2+7, recommended with Secure Boot):
  run0 bash scripts/enroll-tpm2.sh

  # Without Secure Boot (firmware and option code only):
  run0 bash scripts/enroll-tpm2.sh --pcrs 0+2

  # Re-enroll after a firmware update:
  run0 bash scripts/enroll-tpm2.sh --wipe

  # Alternate LUKS partition:
  run0 bash scripts/enroll-tpm2.sh --device /dev/nvme0n1p2

To revoke TPM2 access (e.g. before selling hardware):
  run0 systemd-cryptenroll --wipe-slot=tpm2 <device>
EOF
    exit 0
  fi
done

# ---------------------------------------------------------------------------
# Ensure running as root
# ---------------------------------------------------------------------------

if [[ $EUID -ne 0 ]]; then
  info "This script must run as root. Re-executing with run0..."
  exec run0 bash "${BASH_SOURCE[0]}" "$@"
fi

# ---------------------------------------------------------------------------
# Auto-detect root LUKS device if possible
# ---------------------------------------------------------------------------

detect_luks_device() {
  local root_source ancestry device
  if root_source=$(findmnt -no SOURCE / 2>/dev/null) && [[ -n $root_source ]]; then
    if ancestry=$(lsblk -nsrpo NAME,TYPE,FSTYPE "${root_source%%[*}" 2>/dev/null); then
      device=$(awk '$3 == "crypto_LUKS" { print $1; exit }' <<<"$ancestry")
      if [[ -n $device ]]; then
        readlink -f "$device"
        return 0
      fi
    fi
  fi
  if [[ -b /dev/disk/by-partlabel/luks ]]; then
    echo "/dev/disk/by-partlabel/luks"
    return 0
  fi
  return 1
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

OPT_DEVICE=""
OPT_PCRS="0+2+7"
OPT_WIPE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device) OPT_DEVICE="$2"; shift 2 ;;
    --pcrs)   OPT_PCRS="$2";   shift 2 ;;
    --wipe)   OPT_WIPE=true;   shift ;;
    --help|-h)
      cat <<'EOF'
Usage:
  bash scripts/enroll-tpm2.sh [--device <partition>] [--pcrs <pcrs>]
                              [--wipe] [--help]

Options:
  --device <partition>  LUKS partition (default: auto-detected root LUKS partition)
  --pcrs <pcrs>         PCRs to watch, + separated (default: 0+2+7)
                       0 = UEFI firmware (firmware integrity)
                       2 = UEFI option code (ROM drivers)
                       7 = Secure Boot state
  --wipe                Remove the existing TPM2 slot before re-enrolling.
                       Use after firmware updates or Secure Boot changes
                       that invalidate the current slot.

Examples:
  # Default enrollment (PCRs 0+2+7, recommended with Secure Boot):
  run0 bash scripts/enroll-tpm2.sh

  # Without Secure Boot (firmware and option code only):
  run0 bash scripts/enroll-tpm2.sh --pcrs 0+2

  # Re-enroll after a firmware update:
  run0 bash scripts/enroll-tpm2.sh --wipe

  # Alternate LUKS partition:
  run0 bash scripts/enroll-tpm2.sh --device /dev/nvme0n1p2

To revoke TPM2 access (e.g. before selling hardware):
  run0 systemd-cryptenroll --wipe-slot=tpm2 <device>
EOF
      exit 0 ;;
    *) die "Unknown option: $1. Use --help to see the available options." ;;
  esac
done

if [[ -z "$OPT_DEVICE" ]]; then
  OPT_DEVICE=$(detect_luks_device || true)
fi

if [[ -z "$OPT_DEVICE" ]]; then
  die "Could not auto-detect the LUKS root partition. Please specify --device /dev/<partition>."
fi

DEVICE="$OPT_DEVICE"
PCRS="$OPT_PCRS"

echo
echo -e "${BOLD}╔══════════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║              LUKS Unlock via TPM2 Setup                      ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════════╝${RESET}"
echo

# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------

info "==> Checking prerequisites..."

if [[ ! -b "$DEVICE" ]]; then
  die "LUKS device not found: $DEVICE
  Specify the correct path with --device <partition>"
fi
success "LUKS device found: $DEVICE"

if ! command -v systemd-cryptenroll >/dev/null 2>&1; then
  die "systemd-cryptenroll not found. Please ensure systemd is installed."
fi

TPM_DEVICES=$(ls /dev/tpmrm* /dev/tpm[0-9]* 2>/dev/null || true)
if [[ -z "$TPM_DEVICES" ]]; then
  die "No TPM device found at /dev/tpm*.
  Check whether TPM 2.0 is enabled in the system's UEFI/BIOS."
fi
success "TPM2 detected: $TPM_DEVICES"

if ! command -v cryptsetup >/dev/null 2>&1; then
  die "cryptsetup not found."
fi

if ! cryptsetup isLuks "$DEVICE" 2>/dev/null; then
  die "$DEVICE is not a valid LUKS volume."
fi
success "Valid LUKS volume: $DEVICE"

echo
info "Device: $DEVICE"
info "PCRs:   $PCRS"
echo

# ---------------------------------------------------------------------------
# Remove existing TPM2 slot (if --wipe)
# ---------------------------------------------------------------------------

if [[ "$OPT_WIPE" == "true" ]]; then
  info "==> Removing existing TPM2 slot..."
  if systemd-cryptenroll --wipe-slot=tpm2 "$DEVICE"; then
    success "TPM2 slot removed."
  else
    warn "No TPM2 slot found to remove (or removal failed)."
  fi
  echo
fi

# ---------------------------------------------------------------------------
# Enroll the TPM2
# ---------------------------------------------------------------------------

info "==> Enrolling the TPM2 for the LUKS volume..."
info "    (You will be prompted for your existing LUKS passphrase to authorize this)"
echo

systemd-cryptenroll \
  --tpm2-device=auto \
  --tpm2-pcrs="$PCRS" \
  "$DEVICE"

echo
success "TPM2 enrolled successfully!"
echo
info "The system will automatically unlock the disk on boot,"
info "as long as the PCR measurements [$PCRS] match the current state."
echo
warn "IMPORTANT: Re-enroll the TPM2 after:"
warn "  • Firmware updates (UEFI/BIOS)"
warn "  • Secure Boot configuration changes"
warn "  • Hardware swaps (motherboard, TPM chip)"
echo
info "To revoke TPM2 access:"
echo "  run0 systemd-cryptenroll --wipe-slot=tpm2 $DEVICE"
