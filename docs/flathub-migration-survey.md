# Flathub migration survey

Point-in-time audit of every GUI app on the Omarchy box, checking
which ones Flathub could replace and what would break if they did.

**Snapshot date:** 2026-09-29. The four apps in "Already migrated" below
were applied in `playbooks/flathub-apps.yml` (umbrella tag
`flathub-apps`, driven by `flathub_app_migrations` in
`group_vars/all/main.yml`); the rest is still unapplied review
material.

## Why this exists

The repo already ships four apps from Flathub (Firefox, Brave,
LibreOffice, plus the Bazaar app store), each with its own playbook
handling the desktop-entry, launcher-curation and keybind fallout that
a native → Flatpak swap causes on Omarchy. Those four swaps are done
and deliberate.

The question this doc answers is the same one for everything else:
**which remaining native apps are worth moving, and which are
load-bearing for Omarchy's shell?** Each candidate below carries the
same kind of integration cost, so the answer isn't just "does Flathub
have it".

## Method

Reproduce the inventory with:

```bash
flatpak list --app --columns=application,name,version,origin
pacman -Q | grep -E '\t(application|.*(gui|GUI|Desktop|desktop).*)$'
ls /usr/share/applications/*.desktop        # what actually has a launcher
for b in <binary>; do pacman -Qoq /usr/bin/$b; done
```

Flathub availability was checked against the v2 appstream/search API
rather than the website, so the IDs below are verified, not guessed:

```bash
curl -s -o /dev/null -w '%{http_code}\n' https://flathub.org/api/v2/appstream/<app-id>
curl -s https://flathub.org/api/v2/search -H 'Content-Type: application/json' \
  -d '{"query":"<term>"}'
```

`package-groups` in `/usr/share/omarchy/install/omarchy-base.packages`
is what distinguishes an app the user chose from one the ISO shipped.
Almost everything in the tables below is in that list — the exceptions
are **Zathura and Papers**, which `playbooks/pdf-viewer.yml` installs
(and Zed, a local addition), so those three are this repo's own
choices rather than Omarchy defaults.

## Current inventory

**Flatpak (4, system-wide):** Brave 1.96.59, Firefox 157.0,
LibreOffice 26.8.1.1, Bazaar 0.9.6 — 1.6 GB in `/var/lib/flatpak/app`
(Brave 490M, LibreOffice 776M, Firefox 324M, Bazaar 22M).

**Native GUI apps (23):** aether, btop, chromium, cliamp, evince,
foot, gcr, gnome-disk-utility, imv, kdenlive, localsend, moonlight-qt,
mpv (+ mpv-mpris), nautilus (+ nautilus-python), neovim, obs-studio,
obsidian, pinta, system-config-printer, tensaku, xournalpp, zathura,
zed.

> **Discrepancy worth knowing about:** `group_vars/all/main.yml` also
> defines two Flatpak password managers — `com.bitwarden.desktop`
> (line 431) and `me.proton.Pass` (line 490) — that are **not
> installed on this machine**. Both are outside `site.yml` (run via
> `just bitwarden` / `just proton-pass`), so that's expected, but it
> means the repo is not a complete description of the live box.

## Already migrated (no action)

| App | Flathub id | Playbook |
|---|---|---|
| Firefox | `org.mozilla.firefox` | `playbooks/firefox.yml` |
| Brave | `com.brave.Browser` | `playbooks/brave.yml` |
| LibreOffice | `org.libreoffice.LibreOffice` | `playbooks/libreoffice.yml` |
| Bazaar (store) | `io.github.kolunmi.Bazaar` | `playbooks/flatpak.yml` |
| Kdenlive | `org.kde.kdenlive` | `playbooks/flathub-apps.yml` |
| OBS Studio | `com.obsproject.Studio` | `playbooks/flathub-apps.yml` |
| Pinta | `com.github.PintaProject.Pinta` | `playbooks/flathub-apps.yml` |
| Xournal++ | `com.github.xournalpp.xournalpp` | `playbooks/flathub-apps.yml` |
| Zathura | `org.pwmt.zathura` | `playbooks/pdf-viewer.yml` |

The first four are the reference implementations for the pattern this
repo uses. Read `playbooks/libreoffice.yml` before starting another
swap — its header comment documents the three recurring costs
(desktop-entry id mismatch, launcher `NoDisplay` re-curation, keybind
reassignment) and `playbooks/default-browser.yml` documents a fourth
(the `omarchy default browser` table only knows native ids).

The next four are `playbooks/flathub-apps.yml`, and they hit **none** of
those four costs: every one keeps the same desktop-entry id in both
builds (confirmed on the native side against
`/usr/share/applications/*.desktop`, on the Flatpak side by the fact
that none of the four Flathub manifests sets `desktop-file-name`, so
each exports `<app-id>.desktop`). The play asserts that at run time and
stops if it ever stops holding. The swap also *fixes* a latent bug —
see the window-rule note in the play's header.

