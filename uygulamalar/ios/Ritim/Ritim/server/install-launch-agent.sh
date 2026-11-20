#!/bin/sh
# Installs only a per-user launch agent. No sudo, system service, or embedded credential.
set -eu
SERVER_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
export PATH="$HOME/.local/bin:$HOME/.local/node-v24/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
LABEL=local.ritim.media-server
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"
if [ "${1:-}" = "--uninstall" ]; then
    launchctl bootout "$DOMAIN/$LABEL" >/dev/null 2>&1 || true
    rm -f -- "$PLIST_PATH"
    printf '%s\n' 'Ritim otomatik başlatma kaldırıldı. İndirilen dosyalar ve anahtar korunuyor.'
    exit 0
fi
if [ "${1:-}" != "" ]; then
    printf '%s\n' 'Kullanım: install-launch-agent.sh [--uninstall]' >&2
    exit 1
fi
python3 - "$SERVER_DIR" "$PLIST_PATH" <<'PY'
from pathlib import Path
import os, plistlib, sys
server = Path(sys.argv[1])
plist = Path(sys.argv[2])
runtime = server / '.runtime'
runtime.mkdir(mode=0o700, exist_ok=True)
os.chmod(runtime, 0o700)
plist.parent.mkdir(parents=True, exist_ok=True)
value = {
    'Label': 'local.ritim.media-server',
    'ProgramArguments': [str(server / 'start.sh'), '--host', '0.0.0.0'],
    'WorkingDirectory': str(server),
    'RunAtLoad': True,
    'KeepAlive': True,
    'ThrottleInterval': 10,
    'StandardOutPath': str(runtime / 'launchd.stdout.log'),
    'StandardErrorPath': str(runtime / 'launchd.stderr.log'),
    'EnvironmentVariables': {'PATH': os.environ['PATH']},
}
with plist.open('wb') as handle:
    plistlib.dump(value, handle)
os.chmod(plist, 0o600)
PY
plutil -lint "$PLIST_PATH"
launchctl bootout "$DOMAIN/$LABEL" >/dev/null 2>&1 || true
launchctl bootstrap "$DOMAIN" "$PLIST_PATH"
launchctl kickstart "$DOMAIN/$LABEL"
printf '%s\n' 'Ritim girişte otomatik başlayacak. Durum: launchctl print gui/$(id -u)/local.ritim.media-server'
printf '%s\n' 'Sunucu sağlığı: http://127.0.0.1:8765/health'
