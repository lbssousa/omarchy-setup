#!/usr/bin/env python3
"""Adds a patch to Arch's openssh PKGBUILD (playbooks/openssh-askpass.yml).

Usage: patch-pkgbuild.py <PKGBUILD> <patch> <pkgrel-suffix>

Appends the patch to source=() with its checksums, applies it first thing
in prepare(), and appends the suffix to pkgrel (1 -> 1.1). The suffixed
release sorts after the repo's own build of the same version but before
its next rebuild, so pacman -Syu replaces it with the next official
package. Exits 1 if the PKGBUILD doesn't look the way this expects.
"""
import hashlib
import pathlib
import re
import sys

pkgbuild_path, patch_path, suffix = sys.argv[1:4]
pkgbuild = pathlib.Path(pkgbuild_path)
patch = pathlib.Path(patch_path)
text = pkgbuild.read_text()
data = patch.read_bytes()
name = patch.name

if name in text:
    sys.exit(f"{pkgbuild}: already patched")


def sub_once(pattern, repl, flags=0):
    global text
    text, n = re.subn(pattern, repl, text, count=1, flags=flags)
    if n != 1:
        sys.exit(f"{pkgbuild}: no match for {pattern!r}")


sub_once(r"^pkgrel=(\S+)$", lambda m: f"pkgrel={m.group(1)}{suffix}", re.M)
sub_once(r"^(source=\(.*?)\n\)", lambda m: f"{m.group(1)}\n  {name}\n)", re.S | re.M)
for array, algo in (("sha256sums", hashlib.sha256), ("b2sums", hashlib.blake2b)):
    digest = algo(data).hexdigest()
    sub_once(rf"^({array}=\(.*?)\)", lambda m: f"{m.group(1)}\n  '{digest}')", re.S | re.M)
sub_once(
    r"^(prepare\(\) \{\n  cd \$pkgname-\$pkgver\n)",
    lambda m: f"{m.group(1)}  patch -Np1 -i ../{name}\n",
    re.M,
)
pkgbuild.write_text(text)
