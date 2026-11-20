#!/bin/zsh
# araclar/kurulum-ortak.sh sınaması: kilit (canlı/bayat/PID yeniden kullanımı/yeniden girme/tuzak kapsamı),
# sürüm hesabı, kurulum defteri, dSYM saklama. Telefona, ağa ya da Xcode'a dokunmaz.
#   zsh araclar/testler/kurulum-ortak-test.sh
emulate -L zsh
setopt no_err_exit
BETIK=${0:A:h:h}/kurulum-ortak.sh
GECICI=$(mktemp -d -t kurulum-ortak-test.XXXXXX)
export ASISTAN_KILIT_DIZINI=$GECICI/kilit KURULUM_DEFTERI=$GECICI/defter.log ASISTAN_DSYM_DIZINI=$GECICI/dsym
unset ASISTAN_KILIT_SAHIBI
source "$BETIK"
U=TEST-UDID
KILIT=$(kilit_yolu $U)
basari=0 hata=0
sina() { if eval "$2"; then print "✓ $1"; basari=$((basari + 1)); else print "✗ $1"; hata=$((hata + 1)); fi }
temizle() { [[ -n ${tutucu:-} ]] && kill $tutucu 2>/dev/null; rm -rf -- "$GECICI"; }
trap temizle EXIT
bekle_dosya() { local i; for i in {1..50}; do [[ -f $1 ]] && return 0; sleep 0.1; done; return 1 }
sahip_pid_oku() { sed -n 's/^pid=//p' "$KILIT/sahip" 2>/dev/null }

# 1) İlk kilit alınır ve kilit_al dönünce kilit hâlâ durur (işlev içi EXIT tuzağı gerilemesi).
kilit_al $U; kod=$?
sina "ilk kilit_al başarılı" '(( kod == 0 ))'
sina "kilit_al dönüşünden sonra kilit dizini duruyor" '[[ -d $KILIT && $(sahip_pid_oku) == $$ ]]'

# 2) Yeniden girme: ASISTAN_KILIT_SAHIBI ile çağrılan çocuk süreç 0 döner, kilidi silmez.
zsh -c "source '$BETIK'; kilit_al $U; k=\$?; kilit_birak; exit \$k" 2>/dev/null; kod=$?
sina "ata süreçte kilit varken çocuk kilit_al 0 döner" '(( kod == 0 ))'
sina "çocuk kilit_birak ata sürecin kilidini silmez" '[[ -d $KILIT && $(sahip_pid_oku) == $$ ]]'
kilit_birak
sina "kilit_birak sahibin kilidini kaldırır" '[[ ! -e $KILIT ]]'
sina "kilit_birak ASISTAN_KILIT_SAHIBI'ni temizler" '[[ -z ${ASISTAN_KILIT_SAHIBI:-} ]]'

# 3) Ayrı süreç kilidi tutarken ikinci kilit_al 75 döner; beklemeli çağrı da süre dolunca 75 döner.
zsh -c "source '$BETIK'; kilit_al $U || exit 9; trap kilit_birak EXIT; trap 'kilit_birak; exit 143' TERM; sleep 30 & wait \$!" 2>/dev/null &
tutucu=$!
bekle_dosya "$KILIT/sahip"
kilit_al $U 2>/dev/null; kod=$?
sina "başka süreç tutarken kilit_al 75 döner" '(( kod == 75 ))'
sina "tutucunun kilidi yerinde" '[[ $(sahip_pid_oku) == $tutucu ]]'
bas=$SECONDS; kilit_al $U 1 2>/dev/null; kod=$?
sina "beklemeli kilit_al süre dolunca 75 döner" '(( kod == 75 && SECONDS - bas >= 1 ))'

# 4) Üst düzey TERM tuzağı kilidi bırakır.
kill -TERM $tutucu; wait $tutucu 2>/dev/null; kod=$?; tutucu=""
sina "TERM sonrası tutucu 143 ile çıkar" '(( kod == 143 ))'
sina "TERM sonrası kilit kalktı" '[[ ! -e $KILIT ]]'

# 5) Normal çıkışta üst düzey EXIT tuzağı kilidi bırakır.
zsh -c "source '$BETIK'; kilit_al $U || exit 9; trap kilit_birak EXIT; [[ -d '$KILIT' ]] || exit 8; exit 0" 2>/dev/null; kod=$?
sina "betik içinde kilit tutuldu ve çıkışta" '(( kod == 0 ))'
sina "EXIT tuzağıyla kilit kalktı" '[[ ! -e $KILIT ]]'

# 6) Ölü pid'li sahip dosyası devralınır.
zsh -c 'exit 0' & olu=$!; wait $olu
mkdir -p "$KILIT"; print -l "pid=$olu" "lstart=Mon Jan  1 00:00:00 2001" "dizin=/yok" "git=eski" > "$KILIT/sahip"
cikti=$(kilit_al $U 2>&1); kod=$?
sina "ölü pid'li kilit devralınır" '(( kod == 0 )) && [[ $cikti == *"Bayat kilit devralındı"* ]]'
# $(...) alt kabuğunda $$ ana kabuğun pid'idir; devralınan kilit bu kabuğa yazılmış olmalı.
sina "devralınan kilidin sahibi bu süreç" '[[ $(sahip_pid_oku) == $$ ]]'
KILIT_YOLU=$KILIT; kilit_birak; unset ASISTAN_KILIT_SAHIBI

# 7) PID yaşıyor ama başlangıç anı farklı (PID yeniden kullanılmış): bayat sayılır.
sleep 30 & canli=$!
mkdir -p "$KILIT"; print -l "pid=$canli" "lstart=Mon Jan  1 00:00:00 2001" "dizin=/yok" "git=eski" > "$KILIT/sahip"
kilit_al $U 2>/dev/null; kod=$?
kill $canli 2>/dev/null
sina "lstart uyuşmazlığı bayat sayılır" '(( kod == 0 )) && [[ $(sahip_pid_oku) == $$ ]]'
kilit_birak

