#!/bin/zsh
# Cihaz kabul turu (P3.10-kabul): Debug kurar, sınamaları telefonda sırayla koşturur, raporları çeker,
# önceki turla karşılaştırır (araclar/kabul_karsilastir.py).
#   araclar/cihaz-kabul.sh                          Debug kurar (./telefona-kur.sh --sinama) + varsayılan sınamalar
#   araclar/cihaz-kabul.sh --kurma                  kurmadan, telefondaki Debug sürümle koşturur (son kurulum Release ise 64)
#   araclar/cihaz-kabul.sh --yalniz hiz-kabul,ofis-sinama    yalnız bu sınamalar (--liste hepsini gösterir)
#   araclar/cihaz-kabul.sh --bekle[=sn] --udid X    kilit doluysa bekler (yalnız bayrak verilirse; sn yoksa 600), yoksa 75 · başka cihaz
# Çıkış: 0 geçti · 1 %20'den kötü gerileme ya da başarısız sınama · 2 altyapı (telefon kilitli, açılamadı,
#        dosya çekilemedi, kurulum hatası) · 64 kullanım · 75 kurulum kilidi dolu
# Turlar: ~/Developer/.build/asistan-kabul/<YYYYMMDD-HHMMSS>/ (son 10 tur kalır); karşılaştırma karsilastirma.txt'de.
# Sınama bayrakları yalnız Debug derlemede vardır; gerçek model çağrıları hesap kotasını kullanır.
emulate -L zsh
setopt no_err_exit pipe_fail no_unset
cd "${0:A:h:h}" || exit 2
KOK=$PWD
source araclar/kurulum-ortak.sh

UDID=00008120-001C592421D8A01E
BUNDLE=com.mehmetderin.asistan
BEKLE=""
KUR=1
YALNIZ=""
KABUL_KOK=${ASISTAN_KABUL_DIZINI:-$HOME/Developer/.build/asistan-kabul}
ARALIK=${ASISTAN_KABUL_ARALIK:-5}
ENCOK=${ASISTAN_KABUL_ENCOK:-}   # sınama başına bekleme üst sınırı (sn; kabuk testi kısaltır)
TUT=10
DEVICECTL=(${=ASISTAN_DEVICECTL:-xcrun devicectl})

# Bayrak (--asistan-<ad>) · rapor dosyası (Documents/) · en uzun bekleme (sn) · varsayılan turda mı.
# Yalnız üst düzeyi nesne olan raporlar (kosu/kosuBitti alanı taşıyabilenler) burada yer alır.
SINAMA_TABLOSU=(
  "hiz-kabul                asistan-hiz-kabul.json                600 1"
  "ilk-metin-sinama         asistan-ilk-metin-sinama.json         120 1"
  "ofis-sinama              asistan-ofis-sinama.json              120 1"
  "donusturme-sinama        asistan-donusturme-sinama.json        120 1"
  "arsiv-sinama             asistan-arsiv-sinama.json             120 1"
  "kazima-sinama            asistan-kazima-sinama.json            120 1"
  "sinama                   asistan-sinama.json                   300 1"
  "gelen-kutusu-sinama      asistan-gelen-kutusu-sinama.json      120 0"
  "grok-yetenekleri-sinama  asistan-grok-yetenekleri-sinama.json  180 0"
  "indirme-sinama           asistan-indirme-sinama.json           180 0"
  "son-istek-sinama         asistan-son-istek-sinama.json         180 0"
  "hiz-sinama               asistan-hiz-sinama.json               600 0"
  "modeller-sinama          asistan-modeller-sinama.json          600 0"
  "caba-sinama              asistan-caba-sinama.json              420 0"
  "atolye-sinama            asistan-atolye-sinama.json            300 0"
  "live-baglanti-sinama     asistan-live-baglanti-sinama.json     120 0"
  "live-sinama              asistan-live-sinama.json              300 0"
  "ses-sinama               asistan-ses-sinama.json               120 0"
  "ses-akis-sinama          asistan-ses-akis-sinama.json          120 0"
  "sunucu-sinama            asistan-sunucu-sinama.json            300 0"
  "web-yeni                 asistan-web-yeni.json                 180 0"
)
typeset -A DOSYA SURE
typeset -a VARSAYILAN BILINEN
for satir in "${SINAMA_TABLOSU[@]}"; do
  alanlar=(${=satir})
  DOSYA[$alanlar[1]]=$alanlar[2]; SURE[$alanlar[1]]=$alanlar[3]; BILINEN+=($alanlar[1])
  [[ $alanlar[4] == 1 ]] && VARSAYILAN+=($alanlar[1])
done

