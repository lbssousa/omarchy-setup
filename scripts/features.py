#!/usr/bin/env python3
"""The feature catalog (features.yml) and your choices, for the other tools.

  resolve PHASE OUT   write the resolved selection (catalog defaults + your
                      choices) as JSON extra vars to OUT and print the
                      --tags for PHASE: always, apps, every feature on, and
                      every feature off that can revert. OMARCHY_SETUP_ENABLE
                      (space-separated ids) turns features on for this run.
  check               the catalog is consistent and every feature id is a
                      play tag (and every play tag a feature id)
  doc                 docs/features.md, generated from the catalog
  menu ...            data for scripts/configure.sh (see menu_* below)

Choices live in $XDG_CONFIG_HOME/omarchy-setup/features.yml:

  features: {<id>: true|false, ...}
  apps: {<category>: {installed: [<option id>, ...], default: <option id>}}
  webapps: {engine: none|firefox|chromium|brave}
"""
import json
import os
import re
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "features.yml"
CHOICES = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "omarchy-setup" / "features.yml"
# Tags that aren't features: always-on plays, and the app plays.
STRUCTURAL_TAGS = {"always", "never", "apps"}


def load_catalog():
    with open(CATALOG) as f:
        return yaml.safe_load(f)


def load_choices():
    if CHOICES.exists():
        with open(CHOICES) as f:
            return yaml.safe_load(f) or {}
    return {}


def as_list(value):
    return value if isinstance(value, list) else [value]


def option_label(option):
    source = {"pacman": "native", "aur": "AUR", "flatpak": "Flatpak", "bundle": "Launcher"}[option["source"]]
    extras = [source]
    if option.get("stock"):
        extras.append("stock")
    return f"{option['label']} ({' · '.join(extras)})"


def resolve(catalog, choices):
    """Catalog defaults overlaid with the choices; derived requirements applied."""
    chosen_features = choices.get("features") or {}
    features = {f["id"]: bool(chosen_features.get(f["id"], f["default"])) for f in catalog["features"]}
    for f in catalog["features"]:
        if f.get("hidden"):
            features[f["id"]] = True

    chosen_apps = choices.get("apps") or {}
    apps = {}
    for category in catalog["apps"]:
        ids = [o["id"] for o in category["options"]]
        chosen = chosen_apps.get(category["id"]) or {}
        installed = chosen.get("installed")
        if installed is None:
            installed = [o["id"] for o in category["options"] if o.get("installed")]
        installed = [i for i in ids if i in installed]
        # Options that can't be removed stay installed.
        installed += [o["id"] for o in category["options"] if o.get("keep") and o["id"] not in installed]
        entry = {"installed": [i for i in ids if i in installed]}
        if "default" in category:
            default = chosen.get("default", category["default"])
            if default not in entry["installed"]:
                default = entry["installed"][0] if entry["installed"] else None
            entry["default"] = default
        apps[category["id"]] = entry

    # Any Flatpak option needs the Flatpak base.
    if any(
        o["source"] in ("flatpak", "bundle") and o["id"] in apps[c["id"]]["installed"]
        for c in catalog["apps"]
        for o in c["options"]
    ):
        features["flatpak"] = True
    return features, apps


WEBAPPS_ENGINE_LABELS = {
    "none": "Keep Omarchy's native web apps",
    "firefox": "Firefox Taskbar Tabs",
    "chromium": "Chromium PWAs",
    "brave": "Brave PWAs",
}


def browser_options(catalog):
    for category in catalog["apps"]:
        if category["id"] == "browser":
            return category["options"]
    return []


def browser_engine(catalog, option_id):
    for option in browser_options(catalog):
        if option["id"] == option_id:
            return option.get("engine", "none")
    return "none"


def webapps_engines(catalog, installed_ids):
    """The engines the installed browsers can rebuild Omarchy's web apps with."""
    engines = []
    for option in browser_options(catalog):
        engine = option.get("engine", "none")
        if option["id"] in installed_ids and engine != "none" and engine not in engines:
            engines.append(engine)
    return engines


def pick_webapps_engine(catalog, installed_ids, default_id, choices):
    """The chosen engine, or the default browser's own when unchosen."""
    available = webapps_engines(catalog, installed_ids)
    chosen = (choices.get("webapps") or {}).get("engine")
    if chosen is not None:
        return chosen
    engine = browser_engine(catalog, default_id)
    return engine if engine in available else "none"


def resolve_webapps_engine(catalog, apps, choices):
    return pick_webapps_engine(
        catalog, apps["browser"]["installed"], apps["browser"].get("default"), choices
    )


def webapps_engine_errors(catalog, apps, choices):
    engine = resolve_webapps_engine(catalog, apps, choices)
    available = ["none"] + webapps_engines(catalog, apps["browser"]["installed"])
    if engine not in available:
        return [
            f"web apps engine {engine} needs one of these browsers installed: "
            f"{', '.join(e for e in available if e != 'none')}"
        ]
    return []


