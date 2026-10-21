# Omarchy Quattro RS 4.5 migration notes

What the next Omarchy release changes for the automations in this repo,
gathered ahead of time so the migration is quick once it ships.

**Snapshot date:** 2026-10-16. 4.5 was not released yet: no tag, no ISO,
no release notes. DHH announced the name on 2026-09-08 ("Quattro RS
4.5", skipping 4.1, with a bespoke optimized kernel). Everything below
comes from what was already merged on `omacom/omarchy`'s `quattro`
branch (its development trunk) after `v4.0.4`, leaving out the commits
backported to 4.0.x. It can still change before the tag. Re-check each
item against the real release (see *Re-checking* at the end).

## Summary

| Playbook | Verdict | Upstream change |
|---|---|---|
| `limine-silent-boot.yml` | Obsolete | [#15301](https://github.com/omacom/omarchy/pull/15301) |
| `libfprint.yml` (watchdog, lock-screen detector only) | Partly obsolete | [#7158](https://github.com/omacom/omarchy/pull/7158), [#15294](https://github.com/omacom/omarchy/pull/15294) |
| `file-chooser.yml` | **Needs a fix** (regression) | [#9594](https://github.com/omacom/omarchy/pull/9594) |
| `capslock.yml` | Still needed; comments outdated | [#14939](https://github.com/omacom/omarchy/pull/14939) |
| `ptbr.yml` (locale step) | Partly covered upstream | [#15326](https://github.com/omacom/omarchy/pull/15326) |
| `keepassxc.yml`, `proton-pass.yml` | Possible conflict (opt-in) | [#9399](https://github.com/omacom/omarchy/pull/9399) |
| everything else | No impact found | — |

## Obsolete

### `limine-silent-boot.yml`

The 4.5 template (`default/limine/limine.conf`) ships `timeout: 1` and
`quiet: yes` in the header, which is exactly what this playbook sets.
Migration `1791898365.sh` applies the same to existing installs: it
adds `quiet: yes` wherever it is missing and sets `timeout: 1` only
where no uncommented `timeout:` exists (ours is kept). System gains
*Reboot to Boot Menu* (`omarchy-system reboot-boot-menu`).

**Before deleting the playbook:** the migration edits `limine.conf`
with `sed` and doesn't run `limine-update`. With Secure Boot
(`ENABLE_ENROLL_LIMINE_CONFIG=yes`, see `docs/secureboot.md`), a
`limine.conf` edit without re-enrolling the checksum halts the boot.
Check whether 4.5 re-enrolls it some other way. If not, keep a tiny
task that runs `limine-update` when the header changed, or fold it into
`secureboot.yml`. The header comments in the playbook about why
`quiet` must sit before the first entry and why Space doesn't open the
menu are still worth keeping somewhere (e.g. `docs/secureboot.md`).

**Action:** remove the play from `site.yml`, the `limine-silent-boot`
Justfile recipe and its README rows, plus `limine_silent_boot_*` in
`group_vars/all/main.yml`.

### `libfprint.yml`: the lock-screen half of `fprintd-desync-watchdog`

`playbooks/files/fprintd-desync-watchdog.sh` runs two detectors. The
second one works around the lock screen retrying fingerprint auth every
250 ms with no backoff (omacom/omarchy#7176, #7172). Both issues were
closed by #7158, merged on 2026-10-04:

- an exponential backoff, plus a "Fingerprint reader unavailable"
  notice;
- a `system-sleep` hook that restarts fprintd on resume (installed by
  `omarchy-setup-security-fingerprint`);
- the reader is left alone while the lock has the displays off
  (#15294).

**Action:** drop `watch_burst` (the burst detector) from the watchdog
and its comment in `libfprint.yml`. Keep `watch_desync`: the goodix538d
protocol desync is a bug in our driver fork, not in Omarchy. Re-test
fingerprint unlock after suspend once 4.5 is installed, since the
upstream resume hook now restarts fprintd too.

## Needs a fix before running on 4.5

### `file-chooser.yml`: keeps the Secret portal

4.5 ships `~/.config/xdg-desktop-portal/hyprland-portals.conf` with
`org.freedesktop.impl.portal.Secret=gnome-keyring`. It comes from
`config/` on new installs and from migration `1788261467.sh` on
existing ones, which is skipped when the file already exists. Our
*Route the FileChooser portal to the GNOME backend* task writes that
same file whole with `ansible.builtin.copy`. That drops the Secret
line, so sandboxed apps (any Flatpak still installed) lose the
keyring.

**Action:** replace the `copy` with `community.general.ini_file` on
section `preferred`, option `org.freedesktop.impl.portal.FileChooser`,
value `gnome`. Keep a `default=hyprland;gtk` default only when the file
is created from scratch. Restart the portals as today.

## Still needed, update the comments

### `capslock.yml`

4.5 stops using `compose:caps,shift:both_capslock_cancel`. Caps Lock is
Caps Lock again, and Shift+Caps Lock is Compose through Omarchy's own
XKB option `omarchy:shift_caps_compose` (`/etc/xkb/rules/evdev`,
`/etc/xkb/symbols/omarchy`).

Our block in `~/.config/hypr/input.lua` replaces `kb_options` with
`compose:menu`, so the keyd remap keeps working. The block is even
*required* now: with Omarchy's option in effect, keyd's
`[shift] capslock = capslock` would reach XKB as Shift+Caps and type
Compose instead of toggling Caps Lock.

**Action:** rewrite the header of `capslock.yml` (it says Omarchy
defaults to `compose:caps`) to explain the new conflict instead. Check
that the override doesn't need to keep any other option Omarchy now
puts in `kb_options`.

### `ptbr.yml`: locale step

`omarchy-language pt-BR` (Setup > Language, #15326) generates
`pt_BR.UTF-8`, writes `LANG` to
`~/.config/uwsm/env.d/50-omarchy-language` (exported to every app, so
it wins over `/etc/locale.conf` for the session) and switches Omarchy's
own menus, shell and notifications to Portuguese.

**Action:** in the `ptbr-locale` block, call `omarchy-language pt-BR`.
Keep `LANGUAGE=pt_BR:pt:en_US:en` (Omarchy doesn't set a gettext
fallback chain) and decide whether `/etc/locale.conf` still matters
(TTY, system services). Upstream covers none of the other areas:
xdg-user-dirs, Chromium family, LibreOffice, man pages, OCR.
`omarchy-capture-text` still reads `OMARCHY_OCR_LANGS`, which defaults
to `eng`.

### Password managers' SSH agents

4.5 adds an optional `omarchy-setup-security-ssh-agent`. It enables
`gcr-ssh-agent.socket` and writes
`~/.config/environment.d/90-gcr-ssh-agent.conf`. That file sorts after
our `20-proton-pass-ssh-agent.conf` and
`20-ssh-agent.conf`, so it wins `SSH_AUTH_SOCK`.

**Action:** none unless someone runs it. Optionally warn in those
playbooks when `90-gcr-ssh-agent.conf` exists.

## To verify

- **`pam-auth-order.yml`:** fixed. `polkit-1` now ends in
  `include system-auth` (commit `8a13eac8`, migration `1788256455.sh`)
  and exists only as `/usr/lib/pam.d/polkit-1`; `/etc/pam.d/polkit-1`
  is gone, which made `lineinfile` fail with "Destination does not
  exist". `tasks/pam-auth-order-file.yml` now seeds the `/etc` copy from
  the vendor file first. Run it once and check both stacks.
- **`pdf-viewer.yml`:** Evince is still the default
  (`default/applications/mimeapps.list`). Signed is a new PDF app but
  doesn't take the default. Check that Zathura is still the default
  after installing Signed.
- **`file-manager.yml`:** Nautilus is still the default for
  `inode/directory` upstream; no change.

## Re-checking when 4.5 is tagged

```bash
git clone --filter=blob:none https://github.com/omacom/omarchy.git
cd omarchy
# Did each change land in the tag?
for pr in 15301 7158 15294 9594 14939 15326 9399; do
  git log --oneline v4.0.4..v4.5.0 --grep "#$pr" | head -1
done
git diff v4.0.4 v4.5.0 -- install/omarchy-base.packages
git show v4.5.0:default/limine/limine.conf | head
git show v4.5.0:config/xdg-desktop-portal/hyprland-portals.conf
```

The release tag may be named differently: check `git tag`. Then work
through the sections above, deleting each one as it is done.

## Sources

- [DHH on X: the next version is Quattro RS 4.5](https://x.com/dhh/status/2097236884531351700)
- [Omarchy Central: Quattro RS 4.5, bespoke kernel](https://omarchycentral.com/news/omarchy-quattro-rs-4-5-bespoke-kernel/)
- [omarchy.org news](https://omarchy.org/news/)
- [Linuxiac: Omarchy 4.0.4 makes its custom kernel the default](https://linuxiac.com/omarchy-4-0-4-makes-its-custom-linux-kernel-the-default/)
- [omacom/omarchy, `quattro` branch](https://github.com/omacom/omarchy/tree/quattro)
