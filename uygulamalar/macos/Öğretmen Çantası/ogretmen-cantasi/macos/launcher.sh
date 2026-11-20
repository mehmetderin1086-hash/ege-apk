#!/bin/zsh
set -u

resources_dir="${0:A:h}"
entry_bin="$resources_dir/runtime/ogretmen-cantasi"
log_dir="$HOME/Library/Logs/OgretmenCantasi"
server_log="$log_dir/server.log"
launcher_log="$log_dir/launcher.log"
pid_file="$log_dir/server.pid"
lock_dir="$log_dir/baslatma.lock"
expected_version="0.3.0"

# Port aralığı: 8000 PDF Studio, 8000-8010 Sınav Okur, 8010 SesLab,
# 8020-8030 Soru Çözücü, 8317 CLI Proxy, 8766 BioProf kullanıyor.
port_start=8040
port_end=8050

mkdir -p "$log_dir"

rotate_log() {
  local log="$1"
  if [[ -f "$log" ]] && (( $(/usr/bin/stat -f%z "$log") > 5242880 )); then
    /bin/mv -f "${log}.2" "${log}.3" 2>/dev/null || true
    /bin/mv -f "${log}.1" "${log}.2" 2>/dev/null || true
    /bin/mv -f "$log" "${log}.1"
  fi
}
rotate_log "$launcher_log"
rotate_log "$server_log"
exec >>"$launcher_log" 2>&1

timestamp() {
  /bin/date "+%Y-%m-%d %H:%M:%S"
}

# "Port dolu mu" değil, "portta GERÇEKTEN bu program mı" diye bakılır: yalnız
# doluluğa bakmak, kardeş bir programın sayfasını açmaya yol açar.
expected_app() {
  local port="$1"
  /usr/bin/curl -fsS --connect-timeout 1 --max-time 2 \
    "http://127.0.0.1:${port}/saglik" 2>/dev/null |
    /usr/bin/grep -q "\"uygulama\":\"ogretmen-cantasi\".*\"surum\":\"${expected_version}\""
}

port_in_use() {
  /usr/sbin/lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1
}

show_error() {
  local message="$1"
  /usr/bin/osascript -e "display alert \"Öğretmen Çantası açılamadı\" message \"$message\" as critical buttons {\"Tamam\"} default button \"Tamam\"" >/dev/null 2>&1
}

echo "[$(timestamp)] Başlatıcı çalıştı."

if [[ ! -x "$entry_bin" ]]; then
  echo "[$(timestamp)] Python ortamı bulunamadı: $entry_bin"
  show_error "Programın Python ortamı bulunamadı. Proje klasörü taşınmış ya da .venv silinmiş olabilir."
  exit 1
fi

# Zaten açıksa yeni sunucu başlatma, var olan sekmeyi öne getir.
for port in {$port_start..$port_end}; do
  if expected_app "$port"; then
    echo "[$(timestamp)] Çalışan sunucu bulundu: $port"
    /usr/bin/open "http://127.0.0.1:${port}/"
    exit 0
  fi
done

# İki hızlı çift tıklamadan yalnız biri port seçip sunucu başlatır.
if ! /bin/mkdir "$lock_dir" 2>/dev/null; then
  for _attempt in {1..60}; do
    for port in {$port_start..$port_end}; do
      if expected_app "$port"; then
        /usr/bin/open "http://127.0.0.1:${port}/"
        exit 0
      fi
    done
    /bin/sleep 0.5
  done
  /bin/rmdir "$lock_dir" 2>/dev/null || true
  if ! /bin/mkdir "$lock_dir" 2>/dev/null; then
    show_error "Başka bir başlatma işlemi tamamlanamadı."
    exit 1
  fi
fi
trap '/bin/rmdir "$lock_dir" 2>/dev/null || true' EXIT

selected_port=""
for port in {$port_start..$port_end}; do
  if ! port_in_use "$port"; then
    selected_port="$port"
    break
  fi
done

if [[ -z "$selected_port" ]]; then
  echo "[$(timestamp)] $port_start-$port_end aralığında boş port yok."
  show_error "${port_start}–${port_end} arasındaki tüm yerel bağlantı noktaları kullanımda."
  exit 1
fi

# Finder'dan açılan bir .app kabuk profilini (.zshrc) OKUMAZ; orada tanımlı
# OGRETMEN_* değişkenleri buraya ulaşmaz. Sesli yoklamanın whisper yolları
# özelleştirilmişse bu dosyadan gelir.
ortam_dosyasi="$HOME/.ogretmen-cantasi/ortam.sh"
if [[ -f "$ortam_dosyasi" ]]; then
  echo "[$(timestamp)] Ortam dosyası yükleniyor: $ortam_dosyasi"
  # shellcheck source=/dev/null
  source "$ortam_dosyasi"
fi

echo "[$(timestamp)] Sunucu başlatılıyor: port=$selected_port"
cd "$resources_dir" || exit 1
nohup "$entry_bin" sunucu --adres 127.0.0.1 --port "$selected_port" \
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
    show_error "Sunucu başlatılırken kapandı. Ayrıntılar ~/Library/Logs/OgretmenCantasi/server.log dosyasındadır."
    exit 1
  fi
  /bin/sleep 0.5
done

echo "[$(timestamp)] Sunucu zaman aşımına uğradı."
show_error "Sunucu 30 saniye içinde hazır olmadı. Ayrıntılar ~/Library/Logs/OgretmenCantasi/server.log dosyasındadır."
exit 1
