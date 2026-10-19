#!/usr/bin/env python3
"""Find and remove duplicate entries in a KeePassXC database.

Duplicates usually come from importing another vault (or the same export
twice). Two entries are duplicates when title, username and URL match
(title/username case-insensitively, URL without scheme, "www." and
trailing slash); passwords may differ, and the entry whose password is the
most recent one prevails. With --strict-password the password has to match
too. Dry-run by default: it only prints a report.

  keepassxc-dedupe.py Vault.kdbx -y 2                # report
  keepassxc-dedupe.py Vault.kdbx -y 2 --apply        # backup + remove

What --apply does, and does not do:
  * copies the database to <name>.bak-<timestamp> first;
  * removes through `keepassxc-cli rm`, which moves entries to the Recycle
    Bin (the script refuses to run if the Recycle Bin is disabled), so
    every removal can still be undone from inside KeePassXC;
  * keeps the entry with the most recent password of each cluster (see
    below; --keep oldest to invert), and copies the notes of a duplicate
    into the kept entry when the kept one has none;
  * leaves a cluster alone, listed as "manual", when a duplicate carries
    something the CLI cannot merge: different notes, custom attributes
    (TOTP, passkeys, ...), attachments or tags the kept entry lacks;

When are passwords "recent"? KeePassXC keeps every edit in the entry's
history, so the time the current password was set is the modification time
of the oldest history version that already had it. An entry with no history
never changed its password, so its creation time is used. Ties fall back to
the entry's last modification time. The losing entries (and their older
passwords) land in the Recycle Bin, not in the trash for good.

Limits of keepassxc-cli: entries can only be addressed by group path, not
by UUID. Clusters whose members share one path with an unrelated entry are
therefore listed as "manual". Passwords are read from the exported XML in
memory only and are never printed or written to disk.
"""
import argparse
import getpass
import os
import shutil
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from collections import defaultdict
from urllib.parse import urlsplit

STANDARD = {"Title", "UserName", "Password", "URL", "Notes"}


def cli_cmd():
    override = os.environ.get("KEEPASSXC_CLI")
    if override:
        return override.split()
    return ["keepassxc-cli"]


class Vault:
    def __init__(self, args):
        self.opts = []
        if args.key_file:
            self.opts += ["-k", args.key_file]
        if args.yubikey:
            self.opts += ["-y", args.yubikey]
        if args.no_password:
            self.opts += ["--no-password"]
        self.password = "" if args.no_password else getpass.getpass("Database password: ")
        self.base = cli_cmd()

    def run(self, sub, *rest):
        cmd = self.base + [sub, "-q"] + self.opts + list(rest)
        res = subprocess.run(cmd, input=self.password + "\n", capture_output=True, text=True)
        if res.returncode != 0:
            sys.exit(f"keepassxc-cli {sub} failed: {res.stderr.strip() or res.stdout.strip()}")
        return res.stdout

    def export_xml(self, database):
        return ET.fromstring(self.run("export", "-f", "xml", database))


def text(node, tag):
    child = node.find(tag)
    return (child.text or "") if child is not None else ""


def parse(root):
    """Return (entries, recycle_bin_enabled). Skips the Recycle Bin and history."""
    meta = root.find("Meta")
    bin_uuid = text(meta, "RecycleBinUUID") if meta is not None else ""
    bin_enabled = meta is not None and text(meta, "RecycleBinEnabled").lower() == "true"
    entries = []

    def walk(group, trail):
        if bin_uuid and text(group, "UUID") == bin_uuid:
            return
        here = trail + [text(group, "Name")]
        for e in group.findall("Entry"):
            strings = {s.findtext("Key"): (s.findtext("Value") or "") for s in e.findall("String")}
            times = e.find("Times")
            entries.append({
                "uuid": text(e, "UUID"),
                "group": "/".join(here[1:]),  # drop the root group's own name
                "title": strings.get("Title", ""),
                "user": strings.get("UserName", ""),
                "url": strings.get("URL", ""),
                "password": strings.get("Password", ""),
                "notes": strings.get("Notes", ""),
                "custom": {k: v for k, v in strings.items() if k not in STANDARD},
                "binaries": sorted(b.findtext("Key") or "" for b in e.findall("Binary")),
                "tags": set(filter(None, text(e, "Tags").replace(",", ";").split(";"))),
                "mtime": text(times, "LastModificationTime") if times is not None else "",
                "pwtime": password_time(e, strings.get("Password", "")),
            })
        for g in group.findall("Group"):
            walk(g, here)

    walk(root.find("Root").find("Group"), [])
    return entries, bin_enabled


