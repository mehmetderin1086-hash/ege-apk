#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_ROOT="${SCRIPT_DIR:h}"
APP_NAME="PDF Studio.app"
DIST_APP="${PROJECT_ROOT}/dist/${APP_NAME}"
DESKTOP_APP="${HOME}/Desktop/${APP_NAME}"
ICON_FILE="${PROJECT_ROOT}/assets/PDFStudio.icns"
INFO_PLIST="${PROJECT_ROOT}/assets/PDFStudio-Info.plist"
LAUNCH_SCRIPT="${PROJECT_ROOT}/scripts/macos_launch.sh"
LAUNCHER_SOURCE="${PROJECT_ROOT}/scripts/macos_launcher.c"

if [[ "$(uname -s)" != "Darwin" || "$(uname -m)" != "arm64" ]]; then
  print -u2 "HATA: Uygulama yalnız Apple Silicon macOS üzerinde hazırlanabilir."
  exit 2
fi
for required_file in "${ICON_FILE}" "${INFO_PLIST}" "${LAUNCH_SCRIPT}" "${LAUNCHER_SOURCE}"; do
  if [[ ! -f "${required_file}" ]]; then
    print -u2 "HATA: Gerekli dosya bulunamadı: ${required_file}"
    exit 2
  fi
done

STAGE_ROOT="$(mktemp -d /tmp/pdfstudio-app.XXXXXX)"
STAGED_APP="${STAGE_ROOT}/${APP_NAME}"
cleanup() {
  case "${STAGE_ROOT}" in
    /tmp/pdfstudio-app.*) rm -rf -- "${STAGE_ROOT}" ;;
  esac
}
trap cleanup EXIT INT TERM

mkdir -p \
  "${STAGED_APP}/Contents/MacOS" \
  "${STAGED_APP}/Contents/Resources" \
  "${PROJECT_ROOT}/dist" \
  "${PROJECT_ROOT}/build/app-archive"

/usr/bin/clang -Os -arch arm64 -mmacosx-version-min=13.0 \
  "${LAUNCHER_SOURCE}" -o "${STAGED_APP}/Contents/MacOS/PDF Studio"
/bin/cp "${LAUNCH_SCRIPT}" "${STAGED_APP}/Contents/Resources/launch.sh"
/bin/chmod 755 "${STAGED_APP}/Contents/Resources/launch.sh"
/bin/cp "${ICON_FILE}" "${STAGED_APP}/Contents/Resources/PDFStudio.icns"
/bin/cp "${INFO_PLIST}" "${STAGED_APP}/Contents/Info.plist"

/usr/bin/plutil -lint "${STAGED_APP}/Contents/Info.plist"
/usr/bin/xattr -cr "${STAGED_APP}"
/usr/bin/codesign --force --deep --sign - "${STAGED_APP}"
/usr/bin/codesign --verify --deep --strict "${STAGED_APP}"

archive_existing() {
  local existing_app="$1"
  local label="$2"
  if [[ -e "${existing_app}" ]]; then
    local archive_path="${PROJECT_ROOT}/build/app-archive/PDF-Studio-${label}-$(date -u +%Y%m%dT%H%M%SZ).app"
    /bin/mv "${existing_app}" "${archive_path}"
    print "Önceki paket arşivlendi: ${archive_path}"
  fi
}

archive_existing "${DIST_APP}" "dist"
archive_existing "${DESKTOP_APP}" "desktop"

/usr/bin/ditto --norsrc --noextattr "${STAGED_APP}" "${DIST_APP}"
/usr/bin/ditto --norsrc --noextattr "${STAGED_APP}" "${DESKTOP_APP}"

for installed_app in "${DIST_APP}" "${DESKTOP_APP}"; do
  verified=0
  for attempt in {1..10}; do
    /usr/bin/xattr -cr "${installed_app}" 2>/dev/null || true
    /usr/bin/xattr -d com.apple.FinderInfo "${installed_app}" 2>/dev/null || true
    /usr/bin/xattr -d com.apple.ResourceFork "${installed_app}" 2>/dev/null || true
    if /usr/bin/codesign --verify --deep --strict "${installed_app}" 2>/dev/null; then
      verified=1
      break
    fi
  done
  if (( verified == 0 )); then
    print -u2 "HATA: Kurulan uygulamanın imzası doğrulanamadı: ${installed_app}"
    exit 1
  fi
done

print "Hazır: ${DESKTOP_APP}"
