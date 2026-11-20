#!/bin/zsh
# Kepçe'yi iPhone'a derler, kurar ve açar. İlk kez: ./araclar/bagimliliklar.sh
set -e
cd "$(dirname "$0")"
UDID=${1:-00008120-001C592421D8A01E}
DD=~/Developer/.build/kepce-dd-cihaz
[ -d Bagimliliklar/Python.xcframework ] || ./araclar/bagimliliklar.sh
~/Developer/.tools/xcodegen/xcodegen/bin/xcodegen generate >/dev/null
xcodebuild -project Kepce.xcodeproj -scheme Kepce -configuration ${KONFIG:-Release} -destination "id=$UDID" -derivedDataPath "$DD" -allowProvisioningUpdates build 2>&1 | grep -E "^/.*error:|^\*\* BUILD" | sort -u
xcrun devicectl device install app --device "$UDID" "$DD/Build/Products/${KONFIG:-Release}-iphoneos/Kepce.app" | tail -1
xcrun devicectl device process launch --terminate-existing --device "$UDID" com.mehmetderin.kepce | tail -1
