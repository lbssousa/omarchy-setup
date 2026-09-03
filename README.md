# omarchy-setup

Ansible automation for setting up a freshly installed
[Omarchy](https://omarchy.org/) desktop.

Each automation is its own playbook under `playbooks/`, imported by
`site.yml`. All of them share the same privilege escalation (sudo, see
`ansible.cfg`), and each has its own tag: run one with `--tags <tag>`,
or skip one with `--skip-tags <tag>`. Exception: `playbooks/secureboot.yml`
is **not** imported by `site.yml` — it touches firmware/boot, so it
only runs when called explicitly.

## What it sets up

| Automation | Tag | What it does |
|---|---|---|
| NVIDIA | `nvidia` | Installs the right proprietary driver for the detected GPU, plus early KMS. |
| Firefox | `firefox` | Installs Firefox and enables tab apps (Taskbar Tabs), off by default on Linux. Runs before pt-BR localization. |
| Zed editor | `zed` | Installs Zed + omazed (Omarchy theme integration), sets every font size (UI, buffer, agent, terminal) to 20px and the buffer font to JetBrainsMono Nerd Font. |
| pt-BR localization | `ptbr` | Locale, personal folder names, Firefox/Chromium/LibreOffice/man pages/OCR language. |
| Bitwarden | `bitwarden` | Desktop client (AUR or official, whichever is newer) + SSH agent wiring. |
| Podman | `podman` | Rootless container engine. |
| Distrobox | `distrobox` | Depends on Podman. |
| libfprint (goodix538d) | `libfprint` | Builds and installs a fingerprint driver fork, plus a watchdog for a driver desync bug and the Omarchy lock-screen retry-storm bug. |
| EPSON L4160 printer | `printer` | Driverless CUPS queue (IPP Everywhere). |
| Hyprland scrolling resize | `hypr-scrolling-resize` | SUPER+[ / SUPER+SHIFT+[ resize the focused column. |
| Shell/terminal text size | `text-size` | Scales the bar + terminals without scaling GTK apps. |
| Night light | `nightlight-solar` | Syncs hyprsunset to real sunrise/sunset daily. |
| Caps Lock via keyd | `capslock` | tap=Esc, hold=Ctrl, Shift+CapsLock=CapsLock; moves Compose off Caps Lock. |
| Secure Boot | `secureboot` | Limine + sbctl. Not part of `just setup` — see [`docs/secureboot.md`](docs/secureboot.md). |
| Yubikey GPG key | `gpg-yubikey` | Imports the public key, trusts it, configures git signing. Not part of `just setup`. |
| Yubikey SSH keys | `ssh-yubikey` | Prepares for downloading resident FIDO2 keys. Not part of `just setup`. |

See each playbook's own header comment for implementation details.

## Prerequisites

- An Omarchy desktop (or any Arch Linux with pacman, `locale-gen`,
  systemd and `xdg-user-dirs`).
- `sudo` and a user in the `wheel` group.
- The libfprint playbook needs Podman + Distrobox already set up
  (`site.yml` already runs them in the right order).
- The NVIDIA playbook depends on Omarchy's own hardware-detection
  tools — Omarchy-specific, not plain Arch.
- The Secure Boot playbook only covers Limine + limine-entry-tool.

Neither `just` nor `ansible` need to be pre-installed: `./bootstrap.sh`
installs `just`; `just setup` then installs `ansible` and the
`community.general` collection on its own.

### Privilege: sudo + --ask-become-pass

Every privileged task uses sudo with `--ask-become-pass`: it asks for
your password once, at the start, and feeds it to sudo whenever needed.

That password is a fallback, not the primary method: the fingerprint
reader is configured as a sudo login method outside this repo, and is
tried first on every privileged task, silently. If it doesn't resolve,
the password covers the rest. `ansible_local_become_success_timeout: 60`
(in `group_vars/all/main.yml`) gives the fingerprint prompt enough time
to give up on its own before Ansible's local connection times out
waiting for it.

Careful with hidden/unattended terminals: the fingerprint prompt is
still tried first even with nobody there to touch the sensor. A caller
without a human present should use `ansible_become_flags=-H -n` (or
`sudo -n`) to fail fast instead. As a safety net,
[`playbooks/sudo.yml`](playbooks/sudo.yml) lowers sudo's
`passwd_timeout` to limit how long that can hang.

## Usage

```bash
git clone https://github.com/lbssousa/omarchy-setup.git
cd omarchy-setup
./bootstrap.sh   # installs `just`, if missing — only needs to run once
just setup
```

Or directly with Ansible:

```bash
sudo pacman -S --needed ansible
ansible-galaxy collection install -r requirements.yml
ansible-playbook site.yml --ask-become-pass
```

Run a single automation with `just <name>` (see the Justfile) or
`ansible-playbook site.yml --ask-become-pass --tags <tag>`.

The playbooks are idempotent — rerunning is safe.

**Secure Boot, the Yubikey GPG key, and the Yubikey SSH keys are
separate** — not part of `just setup`:

```bash
just secureboot   # see docs/secureboot.md for the full walkthrough
just gpg-yubikey  # needs the Yubikey plugged in
just ssh-yubikey  # needs the Yubikey plugged in
```

## Structure

| File/Directory | Role |
|---|---|
| `bootstrap.sh` | Installs `just`, if missing |
| `site.yml` | Index: imports each `playbooks/*.yml` with its tag |
| `playbooks/sudo.yml` | sudo passwd_timeout (tag `sudo`) |
| `playbooks/polkit.yml` | polkitd ExpirationSeconds (tag `polkit`) |
| `playbooks/nvidia.yml` | NVIDIA driver (tag `nvidia`) |
| `playbooks/firefox.yml` | Firefox + tab apps (tag `firefox`) |
| `playbooks/zed.yml` | Zed editor + Omarchy theme + font size (tag `zed`) |
| `playbooks/ptbr.yml` | pt-BR localization (tag `ptbr`) |
| `playbooks/bitwarden.yml` | Bitwarden (tag `bitwarden`) |
| `playbooks/podman.yml` | Podman rootless (tag `podman`) |
| `playbooks/distrobox.yml` | Distrobox (tag `distrobox`) |
| `playbooks/libfprint.yml` | libfprint goodix538d (tag `libfprint`) |
| `playbooks/printer.yml` | EPSON L4160 printer (tag `printer`) |
| `playbooks/hypr-scrolling-resize.yml` | Scrolling-layout column resize (tag `hypr-scrolling-resize`) |
| `playbooks/text-size.yml` | Shell bar + terminal text size (tag `text-size`) |
| `playbooks/nightlight-solar.yml` | Night light synced to sunrise/sunset (tag `nightlight-solar`) |
| `playbooks/capslock.yml` | Caps Lock via keyd (tag `capslock`) |
| `playbooks/secureboot.yml` | Secure Boot — outside `site.yml` (tag `secureboot`) |
| `docs/secureboot.md` | `just secureboot` walkthrough |
| `playbooks/yubikey-gpg.yml` | Yubikey GPG key — outside `site.yml` (tag `gpg-yubikey`) |
| `playbooks/yubikey-ssh.yml` | Yubikey resident SSH keys — outside `site.yml` (tag `ssh-yubikey`) |
| `playbooks/files/` | Static files copied as-is |
| `playbooks/templates/` | Jinja2 templates |
| `playbooks/tasks/` | Reusable tasks included via `include_tasks` |
| `group_vars/all/main.yml` | Variables for all automations |
| `requirements.yml` | Required Ansible collections |
| `Justfile` | Shortcuts (`just setup`, `just nvidia`, etc.) |