def requirement_errors(catalog, features, apps):
    errors = []
    for f in catalog["features"]:
        if not features[f["id"]]:
            continue
        for req in f.get("requires", []):
            if req.startswith("app:"):
                _, category, option = req.split(":")
                if option not in apps[category]["installed"]:
                    errors.append(f"{f['id']} needs {option} installed ({category})")
            elif not features.get(req):
                errors.append(f"{f['id']} needs {req}")
    for category in catalog["apps"]:
        if category["id"] == "browser" and not apps["browser"]["installed"]:
            errors.append("at least one web browser must stay installed")
        if "default" in category and apps[category["id"]]["installed"] and not apps[category["id"]].get("default"):
            errors.append(f"{category['id']} needs a default")
    return errors


def package_states(catalog, apps):
    """One desired state per package, Flatpak or bundle, across categories.

    An option shared by several categories (ArtCraft) is wanted when any of
    them has it installed.
    """
    states = {}
    for category in catalog["apps"]:
        for o in category["options"]:
            key = (o["source"], json.dumps(as_list(o.get("package") or o.get("flatpak") or o.get("bundle"))))
            wanted = o["id"] in apps[category["id"]]["installed"]
            prev = states.get(key)
            states[key] = {
                "source": o["source"],
                "names": as_list(o.get("package") or o.get("flatpak") or o.get("bundle")),
                "state": "present" if wanted or (prev and prev["state"] == "present") else "absent",
                "keep": bool(o.get("keep")) or bool(prev and prev["keep"]),
            }
    return list(states.values())


def cmd_resolve(phase, out):
    catalog, choices = load_catalog(), load_choices()
    # `just apply <id>...`: those features on for this run only.
    forced = os.environ.get("OMARCHY_SETUP_ENABLE", "").split()
    unknown = [i for i in forced if i not in {f["id"] for f in catalog["features"]} and i != "apps"]
    if unknown:
        sys.exit(f"Unknown feature(s): {' '.join(unknown)} (see features.yml)")
    if forced:
        choices = dict(choices)
        choices["features"] = {**(choices.get("features") or {}), **{i: True for i in forced if i != "apps"}}
    features, apps = resolve(catalog, choices)
    errors = requirement_errors(catalog, features, apps) + webapps_engine_errors(catalog, apps, choices)
    if errors:
        sys.exit("Feature choices don't fit together:\n  " + "\n  ".join(errors) + "\nRun `just configure` to fix them.")
    installed = sorted({i for entry in apps.values() for i in entry["installed"]})
    data = {
        "features_resolved": True,
        "features": features,
        "apps": apps,
        "webapps_engine": resolve_webapps_engine(catalog, apps, choices),
        "apps_installed": installed,
        "apps_packages": package_states(catalog, apps),
        # Each category's options by id, for what the plays need to know
        # about them (desktop ids, browser engine, ...).
        "apps_catalog": {c["id"]: {o["id"]: o for o in c["options"]} for c in catalog["apps"]},
    }
    Path(out).parent.mkdir(parents=True, exist_ok=True)
    with open(out, "w") as f:
        json.dump(data, f, indent=2)
    tags = ["always", "apps"]
    for f in catalog["features"]:
        if phase not in f["phases"]:
            continue
        if features[f["id"]] or f.get("revert"):
            tags.append(f["id"])
    print(",".join(tags))


def play_tags():
    """Every tag used in playbooks/{system,user}/*.yml and the entry points."""
    tags = {}
    files = sorted((ROOT / "playbooks").glob("*/*.yml")) + sorted((ROOT / "playbooks").glob("*/apps/*.yml"))
    for path in files:
        if path.parent.name == "tasks" or "tasks" in path.parts:
            continue
        for line in path.read_text().splitlines():
            m = re.match(r"^\s*tags:\s*\[(.*)\]", line)
            if m:
                for tag in m.group(1).split(","):
                    tags.setdefault(tag.strip(), set()).add(str(path.relative_to(ROOT)))
    return tags


