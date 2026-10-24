"""Creates the Firefox Taskbar Tabs ("tab apps") in a user's webapps list.

Run by playbooks/user/apps/webapps.yml with one JSON argument:
{"apps": [...], "desktop_prefix": ..., "exec_argv": [...], "try_exec": ...,
 "flatpak_id": ... (empty for the native build), "stale_prefixes": [...],
 "profiles_dirs": [...], "desktop_dir": ..., "portal_dir": ...,
 "backup_dir": ...}. Writes the entries straight into the
default profile's taskbartabs.json plus one launcher each in desktop_dir, the
same files Firefox itself writes when a tab is pinned (TaskbarTabsPin.sys.mjs),
minus the DynamicLauncher portal's confirmation dialog. Firefox must not be
running (the playbook checks): it keeps the registry in memory.

Prints one line per change and nothing otherwise, so the playbook can tell
whether anything changed.
"""

import configparser
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import uuid
from html.parser import HTMLParser
from urllib.parse import urljoin, urlparse
from urllib.request import Request, urlopen

# Exit status when Firefox was started while the icons downloaded.
FIREFOX_RUNNING = 3
# Firefox writes Taskbar Tab icons as 256x256 PNGs (ShellService.writeShortcutIcon).
ICON_SIZE = 256
# Sites sniff the User-Agent in opposite ways: messages.google.com answers
# 400 unless it looks like a real Firefox, web.whatsapp.com answers 400 when
# it does (from urllib). Pages are tried with each in turn.
USER_AGENTS = (
    "Mozilla/5.0 (X11; Linux x86_64; rv:140.0) Gecko/20100101 Firefox/140.0",
    "Mozilla/5.0 (X11; Linux x86_64)",
)


def fetch(url, user_agent=USER_AGENTS[0]):
    """Returns (final url after redirects, body bytes)."""
    request = Request(url, headers={"User-Agent": user_agent})
    with urlopen(request, timeout=15) as response:
        return response.geturl(), response.read()


def fetch_page(url):
    for user_agent in USER_AGENTS:
        try:
            return fetch(url, user_agent)
        except Exception:
            continue
    raise RuntimeError(f"could not fetch {url}")


class LinkParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links = []

    def handle_starttag(self, tag, attrs):
        if tag.lower() == "link":
            self.links.append({k.lower(): (v or "") for k, v in attrs})


def parse_sizes(value):
    """Largest width in a `sizes="192x192 512x512"` attribute, or 0."""
    best = 0
    for token in value.lower().split():
        if "x" in token:
            w, _, h = token.partition("x")
            if w.isdigit() and h.isdigit():
                best = max(best, int(w))
    return best


def to_png_256(data):
    """Converts any image Magick knows (PNG, ICO, SVG, WebP) to a 256x256 PNG,
    or None if the bytes aren't a usable image."""
    with tempfile.TemporaryDirectory() as tmp:
        src = pathlib.Path(tmp) / "in"
        dst = pathlib.Path(tmp) / "out.png"
        src.write_bytes(data)
        # [0] picks the first frame/layer — for .ico files, convert otherwise
        # writes out-0.png, out-1.png, ... and leaves out.png missing. Wait:
        # for multi-size .ico, [0] is often the 16x16 layer, so instead delete
        # all but the largest layer (-delete 0--2 after sorting by width).
        cmd = [
            "magick",
            "-background", "none",
            str(src),
            "-resize", f"{ICON_SIZE}x{ICON_SIZE}",
            "-gravity", "center",
            "-extent", f"{ICON_SIZE}x{ICON_SIZE}",
            str(dst),
        ]
        if subprocess.run(cmd, capture_output=True).returncode != 0:
            return None
        if dst.exists():
            return dst.read_bytes()
        # Multi-image input (.ico): pick the last (largest) rendered frame.
        frames = sorted(pathlib.Path(tmp).glob("out-*.png"))
        return frames[-1].read_bytes() if frames else None


def manifest_icons(manifest_url):
    """Yields (declared_size, absolute_url) from a web app manifest."""
    try:
        final_url, raw = fetch(manifest_url)
        data = json.loads(raw.decode("utf-8", errors="replace"))
    except Exception:
        return
    for icon in data.get("icons") or []:
        src = icon.get("src")
        if src:
            yield parse_sizes(icon.get("sizes", "")), urljoin(final_url, src)


