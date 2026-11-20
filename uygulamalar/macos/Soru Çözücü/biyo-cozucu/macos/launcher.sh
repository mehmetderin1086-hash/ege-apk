#!/bin/zsh
set -u

# `__PROJECT_DIR__` kurulum sırasında gerçek yolla değiştirilir
# (bkz. scripts/install_macos_app.py).
project_dir="__PROJECT_DIR__"
entry_bin="$project_dir/.venv/bin/biyo-cozucu"
log_dir="$HOME/Library/Logs/BiyoCozucu"
server_log="$log_dir/server.log"
launcher_log="$log_dir/launcher.log"
pid_file="$log_dir/server.pid"
lock_file="$log_dir/launch.lock"

# Port aralığı bilinçli olarak 8020'den başlıyor: 8000'i PDF Studio, 8000-8010
# aralığını Sınav Okur, 8010'u SesLab kullanıyor. Aynı aralığa girmek iki
# programın birbirinin sunucusunu "kendi sunucusu" sanmasına yol açardı.
port_start=8020
port_end=8030
app_id="biyo-cozucu"
launcher_path="$0"

server_pid=""
lock_held=0
health_app=""
health_build=""
health_pid=""
health_status=""

mkdir -p "$log_dir"
exec >>"$launcher_log" 2>&1

# Betiğin içeriği kurulu launcher build'inin kimliğidir. Child'a yalnız bu
# komut için aktarılır; /healthz aynı değeri döndürmedikçe sunucu hazır sayılmaz.
build_id="$(/usr/bin/shasum -a 256 "$launcher_path" 2>/dev/null | /usr/bin/awk '{print substr($1, 1, 24)}')"
if [[ -z "$build_id" ]]; then
  build_id="launcher-unknown"
fi

timestamp() {
  /bin/date "+%Y-%m-%d %H:%M:%S"
}

# PID ve lock sahipleri yalnız tamamı rakam olan değerler olabilir.
read_pid() {
  local file="$1"
  local value=""
  [[ -f "$file" ]] || return 1
  IFS= read -r value <"$file" || true
  [[ "$value" =~ '^[0-9]+$' ]] || return 1
  print -r -- "$value"
}

pid_alive() {
  local pid="$1"
  [[ "$pid" =~ '^[0-9]+$' ]] && /bin/kill -0 "$pid" 2>/dev/null
}

pid_is_server() {
  local pid="$1"
  local command=""
  pid_alive "$pid" || return 1
  command="$(/bin/ps -p "$pid" -o command= 2>/dev/null)"
  [[ "$command" == *"$entry_bin sunucu"* ]]
}

pid_is_our_child() {
  local pid="$1"
  local parent=""
  pid_alive "$pid" || return 1
  parent="$(/bin/ps -p "$pid" -o ppid= 2>/dev/null)"
  parent="${parent//[[:space:]]/}"
  [[ "$parent" == "$$" ]]
}

atomic_write() {
  local target="$1"
  local value="$2"
  local temp="${target}.$$.$RANDOM.tmp"
  if ! /usr/bin/printf '%s\n' "$value" >"$temp"; then
    /bin/rm -f "$temp"
    return 1
  fi
  if ! /bin/mv -f "$temp" "$target"; then
    /bin/rm -f "$temp"
    return 1
  fi
}

clear_pid_file() {
  local expected="${1:-}"
  local current=""
  [[ -e "$pid_file" ]] || return 0
  current="$(read_pid "$pid_file" 2>/dev/null || true)"
  if [[ -z "$expected" || "$current" == "$expected" ]]; then
    /bin/rm -f "$pid_file"
  fi
}

release_lock() {
  (( lock_held )) || return 0
  exec 9>&-
  lock_held=0
}

cleanup_started_server() {
  local pid="$server_pid"
  [[ -n "$pid" ]] || return 0

  if pid_is_our_child "$pid" || pid_is_server "$pid"; then
    echo "[$(timestamp)] Child temizleniyor: PID=$pid TERM"
    /bin/kill -TERM "$pid" 2>/dev/null || true
    for _cleanup_attempt in {1..20}; do
      pid_alive "$pid" || break
      /bin/sleep 0.1
    done
    if pid_is_our_child "$pid" || pid_is_server "$pid"; then
      echo "[$(timestamp)] Child TERM ile kapanmadı: PID=$pid KILL"
      /bin/kill -KILL "$pid" 2>/dev/null || true
      for _cleanup_attempt in {1..10}; do
        pid_alive "$pid" || break
        /bin/sleep 0.1
      done
    fi
    wait "$pid" 2>/dev/null || true
  fi
  clear_pid_file "$pid"
  server_pid=""
}