def password_time(e, current):
    """When the entry's current password was set (ISO string, sortable)."""
    def stamp(node, tag):
        return text(node.find("Times"), tag) if node.find("Times") is not None else ""

    versions = [(stamp(h, "LastModificationTime"),
                 next((s.findtext("Value") or "" for s in h.findall("String")
                       if s.findtext("Key") == "Password"), ""))
                for h in e.findall("History/Entry")]
    versions.sort()
    if not versions:
        return stamp(e, "CreationTime") or stamp(e, "LastModificationTime")
    since = stamp(e, "LastModificationTime")
    for when, pw in reversed(versions):  # walk back while the password is unchanged
        if pw != current:
            break
        since = when
    return since


def norm_url(url):
    if not url:
        return ""
    parts = urlsplit(url if "//" in url else "//" + url)
    return parts.netloc.lower().removeprefix("www.") + parts.path.rstrip("/")


def entry_path(e):
    return f"{e['group']}/{e['title']}" if e["group"] else e["title"]


def cluster(entries, strict_password=False):
    groups = defaultdict(list)
    for e in entries:
        key = (e["title"].strip().casefold(), e["user"].strip().casefold(), norm_url(e["url"]))
        groups[key + ((e["password"],) if strict_password else ())].append(e)
    return [v for v in groups.values() if len(v) > 1]


def plan(group, entries, keep):
    """Pick the entry to keep; return (keeper, doomed, manual, notes_to_set).

    keepassxc-cli addresses entries by path only (`rm <path>` takes the
    first entry with that path), so an entry is only removed when every
    entry sharing its path is either the keeper or another one being
    removed; apply_cluster() then steers the CLI to the right one.
    """
    ordered = sorted(group, key=lambda e: (e["pwtime"], e["mtime"]), reverse=(keep == "newest"))
    keeper, others = ordered[0], ordered[1:]

    manual, doomed, set_notes = [], [], None
    for o in others:
        if o["custom"] and o["custom"] != keeper["custom"]:
            manual.append((o, "custom attributes differ"))
        elif set(o["binaries"]) - set(keeper["binaries"]):
            manual.append((o, "attachments differ"))
        elif o["tags"] - keeper["tags"]:
            manual.append((o, "tags differ"))
        elif o["notes"] and o["notes"] != keeper["notes"]:
            if keeper["notes"] or (set_notes and set_notes != o["notes"]):
                manual.append((o, "notes differ"))
            else:
                set_notes = o["notes"]
                doomed.append(o)
        else:
            doomed.append(o)

    by_path = defaultdict(list)
    for e in entries:
        by_path[entry_path(e).casefold()].append(e)
    removing = {id(o) for o in doomed} | {id(keeper)}
    safe = []
    for o in doomed:
        if all(id(x) in removing for x in by_path[entry_path(o).casefold()]):
            safe.append(o)
        else:
            manual.append((o, "path shared with an entry that is not a duplicate"))
    if set_notes and any(id(x) not in removing for x in by_path[entry_path(keeper).casefold()]):
        # the notes could land on the wrong entry, so do not drop their only copy
        manual += [(o, "path shared with an entry that is not a duplicate")
                   for o in safe if o["notes"] == set_notes]
        safe = [o for o in safe if o["notes"] != set_notes]
        set_notes = None
    return keeper, safe, manual, set_notes


