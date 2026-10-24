# omarchy-setup

Ansible automation for setting up a freshly installed
[Omarchy](https://omarchy.org/) desktop.

It sets the machine up for **several users**: each automation is split
into a **system phase** (packages, `/etc`, PAM, the login screen, signed
plugin builds, the accounts themselves — run once by an administrator) and
a **user phase** (each person's `~/.config`, session services and shell
plugins — run by each user, as themselves, in their own session). The
login screen lists everyone by full name, with an optional field for any
other username, and nobody is logged in automatically; the Omarchy tools
that assumed a single owner are replaced by
[omarchy-multiuser](https://github.com/lbssousa/omarchy-multiuser). See
[docs/multi-user.md](docs/multi-user.md) for the model.

Each automation is a play under `playbooks/system/` and/or
`playbooks/user/`, indexed by `system.yml` and `user.yml` (`site.yml` runs
both, for the administrator's own account); automations that depend on
each other (Podman → Distrobox, the OpenSSH agent → KeePassXC) or that
share a theme (the desktop tweaks, the Yubikey helpers) live together in
one playbook file. The system phase escalates with run0 (see
`ansible.cfg`); the user phase never becomes root. Each automation has its
own tag, the same in both phases: run one with `just <tag>` or `--tags
<tag>`, or skip one with `--skip-tags <tag>`. A tag that names a play with
a dependency also runs the play it depends on first (e.g. `--tags
distrobox` sets Podman up first), and files with several plays have an
umbrella tag for the whole file (`containers`, `desktop`, `nix`,
`yubikey`). Exceptions: `secureboot`, `tpm2`, `bgrt-theme`, `proton-pass`,
`homebrew` and `yubikey` are **not** in
`system.yml`/`user.yml` — Secure Boot, TPM2 auto-unlock and the BGRT boot theme touch
firmware/boot/crypto, Proton Pass is an alternative to KeePassXC, the default
password manager (it takes over the `SUPER+SHIFT+SLASH` keybind when run),
Homebrew is only needed by the tools that install formulae from it, and the
Yubikey helpers need the physical token plugged in — so they only run when called explicitly. TeX
Live, LilyPond and Gregorio are a separate tool entirely
(`local-typesetting/`, `just typesetting`) — a standalone shell script, not
an Ansible playbook (see below).

## What it sets up

| Automation | Tag | What it does |
|---|---|---|
| User accounts | `users` | System phase. Creates or updates every account in `omarchy_users` (`group_vars/all/users.yml`): full name in GECOS (what the login screen lists), login shell, `wheel` for administrators and `omarchy-users` for everyone else, a subuid/subgid range each. New accounts start locked; `just users` sets their passwords right after and, for `luks: true`, offers each a disk unlock password of their own. |
| omarchy-multiuser | `omarchy-multiuser` | System phase. Builds and installs [omarchy-multiuser](https://github.com/lbssousa/omarchy-multiuser) from a GPG-signed release tag: the multi-user greeter, per-user FIDO2 keys and fingerprints (the lock screen keeps fingerprint unlock while anyone has prints), migrations for users outside `wheel`, account and LUKS keyslot helpers and the menu entries for them. Enables its watchers, the migration recorder for each administrator and its per-login unit for every user. |
| SDDM | `sddm` | System phase. The login screen lists every user by full name, with an optional field to type any other username, and nobody is logged in automatically: removes Omarchy's `/etc/sddm.conf.d/autologin.conf` and checks that `zz-omarchy-multiuser.conf` wins. Never restarts sddm; it takes over at the next login screen. |
| Shared checkout | `shared-checkout` | System phase (`just publish`). Publishes the committed HEAD to `/opt/omarchy-setup` (root-owned, world-readable) with its collections, and installs `omarchy-setup-user`, which runs the user phase from there for whoever calls it. |
| git identity | `git-identity` | User phase. `git config --global user.name/user.email` from `git_user_name`/`git_user_email` in `users/<name>.yml`. |
| Flatpak + Flathub | `flatpak` | Installs Flatpak via pacman, adds the Flathub remote system-wide, installs [Bazaar](https://flathub.org/apps/io.github.kolunmi.Bazaar) (`io.github.kolunmi.Bazaar`, the Flathub app-store frontend), puts the Flatpak export dirs on `XDG_DATA_DIRS` via `~/.config/environment.d/40-flatpak.conf` so the Omarchy app launcher sees Flatpak apps, and masks Bazaar's D-Bus service activation in `~/.local/share/dbus-1/services` so launching it from the shell opens one window instead of two. |
| Firefox | `firefox` | Installs Firefox from Flathub (`org.mozilla.firefox`), removing the native `firefox` package, links `/usr/local/bin/firefox` to the Flatpak's exported launcher and installs a hidden `~/.local/share/applications/firefox.desktop` shim for Omarchy's browser scripts, migrates an existing native profile into `~/.var/app/org.mozilla.firefox` on first run, sets `MOZ_ENABLE_WAYLAND=1` in `~/.config/environment.d`, enables "tab apps" (Taskbar Tabs) by default (`browser.taskbarTabs.enabled`, via the `org.mozilla.firefox.systemconfig` extension's `defaults/pref` so it remains user-overridable in `about:config`), and raises the default page font size (`font.size.variable.x-western`) to 17px. |
| Firefox Taskbar Tabs | `firefox-taskbar-apps` | Creates the Firefox Taskbar Tabs ("tab apps") listed in `firefox_taskbar_apps` (`users/<name>.yml`) straight into the user's default Firefox Flatpak profile (`taskbartabs/taskbartabs.json`, 256×256 icons, and `org.mozilla.firefox.webapp-<uuid>.desktop` launchers in `~/.local/share/applications`, each opening in its Multi-Account Containers container), removes Omarchy's own `omarchy-launch-webapp` launchers for the same sites, opens all Taskbar Tabs in tiled fullscreen (`fullscreen_state = "0 2"`), and rebinds the webapp keys to them via `~/.local/bin/omarchy-setup-launch-firefox-taskbar-app`. Skipped with a warning when Firefox is running (it caches the registry in memory). No root needed. |
| Default browser | `default-browser` | Makes Firefox the default browser with `omarchy-default-browser firefox` (Setup > Defaults > Browser), only when `omarchy-default-browser` doesn't already report it, so a browser picked later in the menu isn't re-pinned (`default_browser` in `group_vars/all/main.yml`). The result is read back rather than taken from the exit code, since the script's closing notification fails outside the graphical session. No root needed. |
| KeePassXC | `keepassxc` | The default password manager. Installs KeePassXC from extra (`omarchy-pkg-add keepassxc`), the browser native messaging manifests for Firefox (inside `~/.var/app/org.mozilla.firefox` with a Python relay and an override for KeePassXC's browser socket dir) and Chromium (the KeePassXC-Browser extension is still installed and connected by hand), and a udev rule, `/etc/udev/rules.d/72-keepassxc-yubikey-lock.rules`, that locks every open database as soon as the YubiKey is unplugged (matched on the raw USB `PRODUCT`, `keepassxc_yubikey_usb_product_match`, since the sysfs attributes are gone on `remove`; it runs `/usr/local/bin/keepassxc-lock-on-yubikey-remove`, which calls KeePassXC's `lockAllDatabases` on the user's session D-Bus when it is running). It also deploys the XDG autostart entry and rebinds `SUPER+SHIFT+SLASH` (Omarchy's "Passwords" key) to KeePassXC. |
| Bitwarden | `bitwarden` | System phase installs Bitwarden from Flathub (`com.bitwarden.desktop`) and the polkit action (`com.bitwarden.Bitwarden.policy`) biometric unlock needs alongside KeePassXC. Running `just bitwarden` also runs `playbooks/user/bitwarden.yml` to wire `SSH_AUTH_SOCK` to Bitwarden's sandboxed SSH agent through a socket-activated proxy (`bitwarden-ssh-agent.socket` at `$XDG_RUNTIME_DIR/bitwarden-ssh-agent.sock`: the first SSH client to connect launches Bitwarden, or raises it to unlock, if its agent isn't answering), deploy its autostart entry and rebind `SUPER+SHIFT+SLASH` to Bitwarden. |
| ONLYOFFICE Desktop Editors | `onlyoffice` | Installs ONLYOFFICE Desktop Editors from Flathub (`org.onlyoffice.desktopeditors`) and removes Omarchy's pre-installed native `libreoffice-fresh` (and any `onlyoffice-bin` AUR install). ONLYOFFICE ships as a single desktop application, so there are no secondary components to hide from the app launcher, and Omarchy binds no key to LibreOffice. |
| Flathub app migrations | `flathub-apps` | Replaces Omarchy's pre-installed Kdenlive (`org.kde.kdenlive`), OBS Studio (`com.obsproject.Studio`), Pinta (`com.github.PintaProject.Pinta`) and Xournal++ (`com.github.xournalpp.xournalpp`) with their Flathub builds (`flathub_app_migrations` in `group_vars/all/main.yml`, see [`docs/flathub-migration-survey.md`](docs/flathub-migration-survey.md)). Asserts each Flatpak exports the same desktop-entry id before removing the native package. |
| Emacs + AUCTeX | `emacs` | Installs Emacs the Omarchy way (`omarchy-pkg-aur-add omarchy-emacs` + `omarchy-install-emacs`: emacs-wayland, theme/font sync, `emacs.service`) and the packages in `emacs_packages` — AUCTeX and yasnippet (GNU ELPA) and lsp-mode (MELPA) — with package.el in batch mode (only the missing ones), plus a managed `omarchy-setup.el` loaded from `init.el` (your own init is never overwritten) that configures the GNU/NonGNU/MELPA archives, AUCTeX/RefTeX defaults (compiling with latexmk: a `latexmkrc` wins, LuaTeX is the fallback), `yas-global-mode` and lsp-mode's `C-c l` prefix (lsp-mode is not started automatically; Eglot stays the default client) and the `classic` theme from emacs-jp/replace-colorthemes (AntiqueWhite on darkslategrey) as Emacs' theme in place of Omarchy's color theme (font syncing is kept). |
| Zed editor | `zed` | Installs Zed + omazed (Omarchy theme integration), sets every font size (UI, buffer, agent, terminal) to 25px and the buffer font to JetBrainsMono Nerd Font, and sets `use_podman` so Dev Containers use Podman instead of Docker. |
| gregorio-lsp | `gregorio-lsp` | Installs Rust (`omarchy install dev-env rust`) if needed, then builds and installs the `gregorio-lsp`, `grelint` and `grefmt` binaries from source. |
| PDF viewer | `pdf-viewer` | Installs Zathura (`org.pwmt.zathura`) from Flathub, removing the native `zathura`, `zathura-pdf-mupdf` and `evince` packages. Makes Zathura the default PDF viewer (`application/pdf` in `~/.config/mimeapps.list`), grants it `~/Projetos` (`pdf_viewer_zathura_extra_paths`) so inotify auto-reload works on typeset PDFs, shadows its exported desktop entry in `~/.local/share/applications/org.pwmt.zathura.desktop` with `@@ %F @@` so relative paths from `xdg-open` work, and sets its statusbar font in `~/.var/app/org.pwmt.zathura/config/zathura/zathurarc`. Papers stays installed (native) as a non-default viewer, since Nautilus's sushi previewer depends on it; a Flathub `org.gnome.Papers` from an earlier run is removed. |
| File manager | `file-manager` | Installs [Flea](https://github.com/thisisgm/flea) (fast, keyboard-first file manager for Omarchy) from the Omarchy repo and makes it the default with its own `flea --default` (undo with `flea --default off`): the handler for directories (`inode/directory` in the user `~/.config/mimeapps.list`), `org.freedesktop.FileManager1` (a user D-Bus service, so "Show in folder" from browsers and other apps opens Flea), Omarchy's "File manager" keys `SUPER+SHIFT+F` and `SUPER+ALT+SHIFT+F` (cwd) (a block in `~/.config/hypr/bindings.lua`), and the file picker for open/save dialogs (see `file-chooser`). Change is read from Flea's own "already …" report, and the result is checked with `xdg-mime`. Nautilus stays installed (sushi uses it). |
| omapin | `pinentry` | Builds and installs [omapin](https://github.com/lbssousa/omapin) (Rust pinentry + omarchy-shell plugin) from its own PKGBUILD, installing Rust first if needed. It builds the release tag in `omapin_ref` only after verifying the tag's GPG signature against the Yubikey's key (`omapin_signing_keys`). Links and enables the `lbssousa.omapin` shell plugin and sets `pinentry-program` in `~/.gnupg/gpg-agent.conf`, so GnuPG PIN and passphrase prompts (e.g. the Yubikey card PIN) use the same overlay dialog as the polkit agent. Without a Wayland session it falls back to pinentry-gnome3/curses. Migrates an install from before the rename (pinentry-omarchy ≤ 0.2.1): removes the old package, disables the `lbssousa.pinentry` plugin and removes its link. Must run inside the graphical session (enabling the plugin goes through the shell's IPC). |
| ssh-askpass-omarchy | `ssh-askpass` | Builds [ssh-askpass-omarchy](https://github.com/lbssousa/ssh-askpass-omarchy) (Rust askpass + omarchy-shell plugin) from the release tag in `ssh_askpass_ref`, checked out in `~/src/ssh-askpass-omarchy` only after verifying the tag's GPG signature against the Yubikey's key (`ssh_askpass_signing_keys`; **needs `just gpg-yubikey` first**), installing Rust first if needed. Installs the binary to `/usr/bin` and the plugin to `/usr/share`, links and enables `lbssousa.ssh_askpass`, and sets `SSH_ASKPASS` and `SSH_ASKPASS_REQUIRE=prefer` in `~/.config/environment.d/90-ssh-askpass.conf` (log in again to pick it up). SSH passphrases and FIDO PINs, `ssh-add -c` confirmations (Deny/Allow) and security key touch requests use the same overlay as the polkit agent. Must run inside the graphical session. |
| polkit-omarchy | `polkit-agent` | Installs [polkit-omarchy](https://github.com/lbssousa/polkit-omarchy) (a copy of Omarchy's polkit agent with pam_u2f support), from the release tag in `polkit_agent_ref`, checked out in `~/src/polkit-omarchy` only after verifying the tag's GPG signature against the Yubikey's key (`polkit_agent_signing_keys`; **needs `just gpg-yubikey` first**), to `/usr/share/polkit-omarchy/plugin` and enables the `lbssousa.polkit` shell plugin, which replaces `omarchy.polkit` (manifest `clonedFrom`). While pam_u2f waits for the security key, the dialog shows a "Touch your security key" prompt instead of a password field whose Enter does nothing. Must run inside the graphical session. |
| Shell plugins | `plugins` | Installs this desktop's list of third-party shell plugins — `omarchy_plugins` in `group_vars/all/main.yml`, **Radio Atlas** first (world radio on a rotatable globe in the bar, playing through Omarchy's `mpv`/`mpv-mpris`, so `omarchy.media` keeps the usual transport controls). Each entry is cloned by `omarchy plugin add` (the only supported installer: it validates the manifest, refuses an id another plugin already claims, and never runs plugin code, hooks or sudo), pinned to its `ref` (plugins are arbitrary unsandboxed QML inside the long-lived `omarchy-shell`, so the pin is the record of what was reviewed — `omarchy plugin update` fast-forwards a pinned clone off its tag, so bump `ref` instead), enabled, and **moved to the bar `section` the entry asks for**: Radio Atlas's icon lands in the right-hand group, right after the tray, rather than in the `left` its manifest's `defaultSection` asks for (`--enable` skips that prompt under `--yes`, so the play places the icon itself). Idempotent — re-running also pulls an icon you moved by hand back to where the list says — and the last tasks fail unless every entry really is enabled and in its section. Runtime dependencies are installed only when `pacman -T` reports one missing (all of them ship with Omarchy). Must run inside the graphical session. |
| openssh askpass notify | `openssh-askpass` | Rebuilds the installed openssh from Arch's packaging with `playbooks/files/openssh/askpass-notify.patch` (pkgrel `.1`), which makes OpenSSH honour `SSH_ASKPASS_REQUIRE` for notifications too, so a security key's "Confirm user presence" request reaches ssh-askpass-omarchy instead of the terminal. Official openssh updates replace it with the unpatched package; run it again after them. |
| Flea file dialogs | `file-chooser` | Makes the open/save file dialogs of non-GNOME apps (Firefox, Chromium, Electron, GTK and Qt apps) Flea's picker. Routes the FileChooser portal to Flea's backend for Hyprland (`org.freedesktop.impl.portal.FileChooser=flea;gtk` in `~/.config/xdg-desktop-portal/hyprland-portals.conf`, GTK3 as the fallback) — the tag runs `file-manager` first, which installs Flea — and exports `GTK_USE_PORTAL=1` from `~/.config/hypr/hyprland.lua`. Qt apps (Qt5 like KeePassXC, and Qt6) use `qt5ct`/`qt6ct` as their platform theme (`QT_QPA_PLATFORMTHEME=qt6ct`) instead of Omarchy's `gtk3`, which draws GTK3 dialogs in-process: their `standard_dialogs=xdgdesktopportal` option asks the portal, and they also set the Qt UI font to GTK's family at `omarchy_system_ui_font_pt` (Qt's plain `xdgdesktopportal` theme would give portal dialogs but a 9pt fallback font). Log out and back in (or restart the app) to pick it up. |
| LazyVim plugins | `lazyvim` | Enables LazyVim's LaTeX extra and installs [gregorio.nvim](https://github.com/AISCGre-BR/gregorio.nvim) (GABC/NABC chant notation, pairs with gregorio-lsp). |
| pt-BR localization | `ptbr` | Locale, personal folder names, Firefox (`firefox-i18n-pt-br` + `RequestedLocale` policy), Chromium-family/man pages/OCR language. |
| Podman | `podman` | Rootless container engine. Part of `playbooks/{system,user}/containers.yml` with Distrobox and the starship integration (umbrella tag `containers`). |
| Distrobox | `distrobox` | Depends on Podman: the tag also runs the Podman play first. |
| Nix | `nix` | Installs Nix from the Arch package (`nix`) in multi-user mode and enables `nix-daemon.socket`. When `/` is btrfs, first creates a top-level `@nix` subvolume and mounts it at `/nix` from `/etc/fstab` (same options as `/`), so snapper's root snapshots don't pin store paths or roll the store back; stops if `/nix` already holds a store outside a subvolume. Enables flakes and the `nix` command in `/etc/nix/nix.conf` and resolves `nixpkgs` through the flake registry (`nix-path`), so `nix-shell -p` works without channels. Appends `~/.nix-profile/bin` and the default profile to the session `PATH` (never shadowing Arch binaries) and their `share` dirs to `XDG_DATA_DIRS` via `environment.d` (log in again to pick it up). |
| direnv | `direnv` (also `nix`) | Installs direnv (Arch package) and hooks it into bash (a block in `~/.bashrc`, before ble.sh's `ble-attach`) and fish (`~/.local/share/fish/vendor_conf.d/direnv.fish`, leaving `~/.config/fish` alone), so a project's `.envrc` — e.g. `use flake` for its Nix dev shell — loads on `cd` once `direnv allow`ed. |
| nix-direnv | `nix-direnv` (also `nix`) | Installs [nix-direnv](https://github.com/nix-community/nix-direnv) into the user's Nix profile (not packaged by Arch or the AUR) and sources it from `~/.config/direnv/direnvrc`, so `use flake` / `use nix` cache the dev shell and keep it from being garbage-collected. Update with `nix profile upgrade nix-direnv`. |
| libfprint (goodix538d) | `libfprint` | Builds a fingerprint driver fork (lbssousa/libfprint) as a PKGBUILD package with makepkg and installs it in place of the official `libfprint` / `libfprint-git` (the package is itself named `libfprint-git` with epoch 2, so fprintd keeps working, `pacman -Syu` won't swap it back and `omarchy-setup-security-fingerprint` finds it installed), plus a watchdog for a driver desync bug and the Omarchy lock-screen retry-storm bug. |
| EPSON L4160 printer | `printer` | Driverless CUPS queue (IPP Everywhere). |
| Hyprland scrolling resize | `hypr-scrolling-resize` | SUPER+[ / SUPER+] resize the focused column. This and the next two are plays of `playbooks/{system,user}/desktop.yml` (umbrella tag `desktop`). |
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
| TPM2 LUKS auto-unlock | `tpm2` | Automatic LUKS unlock via TPM2 chip (systemd-cryptenroll, PCRs 0+2+7). Not part of `just setup` — see [`docs/tpm2.md`](docs/tpm2.md). |
| Yubikey GPG key | `gpg-yubikey` | Imports the public key, trusts it, configures git signing. Not part of `just setup`. **A dependency of `pinentry`, `ssh-askpass` and `polkit-agent`**: they deploy signed release tags and stop at the start if this key isn't in the keyring, so run it first. Lives in `playbooks/{system,user}/yubikey.yml` (umbrella tag `yubikey`). |
| Yubikey SSH keys | `ssh-yubikey` | Not Ansible — `scripts/ssh-yubikey.sh` (the FIDO2 PIN prompt needs a real terminal). Downloads the resident FIDO2 keys with `ssh-keygen -K` into `~/.ssh` (never overwriting) and writes one self-contained drop-in per key, `~/.ssh/config.d/<host>_<user>.conf` (here `github_com_lbssousa.conf`): `github.com` authenticates with `id_ed25519_sk_rk_github.com_lbssousa` (override with `GITHUB_KEY=`) with `IdentityAgent none`, plus `ControlMaster auto` + `ControlPersist 10m`, so the PIN/touch is asked once per 10 minutes. Adds one `Include config.d/*.conf` line to `~/.ssh/config`. **To migrate to an ssh-agent: `just ssh-yubikey-disable`** (renames the drop-in to `*.conf.disabled`, which the `Include` glob ignores). Also `scripts/ssh-yubikey.sh status`/`enable`. Not part of `just setup`. |

See each playbook's own header comment for implementation details.

## Prerequisites

- An Omarchy desktop (or any Arch Linux with pacman, `locale-gen`,
  systemd and `xdg-user-dirs`).
- `run0` (part of systemd, so already there on Arch) and, for the system
  phase, a user in the `wheel` group. Other users need not be: their part is
  the user phase only.
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

As an administrator, on your own account:

```bash
git clone https://github.com/lbssousa/omarchy-setup.git
cd omarchy-setup
./bootstrap.sh   # installs `just`, if missing — only needs to run once
just setup       # the system phase, then your user phase
```

Adding someone: declare them in `group_vars/all/users.yml` (and, if they
want, their settings in `users/<name>.yml`), commit, then:

```bash
just users       # creates the account, asks for its password
just publish     # world-readable copy in /opt/omarchy-setup + omarchy-setup-user
```

They log in from the greeter (Omarchy's first-run setup runs as for the
owner) and apply their part, from a terminal in their session:

```bash
omarchy-setup-user          # same as `just user`, from the shared copy
```

Or directly with Ansible:

```bash
run0 pacman -S --needed ansible
ansible-galaxy collection install -r requirements.yml
./run-empowered.sh ansible-playbook system.yml -e @users/$USER.yml   # administrators
ansible-playbook user.yml -e @users/$USER.yml                         # each user
```

Run a single automation with `just <name>` (see the Justfile): it runs
the feature's system half when you are an administrator, then your user
half. `just check` syntax-checks everything and the boundary between the
phases.

The playbooks are idempotent — rerunning is safe.

**KeePassXC as the primary password manager, Proton Pass, Homebrew, the typesetting toolchain, the
BGRT boot theme, Secure Boot, the Yubikey GPG key, and the Yubikey
SSH keys are separate** — not part of `just setup`:

```bash
just keepassxc     # KeePassXC as the primary password manager (autostart + SUPER+SHIFT+SLASH)
just ssh-agent     # the OpenSSH agent (ssh-agent.socket + SSH_AUTH_SOCK), off by default
just proton-pass   # alternative password manager: desktop client (AUR) + CLI (Homebrew)
just proton-pass-cli  # just the CLI, no root needed
just homebrew      # Linuxbrew; needed by the Proton Pass CLI and `brew install`
just typesetting   # TeX Live + LilyPond + Gregorio, no containers (long network install)
just bgrt-theme    # builds the BGRT-derived boot theme; needs a firmware BGRT logo
just secureboot    # see docs/secureboot.md for the full walkthrough
just tpm2          # see docs/tpm2.md: automatic LUKS unlock via TPM2 chip
just tpm2-wipe     # re-enroll TPM2 after firmware/Secure Boot changes
just gpg-yubikey   # needs the Yubikey plugged in
just ssh-yubikey   # needs the Yubikey plugged in; script, prompts for the FIDO2 PIN
just ssh-yubikey-disable  # drop the GitHub SSH config (e.g. migrating to an ssh-agent)
```

## Structure

| File/Directory | Role |
|---|---|
| `bootstrap.sh` | Installs `just`, if missing |
| `run-empowered.sh` | Runs ansible-playbook under `run0 --empower`: one polkit authentication, then privileged tasks pass (see *Privilege* above) |
| `site.yml` | Runs `system.yml`, then `user.yml` (`just setup`) |
| `system.yml` | Index of the system phase: each `playbooks/system/*.yml` with its tag (`just system`) |
| `user.yml` | Index of the user phase: each `playbooks/user/*.yml` with its tag (`just user`, `omarchy-setup-user`) |
| `scripts/run-phase.sh` | Runs a playbook in a phase: system only for `wheel`, under `run-empowered.sh`; user only as the user; loads `users/$USER.yml` |
| `scripts/check-phases.sh` | Fails when a user-phase play becomes root or installs packages, or a system-phase play talks to a user session (`just check`, CI) |
| `group_vars/all/users.yml` | The machine's accounts (`omarchy_users`): full name, admin, shell |
| `group_vars/all/target.yml` | `target_user`/`target_home`: the account a run configures |
| `users/<name>.yml` | Each user's own settings (see `users/README.md`) |
| `playbooks/system/users.yml` | Accounts from `omarchy_users` (tag `users`) |
| `playbooks/system/omarchy-multiuser.yml` | omarchy-multiuser from a signed tag + its units (tag `omarchy-multiuser`) |
| `playbooks/system/sddm.yml` | Multi-user greeter, no autologin (tag `sddm`) |
| `playbooks/system/shared-checkout.yml` | `/opt/omarchy-setup` + `omarchy-setup-user` (tag `shared-checkout`, `just publish`) |
| `playbooks/user/preflight.yml` | User phase preconditions: not root, inside the graphical session |
| `playbooks/user/git-identity.yml` | git identity from `users/<name>.yml` (tag `git-identity`) |
| `docs/multi-user.md` | The multi-user model: phases, adding people, FIDO2/fingerprints, migrations, what stays global |
| `playbooks/system/polkit.yml` | polkitd ExpirationSeconds (tag `polkit`) |
| `playbooks/system/pam-auth-order.yml` | Pins the order of the sudo and polkit PAM stacks: fingerprint (`pam_fprintd`), then FIDO2/U2F key (`pam_u2f`), then password. Omarchy's fingerprint and FIDO2 setup scripts each insert at the top of the file, so the order otherwise depends on which ran last; this adds `pam_fprintd` (behind Omarchy's clamshell gate) at the top when it is missing, moves the `pam_u2f` line below it, has `omarchy-mu-apply-lock` keep `/etc/pam.d/omarchy-lock-fingerprint` (the lock screen only offers the fingerprint when it exists) while any user has prints, and sets `pam_fprintd` to `max-tries=3 timeout=10` (default 3 tries / 30 s): three fingerprint attempts, but the key is asked for quickly when no finger is placed (`pam_auth_order_fprintd_*` vars) (tag `pam-auth-order`) |
| `playbooks/{system,user}/flatpak.yml` | Flatpak + Flathub remote + Bazaar app store (`io.github.kolunmi.Bazaar`), `XDG_DATA_DIRS` session export and Bazaar D-Bus activation mask (tag `flatpak`) |
| `playbooks/{system,user}/firefox.yml` | Firefox from Flathub (`org.mozilla.firefox`), `/usr/local/bin/firefox` link + hidden `firefox.desktop` shim, Taskbar Tabs enabled by default, default page font size (tag `firefox`) |
| `playbooks/user/firefox-taskbar-apps.yml` | Firefox Taskbar Tabs from `firefox_taskbar_apps` (`files/firefox-taskbar-apps.py`), Omarchy web app launcher cleanup, tiled fullscreen rule and keybinds (tag `firefox-taskbar-apps`) |
| `playbooks/user/default-browser.yml` | Firefox as the default browser via `omarchy-default-browser` (when it isn't already) (tag `default-browser`) |
| `playbooks/system/onlyoffice.yml` | ONLYOFFICE Desktop Editors from Flathub (`org.onlyoffice.desktopeditors`), replacing native `libreoffice-fresh` (tag `onlyoffice`) |
| `playbooks/system/flathub-apps.yml` | Kdenlive, OBS Studio, Pinta and Xournal++ from Flathub, replacing the pre-installed native packages (tag `flathub-apps`, see `docs/flathub-migration-survey.md`) |
| `playbooks/{system,user}/emacs.yml` | Emacs (omarchy-emacs) + AUCTeX, yasnippet, lsp-mode + classic theme (tag `emacs`) |
| `playbooks/{system,user}/zed.yml` | Zed editor + Omarchy theme + font size (tag `zed`) |
| `playbooks/{system,user}/gregorio-lsp.yml` | gregorio-lsp, grelint, grefmt, built from source (tag `gregorio-lsp`) |
| `playbooks/{system,user}/pdf-viewer.yml` | Zathura (`org.pwmt.zathura`) from Flathub as default, native Papers kept for sushi, Evince removed (tag `pdf-viewer`) |
| `playbooks/{system,user}/file-manager.yml` | Flea file manager as the default for directories (tag `file-manager`) |
| `playbooks/{system,user}/plugins.yml` | This desktop's third-party shell plugin list (`omarchy_plugins`): `omarchy plugin add`, pinned to each entry's ref, enabled and placed in the bar section the entry asks for (tag `plugins`); plus the plugins that ship their own binary, each deployed from a GPG-signed release tag, as separate plays of the same file: omapin package + gpg-agent `pinentry-program` (tag `pinentry`), ssh-askpass-omarchy binary + `SSH_ASKPASS` environment (tag `ssh-askpass`), polkit-omarchy replacing `omarchy.polkit` (tag `polkit-agent`) |
| `playbooks/system/openssh-askpass.yml` | openssh rebuilt with the askpass notification patch (tag `openssh-askpass`) |
| `playbooks/user/lazyvim.yml` | LazyVim LaTeX extra + gregorio.nvim (tag `lazyvim`) |
| `playbooks/{system,user}/ptbr.yml` | pt-BR localization (tag `ptbr`) |
| `playbooks/{system,user}/keepassxc.yml` | KeePassXC (`omarchy-pkg-add keepassxc`) + XDG autostart (primary only) + browser native messaging manifests for Firefox (Flatpak relay + socket override) and Chromium, with its SSH agent integration off by default (`keepassxc_ssh_agent_enabled`, opt-in with `just ssh-agent`, which also enables the OpenSSH agent play — tag `ssh-agent`) and a udev rule that locks it when the YubiKey is unplugged — the default password manager, imported by `site.yml`; also takes over `SUPER+SHIFT+SLASH` and autostart (tag `keepassxc`) |
| `playbooks/{system,user}/bitwarden.yml` | Bitwarden from Flathub (`com.bitwarden.desktop`) + biometric unlock polkit action (in `system.yml`); `playbooks/user/bitwarden.yml` (`just bitwarden`) wires its SSH agent to `SSH_AUTH_SOCK` (socket-activated, launches Bitwarden on first use), deploys autostart and takes over `SUPER+SHIFT+SLASH` (tag `bitwarden`) |
| `playbooks/{system,user}/proton-pass.yml` | Proton Pass desktop (AUR `proton-pass-bin`) + CLI (Homebrew, `proton-pass-cli`), with the CLI's own SSH agent (`pass-cli ssh-agent`) wired to `SSH_AUTH_SOCK` via a systemd --user service — optional password manager, outside `site.yml`; takes over `SUPER+SHIFT+SLASH` (tags `proton-pass-desktop`, `proton-pass-cli`; umbrella `proton-pass`) |
| `playbooks/{system,user}/containers.yml` | Podman rootless, Distrobox, starship prompt inside distrobox (tags `podman`, `distrobox`, `starship-distrobox`; umbrella `containers`) |
| `playbooks/{system,user}/homebrew.yml` | Homebrew for Linux in `/home/linuxbrew/.linuxbrew`, `brew` launcher in `/usr/local/bin`, `bin`/`sbin` on the session `PATH` — outside `site.yml` (`just homebrew`) |
| `playbooks/{system,user}/nix.yml` | Nix from the Arch package, store on a `@nix` btrfs subvolume, flakes, session env (tag `nix`); direnv with bash + fish hooks (tag `direnv`); nix-direnv in the Nix profile (tag `nix-direnv`) |
| `playbooks/system/libfprint.yml` | libfprint goodix538d (tag `libfprint`) |
| `playbooks/{system,user}/printer.yml` | EPSON L4160 printer (tag `printer`) |
| `playbooks/{system,user}/desktop.yml` | Scrolling-layout column resize, screen scale (100%) + text size, night light synced to sunrise/sunset (tags `hypr-scrolling-resize`, `text-size`, `nightlight-solar`; umbrella `desktop`) |
| `playbooks/{system,user}/capslock.yml` | Caps Lock via keyd (tag `capslock`) |
| `playbooks/user/omadwaita-themes.yml` | Omadwaita / Omadwaita Light / Omadwaita Dark Omarchy themes (tag `omadwaita-themes`) |
| `playbooks/user/omaraptor-themes.yml` | Omaraptor / Omaraptor Light / Omaraptor Dark Omarchy themes — GNOME palette + Bluefin wallpapers (tag `omaraptor-themes`) |
| `playbooks/user/omaraptor-theme-auto.yml` | Day/night switching for the Omaraptor themes: script + systemd --user service/timer (tag `omaraptor-theme-auto`) |
| `playbooks/system/limine-silent-boot.yml` | Limine silent boot — quiet (header-only) + `timeout: 1`, re-enrolls config checksum (tag `limine-silent-boot`) |
| `playbooks/{system,user}/blesh.yml` | ble.sh in Bash: autosuggestions + syntax highlighting, wired into `~/.bashrc` / `~/.blerc` (tag `blesh`) |
| `local-typesetting/` | TeX Live + LilyPond (`/opt`) + Gregorio, built directly on the host (no containers, no Ansible) — `just typesetting` |
| `playbooks/{system,user}/bgrt-theme.yml` | BGRT-derived boot theme — outside `site.yml` (tag `bgrt-theme`) |
| `playbooks/system/secureboot.yml` | Secure Boot — outside `site.yml` (tag `secureboot`) |
| `docs/secureboot.md` | `just secureboot` walkthrough |
| `playbooks/system/tpm2.yml` | Automatic LUKS unlock via TPM2 (systemd-cryptenroll) — outside `site.yml` (recipe `tpm2`) |
| `docs/tpm2.md` | `just tpm2` walkthrough and PCR integrity reference |
| `scripts/enroll-tpm2.sh` | Standalone interactive TPM2 enrollment script (`just tpm2-enroll`) |
| `docs/omarchy-4.5-migration.md` | What the next Omarchy release (Quattro RS 4.5) changes for these automations, gathered ahead of time from the upstream `quattro` branch: which playbooks become obsolete, which need fixing before running on it, and how to re-check once it is tagged |
| `playbooks/{system,user}/yubikey.yml` | Yubikey GPG key — outside `site.yml` (tags `gpg-yubikey`, `yubikey`) |
| `scripts/ssh-yubikey.sh` | Resident SSH keys import + GitHub SSH drop-in (`just ssh-yubikey`, `just ssh-yubikey-disable`) |
| `playbooks/files/` | Static files copied as-is |
| `playbooks/templates/` | Jinja2 templates |
| `playbooks/tasks/` | Reusable tasks included via `include_tasks` |
| `group_vars/all/main.yml` | Variables for all automations (machine defaults) |
| `requirements.yml` | Required Ansible collections |
| `Justfile` | Shortcuts (`just setup`, `just ptbr`, etc.) |