Zathura is the same story with one trap this doc got wrong at first:
sharing a desktop id is necessary but nowhere near sufficient when the
play *also* writes the app's config. Inside a Flatpak, `XDG_CONFIG_HOME`
is `~/.var/app/<app-id>/config` and `~/.config` isn't visible at all, so
the statusbar font this repo has always written to `~/.config/zathura`
kept "working" — the file was rewritten on every run, and Zathura never
read it. The play now writes where Zathura looks and deletes the old
file. Worth checking on any future swap that touches an app's config,
which is why it's called out here rather than left in the play.

## Candidates: Flathub has it, nothing load-bearing breaks

Verified available. Ordered by return (isolation gained ÷ work
required). Items 2–5 have since been implemented — see "Already
migrated" above.

| # | Native | Flathub id | Notes |
|---|---|---|---|
| 1 | Zathura 2026.07.18 | `org.pwmt.zathura` | `pdf_viewer_zathura_desktop_id` is `org.pwmt.zathura.desktop` — **identical for native and Flatpak**, so the `mimeapps.list` default in `playbooks/pdf-viewer.yml` survives untouched. **Not** an Omarchy default though: `playbooks/pdf-viewer.yml` installs it, so the swap belongs in that play (moving it to `flathub-apps.yml` would make the two reinstall each other). **Done.** Two things the swap costs: the Flathub build bundles **zathura-pdf-poppler**, not Arch's `zathura-pdf-mupdf` (same upstream version, different engine — and it also carries djvu + ps backends the Arch pair didn't), and the sandbox only grants `~/Documents` + `~/Downloads`. It also fixes the launcher, which had been showing "Zathura" twice — `zathura-pdf-mupdf` ships a second, unhidden copy of the same desktop entry. See the play's header for the config-path trap, which is the one genuinely surprising part. |
| 2 | Kdenlive 26.08.0 | `org.kde.kdenlive` | Window class is already in Omarchy's no-opacity rules (`system.lua:41`), so the Flatpak's class match is unchanged. Flatpak tracks upstream faster than `extra`. **Done.** |
| 3 | OBS Studio 32.2.2 | `com.obsproject.Studio` | Also already in `system.lua:41`. **Not** part of Omarchy's capture pipeline — that's `gpu-screen-recorder` (`omarchy-menu.jsonc:55`, `ScreenRecording.qml:18`), which stays native. The Flatpak needs the `org.freedesktop.portal.Desktop` ScreenCast portal, already present via `xdg-desktop-portal-hyprland`. **Done.** |
| 4 | Pinta 3.1.2 | `com.github.PintaProject.Pinta` | Same app, same window class (already in `system.lua:41`). Trivial swap. **Done.** |
| 5 | Xournal++ 1.3.7 | `com.github.xournalpp.xournalpp` | Same app. No Omarchy references. **Done.** |
| 6 | Papers 50.2 | `org.gnome.Papers` | **Caveat:** Omarchy floats the `org.gnome.Evince` class (`system.lua:7`) but has **no rule for `org.gnome.Papers`** — swapping in the Flatpak without adding one leaves Papers unfloated. It's an extra, non-default viewer per `playbooks/pdf-viewer.yml`, and like Zathura it isn't an Omarchy default. |
| 7 | Zed 1.18.1 | `dev.zed.Zed` | `omazed` is the blocker to check first, not the flatpak: it writes `~/.config/zed/settings.json` and installs `~/.config/omarchy/hooks/theme-set.d/omazed` (`playbooks/zed.yml`). Shared `$HOME` means the theme hook keeps working, but **Dev Containers need the Podman socket passed into the sandbox** — `zed_dev_container_use_podman` becomes load-bearing inside Flatpak. Not an Omarchy default either. |

**Also available, not currently installed:** Blender
(`org.blender.Blender`), Inkscape (`org.inkscape.Inkscape` — note
`playbooks/inkscape.yml` also needs `python-svg2tikz` from AUR, so
this is a partial migration at best), GNOME Calculator
(`org.gnome.Calculator`).

## Candidates: available on Flathub, but they break Omarchy

Not recommended without a matching shell change first.

| App | Flathub id | What breaks |
|---|---|---|
| mpv 0.41.0 | `io.mpv.Mpv` | `shell/Commons/Util.qml:60` documents that the login shell's PATH is what makes `mpv` a valid GUI target; the Flatpak sandbox hides it. `mpv-mpris` (a separate native package) can't reach the Flatpak's IPC socket, and `default/hypr/apps/webcam-overlay.lua:16` depends on mpv's window class. |
| LocalSend 1.18.2 | `org.localsend.localsend_app` | **Half-supported already.** `default/nautilus-python/extensions/localsend.py:29-43` explicitly probes for the Flatpak id, so the Nautilus "Send with LocalSend" context menu would work. But `omarchy-menu.jsonc:84` launches `uwsm-app -- localsend` — the bare binary, which the Flatpak doesn't provide under that name. That one line needs to become `flatpak run`. |
| Evince 48.4 | `org.gnome.Evince` | Must **stay native**: Nautilus's sushi quick-previewer hard-depends on it at the package level (`playbooks/pdf-viewer.yml` documents this). Installing the Flatpak wouldn't satisfy `pacman`, so sushi and Space-to-preview break for every file type. |
| Chromium 152.0 | `org.chromium.Chromium` | `install/config/browser-policy.sh` + `install/helpers/browser-policy.sh` and `default/hypr/apps/browser.lua` all target the native binary. Also see the browser redundancy below. |

