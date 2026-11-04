#!/usr/bin/env bash
# Takes a machine set up for several users back to Omarchy's single-owner
# defaults, for the owner, from a terminal in their session. Run it again after
# each reboot it asks for: it works out what is left from the machine's state.
#
#   1. FIDO2     tests the key against /etc/fido2/fido2 (`just apply
#                security-key` moves it there), then removes the old list
#   2. accounts  removes the other accounts AND THEIR HOMES, after showing them
#   3. package   removes omarchy-multiuser and what omarchy-setup kept for it
#   4. TPM2 out  takes the TPM2 unlock out of the boot; the slot stays, then a
#                reboot has to ask for the disk password
#   5. close     wipes the TPM2 slot and turns autologin back on
#   6. choices   forgets the removed features in your saved choices
#
# Autologin only ever comes on with no TPM2 token left on the disk: with both,
# the machine would start into an open desktop without asking for anything.
#
# The code for several users is on this repository's multiuser branch.
#
# Usage: scripts/leave-multiuser.sh [--check]
#   --check  says what is left to do and changes nothing
set -euo pipefail

check=false
[[ ${1:-} == --check ]] && check=true

me=$(id -un)
config_home=${XDG_CONFIG_HOME:-$HOME/.config}
own_keys=$config_home/Yubico/u2f_keys
authfile=/etc/fido2/fido2
menu=$config_home/omarchy/extensions/omarchy-menu.jsonc
choices=$config_home/omarchy-setup/features.yml
tpm2_dropin=/etc/mkinitcpio.conf.d/zz-tpm2.conf
autologin=/etc/sddm.conf.d/autologin.conf
marker=/var/lib/omarchy-setup/leave-multiuser-tpm2-out

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }
die() { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }
ask() { # ask <question>: true on y/yes/s/sim
  local answer
  read -rp "$1 [y/N] " answer
  [[ $answer == [yYsS]* ]]
}
ask_word() { # ask_word <question> <word>: true only on exactly that word
  local answer
  read -rp "$1 Type $2 to go on: " answer
  [[ $answer == "$2" ]]
}

other_accounts() {
  getent passwd | awk -F: -v me="$me" \
    '$3 >= 1000 && $3 < 60000 && $7 !~ /(nologin|false)$/ && $1 != me { print $1 }'
}

luks_device() {
  local source
  source=$(findmnt -no SOURCE / | sed 's/\[.*//') || return 0
  lsblk -nsrpo NAME,TYPE,FSTYPE "$source" | awk '$3 == "crypto_LUKS" { print $1; exit }'
}

has_tpm2_token() { # needs root; true when the header has a TPM2 token
  sudo cryptsetup luksDump --dump-json-metadata "$1" |
    jq -e '[.tokens[] | select(.type == "systemd-tpm2")] | length > 0' >/dev/null
}

pending_fido2() { [[ -e $own_keys ]]; }
pending_accounts() { [[ -n $(other_accounts) ]]; }
pending_package() { pacman -Q omarchy-multiuser >/dev/null 2>&1; }
pending_tpm2_out() { [[ -e $tpm2_dropin ]]; }
pending_close() { [[ -n $(luks_device) && ! -e $autologin ]]; }
pending_choices() {
  [[ -f $choices ]] && grep -qE '^\s*(users|omarchy-multiuser|shared-checkout|tpm2):' "$choices"
}

if $check; then
  pending_fido2 && echo "FIDO2: $own_keys is still there"
  pending_accounts && echo "accounts: $(other_accounts | paste -sd' ')"
  pending_package && echo "package: omarchy-multiuser is installed"
  pending_tpm2_out && echo "TPM2 out: $tpm2_dropin is still there"
  pending_close && echo "close: the disk is encrypted and autologin is off"
  pending_choices && echo "choices: $choices names removed features"
  exit 0
fi

[[ -t 0 && -t 1 ]] || die "Run this from a terminal: it asks before each step."
(( EUID != 0 )) || die "Run it as yourself, not as root."

say "Keep a root shell open in another terminal (sudo -s) until this is over."

# --- 1. FIDO2 ---------------------------------------------------------------
if pending_fido2; then
  say "1. FIDO2: from $own_keys to $authfile"
  grep -q "^$me:" "$authfile" 2>/dev/null ||
    die "$authfile has no line for you. Run \`just apply security-key\` first."
  for service in sudo polkit-1; do
    grep -Eq "^\s*auth\s.*pam_u2f\.so.*authfile=$authfile" "/etc/pam.d/$service" ||
      die "/etc/pam.d/$service doesn't read $authfile. Run \`just apply security-key\` first."
  done
  echo "Authenticate with the key when asked, without typing the password."
  sudo -k
  sudo true || die "sudo failed. $own_keys stays; look at /etc/pam.d/sudo from your root shell."
  pkexec true || die "pkexec failed. $own_keys stays; look at /etc/pam.d/polkit-1 from your root shell."
  echo "Now unplug the key: the same two should ask for your password."
  read -rp "Press Enter when it is unplugged. " _
  sudo -k
  sudo true || die "sudo failed without the key. $own_keys stays."
  pkexec true || die "pkexec failed without the key. $own_keys stays."
  ask "Did the key work the first time and the password the second?" ||
    die "Stopping. $own_keys stays; run this again when both work."
  rm -f -- "$own_keys"
  rmdir --ignore-fail-on-non-empty -- "$(dirname "$own_keys")"
  echo "Removed $own_keys."
fi

