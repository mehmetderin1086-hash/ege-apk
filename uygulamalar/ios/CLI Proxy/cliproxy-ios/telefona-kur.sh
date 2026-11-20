#!/bin/zsh
# CLI Proxy'yi iPhone'a derler, kurar ve açar.
# Kullanım: ./telefona-kur.sh [UDID] [--paket]   (--paket: sunucudan taze taşıma paketi üretip uygulamaya aktarır)
set -e
cd "$(dirname "$0")"
UDID=00008120-001C592421D8A01E
PAKET=0
for a in "$@"; do case $a in --paket) PAKET=1;; *) UDID=$a;; esac; done
DD=~/Developer/.build/cliproxy-dd-cihaz
~/Developer/.tools/xcodegen/xcodegen/bin/xcodegen generate >/dev/null
xcodebuild -project CLIProxy.xcodeproj -scheme CLIProxy -destination "id=$UDID" -derivedDataPath "$DD" -allowProvisioningUpdates build 2>&1 | grep -E "error:|BUILD" | sort -u
xcrun devicectl device install app --device "$UDID" "$DD/Build/Products/Debug-iphoneos/CLIProxy.app" | tail -1
if [ $PAKET = 1 ]; then
  T=$(mktemp -d); chmod 700 $T
  ssh root@82.29.179.131 'cd /tmp && /srv/apps/cliproxy/.venv/bin/python /srv/apps/cliproxy/telefon-paketi.py' > $T/telefon-paketi.json
  # Claude API anahtarı sunucuda değil Mac'te (İkra'nın Secrets.xcconfig'i); pakete burada "claude-api" sağlayıcısı olarak eklenir.
  SECRETS=${CLAUDE_SECRETS:-~/Developer/.build/dv27/base/DersPodcast/Secrets.xcconfig}
  CLAUDE_API_KEY=$(sed -n 's/^CLAUDE_API_KEY *= *//p' "$SECRETS" | tr -d '[:space:]')
  if [ -n "$CLAUDE_API_KEY" ]; then
    CLAUDE_API_KEY="$CLAUDE_API_KEY" python3 -I - "$T/telefon-paketi.json" <<'PY'
import json, os, sys
p = sys.argv[1]; b = json.load(open(p))
b["api_anahtarlari"] = [a for a in b.get("api_anahtarlari", []) if a["name"] != "claude-api"] + [{
    "name": "claude-api", "kind": "anthropic", "base_url": "https://api.anthropic.com",
    "api_key": os.environ["CLAUDE_API_KEY"], "models": []}]
json.dump(b, open(p, "w"), ensure_ascii=False)
print("pakete claude-api eklendi")
PY
  else
    echo "UYARI: $SECRETS içinde CLAUDE_API_KEY yok; paket Claude API anahtarsız"
  fi
  xcrun devicectl device copy to --device "$UDID" --domain-type appDataContainer --domain-identifier com.mehmetderin.cliproxy \
    --source $T/telefon-paketi.json --destination Documents/telefon-paketi.json | tail -1
  rm -rf $T   # sır içeren paket Mac'te kalmaz; uygulama içe aktarınca kendi kopyasını siler
fi
xcrun devicectl device process launch --terminate-existing --device "$UDID" com.mehmetderin.cliproxy | tail -1
