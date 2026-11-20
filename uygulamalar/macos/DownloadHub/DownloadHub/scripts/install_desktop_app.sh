#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_ROOT="${SCRIPT_DIR:h}"
SOURCE_APP="${PROJECT_ROOT}/dist/DownloadHub.app"
APPLICATIONS_DIR="${HOME}/Applications"
INSTALLED_APP="${APPLICATIONS_DIR}/DownloadHub.app"
DESKTOP_APP="${HOME}/Desktop/DownloadHub.app"
ARCHIVE_DIR="${PROJECT_ROOT}/build/app-archive"
INSTALL_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
STAGED_APP="${APPLICATIONS_DIR}/.DownloadHub-install-${INSTALL_ID}.app"

if [[ "$(uname -s)" != "Darwin" || "$(uname -m)" != "arm64" ]]; then
  print -u2 "HATA: DownloadHub masaüstü uygulaması Apple Silicon macOS içindir."
  exit 2
fi
if [[ ! -d "${SOURCE_APP}" ]]; then
  print -u2 "HATA: Paket bulunamadı: ${SOURCE_APP}"
  print -u2 "Önce çalıştırın: zsh scripts/build_app.sh"
  exit 2
fi

mkdir -p "${APPLICATIONS_DIR}" "${ARCHIVE_DIR}"

cleanup() {
  case "${STAGED_APP}" in
    "${APPLICATIONS_DIR}"/.DownloadHub-install-*.app)
      [[ -e "${STAGED_APP}" ]] && rm -rf -- "${STAGED_APP}"
      ;;
  esac
}
trap cleanup EXIT INT TERM

/usr/bin/ditto --norsrc --noextattr "${SOURCE_APP}" "${STAGED_APP}"
/usr/bin/xattr -cr "${STAGED_APP}" 2>/dev/null || true
/usr/bin/codesign --verify --deep --strict "${STAGED_APP}"

if [[ -e "${INSTALLED_APP}" ]]; then
  /bin/mv "${INSTALLED_APP}" \
    "${ARCHIVE_DIR}/DownloadHub-applications-before-${INSTALL_ID}.app"
fi
/bin/mv "${STAGED_APP}" "${INSTALLED_APP}"

if [[ -L "${DESKTOP_APP}" ]]; then
  /bin/rm -- "${DESKTOP_APP}"
elif [[ -e "${DESKTOP_APP}" ]]; then
  /bin/mv "${DESKTOP_APP}" \
    "${ARCHIVE_DIR}/DownloadHub-desktop-before-${INSTALL_ID}.app"
fi
/bin/ln -s "${INSTALLED_APP}" "${DESKTOP_APP}"

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"${LSREGISTER}" -f "${INSTALLED_APP}"

/usr/bin/codesign --verify --deep --strict "${INSTALLED_APP}"
print "Hazır: ${INSTALLED_APP}"
print "Masaüstü bağlantısı: ${DESKTOP_APP}"