def apply_cluster(vault, db, entries, keeper, doomed, set_notes):
    """Remove `doomed`, keeping `keeper`, steering a path-only CLI.

    Entries sharing a path are listed in document order, which is the order
    keepassxc-cli walks them: it always acts on the first. Doomed entries
    ahead of the keeper are removed directly; once the keeper is first, it
    is renamed to a unique temporary title, the rest are removed, and the
    title is restored (the notes edit rides along on the temporary path).
    """
    path = entry_path(keeper)
    same = [e for e in entries if entry_path(e) == path]
    doomed_ids = {o["uuid"] for o in doomed}
    ahead = []
    for e in same:  # doomed entries before the keeper, then keeper, then the rest
        if e is keeper:
            break
        if e["uuid"] in doomed_ids:
            ahead.append(e)
    for _ in ahead:
        vault.run("rm", db, path)
    ahead_ids = {id(o) for o in ahead}
    rest = [o for o in doomed if id(o) not in ahead_ids and entry_path(o) == path]
    other = [o for o in doomed if entry_path(o) != path]
    if rest or (set_notes is not None):
        temp = f"{keeper['title']} [dedupe-{keeper['uuid'][:6].strip('=/+')}]"
        temp_path = f"{keeper['group']}/{temp}" if keeper["group"] else temp
        vault.run("edit", "-t", temp, db, path)
        if set_notes is not None:
            vault.run("edit", "--notes", set_notes, db, temp_path)
        for _ in rest:
            vault.run("rm", db, path)
        vault.run("edit", "-t", keeper["title"], db, temp_path)
    for o in other:
        vault.run("rm", db, entry_path(o))


def label(e):
    return f"{entry_path(e)}  [{e['user'] or '-'}] (password of {e['pwtime'][:10]})"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("database")
    ap.add_argument("-k", "--key-file")
    ap.add_argument("-y", "--yubikey", help="slot[:serial], e.g. 2")
    ap.add_argument("--no-password", action="store_true")
    ap.add_argument("--keep", choices=("newest", "oldest"), default="newest",
                    help="which password prevails (default: newest)")
    ap.add_argument("--strict-password", action="store_true",
                    help="only entries with the same password are duplicates")
    ap.add_argument("--apply", action="store_true", help="make changes (default: report only)")
    args = ap.parse_args()

    vault = Vault(args)
    entries, bin_enabled = parse(vault.export_xml(args.database))
    dupes = cluster(entries, args.strict_password)
    print(f"{len(entries)} entries, {len(dupes)} duplicate clusters\n")

    todo, removable = [], 0
    for group in dupes:
        keeper, doomed, manual, set_notes = plan(group, entries, args.keep)
        print(f"keep    {label(keeper)}")
        for o in sorted(group, key=lambda e: e["pwtime"]):
            if o is keeper:
                continue
            why = next((w for x, w in manual if x is o), None)
            note = why or ("different password" if o["password"] != keeper["password"] else "")
            print(f"  {'manual' if why else 'remove':7s} {label(o)}" + (f"  <- {note}" if note else ""))
        if set_notes:
            print("  merge   notes of a duplicate go into the kept entry")
        todo.append((keeper, doomed, set_notes))
        removable += len(doomed)

    print(f"\n{removable} entries removable.")
    if not removable:
        return
    if not args.apply:
        print("Dry run; re-run with --apply to remove them.")
        return
    if not bin_enabled:
        sys.exit("Recycle Bin is disabled in this database: refusing to delete permanently.")

    backup = f"{args.database}.bak-{time.strftime('%Y%m%d%H%M%S')}"
    shutil.copy2(args.database, backup)
    print(f"Backup: {backup}")
    for keeper, doomed, set_notes in todo:
        apply_cluster(vault, args.database, entries, keeper, doomed, set_notes)

    after, _ = parse(vault.export_xml(args.database))
    left = cluster(after, args.strict_password)
    alive = {e["uuid"] for e in after}
    for keeper, doomed, _ in todo:
        if keeper["uuid"] not in alive or any(o["uuid"] in alive for o in doomed):
            print(f"WARNING: {entry_path(keeper)} did not come out as planned; "
                  f"check the Recycle Bin and the backup.")
    print(f"Done: {len(entries)} -> {len(after)} entries; {len(left)} duplicate clusters left.")


if __name__ == "__main__":
    main()
