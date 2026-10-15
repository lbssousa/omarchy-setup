"""Creates the Firefox Taskbar Tabs ("tab apps") in firefox_taskbar_apps.

Run by playbooks/firefox-taskbar-apps.yml with one JSON argument:
{"apps": [...], "flatpak_id": ..., "profiles_dir": ..., "desktop_dir": ...,
 "backup_dir": ...}. Writes the entries straight into the default profile's
taskbartabs.json plus one launcher each in desktop_dir, the same files
Firefox itself writes when a tab is pinned (TaskbarTabsPin.sys.mjs), minus
the DynamicLauncher portal's confirmation dialog. Firefox must not be
running (the playbook checks): it keeps the registry in memory.

Prints one line per change and nothing otherwise, so the playbook can tell
whether anything changed.
"""

import configparser
import json
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
        if tag == "link":
            attrs = dict(attrs)
            if attrs.get("href") and attrs.get("rel"):
                self.links.append(attrs)


def page_icon_urls(url):
    """Icons the page itself declares: Web App Manifest icons plus
    <link rel="icon"/"apple-touch-icon">. mask-icon is skipped (Safari's
    single-colour pinned-tab silhouette), as are manifest icons meant only
    as monochrome badges."""
    try:
        base, body = fetch_page(url)
    except Exception:
        return []
    parser = LinkParser()
    parser.feed(body.decode("utf-8", "ignore"))

    urls = []
    for link in parser.links:
        rels = link["rel"].lower().split()
        href = urljoin(base, link["href"])
        if "manifest" in rels:
            try:
                manifest_url, data = fetch_page(href)
                manifest = json.loads(data.decode("utf-8", "ignore"))
            except Exception:
                continue
            for icon in manifest.get("icons") or []:
                purposes = (icon.get("purpose") or "any").split()
                if icon.get("src") and ("any" in purposes or "maskable" in purposes):
                    urls.append(urljoin(manifest_url, icon["src"]))
        elif "mask-icon" not in rels and any(
            rel in ("icon", "apple-touch-icon", "apple-touch-icon-precomposed")
            for rel in rels
        ):
            urls.append(href)
    return urls


def fallback_icon_urls(url):
    """Used only when the page declares nothing usable. Never the parent
    domain's icon: for messages.google.com that is Google's generic "G"."""
    parsed = urlparse(url)
    return [
        f"{parsed.scheme}://{parsed.netloc}/favicon.ico",
        "https://www.google.com/s2/favicons?sz=256&domain=" + (parsed.hostname or ""),
    ]


def sniff_format(data):
    """ImageMagick needs a hint for formats without a reliable magic number
    (ICO, SVG), and the downloaded file has no extension."""
    if data.startswith(b"\x00\x00\x01\x00"):
        return "ICO:"
    if data[:512].lstrip().startswith((b"<svg", b"<?xml")) and b"<svg" in data[:4096]:
        return "SVG:"
    return ""