def candidate_icon_urls(page_url):
    """Icon URLs for page_url, largest/sharpest first."""
    scored = []
    origin = f"{urlparse(page_url).scheme}://{urlparse(page_url).netloc}"
    try:
        final_url, body = fetch_page(page_url)
        origin = f"{urlparse(final_url).scheme}://{urlparse(final_url).netloc}"
        parser = LinkParser()
        parser.feed(body.decode("utf-8", errors="replace"))
        for link in parser.links:
            rels = set(link.get("rel", "").lower().split())
            href = link.get("href", "").strip()
            if not href:
                continue
            full = urljoin(final_url, href)
            if "manifest" in rels:
                for size, url in manifest_icons(full):
                    scored.append((size or 128, url))
            elif rels & {"icon", "apple-touch-icon", "apple-touch-icon-precomposed", "fluid-icon"}:
                size = parse_sizes(link.get("sizes", ""))
                if not size:
                    size = 180 if "apple-touch-icon" in rels else 64
                scored.append((size, full))
    except Exception:
        pass
    # Prefer >=256px, then the largest below it, with /favicon.ico as last resort.
    scored.sort(key=lambda item: (item[0] >= ICON_SIZE, item[0]), reverse=True)
    return [url for _, url in scored] + [f"{origin}/favicon.ico"]


def best_icon(page_url):
    """256x256 PNG bytes for page_url, or None if every source failed."""
    seen = set()
    for url in candidate_icon_urls(page_url):
        if url in seen:
            continue
        seen.add(url)
        try:
            _, raw = fetch(url)
        except Exception:
            continue
        # For .ico files, pick the largest embedded image before resizing.
        png = ico_largest_to_png(raw) if url.lower().endswith(".ico") else None
        if png is None:
            png = to_png_256(raw)
        if png is not None:
            return png
    return None


def ico_largest_to_png(raw):
    with tempfile.TemporaryDirectory() as tmp:
        src = pathlib.Path(tmp) / "in.ico"
        src.write_bytes(raw)
        identify = subprocess.run(
            ["magick", "identify", "-format", "%p %w\n", str(src)],
            capture_output=True, text=True,
        )
        if identify.returncode == 0 and identify.stdout.strip():
            best = max(
                (line.split() for line in identify.stdout.strip().splitlines()),
                key=lambda parts: int(parts[1]) if len(parts) == 2 and parts[1].isdigit() else 0,
                default=None,
            )
            if best:
                dst = pathlib.Path(tmp) / "out.png"
                cmd = [
                    "magick", "-background", "none", f"{src}[{best[0]}]",
                    "-resize", f"{ICON_SIZE}x{ICON_SIZE}",
                    "-gravity", "center", "-extent", f"{ICON_SIZE}x{ICON_SIZE}",
                    str(dst),
                ]
                if subprocess.run(cmd, capture_output=True).returncode == 0 and dst.exists():
                    return dst.read_bytes()
    return None


def default_profile(profiles_dirs):
    """The profile Firefox starts with: this install's default from
    profiles.ini's [Install*] section, else the [Profile*] marked Default=1.
    Checks ~/.var/app/org.mozilla.firefox/config/mozilla/firefox first
    (Firefox 147+ XDG layout), then ~/.var/app/org.mozilla.firefox/.mozilla/firefox.
    None when Firefox has never been started."""
    for profiles_dir in map(pathlib.Path, profiles_dirs):
        profiles_ini = profiles_dir / "profiles.ini"
        if not profiles_ini.exists():
            continue
        ini = configparser.ConfigParser(interpolation=None, strict=False)
        ini.optionxform = str
        ini.read(profiles_ini)
        for section in ini.sections():
            if section.startswith("Install") and ini[section].get("Default"):
                return profiles_dir / ini[section]["Default"]
        for section in ini.sections():
            if section.startswith("Profile") and ini[section].get("Default") == "1":
                path = ini[section]["Path"]
                relative = ini[section].get("IsRelative", "1") == "1"
                return profiles_dir / path if relative else pathlib.Path(path)
    return None


def container_ids(profile):
    """Container name -> userContextId, from the profile's own
    containers.json (ids are per profile)."""
    path = profile / "containers.json"
    if not path.exists():
        return {}
    identities = json.loads(path.read_text(encoding="utf-8")).get("identities", [])
    return {i["name"]: i["userContextId"] for i in identities if i.get("public") and i.get("name")}


