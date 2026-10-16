"""Install native host files, preserving originals across repeated installations."""
import json
import os
import shutil
import sys
from pathlib import Path

repo = Path(__file__).resolve().parents[1]
home = Path.home()
config = Path(os.environ.get('XDG_CONFIG_HOME', home / '.config'))
data = Path(os.environ.get('XDG_DATA_HOME', home / '.local/share'))
state = Path(os.environ.get('XDG_STATE_HOME', home / '.local/state')) / 'omarchy-firefox-web-apps'
record = state / 'native-files.json'
entries = json.loads(record.read_text()) if record.exists() else {}
if sys.argv[1] == 'install':
    host = data / 'omarchy-firefox-web-apps/bridge.py'
    manifest_dict = {
        "name" : "omarchy_firefox_web_apps",
        "description" : "Omarchy Firefox popup bridge",
        "path" : str(host),
        "type" : "stdio",
        "allowed_extensions" : ['webapps@omarchy-firefox-web-apps.local']
    }
    manifest = json.dumps(manifest_dict, indent=2) + '\n'
    files = {
        host: ((repo / 'files/bridge.py').read_text(), 0o755),
        config / 'environment.d/90-omarchy-firefox-web-apps.conf': ('PATH=${HOME}/.local/bin:${PATH}\n', 0o644)
    }
    for root in {config / 'mozilla', home / '.mozilla'}:
        files[root / 'native-messaging-hosts/omarchy_firefox_web_apps.json'] = (manifest, 0o644)
    state.mkdir(parents=True, exist_ok=True)
    for target, (content, mode) in files.items():
        key = str(target)
        if key not in entries:
            backup = state / ('native-backup-' + str(len(entries)))
            existed = target.exists()
            if existed:
                shutil.copy2(target, backup)
            entries[key] = {'backup': str(backup) if existed else None}
        entries[key]['installed'] = content
        record.write_text(json.dumps(entries, indent=2))
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content)
        target.chmod(mode)
else:
    retained = {}
    for key, entry in entries.items():
        target = Path(key)
        if target.exists() and target.read_text() != entry['installed']:
            print(f'Keeping modified file: {target}')
            retained[key] = entry
            continue
        if entry['backup']:
            shutil.copy2(entry['backup'], target)
        else:
            target.unlink(missing_ok=True)
    record.write_text(json.dumps(retained, indent=2))