# --- 2. Accounts ------------------------------------------------------------
if pending_accounts; then
  mapfile -t others < <(other_accounts)
  say "2. Accounts: these will be removed, WITH THEIR FILES. This can't be undone."
  for user in "${others[@]}"; do
    user_home=$(getent passwd "$user" | cut -d: -f6)
    printf '  %-12s %s\n' "$user" "$(sudo du -sh "$user_home" 2>/dev/null | cut -f1 || true) $user_home"
  done
  ask_word "Remove all of them and delete their homes?" DELETE || die "Nothing removed."
  command -v omarchy-mu-user-remove >/dev/null ||
    die "omarchy-mu-user-remove is missing; remove these accounts with userdel -r."
  for user in "${others[@]}"; do
    omarchy-mu-user-remove "$user" --delete-home
  done
  root_state=$(sudo passwd -S root | cut -d' ' -f2)
  [[ $root_state == P ]] || echo "Root's password is still locked ($root_state): systemd's emergency shell won't open."
fi

# --- 3. Package -------------------------------------------------------------
if pending_package; then
  say "3. Removing omarchy-multiuser"
  ask "Go on? Close what you don't want the shell restart to touch." || die "Stopping."
  # The guard deletes autologin.conf and would keep doing so.
  sudo systemctl disable --now omarchy-mu-sddm-guard.path omarchy-mu-sddm-sync.path omarchy-mu-apply-lock.path 2>/dev/null || true
  mapfile -t record_units < <(systemctl list-unit-files --no-legend 'omarchy-mu-migrate-record@*' | awk '{print $1}' | grep -v '@\.path$' || true)
  (( ${#record_units[@]} == 0 )) || sudo systemctl disable --now "${record_units[@]}" || true
  sudo systemctl disable --now "omarchy-mu-migrate-record@$me.path" 2>/dev/null || true
  # The menu block names commands the package takes away.
  if [[ -f $menu ]]; then
    tmp=$(mktemp)
    awk '/^ *\/\/ >>> omarchy-multiuser/ { skip = 1; next }
         /^ *\/\/ <<< omarchy-multiuser/ { skip = 0; next }
         !skip' "$menu" >"$tmp"
    cat "$tmp" >"$menu"
    rm -f -- "$tmp"
  fi
  sudo pacman -R --noconfirm omarchy-multiuser
  sudo groupdel omarchy-users 2>/dev/null || true
  sudo rm -rf -- /opt/omarchy-setup /etc/omarchy-multiuser /var/lib/omarchy-multiuser
  sudo rm -f -- /usr/local/bin/omarchy-setup-user /etc/sddm/hyprland.lua /etc/sddm.conf.d/zz-omarchy-setup-greeter.conf
  sudo rmdir --ignore-fail-on-non-empty /etc/sddm 2>/dev/null || true
  # The lock screen is a kept-loaded plugin: only a restart brings Omarchy's back.
  omarchy-restart-shell || echo "Restart the shell before locking the screen: omarchy-restart-shell"
fi

device=$(luks_device)

# --- 4. TPM2 out of the boot ------------------------------------------------
if pending_tpm2_out; then
  say "4. TPM2: back to the disk password at boot"
  [[ -n $device ]] || die "$tpm2_dropin exists, but the root isn't on LUKS. Look at it by hand."
  grep -q 'cryptdevice=' /proc/cmdline ||
    die "The kernel command line has no cryptdevice=, which Omarchy's encrypt hook needs. Add it to /etc/default/limine first."
  echo "Type the disk password, to check it before relying on it (no token is used):"
  sudo cryptsetup open --test-passphrase --disable-external-tokens "$device" ||
    die "That password doesn't open the disk. Nothing changed."
  ask "Do you have a live USB at hand, in case the machine doesn't boot?" || die "Stopping. Nothing changed."
  sudo cp -a /etc/crypttab /etc/crypttab.before-leave-multiuser
  sudo sed -i -E '/^\s*\S+\s+UUID=\S+\s+\S+\s+.*tpm2-device=auto/d' /etc/crypttab
  sudo rm -f -- "$tpm2_dropin"
  sudo limine-update
  sudo install -d -m 755 "$(dirname "$marker")"
  sudo touch "$marker"
  say "Reboot now. It must ask for the disk password, then show Omarchy's login screen."
  echo "Then run this again. The TPM2 slot is still there, and nothing uses it."
  exit 0
fi

# --- 5. Close ---------------------------------------------------------------
if pending_close; then
  say "5. Autologin, with the disk password as the only barrier"
  if has_tpm2_token "$device"; then
    if [[ -e $marker ]] && (( $(stat -c %Y "$marker") > $(date -d "$(uptime -s)" +%s) )); then
      die "Reboot first: this boot started before TPM2 left the initramfs."
    fi
    ask "Did this boot ask for the disk password?" || die "Stopping. Look at /etc/crypttab and the kernel command line."
    ask_word "Wipe the TPM2 slot? This can't be undone without enrolling again." WIPE || die "Stopping. Autologin stays off."
    sudo systemd-cryptenroll "$device" --wipe-slot=tpm2
  fi
  has_tpm2_token "$device" && die "The disk still has a TPM2 token: autologin stays off."
  printf '[Autologin]\nUser=%s\nSession=omarchy.desktop\n' "$me" | sudo tee "$autologin" >/dev/null
  sudo rm -f -- "$marker"
  sudo rmdir --ignore-fail-on-non-empty "$(dirname "$marker")" 2>/dev/null || true
  say "Autologin is on from the next boot, as in a stock encrypted Omarchy."
fi

# --- 6. Choices -------------------------------------------------------------
if pending_choices; then
  say "6. Forgetting the removed features in your choices"
  sed -i -E '/^\s*(users|omarchy-multiuser|shared-checkout|tpm2):/d' "$choices"
fi

say "Done. Now run \`just setup\`, then reboot if step 5 ran."
