#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_ROOT="${SCRIPT_DIR:h}"
APP_PATH="${PROJECT_ROOT}/dist/DownloadHub.app"

if [[ "$(uname -s)" != "Darwin" || "$(uname -m)" != "arm64" ]]; then
  print -u2 "HATA: DMG yalnız macOS arm64 üzerinde oluşturulur."
  exit 2
fi
if [[ ! -d "${APP_PATH}" ]]; then
  print -u2 "HATA: ${APP_PATH} bulunamadı. Önce build_app.sh çalıştırın."
  exit 2
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP_PATH}/Contents/Info.plist" 2>/dev/null || print '0.1.0')"
OUTPUT="${PROJECT_ROOT}/dist/DownloadHub-${VERSION}-macOS-arm64.dmg"
SOURCE_NAME="DownloadHub-${VERSION}-source"
SOURCE_OUTPUT="${PROJECT_ROOT}/dist/${SOURCE_NAME}.zip"
SOURCE_OUTPUT_TMP="${PROJECT_ROOT}/dist/.${SOURCE_NAME}.zip.tmp.$$"
if [[ -e "${OUTPUT}" || -e "${SOURCE_OUTPUT}" || -e "${SOURCE_OUTPUT_TMP}" ]]; then
  print -u2 "HATA: Mevcut yayın çıktısının üzerine yazılmayacak."
  print -u2 "      ${OUTPUT}"
  print -u2 "      ${SOURCE_OUTPUT}"
  exit 2
fi

TMP_BASE="${TMPDIR:-/tmp}"
TMP_BASE="${TMP_BASE%/}"
STAGING="$(mktemp -d "${TMP_BASE}/downloadhub-dmg.XXXXXX")"
cleanup() {
  if [[ -e "${SOURCE_OUTPUT_TMP}" ]]; then
    /bin/rm -f -- "${SOURCE_OUTPUT_TMP}"
  fi
  case "${STAGING}" in
    "${TMP_BASE}"/downloadhub-dmg.*) rm -rf -- "${STAGING}" ;;
    *) print -u2 "UYARI: Beklenmeyen geçici yol temizlenmedi: ${STAGING}" ;;
  esac
}
trap cleanup EXIT INT TERM

/usr/bin/ditto --norsrc --noextattr "${APP_PATH}" "${STAGING}/DownloadHub.app"
/usr/bin/xattr -c "${STAGING}/DownloadHub.app"
/usr/bin/xattr -cr "${STAGING}/DownloadHub.app"
/usr/bin/xattr -d com.apple.FinderInfo "${STAGING}/DownloadHub.app" 2>/dev/null || true
/usr/bin/xattr -d com.apple.ResourceFork "${STAGING}/DownloadHub.app" 2>/dev/null || true
/usr/bin/codesign --verify --deep --strict --verbose=2 "${STAGING}/DownloadHub.app"
/usr/bin/ditto "${PROJECT_ROOT}/LICENSE" "${STAGING}/LICENSE.txt"
/usr/bin/ditto "${PROJECT_ROOT}/THIRD_PARTY_NOTICES.md" "${STAGING}/THIRD_PARTY_NOTICES.md"
/usr/bin/ditto "${PROJECT_ROOT}/runtime-manifest.json" "${STAGING}/runtime-manifest.json"

# Ship the complete project source used for this local build. The list is explicit so
# virtual environments, downloaded runtimes, build outputs and user data cannot enter
# the source archive accidentally.
SOURCE_ROOT="${STAGING}/${SOURCE_NAME}"
mkdir -p "${SOURCE_ROOT}"
SOURCE_ITEMS=(
  src
  tests
  extension
  migrations
  scripts
  README.md
  LICENSE
  THIRD_PARTY_NOTICES.md
  runtime-manifest.json
  pyproject.toml
  uv.lock
  alembic.ini
)
for source_item in "${SOURCE_ITEMS[@]}"; do
  /usr/bin/ditto --norsrc --noextattr \
    "${PROJECT_ROOT}/${source_item}" "${SOURCE_ROOT}/${source_item}"
done
/usr/bin/find "${SOURCE_ROOT}" -type d -name __pycache__ -prune \
  -exec /bin/rm -rf -- {} +
/usr/bin/find "${SOURCE_ROOT}" -type f \( -name '*.pyc' -o -name '*.pyo' -o -name '.DS_Store' \) \
  -delete
/usr/bin/xattr -cr "${SOURCE_ROOT}"
/usr/bin/ditto -c -k --keepParent --norsrc --noextattr \
  "${SOURCE_ROOT}" "${STAGING}/${SOURCE_NAME}.zip"
case "${SOURCE_ROOT}" in
  "${STAGING}"/*) /bin/rm -rf -- "${SOURCE_ROOT}" ;;
  *) print -u2 "HATA: Beklenmeyen kaynak hazırlama yolu: ${SOURCE_ROOT}"; exit 1 ;;
esac

# Preserve the actual license files shipped by installed Python distributions. The
# directory hierarchy is retained to avoid ambiguous or colliding LICENSE filenames.
PYTHON_SITE="$(${PROJECT_ROOT}/.venv/bin/python -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')"
LICENSE_ROOT="${STAGING}/Third-Party Licenses/Python"
mkdir -p "${LICENSE_ROOT}"
while IFS= read -r license_file; do
  relative_path="${license_file#${PYTHON_SITE}/}"
  destination="${LICENSE_ROOT}/${relative_path}"
  mkdir -p "${destination:h}"
  /usr/bin/ditto --norsrc --noextattr "${license_file}" "${destination}"
done < <(
  /usr/bin/find "${PYTHON_SITE}" -type f -path '*.dist-info/*' \
    \( -iname 'LICENSE*' -o -iname 'COPYING*' -o -iname 'NOTICE*' \) -print
)
/bin/ln -s /Applications "${STAGING}/Applications"

/usr/bin/hdiutil create \
  -volname "DownloadHub ${VERSION}" \
  -srcfolder "${STAGING}" \
  -format UDZO \
  -imagekey zlib-level=9 \
  "${OUTPUT}"

if [[ -n "${DOWNLOADHUB_CODESIGN_IDENTITY:-}" ]]; then
  /usr/bin/codesign --timestamp --sign "${DOWNLOADHUB_CODESIGN_IDENTITY}" "${OUTPUT}"
  /usr/bin/codesign --verify --verbose=2 "${OUTPUT}"
fi

/usr/bin/unzip -tq "${STAGING}/${SOURCE_NAME}.zip"
/usr/bin/ditto --norsrc --noextattr \
  "${STAGING}/${SOURCE_NAME}.zip" "${SOURCE_OUTPUT_TMP}"
/usr/bin/unzip -tq "${SOURCE_OUTPUT_TMP}"
/bin/mv "${SOURCE_OUTPUT_TMP}" "${SOURCE_OUTPUT}"

print "Hazır: ${OUTPUT}"
print "Hazır: ${SOURCE_OUTPUT}"
print "Notarizasyon ayrı ve açık bir yayın adımıdır; bu betik kimlik bilgisi saklamaz."
