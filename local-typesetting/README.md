# local-typesetting

Automates installing a typesetting and music-engraving toolchain **directly on this
machine, with no containers**:

- [TeX Live](https://tug.org/texlive/) — installed under `/opt/texlive` via the official TUG
  network installer (`scheme-full` by default).
- [LilyPond](https://lilypond.org/) — installed under `/opt/lilypond/<version>`, from the
  official precompiled binary (x86_64 glibc — this machine).
- [Gregorio](https://gregorio-project.github.io/) — built from source from
  [lbssousa/gregorio](https://github.com/lbssousa/gregorio) and wired into TeX Live
  (`gregoriotex`), at the same commit pinned by `gregorio_ref` in
  `../group_vars/all/main.yml`.

TeX Live's bundled fonts are registered with fontconfig at install time, so LilyPond,
Inkscape, and any other fontconfig-aware application on this machine can use them — the same
font integration [lbssousa/distrobox-typesetting](https://github.com/lbssousa/distrobox-typesetting)'s
container image gets. In fact, every install script here (`scripts/`) is adapted from that
project, minus the container/distrobox layer: same OS-detection helpers, same TeX Live
installer profile, same LilyPond/Gregorio build logic, just run as root on the host (via
`run0 --empower`, see `../run-empowered.sh`) instead of as root during a container image
build.

This replaces omarchy-setup's old `playbooks/tex.yml` (AUR `texlive-installer` into
`/usr/local/texlive`, TeX Live's own package selection) — retired because it couldn't get TeX
Live's fonts onto fontconfig without ad hoc plumbing, and only tracked a hand-picked package
list instead of a full scheme.

## Usage

```sh
cp local-typesetting.env.example local-typesetting.env   # optional, edit as needed
./install-typesetting.sh
```

The script needs root and runs every install step as one privileged script under a single
`run0 --empower` (see `../run-empowered.sh`) — expect one polkit prompt (fingerprint or
password) for the whole install, not one per step. Or, from the repo root:

```sh
just typesetting
```

Configuration is resolved in this order (later wins): built-in defaults →
`local-typesetting.env` (current directory, then this project's directory) → CLI flags. Run
`./install-typesetting.sh --help` for the full flag list. Options:

| Option | Config key | CLI flag | Default |
|---|---|---|---|
| TeX Live release | `TEXLIVE_RELEASE` | `--texlive-release` | `latest` |
| TeX Live scheme | `TEXLIVE_SCHEME` | `--texlive-scheme` | `full` |
| Extra TeX Live packages | `TEXLIVE_PACKAGES` | `--texlive-packages` | (none — `full` already covers it) |
| TeX Live mirror | `TEXLIVE_MIRROR` | `--texlive-mirror` | `https://linorg.usp.br` |
| TeX Live download cache | `TEXLIVE_CACHE_DIR` | `--texlive-cache-dir` | disabled |
| LilyPond version | `LILYPOND_VERSION` | `--lilypond-version` | `latest` (resolved via LilyPond's GitLab releases) |
| Gregorio repository | `GREGORIO_REPOSITORY` | `--gregorio-repository` | `lbssousa/gregorio` |
| Gregorio ref | `GREGORIO_REF` | `--gregorio-ref` | the commit pinned in `group_vars/all/main.yml`'s `gregorio_ref` |

`scheme-full` is a large (~7 GB), slow install, but it means never having to hand-sync a
package list again — it already includes `gregoriotex`, `musixtex`, and every other CTAN
package the old `playbooks/tex.yml` used to pick individually for the AISCGre-BR projects.
Pass `--texlive-scheme minimal --texlive-packages "..."` for a lighter, faster install if you
don't need everything.

Re-running the script is safe: each install step overwrites its own target directory/version,
and installed binaries are re-symlinked idempotently.

## TeX Live download cache

Installing `scheme-full` downloads several GB, and the run can die half-way if the connection
to the mirror drops. Set `TEXLIVE_CACHE_DIR` (e.g. `/var/cache/omarchy-setup/texlive-downloads`
— must be a path `root` can write to) to keep every downloaded package around, so re-running
the script only fetches what's missing. Downloads are also retried and resumed automatically.
The cache is keyed by each package's checksum, so it stays valid across mirrors and never
serves outdated packages. Entries unused for 30 days are pruned after a successful install.

## Updating

These helpers are installed to `/usr/local/bin` (self-elevating with `run0` when needed):

- `update-texlive` — runs `tlmgr update --self --all`, then refreshes fontconfig's cache.
- `update-lilypond [version]` — rebuilds LilyPond at the given version (defaults to `latest`),
  reusing the same install logic used at initial install.
- `update-gregorio [ref]` — rebuilds Gregorio from `lbssousa/gregorio` at the given ref
  (defaults to the pinned ref above).

The scripts themselves are kept at `/opt/local-typesetting/scripts/` (copied there by
`install-typesetting.sh`) so these helpers keep working without this repo checked out.

## Environment (MANPATH/INFOPATH)

TeX Live's binaries are symlinked into `/usr/local/bin`, already on `PATH` by default on
Arch/Omarchy. Its man/info pages aren't picked up automatically — add to your shell rc if you
want them:

```sh
export MANPATH="/opt/texlive/bin/man:${MANPATH}"
export INFOPATH="/opt/texlive/bin/info:${INFOPATH}"
```

## Project layout

- `install-typesetting.sh` — the CLI script that runs every install step, then deploys the
  `update-*` helpers.
- `local-typesetting.env.example` — configuration template (copy to `local-typesetting.env`,
  gitignored).
- `scripts/` — one install script per component (`install-texlive.sh`, `install-lilypond.sh`,
  `install-gregorio.sh`, `configure-fonts.sh`), plus `scripts/lib/common.sh` (OS-detection and
  package-manager helpers) and `scripts/lib/texlive-cached-download.sh` (the caching/retrying
  downloader `install-texlive.sh` uses). Copied to `/opt/local-typesetting/scripts/` at install
  time so the `update-*` helpers can reuse them later.
- `bin/` — the `update-*` helper scripts, copied into `/usr/local/bin`.

Adapted from [lbssousa/distrobox-typesetting](https://github.com/lbssousa/distrobox-typesetting)
(`scripts/` and `container-bin/`), dropping the Containerfile/distrobox layer and running
directly on the host with `run0` instead.

## Known limitations

- Only tested on Arch/Omarchy (`is_arch_like`, pacman). The other OS branches in
  `scripts/lib/common.sh` and the install scripts are kept from the source project for
  portability but aren't exercised here.
- Only the x86_64 glibc (official precompiled binary) LilyPond install path is exercised on
  this machine; the from-source and distro-package fallbacks exist for other architectures
  (see `scripts/install-lilypond.sh`) but aren't needed or tested here.
