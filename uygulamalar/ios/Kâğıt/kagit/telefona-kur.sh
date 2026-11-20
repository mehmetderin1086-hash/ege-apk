#!/bin/zsh
# Kâğıt'ı iPhone'a derler, kurar ve açar. İlk kez: ./araclar/pdfium-hazirla.sh
set -e
cd "$(dirname "$0")"
UDID=${1:-00008120-001C592421D8A01E}
DD=~/Developer/.build/kagit-dd-cihaz
[ -d KagitKit/Ikili/pdfium.xcframework ] || ./araclar/pdfium-hazirla.sh
[ -f Secrets.xcconfig ] || cp Secrets.example.xcconfig Secrets.xcconfig
~/Developer/.tools/xcodegen/xcodegen/bin/xcodegen generate >/dev/null
xcodebuild -project Kagit.xcodeproj -scheme Kagit -configuration ${KONFIG:-Release} -destination "id=$UDID" -derivedDataPath "$DD" -allowProvisioningUpdates build 2>&1 | grep -E "^/.*error:|^\*\* BUILD" | sort -u
xcrun devicectl device install app --device "$UDID" "$DD/Build/Products/${KONFIG:-Release}-iphoneos/Kagit.app" | tail -1
xcrun devicectl device process launch --terminate-existing --device "$UDID" com.mehmetderin.kagit | tail -1
