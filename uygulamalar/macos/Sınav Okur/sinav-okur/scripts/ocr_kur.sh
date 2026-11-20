#!/bin/zsh
set -euo pipefail

PROJE_KOKU="${0:A:h:h}"
UV_BIN="${UV_BIN:-$(command -v uv || true)}"

if [[ -z "$UV_BIN" ]]; then
  print -u2 "uv bulunamadı. Önce https://docs.astral.sh/uv/ kurulmalı."
  exit 2
fi

ortam_kur() {
  local motor="$1"
  shift
  local ortam="$PROJE_KOKU/.ocr-envs/$motor"
  if [[ ! -x "$ortam/bin/python" ]]; then
    "$UV_BIN" venv --python 3.12 "$ortam"
  fi
  "$UV_BIN" pip install --python "$ortam/bin/python" "$@"
}

hedef="${1:-all}"
case "$hedef" in
  tesseract)
    ortam_kur tesseract pillow tesserocr
    mkdir -p "$PROJE_KOKU/.ocr-models/tessdata"
    curl -fL --retry 3 \
      -o "$PROJE_KOKU/.ocr-models/tessdata/tur.traineddata" \
      "https://github.com/tesseract-ocr/tessdata_best/raw/main/tur.traineddata"
    curl -fL --retry 3 \
      -o "$PROJE_KOKU/.ocr-models/tessdata/eng.traineddata" \
      "https://github.com/tesseract-ocr/tessdata_best/raw/main/eng.traineddata"
    [[ "$(/usr/bin/shasum -a 256 "$PROJE_KOKU/.ocr-models/tessdata/tur.traineddata" | /usr/bin/awk '{print $1}')" == \
      "e0c3338dc17503dc7d335a507c9ae01b2b46cfd07561171e1e1ac55d85e8e438" ]] \
      || { print -u2 "Türkçe Tesseract modeli doğrulanamadı."; exit 3; }
    [[ "$(/usr/bin/shasum -a 256 "$PROJE_KOKU/.ocr-models/tessdata/eng.traineddata" | /usr/bin/awk '{print $1}')" == \
      "8280aed0782fe27257a68ea10fe7ef324ca0f8d85bd2fd145d1c2b560bcb66ba" ]] \
      || { print -u2 "İngilizce Tesseract modeli doğrulanamadı."; exit 3; }
    ;;
  easyocr)
    ortam_kur easyocr easyocr
    ;;
  paddle)
    ortam_kur paddle \
      --index-url "https://www.paddlepaddle.org.cn/packages/stable/cpu/" \
      paddlepaddle==3.3.0
    ortam_kur paddle paddleocr
    ;;
  surya)
    ortam_kur surya surya-ocr
    mkdir -p "$PROJE_KOKU/.ocr-tools/llama.cpp"
    surum="b10093"
    beklenen_sha="6379088df10bc7af31c61e887160bb6bf7a980346c723d27b6d1f27a88432f78"
    arsiv="$PROJE_KOKU/.ocr-tools/llama.cpp/llama-${surum}-macos-arm64.tar.gz"
    if [[ ! -f "$arsiv" ]]; then
      curl -fL --retry 3 -o "$arsiv" \
        "https://github.com/ggml-org/llama.cpp/releases/download/$surum/llama-${surum}-bin-macos-arm64.tar.gz"
    fi
    gercek_sha="$(/usr/bin/shasum -a 256 "$arsiv" | /usr/bin/awk '{print $1}')"
    if [[ "$gercek_sha" != "$beklenen_sha" ]]; then
      print -u2 "llama.cpp arşiv özeti doğrulanamadı."
      exit 3
    fi
    tar -xzf "$arsiv" -C "$PROJE_KOKU/.ocr-tools/llama.cpp"
    ;;
  all)
    "$0" tesseract
    "$0" easyocr
    "$0" paddle
    "$0" surya
    ;;
  *)
    print -u2 "Kullanım: $0 [all|tesseract|easyocr|paddle|surya]"
    exit 2
    ;;
esac

print "Hazır: $hedef"
