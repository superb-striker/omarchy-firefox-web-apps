#!/bin/bash

set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
config_home=${XDG_CONFIG_HOME:-$HOME/.config}
state_home=${XDG_STATE_HOME:-$HOME/.local/state}
state_dir="$state_home/omarchy-firefox-web-apps"

launcher="$HOME/.local/bin/omarchy-launch-webapp"
remover="$HOME/.local/bin/omarchy-webapp-remove"
environment_file="$config_home/environment.d/90-omarchy-firefox-web-apps.conf"
hyprland_file="$config_home/hypr/hyprland.lua"

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

if [[ -f $state_dir/remover.backup ]]; then
  remover_backup=$(cat "$state_dir/remover.backup")
  if [[ -f $remover_backup ]]; then
    install -m 0755 "$remover_backup" "$remover"
  fi
elif [[ -f $state_dir/remover.created ]] && \
     cmp -s "$remover" "$project_dir/files/omarchy-webapp-remove"; then
  rm -f "$remover"
fi

remove_managed_block "$hyprland_file" \
  "-- BEGIN omarchy-firefox-web-apps: user launcher path" \
  "-- END omarchy-firefox-web-apps: user launcher path"

python3 "$project_dir/scripts/native-install.py" uninstall

if command -v hyprctl >/dev/null 2>&1 && [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
  hyprctl reload
  config_errors=$(hyprctl configerrors)
  if [[ -n $config_errors ]]; then
    echo "$config_errors" >&2
    exit 1
  fi
fi

rm -f "$state_dir/launcher.backup" "$state_dir/launcher.created" \
  "$state_dir/remover.backup" "$state_dir/remover.created"

echo "omarchy-firefox-web-apps removed. Remove the Omarchy Firefox Web Apps extension in Firefox."
