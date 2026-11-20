#!/usr/bin/env python3
"""Open Bilgi Arenası with accounts already shared by the iPhone CLI Proxy app."""
import argparse, subprocess
p = argparse.ArgumentParser()
p.add_argument('device')
p.add_argument('--simulator', action='store_true')
a=p.parse_args()
if a.simulator:
 command=['xcrun','simctl','launch',a.device,'com.mehmetderin.bilgiarena']
else:
 command=['xcrun','devicectl','device','process','launch','--device',a.device,'--terminate-existing','com.mehmetderin.bilgiarena']
r=subprocess.run(command,capture_output=True)
print('Uygulama açıldı; hesaplar iPhone CLI Proxy ortak kasasından okunur.' if r.returncode == 0 else 'Uygulama açılamadı; cihaz bağlantısını kontrol et.')
raise SystemExit(r.returncode)
