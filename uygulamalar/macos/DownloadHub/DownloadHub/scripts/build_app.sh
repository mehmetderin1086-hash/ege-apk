#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_ROOT="${SCRIPT_DIR:h}"
PYTHON_BIN="${PROJECT_ROOT}/.venv/bin/python"
PYINSTALLER_BIN="${PROJECT_ROOT}/.venv/bin/pyinstaller"
DIST_DIR="${PROJECT_ROOT}/dist"
OUTPUT_APP="${DIST_DIR}/DownloadHub.app"
APP_ICON="${PROJECT_ROOT}/assets/DownloadHub.icns"
DEVELOPMENT_BUILD=0

if [[ "${1:-}" == "--development" ]]; then
  DEVELOPMENT_BUILD=1
elif [[ -n "${1:-}" ]]; then
  print -u2 "Kullanım: zsh scripts/build_app.sh [--development]"
  exit 2
fi

if [[ "$(uname -s)" != "Darwin" || "$(uname -m)" != "arm64" ]]; then
  print -u2 "HATA: .app yalnız macOS arm64 üzerinde paketlenir."
  exit 2
fi
if [[ ! -x "${PYINSTALLER_BIN}" || ! -x "${PYTHON_BIN}" ]]; then
  print -u2 "HATA: Paketleme ortamı eksik. Önce zsh scripts/bootstrap.sh çalıştırın."
  exit 2
fi
if [[ ! -f "${APP_ICON}" ]]; then
  print -u2 "HATA: Uygulama simgesi bulunamadı: ${APP_ICON}"
  exit 2
fi
APP_VERSION="$("${PYTHON_BIN}" -c 'from importlib.metadata import version; print(version("downloadhub"))')"
if [[ ! "${APP_VERSION}" =~ '^[0-9]+([.][0-9]+){1,3}$' ]]; then
  print -u2 "HATA: macOS bundle için geçersiz uygulama sürümü: ${APP_VERSION}"
  exit 2
fi
if [[ -e "${OUTPUT_APP}" ]]; then
  print -u2 "HATA: Mevcut çıktı üzerine yazılmayacak: ${OUTPUT_APP}"
  print -u2 "Arşivleyin veya kaldırın, sonra yeniden deneyin."
  exit 2
fi

if (( DEVELOPMENT_BUILD == 0 )); then
  "${PYTHON_BIN}" "${PROJECT_ROOT}/scripts/runtime_manager.py" verify --required
else
  print -u2 "UYARI: --development seçildi; eksik/etkinleştirilmemiş runtime'larla paket oluşturuluyor."
fi

mkdir -p "${DIST_DIR}" "${PROJECT_ROOT}/build"
BUILD_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
WORK_DIR="${PROJECT_ROOT}/build/pyinstaller-${BUILD_ID}"
mkdir -p "${WORK_DIR}/spec" "${WORK_DIR}/work"
TMP_BASE="${TMPDIR:-/tmp}"
TMP_BASE="${TMP_BASE%/}"
PACKAGE_STAGE="$(mktemp -d "${TMP_BASE}/downloadhub-app.XXXXXX")"
cleanup_package_stage() {
  case "${PACKAGE_STAGE}" in
    "${TMP_BASE}"/downloadhub-app.*) rm -rf -- "${PACKAGE_STAGE}" ;;
    *) print -u2 "UYARI: Beklenmeyen geçici yol temizlenmedi: ${PACKAGE_STAGE}" ;;
  esac
}
trap cleanup_package_stage EXIT INT TERM
STAGE_DIST="${PACKAGE_STAGE}/dist"
STAGED_APP="${STAGE_DIST}/DownloadHub.app"
mkdir -p "${STAGE_DIST}"

PYINSTALLER_ARGS=(
  --noconfirm
  --name DownloadHub
  --windowed
  --icon "${APP_ICON}"
  --osx-bundle-identifier com.downloadhub.local
  --paths "${PROJECT_ROOT}/src"
  --hidden-import downloadhub.app
  --hidden-import aiosqlite
  --collect-data downloadhub
  --collect-all imageio_ffmpeg
  --collect-all yt_dlp
  --distpath "${STAGE_DIST}"
  --workpath "${WORK_DIR}/work"
  --specpath "${WORK_DIR}/spec"
  --add-data "${PROJECT_ROOT}/runtime-manifest.json:."
  --add-data "${PROJECT_ROOT}/LICENSE:."
  --add-data "${PROJECT_ROOT}/THIRD_PARTY_NOTICES.md:."
  --add-data "${PROJECT_ROOT}/src/downloadhub/static:downloadhub/static"
  --add-data "${PROJECT_ROOT}/src/downloadhub/templates:downloadhub/templates"
)

RUNTIME_PATHS=()
if "${PYTHON_BIN}" "${PROJECT_ROOT}/scripts/runtime_manager.py" paths \
  >"${WORK_DIR}/runtime-paths.txt" 2>"${WORK_DIR}/runtime-paths.err"; then
  while IFS= read -r runtime_path; do
    [[ -n "${runtime_path}" ]] && RUNTIME_PATHS+=("${runtime_path}")
  done < "${WORK_DIR}/runtime-paths.txt"
fi
for runtime_path in "${RUNTIME_PATHS[@]}"; do
  PYINSTALLER_ARGS+=(--add-binary "${runtime_path}:runtime/bin")
