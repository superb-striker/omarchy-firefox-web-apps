#!/bin/bash

set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
config_home=${XDG_CONFIG_HOME:-$HOME/.config}
state_home=${XDG_STATE_HOME:-$HOME/.local/state}
state_dir="$state_home/omarchy-firefox-web-apps"

launcher="$HOME/.local/bin/omarchy-launch-webapp"
environment_file="$config_home/environment.d/90-omarchy-firefox-web-apps.conf"
hyprland_file="$config_home/hypr/hyprland.lua"
firefox_root="$config_home/mozilla/firefox"

remove_managed_block() {
  local file=$1 begin=$2 end=$3 temporary
  [[ -f $file ]] || return 0
  temporary=$(mktemp)
  awk -v begin="$begin" -v end="$end" '
    $0 == begin { managed = 1; next }
    $0 == end { managed = 0; next }
    !managed { print }
  ' "$file" >"$temporary"
  cat "$temporary" >"$file"
  rm -f "$temporary"
}

if [[ -f $state_dir/launcher.backup ]]; then
  launcher_backup=$(cat "$state_dir/launcher.backup")
  if [[ -f $launcher_backup ]]; then
    install -m 0755 "$launcher_backup" "$launcher"
  fi
elif [[ -f $state_dir/launcher.created ]] && \
     cmp -s "$launcher" "$project_dir/files/omarchy-launch-webapp"; then
  rm -f "$launcher"
fi

rm -f "$environment_file"
remove_managed_block "$hyprland_file" \
  "-- BEGIN omarchy-firefox-web-apps: user launcher path" \
  "-- END omarchy-firefox-web-apps: user launcher path"

profile_relative=$(sed -n 's/^Default=//p' "$firefox_root/installs.ini" 2>/dev/null | head -1)
if [[ -n $profile_relative ]]; then
  remove_managed_block "$firefox_root/$profile_relative/user.js" \
    "// BEGIN omarchy-firefox-web-apps: Firefox Taskbar Tabs" \
    "// END omarchy-firefox-web-apps: Firefox Taskbar Tabs"
fi

if command -v hyprctl >/dev/null 2>&1 && [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
  hyprctl reload
  config_errors=$(hyprctl configerrors)
  if [[ -n $config_errors ]]; then
    echo "$config_errors" >&2
    exit 1
  fi
fi

rm -rf "$state_dir"

echo "omarchy-firefox-web-apps removed. Restart Firefox to finish disabling Taskbar Tabs."
