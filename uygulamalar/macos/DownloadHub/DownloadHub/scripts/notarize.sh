#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_ROOT="${SCRIPT_DIR:h}"
DMG_PATH="${1:-}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  print -u2 "HATA: Notarizasyon yalnız macOS üzerinde çalışır."
  exit 2
fi
if [[ -z "${DMG_PATH}" || -n "${2:-}" ]]; then
  print -u2 "Kullanım: DOWNLOADHUB_NOTARY_PROFILE=profil zsh scripts/notarize.sh dist/DownloadHub-….dmg"
  exit 2
fi
if [[ -z "${DOWNLOADHUB_NOTARY_PROFILE:-}" ]]; then
  print -u2 "HATA: xcrun notarytool keychain profili DOWNLOADHUB_NOTARY_PROFILE ile verilmelidir."
  print -u2 "Kimlik bilgileri komut satırında veya depoda kabul edilmez."
  exit 2
fi

ABSOLUTE_DMG="${DMG_PATH:A}"
case "${ABSOLUTE_DMG}" in
  "${PROJECT_ROOT}/dist/"*.dmg) ;;
  *) print -u2 "HATA: Yalnız proje dist/ klasöründeki DMG notarize edilir."; exit 2 ;;
esac
if [[ ! -f "${ABSOLUTE_DMG}" || -L "${ABSOLUTE_DMG}" ]]; then
  print -u2 "HATA: Güvenli DMG dosyası bulunamadı: ${ABSOLUTE_DMG}"
  exit 2
fi

/usr/bin/xcrun notarytool submit "${ABSOLUTE_DMG}" \
  --keychain-profile "${DOWNLOADHUB_NOTARY_PROFILE}" \
  --wait
/usr/bin/xcrun stapler staple "${ABSOLUTE_DMG}"
/usr/bin/xcrun stapler validate "${ABSOLUTE_DMG}"
print "Notarizasyon bileti doğrulandı: ${ABSOLUTE_DMG}"
