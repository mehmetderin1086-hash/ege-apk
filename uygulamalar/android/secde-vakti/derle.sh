#!/bin/bash
# Secde Vakti 1.0.0 APK'sına bildirim denetim katmanını ekler, yeniden paketler ve imzalar.
#
# Kullanım (telefondan açılan bir Claude oturumunda da çalışır):
#   ./derle.sh <anahtar.p12> <anahtar-parolası> [takma-ad]
#
# Girdi APK depodaki kaynak/secde_vakti_1.0.0.apk.zip'ten açılır; başka bir APK için
# GIRDI=/yol/secde.apk ./derle.sh ... şeklinde verilebilir.
# Gerekenler: JDK 17+, python3, curl, zip, unzip. Android SDK GEREKMEZ; araçlar aşağıda indirilir.
# Çıktı: surumler/secde_vakti_2.0.1.apk.zip (telefona gönderilecek APK .derleme/ altında da kalır)
set -euo pipefail

KOK=$(cd "$(dirname "$0")" && pwd)
ANAHTAR=${1:?"Kullanım: ./derle.sh <anahtar.p12> <parola> [takma-ad]"}
PAROLA=${2:?"Anahtar parolası gerekli"}
TAKMA=${3:-secde}
IS="$KOK/.derleme"
ARAC="$IS/araclar"
mkdir -p "$ARAC" "$IS/cls" "$IS/dex" "$KOK/surumler"

if [ -z "${GIRDI:-}" ]; then
  GIRDI="$IS/secde_vakti_1.0.0.apk"
  [ -s "$GIRDI" ] || unzip -p "$KOK/kaynak/secde_vakti_1.0.0.apk.zip" secde_vakti.apk > "$GIRDI"
fi
echo "d2dcff49978ad5c5412c6c94e24aa9f51ceac83abc737462108834196a2c63f7  $GIRDI" | sha256sum -c --quiet \
  || echo "UYARI: girdi APK beklenen 1.0.0 değil; yamalar uymayabilir."

indir() { [ -s "$ARAC/$1" ] || curl -fsSL -o "$ARAC/$1" "$2"; }
indir apksig-2.3.0.jar https://repo1.maven.org/maven2/com/android/tools/build/apksig/2.3.0/apksig-2.3.0.jar
indir r8lib.jar https://storage.googleapis.com/r8-releases/raw/8.11.18/r8lib.jar
indir android-all.jar https://repo1.maven.org/maven2/org/robolectric/android-all/16-robolectric-13921718/android-all-16-robolectric-13921718.jar

# 1) Java katmanı -> dex
rm -rf "$IS/cls"/* "$IS/dex"/*
javac --release 11 -encoding UTF-8 -nowarn -cp "$ARAC/android-all.jar" -d "$IS/cls" $(find "$KOK/native/src" -name "*.java")
java -cp "$ARAC/r8lib.jar" com.android.tools.r8.D8 --release --min-api 24 \
  --lib "$ARAC/android-all.jar" --output "$IS/dex" $(find "$IS/cls" -name "*.class")

# 2) Manifest
python3 -I "$KOK/araclar/manifest_duzenle.py" "$GIRDI" "$IS/AndroidManifest.xml"

# 3) Tema: her mimarinin libapp.so'sunda varsayılan temayı "Mihrap" paletine çevir
YAMALAR=()
for ABI in arm64-v8a armeabi-v7a x86_64; do
  mkdir -p "$IS/lib/$ABI"
  unzip -p "$GIRDI" "lib/$ABI/libapp.so" > "$IS/lib/$ABI/libapp.orijinal.so"
  python3 -I "$KOK/araclar/tema_yamasi.py" "$IS/lib/$ABI/libapp.orijinal.so" "$IS/lib/$ABI/libapp.so"
  YAMALAR+=("lib/$ABI/libapp.so=$IS/lib/$ABI/libapp.so")
done

# Vakitler ekranının arka plan görselleri -> assets/secde/
for G in "$KOK"/gorseller/*.webp; do
  YAMALAR+=("assets/secde/$(basename "$G")=$G")
done
if [ -f "$KOK/gorseller/uygulama_simgesi.png" ]; then
  python3 -I "$KOK/araclar/simge_uret.py" "$KOK/gorseller/uygulama_simgesi.png" "$IS/simgeler"
  for S in "$IS"/simgeler/*.png; do
    YAMALAR+=("res/$(basename "$S")=$S")
  done
fi

# Sesli meal dizini (uygulamanın official_meal_audio.json kayıtlarından sure → okuyucu → adres)
python3 -I "$KOK/araclar/meal_ses_uret.py" "$GIRDI" "$IS/meal_ses.json"
YAMALAR+=("assets/secde/meal_ses.json=$IS/meal_ses.json")

# 4) Paketle (hizalama dahil)
python3 -I "$KOK/araclar/repack.py" "$GIRDI" "$IS/imzasiz.apk" \
  AndroidManifest.xml="$IS/AndroidManifest.xml" classes3.dex="$IS/dex/classes.dex" "${YAMALAR[@]}"

# 5) İmzala (APK Signature Scheme v2) ve doğrula
JAVA_ACIK="--add-exports java.base/sun.security.x509=ALL-UNNAMED --add-exports java.base/sun.security.pkcs=ALL-UNNAMED --add-exports java.base/sun.security.util=ALL-UNNAMED"
javac -cp "$ARAC/apksig-2.3.0.jar" -d "$IS" "$KOK/araclar/Sign.java" "$KOK/araclar/Dogrula.java"
CIKTI="$KOK/surumler/secde_vakti_2.2.1.apk"
java $JAVA_ACIK -cp "$ARAC/apksig-2.3.0.jar:$IS" Sign "$ANAHTAR" "$PAROLA" "$TAKMA" "$IS/imzasiz.apk" "$CIKTI"
python3 -I "$KOK/araclar/checkalign.py" "$CIKTI"
java $JAVA_ACIK -cp "$ARAC/apksig-2.3.0.jar:$IS" Dogrula "$CIKTI"

(cd "$KOK/surumler" && rm -f secde_vakti_*.apk.zip && zip -q -9 secde_vakti_2.2.1.apk.zip secde_vakti_2.2.1.apk && mv secde_vakti_2.2.1.apk "$IS/")
echo "Hazır: $KOK/surumler/secde_vakti_2.2.1.apk.zip"
echo "Telefona gönderilecek APK: $IS/secde_vakti_2.2.1.apk"
