#!/usr/bin/env python3
"""Pair and launch a debug build without embedding or printing credentials."""
import argparse
import os
import pathlib
import subprocess

root = pathlib.Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('device', help='iPhone UDID or simulator UUID')
parser.add_argument('--simulator', action='store_true')
parser.add_argument('--server', default=None)
args = parser.parse_args()
token_path = root / 'server/.runtime/api-token'
if not token_path.is_file():
    raise SystemExit('Önce server/start.sh ile indirme servisini başlatın.')
hostname = subprocess.check_output(['scutil', '--get', 'LocalHostName'], text=True).strip()
server = args.server or ('http://localhost:8765' if args.simulator else f'http://{hostname}.local:8765')
env = os.environ.copy()
prefix = 'SIMCTL_CHILD_' if args.simulator else 'DEVICECTL_CHILD_'
env[prefix + 'RITIM_SERVER_URL'] = server
env[prefix + 'RITIM_SERVER_TOKEN'] = token_path.read_text().strip()
if args.simulator:
    subprocess.run(['xcrun', 'simctl', 'terminate', args.device, 'com.mehmetderin.ritim'], capture_output=True)
    command = ['xcrun', 'simctl', 'launch', args.device, 'com.mehmetderin.ritim']
else:
    command = ['xcrun', 'devicectl', 'device', 'process', 'launch', '--device', args.device, '--terminate-existing', 'com.mehmetderin.ritim']
result = subprocess.run(command, env=env, capture_output=True, text=True)
# Print only the launch result and public endpoint; never the environment.
print('Sunucu:', server)
print('Uygulama açıldı.' if result.returncode == 0 else 'Açılamadı; telefon kilidini ve geliştirici modunu kontrol edin.')
if result.returncode:
    text = (result.stdout + result.stderr).replace(env[prefix + 'RITIM_SERVER_TOKEN'], '[hidden]')
    print(text[:3000])
raise SystemExit(result.returncode)
