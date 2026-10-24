#!/usr/bin/env bash
# `just configure`: choose, with gum, which apps (per category, with their
# installation alternatives) and which features this setup applies for you.
# The catalog is features.yml (docs/features.md); the choices go to
# ~/.config/omarchy-setup/features.yml, which `just setup`, `just system`
# and `just user` apply. Starts from your current choices (or the catalog's
# defaults), shows what would change and offers to apply it right away.
#
# Administrators choose every feature; other users only those with a user
# phase (the rest is the machine's, chosen by an administrator).
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")/.."

menu() { python3 scripts/features.py menu "$@"; }

admin=0
id -nG | tr ' ' '\n' | grep -qx wheel && admin=1

# Picks from gum choose come back as ids (label|id, --label-delimiter);
# --selected matches labels.
choose_many() { # header, then "label|id" lines on stdin; preselected labels in $selected
    local header=$1
    gum choose --no-limit --height=15 --header="$header" --label-delimiter='|' \
        --selected="$selected" || true
}

gum style --border=rounded --padding="0 2" --margin="1 0" \
    "omarchy-setup — what to apply" \
    "Space toggles, Enter confirms. Unchecked apps are uninstalled; ⟲ marks" \
    "features whose changes are undone when unchecked."

declare -A app_installed app_default
declare -A feature_on

# --- Apps ------------------------------------------------------------------
# Lists are read into arrays first: a loop reading from a pipe would share
# its stdin with gum, which then eats the rest of the list.
mapfile -t categories < <(menu categories)
for category_line in "${categories[@]}"; do
    IFS=$'\t' read -r cat title has_default role <<<"$category_line"
    options=() selected="" kept=() stock=()
    declare -A label_of=()
    mapfile -t option_lines < <(menu options "$cat")
    for option_line in "${option_lines[@]}"; do
        IFS=$'\t' read -r id label installed keep is_stock note <<<"$option_line"
        [[ $keep == 1 ]] && { label+=" (kept)"; kept+=("$id"); }
        [[ $is_stock == 1 ]] && stock+=("$id")
        options+=("$label|$id")
        label_of[$id]=$label
        [[ $installed == 1 ]] && selected+="${selected:+,}$label"
        [[ -n $note ]] && echo "  $label: $note" >&2
    done

    picked=$(printf '%s\n' "${options[@]}" | choose_many "$title — which to install?")
    mapfile -t ids < <(printf '%s\n' "$picked" | sed '/^$/d')
    # Kept options stay whatever was picked.
    for k in "${kept[@]}"; do
        printf '%s\n' "${ids[@]}" | grep -qx "$k" || ids+=("$k")
    done

    # Unchecking one of Omarchy's own apps removes it: ask first.
    for s in "${stock[@]}"; do
        if ! printf '%s\n' "${ids[@]}" | grep -qx "$s" \
            && printf '%s\n' "${option_lines[@]}" | awk -F'\t' -v id="$s" '$1 == id && $3 == 1 {found = 1} END {exit !found}'; then
            if ! gum confirm "Uninstall ${label_of[$s]}, which ships with Omarchy?" --default=false; then
                ids+=("$s")
            fi
        fi
    done

    app_installed[$cat]=$(printf '%s\n' "${ids[@]}" | sed '/^$/d' | paste -sd,)

    if [[ $has_default == 1 && ${#ids[@]} -gt 0 ]]; then
        current=$(menu default "$cat")
        if [[ ${#ids[@]} -eq 1 ]]; then
            app_default[$cat]=${ids[0]}
        else
            default_options=()
            for i in "${ids[@]}"; do default_options+=("${label_of[$i]}|$i"); done
            app_default[$cat]=$(gum choose --header="$title — $role" --label-delimiter='|' \
                --selected="${label_of[$current]:-}" "${default_options[@]}")
        fi
    fi
done

# --- Features --------------------------------------------------------------
mapfile -t groups < <(menu groups)
for group_line in "${groups[@]}"; do
    IFS=$'\t' read -r group title <<<"$group_line"
    options=() selected="" rows=()
    mapfile -t feature_lines < <(menu features "$group" "$admin")
    for feature_line in "${feature_lines[@]}"; do
        IFS=$'\t' read -r id label on effect <<<"$feature_line"
        options+=("$label|$id")
        rows+=("| $label | $effect |")
        [[ $on == 1 ]] && selected+="${selected:+,}$label"
    done
    [[ ${#options[@]} -gt 0 ]] || continue
    printf '%s\n' "## $title" "" "| Feature | Effect |" "|---|---|" "${rows[@]}" | gum format >&2
    picked=$(printf '%s\n' "${options[@]}" | choose_many "$title — which to apply?")
    for opt in "${options[@]}"; do
        id=${opt##*|}
        if printf '%s\n' "$picked" | grep -qx "$id"; then feature_on[$id]=true; else feature_on[$id]=false; fi
    done
done

# --- Save ------------------------------------------------------------------
json=$(
    {
        for id in "${!feature_on[@]}"; do printf 'f\t%s\t%s\n' "$id" "${feature_on[$id]}"; done
        for cat in "${!app_installed[@]}"; do printf 'a\t%s\t%s\t%s\n' "$cat" "${app_installed[$cat]}" "${app_default[$cat]:-}"; done
    } | python3 -c '
import json, sys
out = {"features": {}, "apps": {}}
for line in sys.stdin.read().splitlines():
    kind, key, *rest = line.split("\t")
    if kind == "f":
        out["features"][key] = rest[0] == "true"
    else:
        installed, default = rest[0], rest[1] if len(rest) > 1 else ""
        entry = {"installed": [i for i in installed.split(",") if i]}
        if default:
            entry["default"] = default
        out["apps"][key] = entry
print(json.dumps(out))
'
)

changes=$(menu summary <<<"$json")
if [[ -z $changes ]]; then
    gum style "No changes."
else
    printf '%s\n' "## Changes" "" "$changes" | gum format
fi

if ! errors=$(menu save <<<"$json" 2>&1); then
    gum style --foreground=1 "Not saved — these choices don't fit together:" "$errors"
    echo "Run \`just configure\` again." >&2
    exit 1
fi
gum style "Saved to ${XDG_CONFIG_HOME:-$HOME/.config}/omarchy-setup/features.yml."

if gum confirm "Apply now?"; then
    if [[ $admin == 1 ]]; then
        just system user
    else
        just user
    fi
fi
