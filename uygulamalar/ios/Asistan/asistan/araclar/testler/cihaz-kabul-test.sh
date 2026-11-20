#!/bin/zsh
# araclar/cihaz-kabul.sh sınaması: sahte devicectl ile (telefona, ağa, Xcode'a dokunmaz).
# Kilit, defter ve tur dizinleri geçici dizindedir.
#   zsh araclar/testler/cihaz-kabul-test.sh
emulate -L zsh
setopt no_err_exit
KOK=${0:A:h:h:h}
BETIK=$KOK/araclar/cihaz-kabul.sh
GECICI=$(mktemp -d -t cihaz-kabul-test.XXXXXX)
export ASISTAN_KILIT_DIZINI=$GECICI/kilit KURULUM_DEFTERI=$GECICI/defter.log
export ASISTAN_KABUL_DIZINI=$GECICI/turlar ASISTAN_KABUL_ARALIK=1
export SAHTE_BELGELER=$GECICI/belgeler SAHTE_KIP=iyi SAHTE_GUNLUK=$GECICI/sahte.log
unset ASISTAN_KILIT_SAHIBI
mkdir -p "$SAHTE_BELGELER"
basari=0 hata=0
sina() { if eval "$2"; then print "✓ $1"; basari=$((basari + 1)); else print "✗ $1"; hata=$((hata + 1)); fi }
trap 'rm -rf -- "$GECICI"' EXIT

# Sahte devicectl: launch yazılı raporu SAHTE_KIP'e göre üretir; copy from Documents/<ad>'ı SAHTE_BELGELER'den kopyalar.
SAHTE=$GECICI/sahte-devicectl
cat > "$SAHTE" <<'SON'
#!/bin/zsh
print -r -- "$*" >> "$SAHTE_GUNLUK"
if [[ "$1 $2 $3" == "device process launch" ]]; then
  [[ $SAHTE_KIP == kilitli ]] && { print -u2 "ERROR: The device is locked."; exit 1; }
  kosu="" ad=""
  for a in "$@"; do
    case $a in
      --sinama-kosu=*) kosu=${a#--sinama-kosu=} ;;
      --asistan-*) ad=${a#--asistan-} ;;
    esac
  done
  [[ -z $ad ]] && exit 0
  dosya=$SAHTE_BELGELER/asistan-$ad.json
  case $SAHTE_KIP in
    iyi) print -r -- "{\"tamamlandi\":true,\"hata\":\"\",\"toplamSn\":1.0,\"kosu\":\"$kosu\",\"kosuBitti\":true,\"surum\":\"0.21.0 (202610201530) · git abc · Debug\"}" > "$dosya" ;;
    yavas) print -r -- "{\"tamamlandi\":true,\"hata\":\"\",\"toplamSn\":5.0,\"kosu\":\"$kosu\",\"kosuBitti\":true}" > "$dosya" ;;
    eski) print -r -- "{\"tamamlandi\":true,\"kosu\":\"BASKA\",\"kosuBitti\":true}" > "$dosya" ;;
    bitmemis) print -r -- "{\"tamamlandi\":false,\"kosu\":\"$kosu\",\"kosuBitti\":false}" > "$dosya" ;;
  esac
  exit 0
