#!/bin/zsh
set -u

PROJECT_ROOT="${HOME}/Developer/PDFStudio"
PYTHON_BIN="${PROJECT_ROOT}/.venv/bin/python"
LOG_FILE="${PROJECT_ROOT}/storage/launcher.log"

# Port defteri: 8000-8010 Sınav Okur'a ayrılı; PDF Studio aralığı 8060-8070.
BASE_PORT="${PDFSTUDIO_PORT:-8060}"
MAX_PORT=$(( BASE_PORT + 10 ))
APP_SIGNATURE='"app": *"pdf-studio"'

show_error() {
  /usr/bin/osascript -e 'on run argv
    display alert "PDF Studio açılamadı" message (item 1 of argv) as critical
  end run' "$1" >/dev/null 2>&1 || true
}

log_banner() {
  print -- "==== $(/bin/date '+%Y-%m-%d %H:%M:%S') — $1 ====" >>"${LOG_FILE}"
}

# Portta bir TCP dinleyici var mı? (curl yerine lsof: HTTP olmayan veya yavaş
# yanıt veren dinleyiciler de doğru şekilde "dolu" sayılır)
port_busy() {
  /usr/sbin/lsof -nP -iTCP:"$1" -sTCP:LISTEN -t >/dev/null 2>&1
}

# Portta GERÇEKTEN PDF Studio mu var? "Port dolu" yetmez — 8000 vakasında
# /health'e 200 dönen başka bir uygulama bizim sanılmıştı.
is_ours() {
  /usr/bin/curl --silent --max-time 2 "http://127.0.0.1:$1/health" 2>/dev/null \
    | /usr/bin/grep -q "${APP_SIGNATURE}"
}

# 1) Aralıkta zaten çalışan bir PDF Studio varsa sadece tarayıcıyı aç.
for (( p = BASE_PORT; p <= MAX_PORT; p++ )); do
  if is_ours "${p}"; then
    /usr/bin/open "http://127.0.0.1:${p}"
    exit 0
  fi
done

if [[ ! -d "${PROJECT_ROOT}" ]]; then
  show_error "Proje klasörü bulunamadı: ${PROJECT_ROOT}"
  exit 1
fi
if [[ ! -x "${PYTHON_BIN}" ]]; then
  show_error "Python çalışma ortamı bulunamadı: ${PYTHON_BIN}
Kurulum için proje klasöründe 'uv sync' çalıştırın."
  exit 1
fi

/bin/mkdir -p "${PROJECT_ROOT}/storage"

# Log rotasyonu: 1 MB'ı aşan log sıfırlanır.
if [[ -f "${LOG_FILE}" ]] && (( $(/usr/bin/stat -f %z "${LOG_FILE}") > 1048576 )); then
  : >"${LOG_FILE}"
fi
log_banner "başlatma denemesi"

# 2) Sağlık yanıtı yokken hâlâ yaşayan sunucu süreci = donmuş/terkedilmiş; temizle.
#    Desen bilinçli olarak .venv/bin/python + run.py ikilisini arar: yalnız gerçek
#    sunucu süreçleri eşleşir; run.py'yi editörde açan vim/code/tail eşleşmez.
#    (Eski ~/Documents kopyasının artıklarını da kapsar.)
STALE_PATTERN="PDFStudio/\.venv/bin/python[0-9.]* .*run\.py"
STALE_PIDS=$(/usr/bin/pgrep -f "${STALE_PATTERN}" || true)
if [[ -n "${STALE_PIDS}" ]]; then
  # Sunucu gerçekten donmuş olmayabilir: uzun bir işlem sırasında /health geç
  # yanıtlar, ya da süreç henüz açılış aşamasındadır. Öldürmeden önce birkaç
  # kez bekleyip yeniden dene.
  for _ in 1 2 3; do
    /bin/sleep 3
    for (( p = BASE_PORT; p <= MAX_PORT; p++ )); do
      if is_ours "${p}"; then
        /usr/bin/open "http://127.0.0.1:${p}"
        exit 0
      fi
    done
  done
  STALE_PIDS=$(/usr/bin/pgrep -f "${STALE_PATTERN}" || true)
fi
if [[ -n "${STALE_PIDS}" ]]; then
  log_banner "donmuş süreç temizliği: ${STALE_PIDS}"
  echo "${STALE_PIDS}" | /usr/bin/xargs /bin/kill 2>/dev/null || true
  /bin/sleep 2
  STALE_PIDS=$(/usr/bin/pgrep -f "${STALE_PATTERN}" || true)
  [[ -n "${STALE_PIDS}" ]] && echo "${STALE_PIDS}" | /usr/bin/xargs /bin/kill -9 2>/dev/null || true
fi

# 3) Aralıktan ilk boş portu seç (başka uygulamanın işgal ettiği portu atla).
PORT=""
for (( p = BASE_PORT; p <= MAX_PORT; p++ )); do
  if ! port_busy "${p}"; then
    PORT="${p}"
    break
  fi
done
if [[ -z "${PORT}" ]]; then
  show_error "${BASE_PORT}-${MAX_PORT} aralığındaki tüm portlar dolu. Diğer yerel uygulamaları kapatıp yeniden deneyin."
  exit 1
fi
log_banner "port ${PORT} seçildi"

cd "${PROJECT_ROOT}" || exit 1

# PYTHONUNBUFFERED: log satır satır aksın (önceki sürümde blok buffer yüzünden
# donan süreç log'a tek satır bile yazmamıştı).
PYTHONUNBUFFERED=1 PDFSTUDIO_OPEN_BROWSER=0 PDFSTUDIO_PORT="${PORT}" \
  PYTHONPATH="${PROJECT_ROOT}" \
  "${PYTHON_BIN}" "${PROJECT_ROOT}/run.py" >>"${LOG_FILE}" 2>&1 </dev/null &
SERVER_PID=$!

for _ in {1..120}; do
  if is_ours "${PORT}"; then
    /usr/bin/open "http://127.0.0.1:${PORT}"
    exit 0
  fi
  if ! /bin/kill -0 "${SERVER_PID}" 2>/dev/null; then
    show_error "Sunucu başlatılamadı. Son log satırları:
$(/usr/bin/tail -n 3 "${LOG_FILE}" 2>/dev/null)"
    exit 1
  fi
  /bin/sleep 0.25
done

# Zaman aşımı: başlattığımız süreci arkada bırakma (eski sürümün sızıntısı).
/bin/kill "${SERVER_PID}" 2>/dev/null || true
/bin/sleep 2
/bin/kill -9 "${SERVER_PID}" 2>/dev/null || true
log_banner "zaman aşımı — süreç ${SERVER_PID} sonlandırıldı"
show_error "Sunucu 30 saniye içinde hazır olmadı; süreç sonlandırıldı. Ayrıntılar: storage/launcher.log"
exit 1
