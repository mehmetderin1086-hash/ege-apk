#!/bin/zsh
# Asistan'ı iPhone "Mehmet iPhone'u"na derler, kurar ve açar.
#   ./telefona-kur.sh                 Release kurar (varsayılan)
#   ./telefona-kur.sh --sinama        Debug kurar (--asistan-* sınama bayrakları yalnız Debug'da vardır)
#   ./telefona-kur.sh --bekle[=sn]    telefon kilitliyse bekler (varsayılan 600 sn); yoksa 75 koduyla çıkar
#   ./telefona-kur.sh --udid X | X    başka cihaz
# Kilit: ~/Developer/.build/asistan-telefon-<UDID>.kilit · defter: ~/Developer/.build/asistan-kurulumlar.log
# Tam derleme günlüğü: ~/Developer/.build/asistan-kur-son.log · dSYM: ~/Developer/.build/asistan-dsym/ (son 5)
set -euo pipefail
cd "$(dirname "$0")"
KOK=$PWD
source araclar/kurulum-ortak.sh

UDID=00008120-001C592421D8A01E
YAPILANDIRMA=Release
BEKLE=""
udid_verildi=0
while (( $# )); do
  case $1 in
    --sinama) YAPILANDIRMA=Debug ;;
    --bekle) BEKLE=600 ;;
    --bekle=*) BEKLE=${1#--bekle=} ;;
    --udid) shift; UDID=${1:-}; udid_verildi=1 ;;
    --udid=*) UDID=${1#--udid=}; udid_verildi=1 ;;
    -h|--yardim) sed -n '2,8p' "$0"; exit 0 ;;
    -*) print -u2 "Bilinmeyen bayrak: $1"; exit 64 ;;
    *) if (( udid_verildi )); then print -u2 "Fazla argüman: $1"; exit 64; fi
       UDID=$1; udid_verildi=1 ;;
  esac
  shift
done
[[ -n $UDID ]] || { print -u2 "UDID boş"; exit 64; }
[[ -z $BEKLE || $BEKLE == <-> ]] || { print -u2 -r -- "--bekle saniye ister: $BEKLE"; exit 64; }

BASLA=$SECONDS
kilit_al "$UDID" $BEKLE || exit $?
# Üst düzeyde kurulur: zsh'ta işlev içindeki EXIT tuzağı işlev dönünce çalışırdı.
trap kilit_birak EXIT
trap 'kilit_birak; exit 130' INT
trap 'kilit_birak; exit 143' TERM

DD=~/Developer/.build/asistan-dd-cihaz
GUNLUK=~/Developer/.build/asistan-kur-son.log
APP="$DD/Build/Products/$YAPILANDIRMA-iphoneos/Asistan.app"
sure() { print $((SECONDS - BASLA)); }

if ! ~/Developer/.tools/xcodegen/xcodegen/bin/xcodegen generate >/dev/null; then
  surum_hesapla
  defter_yaz derleme_hatasi "$(sure)"; print -u2 "xcodegen başarısız"; exit 1
fi

# Sürüm damgası xcodegen'den sonra: derleme numarası ve değişmiş dosya sayısı derlemeye girenle aynı anı yansıtır.
surum_hesapla
arti=""; (( KIRLI > 0 )) && arti=" +$KIRLI"
print "Asistan $PAZARLAMA ($SURUM) · git $GIT$arti · $YAPILANDIRMA → $UDID"

# Tam günlük dosyaya, ekrana yalnız hata/BUILD satırları; xcodebuild'in kendi çıkış kodu pipestatus'tan okunur.
set +e
xcodebuild -project Asistan.xcodeproj -scheme Asistan -configuration "$YAPILANDIRMA" -destination "id=$UDID" \
  -derivedDataPath "$DD" -allowProvisioningUpdates \
  CURRENT_PROJECT_VERSION="$SURUM" ASISTAN_GIT_HASH="$GIT" ASISTAN_KIRLI="$KIRLI" build 2>&1 \
  | tee "$GUNLUK" | grep -E "error:|BUILD" | sort -u
derleme_durumu=${pipestatus[1]}
set -e
if (( derleme_durumu != 0 )); then
  defter_yaz derleme_hatasi "$(sure)"; print -u2 "Derleme başarısız (tam günlük: $GUNLUK)"; exit 1
fi

if ! cikti=$(xcrun devicectl device install app --device "$UDID" "$APP" 2>&1); then
  print -r -- "$cikti" | tail -5 >&2
  defter_yaz kurulum_hatasi "$(sure)"; exit 1
fi
print -r -- "$cikti" | tail -1

# Telefondaki sürümü doğrula (yalnız uyarı). devicectl JSON'unda alan adı bundleVersion beklenir; bulunamazsa uyarılır.
TMPJSON=$(mktemp -t asistan-uygulamalar.XXXXXX)
if xcrun devicectl device info apps --device "$UDID" --json-output "$TMPJSON" >/dev/null 2>&1; then
  telefondaki=$(jq -r '[.. | objects | select(.bundleIdentifier? == "com.mehmetderin.asistan") | .bundleVersion? // empty] | first // empty' "$TMPJSON" 2>/dev/null || true)
  if [[ -z $telefondaki ]]; then
    print -u2 "Uyarı: telefondaki derleme numarası JSON'da bulunamadı (bundleVersion alanı yok?): $TMPJSON"
  elif [[ $telefondaki != "$SURUM" ]]; then
    print -u2 "Uyarı: telefondaki sürüm başka: $telefondaki (beklenen $SURUM). project.yml'de CFBundleVersion \$(CURRENT_PROJECT_VERSION) mi?"
    rm -f "$TMPJSON"
  else
    print "Telefondaki derleme doğrulandı: $telefondaki"
    rm -f "$TMPJSON"
  fi
else
  print -u2 "Uyarı: telefondaki uygulama listesi okunamadı; sürüm doğrulanmadı."
  rm -f "$TMPJSON"
fi

if [[ $YAPILANDIRMA == Release ]]; then
  dsym_sakla "$DD/Build/Products/Release-iphoneos" "$SURUM-$GIT" 5
fi

if ! cikti=$(xcrun devicectl device process launch --terminate-existing --device "$UDID" com.mehmetderin.asistan 2>&1); then
  print -r -- "$cikti" | tail -5 >&2
  defter_yaz acilis_hatasi "$(sure)"; exit 1
fi
print -r -- "$cikti" | tail -1
defter_yaz basarili "$(sure)"
print "Kuruldu: Asistan $PAZARLAMA ($SURUM) · $(sure) sn"
