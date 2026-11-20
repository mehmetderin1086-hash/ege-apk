#!/bin/zsh
# Xcode derleme sonrası adımı (python-kur.sh çağırır; imzalama bütün betik aşamalarından sonra yapılır):
# uygulama paketindeki Info.plist'e git kısa hash'ini, değişmiş dosya sayısını, derleme zamanını ve
# yapılandırmayı yazar. Hiçbir durumda hata kodu döndürmez; derlemeyi asla düşürmez.
# telefona-kur.sh ASISTAN_GIT_HASH / ASISTAN_KIRLI derleme ayarlarını verir; Xcode arayüzünden derlemede git'ten okunur.
PL="${CODESIGNING_FOLDER_PATH:-}/Info.plist"
if [[ -z ${CODESIGNING_FOLDER_PATH:-} || ! -f $PL ]]; then
  print -u2 "surum-damgala: Info.plist bulunamadı, atlandı ($PL)"
  exit 0
fi
KOK=${PROJECT_DIR:-${0:A:h:h}}
GIT=${ASISTAN_GIT_HASH:-$(git -C "$KOK" rev-parse --short HEAD 2>/dev/null)}
GIT=${GIT:-yok}
KIRLI=${ASISTAN_KIRLI:-$(git -C "$KOK" status --porcelain 2>/dev/null | wc -l | tr -d ' ')}
[[ $KIRLI == <-> ]] || KIRLI=0
ZAMAN=$(date +%Y-%m-%dT%H:%M:%S%z)
TUR=${CONFIGURATION:-bilinmiyor}

yaz() {
  /usr/libexec/PlistBuddy -c "Set :$1 $2" "$PL" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :$1 string $2" "$PL" 2>/dev/null \
    || print -u2 "surum-damgala: $1 yazılamadı"
}
yaz AsistanGitHash "$GIT"
yaz AsistanDegisikDosya "$KIRLI"
yaz AsistanDerlemeZamani "$ZAMAN"
yaz AsistanDerlemeTuru "$TUR"
print "surum-damgala: git $GIT +$KIRLI · $TUR · $ZAMAN"
exit 0
