# omarchy-setup

Ansible automation for setting up a freshly installed
[Omarchy](https://omarchy.org/) desktop.

Each automation is a play under `playbooks/`, imported by `site.yml`;
automations that depend on each other (Podman → Distrobox, snapd → VS Code,
the OpenSSH agent → KeePassXC) or that share a theme
(the desktop tweaks, the Yubikey helpers) live together in one playbook
file. All of them share the same privilege escalation (run0, see
`ansible.cfg`), and each automation has its own tag: run one with
`--tags <tag>`, or skip one with `--skip-tags <tag>`. A tag that names a
play with a dependency also runs the play it depends on first (e.g.
`--tags distrobox` sets Podman up first), and files with several plays
have an umbrella tag for the whole file (`containers`, `snap`, `desktop`,
`yubikey`). Exceptions:
`playbooks/secureboot.yml`, `playbooks/bgrt-theme.yml`,
`playbooks/apparmor.yml`, `playbooks/keepassxc.yml`, `playbooks/bitwarden.yml`,
`playbooks/proton-pass.yml`, `playbooks/homebrew.yml`, `playbooks/yubikey.yml`
are **not** imported by `site.yml` — Secure Boot, the BGRT boot theme and
AppArmor touch firmware/boot, KeePassXC, Bitwarden and Proton Pass are three
alternative password managers (install whichever one you want — none of them
is the default), Homebrew is only needed by the tools that install formulae
from it, and the Yubikey helpers need the physical token plugged in — so
they only run when called explicitly. TeX Live, LilyPond and Gregorio are a
separate tool entirely (`local-typesetting/`, `just typesetting`) — a
standalone shell script, not an Ansible playbook (see below).

## What it sets up

| Automation | Tag | What it does |
|---|---|---|
| Firefox | `firefox` | Installs Firefox from Flathub (bundles every locale, so pt-BR localization doesn't need a separate language pack for it) and turns on tab apps (Taskbar Tabs) by default — off by default on Linux even though it's stable — by dropping a `browser.taskbarTabs.enabled` default into the `org.mozilla.firefox.systemconfig` extension's `defaults/pref/` (the sandbox can't see the host's `/usr/lib/firefox`, and `policies.json`'s `Preferences` allowlist rejects that pref), so it's still visible and user-overridable in `about:config`. Bootstraps Flatpak + the Flathub remote itself. Runs before pt-BR localization. |
| Brave | `brave` | Installs Brave from Flathub, replacing the AUR `brave-origin-bin` package (uninstalled) that used to drive the Brave PWA web app swap (removed — see git history). Bootstraps Flatpak + the Flathub remote itself. Also removes the leftover `/etc/brave/policies/managed/omarchy-setup-webapps.json`. Omarchy's own web app launchers (YouTube, WhatsApp, Google Maps, ...) are left untouched and run on this Brave (see `default-browser`). |
| Brave PWA `.desktop` fixup | `brave-pwa-desktop-fix` | Fixes the `.desktop` files Brave's Flatpak PWA installer itself writes (`com.brave.Browser.flextop.brave-*.desktop`): shell-style quotes and an unescaped `?` in `Exec=` that violate the freedesktop.org spec, a missing `StartupNotify`, a `StartupWMClass` in the wrong format for Wayland window matching (`crx_<id>` instead of `brave-<id>-<profile>`), an `Icon=` pointing at a path Brave never actually writes to (rewritten to the bare icon name so themed lookup finds the real file under `~/.local/share/icons/hicolor`), and (for PWAs listed in `brave_pwa_containers`) a missing `--container=<name>` so the PWA opens inside its intended Brave container (`brave://settings/containers`) instead of the profile's default partition — see `playbooks/templates/fix-brave-pwa-desktop.sh.j2`. Also installs a systemd `--user` path unit that reruns the fix automatically whenever Brave installs or updates a PWA. Runs as part of `brave`; also has its own tag to rerun on its own. No root needed. |
| Default browser | `default-browser` | Makes the Flathub Brave the system default browser (only when it isn't already, so a later manual change isn't re-pinned — switch with `omarchy-setup-default-browser <firefox\|brave>`, or set `default_browser_desktop_id` in `group_vars/all/main.yml`). It is set through a hidden `~/.local/share/applications/brave-browser.desktop` shim whose `Exec=` is `~/.local/bin/omarchy-setup-brave` (runs `flatpak run com.brave.Browser "$@"`): Omarchy's `omarchy-launch-webapp` only accepts the Chromium family's native ids (`brave-browser*`), falls back to Chromium for `com.brave.Browser.desktop`, and takes just the first token of `Exec=` (a bare `flatpak`), so with the shim every native Omarchy web app (launcher entries, keybinds, `omarchy-launch-or-focus-webapp`) opens as a Brave `--app=` window with no change to Omarchy's files. The play asserts at run time that `omarchy-launch-webapp` still matches `brave-browser*`/`--app` and that the shim resolves to the wrapper. Also deploys `~/.local/bin/omarchy-setup-default-browser` (`<firefox\|brave>`), a stand-in for `omarchy default browser` (whose table lacks the Flathub ids), and fixes Omarchy's default-browser keybinds (`SUPER+SHIFT+RETURN`/`B`/`ALT+B`), where `flatpak run <id>` gets truncated to bare `flatpak`: symlinks the Flatpak-exported `.desktop` files into `~/.local/share/applications` (which `xdg-settings` needs too), deploys `~/.local/bin/omarchy-setup-launch-browser`, and rebinds the three keys to it. No root needed. |
| LibreOffice | `libreoffice` | Installs LibreOffice from Flathub (`org.libreoffice.LibreOffice`, bundles every locale), replacing Omarchy's pre-installed native `libreoffice-fresh` and its pt-BR language pack. Bootstraps Flatpak + the Flathub remote itself. Re-hides the Flatpak's Base/Draw/Math/Start Center/XSLT-filter components from the app launcher (`NoDisplay=true` overrides in `~/.local/share/applications`) to match Omarchy's own curation of the native build, and checks Omarchy's default keybinds plus this user's `~/.config/hypr/bindings.lua` for anything bound to LibreOffice, warning if one needs reassigning by hand (none exist by default). |
| Zed editor | `zed` | Installs Zed + omazed (Omarchy theme integration), sets every font size (UI, buffer, agent, terminal) to 25px and the buffer font to JetBrainsMono Nerd Font, and sets `use_podman` so Dev Containers use Podman instead of Docker. |
| Flathub app migrations | `flathub-apps` | Replaces the native Kdenlive, OBS Studio, Pinta and Xournal++ that Omarchy pre-installs (`omarchy-base.packages`) with their Flathub builds, and uninstalls the native packages. Cheaper than the LibreOffice swap: each app exports the **same** desktop-entry id in both builds (checked at run time — the play stops if it ever stops holding), so the app launcher, `mimeapps.list` and Hyprland's window rules need no changes. The rules are in fact fixed *by* the swap: Omarchy's `system.lua` no-opacity rules list the Flatpak classes `org.kde.kdenlive`/`com.obsproject.Studio`/`com.github.PintaProject.Pinta`, while the native builds report `kdenlive`/`obs`/`Pinta`, so they never matched before. Which apps are in the set is data (`flathub_app_migrations` in `group_vars/all/main.yml`) — trim the list to migrate a subset. Deliberately excludes mpv, LocalSend, Evince, Chromium and the TUI/GTK utilities Omarchy wires into its shell, plus Zed/Zathura/Papers (see `docs/flathub-migration-survey.md` for why each). |
| gregorio-lsp | `gregorio-lsp` | Installs Rust (`omarchy install dev-env rust`) if needed, then builds and installs the `gregorio-lsp`, `grelint` and `grefmt` binaries from source. |
| PDF viewer | `pdf-viewer` | Installs Zathura from Flathub (`org.pwmt.zathura`) as the default PDF viewer, replacing the Arch `zathura` + `zathura-pdf-mupdf` pair, and installs Papers as an extra, non-default viewer. Bootstraps Flatpak + the Flathub remote itself. Like the Kdenlive/OBS/Pinta/Xournal++ swap, this one is cheap because both builds export the same `org.pwmt.zathura.desktop` id, so the `~/.config/mimeapps.list` default survives untouched (asserted at run time). Two behaviour changes come with it: the backend becomes **zathura-pdf-poppler** instead of MuPDF (same upstream version, different engine), and the sandbox only grants `~/Documents` + `~/Downloads`, so a PDF from anywhere else is refused until you add the path to `pdf_viewer_zathura_extra_paths`. Evince stays installed since Nautilus's sushi previewer depends on it. |
| pinentry-omarchy | `pinentry` | Builds and installs [pinentry-omarchy](https://github.com/lbssousa/pinentry-omarchy) (Rust pinentry + omarchy-shell plugin) from its own PKGBUILD, installing Rust first if needed. It builds the release tag in `pinentry_omarchy_ref` only after verifying the tag's GPG signature against the Yubikey's key (`pinentry_omarchy_signing_keys`). Links and enables the `lbssousa.pinentry` shell plugin and sets `pinentry-program` in `~/.gnupg/gpg-agent.conf`, so GnuPG PIN and passphrase prompts (e.g. the Yubikey card PIN) use the same overlay dialog as the polkit agent. Without a Wayland session it falls back to pinentry-gnome3/curses. Must run inside the graphical session (enabling the plugin goes through the shell's IPC). |
| ssh-askpass-omarchy | `ssh-askpass` | Builds [ssh-askpass-omarchy](https://github.com/lbssousa/ssh-askpass-omarchy) (Rust askpass + omarchy-shell plugin) from the release tag in `ssh_askpass_ref`, checked out in `~/src/ssh-askpass-omarchy` only after verifying the tag's GPG signature against the Yubikey's key (`ssh_askpass_signing_keys`; **needs `just gpg-yubikey` first**), installing Rust first if needed. Installs the binary to `/usr/bin` and the plugin to `/usr/share`, links and enables `lbssousa.ssh_askpass`, and sets `SSH_ASKPASS` and `SSH_ASKPASS_REQUIRE=prefer` in `~/.config/environment.d/90-ssh-askpass.conf` (log in again to pick it up). SSH passphrases and FIDO PINs, `ssh-add -c` confirmations (Deny/Allow) and security key touch requests use the same overlay as the polkit agent. Must run inside the graphical session. |
| polkit-omarchy | `polkit-agent` | Installs [polkit-omarchy](https://github.com/lbssousa/polkit-omarchy) (a copy of Omarchy's polkit agent with pam_u2f support), from the release tag in `polkit_agent_ref`, checked out in `~/src/polkit-omarchy` only after verifying the tag's GPG signature against the Yubikey's key (`polkit_agent_signing_keys`; **needs `just gpg-yubikey` first**), to `/usr/share/polkit-omarchy/plugin` and enables the `lbssousa.polkit` shell plugin, which replaces `omarchy.polkit` (manifest `clonedFrom`). While pam_u2f waits for the security key, the dialog shows a "Touch your security key" prompt instead of a password field whose Enter does nothing. Must run inside the graphical session. |
| Shell plugins | `plugins` | Installs this desktop's list of third-party shell plugins — `omarchy_plugins` in `group_vars/all/main.yml`, **Radio Atlas** first (world radio on a rotatable globe in the bar, playing through Omarchy's `mpv`/`mpv-mpris`, so `omarchy.media` keeps the usual transport controls). Each entry is cloned by `omarchy plugin add` (the only supported installer: it validates the manifest, refuses an id another plugin already claims, and never runs plugin code, hooks or sudo), pinned to its `ref` (plugins are arbitrary unsandboxed QML inside the long-lived `omarchy-shell`, so the pin is the record of what was reviewed — `omarchy plugin update` fast-forwards a pinned clone off its tag, so bump `ref` instead), enabled, and **moved to the bar `section` the entry asks for**: Radio Atlas's icon lands in the right-hand group, right after the tray, rather than in the `left` its manifest's `defaultSection` asks for (`--enable` skips that prompt under `--yes`, so the play places the icon itself). Idempotent — re-running also pulls an icon you moved by hand back to where the list says — and the last tasks fail unless every entry really is enabled and in its section. Runtime dependencies are installed only when `pacman -T` reports one missing (all of them ship with Omarchy). Must run inside the graphical session. |
| openssh askpass notify | `openssh-askpass` | Rebuilds the installed openssh from Arch's packaging with `playbooks/files/openssh/askpass-notify.patch` (pkgrel `.1`), which makes OpenSSH honour `SSH_ASKPASS_REQUIRE` for notifications too, so a security key's "Confirm user presence" request reaches ssh-askpass-omarchy instead of the terminal. Official openssh updates replace it with the unpatched package; run it again after them. |
| GTK4 file dialogs | `file-chooser` | Makes the open/save file dialogs of non-GNOME apps (Firefox, Chromium, Electron, GTK and Qt apps) the GTK4 ones. Installs `xdg-desktop-portal-gnome` (its FileChooser is Nautilus's) and routes the FileChooser portal to it for Hyprland (`~/.config/xdg-desktop-portal/hyprland-portals.conf`), clears the session's forced `GDK_BACKEND` for that one service (otherwise it starts in a settings-only mode and shows no dialogs), and exports `GTK_USE_PORTAL=1` from `~/.config/hypr/hyprland.lua`. Qt apps (Qt5 like KeePassXC, and Qt6) use `qt5ct`/`qt6ct` as their platform theme (`QT_QPA_PLATFORMTHEME=qt6ct`) instead of Omarchy's `gtk3`, which draws GTK3 dialogs in-process: their `standard_dialogs=xdgdesktopportal` option asks the portal, and they also set the Qt UI font to GTK's family at `omarchy_system_ui_font_pt` (Qt's plain `xdgdesktopportal` theme would give portal dialogs but a 9pt fallback font). Log out and back in (or restart the app) to pick it up. |
| LazyVim plugins | `lazyvim` | Enables LazyVim's LaTeX extra and installs [gregorio.nvim](https://github.com/AISCGre-BR/gregorio.nvim) (GABC/NABC chant notation, pairs with gregorio-lsp). |
| pt-BR localization | `ptbr` | Locale, personal folder names, Firefox/Chromium/LibreOffice/man pages/OCR language. |
| Podman | `podman` | Rootless container engine. Part of `playbooks/containers.yml` with Distrobox and the starship integration (umbrella tag `containers`). |
| Distrobox | `distrobox` | Depends on Podman: the tag also runs the Podman play first. |
| Flatpak + Flathub | `flatpak` | Installs Flatpak, enables the Flathub remote system-wide (so the apps and launchers are there for every user, not just this one) and installs Bazaar, the Flathub app store. The app-installing plays (`firefox`, `brave`, `libreoffice`, `pdf-viewer`, `flathub-apps`) each bootstrap Flatpak + the remote themselves, so they work standalone; this play is the umbrella one. |
| snapd | `snapd` | Builds and installs snapd from the AUR (no official Arch package), enables `snapd.socket` (+ `snapd.apparmor.service`), links `/snap` → `/var/lib/snapd/snap` (classic snaps expect it), waits for first-boot seeding, and exports snap's `bin` and desktop-entry dirs to the graphical session (`PATH`/`XDG_DATA_DIRS` via `environment.d`; log out and back in to pick it up). Doesn't touch the kernel cmdline: strict confinement would need AppArmor as the active LSM, which Omarchy doesn't enable by default — snapd still works, and classic snaps don't need it. |
| Visual Studio Code | `vscode` | Installs VS Code from Microsoft's official snap (`--classic`). Depends on `snapd` (the tag also runs the snapd play first; `playbooks/snap.yml`, umbrella tag `snap`). Also fixes two Hyprland issues: sets `"password-store": "gnome-libsecret"` in `~/.vscode/argv.json` so VS Code uses the Secret Service keyring (Electron doesn't detect one under Hyprland), and installs a `~/.local/bin/code` wrapper + user desktop entries that set the UI scale to the monitor scale (the snap is forced onto XWayland, where `GDK_SCALE=2` made the UI too big). |
| libfprint (goodix538d) | `libfprint` | Builds and installs a fingerprint driver fork, plus a watchdog for a driver desync bug and the Omarchy lock-screen retry-storm bug. |
| EPSON L4160 printer | `printer` | Driverless CUPS queue (IPP Everywhere). |
| Hyprland scrolling resize | `hypr-scrolling-resize` | SUPER+[ / SUPER+] resize the focused column. This and the next two are plays of `playbooks/desktop.yml` (umbrella tag `desktop`). |
| Screen scale + text size | `text-size` | Sets the Hyprland monitor scale to 100% (and `GDK_SCALE` to match) and compensates with larger text: shell bar + terminals at 20px (15pt terminal font) and the GTK UI font at 12pt (Qt follows it through the `file-chooser` play), with GTK's text-scaling factor left at 1.0. |
| Night light | `nightlight-solar` | Syncs hyprsunset to real sunrise/sunset daily. |
| Caps Lock via keyd | `capslock` | tap=Esc, hold=Ctrl, Shift+CapsLock=CapsLock; moves Compose off Caps Lock. |
| Inkscape + svg2tikz | `inkscape` | Installs Inkscape and the [svg2tikz](https://github.com/xyz2tex/svg2tikz) extension (AUR `python-svg2tikz`) for exporting SVG paths as TikZ/PGF code for LaTeX. |
| Omadwaita themes | `omadwaita-themes` | Installs three Adwaita-based Omarchy themes whose terminal palettes come from Adwaita's nine accent colors, WCAG-AA-checked on their background: **Omadwaita** (dark TUI, light GTK — a `theme-set` hook flips GTK back to light), **Omadwaita Light** and **Omadwaita Dark**. All three use the Adwaita icon theme and share one wallpaper set (devotional paintings and wallpapers, `playbooks/files/omadwaita/backgrounds/`, migrated from the former Sacred Heart theme), plus a generated fallback wallpaper (the Omarchy logo on a gradient in the theme's palette). Browsers (Chromium, Brave, Chrome, Edge) get a per-theme `chromium.theme` seed color so their accent has Adwaita blue's hue instead of an arbitrary one derived from the neutral background. Omarchy never recolors GTK (it only picks `Adwaita`/`Adwaita-dark` from the theme's `mode`), so GTK apps keep the stock Adwaita palette. Installs only; apply with `omarchy-theme-set "Omadwaita"`. |
| Limine silent boot | `limine-silent-boot` | Sets `quiet: yes` (in the config header, before the first entry — otherwise Limine ignores it) and `timeout: 1` in `/boot/limine.conf` (and removes any `firmware_logo`) for a flicker-free boot: with `quiet` in effect Limine draws nothing and keeps the firmware BGRT logo on screen through its 1-second key window (press ↑/↓ to reveal the menu — not Space/Enter, which Limine treats as "boot the selected entry"; snapshots/fallback stay reachable). Re-runs `limine-update` to re-enroll the config checksum, so it also works with Secure Boot's `ENABLE_ENROLL_LIMINE_CONFIG=yes`. |
| ble.sh | `blesh` | Loads [ble.sh](https://github.com/akinomyoga/ble.sh) by default in Bash — Omarchy doesn't — with fish-style **autosuggestions** (ghost text from history, then completion) and **syntax highlighting** as you type. Builds AUR `blesh-git` (0.4.0-devel: the stable 0.3.4 predates Bash 5.3 and warns on every shell start against Omarchy's inputrc). Wraps the `source "$OMARCHY_PATH/default/bash/rc"` line in `~/.bashrc` with `source ble.sh --noattach` before it and `ble-attach` at the end, so starship and fzf's key bindings (Ctrl-R etc.) keep working; the feature options live in `~/.blerc`. Open a new terminal to pick it up. |
| rclone Google Drive | `rclone-gdrive` | Writes the config to mount Google Drive with rclone, same layout as nix-config's `rclone.nix`: `~/.config/rclone/rclone.conf` (remote `Google Drive`, `0600`), a `rclone-google-drive@.service` systemd `--user` template plus one env file per mount, and the mounts `~/Público/Google Drive/<email>/My Drive` and `…/Shared with Me` (base in `rclone_gdrive_base_dir`, instances in `rclone_gdrive_instances`; the unit creates `~/.cache/rclone` for the log file). The Google API OAuth `client_id`/`client_secret` are supplied by you on the first run — `RCLONE_GDRIVE_CLIENT_ID=… RCLONE_GDRIVE_CLIENT_SECRET=… just rclone-gdrive` (or `-e rclone_gdrive_client_id=…`) — and reused from `rclone.conf` afterwards. The OAuth token rclone stores is preserved across runs; the one manual step is `rclone config reconnect "Google Drive:"`, after which re-running starts the mounts. Installs `rclone` and `fuse3` via pacman. Not part of `just setup` (tag `never`): `just rclone-gdrive`. |
| Starship in distrobox | `starship-distrobox` | Makes the prompt work inside distrobox containers and show which one you're in (`⬢ <container> <dir> <branch> ❯`). Omarchy's `~/.bashrc` sources `$OMARCHY_PATH/default/bash/rc`, which doesn't exist in the container (its `/usr` is the image's; the host's is at `/run/host`), so starship never started: a `~/.bashrc` block points `OMARCHY_PATH` at `/run/host` inside distrobox and falls back to the host's starship binary (same Arch userland; another distro may need its own). The name comes from `CONTAINER_ID`, exported by `distrobox-enter`, through starship's `env_var` module in `~/.config/starship.toml` (blank on the host). |
| Homebrew | — | Installs Homebrew for Linux to `/home/linuxbrew/.linuxbrew` and symlinks `brew` into `/usr/local/bin`, then puts `bin`/`sbin` on the session `PATH` via `environment.d` (log out and back in to pick it up). Not part of `just setup` — run explicitly with `just homebrew`; only the tooling that installs formulae from it (e.g. the Proton Pass CLI) needs it. |
| TeX Live + LilyPond + Gregorio | — | Not an Ansible playbook: `local-typesetting/install-typesetting.sh` (`just typesetting`) installs TeX Live and LilyPond under `/opt`, builds Gregorio from source, and registers TeX Live's fonts with fontconfig, directly on the host with `sudo` — no containers. Not part of `just setup` — a long network install, run explicitly. See [`local-typesetting/README.md`](local-typesetting/README.md). |
| AppArmor | — | Activates AppArmor as a kernel LSM: `lsm=landlock,lockdown,yama,integrity,apparmor,bpf` (the kernel is built with it but leaves it out of the default list) via a `limine-entry-tool` drop-in + `limine-update`; needs a reboot. Two variants: **`just apparmor`** (kernel LSM only — no distro profiles loaded, the desktop is unchanged, snapd still confines strict snaps with its own profiles) and **`just apparmor-profiles`** (also enables `apparmor.service`, loading `/etc/apparmor.d`; on this setup that enforces `unix-chkpwd`, `avahi-daemon`, `ping`, …). Not part of `just setup`. |
| BGRT boot theme | `bgrt-theme` | Builds an Omarchy theme + a standalone Plymouth theme from this machine's own UEFI BGRT boot logo, so the same picture stays on screen from firmware through Plymouth to Hyprlock. Not part of `just setup` — rewrites the default Plymouth theme and rebuilds the initramfs. |
| Secure Boot | `secureboot` | Limine + sbctl. Not part of `just setup` — see [`docs/secureboot.md`](docs/secureboot.md). |
| Yubikey GPG key | `gpg-yubikey` | Imports the public key, trusts it, configures git signing. Not part of `just setup`. **A dependency of `pinentry`, `ssh-askpass` and `polkit-agent`**: they deploy signed release tags and stop at the start if this key isn't in the keyring, so run it first. Lives in `playbooks/yubikey.yml` (umbrella tag `yubikey`). |
| Yubikey SSH keys | `ssh-yubikey` | Not Ansible — `scripts/ssh-yubikey.sh` (the FIDO2 PIN prompt needs a real terminal). Downloads the resident FIDO2 keys with `ssh-keygen -K` into `~/.ssh` (never overwriting) and writes one self-contained drop-in per key, `~/.ssh/config.d/<host>_<user>.conf` (here `github_com_lbssousa.conf`): `github.com` authenticates with `id_ed25519_sk_rk_github.com_lbssousa` (override with `GITHUB_KEY=`) with `IdentityAgent none`, plus `ControlMaster auto` + `ControlPersist 10m`, so the PIN/touch is asked once per 10 minutes. Adds one `Include config.d/*.conf` line to `~/.ssh/config`, and migrates the old `10-yubikey-github.conf`. **To migrate to an ssh-agent: `just ssh-yubikey-disable`** (renames the drop-in to `*.conf.disabled`, which the `Include` glob ignores). Also `scripts/ssh-yubikey.sh status`/`enable`. Not part of `just setup`. |

See each playbook's own header comment for implementation details.

## Prerequisites

- An Omarchy desktop (or any Arch Linux with pacman, `locale-gen`,
  systemd and `xdg-user-dirs`).
- `run0` (part of systemd, so already there on Arch) and a user in the
  `wheel` group.
- The libfprint playbook needs Podman + Distrobox already set up
  (`site.yml` already runs them in the right order).
- The Proton Pass playbook needs Flatpak + Flathub (`site.yml` already
  runs it in the right order) and Homebrew (`just homebrew` — not part of
  `just setup`).
- The Secure Boot playbook only covers Limine + limine-entry-tool.

Neither `just` nor `ansible` need to be pre-installed: `./bootstrap.sh`
installs `just`; `just setup` then installs `ansible` and the
`community.general` collection on its own.

### Privilege: run0 --empower

Privileged tasks escalate with [`run0`](https://www.freedesktop.org/software/systemd/man/latest/run0.html)
(the `community.general.run0` become plugin, set as `become_method` in
`ansible.cfg`). run0 authenticates through polkit, and Omarchy's shell
registers a graphical polkit agent, so a bare run0 would pop up an
authentication dialog for **every** privileged task, and polkit doesn't
retain the authorization between separate run0 processes (checked on this
machine). A playbook run has dozens of privileged tasks.

So every recipe that needs root runs ansible-playbook through
[`run-empowered.sh`](run-empowered.sh), i.e. under `run0 --empower`: the
playbook keeps running as your user (same `$HOME`, `systemctl --user`, ...)
but with all capabilities and the `empower` group, for which systemd's stock
polkit rule allows every action. You authenticate **once**, in the polkit
dialog that appears at the start (fingerprint or password, whatever the
dialog offers), and each `become: true` task's own `run0 --user=root` inside
passes without another prompt. There is no `--ask-become-pass`: no password
is handed to run0.

Nothing persists: no polkit rule granting passwordless root is installed, and
the privileges live only in that process tree while it runs. Per run0(1),
other unprivileged processes of your user have privileges over an empowered
process, so don't run a playbook while untrusted software is running in your
session.

Careful with hidden/unattended terminals: the dialog needs someone at the
screen. A caller without a human present should pass
`ansible_become_flags=--no-ask-password` (or use `run0 --no-ask-password`) to
fail fast instead of waiting.

## Usage

```bash
git clone https://github.com/lbssousa/omarchy-setup.git
cd omarchy-setup
./bootstrap.sh   # installs `just`, if missing — only needs to run once
just setup
```

Or directly with Ansible:

```bash
run0 pacman -S --needed ansible
ansible-galaxy collection install -r requirements.yml
./run-empowered.sh ansible-playbook site.yml
```

Run a single automation with `just <name>` (see the Justfile) or
`./run-empowered.sh ansible-playbook site.yml --tags <tag>`.

The playbooks are idempotent — rerunning is safe.

**KeePassXC, Bitwarden, Proton Pass, Homebrew, the typesetting toolchain, the
BGRT boot theme, AppArmor, Secure Boot, the Yubikey GPG key, and the Yubikey
SSH keys are separate** — not part of `just setup`:

```bash
just keepassxc     # one of three alternative password managers — pick any
just ssh-agent     # the OpenSSH agent (ssh-agent.socket + SSH_AUTH_SOCK), off by default
just bitwarden     # combination, or none; no password manager is the default
just proton-pass   # desktop client (AUR) + CLI (official installer)
just proton-pass-cli  # just the CLI, no root needed
just homebrew      # Linuxbrew; needed by the Proton Pass CLI and `brew install`
just typesetting   # TeX Live + LilyPond + Gregorio, no containers (long network install)
just bgrt-theme    # builds the BGRT-derived boot theme; needs a firmware BGRT logo
just apparmor      # AppArmor as a kernel LSM, no distro profiles; needs a reboot
just apparmor-profiles  # same + apparmor.service loading /etc/apparmor.d's profiles
just secureboot    # see docs/secureboot.md for the full walkthrough
just gpg-yubikey   # needs the Yubikey plugged in
just ssh-yubikey   # needs the Yubikey plugged in; script, prompts for the FIDO2 PIN
just ssh-yubikey-disable  # drop the GitHub SSH config (e.g. migrating to an ssh-agent)
```

## Structure

| File/Directory | Role |
|---|---|
| `bootstrap.sh` | Installs `just`, if missing |
| `run-empowered.sh` | Runs ansible-playbook under `run0 --empower`: one polkit authentication, then privileged tasks pass (see *Privilege* above) |
| `site.yml` | Index: imports each `playbooks/*.yml` with its tag |
| `playbooks/polkit.yml` | polkitd ExpirationSeconds + legacy cleanup (sudoers drop-in, OpenSSH agent no longer enabled by default) (tag `polkit`) |
| `playbooks/firefox.yml` | Firefox (Flathub) + tab apps on by default (tag `firefox`) |
| `playbooks/brave.yml` | Brave (Flathub), replacing AUR `brave-origin-bin`, + the PWA `.desktop` fixup (tags `brave`, `brave-pwa-desktop-fix`) |
| `playbooks/default-browser.yml` | Pins the Flathub Brave as the default browser (when it isn't already) via a `brave-browser.desktop` shim so Omarchy web apps work + `omarchy-setup-default-browser`/`omarchy-setup-launch-browser` wrappers and keybind fix for Firefox/Brave (tag `default-browser`) |
| `playbooks/libreoffice.yml` | LibreOffice (Flathub), replacing native `libreoffice-fresh`, + launcher/keybind re-curation (tag `libreoffice`) |
| `playbooks/zed.yml` | Zed editor + Omarchy theme + font size (tag `zed`) |
| `playbooks/flathub-apps.yml` | Native Kdenlive/OBS Studio/Pinta/Xournal++ -> their Flathub builds, native packages removed (tag `flathub-apps`) |
| `playbooks/gregorio-lsp.yml` | gregorio-lsp, grelint, grefmt, built from source (tag `gregorio-lsp`) |
| `playbooks/pdf-viewer.yml` | Zathura (Flathub) as default, replacing the native `zathura` + MuPDF backend, + Papers optional, Evince kept for sushi (tag `pdf-viewer`) |
| `playbooks/pinentry.yml` | pinentry-omarchy package, shell plugin, gpg-agent `pinentry-program` (tag `pinentry`) |
| `playbooks/ssh-askpass.yml` | ssh-askpass-omarchy binary, shell plugin, `SSH_ASKPASS` environment (tag `ssh-askpass`) |
| `playbooks/polkit-agent.yml` | polkit-omarchy shell plugin replacing `omarchy.polkit` (tag `polkit-agent`) |
| `playbooks/plugins.yml` | This desktop's third-party shell plugin list (`omarchy_plugins`): `omarchy plugin add`, pinned to each entry's ref, enabled and placed in the bar section the entry asks for (tag `plugins`) |
| `playbooks/openssh-askpass.yml` | openssh rebuilt with the askpass notification patch (tag `openssh-askpass`) |
| `playbooks/lazyvim.yml` | LazyVim LaTeX extra + gregorio.nvim (tag `lazyvim`) |
| `playbooks/ptbr.yml` | pt-BR localization (tag `ptbr`) |
| `playbooks/keepassxc.yml` | KeePassXC from Flathub (native package removed) + XDG autostart + browser native messaging manifests (for the Firefox Flatpak, a manifest plus a small Python relay inside its data dir, `~/.var/app/org.mozilla.firefox/.mozilla/native-messaging-hosts/`, and an override giving Firefox only KeePassXC's socket dir — no `org.freedesktop.Flatpak` access), with its SSH agent integration off by default (`keepassxc_ssh_agent_enabled`, opt-in with `just ssh-agent`, which also enables the OpenSSH agent play — tag `ssh-agent`) — optional password manager, outside `site.yml` (tag `keepassxc`) |
| `playbooks/bitwarden.yml` | Bitwarden (Flatpak, `com.bitwarden.desktop`), its SSH agent wired to `SSH_AUTH_SOCK`, and the polkit action biometric unlock needs — optional password manager, outside `site.yml` (tag `bitwarden`) |
| `playbooks/proton-pass.yml` | Proton Pass desktop (Flatpak, `me.proton.Pass`) + CLI (Homebrew, `proton-pass-cli`), with the CLI's own SSH agent (`pass-cli ssh-agent`) wired to `SSH_AUTH_SOCK` via a systemd --user service — optional password manager, outside `site.yml` (tags `proton-pass-desktop`, `proton-pass-cli`; umbrella `proton-pass`) |
| `playbooks/containers.yml` | Podman rootless, Distrobox, starship prompt inside distrobox (tags `podman`, `distrobox`, `starship-distrobox`; umbrella `containers`) |
| `playbooks/flatpak.yml` | Flatpak + Flathub remote (tag `flatpak`) |
| `playbooks/homebrew.yml` | Homebrew for Linux in `/home/linuxbrew/.linuxbrew`, `brew` launcher in `/usr/local/bin`, `bin`/`sbin` on the session `PATH` — outside `site.yml` (`just homebrew`) |
| `playbooks/snap.yml` | snapd from the AUR (`/snap` link + session env) and Visual Studio Code's official snap + keyring/UI-scale fixes (tags `snapd`, `vscode`; umbrella `snap`) |
| `playbooks/libfprint.yml` | libfprint goodix538d (tag `libfprint`) |
| `playbooks/printer.yml` | EPSON L4160 printer (tag `printer`) |
| `playbooks/desktop.yml` | Scrolling-layout column resize, screen scale (100%) + text size, night light synced to sunrise/sunset (tags `hypr-scrolling-resize`, `text-size`, `nightlight-solar`; umbrella `desktop`) |
| `playbooks/capslock.yml` | Caps Lock via keyd (tag `capslock`) |
| `playbooks/omadwaita-themes.yml` | Omadwaita / Omadwaita Light / Omadwaita Dark Omarchy themes (tag `omadwaita-themes`) |
| `playbooks/limine-silent-boot.yml` | Limine silent boot — quiet (header-only) + `timeout: 1`, re-enrolls config checksum (tag `limine-silent-boot`) |
| `playbooks/blesh.yml` | ble.sh in Bash: autosuggestions + syntax highlighting, wired into `~/.bashrc` / `~/.blerc` (tag `blesh`) |
| `local-typesetting/` | TeX Live + LilyPond (`/opt`) + Gregorio, built directly on the host (no containers, no Ansible) — `just typesetting` |
| `playbooks/apparmor.yml` | AppArmor kernel LSM (+ optional distro profiles) — outside `site.yml` (`just apparmor` / `just apparmor-profiles`) |
| `playbooks/bgrt-theme.yml` | BGRT-derived boot theme — outside `site.yml` (tag `bgrt-theme`) |
| `playbooks/secureboot.yml` | Secure Boot — outside `site.yml` (tag `secureboot`) |
| `docs/secureboot.md` | `just secureboot` walkthrough |
| `docs/flathub-migration-survey.md` | Survey of the native GUI apps that Flathub could replace, which ones are load-bearing for Omarchy's shell, and the redundancies to cut first. The five safe cases are implemented (four in `playbooks/flathub-apps.yml`, Zathura in `playbooks/pdf-viewer.yml`); the rest is reference material, no playbook acts on it |
| `playbooks/yubikey.yml` | Yubikey GPG key — outside `site.yml` (tags `gpg-yubikey`, `yubikey`) |
| `scripts/ssh-yubikey.sh` | Resident SSH keys import + GitHub SSH drop-in (`just ssh-yubikey`, `just ssh-yubikey-disable`) |
| `playbooks/files/` | Static files copied as-is |
| `playbooks/templates/` | Jinja2 templates |
| `playbooks/tasks/` | Reusable tasks included via `include_tasks` |
| `group_vars/all/main.yml` | Variables for all automations |
| `requirements.yml` | Required Ansible collections |
| `Justfile` | Shortcuts (`just setup`, `just ptbr`, etc.) |