cleanup_on_exit() {
  local exit_code=$?
  if [[ -n "$server_pid" ]]; then
    cleanup_started_server
  fi
  release_lock
  return "$exit_code"
}

trap cleanup_on_exit EXIT
trap 'exit 130' HUP INT TERM

acquire_lock() {
  # FD tabanlı BSD kilidi süreçle birlikte çekirdek tarafından bırakılır;
  # lock dosyasının kalması kilit anlamına gelmez ve stale-owner/ABA yarışı yoktur.
  exec 9>"$lock_file" || return 1
  if /usr/bin/lockf -s -t 40 9; then
    lock_held=1
    return 0
  fi
  exec 9>&-
  return 1
}

json_string() {
  local json="$1"
  local key="$2"
  print -r -- "$json" |
    /usr/bin/sed -nE "s/^.*\"${key}\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*$/\\1/p"
}

json_number() {
  local json="$1"
  local key="$2"
  print -r -- "$json" |
    /usr/bin/sed -nE "s/^.*\"${key}\"[[:space:]]*:[[:space:]]*([0-9]+).*$/\\1/p"
}

# Portta GERÇEKTEN bu program mı çalışıyor: HTML işareti yerine kimlikli,
# auth gerektirmeyen fakat yalnız loopback'e açık /healthz yanıtı kullanılır.
health_probe() {
  local port="$1"
  local json=""
  json="$(/usr/bin/curl -fsS --connect-timeout 1 --max-time 2 \
    "http://127.0.0.1:${port}/healthz" 2>/dev/null)" || return 1
  health_app="$(json_string "$json" app)"
  health_build="$(json_string "$json" build)"
  health_pid="$(json_number "$json" pid)"
  health_status="$(json_string "$json" status)"
  [[ "$health_app" == "$app_id" && "$health_status" == "ready" &&
     -n "$health_build" && "$health_pid" =~ '^[0-9]+$' ]]
}

pid_owns_port() {
  local pid="$1"
  local port="$2"
  /usr/sbin/lsof -nP -a -p "$pid" -iTCP:"$port" -sTCP:LISTEN \
    >/dev/null 2>&1
}

# Var olan sunucuyu KULLANMA ölçütü: doğru uygulama, doğru komut satırı ve
# portun gerçekten o sürece ait olması. Build eşitliği ARANMAZ — Biyoloji
# Stüdyosu ve eski Soru Çözücü kısayolları farklı launcher SHA'sı taşır;
# build eşitliği istenirse ikisi aynı veri klasörüne bakan İKİ sunucu açardı.
# Build farkı yalnız günlüğe yazılır. (Başlatma yolunda build eşitliği hâlâ
# zorunludur: orada child'ın bizim başlattığımız süreç olduğunu kanıtlar.)
valid_server_on_port() {
  local port="$1"
  health_probe "$port" || return 1
  pid_is_server "$health_pid" || return 1
  pid_owns_port "$health_pid" "$port" || return 1
  if [[ "$health_build" != "$build_id" ]]; then
    # stdout ÇAĞIRANIN dönüş değeridir (find_existing_server komut ikamesiyle
    # okur), stderr ise çağrı yerinde /dev/null'a gidiyor. Günlük satırı bu
    # yüzden doğrudan dosyaya yazılır.
    echo "[$(timestamp)] Farklı build'li sunucu kullanılıyor: port=$port build=$health_build (bizimki $build_id)" >>"$launcher_log"
  fi
  return 0
}

find_port_for_pid() {
  local wanted_pid="$1"
  local port
  for port in {$port_start..$port_end}; do
    if valid_server_on_port "$port" && [[ "$health_pid" == "$wanted_pid" ]]; then
      print -r -- "$port"
      return 0
    fi
  done
  return 1
}

find_existing_server() {
  local port
  for port in {$port_start..$port_end}; do
    if valid_server_on_port "$port"; then
      print -r -- "${port}:${health_pid}:${health_build}"
      return 0
    fi
  done
  return 1
}

port_in_use() {
  /usr/sbin/lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1
}

