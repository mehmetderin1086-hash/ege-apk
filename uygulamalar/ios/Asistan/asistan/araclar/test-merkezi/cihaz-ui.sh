#!/bin/zsh
# AsistanUITests-Runner'ı gerçek iPhone'a kurup bütün UI senaryolarını çalıştırır.
emulate -L zsh
setopt pipe_fail
cd "${0:A:h:h:h}" || exit 2
source araclar/kurulum-ortak.sh
UDID=${ASISTAN_CIHAZ_UDID:-00008120-001C592421D8A01E}
kilit_al "$UDID" ${ASISTAN_UI_BEKLE:-} || exit $?
trap kilit_birak EXIT
YAPILANDIRMA=Debug
surum_hesapla
PLAN=${ASISTAN_TEST_PLANI:-Tam}
SECIM=(-only-testing:AsistanUITests)
[[ $PLAN == Canli || "${(j: :)@}" == *-only-testing:* ]] && SECIM=()
xcodebuild test -project Asistan.xcodeproj -scheme Asistan -testPlan "$PLAN" \
  -destination "platform=iOS,id=$UDID" \
  -derivedDataPath "$HOME/Developer/.build/asistan-dd-cihaz" \
  -allowProvisioningUpdates -parallel-testing-enabled NO -collect-test-diagnostics never \
  "${SECIM[@]}" CURRENT_PROJECT_VERSION="$SURUM" "$@"
kod=$?
exit $kod