def cmd_check():
    catalog = load_catalog()
    problems = []
    ids = [f["id"] for f in catalog["features"]]
    groups = catalog["groups"]
    for f in catalog["features"]:
        for key in ("id", "group", "title", "effect", "phases", "default", "revert"):
            if key not in f:
                problems.append(f"feature {f.get('id', '?')}: missing {key}")
        if f.get("group") not in groups:
            problems.append(f"feature {f['id']}: unknown group {f.get('group')}")
        for req in f.get("requires", []):
            if req.startswith("app:"):
                _, category, option = req.split(":")
                cats = {c["id"]: c for c in catalog["apps"]}
                if category not in cats or option not in [o["id"] for o in cats[category]["options"]]:
                    problems.append(f"feature {f['id']}: unknown requirement {req}")
            elif req not in ids:
                problems.append(f"feature {f['id']}: unknown requirement {req}")
    if len(ids) != len(set(ids)):
        problems.append("duplicate feature ids")
    for category in catalog["apps"]:
        opt_ids = [o["id"] for o in category["options"]]
        if len(opt_ids) != len(set(opt_ids)):
            problems.append(f"apps {category['id']}: duplicate option ids")
        if "default" in category and category["default"] not in opt_ids:
            problems.append(f"apps {category['id']}: default {category['default']} isn't an option")
        for o in category["options"]:
            if o["source"] not in ("pacman", "aur", "flatpak", "bundle"):
                problems.append(f"apps {category['id']}/{o['id']}: unknown source {o['source']}")
            if "engine" in o and o["engine"] not in WEBAPPS_ENGINE_LABELS:
                problems.append(f"apps {category['id']}/{o['id']}: unknown web apps engine {o['engine']}")
    tags = play_tags()
    for i in ids:
        if i not in tags:
            problems.append(f"feature {i}: no play is tagged with it")
    for tag, where in sorted(tags.items()):
        if tag not in ids and tag not in STRUCTURAL_TAGS:
            problems.append(f"tag {tag} ({', '.join(sorted(where))}) isn't a feature in features.yml")
    features, apps = resolve(catalog, {})
    problems += [f"defaults: {e}" for e in requirement_errors(catalog, features, apps)]
    problems += [f"defaults: {e}" for e in webapps_engine_errors(catalog, apps, {})]
    if problems:
        sys.exit("features.yml:\n  " + "\n  ".join(problems))
    print("Feature catalog OK.")


def cmd_doc():
    catalog = load_catalog()
    out = [
        "# Features",
        "",
        "<!-- Generated from features.yml by `just docs`. Don't edit by hand. -->",
        "",
        "What each automation does to a stock Omarchy 4.5, and whether it is on",
        "until you choose otherwise with `just configure`. **Revert**: turning it",
        "off undoes it on the next run; otherwise turning it off only stops",
        "managing it. fish as every account's login shell isn't a feature: it is",
        "always applied.",
        "",
    ]
    for group, title in catalog["groups"].items():
        rows = [f for f in catalog["features"] if f["group"] == group and not f.get("hidden")]
        if not rows:
            continue
        out += [f"## {title}", "", "| Feature | Tag | Effect | Phases | Default | Revert |", "|---|---|---|---|---|---|"]
        for f in rows:
            out.append(
                f"| {f['title']} | `{f['id']}` | {f['effect']} | {', '.join(f['phases'])} | "
                f"{'on' if f['default'] else 'off'} | {'yes' if f['revert'] else 'no'} |"
            )
        out.append("")
    out += [
        "## Apps",
        "",
        "Each category lists its installation alternatives; several can be",
        "installed side by side. Options are declarative: one left out is",
        "uninstalled, Omarchy's own (**stock**) included, unless it is marked",
        "as kept. ★ marks what is installed by default, and the default app",
        "where the category has one.",
        "",
    ]
    for category in catalog["apps"]:
        out += [f"### {category['title']}", ""]
        if category.get("role"):
            out += [f"Default app: {category['role']}.", ""]
        out += ["| Option | Source | Notes |", "|---|---|---|"]
        for o in category["options"]:
            star = " ★" if o.get("installed") else ""
            default = " (default)" if category.get("default") == o["id"] else ""
            name = ", ".join(f"`{n}`" for n in as_list(o.get("package") or o.get("flatpak") or o.get("bundle")))
            notes = []
            if o.get("stock"):
                notes.append("stock")
            if o.get("keep"):
                notes.append("kept")
            if o.get("note"):
                notes.append(o["note"])
            out.append(f"| {o['label']}{star}{default} | {o['source']} {name} | {'; '.join(notes)} |")
        out.append("")
    print("\n".join(out).rstrip() + "\n", end="")


# --- data for scripts/configure.sh ------------------------------------------
# Lines are tab-separated; configure.sh reads them with `IFS=$'\t' read`.


def menu_label(text):
    """gum choose --selected matches labels and splits its list on commas."""
    return text.replace(", ", " / ").replace(",", " /").replace("|", "/")


