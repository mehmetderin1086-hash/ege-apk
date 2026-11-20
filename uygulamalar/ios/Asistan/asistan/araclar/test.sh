#!/bin/zsh
# P3.10: test planlarını simülatörde koşturur.
#   araclar/test.sh duman   → hermetik, ~2 dk: çekirdek birim testleri + SahteModelUITestleri + çekmece (Planlar/Duman.xctestplan)
#   araclar/test.sh tam     → birim testleri + bütün hermetik UI testleri (Planlar/Tam.xctestplan; canlı testler atlanır)
#   araclar/test.sh canli   → gerçek model/ağ (ÜCRETLİ), ASISTAN_CANLI=1 (Planlar/Canli.xctestplan)
# Ek bağımsız değişkenler xcodebuild'e geçer (ör. -only-testing:AsistanUITests/SahteModelUITestleri).
# Simülatör: ASISTAN_SIM_UDID (varsayılan AGENTS.md'deki simülatör). Tam günlük: ~/Developer/.build/asistan-test-<kip>.log
# Çıkış kodu xcodebuild'inkidir. Ağa yükleme, imzalı cihaz kurulumu ya da sır okuma yapmaz.
set -u

kip="${1:-}"
case "$kip" in
  duman) plan=Duman ;;
  tam)   plan=Tam ;;
  canli) plan=Canli ;;
  *) print -u2 "kullanım: araclar/test.sh duman|tam|canli [xcodebuild bağımsız değişkenleri…]"; exit 64 ;;
esac
shift

kok="${0:A:h:h}"
udid="${ASISTAN_SIM_UDID:-B3D3ABF3-2FE1-4EEA-8896-8386034F6802}"
gunluk_dizin="$HOME/Developer/.build"
mkdir -p "$gunluk_dizin"
gunluk="$gunluk_dizin/asistan-test-$kip.log"

ek=()
# Canlı plan ASISTAN_CANLI=1'i ortam değişkeni olarak zaten verir; derleme ayarı da geçirilir ki Tam planın
# "$(ASISTAN_CANLI)" genişletmesi ve eski şema yolu da aynı değeri görsün.
[[ "$kip" == canli ]] && ek+=(ASISTAN_CANLI=1)

[[ "$kip" == canli ]] && print "UYARI: canlı plan gerçek modellere ve dış sitelere çıkar (ücretli)."
print "Plan: $plan · simülatör $udid · günlük $gunluk"
baslangic=$SECONDS

xcodebuild test \
  -project "$kok/Asistan.xcodeproj" \
  -scheme Asistan \
  -testPlan "$plan" \
  -destination "platform=iOS Simulator,id=$udid" \
  "${ek[@]}" "$@" >"$gunluk" 2>&1
kod=$?

# Özet: derleme hataları, başarısız testler ve sonuç satırları (Swift Testing + XCTest).
grep -E "error:|✘ Test|Test Case .* failed|Test run with [0-9]+ tests|Executed [0-9]+ tests|\*\* TEST (SUCCEEDED|FAILED) \*\*" "$gunluk" | tail -40
sure=$(( SECONDS - baslangic ))
print "Süre: ${sure} sn · çıkış kodu $kod"
exit $kod
