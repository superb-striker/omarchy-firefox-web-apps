#!/bin/bash

set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
config_home=${XDG_CONFIG_HOME:-$HOME/.config}
state_home=${XDG_STATE_HOME:-$HOME/.local/state}
state_dir="$state_home/omarchy-firefox-web-apps"
backup_dir="$state_dir/backups"
timestamp=$(date +%Y%m%d-%H%M%S)

launcher="$HOME/.local/bin/omarchy-launch-webapp"
remover="$HOME/.local/bin/omarchy-webapp-remove"
environment_file="$config_home/environment.d/90-omarchy-firefox-web-apps.conf"
hyprland_file="$config_home/hypr/hyprland.lua"

hypr_begin="-- BEGIN omarchy-firefox-web-apps: user launcher path"
hypr_end="-- END omarchy-firefox-web-apps: user launcher path"

if [[ ! -f $hyprland_file ]]; then
  echo "Hyprland config not found: $hyprland_file" >&2
  exit 1
fi
command -v python3 >/dev/null
mkdir -p "$HOME/.local/bin" "$config_home/environment.d" "$backup_dir"

if [[ -e $launcher && ! -e $state_dir/launcher.backup && ! -e $state_dir/launcher.created ]]; then
  launcher_backup="$backup_dir/omarchy-launch-webapp.$timestamp"
  cp -a "$launcher" "$launcher_backup"
  printf '%s\n' "$launcher_backup" >"$state_dir/launcher.backup"
elif [[ ! -e $launcher && ! -e $state_dir/launcher.created ]]; then
  : >"$state_dir/launcher.created"
fi

install -m 0755 "$project_dir/files/omarchy-launch-webapp" "$launcher"

if [[ -e $remover && ! -e $state_dir/remover.backup && ! -e $state_dir/remover.created ]]; then
  remover_backup="$backup_dir/omarchy-webapp-remove.$timestamp"
  cp -a "$remover" "$remover_backup"
  printf '%s\n' "$remover_backup" >"$state_dir/remover.backup"
elif [[ ! -e $remover && ! -e $state_dir/remover.created ]]; then
  : >"$state_dir/remover.created"
fi

install -m 0755 "$project_dir/files/omarchy-webapp-remove" "$remover"

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

python3 "$project_dir/scripts/native-install.py" install

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
Popup bridge installed. In Firefox, open about:debugging#/runtime/this-firefox,
choose Load Temporary Add-on, and select:
  $project_dir/extension/manifest.json
Load this in just the profile whose existing session you want to use.
Unsigned temporary add-ons must be loaded again after restarting Firefox.
EOF
