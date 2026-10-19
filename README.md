# omarchy-setup

Ansible automation for setting up a freshly installed
[Omarchy](https://omarchy.org/) desktop.

Each automation is a play under `playbooks/`, imported by `site.yml`;
automations that depend on each other (Podman → Distrobox, the OpenSSH
agent → KeePassXC) or that share a theme
(the desktop tweaks, the Yubikey helpers) live together in one playbook
file. All of them share the same privilege escalation (run0, see
`ansible.cfg`), and each automation has its own tag: run one with
`--tags <tag>`, or skip one with `--skip-tags <tag>`. A tag that names a
play with a dependency also runs the play it depends on first (e.g.
`--tags distrobox` sets Podman up first), and files with several plays
have an umbrella tag for the whole file (`containers`, `desktop`, `nix`,
`yubikey`). Exceptions:
`playbooks/secureboot.yml`, `playbooks/bgrt-theme.yml`,
`playbooks/keepassxc.yml`, `playbooks/proton-pass.yml`,
`playbooks/homebrew.yml`, `playbooks/yubikey.yml` are **not** imported by
`site.yml` — Secure Boot and the BGRT boot theme touch firmware/boot,
KeePassXC and Proton Pass are alternatives to Bitwarden, the default
password manager (each one takes over the `SUPER+SHIFT+SLASH` keybind when
run), Homebrew is only needed by the tools that install formulae from it, and the Yubikey helpers need the physical token plugged in — so
they only run when called explicitly. TeX Live, LilyPond and Gregorio are a
separate tool entirely (`local-typesetting/`, `just typesetting`) — a
standalone shell script, not an Ansible playbook (see below).

## What it sets up

| Automation | Tag | What it does |
|---|---|---|
| Brave Origin | `brave` | Installs Brave Origin (Brave without Rewards, Wallet, VPN, Leo and News) with Omarchy's own installer, `omarchy-install-browser brave-origin` — the same as Install > Browser > Brave Origin in the Omarchy menu: the AUR `brave-origin-bin` package, Omarchy's Chromium flags (`~/.config/brave-origin-flags.conf`), its managed browser policy and the theme color sync. Only runs when the package is missing. Omarchy's own web app launchers run on it (see `default-browser`); the ones listed in `brave_omarchy_webapp_containers` are additionally wired to open inside a Brave container (see `brave-webapp-containers`). |
| Brave web app containers | `brave-webapp-containers` | Appends `--container=<name>` to the `Exec=` of Omarchy's own web app launchers (`~/.local/share/applications/*.desktop` running `omarchy-launch-webapp`) that are listed in `brave_omarchy_webapp_containers` (`group_vars/all/main.yml`), so they open inside that existing Brave container (`brave://settings/containers`) instead of the profile's default partition. Brave has accepted `--container=` together with `--app=` since 1.95.x (`brave/brave-browser#58019`, via `brave-core#38964`). Idempotent: drops a stale `--container=<other>` first, so re-mapping moves; only touches the user's copies in `~/.local/share/applications`, backing up before editing. Installs a systemd `--user` path unit that reruns it whenever a web app launcher is installed or rewritten (e.g. by `omarchy-webapp-install`). Runs as part of `brave`; also has its own tag. No root needed. — see `playbooks/templates/fix-brave-omarchy-webapp-containers.sh.j2` |
| Default browser | `default-browser` | Makes Brave Origin the default browser with `omarchy-default-browser brave-origin` (Setup > Defaults > Browser), only when `omarchy-default-browser` doesn't already report it, so a browser picked later in the menu isn't re-pinned (`default_browser` in `group_vars/all/main.yml`). The result is read back rather than taken from the exit code, since the script's closing notification fails outside the graphical session. `brave-origin.desktop` is an id `omarchy-launch-webapp` accepts, so the browser keybinds and every Omarchy web app open in it with no wrapper. No root needed. |
| Bitwarden | `bitwarden` | The default password manager. Installs Bitwarden's own release builds from the AUR (`omarchy-pkg-aur-add bitwarden-bin bitwarden-cli-bin`, kept current by `omarchy-update`) instead of the extra packages the Omarchy menu uses (Install > Service > Bitwarden: `bitwarden bitwarden-cli`), which lag months behind upstream, removing those if present; then rebinds Omarchy's "Passwords" key, `SUPER+SHIFT+SLASH` (1Password upstream), to Bitwarden, focusing the running window instead of opening another. Starts it with the session through `o.launch_on_start("bitwarden")` in `~/.config/hypr/autostart.lua` (Bitwarden's own "start at login" option is a no-op on Linux). Points `SSH_AUTH_SOCK` at Bitwarden's SSH agent, `~/.bitwarden-ssh-agent.sock`: statically in `~/.config/environment.d/20-bitwarden-ssh-agent.conf` and through a systemd `--user` path unit that exports it to the session once Bitwarden creates the socket (after unlock), with `gcr-ssh-agent` masked so it doesn't compete; log in again to pick up the static part. Also installs the polkit action biometric unlock needs (neither package ships it). |
| ONLYOFFICE Desktop Editors | `onlyoffice` | Installs ONLYOFFICE Desktop Editors from the AUR (`onlyoffice-bin`) with Omarchy's `omarchy-pkg-aur-add` and removes Omarchy's pre-installed native `libreoffice-fresh`. ONLYOFFICE ships as a single desktop application, so there are no secondary components to hide from the app launcher, and Omarchy binds no key to LibreOffice. |
| Emacs + AUCTeX | `emacs` | Installs Emacs the Omarchy way (`omarchy-pkg-aur-add omarchy-emacs` + `omarchy-install-emacs`: emacs-wayland, theme/font sync, `emacs.service`) and the packages in `emacs_packages` — AUCTeX and yasnippet (GNU ELPA) and lsp-mode (MELPA) — with package.el in batch mode (only the missing ones), plus a managed `omarchy-setup.el` loaded from `init.el` (your own init is never overwritten) that configures the GNU/NonGNU/MELPA archives, AUCTeX/RefTeX defaults (compiling with latexmk: a `latexmkrc` wins, LuaTeX is the fallback), `yas-global-mode` and lsp-mode's `C-c l` prefix (lsp-mode is not started automatically; Eglot stays the default client) and the `classic` theme from emacs-jp/replace-colorthemes (AntiqueWhite on darkslategrey) as Emacs' theme in place of Omarchy's color theme (font syncing is kept). |
| Zed editor | `zed` | Installs Zed + omazed (Omarchy theme integration), sets every font size (UI, buffer, agent, terminal) to 25px and the buffer font to JetBrainsMono Nerd Font, and sets `use_podman` so Dev Containers use Podman instead of Docker. |
| gregorio-lsp | `gregorio-lsp` | Installs Rust (`omarchy install dev-env rust`) if needed, then builds and installs the `gregorio-lsp`, `grelint` and `grefmt` binaries from source. |
| PDF viewer | `pdf-viewer` | Installs Zathura from the Arch packages (`zathura` + `zathura-pdf-mupdf`) as the default PDF viewer (`application/pdf` in `~/.config/mimeapps.list`, asserted against the package's `org.pwmt.zathura.desktop`), and Papers as an extra, non-default viewer. The statusbar font goes in `~/.config/zathura/zathurarc`. Evince stays installed since Nautilus's sushi previewer depends on it. |
| File manager | `file-manager` | Installs [Flea](https://github.com/thisisgm/flea) (fast, keyboard-first file manager for Omarchy) from the Omarchy repo and sets it as the default handler for directories (`inode/directory` in the user `~/.config/mimeapps.list`). Nautilus stays installed (the file chooser portal and sushi use it). |
| pinentry-omarchy | `pinentry` | Builds and installs [pinentry-omarchy](https://github.com/lbssousa/pinentry-omarchy) (Rust pinentry + omarchy-shell plugin) from its own PKGBUILD, installing Rust first if needed. It builds the release tag in `pinentry_omarchy_ref` only after verifying the tag's GPG signature against the Yubikey's key (`pinentry_omarchy_signing_keys`). Links and enables the `lbssousa.pinentry` shell plugin and sets `pinentry-program` in `~/.gnupg/gpg-agent.conf`, so GnuPG PIN and passphrase prompts (e.g. the Yubikey card PIN) use the same overlay dialog as the polkit agent. Without a Wayland session it falls back to pinentry-gnome3/curses. Must run inside the graphical session (enabling the plugin goes through the shell's IPC). |
| ssh-askpass-omarchy | `ssh-askpass` | Builds [ssh-askpass-omarchy](https://github.com/lbssousa/ssh-askpass-omarchy) (Rust askpass + omarchy-shell plugin) from the release tag in `ssh_askpass_ref`, checked out in `~/src/ssh-askpass-omarchy` only after verifying the tag's GPG signature against the Yubikey's key (`ssh_askpass_signing_keys`; **needs `just gpg-yubikey` first**), installing Rust first if needed. Installs the binary to `/usr/bin` and the plugin to `/usr/share`, links and enables `lbssousa.ssh_askpass`, and sets `SSH_ASKPASS` and `SSH_ASKPASS_REQUIRE=prefer` in `~/.config/environment.d/90-ssh-askpass.conf` (log in again to pick it up). SSH passphrases and FIDO PINs, `ssh-add -c` confirmations (Deny/Allow) and security key touch requests use the same overlay as the polkit agent. Must run inside the graphical session. |
| polkit-omarchy | `polkit-agent` | Installs [polkit-omarchy](https://github.com/lbssousa/polkit-omarchy) (a copy of Omarchy's polkit agent with pam_u2f support), from the release tag in `polkit_agent_ref`, checked out in `~/src/polkit-omarchy` only after verifying the tag's GPG signature against the Yubikey's key (`polkit_agent_signing_keys`; **needs `just gpg-yubikey` first**), to `/usr/share/polkit-omarchy/plugin` and enables the `lbssousa.polkit` shell plugin, which replaces `omarchy.polkit` (manifest `clonedFrom`). While pam_u2f waits for the security key, the dialog shows a "Touch your security key" prompt instead of a password field whose Enter does nothing. Must run inside the graphical session. |
| Shell plugins | `plugins` | Installs this desktop's list of third-party shell plugins — `omarchy_plugins` in `group_vars/all/main.yml`, **Radio Atlas** first (world radio on a rotatable globe in the bar, playing through Omarchy's `mpv`/`mpv-mpris`, so `omarchy.media` keeps the usual transport controls). Each entry is cloned by `omarchy plugin add` (the only supported installer: it validates the manifest, refuses an id another plugin already claims, and never runs plugin code, hooks or sudo), pinned to its `ref` (plugins are arbitrary unsandboxed QML inside the long-lived `omarchy-shell`, so the pin is the record of what was reviewed — `omarchy plugin update` fast-forwards a pinned clone off its tag, so bump `ref` instead), enabled, and **moved to the bar `section` the entry asks for**: Radio Atlas's icon lands in the right-hand group, right after the tray, rather than in the `left` its manifest's `defaultSection` asks for (`--enable` skips that prompt under `--yes`, so the play places the icon itself). Idempotent — re-running also pulls an icon you moved by hand back to where the list says — and the last tasks fail unless every entry really is enabled and in its section. Runtime dependencies are installed only when `pacman -T` reports one missing (all of them ship with Omarchy). Must run inside the graphical session. |
| openssh askpass notify | `openssh-askpass` | Rebuilds the installed openssh from Arch's packaging with `playbooks/files/openssh/askpass-notify.patch` (pkgrel `.1`), which makes OpenSSH honour `SSH_ASKPASS_REQUIRE` for notifications too, so a security key's "Confirm user presence" request reaches ssh-askpass-omarchy instead of the terminal. Official openssh updates replace it with the unpatched package; run it again after them. |
| GTK4 file dialogs | `file-chooser` | Makes the open/save file dialogs of non-GNOME apps (Firefox, Chromium, Electron, GTK and Qt apps) the GTK4 ones. Installs `xdg-desktop-portal-gnome` (its FileChooser is Nautilus's) and routes the FileChooser portal to it for Hyprland (`~/.config/xdg-desktop-portal/hyprland-portals.conf`), clears the session's forced `GDK_BACKEND` for that one service (otherwise it starts in a settings-only mode and shows no dialogs), and exports `GTK_USE_PORTAL=1` from `~/.config/hypr/hyprland.lua`. Qt apps (Qt5 like KeePassXC, and Qt6) use `qt5ct`/`qt6ct` as their platform theme (`QT_QPA_PLATFORMTHEME=qt6ct`) instead of Omarchy's `gtk3`, which draws GTK3 dialogs in-process: their `standard_dialogs=xdgdesktopportal` option asks the portal, and they also set the Qt UI font to GTK's family at `omarchy_system_ui_font_pt` (Qt's plain `xdgdesktopportal` theme would give portal dialogs but a 9pt fallback font). Log out and back in (or restart the app) to pick it up. |
| LazyVim plugins | `lazyvim` | Enables LazyVim's LaTeX extra and installs [gregorio.nvim](https://github.com/AISCGre-BR/gregorio.nvim) (GABC/NABC chant notation, pairs with gregorio-lsp). |
| pt-BR localization | `ptbr` | Locale, personal folder names, Chromium-family (Brave Origin included)/man pages/OCR language. |
| Podman | `podman` | Rootless container engine. Part of `playbooks/containers.yml` with Distrobox and the starship integration (umbrella tag `containers`). |
| Distrobox | `distrobox` | Depends on Podman: the tag also runs the Podman play first. |
| Nix | `nix` | Installs Nix from the Arch package (`nix`) in multi-user mode and enables `nix-daemon.socket`. When `/` is btrfs, first creates a top-level `@nix` subvolume and mounts it at `/nix` from `/etc/fstab` (same options as `/`), so snapper's root snapshots don't pin store paths or roll the store back; stops if `/nix` already holds a store outside a subvolume. Enables flakes and the `nix` command in `/etc/nix/nix.conf` and resolves `nixpkgs` through the flake registry (`nix-path`), so `nix-shell -p` works without channels. Appends `~/.nix-profile/bin` and the default profile to the session `PATH` (never shadowing Arch binaries) and their `share` dirs to `XDG_DATA_DIRS` via `environment.d` (log in again to pick it up). |
| direnv | `direnv` (also `nix`) | Installs direnv (Arch package) and hooks it into bash (a block in `~/.bashrc`, before ble.sh's `ble-attach`) and fish (`~/.local/share/fish/vendor_conf.d/direnv.fish`, leaving `~/.config/fish` alone), so a project's `.envrc` — e.g. `use flake` for its Nix dev shell — loads on `cd` once `direnv allow`ed. |
| nix-direnv | `nix-direnv` (also `nix`) | Installs [nix-direnv](https://github.com/nix-community/nix-direnv) into the user's Nix profile (not packaged by Arch or the AUR) and sources it from `~/.config/direnv/direnvrc`, so `use flake` / `use nix` cache the dev shell and keep it from being garbage-collected. Update with `nix profile upgrade nix-direnv`. |
| libfprint (goodix538d) | `libfprint` | Builds a fingerprint driver fork (lbssousa/libfprint) as a PKGBUILD package with makepkg and installs it in place of the official `libfprint` / `libfprint-git` (the package is itself named `libfprint-git` with epoch 2, so fprintd keeps working, `pacman -Syu` won't swap it back and `omarchy-setup-security-fingerprint` finds it installed), plus a watchdog for a driver desync bug and the Omarchy lock-screen retry-storm bug. |
| EPSON L4160 printer | `printer` | Driverless CUPS queue (IPP Everywhere). |
| Hyprland scrolling resize | `hypr-scrolling-resize` | SUPER+[ / SUPER+] resize the focused column. This and the next two are plays of `playbooks/desktop.yml` (umbrella tag `desktop`). |
| Screen scale + text size | `text-size` | Sets the Hyprland monitor scale to 100% (and `GDK_SCALE` to match) and compensates with larger text: shell bar + terminals at 20px (15pt terminal font) and the GTK/GNOME UI fonts at GNOME's own default sizes (interface 11pt, document 12pt, monospace 11pt, window titles 11pt; family kept), with GTK's text-scaling factor left at 1.0. Qt apps (`file-chooser` play) and zathura keep `omarchy_system_ui_font_pt` (13pt). |
| Night light | `nightlight-solar` | Syncs hyprsunset to real sunrise/sunset daily. |
| Caps Lock via keyd | `capslock` | tap=Esc, hold=Ctrl, Shift+CapsLock=CapsLock; moves Compose off Caps Lock. |
| Inkscape + svg2tikz | `inkscape` | Installs Inkscape and the [svg2tikz](https://github.com/xyz2tex/svg2tikz) extension (AUR `python-svg2tikz`) for exporting SVG paths as TikZ/PGF code for LaTeX. |
| Omadwaita themes | `omadwaita-themes` | Installs three Adwaita-based Omarchy themes whose terminal palettes come from Adwaita's nine accent colors, WCAG-AA-checked on their background: **Omadwaita** (dark TUI, light GTK — a `theme-set` hook flips GTK back to light), **Omadwaita Light** and **Omadwaita Dark**. All three use the Adwaita icon theme and share one wallpaper set (devotional paintings and wallpapers, `playbooks/files/omadwaita/backgrounds/`, migrated from the former Sacred Heart theme), plus a generated fallback wallpaper (the Omarchy logo on a gradient in the theme's palette). Browsers (Chromium, Brave, Chrome, Edge) get a per-theme `chromium.theme` seed color so their accent has Adwaita blue's hue instead of an arbitrary one derived from the neutral background. Omarchy never recolors GTK (it only picks `Adwaita`/`Adwaita-dark` from the theme's `mode`), so GTK apps keep the stock Adwaita palette. Installs only; apply with `omarchy-theme-set "Omadwaita"`. |
| Omaraptor themes | `omaraptor-themes` | Installs three Omarchy themes modeled on Omadwaita but built on the classic GNOME color palette (Blue/Green/Yellow/Orange/Red/Purple + Light/Dark tiers, WCAG-AA-checked on their background; cyan, absent from the palette, is a Blue/Green midpoint) and Project Bluefin's default wallpapers (`01-bluefin`…`12-bluefin`, Apache-2.0, converted to 2560×1440 JPEG, `playbooks/files/omaraptor/backgrounds/`): **Omaraptor** (dark TUI, light GTK via a `theme-set` hook; day + night wallpapers), all three with Bluefin's slate (gray) GTK4/libadwaita accent set by the same hook and a matching slate Hyprland active-window border and polkit/askpass/pinentry dialog accent (`shell.polkit.toml` section override) (gsettings plus a `~/.config/gtk-4.0/gtk.css` override, because the GTK portal backend does not expose `accent-color` to libadwaita), **Omaraptor Light** (day) and **Omaraptor Dark** (night). Same Adwaita icon theme and browser seed colors as Omadwaita. The default wallpaper of each theme sorts first (`00-bluefin-day.jpg`, Bluefin's 08, for Omaraptor and Omaraptor Light; `00-bluefin-night.jpg` for Omaraptor Dark). Installs only; apply with `omarchy-theme-set "Omaraptor"`. |
| Omaraptor day/night | `omaraptor-theme-auto` | A `systemd --user` timer (`omaraptor-theme-auto.timer`, every 5 min) switches from `omaraptor_auto_day_theme` (Omaraptor) to `omaraptor_auto_night_theme` (Omaraptor Dark) at sunset and back at sunrise, then sets the theme's default wallpaper. Sunrise/sunset come from `hyprsunset.conf` (the `nightlight-solar` play), with fallback times. A theme picked by hand is kept until the next sunrise/sunset; other themes are left alone. |
| Limine silent boot | `limine-silent-boot` | Sets `quiet: yes` (in the config header, before the first entry — otherwise Limine ignores it) and `timeout: 1` in `/boot/limine.conf` for a flicker-free boot: with `quiet` in effect Limine draws nothing and keeps the firmware BGRT logo on screen through its 1-second key window (press ↑/↓ to reveal the menu — not Space/Enter, which Limine treats as "boot the selected entry"; snapshots/fallback stay reachable). Re-runs `limine-update` to re-enroll the config checksum, so it also works with Secure Boot's `ENABLE_ENROLL_LIMINE_CONFIG=yes`. |
| ble.sh | `blesh` | Loads [ble.sh](https://github.com/akinomyoga/ble.sh) by default in Bash — Omarchy doesn't — with fish-style **autosuggestions** (ghost text from history, then completion) and **syntax highlighting** as you type. Builds AUR `blesh-git` (0.4.0-devel: the stable 0.3.4 predates Bash 5.3 and warns on every shell start against Omarchy's inputrc). Wraps the `source "$OMARCHY_PATH/default/bash/rc"` line in `~/.bashrc` with `source ble.sh --noattach` before it and `ble-attach` at the end, so starship and fzf's key bindings (Ctrl-R etc.) keep working; the feature options live in `~/.blerc`. Open a new terminal to pick it up. |
| rclone Google Drive | `rclone-gdrive` | Writes the config to mount Google Drive with rclone, same layout as nix-config's `rclone.nix`: `~/.config/rclone/rclone.conf` (remote `Google Drive`, `0600`), a `rclone-google-drive@.service` systemd `--user` template plus one env file per mount, and the mounts `~/Público/Google Drive/<email>/Meu Drive` and `…/Compartilhados Comigo` (base in `rclone_gdrive_base_dir`, instances in `rclone_gdrive_instances`; the unit creates `~/.cache/rclone` for the log file). The Google API OAuth `client_id`/`client_secret` are supplied by you on the first run — `RCLONE_GDRIVE_CLIENT_ID=… RCLONE_GDRIVE_CLIENT_SECRET=… just rclone-gdrive` (or `-e rclone_gdrive_client_id=…`) — and reused from `rclone.conf` afterwards. The OAuth token rclone stores is preserved across runs; the one manual step is `rclone config reconnect "Google Drive:"`, after which re-running starts the mounts. Installs `rclone` and `fuse3` via pacman. Not part of `just setup` (tag `never`): `just rclone-gdrive`. |
| Starship in distrobox | `starship-distrobox` | Makes the prompt work inside distrobox containers and show which one you're in (`⬢ <container> <dir> <branch> ❯`). Omarchy's `~/.bashrc` sources `$OMARCHY_PATH/default/bash/rc`, which doesn't exist in the container (its `/usr` is the image's; the host's is at `/run/host`), so starship never started: a `~/.bashrc` block points `OMARCHY_PATH` at `/run/host` inside distrobox and falls back to the host's starship binary (same Arch userland; another distro may need its own). The name comes from `CONTAINER_ID`, exported by `distrobox-enter`, through starship's `env_var` module in `~/.config/starship.toml` (blank on the host). |
| Homebrew | — | Installs Homebrew for Linux to `/home/linuxbrew/.linuxbrew` and installs a `brew` launcher in `/usr/local/bin`, then puts `bin`/`sbin` on the session `PATH` via `environment.d` (log out and back in to pick it up). Not part of `just setup` — run explicitly with `just homebrew`; only the tooling that installs formulae from it (e.g. the Proton Pass CLI) needs it. |
| TeX Live + LilyPond + Gregorio | — | Not an Ansible playbook: `local-typesetting/install-typesetting.sh` (`just typesetting`) installs TeX Live and LilyPond under `/opt`, builds Gregorio from source, and registers TeX Live's fonts with fontconfig, directly on the host with `sudo` — no containers. Not part of `just setup` — a long network install, run explicitly. See [`local-typesetting/README.md`](local-typesetting/README.md). |
| BGRT boot theme | `bgrt-theme` | Builds an Omarchy theme + a standalone Plymouth theme from this machine's own UEFI BGRT boot logo, so the same picture stays on screen from firmware through Plymouth to Hyprlock. Not part of `just setup` — rewrites the default Plymouth theme and rebuilds the initramfs. |
| Secure Boot | `secureboot` | Limine + sbctl. Not part of `just setup` — see [`docs/secureboot.md`](docs/secureboot.md). |
| Yubikey GPG key | `gpg-yubikey` | Imports the public key, trusts it, configures git signing. Not part of `just setup`. **A dependency of `pinentry`, `ssh-askpass` and `polkit-agent`**: they deploy signed release tags and stop at the start if this key isn't in the keyring, so run it first. Lives in `playbooks/yubikey.yml` (umbrella tag `yubikey`). |
| Yubikey SSH keys | `ssh-yubikey` | Not Ansible — `scripts/ssh-yubikey.sh` (the FIDO2 PIN prompt needs a real terminal). Downloads the resident FIDO2 keys with `ssh-keygen -K` into `~/.ssh` (never overwriting) and writes one self-contained drop-in per key, `~/.ssh/config.d/<host>_<user>.conf` (here `github_com_lbssousa.conf`): `github.com` authenticates with `id_ed25519_sk_rk_github.com_lbssousa` (override with `GITHUB_KEY=`) with `IdentityAgent none`, plus `ControlMaster auto` + `ControlPersist 10m`, so the PIN/touch is asked once per 10 minutes. Adds one `Include config.d/*.conf` line to `~/.ssh/config`. **To migrate to an ssh-agent: `just ssh-yubikey-disable`** (renames the drop-in to `*.conf.disabled`, which the `Include` glob ignores). Also `scripts/ssh-yubikey.sh status`/`enable`. Not part of `just setup`. |

See each playbook's own header comment for implementation details.

## Prerequisites

- An Omarchy desktop (or any Arch Linux with pacman, `locale-gen`,
  systemd and `xdg-user-dirs`).
- `run0` (part of systemd, so already there on Arch) and a user in the
  `wheel` group.
- The libfprint playbook builds with `makepkg` on the host (no container);
  it replaces the official `libfprint`/`libfprint-git` via `pacman -U`.
- The Proton Pass playbook needs Homebrew (`just homebrew` — not part of
  `just setup`) for its CLI.
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

**KeePassXC, Proton Pass, Homebrew, the typesetting toolchain, the
BGRT boot theme, Secure Boot, the Yubikey GPG key, and the Yubikey
SSH keys are separate** — not part of `just setup`:

```bash
just keepassxc     # alternative password manager to Bitwarden (the default)
just ssh-agent     # the OpenSSH agent (ssh-agent.socket + SSH_AUTH_SOCK), off by default
just proton-pass   # alternative password manager: desktop client (AUR) + CLI (Homebrew)
just proton-pass-cli  # just the CLI, no root needed
just homebrew      # Linuxbrew; needed by the Proton Pass CLI and `brew install`
just typesetting   # TeX Live + LilyPond + Gregorio, no containers (long network install)
just bgrt-theme    # builds the BGRT-derived boot theme; needs a firmware BGRT logo
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
| `playbooks/polkit.yml` | polkitd ExpirationSeconds (tag `polkit`) |
| `playbooks/pam-auth-order.yml` | Pins the order of the sudo and polkit PAM stacks: fingerprint (`pam_fprintd`), then FIDO2/U2F key (`pam_u2f`), then password. Omarchy's fingerprint and FIDO2 setup scripts each insert at the top of the file, so the order otherwise depends on which ran last; this adds `pam_fprintd` (behind Omarchy's clamshell gate) at the top when it is missing, moves the `pam_u2f` line below it, and writes `/etc/pam.d/omarchy-lock-fingerprint` (the lock screen only offers the fingerprint when it exists) once a print is enrolled, and sets `pam_fprintd` to `max-tries=3 timeout=10` (default 3 tries / 30 s): three fingerprint attempts, but the key is asked for quickly when no finger is placed (`pam_auth_order_fprintd_*` vars) (tag `pam-auth-order`) |
| `playbooks/brave.yml` | Brave Origin (`omarchy-install-browser brave-origin`) + the Omarchy web app container wiring (tags `brave`, `brave-webapp-containers`) |
| `playbooks/default-browser.yml` | Brave Origin as the default browser via `omarchy-default-browser` (when it isn't already) (tag `default-browser`) |
| `playbooks/onlyoffice.yml` | ONLYOFFICE Desktop Editors (AUR `onlyoffice-bin`), replacing native `libreoffice-fresh` (tag `onlyoffice`) |
| `playbooks/emacs.yml` | Emacs (omarchy-emacs) + AUCTeX, yasnippet, lsp-mode + classic theme (tag `emacs`) |
| `playbooks/zed.yml` | Zed editor + Omarchy theme + font size (tag `zed`) |
| `playbooks/gregorio-lsp.yml` | gregorio-lsp, grelint, grefmt, built from source (tag `gregorio-lsp`) |
| `playbooks/pdf-viewer.yml` | Zathura (`zathura` + MuPDF backend) as default + Papers optional, Evince kept for sushi (tag `pdf-viewer`) |
| `playbooks/file-manager.yml` | Flea file manager as the default for directories (tag `file-manager`) |
| `playbooks/plugins.yml` | This desktop's third-party shell plugin list (`omarchy_plugins`): `omarchy plugin add`, pinned to each entry's ref, enabled and placed in the bar section the entry asks for (tag `plugins`); plus the plugins that ship their own binary, each deployed from a GPG-signed release tag, as separate plays of the same file: pinentry-omarchy package + gpg-agent `pinentry-program` (tag `pinentry`), ssh-askpass-omarchy binary + `SSH_ASKPASS` environment (tag `ssh-askpass`), polkit-omarchy replacing `omarchy.polkit` (tag `polkit-agent`) |
| `playbooks/openssh-askpass.yml` | openssh rebuilt with the askpass notification patch (tag `openssh-askpass`) |
| `playbooks/lazyvim.yml` | LazyVim LaTeX extra + gregorio.nvim (tag `lazyvim`) |
| `playbooks/ptbr.yml` | pt-BR localization (tag `ptbr`) |
| `playbooks/keepassxc.yml` | KeePassXC (`omarchy-pkg-add keepassxc`) + XDG autostart + browser native messaging manifests for Chromium and Brave Origin, with its SSH agent integration off by default (`keepassxc_ssh_agent_enabled`, opt-in with `just ssh-agent`, which also enables the OpenSSH agent play — tag `ssh-agent`) — optional password manager, outside `site.yml`; takes over `SUPER+SHIFT+SLASH` (tag `keepassxc`) |
| `playbooks/bitwarden.yml` | Bitwarden (AUR `bitwarden-bin bitwarden-cli-bin`, replacing extra's outdated `bitwarden bitwarden-cli`), the default password manager: `SUPER+SHIFT+SLASH`, session autostart, its SSH agent as `SSH_AUTH_SOCK`, and the polkit action biometric unlock needs (tag `bitwarden`) |
| `playbooks/proton-pass.yml` | Proton Pass desktop (AUR `proton-pass-bin`) + CLI (Homebrew, `proton-pass-cli`), with the CLI's own SSH agent (`pass-cli ssh-agent`) wired to `SSH_AUTH_SOCK` via a systemd --user service — optional password manager, outside `site.yml`; takes over `SUPER+SHIFT+SLASH` (tags `proton-pass-desktop`, `proton-pass-cli`; umbrella `proton-pass`) |
| `playbooks/containers.yml` | Podman rootless, Distrobox, starship prompt inside distrobox (tags `podman`, `distrobox`, `starship-distrobox`; umbrella `containers`) |
| `playbooks/homebrew.yml` | Homebrew for Linux in `/home/linuxbrew/.linuxbrew`, `brew` launcher in `/usr/local/bin`, `bin`/`sbin` on the session `PATH` — outside `site.yml` (`just homebrew`) |
| `playbooks/nix.yml` | Nix from the Arch package, store on a `@nix` btrfs subvolume, flakes, session env (tag `nix`); direnv with bash + fish hooks (tag `direnv`); nix-direnv in the Nix profile (tag `nix-direnv`) |
| `playbooks/libfprint.yml` | libfprint goodix538d (tag `libfprint`) |
| `playbooks/printer.yml` | EPSON L4160 printer (tag `printer`) |
| `playbooks/desktop.yml` | Scrolling-layout column resize, screen scale (100%) + text size, night light synced to sunrise/sunset (tags `hypr-scrolling-resize`, `text-size`, `nightlight-solar`; umbrella `desktop`) |
| `playbooks/capslock.yml` | Caps Lock via keyd (tag `capslock`) |
| `playbooks/omadwaita-themes.yml` | Omadwaita / Omadwaita Light / Omadwaita Dark Omarchy themes (tag `omadwaita-themes`) |
| `playbooks/omaraptor-themes.yml` | Omaraptor / Omaraptor Light / Omaraptor Dark Omarchy themes — GNOME palette + Bluefin wallpapers (tag `omaraptor-themes`) |
| `playbooks/omaraptor-theme-auto.yml` | Day/night switching for the Omaraptor themes: script + systemd --user service/timer (tag `omaraptor-theme-auto`) |
| `playbooks/limine-silent-boot.yml` | Limine silent boot — quiet (header-only) + `timeout: 1`, re-enrolls config checksum (tag `limine-silent-boot`) |
| `playbooks/blesh.yml` | ble.sh in Bash: autosuggestions + syntax highlighting, wired into `~/.bashrc` / `~/.blerc` (tag `blesh`) |
| `local-typesetting/` | TeX Live + LilyPond (`/opt`) + Gregorio, built directly on the host (no containers, no Ansible) — `just typesetting` |
| `playbooks/bgrt-theme.yml` | BGRT-derived boot theme — outside `site.yml` (tag `bgrt-theme`) |
| `playbooks/secureboot.yml` | Secure Boot — outside `site.yml` (tag `secureboot`) |
| `docs/secureboot.md` | `just secureboot` walkthrough |
| `docs/omarchy-4.5-migration.md` | What the next Omarchy release (Quattro RS 4.5) changes for these automations, gathered ahead of time from the upstream `quattro` branch: which playbooks become obsolete, which need fixing before running on it, and how to re-check once it is tagged |
| `playbooks/yubikey.yml` | Yubikey GPG key — outside `site.yml` (tags `gpg-yubikey`, `yubikey`) |
| `scripts/ssh-yubikey.sh` | Resident SSH keys import + GitHub SSH drop-in (`just ssh-yubikey`, `just ssh-yubikey-disable`) |
| `playbooks/files/` | Static files copied as-is |
| `playbooks/templates/` | Jinja2 templates |
| `playbooks/tasks/` | Reusable tasks included via `include_tasks` |
| `group_vars/all/main.yml` | Variables for all automations |
| `requirements.yml` | Required Ansible collections |
| `Justfile` | Shortcuts (`just setup`, `just ptbr`, etc.) |
