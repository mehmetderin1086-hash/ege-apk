#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_ROOT="${SCRIPT_DIR:h}"
VENV_PATH="${PROJECT_ROOT}/.venv"

if [[ "$(uname -s)" != "Darwin" || "$(uname -m)" != "arm64" ]]; then
  print -u2 "HATA: DownloadHub geliştirme ortamı macOS arm64 gerektirir."
  exit 2
fi

if [[ -L "${VENV_PATH}" ]]; then
  print -u2 "HATA: Güvenlik nedeniyle sembolik bağlantı olan .venv kullanılmaz."
  exit 2
fi

UV_BIN="$(command -v uv || true)"
if [[ -z "${UV_BIN}" && -x "${HOME}/.local/bin/uv" ]]; then
  UV_BIN="${HOME}/.local/bin/uv"
fi
if [[ -z "${UV_BIN}" ]]; then
  print -u2 "HATA: uv bulunamadı. Resmî uv kurulum belgelerini izleyip bu betiği yeniden çalıştırın:"
  print -u2 "      https://docs.astral.sh/uv/getting-started/installation/"
  print -u2 "Güvenlik nedeniyle bu betik uzaktan shell betiği indirip çalıştırmaz."
  exit 2
fi

cd "${PROJECT_ROOT}"
"${UV_BIN}" python install 3.12

if [[ ! -f "${PROJECT_ROOT}/uv.lock" ]]; then
  print "uv.lock bulunamadı; proje bağımlılıkları hash'leriyle kilitleniyor…"
  "${UV_BIN}" lock
fi

UV_PROJECT_ENVIRONMENT="${VENV_PATH}" "${UV_BIN}" sync \
  --locked \
  --no-editable \
  --all-extras

print "Python ortamı hazırlandı: ${VENV_PATH}"
print "Sabitlenmiş Deno runtime'ı doğrulanarak hazırlanıyor…"
"${VENV_PATH}/bin/python" "${PROJECT_ROOT}/scripts/runtime_manager.py" install deno
print "aria2, resmî kaynak paketinden AppleTLS ile hazırlanıyor…"
if ! "${VENV_PATH}/bin/python" "${PROJECT_ROOT}/scripts/runtime_manager.py" install aria2c; then
  print -u2 "UYARI: aria2 derlenemedi; tek akış HTTP kurtarma motoru kullanılacak."
  print -u2 "       Segmentli motor için Apple Command Line Tools kurup bootstrap'ı yeniden çalıştırın."
fi
"${VENV_PATH}/bin/python" "${PROJECT_ROOT}/scripts/runtime_manager.py" verify --required
"${VENV_PATH}/bin/python" "${PROJECT_ROOT}/scripts/runtime_manager.py" status
print ""
print "Runtime bileşenleri yalnız sabitlenmiş resmî HTTPS kaynakları ve SHA-256"
print "doğrulamasıyla kuruldu; Homebrew kullanılmadı."
print ""
"${VENV_PATH}/bin/python" "${PROJECT_ROOT}/scripts/diagnose.py" || true
print ""
print "Başlatmak için: zsh scripts/run.sh"