while (( $# )); do
  case $1 in
    --kurma) KUR=0 ;;
    --yalniz) shift; YALNIZ=${1:-} ;;
    --yalniz=*) YALNIZ=${1#--yalniz=} ;;
    --bekle) BEKLE=600 ;;
    --bekle=*) BEKLE=${1#--bekle=} ;;
    --udid) shift; UDID=${1:-} ;;
    --udid=*) UDID=${1#--udid=} ;;
    --liste)
      for s in "${BILINEN[@]}"; do print -r -- "$s · ${DOSYA[$s]} · ${SURE[$s]} sn$([[ ${VARSAYILAN[(Ie)$s]} -gt 0 ]] && print ' · varsayılan')"; done
      exit 0 ;;
    -h|--yardim) sed -n '2,11p' "$0"; exit 0 ;;
    *) print -u2 -r -- "Bilinmeyen bağımsız değişken: $1"; exit 64 ;;
  esac
  shift
done
[[ -n $UDID ]] || { print -u2 "UDID boş"; exit 64; }
[[ -z $BEKLE || $BEKLE == <-> ]] || { print -u2 -r -- "--bekle saniye ister: $BEKLE"; exit 64; }
[[ $ARALIK == <-> && $ARALIK -gt 0 ]] || { print -u2 -r -- "ASISTAN_KABUL_ARALIK saniye ister: $ARALIK"; exit 64; }

typeset -a SINAMALAR
if [[ -n $YALNIZ ]]; then
  for s in ${(s:,:)YALNIZ}; do
    [[ -n ${DOSYA[$s]:-} ]] || { print -u2 -r -- "Bilinmeyen sınama: $s (--liste)"; exit 64; }
    SINAMALAR+=($s)
  done
else
  SINAMALAR=("${VARSAYILAN[@]}")
