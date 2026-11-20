#!/bin/zsh
# Gömülü Python (BeeWare iOS paketi) ve yt-dlp tekerleklerini Bagimliliklar/ altına indirir.
# Sürümler sabittir; yt-dlp'yi uygulama içinden de güncelleyebilirsin (Ayarlar → Motor).
set -e
cd "$(dirname "$0")/.."
PY_SURUM=3.14-b12
PY_DOSYA=Python-3.14-iOS-support.b12.tar.gz
YTDLP=2026.8.19
EJS=0.8.0
CERTIFI=2026.7.22
mkdir -p Bagimliliklar && cd Bagimliliklar
if [ ! -d Python.xcframework ]; then
  curl -fsSL -o py.tgz "https://github.com/beeware/Python-Apple-support/releases/download/$PY_SURUM/$PY_DOSYA"
  tar xzf py.tgz Python.xcframework VERSIONS && rm py.tgz
fi
rm -rf app_packages whl && mkdir -p app_packages whl
for p in "yt-dlp==$YTDLP" "yt-dlp-ejs==$EJS" "certifi==$CERTIFI"; do
  ad=${p%%==*}; surum=${p##*==}
  url=$(curl -fsS "https://pypi.org/pypi/$ad/$surum/json" | python3 -c "import sys,json;print([f['url'] for f in json.load(sys.stdin)['urls'] if f['url'].endswith('.whl')][0])")
  curl -fsSL -o "whl/${url:t}" "$url"
  unzip -q -o "whl/${url:t}" -d app_packages
done
rm -rf whl app_packages/*.dist-info app_packages/*.data app_packages/bin
echo "Python: $(head -1 VERSIONS) · yt-dlp $YTDLP · ejs $EJS"
