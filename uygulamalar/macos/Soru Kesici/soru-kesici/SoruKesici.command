#!/bin/zsh
# Soru Kesici web arayüzü — Finder'da çift tıklayarak açabilirsiniz.

# Başlatıcı masaüstüne sembolik bağ olarak konursa da proje dizinini bul.
BETIK_YOLU="$0"
while [ -L "$BETIK_YOLU" ]; do
  BETIK_DIZINI="$(cd -P "$(dirname "$BETIK_YOLU")" >/dev/null 2>&1 && pwd)"
  BETIK_YOLU="$(readlink "$BETIK_YOLU")"
  [[ "$BETIK_YOLU" = /* ]] || BETIK_YOLU="$BETIK_DIZINI/$BETIK_YOLU"
done
PROJE_DIZINI="$(cd -P "$(dirname "$BETIK_YOLU")" >/dev/null 2>&1 && pwd)"
PYTHON="$PROJE_DIZINI/.venv/bin/python"

if [ ! -x "$PYTHON" ]; then
  print -u2 "Soru Kesici Python ortamı bulunamadı: $PYTHON"
  read -k 1 "?Kapatmak için bir tuşa basın..."
  exit 1
fi

cd "$PROJE_DIZINI" || exit 1
exec "$PYTHON" "$PROJE_DIZINI/soru_kes_web.py"