## No Flathub equivalent

Verified absent (404 on the appstream API and/or no search hit):

- **`aether`** 4.30.0 — Omarchy's default browser, from the `omarchy` repo. No Flatpak at all.
- **`tensaku`** 0.29.0 — screenshot annotation, from the `omarchy` repo. Omarchy has a window rule for `dev.tensaku.Tensaku` (`system.lua:30`) and lists it as a GUI PATH target (`Util.qml:60`). Must stay native.
- **`foot`**, **`btop`**, **`imv`**, **`neovim`**, **`gcr`**, **`cliamp`**, **`system-config-printer`** — terminal, TUI/TLI tools, or GTK utilities Omarchy wires into its own shell.
- **`nautilus`** — was on Flathub, now returns 404. Irrelevant anyway: it's the file manager, and `nautilus-python` is an Omarchy-critical extension host.
- **`gnome-disk-utility`** — not on Flathub.

## Redundancies found (the actual win)

The Flatpak migrations above are worth less than the duplication they
sit next to:

1. **Four browsers.** Firefox (Flathub) + Brave (Flathub) + Chromium
   (native) + aether (native, Omarchy default). At most two are ever
   primary. Chromium and aether both have Flathub-blocked status, so
   this is a choice, not a migration — `playbooks/default-browser.yml`
   already models `<firefox|brave>` as the supported set.
2. **Two PDF viewers.** Evince + Papers, on top of Zathura. Papers
   exists here as an explicit "extra, non-default" pick
   (`playbooks/pdf-viewer.yml`); if it's never launched, it's ~19 MB of
   dead weight.
3. **Two video players.** mpv (tied into the shell, see above) and
   Moonlight. Moonlight is a genuine second use case, not a duplicate.
4. **Flathub already costs 1.6 GB.** LibreOffice alone is 776M. Every
   additional Flatpak app pulls a shared runtime — Qt6 apps (Zed,
   Kdenlive, Zathura, Moonlight) all share the KDE runtime, so the
   first one is expensive and the rest are cheap. Migrating the whole
   Qt cluster together is materially better than migrating one of them.

> **On disk size:** `pacman -Qi` "Installed Size" for zathura (1.8 G),
> moonlight-qt (2.0 G) and zed (352 M) is **not** the app size — those
> are `extra` packages whose PKGBUILD bundles their recursive
> dependencies into one `noverpkg`, so the figure includes Qt6, FFmpeg
> etc. Don't use it to estimate what a Flatpak swap saves. The honest
> comparison is "Qt6 shared runtime once" vs. "bundled Qt6 four times",
> and that only holds if the whole cluster moves together.

## Suggested order, and where each one landed

1. **Pinta + Xournal++ together** — zero integration surface, smallest
   per-app work, good way to validate the pattern a fourth time.
   **Done** (`flathub-apps.yml`).
2. **Kdenlive + OBS + Zathura** — the Qt6 cluster, in one pass. Window
   classes already match in `system.lua:41`. All three are **done**;
   Zathura went in `pdf-viewer.yml` rather than `flathub-apps.yml`,
   since that play owns the app.
3. **Zed** — needs a decision on the Podman socket in Dev Containers
   before it can move.
4. **Papers** — only if it's actually used; otherwise delete it from
   `playbooks/pdf-viewer.yml` instead of migrating it.

The four that share a playbook do so because they need no per-app data
beyond name / Flatpak id / native package: one `flathub_app_migrations`
list in `group_vars/all/main.yml`, one `Justfile` recipe
(`just flathub-apps`), one `site.yml` import. Zathura is the exception
that proves the rule — it went into `playbooks/pdf-viewer.yml` instead,
because that play already owns it (Zathura, the default-viewer
mapping, the statusbar font), and moving it to the umbrella play would
have had the two reinstall each other. Zed, if it ever moves, will need
a play of its own too — for the Podman socket, not for the app.

## Open questions for the review

- Is mpv actually used, or is it just there because Omarchy seeds it?
  Its whole Flatpak case rests on the answer.
- Is Papers opened, or is it purely a "Open With" entry?
- Should Chromium or aether be dropped to get back to two browsers?
  Both are Flathub-blocked, so this is a keep/drop decision.
- `bitwarden` and `proton-pass` are in `group_vars` but not installed
  — is that intentional, or did those plays just never run?