done

cd "${PROJECT_ROOT}"
"${PYINSTALLER_BIN}" "${PYINSTALLER_ARGS[@]}" "${PROJECT_ROOT}/scripts/app_entry.py"

if ! /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${APP_VERSION}" \
  "${STAGED_APP}/Contents/Info.plist" >/dev/null 2>&1; then
  /usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string ${APP_VERSION}" \
    "${STAGED_APP}/Contents/Info.plist"
fi
if ! /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${APP_VERSION}" \
  "${STAGED_APP}/Contents/Info.plist" >/dev/null 2>&1; then
  /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string ${APP_VERSION}" \
    "${STAGED_APP}/Contents/Info.plist"
fi

# Finder/provenance extended attributes copied from source files make an otherwise
# valid bundle unverifiable by codesign. Strip them only from this newly-created,
# fixed output path; source files and user data are never touched. `xattr -r` walks
# children but leaves attributes on the bundle root on some macOS versions, so clear
# the root explicitly as well.
/usr/bin/xattr -c "${STAGED_APP}"
/usr/bin/xattr -cr "${STAGED_APP}"
/usr/bin/xattr -d com.apple.FinderInfo "${STAGED_APP}" 2>/dev/null || true
/usr/bin/xattr -d com.apple.ResourceFork "${STAGED_APP}" 2>/dev/null || true

if [[ -n "${DOWNLOADHUB_CODESIGN_IDENTITY:-}" ]]; then
  /usr/bin/codesign --force --deep --options runtime --timestamp \
    --sign "${DOWNLOADHUB_CODESIGN_IDENTITY}" "${STAGED_APP}"
  print "Developer ID ile imzalandı: ${DOWNLOADHUB_CODESIGN_IDENTITY}"
else
  /usr/bin/codesign --force --deep --sign - "${STAGED_APP}"
  print -u2 "UYARI: Uygulama yalnız ad-hoc imzalandı; notarizasyon için Developer ID gerekir."
fi

# Plist/codesign notifications can cause File Provider to attach FinderInfo to an app
# directory. It is not signature content and must not be conveyed in a release.
/usr/bin/xattr -d com.apple.FinderInfo "${STAGED_APP}" 2>/dev/null || true
/usr/bin/xattr -d com.apple.ResourceFork "${STAGED_APP}" 2>/dev/null || true
/usr/bin/codesign --verify --deep --strict --verbose=2 "${STAGED_APP}"

# Copy the finished bundle without resource forks or extended attributes. This keeps
# cloud/File-Provider metadata from contaminating the deliverable in dist/.
/usr/bin/ditto --norsrc --noextattr "${STAGED_APP}" "${OUTPUT_APP}"
/usr/bin/xattr -c "${OUTPUT_APP}"
/usr/bin/xattr -cr "${OUTPUT_APP}"
if ! /usr/bin/rsync -nrlc --delete --itemize-changes \
  "${STAGED_APP}/" "${OUTPUT_APP}/" >"${WORK_DIR}/output-content-diff.log"; then
  print -u2 "HATA: dist/ kopyası imzası doğrulanmış staging bundle ile aynı değil."
  /usr/bin/tail -20 "${WORK_DIR}/output-content-diff.log" >&2
  exit 1
fi
if [[ -s "${WORK_DIR}/output-content-diff.log" ]]; then
  print -u2 "HATA: dist/ kopyası imzası doğrulanmış staging bundle ile aynı değil."
  /usr/bin/tail -20 "${WORK_DIR}/output-content-diff.log" >&2
  exit 1
fi

# iCloud/File Provider may recreate a zero-length FinderInfo attribute immediately
# after a .app appears in dist/. Clear and verify as one retryable operation. The
# signed contents never change; only out-of-band filesystem metadata is removed.
OUTPUT_VERIFIED=0
/bin/sleep 1
for attempt in 1 2 3 4 5 6 7 8 9 10; do
  /usr/bin/xattr -d com.apple.FinderInfo "${OUTPUT_APP}" 2>/dev/null || true
  /usr/bin/xattr -d com.apple.ResourceFork "${OUTPUT_APP}" 2>/dev/null || true
  if /usr/bin/codesign --verify --deep --strict "${OUTPUT_APP}" \
    2>"${WORK_DIR}/output-codesign-${attempt}.log"; then
    OUTPUT_VERIFIED=1
    break
  fi
  /bin/sleep 1
done
if (( OUTPUT_VERIFIED == 0 )); then
  if /usr/bin/xattr -p com.apple.FinderInfo "${OUTPUT_APP}" >/dev/null 2>&1 \
    && ! /usr/bin/xattr -p com.apple.ResourceFork "${OUTPUT_APP}" >/dev/null 2>&1; then
    print -u2 "UYARI: File Provider FinderInfo özniteliğini yeniden ekledi."
    print -u2 "İmzalı staging bundle doğrulandı ve dist/ dosya içerikleri birebir eşleşiyor; DMG hazırlığı öznitelikleri yeniden temizleyecek."
  else
    print -u2 "HATA: Çıktı uygulamasının kod imzası doğrulanamadı."
    /usr/bin/tail -20 "${WORK_DIR}/output-codesign-10.log" >&2
    exit 1
  fi
fi
print "Hazır: ${OUTPUT_APP}"
