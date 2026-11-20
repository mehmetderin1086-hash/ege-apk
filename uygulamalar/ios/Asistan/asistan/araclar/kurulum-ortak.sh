#!/bin/zsh
# Telefona kurulum için ortak işlevler; `source araclar/kurulum-ortak.sh` ile yüklenir.
#   kilit_al UDID [bekle_sn]  telefon başına kilit (aynı anda iki kurulum / cihaz testi olmasın)
#   kilit_birak               kilidi yalnız sahibi ($$) kaldırır
#   surum_hesapla             SURUM (YYYYMMDDHHMM), GIT, KIRLI, PAZARLAMA
#   defter_yaz SONUC SURE     kurulum defterine sekmeyle ayrılmış tek satır
#   dsym_sakla KAYNAK AD [TUT]  dSYM'leri saklar, en yeni TUT (5) klasör kalır
#
# ÖNEMLİ: kilit_al kendisi trap KURMAZ. zsh'ta işlev içinde kurulan `trap … EXIT` işlev dönünce çalışır
# (kilit derleme başlamadan kalkardı). Çağıran betik, kilit_al başarılı olunca ÜST DÜZEYDE şunu yazar:
#   trap kilit_birak EXIT; trap 'kilit_birak; exit 130' INT; trap 'kilit_birak; exit 143' TERM
# Yeniden girme: kilidi alan süreç ASISTAN_KILIT_SAHIBI'ni dışa aktarır; aynı telefon için çağrılan çocuk
# betik (ör. cihaz-kabul.sh → telefona-kur.sh) kilidi ata süreçte görür, 0 döner ve kilide dokunmaz.

ASISTAN_KOK_VARSAYILAN=${${(%):-%x}:A:h:h}