show_error() {
  local message="$1"
  /usr/bin/osascript -e "display alert \"Biyoloji Stüdyosu açılamadı\" message \"$message\" as critical buttons {\"Tamam\"} default button \"Tamam\"" >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Yardımcı servisler: Soru Kesici, BioProf ve BioProf'un kendi bağımlıları.
#
# Biyoloji Stüdyosu tek program gibi görünür ama altında bağımsız süreçler
# çalışır. Hepsi arka planda, Stüdyo'yu bekletmeden ayağa kaldırılır. İki
# kural: (1) "port dolu" değil "portta gerçekten O program mı" diye bakılır,
# (2) her servisin kendi kilidi vardır; iki kısayol aynı anda açılsa bile
# ikinci kopya başlatılmaz.
# ---------------------------------------------------------------------------
soru_kesici_port=8756
seslab_port=8010
cliproxy_port=8317

service_healthy() {
  local url="$1" signature="$2" json=""
  json="$(/usr/bin/curl -fsS --connect-timeout 1 --max-time 2 "$url" 2>/dev/null)" || return 1
  [[ -z "$signature" || "$json" == *"$signature"* ]]
}

# Kilit, servis sağlıklı olana kadar (en çok 20 sn) tutulur. Kilidi hemen
# bırakmak, "başlattım ama daha portu açmadı" penceresinde ikinci bir kopyanın
# doğmasına izin verirdi.
# Çağrı öncesi ayarlanır; start_service_once okuyup sıfırlar.
service_cwd=""

# Kilidi `lockf`in komut biçimiyle alıyoruz: kilit, altındaki komut bitene
# kadar tutulur. Böylece "başlattım ama servis daha portu açmadı" penceresinde
# ikinci bir kopya doğamaz. -t 0: kilit başkasındaysa hemen vazgeç (o zaten
# başlatıyor), -k: kilit dosyası kalıcı olsun.
start_service_once() {
  local name="$1" url="$2" signature="$3"
  shift 3
  local calisma_dizini="$service_cwd"
  service_cwd=""
  service_healthy "$url" "$signature" && return 0
  local lock="$log_dir/companion-${name}.lock"
  local service_log="$log_dir/${name}.log"
  (
    exec 9>&-
    /usr/bin/lockf -s -t 0 -k "$lock" /bin/zsh -c '
      url="$1"; sig="$2"; wd="$3"; slog="$4"; ad="$5"
      shift 5
      saglikli() {
        local json=""
        json="$(/usr/bin/curl -fsS --connect-timeout 1 --max-time 2 "$url" 2>/dev/null)" ||
          return 1
        [[ -z "$sig" || "$json" == *"$sig"* ]]
      }
      # Kilit altında ikinci yoklama: kilidi bekleyen başka bir yol bu arada
      # servisi ayağa kaldırmış olabilir.
      saglikli && exit 0
      [[ -n "$wd" ]] && { cd "$wd" || exit 0; }
      echo "[$(/bin/date "+%Y-%m-%d %H:%M:%S")] $ad başlatılıyor."
      nohup "$@" >>"$slog" 2>&1 </dev/null &
      for _wait in {1..40}; do
        saglikli && break
        /bin/sleep 0.5
      done
    ' zsh "$url" "$signature" "$calisma_dizini" "$service_log" "$name" "$@"
  ) &
  disown 2>/dev/null || true
}

ensure_soru_kesici() {
  local kok="${SORU_KESICI_KOK:-$HOME/Developer/soru-kesici}"
  [[ -f "$kok/soru_kes_web.py" ]] || kok="$HOME/Documents/soru-kesici"
  if [[ ! -x "$kok/.venv/bin/python" || ! -f "$kok/soru_kes_web.py" ]]; then
    echo "[$(timestamp)] Soru Kesici kurulumu bulunamadı, atlandı."
    return 0
  fi
  service_cwd="$kok"
  start_service_once "soru-kesici" \
    "http://127.0.0.1:${soru_kesici_port}/healthz" '"soru-kesici"' \
    "$kok/.venv/bin/python" "$kok/soru_kes_web.py"
}

bioprof_runtime() {
  local isaret="$HOME/Desktop/BioProf.app/Contents/Resources/runtime-path"
  local kok=""
  if [[ -n "${BIOPROF_KOK:-}" ]]; then
    kok="$BIOPROF_KOK"
  elif [[ -f "$isaret" ]]; then
    kok="$(<"$isaret")"
  fi
  if [[ -z "$kok" || ! -f "$kok/pyproject.toml" ]]; then
    kok="$HOME/Library/Application Support/BioProf/runtime"
  fi
  [[ -f "$kok/pyproject.toml" ]] || return 1
  print -r -- "$kok"
}

ensure_bioprof() {
  local kok=""
  kok="$(bioprof_runtime 2>/dev/null || true)"
  if [[ -z "$kok" ]]; then
    echo "[$(timestamp)] BioProf çalışma klasörü bulunamadı, atlandı."
    return 0
  fi
  local uv=""
  local aday
  for aday in "$HOME/.local/bin/uv" /opt/homebrew/bin/uv /usr/local/bin/uv; do
    if [[ -x "$aday" ]]; then
      uv="$aday"
      break
    fi
  done
  if [[ -z "$uv" ]]; then
    echo "[$(timestamp)] uv bulunamadı, BioProf atlandı."
    return 0
  fi
  # BioProf'un tercih ettiği port 8766; doluysa 8765-8775 taranır.
  local bioprof_port=""
  local port
  for port in 8766 {8765..8775}; do
    if service_healthy "http://127.0.0.1:${port}/healthz" '"status":"ok"'; then
      return 0
    fi
    if [[ -z "$bioprof_port" ]] && ! port_in_use "$port"; then
      bioprof_port="$port"
    fi
  done
  if [[ -z "$bioprof_port" ]]; then
    echo "[$(timestamp)] 8765-8775 aralığında BioProf için boş port yok."
    return 0
  fi
  # PYTHONPATH komutun kendisine gömülüyor: BioProf paketi `src` düzeninde.
  service_cwd="$kok"
  start_service_once "bioprof" \
    "http://127.0.0.1:${bioprof_port}/healthz" '"status":"ok"' \
    /usr/bin/env "PYTHONPATH=$kok/src" \
    "$uv" run --project "$kok" --no-sync python -m bioprof.cli serve \
    --port "$bioprof_port"
}

ensure_seslab() {
  local kok="$HOME/Developer/seslab"
  [[ -x "$kok/.venv/bin/uvicorn" ]] || return 0
  service_cwd="$kok"
  start_service_once "seslab" \
    "http://127.0.0.1:${seslab_port}/api/system/status" "" \
    "$kok/.venv/bin/uvicorn" app.main:app --host 127.0.0.1 --port "$seslab_port"
}

ensure_cliproxy() {
  local bin="$HOME/cli-proxy-api/.venv/bin/cliproxy"
  [[ -x "$bin" ]] || return 0
  service_cwd="$HOME/cli-proxy-api"
  start_service_once "cliproxy" \
    "http://127.0.0.1:${cliproxy_port}/healthz" "" \
    "$bin" serve --host 127.0.0.1 --port "$cliproxy_port"
}

ensure_companions() {
  [[ "${BIYO_YARDIMCI_SERVISLER:-1}" == "0" ]] && return 0
  ensure_soru_kesici
  ensure_bioprof
  ensure_seslab
  ensure_cliproxy
}

echo "[$(timestamp)] Başlatıcı çalıştı."

if [[ ! -x "$entry_bin" ]]; then
  echo "[$(timestamp)] Python ortamı bulunamadı: $entry_bin"
  show_error "Programın Python ortamı bulunamadı. Proje klasörü taşınmış ya da .venv silinmiş olabilir."
  exit 1
fi

# Stüdyo zaten açık olsa bile yardımcı servisler güvenceye alınır: kullanıcı
# ikonu ikinci kez tıkladığında eksik kalan servis ayağa kalksın.
ensure_companions

if ! acquire_lock; then
  echo "[$(timestamp)] Başlatma kilidi alınamadı."
  show_error "Başka bir başlatma işlemi tamamlanamadı. Birkaç saniye sonra yeniden deneyin."
  exit 1
fi

# PID dosyası yalnız canlı, doğru komutlu ve health PID'siyle eşleşen bir
# sürece işaret ediyorsa geçerlidir. Aksi hâlde dosya güvenle temizlenir.
saved_pid="$(read_pid "$pid_file" 2>/dev/null || true)"
if [[ -e "$pid_file" ]]; then
  saved_port=""
  if [[ -n "$saved_pid" ]] && pid_is_server "$saved_pid"; then
    saved_port="$(find_port_for_pid "$saved_pid" 2>/dev/null || true)"
  fi
  if [[ -n "$saved_port" ]]; then
    echo "[$(timestamp)] Çalışan sunucu PID dosyasından doğrulandı: port=$saved_port PID=$saved_pid"
    /usr/bin/open "http://127.0.0.1:${saved_port}/merkez"
    exit 0
  fi
  echo "[$(timestamp)] Bayat/geçersiz PID dosyası temizleniyor: ${saved_pid:-okunamadı}"
  clear_pid_file
fi

# PID dosyası kaybolmuş olsa bile kimlikli canlı sunucuyu bulup kaydı onar.
existing="$(find_existing_server 2>/dev/null || true)"
if [[ -n "$existing" ]]; then
  existing_port="${existing%%:*}"
  existing_rest="${existing#*:}"
  existing_pid="${existing_rest%%:*}"
  existing_build="${existing_rest#*:}"
  if ! atomic_write "$pid_file" "$existing_pid"; then
    echo "[$(timestamp)] PID dosyası onarılamadı: $pid_file"
    show_error "Sunucu bulundu ancak süreç kaydı yazılamadı. Günlük klasörünün izinlerini denetleyin."
    exit 1
  fi
  echo "[$(timestamp)] Çalışan sunucu bulundu: port=$existing_port PID=$existing_pid build=$existing_build"
  /usr/bin/open "http://127.0.0.1:${existing_port}/merkez"
  exit 0
fi

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
# BIYO_* değişkenleri buraya hiç ulaşmaz. İnce ayarlı bir model kurulduğunda
# terminalden çalışan komutlar onu kullanırken arayüz sessizce taban modele
# düşüyordu. `ortam.sh` bu boşluğu kapatır ve tek kaynak olur.
ortam_dosyasi="$HOME/.biyo-cozucu/ortam.sh"
if [[ -f "$ortam_dosyasi" ]]; then
  echo "[$(timestamp)] Ortam dosyası yükleniyor: $ortam_dosyasi"
  # shellcheck source=/dev/null
  source "$ortam_dosyasi"
fi

# Motor türü dışarıdan verilebilir; masaüstünde varsayılan ``karma``dır:
# görselsiz soru ince ayarlı MLX modele, resim/PDF sayfası görsel modele gider.
# Modeller TEMBEL yüklenir; sunucu hemen ayağa kalkar, ilk soruda hazırlanır.
motor="${BIYO_MOTOR:-karma}"
if [[ -n "${BIYO_MLX_MODEL:-}" ]]; then
  echo "[$(timestamp)] Model: $BIYO_MLX_MODEL"
fi

echo "[$(timestamp)] Sunucu başlatılıyor: port=$selected_port motor=$motor"
cd "$project_dir" || exit 1
BIYO_BUILD_ID="$build_id" nohup "$entry_bin" sunucu \
  --adres 127.0.0.1 \
  --port "$selected_port" \
  --motor "$motor" \
  >>"$server_log" 2>&1 </dev/null 9>&- &
server_pid=$!
if ! atomic_write "$pid_file" "$server_pid"; then
  echo "[$(timestamp)] PID dosyası yazılamadı: $pid_file"
  show_error "Sunucu süreç kaydı yazılamadı. Günlük klasörünün izinlerini denetleyin."
  exit 1
fi

for _attempt in {1..60}; do
  if health_probe "$selected_port" &&
     [[ "$health_pid" == "$server_pid" && "$health_build" == "$build_id" ]] &&
     pid_owns_port "$server_pid" "$selected_port"; then
    echo "[$(timestamp)] Sunucu hazır: PID=$server_pid build=$build_id; tarayıcı açılıyor."
    # EXIT trap yalnız başarısız başlatılan child'ı temizler. PID dosyası ve
    # doğrulanmış sunucu başarıdan sonra yaşamaya devam etmeli.
    server_pid=""
    /usr/bin/open "http://127.0.0.1:${selected_port}/merkez"
    exit 0
  fi
  if ! /bin/kill -0 "$server_pid" 2>/dev/null; then
    echo "[$(timestamp)] Sunucu hazır olmadan kapandı."
    cleanup_started_server
    show_error "Sunucu başlatılırken kapandı. Ayrıntılar ~/Library/Logs/BiyoCozucu/server.log dosyasındadır."
    exit 1
  fi
  /bin/sleep 0.5
done

echo "[$(timestamp)] Sunucu kimliği doğrulanamadı veya zaman aşımına uğradı: PID=$server_pid build=$build_id"
cleanup_started_server
show_error "Sunucu 30 saniye içinde hazır olmadı. Ayrıntılar ~/Library/Logs/BiyoCozucu/server.log dosyasındadır."
exit 1
