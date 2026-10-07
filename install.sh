#!/bin/bash

set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
config_home=${XDG_CONFIG_HOME:-$HOME/.config}
state_home=${XDG_STATE_HOME:-$HOME/.local/state}
state_dir="$state_home/omarchy-firefox-web-apps"
backup_dir="$state_dir/backups"
timestamp=$(date +%Y%m%d-%H%M%S)

launcher="$HOME/.local/bin/omarchy-launch-webapp"
environment_file="$config_home/environment.d/90-omarchy-firefox-web-apps.conf"
hyprland_file="$config_home/hypr/hyprland.lua"
firefox_root="$config_home/mozilla/firefox"

hypr_begin="-- BEGIN omarchy-firefox-web-apps: user launcher path"
hypr_end="-- END omarchy-firefox-web-apps: user launcher path"
firefox_begin="// BEGIN omarchy-firefox-web-apps: Firefox Taskbar Tabs"

mkdir -p "$HOME/.local/bin" "$config_home/environment.d" "$backup_dir"

if [[ -e $launcher && ! -e $state_dir/launcher.backup ]]; then
  launcher_backup="$backup_dir/omarchy-launch-webapp.$timestamp"
  cp -a "$launcher" "$launcher_backup"
  printf '%s\n' "$launcher_backup" >"$state_dir/launcher.backup"
elif [[ ! -e $launcher && ! -e $state_dir/launcher.created ]]; then
  : >"$state_dir/launcher.created"
fi

install -m 0755 "$project_dir/files/omarchy-launch-webapp" "$launcher"
cat >"$environment_file" <<'EOF'
PATH=${HOME}/.local/bin:${PATH}
EOF

if [[ ! -f $hyprland_file ]]; then
  echo "Hyprland config not found: $hyprland_file" >&2
  exit 1
fi

if ! grep -Fqx -- "$hypr_begin" "$hyprland_file"; then
  cp -a "$hyprland_file" "$backup_dir/hyprland.lua.$timestamp"
  cat >>"$hyprland_file" <<'EOF'

-- BEGIN omarchy-firefox-web-apps: user launcher path
-- Prefer user command overrides for actions dispatched by Omarchy.
do
  local user_bin = (os.getenv("HOME") or "") .. "/.local/bin"
  local kept = {}
  for entry in (os.getenv("PATH") or "/usr/local/bin:/usr/bin"):gmatch("[^:]+") do
    if entry ~= user_bin then table.insert(kept, entry) end
  end
  table.insert(kept, 1, user_bin)
  hl.env("PATH", table.concat(kept, ":"))
end
-- END omarchy-firefox-web-apps: user launcher path
EOF
fi

profile_relative=$(sed -n 's/^Default=//p' "$firefox_root/installs.ini" 2>/dev/null | head -1)
profile="$firefox_root/$profile_relative"
user_js="$profile/user.js"

if [[ -z $profile_relative || ! -d $profile ]]; then
  echo "Could not find Firefox's active profile from $firefox_root/installs.ini" >&2
  exit 1
fi

if [[ ! -f $user_js ]] || ! grep -Fqx -- "$firefox_begin" "$user_js"; then
  [[ ! -f $user_js ]] || cp -a "$user_js" "$backup_dir/user.js.$timestamp"
  printf '\n' >>"$user_js"
  cat "$project_dir/files/firefox-user.js" >>"$user_js"
fi

if command -v hyprctl >/dev/null 2>&1 && [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
  hyprctl reload
  config_errors=$(hyprctl configerrors)
  if [[ -n $config_errors ]]; then
    echo "$config_errors" >&2
    echo "Hyprland reported configuration errors; inspect the backup in $backup_dir" >&2
    exit 1
  fi
fi

cat <<EOF
omarchy-firefox-web-apps installed.

Restart Firefox once so it reads:
  $user_js

Then open Ctrl+Space -> Learn -> Omarchy.
EOF
