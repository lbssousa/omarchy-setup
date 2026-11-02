#!/usr/bin/env bash
# efi-boot-cleanup.sh — Remove stale entries from the UEFI boot list
#
# Leftovers from earlier installs pile up in the firmware's boot list. An
# entry counts as stale when:
#   1. it points to a GPT partition (HD(...,GPT,<PARTUUID>,...)) that no
#      connected disk has any more (an earlier install whose ESP is gone);
#   2. the partition exists and is mounted, but the .efi file isn't on it;
#   3. it duplicates another entry exactly (same partition and path).
#
# Never removes: BootCurrent, entries without an HD() path (firmware, PXE,
# Setup...), firmware-created entries for disks that are present, or entries
# given with --keep. An entry on an unplugged USB disk counts as stale: plug
# it in first, or protect it with --keep.
#
# Dry run by default; --apply removes, after saving the current list to
# /root/efibootmgr-backup-<date>.txt.
#
# Usage:
#   bash scripts/efi-boot-cleanup.sh                  # dry run
#   run0 scripts/efi-boot-cleanup.sh --apply          # remove (asks first)
#   run0 scripts/efi-boot-cleanup.sh --apply --yes --keep 0005,0008

set -euo pipefail

APPLY=0
ASSUME_YES=0
KEEP=""

usage() { sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --apply)   APPLY=1 ;;
        -y|--yes)  ASSUME_YES=1 ;;
        --keep)    KEEP="${2:-}"; shift ;;
        -h|--help) usage 0 ;;
        *) echo "Unknown option: $1" >&2; usage 1 ;;
    esac
    shift
done

command -v efibootmgr >/dev/null || { echo "efibootmgr not found." >&2; exit 1; }
[[ -d /sys/firmware/efi ]] || { echo "Not booted in UEFI mode." >&2; exit 1; }
if (( APPLY )) && [[ $EUID -ne 0 ]]; then
    echo "--apply needs root (use run0)." >&2; exit 1
fi

KEEP="${KEEP^^}"
OUTPUT="$(efibootmgr -v)"
CURRENT="$(awk '/^BootCurrent:/ {print toupper($2)}' <<<"$OUTPUT")"

# PARTUUIDs present on connected disks (lowercase)
mapfile -t PARTUUIDS < <(lsblk -rno PARTUUID 2>/dev/null | awk 'NF' | tr '[:upper:]' '[:lower:]')
partuuid_exists() {
    local p
    for p in "${PARTUUIDS[@]}"; do [[ $p == "$1" ]] && return 0; done
    return 1
}

# Mount point of a partition, by PARTUUID (empty when not mounted)
mountpoint_of() {
    local dev
    dev="$(blkid -t PARTUUID="$1" -o device 2>/dev/null | head -n1)" || true
    [[ -n $dev ]] && findmnt -rno TARGET --source "$dev" 2>/dev/null | head -n1
}

# Whether the loader file is on the ESP (FAT is case-insensitive).
# Returns 0 = present, 1 = missing, 2 = can't tell (no permission).
efi_file_exists() {
    local mnt="$1" path="$2" cur="$1" part match
    [[ -r $mnt && -x $mnt ]] || return 2
    path="${path//\\//}"; path="${path#/}"
    IFS='/' read -ra parts <<<"$path"
    for part in "${parts[@]}"; do
        [[ -z $part ]] && continue
        [[ -r $cur && -x $cur ]] || return 2
        match="$(find "$cur" -mindepth 1 -maxdepth 1 -iname "$part" -print -quit 2>/dev/null)"
        [[ -z $match ]] && return 1
        cur="$match"
    done
    [[ -f $cur ]]
}

declare -a TO_DELETE=()
declare -A SEEN=()

printf '%-6s %-4s %-28s %s\n' "Entry" "Act." "Label" "Reason"
printf '%s\n' "------------------------------------------------------------------------------"

while IFS= read -r line; do
    [[ $line =~ ^Boot([0-9A-Fa-f]{4})(\*?)[[:space:]]+([^$'\t']*)$'\t'(.*)$ ]] || continue
    num="${BASH_REMATCH[1]^^}"
    label="${BASH_REMATCH[3]}"
    dp="${BASH_REMATCH[4]}"
    action="KEEP"; reason=""

    if [[ ! $dp =~ HD\([0-9]+,GPT,([0-9A-Fa-f-]{36}) ]]; then
        reason="no GPT partition (firmware/network/removable)"
    else
        uuid="${BASH_REMATCH[1],,}"
        path=""
        [[ $dp =~ \)/(\\[^{]*) ]] && path="${BASH_REMATCH[1]}"
        key="$uuid|${path,,}"

        if [[ $num == "$CURRENT" ]]; then
            reason="BootCurrent (the running system)"
        elif [[ ",$KEEP," == *",$num,"* ]]; then
            reason="protected by --keep"
        elif [[ $dp == *"{auto_created_boot_option}"* ]] && partuuid_exists "$uuid"; then
            reason="created by the firmware (disk fallback)"
        elif ! partuuid_exists "$uuid"; then
            action="DEL"; reason="partition $uuid doesn't exist"
        elif [[ -n ${SEEN[$key]:-} ]]; then
            action="DEL"; reason="duplicate of Boot${SEEN[$key]}"
        else
            mnt="$(mountpoint_of "$uuid" || true)"
            rc=0
            if [[ -n $mnt && -n $path ]]; then
                efi_file_exists "$mnt" "$path" || rc=$?
            fi
            case "$rc" in
                1) action="DEL"; reason="$path missing from $mnt" ;;
                2) reason="partition exists (no permission to check the file)" ;;
                *) reason="partition exists${mnt:+, file checked in $mnt}" ;;
            esac
        fi
        [[ $action == KEEP && -z ${SEEN[$key]:-} ]] && SEEN[$key]="$num"
    fi

    printf '%-6s %-4s %-28.28s %s\n' "$num" "$action" "$label" "$reason"
    [[ $action == DEL ]] && TO_DELETE+=("$num")
done <<<"$OUTPUT"

echo
if (( ${#TO_DELETE[@]} == 0 )); then
    echo "No stale entries."; exit 0
fi

echo "Entries to remove: ${TO_DELETE[*]}"
if (( ! APPLY )); then
    echo "Dry run. Run 'run0 $0 --apply' to remove them."
    exit 0
fi

if (( ! ASSUME_YES )); then
    read -rp "Remove ${#TO_DELETE[@]} entries? [y/N] " ans
    [[ $ans =~ ^[yYsS]$ ]] || { echo "Cancelled."; exit 0; }
fi

BACKUP="/root/efibootmgr-backup-$(date +%Y%m%d-%H%M%S).txt"
printf '%s\n' "$OUTPUT" >"$BACKUP"
echo "Current list saved to $BACKUP"

for num in "${TO_DELETE[@]}"; do
    echo "Removing Boot$num..."
    efibootmgr -q -b "$num" -B
done

echo
efibootmgr
