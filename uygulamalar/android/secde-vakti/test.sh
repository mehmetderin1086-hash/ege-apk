#!/bin/bash
# Secde ana menüsünün uçtan uca testleri (Robolectric 4.14, gerçek çizim / native graphics).
# Her sekmenin ekran görüntüsü .derleme/test-cikti/*.png olarak yazılır.
#
# Kullanım: ./test.sh
#
# Bu ortamda Google Maven (dl.google.com) kapalı olduğu için Robolectric'in androidx.test
# bağımlılıkları Maven Central'dan değil, android/android-test kaynağından derlenir
# (test-destek/stub: eksik androidx.annotation / androidx.tracing ve iki Kotlin sınıfının Java karşılığı).
set -euo pipefail

KOK=$(cd "$(dirname "$0")" && pwd)
IS="$KOK/.derleme"
T="$IS/test"
ARAC="$IS/araclar"
mkdir -p "$T" "$ARAC"

indir() { [ -s "$ARAC/$1" ] || curl -fsSL -o "$ARAC/$1" "$2"; }
indir android-all.jar https://repo1.maven.org/maven2/org/robolectric/android-all/16-robolectric-13921718/android-all-16-robolectric-13921718.jar

# 1) Robolectric ve bağımlılıkları (androidx.test hariç)
if [ ! -s "$T/lib/robolectric-4.14.1.jar" ]; then
  (cd "$KOK/test-destek" && mvn -q dependency:copy-dependencies -DoutputDirectory="$T/lib")
fi
# Robolectric'in çalışırken indirdiği Android SDK jar'ları (doğrudan indirme 429 verebiliyor)
for SURUM in 14-robolectric-10818077-i7 15-robolectric-12650502-i7; do
  [ -s "$HOME/.m2/repository/org/robolectric/android-all-instrumented/$SURUM/android-all-instrumented-$SURUM.jar" ] || \
    mvn -q org.apache.maven.plugins:maven-dependency-plugin:3.6.1:get \
      -Dartifact=org.robolectric:android-all-instrumented:$SURUM -Dtransitive=false
done

# 2) androidx.test (monitor + espresso idling resource) kaynaktan
if [ ! -s "$T/lib/androidx-test-yerel.jar" ]; then
  rm -rf "$T/at" "$T/atcls"
  git -c advice.detachedHead=false clone -q --depth 1 --filter=blob:none --sparse \
    https://github.com/android/android-test.git "$T/at"
  (cd "$T/at" && git sparse-checkout set runner/monitor espresso/idling_resource)
  find "$T/at/runner/monitor/java" "$T/at/espresso/idling_resource/java" "$KOK/test-destek/stub" -name "*.java" \
    | grep -v "internal/runner/runtime/ExposedInstrumentationApi.java" > "$T/at.txt"
  CP="$ARAC/android-all.jar:$(ls "$T"/lib/*.jar | tr '\n' ':')"
  mkdir -p "$T/atcls"
  javac --release 11 -nowarn -encoding UTF-8 -cp "$CP" -d "$T/atcls" @"$T/at.txt"
  # Çalışma anında kullanılan (boş) ExposedInstrumentationApi
  javac --release 11 -nowarn -encoding UTF-8 -cp "$CP:$T/atcls" -d "$T/atcls" \
    "$T/at/runner/monitor/java/androidx/test/internal/runner/runtime/ExposedInstrumentationApi.java"
  (cd "$T/atcls" && jar cf "$T/lib/androidx-test-yerel.jar" .)
fi

# 3) Uygulamanın Flutter dosyaları (Kur'an verisi, Elif-Ba, yazı tipleri) ve sesli meal dizini
GIRDI="$IS/secde_vakti_1.0.0.apk"
[ -s "$GIRDI" ] || unzip -p "$KOK/kaynak/secde_vakti_1.0.0.apk.zip" secde_vakti.apk > "$GIRDI"
if [ ! -d "$T/flutter/assets/data" ]; then
  rm -rf "$T/flutter_tmp" && mkdir -p "$T/flutter_tmp"
  unzip -q -o "$GIRDI" 'assets/flutter_assets/*' -d "$T/flutter_tmp"
  rm -rf "$T/flutter" && mv "$T/flutter_tmp/assets/flutter_assets" "$T/flutter" && rm -rf "$T/flutter_tmp"
fi
mkdir -p "$T/veri"
python3 -I "$KOK/araclar/meal_ses_uret.py" "$GIRDI" "$T/veri/meal_ses.json"

# 4) Uygulama kodu + testler
CP="$(ls "$T"/lib/*.jar | tr '\n' ':')"
rm -rf "$T/cls" "$T/tcls" "$IS/test-cikti"
mkdir -p "$T/cls" "$T/tcls" "$IS/test-cikti"
javac --release 11 -nowarn -encoding UTF-8 -cp "$ARAC/android-all.jar" -d "$T/cls" $(find "$KOK/native/src" -name "*.java")
javac --release 11 -nowarn -encoding UTF-8 -cp "$CP:$ARAC/android-all.jar:$T/cls" -d "$T/tcls" $(find "$KOK/test" -name "*.java")

# 5) Çalıştır
java -Dcikti="$IS/test-cikti" -Dsecde.gorsel.dizin="$KOK/gorseller" \
  -Dsecde.flutter.dizin="$T/flutter" -Dsecde.veri.dizin="$T/veri" \
  -cp "$T/tcls:$T/cls:$CP:$ARAC/android-all.jar" org.junit.runner.JUnitCore \
  com.mehmetderin.secde_vakti.saglik.AnaMenuTesti 2>&1 \
  | grep -vE "JAVA_TOOL|^WARNING|No manifest|Falling back|To remove|Android Gradle|^\s+at (org\.junit|java\.base|jdk|sun)"
echo "Ekran görüntüleri: $IS/test-cikti/"
