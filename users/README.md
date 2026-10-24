# Per-user settings

One `<login name>.yml` per person, loaded by `scripts/run-phase.sh` (every
`just` recipe) as extra vars, so it overrides `group_vars/all/*` for that
user only. Everything is optional; a user without a file gets the
defaults. Typical keys:

| Key | What |
|---|---|
| `git_user_name`, `git_user_email` | git identity (`user/git-identity.yml`) |
| `rclone_gdrive_email` | Google Drive account to mount (`just rclone-gdrive`) |
| `firefox_taskbar_apps` | Firefox Taskbar Tabs replacing Omarchy's web apps (`user/firefox-taskbar-apps.yml`) |
| `omarchy_plugins` | shell plugins (default: this machine's list) |
| `omarchy_text_size_px`, `omarchy_monitor_scale`, `omarchy_system_ui_font_pt` | text size and scale |
| `bitwarden_hypr_keybind`, `bitwarden_floating` | password manager key and window |
| `omaraptor_auto_day_theme`, `omaraptor_auto_night_theme` | automatic themes |

Accounts themselves (full name, admin, shell) are declared in
`group_vars/all/users.yml`. A machine-local file that shouldn't be
committed can go in `~/.config/omarchy-setup/local.yml`, loaded after this
one.
