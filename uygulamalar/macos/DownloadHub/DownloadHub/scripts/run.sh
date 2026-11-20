#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_ROOT="${SCRIPT_DIR:h}"
VENV_BIN="${PROJECT_ROOT}/.venv/bin"

if [[ ! -x "${VENV_BIN}/downloadhub" ]]; then
  print -u2 "HATA: Geliştirme ortamı hazır değil. Önce çalıştırın: zsh scripts/bootstrap.sh"
  exit 2
fi

if [[ "${DOWNLOADHUB_HOST:-127.0.0.1}" != "127.0.0.1" ]]; then
  print -u2 "HATA: DownloadHub yalnız 127.0.0.1 üzerinde dinleyebilir."
  exit 2
fi
export DOWNLOADHUB_HOST="127.0.0.1"
export DOWNLOADHUB_PORT="${DOWNLOADHUB_PORT:-8765}"
# Some macOS File Provider volumes mark uv's underscore-prefixed editable .pth
# file as UF_HIDDEN. Python deliberately skips hidden .pth files, so keep the
# development entry point deterministic by adding the src layout explicitly.
export PYTHONPATH="${PROJECT_ROOT}/src${PYTHONPATH:+:${PYTHONPATH}}"

for component in aria2c ffmpeg deno yt-dlp; do
  candidate="${PROJECT_ROOT}/runtime/bin/${component}"
  if [[ -x "${candidate}" ]]; then
    case "${component}" in
      aria2c) export DOWNLOADHUB_ARIA2_PATH="${candidate}" ;;
      ffmpeg) export DOWNLOADHUB_FFMPEG_PATH="${candidate}" ;;
      deno) export DOWNLOADHUB_DENO_PATH="${candidate}" ;;
      yt-dlp) export DOWNLOADHUB_YT_DLP_PATH="${candidate}" ;;
    esac
  fi
done

cd "${PROJECT_ROOT}"
exec "${VENV_BIN}/downloadhub" "$@"
