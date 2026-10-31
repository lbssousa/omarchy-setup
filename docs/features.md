# Features

<!-- Generated from features.yml by `just docs`. Don't edit by hand. -->

What each automation does to a stock Omarchy 4.5, and whether it is on
until you choose otherwise with `just configure`. **Revert**: turning it
off undoes it on the next run; otherwise turning it off only stops
managing it. fish as every account's login shell isn't a feature: it is
always applied.

## Accounts and login

| Feature | Tag | Effect | Phases | Default | Revert |
|---|---|---|---|---|---|
| User accounts | `users` | adds the accounts in group_vars/all/users.yml (fish as login shell, wheel or omarchy-users, subuid ranges) | system | off | no |
| omarchy-multiuser | `omarchy-multiuser` | adds forks of Omarchy's single-owner tools (multi-user greeter, per-user FIDO2/fingerprint, migrations); modifies SDDM (removes autologin) | system | off | no |
| PAM order | `pam-auth-order` | modifies the sudo and polkit PAM stacks (fingerprint, then FIDO2/U2F, then password) | system | on | no |
| polkit authentication cache | `polkit` | modifies polkitd's ExpirationSeconds | system | on | no |
| Shared checkout | `shared-checkout` | adds /opt/omarchy-setup and omarchy-setup-user, so every user can run their own phase | system | off | no |

## Base

| Feature | Tag | Effect | Phases | Default | Revert |
|---|---|---|---|---|---|
| Flatpak + Flathub + Bazaar | `flatpak` | adds Flatpak, the Flathub remote, Bazaar and the installation's languages; required by every Flatpak app option | system, user | on | no |
| git identity | `git-identity` | modifies ~/.gitconfig (user.name, user.email from the untracked local.yml) | user | on | no |

## Shell and prompt

| Feature | Tag | Effect | Phases | Default | Revert |
|---|---|---|---|---|---|
| Starship extras | `starship` | modifies ~/.config/starship.toml (Nix dev shell badge, commits ahead of/behind) | user | on | no |
| Starship inside distrobox | `starship-distrobox` | modifies ~/.config/starship.toml and ~/.bashrc (container name in the prompt) | user | on | no |

## Desktop

| Feature | Tag | Effect | Phases | Default | Revert |
|---|---|---|---|---|---|
| Flea file dialogs | `file-chooser` | modifies the FileChooser portal (Flea) and the Qt platform theme (qt6ct); adds qt5ct/qt6ct | system, user | on | yes |
| Column resize keys (scrolling layout) | `hypr-scrolling-resize` | adds SUPER+[ and SUPER+] to ~/.config/hypr/bindings.lua | user | on | yes |
| Screen scale + text size | `text-size` | modifies the monitor scale (100%), GDK_SCALE, the shell/terminal text size and the GNOME font sizes | user | on | no |
| Night light at sunset/sunrise | `nightlight-solar` | adds a timer that follows the real sunset/sunrise with hyprsunset | user | on | yes |
| Caps Lock via keyd | `capslock` | adds keyd (tap Esc, hold Ctrl, Shift+Caps Lock = Caps Lock); modifies Compose (Menu key instead of Shift+Caps Lock) | system, user | on | yes |
| Omadwaita themes | `omadwaita-themes` | adds three Adwaita-based Omarchy themes | user | on | no |
| Omaraptor themes | `omaraptor-themes` | adds three Omarchy themes on the GNOME palette with Bluefin wallpapers; modifies the Flatpak global override (GTK config read-only) | user | on | no |
| Omaraptor day/night switching | `omaraptor-theme-auto` | adds a timer switching the Omaraptor theme at sunrise/sunset | user | on | yes |

## Omarchy shell plugins and prompts