fi
if [[ "$1 $2 $3" == "device copy from" ]]; then
  [[ $SAHTE_KIP == kopya-kilitli ]] && { print -u2 "Device is passcode locked"; exit 1; }
  kaynak="" hedef=""
  while (( $# )); do
    case $1 in --source) kaynak=$2; shift ;; --destination) hedef=$2; shift ;; esac
    shift
  done
  [[ -f $SAHTE_BELGELER/${kaynak#Documents/} ]] || { print -u2 "No such file"; exit 1; }
  cp "$SAHTE_BELGELER/${kaynak#Documents/}" "$hedef"
  exit 0
fi
exit 0
SON
chmod +x "$SAHTE"
export ASISTAN_DEVICECTL=$SAHTE

kos() { zsh "$BETIK" --kurma --udid TEST-UDID "$@" > "$GECICI/cikti.txt" 2>&1; }
tur_sayisi() { local -a t=("$ASISTAN_KABUL_DIZINI"/<->-<->(N/)); print ${#t} }

# 1) Temiz ilk tur: önceki yok → 0; rapor kosu kimliğiyle çekilir; olağan açılışa dönülür.
kos --yalniz ofis-sinama,arsiv-sinama; kod=$?
sina "temiz ilk tur 0 döner" '(( kod == 0 ))'
sina "iki rapor çekildi" '(( $(print -l $ASISTAN_KABUL_DIZINI/*/asistan-*.json(N) | wc -l) == 2 ))'
sina "karşılaştırma dosyası yazıldı" '[[ -n $(print $ASISTAN_KABUL_DIZINI/*/karsilastirma.txt(N)) ]]'
sina "uygulama argümanları -- ile ayrıldı" 'grep -q -- "com.mehmetderin.asistan -- --asistan-ofis-sinama --sinama-kosu=" "$SAHTE_GUNLUK"'
sina "son açılış bayraksız" '[[ $(grep "process launch" "$SAHTE_GUNLUK" | tail -1) == *"--terminate-existing com.mehmetderin.asistan" ]]'
sina "defterde kabul_gecti satırı" 'grep -q "kabul_gecti" "$KURULUM_DEFTERI"'
sina "defterde derleme numarası rapordan" 'grep "kabul_gecti" "$KURULUM_DEFTERI" | grep -q 202610201530'
sina "kilit tur sonunda kalktı" '[[ -z $(print $ASISTAN_KILIT_DIZINI/*.kilit(N)) ]]'

# 2) Aynı süre: geçer. 3) Yavaşlama (%400): 1.
sleep 1
kos --yalniz ofis-sinama; kod=$?
sina "aynı süreli ikinci tur 0 döner" '(( kod == 0 ))'
sleep 1
SAHTE_KIP=yavas kos --yalniz ofis-sinama; kod=$?
sina "%20'den kötü gerileme 1 döner" '(( kod == 1 ))'
sina "çıktıda GERİLEME" 'grep -q "GERİLEME" "$GECICI/cikti.txt"'

# 4) Eski koşunun dosyası sayılmaz → zaman aşımı işareti → 1.
sleep 1
rm -f "$SAHTE_BELGELER"/*.json(N)
SAHTE_KIP=eski ASISTAN_KABUL_ENCOK=3 kos --yalniz gelen-kutusu-sinama; kod=$?
sina "kosu uyuşmazlığı zaman aşımı sayılır (1)" '(( kod == 1 ))' 2>/dev/null
SON_TUR=$(print -l $ASISTAN_KABUL_DIZINI/<->-<->(N/On) | head -1)
sina "zaman aşımı işareti yazıldı" 'jq -e ".kabulZamanAsimi == true" "$SON_TUR/asistan-gelen-kutusu-sinama.json" >/dev/null'
sina "son okunan dosya tanı için saklandı" '[[ -f $SON_TUR/son-okunan-asistan-gelen-kutusu-sinama.json ]]'

# 5) Telefon kilitli → 2.
sleep 1
SAHTE_KIP=kilitli kos --yalniz ofis-sinama; kod=$?
sina "kilitli telefon 2 döner" '(( kod == 2 ))'
sina "kilit açma uyarısı" 'grep -q "kilidini aç" "$GECICI/cikti.txt"'
SAHTE_KIP=kopya-kilitli kos --yalniz ofis-sinama; kod=$?
sina "kopyalamada kilitli 2 döner" '(( kod == 2 ))'

# 6) Kullanım hataları ve kurulum kilidi.
kos --yalniz yok-boyle; kod=$?
sina "bilinmeyen sınama 64 döner" '(( kod == 64 ))'
zsh "$BETIK" --liste > "$GECICI/liste.txt" 2>&1
sina "--liste varsayılanları gösterir" 'grep -q "hiz-kabul.*varsayılan" "$GECICI/liste.txt"'
zsh -c "source '$KOK/araclar/kurulum-ortak.sh'; kilit_al TEST-UDID || exit 9; trap kilit_birak EXIT; sleep 20 & wait \$!" 2>/dev/null &
tutucu=$!
for i in {1..50}; do [[ -f $ASISTAN_KILIT_DIZINI/asistan-telefon-TEST-UDID.kilit/sahip ]] && break; sleep 0.1; done
zsh "$BETIK" --kurma --udid TEST-UDID --bekle=0 > /dev/null 2>&1; kod=$?
kill $tutucu 2>/dev/null; wait $tutucu 2>/dev/null
sina "kurulum kilidi doluysa 75 döner" '(( kod == 75 ))'

# 6b) --kurma: telefondaki son kurulum Release ise sınama bayrakları çalışmaz → 64 (kabul_* satırları sayılmaz).
tab=$'\t'
defter_satiri() { print -r -- "2026-10-20T10:00:00+0300${tab}TEST-UDID${tab}0.21.0${tab}202610201000${tab}abc1234${tab}0${tab}$1${tab}/x${tab}basarili${tab}30" >> "$KURULUM_DEFTERI"; }
defter_satiri Release
SAHTE_KIP=iyi kos --yalniz ofis-sinama; kod=$?
sina "--kurma Release kuruluyken 64 döner" '(( kod == 64 ))'
sina "Release uyarısı ve ipucu yazılır" 'grep -q "Release" "$GECICI/cikti.txt" && grep -q "İpucu" "$GECICI/cikti.txt"'
defter_satiri Debug
SAHTE_KIP=iyi kos --yalniz ofis-sinama; kod=$?
sina "--kurma Debug kuruluyken sürer" '(( kod == 0 ))'

# 7) Saklama: son 10 tur kalır.
mkdir -p "$ASISTAN_KABUL_DIZINI"/2026010{1..9}-000000 "$ASISTAN_KABUL_DIZINI"/2026011{0..5}-000000
SAHTE_KIP=iyi kos --yalniz ofis-sinama
sina "en çok 10 tur dizini kalır" '(( $(tur_sayisi) == 10 ))'

print "\n$basari geçti, $hata başarısız"
(( hata == 0 ))