# 8) Sahip dosyası olmayan yarım kilit birkaç saniye sonra bayat sayılır.
mkdir -p "$KILIT"
kilit_al $U 2>/dev/null; kod=$?
sina "sahipsiz kilit dizini devralınır" '(( kod == 0 )) && [[ $(sahip_pid_oku) == $$ ]]'
kilit_birak

# 9) Geçersiz argümanlar.
kilit_al 2>/dev/null; kod=$?
sina "UDID'siz kilit_al 64 döner" '(( kod == 64 ))'
kilit_al $U abc 2>/dev/null; kod=$?
sina "sayı olmayan bekleme 64 döner" '(( kod == 64 ))'

# 10) Sürüm hesabı.
KOK=${0:A:h:h:h}
surum_hesapla
sina "SURUM 12 haneli YYYYMMDDHHMM" '[[ $SURUM =~ ^[0-9]{12}$ ]]'
sina "PAZARLAMA project.yml'den ayıklanır" '[[ $PAZARLAMA =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]'
sina "KIRLI sayı" '[[ $KIRLI =~ ^[0-9]+$ ]]'
sina "GIT boş değil" '[[ -n $GIT ]]'

# 11) Defter: tam 10 sekme alanlı tek satır.
UDID=$U YAPILANDIRMA=Release defter_yaz basarili 42
sina "defter tek satır" '[[ $(wc -l < "$KURULUM_DEFTERI" | tr -d " ") == 1 ]]'
sina "defter satırı 10 sekme alanlı" '[[ $(awk -F "\t" "{print NF}" "$KURULUM_DEFTERI") == 10 ]]'
sina "defter alanları sırada" '[[ $(cut -f2,7,9,10 "$KURULUM_DEFTERI") == "$U"$'"'"'\t'"'"'Release$'"'"'\t'"'"'basarili$'"'"'\t'"'"'42 ]]'

# 12) dSYM saklama: en yeni 5 klasör kalır.
mkdir -p "$ASISTAN_DSYM_DIZINI" "$GECICI/urun/Asistan.app.dSYM/Contents" "$GECICI/urun/AsistanKontrol.appex.dSYM"
for i in {1..6}; do mkdir -p "$ASISTAN_DSYM_DIZINI/eski$i"; touch -t "20260101000$i" "$ASISTAN_DSYM_DIZINI/eski$i"; done
dsym_sakla "$GECICI/urun" yeni 5
sina "dSYM yeni klasöre kopyalandı" '[[ -d $ASISTAN_DSYM_DIZINI/yeni/Asistan.app.dSYM && -d $ASISTAN_DSYM_DIZINI/yeni/AsistanKontrol.appex.dSYM ]]'
sina "yalnız son 5 klasör kalır" '(( $(ls -1 "$ASISTAN_DSYM_DIZINI" | wc -l) == 5 )) && [[ ! -e $ASISTAN_DSYM_DIZINI/eski1 && ! -e $ASISTAN_DSYM_DIZINI/eski2 && -e $ASISTAN_DSYM_DIZINI/eski6 ]]'
dsym_sakla "$GECICI/bos" yok 5 2>/dev/null; kod=$?
sina "dSYM yoksa uyarı verip 0 döner" '(( kod == 0 )) && [[ ! -e $ASISTAN_DSYM_DIZINI/yok ]]'

# 13) telefona-kur.sh: bayrak denetimi ve kilit çakışması derlemeye girmeden çıkar.
#     HOME geçici dizine yönlenir: kilit bir şekilde alınsa bile xcodegen bulunamaz, derleme başlamaz.
KUR=${0:A:h:h:h}/telefona-kur.sh
HOME=$GECICI/ev zsh "$KUR" --bilinmeyen >/dev/null 2>&1; kod=$?
sina "telefona-kur bilinmeyen bayrakta 64" '(( kod == 64 ))'
HOME=$GECICI/ev zsh "$KUR" --bekle=abc >/dev/null 2>&1; kod=$?
sina "telefona-kur sayı olmayan --bekle 64" '(( kod == 64 ))'
HOME=$GECICI/ev zsh "$KUR" X Y >/dev/null 2>&1; kod=$?
sina "telefona-kur fazla argümanda 64" '(( kod == 64 ))'
zsh -c "source '$BETIK'; kilit_al $U || exit 9; trap kilit_birak EXIT; trap 'kilit_birak; exit 143' TERM; sleep 30 & wait \$!" 2>/dev/null &
tutucu=$!
bekle_dosya "$KILIT/sahip"
HOME=$GECICI/ev zsh "$KUR" --udid $U >/dev/null 2>&1; kod=$?
sina "telefona-kur kilit doluyken 75 ile çıkar" '(( kod == 75 ))'
sina "telefona-kur kilit doluyken deftere yazmaz" '[[ $(wc -l < "$KURULUM_DEFTERI" | tr -d " ") == 1 ]]'
kill -TERM $tutucu; wait $tutucu 2>/dev/null; tutucu=""
HOME=$GECICI/ev zsh "$KUR" --udid $U >/dev/null 2>&1; kod=$?
sina "telefona-kur xcodegen yoksa 1 ve derleme_hatasi" '(( kod == 1 )) && [[ $(tail -1 "$KURULUM_DEFTERI" | cut -f9) == derleme_hatasi ]]'
sina "telefona-kur çıkışta kilidi bırakır" '[[ ! -e $KILIT ]]'

print "\n$basari geçti, $hata kaldı"
(( hata == 0 ))
