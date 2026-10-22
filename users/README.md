# Per-user settings

One `<login name>.yml` per person, loaded by `scripts/run-phase.sh` (every
`just` recipe) as extra vars, so it overrides `group_vars/all/*` for that
user only. Everything is optional; a user without a file gets the
defaults. Typical keys:

| Key | What |
|---|---|
| `git_user_name`, `git_user_email` | git identity (`user/git-identity.yml`) |
| `rclone_gdrive_email` | Google Drive account to mount (`just rclone-gdrive`) |
| `brave_pwa_webapps` | Brave PWAs replacing Omarchy's web apps (`just brave-pwa-webapps`) |
| `brave_omarchy_webapp_containers` | Omarchy web app launchers → Brave containers |
| `omarchy_plugins` | shell plugins (default: this machine's list) |
| `omarchy_text_size_px`, `omarchy_monitor_scale`, `omarchy_system_ui_font_pt` | text size and scale |
| `keepassxc_primary`, `keepassxc_hypr_keybind` | password manager choice and key |
| `omaraptor_auto_day_theme`, `omaraptor_auto_night_theme` | automatic themes |

Accounts themselves (full name, admin, shell) are declared in
`group_vars/all/users.yml`. A machine-local file that shouldn't be
committed can go in `~/.config/omarchy-setup/local.yml`, loaded after this
one.