def menu(args):
    catalog, choices = load_catalog(), load_choices()
    features, apps = resolve(catalog, choices)
    what = args[0]
    if what == "groups":
        for group, title in catalog["groups"].items():
            if any(f["group"] == group and not f.get("hidden") for f in catalog["features"]):
                print(f"{group}\t{title}")
    elif what == "features":
        admin = args[2] == "1" if len(args) > 2 else True
        for f in catalog["features"]:
            if f["group"] != args[1] or f.get("hidden"):
                continue
            if not admin and "user" not in f["phases"]:
                continue
            mark = " ⟲" if f["revert"] else ""
            requires = ",".join(f.get("requires", []))
            print(f"{f['id']}\t{menu_label(f['title'] + mark)}\t{int(features[f['id']])}\t{f['effect']}\t{requires}")
    elif what == "categories":
        for c in catalog["apps"]:
            print(f"{c['id']}\t{c['title']}\t{int('default' in c)}\t{c.get('role', '')}")
    elif what == "options":
        category = next(c for c in catalog["apps"] if c["id"] == args[1])
        for o in category["options"]:
            print(
                f"{o['id']}\t{menu_label(option_label(o))}\t{int(o['id'] in apps[category['id']]['installed'])}"
                f"\t{int(bool(o.get('keep')))}\t{int(bool(o.get('stock')))}\t{o.get('note', '')}"
            )
    elif what == "default":
        print(apps[args[1]].get("default") or "")
    elif what == "webapps-engines":
        # The engines the installed browsers (args[1], comma-separated; the
        # saved selection when omitted) can rebuild Omarchy's web apps with.
        installed = args[1].split(",") if len(args) > 1 else apps["browser"]["installed"]
        for engine in ["none"] + webapps_engines(catalog, installed):
            print(f"{engine}\t{menu_label(WEBAPPS_ENGINE_LABELS[engine])}")
    elif what == "webapps-engine":
        # The engine to preselect for a (possibly new) browser selection:
        # args[1] = default browser id, args[2] = installed ids.
        if len(args) > 2:
            print(pick_webapps_engine(catalog, args[2].split(","), args[1], choices))
        else:
            print(resolve_webapps_engine(catalog, apps, choices))
    elif what == "save":
        # stdin: JSON {"features": {...}, "apps": {...}, "webapps": {...}}
        # (only what the menu asked about); merged into the choices file.
        new = json.load(sys.stdin)
        merged = {
            "features": dict(choices.get("features") or {}),
            "apps": dict(choices.get("apps") or {}),
            "webapps": dict(choices.get("webapps") or {}),
        }
        merged["features"].update(new.get("features", {}))
        merged["apps"].update(new.get("apps", {}))
        merged["webapps"].update(new.get("webapps") or {})
        f2, a2 = resolve(catalog, merged)
        errors = requirement_errors(catalog, f2, a2) + webapps_engine_errors(catalog, a2, merged)
        if errors:
            print("\n".join(errors), file=sys.stderr)
            sys.exit(3)
        CHOICES.parent.mkdir(parents=True, exist_ok=True)
        with open(CHOICES, "w") as f:
            f.write("# Written by `just configure` (scripts/configure.sh). Catalog: features.yml.\n")
            yaml.safe_dump(merged, f, sort_keys=True, allow_unicode=True)
    elif what == "summary":
        # stdin: same JSON as save; prints what changes against the current
        # resolved selection.
        new = json.load(sys.stdin)
        merged = {
            "features": dict(choices.get("features") or {}),
            "apps": dict(choices.get("apps") or {}),
            "webapps": dict(choices.get("webapps") or {}),
        }
        merged["features"].update(new.get("features", {}))
        merged["apps"].update(new.get("apps", {}))
        merged["webapps"].update(new.get("webapps") or {})
        f2, a2 = resolve(catalog, merged)
        titles = {f["id"]: f for f in catalog["features"]}
        for fid, on in f2.items():
            if on != features[fid]:
                verb = "turn on" if on else ("revert" if titles[fid]["revert"] else "stop managing")
                print(f"- {verb}: {titles[fid]['title']}")
        for c in catalog["apps"]:
            labels = {o["id"]: option_label(o) for o in c["options"]}
            before, after = set(apps[c["id"]]["installed"]), set(a2[c["id"]]["installed"])
            for i in sorted(after - before):
                print(f"- install: {labels[i]}")
            for i in sorted(before - after):
                print(f"- uninstall: {labels[i]}")
            if a2[c["id"]].get("default") != apps[c["id"]].get("default"):
                print(f"- {c['title']}, default: {labels.get(a2[c['id']].get('default'), 'none')}")
        engine_before = resolve_webapps_engine(catalog, apps, choices)
        engine_after = resolve_webapps_engine(catalog, a2, merged)
        if engine_after != engine_before:
            print(f"- web apps: {WEBAPPS_ENGINE_LABELS[engine_after]}")
    else:
        sys.exit(f"unknown menu query: {what}")


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    cmd, args = sys.argv[1], sys.argv[2:]
    if cmd == "resolve" and len(args) == 2:
        cmd_resolve(*args)
    elif cmd == "check":
        cmd_check()
    elif cmd == "doc":
        cmd_doc()
    elif cmd == "menu" and args:
        menu(args)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