# Bir sürecin başlangıç anı; PID yeniden kullanılınca değişir (bayat kilit ayrımı).
_kilit_surec_baslangici() {
  ps -o lstart= -p "$1" 2>/dev/null | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

kilit_yolu() {
  print -r -- "${ASISTAN_KILIT_DIZINI:-$HOME/Developer/.build}/asistan-telefon-$1.kilit"
}

# Sahip dosyasını çağıranın değişkenlerine okur (zsh dinamik kapsam): sahip_pid sahip_lstart sahip_dizin sahip_git.
_kilit_sahip_oku() {
  sahip_pid="" sahip_lstart="" sahip_dizin="" sahip_git=""
  local dosya="$1/sahip" satir
  [[ -f $dosya ]] || return 1
  while IFS= read -r satir || [[ -n $satir ]]; do
    case $satir in
      pid=*) sahip_pid=${satir#pid=} ;;
      lstart=*) sahip_lstart=${satir#lstart=} ;;
      dizin=*) sahip_dizin=${satir#dizin=} ;;
      git=*) sahip_git=${satir#git=} ;;
    esac
  done < "$dosya"
  return 0
}

# pid yaşıyor ve başlangıç anı kayıtlıyla aynıysa kilit canlıdır.
_kilit_canli() {
  local pid=$1 lstart=$2
  [[ $pid == <-> ]] || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  [[ "$(_kilit_surec_baslangici "$pid")" == "$lstart" ]]
}

kilit_al() {
  local udid=${1:-} bekle=${2:-}
  if [[ -z $udid ]]; then print -u2 "kilit_al: UDID gerekli"; return 64; fi
  if [[ -n $bekle && $bekle != <-> ]]; then print -u2 "kilit_al: bekleme süresi saniye olmalı: $bekle"; return 64; fi
  local kilit; kilit=$(kilit_yolu "$udid")
  local sahip_pid sahip_lstart sahip_dizin sahip_git
  local benim_lstart; benim_lstart=$(_kilit_surec_baslangici $$)
  mkdir -p "${kilit:h}" 2>/dev/null || true

  # Yeniden girme: kilit ata süreçteyse (aynı UDID, aynı pid + başlangıç anı ve hâlâ canlı) tutulmuş sayılır.
  if [[ -n ${ASISTAN_KILIT_SAHIBI:-} && ${ASISTAN_KILIT_SAHIBI%%:*} == "$udid" ]] && _kilit_sahip_oku "$kilit"; then
    if [[ "$udid:$sahip_pid:$sahip_lstart" == "$ASISTAN_KILIT_SAHIBI" ]] && _kilit_canli "$sahip_pid" "$sahip_lstart"; then
      print -u2 "Kilit ata süreçte (pid $sahip_pid); yeniden giriliyor."
      KILIT_YOLU=""   # bu süreç sahip değil; kilit_birak dokunmaz
      return 0
    fi
  fi

  local bas=$SECONDS bayat=0 bos=0 yazildi=0
  while true; do
    if mkdir "$kilit" 2>/dev/null; then
      local gecici="$kilit/.sahip.$$"
      {
        print -r -- "pid=$$"
        print -r -- "lstart=$benim_lstart"
        print -r -- "dizin=$PWD"
        print -r -- "git=$(git -C "${KOK:-$ASISTAN_KOK_VARSAYILAN}" rev-parse --short HEAD 2>/dev/null || print yok)"
      } > "$gecici" && mv -f "$gecici" "$kilit/sahip" && yazildi=1
      if (( ! yazildi )); then
        rm -f "$gecici"; rmdir "$kilit" 2>/dev/null
        print -u2 "kilit_al: sahip dosyası yazılamadı: $kilit"; return 1
      fi
      export ASISTAN_KILIT_SAHIBI="$udid:$$:$benim_lstart"
      KILIT_YOLU=$kilit
      return 0
    fi

    if ! _kilit_sahip_oku "$kilit"; then
      # Başka süreç dizini yeni açmış, sahip dosyasını henüz yazmamış olabilir: kısa süre bekle.
      if (( bos < 3 )); then bos=$((bos + 1)); sleep 1; continue; fi
    elif _kilit_canli "$sahip_pid" "$sahip_lstart"; then
      bos=0
      print -u2 "Telefon kilitli: pid $sahip_pid · dizin $sahip_dizin · git $sahip_git"
      if [[ -n $bekle ]] && (( SECONDS - bas < bekle )); then
        print -u2 "  kilit bekleniyor… ($((SECONDS - bas))/$bekle sn)"
        sleep 5; continue
      fi
      return 75
    fi

    # Sahip ölmüş, PID başka sürece geçmiş ya da sahip dosyası yok: bayat kilit.
    if (( bayat >= 3 )); then print -u2 "kilit_al: bayat kilit kaldırılamadı: $kilit"; return 1; fi
    bayat=$((bayat + 1)); bos=0
    local eski_pid=$sahip_pid eski_lstart=$sahip_lstart
    # Kaldırmadan hemen önce yeniden oku: bu arada başka biri devralıp yeni sahip yazdıysa onunkini silme.
    _kilit_sahip_oku "$kilit" || true
    if [[ $sahip_pid != "$eski_pid" || $sahip_lstart != "$eski_lstart" ]]; then continue; fi
    print -u2 "Bayat kilit devralındı (eski pid ${eski_pid:-?})."
    rm -f "$kilit/sahip" "$kilit"/.sahip.*(N)
    rmdir "$kilit" 2>/dev/null || true
  done
}

kilit_birak() {
  local kilit=${KILIT_YOLU:-}
  [[ -n $kilit && -d $kilit ]] || return 0
  local sahip_pid sahip_lstart sahip_dizin sahip_git
  _kilit_sahip_oku "$kilit" || return 0
  [[ $sahip_pid == "$$" ]] || return 0
  rm -f "$kilit/sahip"
  rmdir "$kilit" 2>/dev/null || true
  KILIT_YOLU=""
  [[ ${ASISTAN_KILIT_SAHIBI:-} == *":$$:"* ]] && unset ASISTAN_KILIT_SAHIBI
  return 0
}

surum_hesapla() {
  local kok=${KOK:-$ASISTAN_KOK_VARSAYILAN}
  SURUM=$(date +%Y%m%d%H%M)
  GIT=$(git -C "$kok" rev-parse --short HEAD 2>/dev/null || print yok)
  KIRLI=$(git -C "$kok" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  [[ $KIRLI == <-> ]] || KIRLI=0
  PAZARLAMA=$(sed -nE 's/^[[:space:]]*CFBundleShortVersionString:[[:space:]]*"?([^"]+)"?.*/\1/p' "$kok/project.yml" 2>/dev/null | head -1)
  PAZARLAMA=${PAZARLAMA:-bilinmiyor}
}

# Alan sırası: zaman, UDID, pazarlama, derleme, git, kirli, yapılandırma, dizin, sonuç, süre_sn (10 alan).
defter_yaz() {
  local sonuc=${1:-bilinmiyor} sure=${2:-0}
  local defter=${KURULUM_DEFTERI:-$HOME/Developer/.build/asistan-kurulumlar.log}
  mkdir -p "${defter:h}" 2>/dev/null || true
  local -a alanlar=(
    "$(date +%Y-%m-%dT%H:%M:%S%z)" "${UDID:-?}" "${PAZARLAMA:-?}" "${SURUM:-?}" "${GIT:-?}" "${KIRLI:-?}"
    "${YAPILANDIRMA:-?}" "$PWD" "$sonuc" "$sure"
  )
  local a sekme=$'\t' satir="" ilk=1
  for a in "${alanlar[@]}"; do
    a=${a//$sekme/ }; a=${a//$'\n'/ }
    if (( ilk )); then satir=$a; ilk=0; else satir+="$sekme$a"; fi
  done
  print -r -- "$satir" >> "$defter"
}

# dsym_sakla KAYNAK_DIZIN AD [TUT]: KAYNAK_DIZIN/*.dSYM → ASISTAN_DSYM_DIZINI/AD/; en yeni TUT klasör kalır.
dsym_sakla() {
  local kaynak=$1 ad=$2 tut=${3:-5}
  local kok=${ASISTAN_DSYM_DIZINI:-$HOME/Developer/.build/asistan-dsym}
  local -a dsymler=("$kaynak"/*.dSYM(N))
  if (( ${#dsymler} == 0 )); then print -u2 "Uyarı: saklanacak dSYM yok ($kaynak)."; return 0; fi
  mkdir -p "$kok/$ad" || return 0
  local d
  for d in "${dsymler[@]}"; do ditto "$d" "$kok/$ad/${d:t}" || print -u2 "Uyarı: dSYM kopyalanamadı: ${d:t}"; done
  # En yeniler başta (değiştirilme zamanı); TUT'tan sonrakiler silinir.
  local -a klasorler=("$kok"/*(N/om))
  local eski
  for eski in "${(@)klasorler[$((tut + 1)),-1]}"; do rm -rf -- "$eski"; done
  return 0
}
