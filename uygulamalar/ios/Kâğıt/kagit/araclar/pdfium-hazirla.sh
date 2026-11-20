#!/bin/zsh
# PDFium (bblanchon/pdfium-binaries, BSD-3/Apache-2.0) ikililerini indirip
# iOS cihaz + iOS simülatör + macOS dilimli tek bir pdfium.xcframework kurar.
# Çıktı: Bagimliliklar/pdfium.xcframework (git dışı). Tekrar çalıştırmak güvenlidir.
set -euo pipefail
cd "$(dirname "$0")/.."
SURUM=${PDFIUM_SURUM:-8125}
HEDEF=KagitKit/Ikili
IS=$HEDEF/.pdfium-is
URL="https://github.com/bblanchon/pdfium-binaries/releases/download/chromium%2F$SURUM"

mkdir -p $IS
for paket in ios-device-arm64 ios-simulator-arm64 mac-arm64; do
  if [ ! -d $IS/$paket ]; then
    echo "indiriliyor: $paket"
    curl -fsSL "$URL/pdfium-$paket.tgz" -o $IS/$paket.tgz
    mkdir -p $IS/$paket && tar -xzf $IS/$paket.tgz -C $IS/$paket
  fi
done

basliklar() { # $1 = Headers dizini
  mkdir -p "$1"
  cp $IS/ios-device-arm64/include/*.h "$1/"
  rm -f "$1"/*.orig(N)
  { echo "// Kâğıt: PDFium şemsiye başlığı"
    for h in "$1"/fpdf*.h; do echo "#include \"$(basename $h)\""; done
  } > "$1/pdfium.h"
}
modul() { # $1 = Modules dizini
  mkdir -p "$1"
  cat > "$1/module.modulemap" <<'EOF'
framework module pdfium {
  umbrella header "pdfium.h"
  export *
  module * { export * }
}
EOF
}

rm -rf $IS/cerceve && mkdir -p $IS/cerceve/{ios,sim,mac}

# iOS cihaz ve simülatör: düz framework yapısı
for d in ios:ios-device-arm64 sim:ios-simulator-arm64; do
  ad=${d%%:*}; paket=${d#*:}
  fw=$IS/cerceve/$ad/pdfium.framework
  if [ -d $IS/$paket/lib/pdfium.framework ]; then
    cp -R $IS/$paket/lib/pdfium.framework $fw
  else
    mkdir -p $fw && cp $IS/$paket/lib/libpdfium.dylib $fw/pdfium
    install_name_tool -id @rpath/pdfium.framework/pdfium $fw/pdfium
    cp $IS/ios-device-arm64/lib/pdfium.framework/Info.plist $fw/Info.plist
    plutil -replace CFBundleSupportedPlatforms -json '["iPhoneSimulator"]' $fw/Info.plist
  fi
  basliklar $fw/Headers; modul $fw/Modules
done

# macOS: sürümlü framework yapısı (swift test için)
fw=$IS/cerceve/mac/pdfium.framework
mkdir -p $fw/Versions/A/Resources
cp $IS/mac-arm64/lib/libpdfium.dylib $fw/Versions/A/pdfium
install_name_tool -id @rpath/pdfium.framework/Versions/A/pdfium $fw/Versions/A/pdfium
basliklar $fw/Versions/A/Headers; modul $fw/Versions/A/Modules
cat > $fw/Versions/A/Resources/Info.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>pdfium</string>
<key>CFBundleIdentifier</key><string>io.github.bblanchon.pdfium</string>
<key>CFBundlePackageType</key><string>FMWK</string>
<key>CFBundleName</key><string>pdfium</string>
<key>CFBundleShortVersionString</key><string>158.0.SURUM</string>
<key>CFBundleVersion</key><string>158.0.SURUM</string>
</dict></plist>
EOF
sed -i '' "s/SURUM/$SURUM/g" $fw/Versions/A/Resources/Info.plist
( cd $fw/Versions && ln -sfh A Current )
( cd $fw && ln -sfh Versions/Current/pdfium pdfium && ln -sfh Versions/Current/Headers Headers \
   && ln -sfh Versions/Current/Modules Modules && ln -sfh Versions/Current/Resources Resources )

for ad in ios sim mac; do codesign -f -s - $IS/cerceve/$ad/pdfium.framework >/dev/null 2>&1 || true; done

rm -rf $HEDEF/pdfium.xcframework
xcodebuild -create-xcframework \
  -framework $IS/cerceve/ios/pdfium.framework \
  -framework $IS/cerceve/sim/pdfium.framework \
  -framework $IS/cerceve/mac/pdfium.framework \
  -output $HEDEF/pdfium.xcframework >/dev/null
cp $IS/ios-device-arm64/LICENSE $HEDEF/pdfium-LICENSE
echo "hazır: $HEDEF/pdfium.xcframework"
