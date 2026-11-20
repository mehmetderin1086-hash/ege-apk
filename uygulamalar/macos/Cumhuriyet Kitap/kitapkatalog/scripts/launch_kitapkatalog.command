#!/bin/zsh
set -eu

# KitapKatalog başlatıcı — varsayılan olarak tarayıcıda açılan web arayüzünü
# çalıştırır. Eski PySide masaüstü arayüzü için: launch_kitapkatalog.command --qt

SCRIPT_DIRECTORY=${0:A:h}
PROJECT_DIRECTORY=${SCRIPT_DIRECTORY:h}

PYTHON_EXECUTABLE=""
if [[ -x "${PROJECT_DIRECTORY}/.venv/bin/python" ]]; then
  if "${PROJECT_DIRECTORY}/.venv/bin/python" -c 'import sys; raise SystemExit(sys.version_info[:2] != (3, 12))'; then
    PYTHON_EXECUTABLE="${PROJECT_DIRECTORY}/.venv/bin/python"
  fi
fi
if [[ -z "${PYTHON_EXECUTABLE}" ]] && command -v python3.12 >/dev/null 2>&1; then
  PYTHON_EXECUTABLE=$(command -v python3.12)
fi
if [[ -z "${PYTHON_EXECUTABLE}" ]]; then
  print -u2 "KitapKatalog için Python 3.12 bulunamadı."
  print -u2 "Proje bağımlılıklarını yerel wheel deposundan .venv içine kurun."
  exit 2
fi

if [[ -z "${KITAPKATALOG_MODEL_DIR:-}" ]]; then
  if [[ -f "${PROJECT_DIRECTORY}/KitapKatalog-models/model_manifest.lock.json" ]]; then
    export KITAPKATALOG_MODEL_DIR="${PROJECT_DIRECTORY}/KitapKatalog-models"
  elif [[ -f "${PROJECT_DIRECTORY}/models/model_manifest.lock.json" ]]; then
    export KITAPKATALOG_MODEL_DIR="${PROJECT_DIRECTORY}/models"
  fi
fi

export PYTHONPATH="${PROJECT_DIRECTORY}/src${PYTHONPATH:+:${PYTHONPATH}}"
export HF_HUB_OFFLINE=1
export TRANSFORMERS_OFFLINE=1
export HF_DATASETS_OFFLINE=1
export PIP_NO_INDEX=1
export PIP_DISABLE_PIP_VERSION_CHECK=1
export KITAPKATALOG_NETWORK_DISABLED=1

# Eski Qt masaüstü arayüzü istenirse doğrudan ona geç.
if [[ "${1:-}" == "--qt" ]]; then
  shift
  exec "${PYTHON_EXECUTABLE}" "${PROJECT_DIRECTORY}/deployment/entry.py" "$@"
fi

# Web oturumu ve günlükleri süreç doğduğu andan itibaren yalnız bu kullanıcıya
# açık oluşturulsun. Eski Qt dışa aktarma izinlerini değiştirme.
umask 077

# Çalışan bir KitapKatalog web sunucusu var mı? Başlatıcı yalnız
# app+nonce+version birebir eşleşen oturumu yeniden kullanır. Uyuşmayan canlı
# dinleyici ancak bu kullanıcıya ait beklenen Python modülü olduğu lsof+ps ile
# doğrulanırsa SIGTERM ile kapatılır; aksi halde ikinci sunucu açılmaz.
SESSION_FILE="${KITAPKATALOG_DATA_DIR:-${HOME}/Library/Application Support/KitapKatalog}/web_session.json"
set +e
"${PYTHON_EXECUTABLE}" -m kitapkatalog.webapp.server --check-session "${SESSION_FILE}"
SESSION_STATUS=$?
set -e
case "${SESSION_STATUS}" in
  0)
    exit 0
    ;;
  10)
    ;;
  *)
    # Ayrıntılı, tokensız hata Python yardımcı komutu tarafından stderr'e yazıldı.
    exit "${SESSION_STATUS}"
    ;;
esac

# --detach: masaüstü .app başlatıcısı için — sunucuyu arka planda başlat,
# log dosyasına yaz ve hemen çık (tarayıcıyı sunucu kendisi açar).
if [[ "${1:-}" == "--detach" ]]; then
  shift
  LOG_DIRECTORY="${KITAPKATALOG_DATA_DIR:-${HOME}/Library/Application Support/KitapKatalog}/logs"
  mkdir -p -m 700 "${LOG_DIRECTORY}"
  chmod 700 "${LOG_DIRECTORY}"
  : >> "${LOG_DIRECTORY}/web.log"
  chmod 600 "${LOG_DIRECTORY}/web.log"
  nohup "${PYTHON_EXECUTABLE}" -m kitapkatalog.webapp.server "$@" \
    >> "${LOG_DIRECTORY}/web.log" 2>&1 &
  exit 0
fi

exec "${PYTHON_EXECUTABLE}" -m kitapkatalog.webapp.server "$@"
