# `just apply tpm2` — Automatic LUKS Unlock via TPM2

Usage guide for `playbooks/system/tpm2.yml` and `scripts/enroll-tpm2.sh`. Unlike
most automations in this repository, **this playbook is not part of `just setup`**
— it touches disk encryption and bootloader configuration, so it only runs when
called explicitly: `just apply tpm2` (or `just tpm2-wipe`).

## Overview

Automatic LUKS unlock binds the encryption keys of the LUKS2 volume (holding the
root filesystem) to the hardware **TPM2 (Trusted Platform Module)** chip using
`systemd-cryptenroll`.

At early boot, the initramfs (`sd-encrypt`) verifies the TPM2 measurements (PCRs)
against the sealed policy. If the measurements match, the volume is decrypted
automatically without asking for a password. If the measurements differ (e.g.,
firmware update, BIOS settings changed, Secure Boot keys altered), the TPM2
refuses to release the key, and the boot sequence safely falls back to prompting
for your standard LUKS passphrase.

Your existing passphrase keyslot remains intact at all times as a permanent
fallback.

## Sealed PCRs

By default, the automation seals the LUKS volume against **PCRs 0+2+7**:
- **PCR 0**: UEFI BIOS / firmware code and motherboard state.
- **PCR 2**: UEFI Option ROMs (PCIe devices, GPU firmware, network cards).
- **PCR 7**: Secure Boot state (UEFI Secure Boot enabled, PK, KEK, db, dbx keys).

If you change BIOS settings, update firmware, or change Secure Boot keys, PCR 0,
2, or 7 will change, and TPM2 auto-unlock will gracefully fall back to the
passphrase until you re-enroll.

## Prerequisites

- Physical machine with a TPM 2.0 chip enabled in UEFI/BIOS (Intel PTT, AMD
  fTPM, or discrete TPM).
- Encrypted root partition using **LUKS2** format.
- Run after the initial successful boot (and ideally after enabling Secure Boot
  via `just apply secureboot`).
- Administrator (`wheel`) access with `run0` empowerment.

## How it works in Omarchy

1. **Packages**: Ensures `tpm2-tools` and `tpm2-tss` are installed.
2. **LUKS Partition Discovery**: Auto-detects the root partition's LUKS2 UUID
   (e.g., `/dev/nvme0n1p2`).
3. **/etc/crypttab**: Adds an entry with `x-initrd.attach` and `tpm2-device=auto`:
   ```
   root UUID=<UUID> none tpm2-device=auto,discard,x-initrd.attach
   ```
4. **mkinitcpio Drop-in** (`/etc/mkinitcpio.conf.d/zz-tpm2.conf`):
   - Adds the required early kernel driver modules: `MODULES+=(tpm_crb tpm_tis)`.
   - Replaces the traditional busybox `encrypt` and `udev` hooks with systemd-based
     `systemd` and `sd-encrypt` (which include `libcryptsetup-token-systemd-tpm2.so`
     and support TPM2 token unsealing).
5. **Initramfs Rebuild**: Rebuilds the initramfs using `limine-update` (which also
   re-signs the boot binaries if Secure Boot is active).
6. **Enrollment**: Enrolls the TPM2 chip into a LUKS2 keyslot via
   `systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+2+7 <device>`.

## Step by step

### 1. Initial Setup & Enrollment

Run the playbook via `just`:

```bash
just apply tpm2
```

Ansible will configure the initramfs, crypttab, packages, and prompt you for
your LUKS passphrase to authorize adding the new TPM2 keyslot.

Alternatively, if you prefer the interactive standalone script (identical to
the `nix-config` workflow):

```bash
just tpm2-enroll
# or: run0 bash scripts/enroll-tpm2.sh
```

### 2. Re-enrolling after Firmware / Secure Boot updates

If a UEFI update or Secure Boot change altered PCR values and the system asks
for the disk password on boot:

1. Unlock the disk by typing your usual LUKS passphrase.
2. Once booted into your desktop, re-enroll the TPM2:
   ```bash
   just tpm2-wipe
   ```
   Or using the script:
   ```bash
   run0 bash scripts/enroll-tpm2.sh --wipe
   ```

### 3. Revoking TPM2 Access

To permanently revoke TPM2 unlocking (for example, before selling the device or
replacing the motherboard):

```bash
run0 systemd-cryptenroll --wipe-slot=tpm2 /dev/<luks-partition>
```

You can find the partition path with `cryptsetup status root`.

## Verification

To verify that the TPM2 token is enrolled in your LUKS volume:

```bash
run0 cryptsetup luksDump /dev/<luks-partition>
```

You should see a `systemd-tpm2` token in the `Tokens:` section, with `tpm2-pcrs: [0, 2, 7]`.
