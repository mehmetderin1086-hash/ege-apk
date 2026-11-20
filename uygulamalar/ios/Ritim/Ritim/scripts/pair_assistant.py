#!/usr/bin/env python3
"""Provision a direct HTTPS assistant connection into the iPhone Keychain.

This tool injects credentials into the development launch environment only.
It never embeds credentials in an app, xctestrun, source file, or console output.
"""
import argparse
import json
import os
import pathlib
import subprocess
from urllib.parse import urlsplit

root = pathlib.Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('device', help='iPhone UDID or simulator UUID')
parser.add_argument('--simulator', action='store_true')
parser.add_argument('--config', type=pathlib.Path, default=root / 'server/.runtime/ai-proxy.json')
args = parser.parse_args()
config = json.loads(args.config.read_text())
endpoint = urlsplit(config.get('base_url', ''))
if endpoint.scheme != 'https' or not endpoint.hostname or endpoint.username or endpoint.password or endpoint.query or endpoint.fragment:
    raise SystemExit('Asistan bağlantısı geçerli bir HTTPS adresi gerektirir.')
if not isinstance(config.get('api_key'), str) or not config['api_key']:
    raise SystemExit('Asistan erişim anahtarı eksik.')
os.chmod(args.config, 0o600)
env = os.environ.copy()
prefix = 'SIMCTL_CHILD_' if args.simulator else 'DEVICECTL_CHILD_'
env[prefix + 'RITIM_AI_CONFIGURATION'] = json.dumps(config, ensure_ascii=False)
if args.simulator:
    subprocess.run(['xcrun', 'simctl', 'terminate', args.device, 'com.mehmetderin.ritim'], capture_output=True)
    command = ['xcrun', 'simctl', 'launch', args.device, 'com.mehmetderin.ritim']
else:
    command = ['xcrun', 'devicectl', 'device', 'process', 'launch', '--device', args.device,
               '--terminate-existing', 'com.mehmetderin.ritim']
result = subprocess.run(command, env=env, capture_output=True, text=True)
print('Asistan eşleştirmesi için uygulama açıldı.' if result.returncode == 0 else 'Uygulama açılamadı; cihaz bağlantısını kontrol edin.')
# Launch errors are intentionally not printed: tools can echo process environments.
raise SystemExit(result.returncode)
