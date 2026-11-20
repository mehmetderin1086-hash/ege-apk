#!/bin/zsh
set -u

project_dir="__PROJECT_DIR__"
python_bin="$project_dir/.venv/bin/python"
entry_bin="$project_dir/.venv/bin/sinav-okur"
log_dir="/Users/mehmetderin/Library/Logs/SinavOkur"
server_log="$log_dir/server.log"
launcher_log="$log_dir/launcher.log"
pid_file="$log_dir/server.pid"

mkdir -p "$log_dir"
exec >>"$launcher_log" 2>&1

timestamp() {
  /bin/date "+%Y-%m-%d %H:%M:%S"
}

expected_app() {
  local port="$1"
  /usr/bin/curl -fsS --connect-timeout 1 --max-time 2 \
    "http://127.0.0.1:${port}/" 2>/dev/null |
    /usr/bin/grep -q "Sınav değerlendirme merkezi"
}

port_in_use() {
  /usr/sbin/lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1
}

show_error() {
  local message="$1"
  /usr/bin/osascript -e "display alert \"Sınav Okur açılamadı\" message \"$message\" as critical buttons {\"Tamam\"} default button \"Tamam\"" >/dev/null 2>&1
}

echo "[$(timestamp)] Başlatıcı çalıştı."

if [[ ! -x "$python_bin" || ! -x "$entry_bin" ]]; then
  echo "[$(timestamp)] Python ortamı bulunamadı: $entry_bin"
  show_error "Programın Python ortamı bulunamadı. Proje klasörü taşınmış veya .venv silinmiş olabilir."
  exit 1
fi

for port in {8000..8010}; do
  if expected_app "$port"; then
    echo "[$(timestamp)] Çalışan Sınav Okur bulundu: $port"
    /usr/bin/open "http://127.0.0.1:${port}/"
    exit 0
  fi
done

selected_port=""
for port in {8000..8010}; do
  if ! port_in_use "$port"; then
    selected_port="$port"
    break
  fi
done

if [[ -z "$selected_port" ]]; then
  echo "[$(timestamp)] 8000-8010 aralığında boş port yok."
  show_error "8000–8010 arasındaki tüm yerel bağlantı noktaları kullanımda."
  exit 1
fi

echo "[$(timestamp)] Sunucu başlatılıyor: $selected_port"
cd "$project_dir" || exit 1
# Sıcak havuz: OCR alt süreçleri kalıcı çalışıp modeli bir kez yükler.
# Bu satır olmadan .app'te havuz kapalıydı ve her sayfa modeli yeniden
# yüklüyordu (ölçüldü: 7,5 dk/sayfa).
export SINAV_OKUR_SICAK_HAVUZ=1
# transformers'ın TensorFlow yolunu hiç yükleme: kurulu Keras 3 ile
# çakışıp gömlemciyi ValueError ile düşürüyor.
export USE_TF=0
nohup "$entry_bin" webapp \
  --db "$project_dir/sinav_okur.db" \
  --kirp-dizini "$project_dir/kirpintlar" \
  --veri-dizini "$project_dir/sinav_okur_veri" \
  --host 127.0.0.1 \
  --port "$selected_port" \
  >>"$server_log" 2>&1 </dev/null &
server_pid=$!
echo "$server_pid" >"$pid_file"

for _attempt in {1..60}; do
  if expected_app "$selected_port"; then
    echo "[$(timestamp)] Sunucu hazır; tarayıcı açılıyor."
    /usr/bin/open "http://127.0.0.1:${selected_port}/"
    exit 0
  fi
  if ! /bin/kill -0 "$server_pid" 2>/dev/null; then
    echo "[$(timestamp)] Sunucu hazır olmadan kapandı."
    show_error "Sunucu başlatılırken kapandı. Ayrıntılar ~/Library/Logs/SinavOkur/server.log dosyasındadır."
    exit 1
  fi
  /bin/sleep 0.5
done

echo "[$(timestamp)] Sunucu zaman aşımına uğradı."
show_error "Sunucu 30 saniye içinde hazır olmadı. Ayrıntılar ~/Library/Logs/SinavOkur/server.log dosyasındadır."
exit 1