fi
(( ${#SINAMALAR} )) || { print -u2 "Koşturulacak sınama yok"; exit 64; }
command -v jq >/dev/null || { print -u2 "jq gerekli"; exit 2; }

# Kilit bütün tur boyunca tutulur; çocuk telefona-kur.sh ASISTAN_KILIT_SAHIBI ile yeniden girer.
kilit_al "$UDID" $BEKLE; kod=$?
(( kod == 0 )) || exit $kod
trap kilit_birak EXIT
trap 'kilit_birak; exit 130' INT
trap 'kilit_birak; exit 143' TERM

BASLA=$SECONDS
sure() { print $((SECONDS - BASLA)); }
YAPILANDIRMA=Debug

# --kurma: sınama bayrakları yalnız Debug derlemede vardır; telefondaki son kurulum Release ise tur 25 dk sessizce zaman aşımına uğrar.
# Yalnız kurulumu tamamlanmış satırlara bakılır (kabul_* satırları bu betiğin YAPILANDIRMA'sını yazar). Defter yoksa/satır yoksa sürdürülür.
if (( ! KUR )); then
  son_yapilandirma=$(awk -F'\t' -v u="$UDID" '$2 == u && ($9 == "basarili" || $9 == "acilis_hatasi") { c = $7 } END { print c }' \
    "${KURULUM_DEFTERI:-$HOME/Developer/.build/asistan-kurulumlar.log}" 2>/dev/null)
  if [[ -n $son_yapilandirma && $son_yapilandirma != Debug ]]; then
    print -u2 -r -- "Telefondaki son kurulum $son_yapilandirma; sınama bayrakları yalnız Debug'da çalışır."
    print -u2 "İpucu: --kurma olmadan çalıştır (Debug kurar) ya da önce ./telefona-kur.sh --sinama."
    exit 64
  fi
fi
surum_hesapla
SURUM=kabul   # derleme numarası raporların `surum` alanından okunur (aşağıda)

if (( KUR )); then
  ./telefona-kur.sh --sinama ${BEKLE:+--bekle=$BEKLE} --udid "$UDID"; kod=$?
  if (( kod != 0 )); then
    defter_yaz kabul_kurulum_hatasi "$(sure)"
    (( kod == 75 )) && exit 75
    print -u2 "Kurulum başarısız ($kod); kabul turu koşmadı."; exit 2
  fi
fi

mkdir -p "$KABUL_KOK" || exit 2
TUR=$KABUL_KOK/$(date +%Y%m%d-%H%M%S)
while [[ -e $TUR ]]; do sleep 1; TUR=$KABUL_KOK/$(date +%Y%m%d-%H%M%S); done
GELEN=$TUR/.gelen
mkdir -p "$TUR" "$GELEN" || exit 2
GUNLUK=$TUR/kabul.log
print "Kabul turu → $TUR · ${(j:, :)SINAMALAR}"

kilitli_mi() { print -r -- "$1" | grep -qiE 'locked|passcode|kilitli' }

ac() {  # ac [bağımsız değişkenler…]: uygulamayı yeniden başlatır
  local cikti
  if (( $# )); then
    cikti=$("${DEVICECTL[@]}" device process launch --device "$UDID" --terminate-existing "$BUNDLE" -- "$@" 2>&1)
  else
    cikti=$("${DEVICECTL[@]}" device process launch --device "$UDID" --terminate-existing "$BUNDLE" 2>&1)
  fi
  local k=$?
  print -r -- "[ac $*] $cikti" >> "$GUNLUK"
  ACIS_CIKTISI=$cikti
  return $k
}

cek() {  # cek RAPOR HEDEF: Documents/RAPOR → HEDEF
  rm -f -- "$2"
  local cikti
  cikti=$("${DEVICECTL[@]}" device copy from --device "$UDID" --domain-type appDataContainer \
    --domain-identifier "$BUNDLE" --source "Documents/$1" --destination "$2" 2>&1)
  local k=$?
  CEKIS_CIKTISI=$cikti
  (( k == 0 )) || print -r -- "[cek $1] $cikti" >> "$GUNLUK"
  (( k == 0 )) && [[ -s $2 ]]
}

altyapi_cik() {  # altyapi_cik MESAJ
  print -u2 -r -- "$1"
  ac >/dev/null 2>&1 || true
  rm -rf -- "$GELEN"
  defter_yaz kabul_altyapi "$(sure)"
  exit 2
}

hic_cekilen=0
for ad in "${SINAMALAR[@]}"; do
  dosya=${DOSYA[$ad]} enuzun=${SURE[$ad]}
  [[ $ENCOK == <-> ]] && (( ENCOK < enuzun )) && enuzun=$ENCOK
  KOSU=$(uuidgen)
  print -n -r -- "• $ad … "
  if ! ac "--asistan-$ad" "--sinama-kosu=$KOSU"; then
    print "açılamadı"
    if kilitli_mi "$ACIS_CIKTISI"; then altyapi_cik "Telefon kilitli: telefonun kilidini aç ve yeniden dene."; fi
    altyapi_cik "Uygulama açılamadı ($ad); ayrıntı: $GUNLUK"
  fi
  bas=$SECONDS geldi=0 bitti=0
  while (( SECONDS - bas < enuzun )); do
    sleep "$ARALIK"
    if cek "$dosya" "$GELEN/$dosya"; then
      geldi=1; hic_cekilen=1
      if jq -e --arg k "$KOSU" '.kosu == $k and .kosuBitti == true' "$GELEN/$dosya" >/dev/null 2>&1; then
        mv -f -- "$GELEN/$dosya" "$TUR/$dosya"; bitti=1; break
      fi
    elif kilitli_mi "$CEKIS_CIKTISI"; then
      altyapi_cik "Telefon kilitli: telefonun kilidini aç ve yeniden dene."
    fi
  done
  if (( bitti )); then
    print "bitti ($((SECONDS - bas)) sn)"
  else
    print "zaman aşımı (${enuzun} sn)"
    # Son okunan (eski koşunun ya da bitmemiş) dosya tanı için saklanır; karşılaştırıcı yalnız asistan-*.json okur.
    [[ -f $GELEN/$dosya ]] && mv -f -- "$GELEN/$dosya" "$TUR/son-okunan-$dosya"
    jq -n --arg k "$KOSU" --argjson s "$enuzun" --argjson g "$geldi" \
      '{kabulZamanAsimi: true, kabulKosu: $k, kabulSureSn: $s, kabulDosyaGeldi: ($g == 1)}' > "$TUR/$dosya"
  fi
done

# Olağan açılışa dön (sınama bayraksız).
ac >/dev/null 2>&1 || print -u2 "Uyarı: uygulama olağan açılışa döndürülemedi."
rm -rf -- "$GELEN"

if (( ! hic_cekilen )); then
  altyapi_cik "Hiçbir rapor telefondan çekilemedi (uygulama kapsayıcısına erişilemiyor?); ayrıntı: $GUNLUK"
fi

# Derleme numarası: "0.21.0 (202610201530) · git …" → 202610201530.
for f in "$TUR"/asistan-*.json(N); do
  s=$(jq -r '.surum // empty' "$f" 2>/dev/null)
  if [[ $s == *"("<->")"* ]]; then SURUM=${${s#*\(}%%\)*}; break; fi
done

# Önceki tur: bu turdan önceki, rapor içeren en yeni tur dizini.
ONCEKI=""
for d in "$KABUL_KOK"/<->-<->(N/On); do
  [[ $d == "$TUR" || $d > $TUR ]] && continue
  if [[ -n $(print -r -- "$d"/asistan-*.json(N[1])) ]]; then ONCEKI=$d; break; fi
done

/usr/bin/python3 -I araclar/kabul_karsilastir.py "${ONCEKI:--}" "$TUR" 2>&1 | tee "$TUR/karsilastirma.txt"
kod=${pipestatus[1]}

case $kod in
  0) sonuc=gecti ;;
  1) sonuc=gerileme ;;
  *) sonuc=altyapi ;;
esac
defter_yaz "kabul_$sonuc" "$(sure)"

# Disk: son $TUT tur kalır.
eskiler=("$KABUL_KOK"/<->-<->(N/On))
for d in "${(@)eskiler[$((TUT + 1)),-1]}"; do rm -rf -- "$d"; done

print "Kabul: $sonuc · $(sure) sn · $TUR/karsilastirma.txt"
exit $kod
