#!/bin/zsh
set -eu

export PATH=/Users/mehmetderin/Developer/biyo-cozucu/.venv/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
export PYTHONUNBUFFERED=1

project_root=/Users/mehmetderin/Developer/biyo-cozucu
data_root=/Users/mehmetderin/.biyo-cozucu
book_dir="$data_root/kitaplar"
target_pdf="$book_dir/campbell.pdf"
partial_pdf="$book_dir/campbell.pdf.part"
database="$data_root/biyo.db"
checkpoint="$book_dir/.campbell-ocr-v1.checkpoint"
report="$book_dir/campbell-validation.txt"
missing_audit="$book_dir/campbell-missing-audit.jsonl"
expected_size=187751026
expected_pages=1101
chunk_size=40
download_source='/Users/mehmetderin/Library/Mobile Documents/com~apple~CloudDocs/biyoloji-campbell.pdf'

mkdir -p "$book_dir"
touch "$checkpoint"
cd "$project_root"

pdf_ready() {
  local candidate=$1
  [[ -f "$candidate" ]] || return 1
  [[ $(stat -f %z "$candidate") -eq $expected_size ]] || return 1
  ! ls -lO "$candidate" | grep -q dataless
}

if ! pdf_ready "$target_pdf"; then
  print "Campbell PDF iCloud'dan bekleniyor: $(date '+%Y-%m-%dT%H:%M:%S%z')"
  source_pdf=''
  while [[ -z "$source_pdf" ]]; do
    # Yalnız asıl iCloud öğesini indir. Yedek adaylar ancak zaten fiziksel
    # olarak hazırsa kullanılır; böylece FileProvider kuyruğu çoğaltılmaz.
    /usr/bin/brctl download "$download_source" 2>/dev/null || true
    candidates=(
      "$download_source"
      '/Users/mehmetderin/Desktop/Yeni klasör (3)/biyoloji-campbell.pdf'
      /private/tmp/biyo-campbell-finder.*/biyoloji-campbell.pdf(N)
    )
    for candidate in "${candidates[@]}"; do
      if pdf_ready "$candidate"; then
        source_pdf="$candidate"
        break
      fi
    done
    [[ -z "$source_pdf" ]] && sleep 30
  done

  print "Campbell kaynağı hazır: $source_pdf"
  /bin/cp "$source_pdf" "$partial_pdf"
  [[ $(stat -f %z "$partial_pdf") -eq $expected_size ]]
  .venv/bin/python -c \
    'import pypdfium2,sys; p=pypdfium2.PdfDocument(sys.argv[1]); assert len(p)==int(sys.argv[2]); p.close()' \
    "$partial_pdf" "$expected_pages"
  /bin/mv -f "$partial_pdf" "$target_pdf"
fi

chunk_done() {
  /usr/bin/grep -Fxq -- "$1-$2" "$checkpoint"
}

ocr_range() {
  local start=$1
  local last=$2
  local end attempt
  while (( start <= last )); do
    end=$(( start + chunk_size - 1 ))
    (( end > last )) && end=$last
    if chunk_done "$start" "$end"; then
      print "Dilim $start-$end daha önce tamamlandı; atlanıyor."
      start=$(( end + 1 ))
      continue
    fi

    attempt=1
    while (( attempt <= 3 )); do
      print "Dilim $start-$end deneme $attempt: $(date '+%Y-%m-%dT%H:%M:%S%z')"
      if .venv/bin/python -u -m biyo_cozucu.cli kitap-al "$target_pdf" \
        --kaynak 'Campbell Biyoloji' \
        --baslangic "$start" --bitis "$end" \
        --ocr zorla --ocr-motoru surya --indekssiz; then
        print -r -- "$start-$end" >> "$checkpoint"
        break
      fi
      attempt=$(( attempt + 1 ))
      (( attempt <= 3 )) && sleep 15
    done
    if (( attempt > 3 )); then
      print -u2 "Campbell OCR $start-$end diliminde üç kez başarısız oldu."
      exit 4
    fi
    start=$(( end + 1 ))
  done
}

# İlk yerel koşunun 101-149 aralığı ve Colab checkpoint'inin 162-632
# aralığı veritabanına aktarıldı. Kalan OCR'yi ilk eksik sayfadan sürdür.
ocr_range 101 149
ocr_range 633 1101

# Ana koşuda OCR boş dönen ya da yalnız çok kısa metin taşıyan sayfaları bir
# kez daha aynı modelle oku. Yeterli metin dönenler eklenir; gerçek kısa/boş
# sayfalar ile OCR hataları denetim dosyasında birbirinden ayrılır.
.venv/bin/python -u scripts/campbell_missing_retry.py "$target_pdf" \
  --veritabani "$database" \
  --kaynak 'Campbell Biyoloji' \
  --son "$expected_pages" \
  --ocr-motoru surya \
  --denetim "$missing_audit"

{
  print "Campbell doğrulaması: $(date '+%Y-%m-%dT%H:%M:%S%z')"
  actual_size=$(stat -f %z "$target_pdf")
  print "PDF boyutu: $actual_size (beklenen $expected_size)"
  [[ "$actual_size" -eq "$expected_size" ]]

  .venv/bin/python -c \
    'import pypdfium2,sys; p=pypdfium2.PdfDocument(sys.argv[1]); print(f"PDF sayfası: {len(p)}"); assert len(p)==1101; p.close()' \
    "$target_pdf"

  sqlite3 -header -column "$database" \
    "SELECT COUNT(*) AS pasaj, MIN(sayfa) AS min_sayfa, MAX(sayfa) AS max_sayfa, COUNT(DISTINCT sayfa) AS sayfali_sayfa, ROUND(AVG(LENGTH(metin)),1) AS ort_karakter, SUM(LENGTH(TRIM(metin)) < 120) AS cok_kisa, SUM(LENGTH(metin) > 1200) AS cok_uzun FROM pasaj WHERE aktif=1 AND kaynak='Campbell Biyoloji';"

  missing=$(sqlite3 "$database" \
    "WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM n WHERE x<1101) SELECT COUNT(*) FROM n WHERE NOT EXISTS (SELECT 1 FROM pasaj p WHERE p.aktif=1 AND p.kaynak='Campbell Biyoloji' AND p.sayfa=n.x);")
  suspicious=$(sqlite3 "$database" \
    "SELECT COUNT(*) FROM pasaj WHERE aktif=1 AND kaynak='Campbell Biyoloji' AND (metin LIKE '%Inference error%' OR metin LIKE '%Connection error%' OR metin LIKE '%Traceback%');")
  print "Pasajsız sayfa: $missing"
  print "Şüpheli hata metni: $suspicious"
  print "Pasajsız sayfa yeniden OCR denetimi:"
  cat "$missing_audit"
  (( missing <= 22 ))
  (( suspicious == 0 ))

  print "Campbell OCR ve doğrulama tamamlandı."
} >| "$report" 2>&1

print "Campbell entegrasyonu tamamlandı: $report"
