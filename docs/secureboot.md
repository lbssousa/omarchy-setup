# `just secureboot` — Secure Boot (Limine + sbctl)

Usage guide for `playbooks/secureboot.yml`. Unlike the rest of this
repo, **this playbook is not part of `just setup`** — it touches
firmware/boot, so it only runs when called explicitly:
`just secureboot` (or `ansible-playbook playbooks/secureboot.yml
--ask-become-pass`).

## Prerequisites

- **Limine** bootloader with `limine-mkinitcpio-hook`
  (`limine-entry-tool`) installed — the default on Omarchy. The
  playbook fails early, without changing anything, on another
  bootloader (GRUB, systemd-boot).
- Physical access to enter the BIOS/UEFI twice during the process — not
  doable remotely over SSH.
- `sudo` with an interactive password.

## How it works

Limine has no shim or MOK/MOKmanager — the firmware verifies the
Limine binary's PE signature directly, and the kernel/initramfs are
protected by a BLAKE2b checksum embedded in that same binary
(`limine enroll-config`), not individual signatures. Once `sbctl` has
keys, any limine-entry-tool operation (including the pacman kernel
update hook) already re-signs the Limine binary on its own — this
playbook relies on that instead of a manual sign-and-enroll process.

## Step by step

Two runs of the playbook, with a BIOS trip in between — run
`just secureboot` the same way both times; it detects which stage
you're at.

### 1st run — preparation

```bash
just secureboot
```

With Secure Boot off, the playbook:

1. Confirms the bootloader is Limine + limine-entry-tool.
2. Installs `sbctl`.
3. Warns (without removing anything) if `splash` is on the kernel
   cmdline — incompatible with Secure Boot here.
4. Creates `sbctl` keys, if missing.
5. Sets `ENABLE_ENROLL_LIMINE_CONFIG=yes` and `ENABLE_VERIFICATION=yes`
   in `/etc/default/limine`, and `hash_mismatch_panic: yes` in
   `/boot/limine.conf`.
6. Runs `limine-update`, which signs the Limine binary with the new
   keys.
7. Shows `sbctl status` and `sbctl verify`.
8. Detects the firmware is **not in Setup Mode** and stops, with
   instructions.

### BIOS trip #1 — enter Setup Mode

1. Reboot and enter the BIOS/UEFI (F2, F12, Del or Esc during boot,
   depending on the vendor).
2. Go to **Secure Boot** and look for an option like *"Setup Mode"*,
   *"Clear Secure Boot Keys"*, or *"Delete All Secure Boot Keys"*.
3. Clear the existing keys — this enables Setup Mode.
4. Save and reboot back into Linux.

### 2nd run — key enrollment

```bash
just secureboot
```

This time the playbook detects Setup Mode and:

1. Unlocks immutable EFI variables, if needed.
2. Enrolls the keys into firmware: `sbctl enroll-keys --microsoft`
   (includes Microsoft's keys, for their-signed drivers/firmware).
3. Shows the result and next steps.

### BIOS trip #2 — enable Secure Boot

1. Reboot, enter the BIOS/UEFI again.
2. **Enable** Secure Boot.
3. Save and reboot.

### Final check

```bash
sbctl status      # should show "Secure Boot: enabled"
bootctl status    # same, under "Secure Boot"
```

If the machine doesn't boot with Secure Boot on, see
[If boot fails](#if-boot-fails) below.

## Important notes

- **`splash` (Plymouth) on the kernel cmdline** breaks boot with
  Secure Boot enabled here. The playbook warns but doesn't remove it —
  edit `/etc/default/limine` yourself and run `sudo limine-update`
  afterward if needed.
- **LUKS with TPM2 auto-unlock**: enabling Secure Boot for the first
  time changes PCR7 and breaks auto-unlock until you re-enroll:
  ```bash
  sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+2+7 /dev/<luks-partition>
  ```
  The password keeps working as a fallback in the meantime.
- **`hash_mismatch_panic: yes`** (enabled by this playbook) halts boot
  on a kernel/initrd checksum mismatch. Real integrity protection, but
  it means editing boot files by hand without going through
  limine-entry-tool afterward breaks boot.

## If boot fails

A misconfigured Secure Boot setup typically doesn't boot at all (black
screen or a Limine panic) rather than booting halfway — there's no
"partially broken" state. Recovery:

1. Reboot and enter the BIOS/UEFI.
2. **Disable** Secure Boot again — this alone should restore boot.
3. From Linux, run `sbctl verify` to see what's unsigned, and
   `sudo limine-update` to force a re-sign.
4. Repeat the steps above from where you left off.

No system files are deleted by this process — worst case is not being
able to re-enable Secure Boot until you fix the cause, not data loss
or a reinstall.

## Running again

The playbook is idempotent: rerunning `just secureboot` on an
already-configured machine just confirms the state and does nothing
new, except `limine-update` itself (always run, safe by design).