| Feature | Tag | Effect | Phases | Default | Revert |
|---|---|---|---|---|---|
| Omarchy shell plugins | `plugins` | adds the shell plugins in omarchy_plugins (and their dependencies) | system, user | on | no |
| omapin (GnuPG prompt) | `pinentry` | adds omapin and makes it gpg-agent's pinentry | system, user | on | no |
| omaskpass (SSH prompt) | `ssh-askpass` | adds omaskpass and makes it the SSH key/FIDO2 prompt (SSH_ASKPASS); removes ssh-askpass-omarchy | system, user | on | no |
| polkit-omarchy | `polkit-agent` | modifies the polkit agent (replaces Omarchy's omarchy.polkit plugin) | system, user | on | no |
| xdg-desktop-portal-omarchy (clipboard portal) | `clipboard-portal` | adds the RemoteDesktop/Clipboard portals (clipboard only, after a shell dialog), so the Bitwarden Flatpak copies natively on Wayland; off, it runs under XWayland | system, user | on | no |
| fingerprint-omarchy (fingerprint overlay) | `fingerprint` | adds an overlay from the Omarchy plugin marketplace to enroll, test and delete your fingerprints (fprintd), opened from Setup › Security; removes the fingerprint-omarchy package | system, user | on | no |
| security-key-omarchy (security key overlay) | `security-key` | adds an overlay from the Omarchy plugin marketplace to register your FIDO2 key for sudo/polkit and import its OpenPGP and SSH keys, opened from Setup › Security; removes the security-key-omarchy package | system, user | on | no |
| openssh with askpass touch notifications | `openssh-askpass` | modifies the openssh package (rebuilt with a patch) | system | on | no |

## Development

| Feature | Tag | Effect | Phases | Default | Revert |
|---|---|---|---|---|---|
| gregorio-lsp | `gregorio-lsp` | adds clang, rustup and the Gregorio language server, grelint and grefmt | system, user | on | no |
| LazyVim extras | `lazyvim` | modifies LazyVim (LaTeX extra, gregorio.nvim) | user | on | no |
| Podman | `podman` | adds rootless Podman (alongside Omarchy's Docker) | system, user | on | no |
| Distrobox | `distrobox` | adds Distrobox | system, user | on | no |
| Nix | `nix` | adds Nix (multi-user, flakes) on its own btrfs subvolume, and nix-direnv | system, user | on | no |
| direnv | `direnv` | adds direnv, hooked into fish and bash | system, user | on | no |

## Portuguese (Brazil)

| Feature | Tag | Effect | Phases | Default | Revert |
|---|---|---|---|---|---|
| pt-BR language | `ptbr-locale` | modifies Omarchy's language (omarchy-language pt-BR) and /etc/locale.conf | system, user | on | no |
| Folders in Portuguese | `ptbr-xdg-user-dirs` | modifies the personal folders (Documents → Documentos, Pictures → Imagens, ...) | system, user | on | no |
| Browsers in Portuguese | `ptbr-browsers` | modifies Firefox's RequestedLocale and the Chromium family's page language | system, user | on | no |
| man pages in Portuguese | `ptbr-man-pages` | adds man-pages-pt_br | system | on | no |
| OCR in Portuguese | `ptbr-ocr` | adds tesseract-data-por; modifies OMARCHY_OCR_LANGS | system, user | on | no |

## Hardware

| Feature | Tag | Effect | Phases | Default | Revert |
|---|---|---|---|---|---|
| Goodix 538d fingerprint reader | `libfprint` | modifies libfprint (goodix538d fork); adds a desync watchdog | system | on | no |
| EPSON L4160 printer | `printer` | adds the driverless L4160 queue as the default printer | system, user | on | no |

## Boot and security (opt-in)

| Feature | Tag | Effect | Phases | Default | Revert |
|---|---|---|---|---|---|
| Secure Boot (sbctl) | `secureboot` | adds sbctl keys; modifies Limine (checksums, hash_mismatch_panic) | system | off | no |
| LUKS auto-unlock (TPM2) | `tpm2` | modifies crypttab and the initramfs; adds a TPM2 keyslot (needs omarchy-multiuser, which removes autologin) | system | off | no |
| Yubikey GPG key | `gpg-yubikey` | adds the card's public key (ultimate trust) and git commit signing | system, user | off | no |

## Extras (opt-in)

| Feature | Tag | Effect | Phases | Default | Revert |
|---|---|---|---|---|---|
| Homebrew | `homebrew` | adds Homebrew for Linux (/home/linuxbrew) and bbrew | system, user | off | no |
| BGRT boot theme | `bgrt-theme` | adds an Omarchy theme and a Plymouth theme from the firmware logo | system, user | off | no |
| Google Drive (rclone) | `rclone-gdrive` | adds rclone mounts of Google Drive (systemd --user) | system, user | off | no |

## Apps

Each category lists its installation alternatives; several can be
installed side by side. Options are declarative: one left out is
uninstalled, Omarchy's own (**stock**) included, unless it is marked
as kept. ★ marks what is installed by default, and the default app
where the category has one.

### Web browsers

Default app: default browser (omarchy-default-browser); the menu also asks whether to keep Omarchy's native web apps or rebuild them with an installed browser.

| Option | Source | Notes |
|---|---|---|
| Chromium ★ | pacman `chromium` | stock |
| Firefox | pacman `firefox` |  |
| Firefox ★ (default) | flatpak `org.mozilla.firefox` |  |
| Brave Origin | aur `brave-origin-bin` |  |
| Brave | flatpak `com.brave.Browser` | Omarchy's web apps stay as they are: PWA install through machine policy is unverified inside its sandbox |

### Password managers

Default app: default password manager (SUPER+SHIFT+SLASH, autostart, SSH agent).

| Option | Source | Notes |
|---|---|---|
| Bitwarden ★ (default) | flatpak `com.bitwarden.desktop` | copies passwords through the clipboard portal (clipboard-portal feature); without that feature it runs under XWayland |
| Bitwarden | pacman `bitwarden` |  |
| KeePassXC | flatpak `org.keepassxc.KeePassXC` |  |
| KeePassXC | pacman `keepassxc` |  |

### Office suites

| Option | Source | Notes |
|---|---|---|
| LibreOffice | pacman `libreoffice-fresh` | stock |
| LibreOffice | flatpak `org.libreoffice.LibreOffice` |  |
| ONLYOFFICE ★ | flatpak `org.onlyoffice.desktopeditors` |  |
| ONLYOFFICE | aur `onlyoffice-bin` |  |
| ArtCraft: WordCraft, GridCraft, DeckCraft | bundle `artcraft-launcher` | early alpha; the apps are picked in the ArtCraft Launcher, which installs them as host Flatpaks (its sandbox may talk to org.freedesktop.Flatpak) |

### Graphics

| Option | Source | Notes |
|---|---|---|
| Pinta | pacman `pinta` | stock |
| Pinta ★ | flatpak `com.github.PintaProject.Pinta` |  |
| Inkscape (+ svg2tikz) ★ | pacman `inkscape` |  |
| Inkscape | flatpak `org.inkscape.Inkscape` |  |
| GIMP | pacman `gimp` |  |
| GIMP | flatpak `org.gimp.GIMP` |  |
| Krita | pacman `krita` |  |
| Krita | flatpak `org.kde.krita` |  |
| ArtCraft: PhotoCraft, VectorCraft, LightCraft, DesignCraft, FigCraft | bundle `artcraft-launcher` | early alpha; the apps are picked in the ArtCraft Launcher, which installs them as host Flatpaks (its sandbox may talk to org.freedesktop.Flatpak) |

### Document viewers (PDF)

Default app: default PDF viewer.

| Option | Source | Notes |
|---|---|---|
| Evince | pacman `evince` | stock |
| Papers ★ | pacman `papers` | kept; Nautilus's previewer (sushi) depends on it |
| Zathura ★ (default) | flatpak `org.pwmt.zathura` |  |
| Zathura | pacman `zathura`, `zathura-pdf-mupdf` |  |

### Video and streaming

| Option | Source | Notes |
|---|---|---|
| Kdenlive ★ | flatpak `org.kde.kdenlive` |  |
| Kdenlive | pacman `kdenlive` |  |
| OBS Studio ★ | flatpak `com.obsproject.Studio` |  |
| OBS Studio | pacman `obs-studio` |  |
| ArtCraft: FilmCraft, EffectCraft | bundle `artcraft-launcher` | early alpha; the apps are picked in the ArtCraft Launcher, which installs them as host Flatpaks (its sandbox may talk to org.freedesktop.Flatpak) |

### Notes and handwriting

| Option | Source | Notes |
|---|---|---|
| Xournal++ ★ | flatpak `com.github.xournalpp.xournalpp` |  |
| Xournal++ | pacman `xournalpp` |  |

### Editors

| Option | Source | Notes |
|---|---|---|
| Emacs (AUCTeX ★ | pacman `omarchy-emacs`, `emacs-wayland` |  |
| Zed (Omazed theme) ★ | pacman `zed`, `omazed` |  |

### File managers

Default app: default file manager (inode/directory).

| Option | Source | Notes |
|---|---|---|
| Nautilus ★ | pacman `nautilus` | stock; kept; Omarchy's own previews and scripts use it |
| Flea ★ (default) | pacman `flea` |  |