def desktop_exec(argv):
    """Exec= quoting as in ShellService.createLinuxDesktopEntry."""
    escape = lambda arg: "".join("\\" + c if c in '`$"\\' else c for c in arg)
    return " ".join(f'"{escape(arg)}"' for arg in argv)


def firefox_running(flatpak_id):
    if flatpak_id:
        ps = subprocess.run(
            ["flatpak", "ps", "--columns=application"], capture_output=True, text=True, check=True
        )
        return flatpak_id in ps.stdout.split()
    # The native build: this user's own firefox processes only.
    ps = subprocess.run(["pgrep", "-u", str(os.getuid()), "-x", "firefox"], capture_output=True)
    return ps.returncode == 0


def write_if_changed(path, data):
    if path.exists() and not path.is_symlink() and path.read_bytes() == data:
        return
    # A tab pinned from Firefox leaves a symlink into the portal's directory
    # here; replace it rather than write through it.
    if path.is_symlink():
        path.unlink()
    path.write_bytes(data)
    print(f"Wrote {path}")


def main():
    config = json.loads(sys.argv[1])
    apps = config["apps"]
    if not apps:
        return
    flatpak_id = config.get("flatpak_id") or ""
    exec_argv = config["exec_argv"]
    desktop_dir = pathlib.Path(config["desktop_dir"])
    backup_dir = pathlib.Path(config["backup_dir"])
    # Where the DynamicLauncher portal keeps the launchers (and icons) of
    # tabs pinned from inside Firefox; desktop_dir only gets a symlink.
    portal_dir = pathlib.Path(
        config.get("portal_dir") or (pathlib.Path.home() / ".local" / "share" / "xdg-desktop-portal")
    )
    webapp_prefix = f"{config['desktop_prefix']}.webapp-"

    profile = default_profile(config["profiles_dirs"])
    if profile is None:
        # A fresh install that has never started Firefox: nothing to add the
        # tabs to yet. Not an error, so a full site.yml / user.yml run carries on.
        print("No Firefox profile yet: start Firefox once, then run this again.", file=sys.stderr)
        return
    profile = profile.resolve()

    # The slow part (a minute or so of downloads) goes first, so the check
    # for a running Firefox right after it is still true when the registry
    # is read and written: one started meanwhile would keep its own copy in
    # memory and overwrite ours (the playbook checks too, but before this).
    icons = {app["url"]: best_icon(app["url"]) for app in apps}
    if firefox_running(flatpak_id):
        print(f"{flatpak_id or 'firefox'} is running; nothing written.", file=sys.stderr)
        sys.exit(FIREFOX_RUNNING)

    registry_path = profile / "taskbartabs" / "taskbartabs.json"
    icons_dir = profile / "taskbartabs" / "icons"
    for directory in (desktop_dir, icons_dir, backup_dir):
        directory.mkdir(parents=True, exist_ok=True)

    old_registry = registry_path.read_text(encoding="utf-8") if registry_path.exists() else None
    registry = json.loads(old_registry) if old_registry else {"version": 1, "taskbarTabs": []}
    tabs = registry["taskbarTabs"]
    by_name = {tab.get("name"): tab for tab in tabs}

    # Multi-Account Containers' "always open in" rules (and Facebook
    # Container) reopen a page loaded in the wrong container as a tab of the
    # right one in the main window, closing the tab app's window. So each
    # app runs in the container its site is assigned to.
    containers = container_ids(profile)

    for app in apps:
        name, url = app["desktop_name"], app["url"]
        container = app.get("container")
        if container and container not in containers:
            sys.exit(
                f"{name}: container {container!r} not found in {profile / 'containers.json'}"
                f" (have: {', '.join(sorted(containers)) or 'none'})"
            )
        user_context_id = containers[container] if container else 0

        tab = by_name.get(name)
        if tab is None:
            tab = by_name[name] = {"id": str(uuid.uuid4()), "name": name}
            tabs.append(tab)
        tab.update(
            scopes=[{"hostname": urlparse(url).hostname or ""}],
            userContextId=user_context_id,
            startUrl=url,
            shortcutRelativePath=f"{webapp_prefix}{tab['id']}.desktop",
        )

        icon_path = icons_dir / f"{tab['id']}.png"
        icon = icons[url]
        if icon:
            write_if_changed(icon_path, icon)
        # A failed fetch keeps the icon from an earlier run; with none at
        # all, the launcher falls back to the Firefox icon.
        icon_value = str(icon_path) if icon_path.exists() else (flatpak_id or "firefox")

        exec_line = desktop_exec([
            *exec_argv,
            # The same arguments Firefox puts in its own launchers
            # (TaskbarTabsPin.sys.mjs).
            "-taskbar-tab", tab["id"],
            "-new-window", url,
            "-profile", str(profile),
            "-container", str(user_context_id),
        ])
        write_if_changed(
            desktop_dir / tab["shortcutRelativePath"],
            (
                "[Desktop Entry]\n"
                "Type=Application\n"
                "Version=1.5\n"
                f"Name={name}\n"
                f"Icon={icon_value}\n"
                f"Exec={exec_line}\n"
                f"TryExec={config['try_exec']}\n"
                + (f"X-Flatpak={flatpak_id}\n" if flatpak_id else "")
            ).encode(),
        )

    # Drop the shadow entries Firefox makes when a launcher names a
    # -taskbar-tab uuid it doesn't know (TaskbarTabsCmd.sys.mjs recreates the
    # tab under a fresh uuid, with no launcher of its own). Firefox opens a
    # URL in the first entry whose scope matches, so a shadow sharing a
    # managed app's hostname and container steals it.
    managed = [by_name[app["desktop_name"]] for app in apps]
    managed_ids = {tab["id"] for tab in managed}
    managed_scopes = {
        (scope["hostname"], tab["userContextId"]) for tab in managed for scope in tab["scopes"]
    }

    def shadow(tab):
        return (
            tab["id"] not in managed_ids
            and not tab.get("shortcutRelativePath")
            and any(
                (scope.get("hostname"), tab.get("userContextId")) in managed_scopes
                for scope in tab.get("scopes", [])
            )
        )

    for tab in filter(shadow, tabs):
        print(f"Removed shadow Taskbar Tab: {tab['id']} ({tab.get('name')})")
    registry["taskbarTabs"] = tabs = [tab for tab in tabs if not shadow(tab)]

    new_registry = json.dumps(registry, ensure_ascii=False, indent=2) + "\n"
    if new_registry != old_registry:
        registry_path.write_text(new_registry, encoding="utf-8")
        print(f"Wrote {registry_path}")

    def remove(path, backup):
        if backup and not path.is_symlink():
            shutil.copy2(path, backup_dir / path.name)
        path.unlink()
        print(f"Removed {path}")

    # Omarchy's own launchers (omarchy-launch-webapp) for the same sites.
    # Omarchy names them its own way ("WhatsApp", not "WhatsApp Web"), so the
    # label matches too, or an explicit omarchy_webapp_name.
    omarchy_names = {
        n for app in apps
        for n in (app["desktop_name"], app.get("label"), app.get("omarchy_webapp_name")) if n
    }
    for desktop_file in desktop_dir.glob("*.desktop"):
        if desktop_file.name.startswith(webapp_prefix):
            continue
        try:
            text = desktop_file.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        names = [line[len("Name="):] for line in text.splitlines() if line.startswith("Name=")]
        if names and names[0] in omarchy_names and "omarchy-launch-webapp" in text:
            remove(desktop_file, backup=True)

    # Orphans: launchers and icons of Taskbar Tabs no longer in the registry
    # (earlier runs, Firefox-recreated shadows, tabs pinned through the
    # portal and since dropped), and launchers of the other Firefox build.
    # Firefox's own "unpin" goes through the portal, which can't remove
    # launchers written here.
    live_ids = {tab["id"] for tab in tabs}
    for pattern_dir, pattern in (
        (desktop_dir, webapp_prefix + "*.desktop"),
        (portal_dir / "applications", webapp_prefix + "*.desktop"),
        (portal_dir / "icons", "**/" + webapp_prefix + "*"),
    ):
        for path in pattern_dir.glob(pattern):
            if path.name[len(webapp_prefix):].removesuffix(path.suffix) not in live_ids:
                remove(path, backup=False)
    for prefix in config.get("stale_prefixes", []):
        for path in desktop_dir.glob(f"{prefix}.webapp-*.desktop"):
            remove(path, backup=False)
    for icon_file in icons_dir.glob("*.png"):
        if icon_file.stem not in live_ids:
            remove(icon_file, backup=False)


if __name__ == "__main__":
    main()