def rasterize(data, workdir):
    """Decodes an icon (PNG, ICO with several frames, SVG, WebP, ...) and
    returns (native size, 256x256 PNG bytes), or None if it can't be read.
    Vector icons count as infinitely large."""
    src = pathlib.Path(workdir) / "src"
    dst = pathlib.Path(workdir) / "dst.png"
    src.write_bytes(data)
    dst.unlink(missing_ok=True)
    source = sniff_format(data) + str(src)
    try:
        info = subprocess.run(
            ["magick", "identify", "-format", "%p %w %h %m\n", source],
            check=True, capture_output=True, text=True,
        ).stdout.split()
    except Exception:
        return None
    frames = [
        (int(info[i]), int(info[i + 1]), int(info[i + 2]), info[i + 3])
        for i in range(0, len(info) - 3, 4)
    ]
    if not frames:
        return None
    # An ICO carries several sizes; take the largest one, not frame 0.
    index, width, height, fmt = max(frames, key=lambda f: min(f[1], f[2]))
    vector = fmt.upper() in ("SVG", "SVGZ", "MSVG")
    try:
        subprocess.run(
            ["magick", "-background", "none"]
            + (["-density", "1024"] if vector else [])
            + [f"{source}[{index}]",
               "-resize", f"{ICON_SIZE}x{ICON_SIZE}",
               "-gravity", "center",
               "-extent", f"{ICON_SIZE}x{ICON_SIZE}",
               # No timestamps, so an unchanged icon encodes to the same bytes.
               "-strip",
               f"PNG32:{dst}"],
            check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
    except Exception:
        return None
    return (float("inf") if vector else min(width, height)), dst.read_bytes()


def best_icon(url):
    """The largest icon the page declares, or failing that the best
    fallback; None if nothing could be fetched."""
    with tempfile.TemporaryDirectory() as workdir:
        for candidates in (page_icon_urls(url), fallback_icon_urls(url)):
            best = None
            for icon_url in dict.fromkeys(candidates):
                try:
                    _, data = fetch(icon_url)
                except Exception:
                    continue
                result = rasterize(data, workdir) if data else None
                if result and (best is None or result[0] > best[0]):
                    best = result
            if best:
                return best[1]
    return None


def default_profile(profiles_dir):
    """The profile Firefox starts with: this install's default from
    profiles.ini's [Install*] section, else the [Profile*] marked Default=1.
    None when Firefox has never been started."""
    ini = configparser.ConfigParser(interpolation=None, strict=False)
    ini.optionxform = str
    ini.read(profiles_dir / "profiles.ini")
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
    ps = subprocess.run(
        ["flatpak", "ps", "--columns=application"], capture_output=True, text=True, check=True
    )
    return flatpak_id in ps.stdout.split()


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
    flatpak_id = config["flatpak_id"]
    desktop_dir = pathlib.Path(config["desktop_dir"])
    backup_dir = pathlib.Path(config["backup_dir"])
    # Where the DynamicLauncher portal keeps the launchers (and icons) of
    # tabs pinned from inside Firefox; desktop_dir only gets a symlink.
    portal_dir = pathlib.Path.home() / ".local" / "share" / "xdg-desktop-portal"
    webapp_prefix = f"{flatpak_id}.webapp-"

    profile = default_profile(pathlib.Path(config["profiles_dir"]))
    if profile is None:
        # A fresh install that has never started Firefox: nothing to add the
        # tabs to yet. Not an error, so a full site.yml run carries on.
        print("No Firefox profile yet: start Firefox once, then run this again.", file=sys.stderr)
        return
    profile = profile.resolve()

    # The slow part (a minute or so of downloads) goes first, so the check
    # for a running Firefox right after it is still true when the registry
    # is read and written: one started meanwhile would keep its own copy in
    # memory and overwrite ours (the playbook checks too, but before this).
    icons = {app["url"]: best_icon(app["url"]) for app in apps}
    if firefox_running(flatpak_id):
        print(f"{flatpak_id} is running; nothing written.", file=sys.stderr)
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
        icon_value = str(icon_path) if icon_path.exists() else flatpak_id

        exec_line = desktop_exec([
            "flatpak", "run", "--command=/app/lib/firefox/firefox", flatpak_id,
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
                f"TryExec=/var/lib/flatpak/exports/bin/{flatpak_id}\n"
                f"X-Flatpak={flatpak_id}\n"
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
    # portal and since dropped). Firefox's own "unpin" goes through the
    # portal, which can't remove launchers written here.
    live_ids = {tab["id"] for tab in tabs}
    for pattern_dir, pattern in (
        (desktop_dir, webapp_prefix + "*.desktop"),
        (portal_dir / "applications", webapp_prefix + "*.desktop"),
        (portal_dir / "icons", "**/" + webapp_prefix + "*"),
    ):
        for path in pattern_dir.glob(pattern):
            if path.name[len(webapp_prefix):].removesuffix(path.suffix) not in live_ids:
                remove(path, backup=path.suffix == ".desktop")
    for icon_file in icons_dir.glob("*.png"):
        if icon_file.stem not in live_ids:
            remove(icon_file, backup=False)


if __name__ == "__main__":
    main()
