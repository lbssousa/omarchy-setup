#!/usr/bin/env bash
# Installs `just` via pacman if it isn't already available — the only
# prerequisite for running any recipe in this repo. Other dependencies
# (ansible, community.general) are resolved by the Justfile itself on
# first run.
set -euo pipefail

if command -v just >/dev/null; then
    echo "just is already installed ($(command -v just))."
else
    echo "just not found; installing via pacman..."
    sudo pacman -S --needed --noconfirm just
fi

echo "Done. Run 'just setup' to apply the automations (or 'just --list' to see available recipes)."
