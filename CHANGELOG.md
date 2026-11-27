# Changelog

## Unreleased

- **Ready for Omarchy 4.6.0rc1.**
  - polkit-omarchy 0.4.0 (was 0.3.0): 4.6 asks for encrypted drives'
    passwords through the polkit agent (`omarchy.polkit unlockDrive`), which
    0.3.0 lacks, so with it no encrypted drive unlocked. Its prompts also
    follow 4.6's agent.
  - omarchy-multiuser 0.15.0 (was 0.14.2): on 4.6, Update > Password stays
    per person, and Factory Reset, Hostname and Snapshots are for
    administrators.
  - The bar's screensaver guard steps aside on 4.6, whose screensaver is
    drawn natively and is no longer a window: the watcher isn't installed
    there, and one already installed is removed.
  - The fish port still follows Omarchy 4.5's bash files; on 4.6 the fish
    play warns that several of them changed.

## 0.1.0 (2026-11-27)

The first release: Ansible automation that sets up a freshly installed
Omarchy 4.5 desktop, with a menu to choose what to apply, for one person or
several sharing the machine.

- **Two phases.** `just system` (packages, /etc, PAM, the login screen,
  signed plugin builds; administrators only, one polkit authentication up
  front under `run0 --empower`) and `just user` (each person's ~/.config,
  session services and shell plugins, run as themselves). `just setup` runs
  both; `just apply <id>...` runs only the features named.
- **`just configure`**, a gum menu over the feature catalog (`features.yml`,
  documented in `docs/features.md`): the features to apply, the apps per
  category with their installation alternatives (native, AUR, Flathub or a
  release bundle) and default app, the web apps engine (Omarchy's native web
  apps, Firefox Taskbar Tabs, or Chrome/Chromium/Brave PWAs), and the Bibata
  mouse cursor theme. Choices go to `~/.config/omarchy-setup/features.yml`;
  features marked to revert are undone when turned off.
- **Accounts and login**: the accounts in `group_vars/all/users.yml` (fish as
  login shell, administrators, child accounts, subuid ranges; `just users`),
  [omarchy-multiuser](https://github.com/lbssousa/omarchy-multiuser) for
  several people on one machine, the PAM order, and a shared checkout every
  user runs their own phase from (`just publish`, `omarchy-setup-user`).
- **Desktop**: file dialogs from the default file manager, column resize keys
  and vertical workspace animation for Hyprland, screen scale and text size,
  night light at sunset and sunrise, the bar hidden under the screensaver,
  Firefox following the Omarchy theme, Caps Lock as Esc, Superwhisper
  hold-to-talk.
- **Themes**: Omadwaita, Omaraptor (with day/night switching), Osaka Jade and
  Piedmont Gold, and the Bibata mouse cursor.
- **Omarchy shell plugins**: the Agents panel, Dropbox, fingerprint and
  security key overlays, polkit agent, askpass and pinentry dialogs, and
  more, built and signed in the system phase.
- **Shell and development**: fish with ports of Omarchy's bash functions,
  Starship extras, LazyVim extras, Podman, Distrobox, Nix, Homebrew.
- **Portuguese (Brazil)**: folders, browsers and OCR in Portuguese.
- **Hardware and security**: the Goodix 538d fingerprint reader, the EPSON
  L4160 printer, Secure Boot with sbctl, a Yubikey GPG key, and the security
  key wizard (`just security-key`: FIDO2, OpenPGP, resident SSH keys), plus
  `just git-dir-identity` for a git identity per folder.
- **Extras**: the BGRT boot theme and Google Drive through rclone.
- **Checks**: `just check` syntax-checks every entry point, keeps the two
  phases apart (no root in the user phase, no user session in the system
  phase), matches the catalog against the plays' tags and keeps
  `docs/features.md` current; CI runs it on every pull request and push to
  main.
