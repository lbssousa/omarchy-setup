# Per-user settings

One `<login name>.yml` per person, loaded by `scripts/run-phase.sh` (every
`just` recipe) as extra vars, so it overrides `group_vars/all/*` for that
user only. Which features and apps apply is chosen separately, with
`just configure` (saved in `~/.config/omarchy-setup/features.yml`). Everything is optional; a user without a file gets the
defaults. Typical keys:

| Key | What |
|---|---|
| `webapps` | Omarchy's web apps, kept native or rebuilt with the browser chosen in `just configure`: Firefox Taskbar Tabs or Brave/Chromium PWAs (`user/apps/webapps.yml`) |
| `omarchy_plugins` | shell plugins (default: this machine's list) |
| `omarchy_text_size_px`, `omarchy_shell_font_px`, `omarchy_monitor_scale`, `omarchy_system_ui_font_pt` | text size and scale |
| `password_hypr_keybind`, `bitwarden_floating` | the default password manager's key, Bitwarden's window |
| `omaraptor_auto_day_theme`, `omaraptor_auto_night_theme` | automatic themes |

Accounts themselves (login, admin, shell) are declared in
`group_vars/all/users.yml`. Personal data stays out of the repository, in
`~/.config/omarchy-setup/local.yml`, loaded after this file: git identity
(`git_user_name`, `git_user_email`), the rclone account
(`rclone_gdrive_email`) and, for the administrator, the accounts' full names
(`omarchy_user_full_names`). Template: `local.example.yml`.
