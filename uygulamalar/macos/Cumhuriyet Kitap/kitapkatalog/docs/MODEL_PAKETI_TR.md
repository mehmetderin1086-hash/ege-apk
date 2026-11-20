# Çevrimdışı model paketini hazırlama

KitapKatalog çalışma zamanında dosya indirmez. Model ve platforma özgü yerel
çalıştırılabilir dosyalar dağıtım hazırlanırken lisanslarına uygun biçimde
temin edilmeli, aşağıdaki dizilime yerleştirilmeli ve hash kilidi
oluşturulmalıdır.

## Beklenen kaynak dizilimi

```text
model-kaynagi/
├── bin/
│   ├── tesseract
│   └── llama-server
├── rapidocr/
│   ├── PP-OCRv6_det_medium.onnx
│   └── PP-OCRv6_rec_medium.onnx
├── tessdata/
│   ├── tur.traineddata
│   └── eng.traineddata
├── easyocr/
│   ├── craft_mlt_25k.pth
│   └── latin_g2.pth
├── paddleocr-vl/
│   ├── model.gguf
│   └── mmproj.gguf
├── surya/
│   ├── model.gguf
│   └── mmproj.gguf
├── qwen3/
│   └── Qwen3-4B-Q4_K_M.gguf
└── calibration/
    └── ensemble.json  # otomatik alan kabulü için
```

RapidOCR small detector/recognizer ve yön sınıflandırıcı ONNX dosyaları
varsayılan olarak build ortamındaki test edilmiş `rapidocr` paketinden alınır.
Medium detector ve recognizer ise paket tarafından dağıtılmadığından her zaman
yerel kaynak dizininden alınır:

- `rapidocr/PP-OCRv6_det_medium.onnx`
- `rapidocr/PP-OCRv6_rec_medium.onnx`

Hazırlama aracı bu dosyaları indirmez. Eksik medium dosyasında paket üretimi
fail-closed durur. Small dosyaların da kaynak dizininden alınması istenirse
`rapidocr/PP-OCRv6_det_small.onnx`,
`rapidocr/PP-OCRv6_rec_small.onnx` ve
`rapidocr/ch_ppocr_mobile_v2.0_cls_mobile.onnx` verilip
`--rapidocr-source source` kullanılabilir.

`calibration/ensemble.json` beş OCR’ın çalışması için zorunlu değildir.
Ancak geçerli ve güvenilir profil yoksa otomatik alan kabulü fail-closed
kapanır ve bütün alan adayları incelemeye gider. Profil, model ağırlığı gibi
başka bir projeden kopyalanmamalı; bu kurulumun kesin OCR/model/prompt
digestleriyle, eser-baskı-fotoğraf oturumu ayrık kalibrasyon kümesinden
üretilmelidir.

Kalibrasyon kaynağı CSV, JSON veya JSONL olabilir. Her satır/nesne
`raw_confidence` (veya `confidence`) ve boolean `correct` alanını taşır:

```json
{"raw_confidence": 0.973, "correct": true}
```

Yalnız ayrık kalibrasyon bölümünden monoton izotonik profil üretin:

```bash
.venv/bin/kitapkatalog fit-calibration \
  /mutlak/yol/kalibrasyon.jsonl \
  /mutlak/yol/model-kaynagi/calibration/ensemble.json \
  --version "kalibrasyon-2026-07" \
  --minimum-samples 200
```

Varsayılan asgari örnek sayısı 200’dür. Daha az örnekle dosya oluşsa da
`trusted=false` kalır ve otomatik kabul açılmaz. Eğitim veya kör test örneğini
kalibrasyon komutuna vermek veri sızıntısıdır.

## Hash kilidi

Geliştirme ortamı kurulduktan sonra:

```bash
.venv/bin/python scripts/prepare_offline_bundle.py \
  /mutlak/yol/model-kaynagi \
  /mutlak/yol/KitapKatalog-models
```

Komut ağ kullanmaz, eksik tek bir dosyada bile hedefi yayımlamaz ve bütün
model artifact’larının yanında `bin/tesseract` ile `bin/llama-server`
çalıştırılabilir dosyalarının SHA-256/boyut değerlerini
`model_manifest.lock.json` içine yazar. Kaynakta doğrulanmış
`calibration/ensemble.json` varsa onu da `optional_artifacts` altında
SHA-256/boyut ile kilitler. Hedef önceden varsa güvenlik için üzerine yazılmaz.

Doğrulama:

```bash
.venv/bin/python scripts/prepare_offline_bundle.py . . \
  --verify /mutlak/yol/KitapKatalog-models
```

Başarılı çıktı `{"valid": true, "problems": []}` biçimindedir. Çalışma
zamanında manifestte hashesiz, boyutu değişmiş veya eksik artifact bulunduğunda
beş-OCR işi başlamaz.

Motor/model artifact kilidi başarılı olsa bile `calibration/ensemble.json`
ayrıca uygulama açılışında şema, monotonluk, örnek sayısı ve içerik digest’i
bakımından doğrulanır. Profil yokluğu model paketini OCR için geçersiz yapmaz;
yalnız `auto` karar yetkisini kaldırır. Buna karşılık manifestte tanımlı
profilin eksik, hash-uyuşmaz veya bozuk olması paket bütünlüğü hatasıdır.
Profilin el ile yüksek olasılıklar yazılarak üretilmesi kabul testinin yerine
geçmez.

## Platform paketleri

macOS arm64 ve Windows x64 model paketleri ayrı üretilir. `bin/` altındaki
dosyalar hedef platformun yerel çalıştırılabilir dosyaları olmalıdır. Model
bytes’ları ortak olabilir; yine de her platform paketinin kilit manifesti
ayrıca oluşturulur.

Paketleme sırasında:

- `TESSDATA_PREFIX` paket içindeki `tessdata` dizinine yöneltilir;
- `KITAPKATALOG_LLAMA_BACKEND` paket içindeki `llama-server` yoludur;
- alan çıkarıcı `llama-server` yalnız `127.0.0.1` üzerinde rastgele boş bir
  portta ve dış ağ kapalı başlatılır;
- `HF_HUB_OFFLINE`, `TRANSFORMERS_OFFLINE` ve `HF_DATASETS_OFFLINE` `1` olur;
- EasyOCR `download_enabled=False` ile açılır.

Uygulama ve model paketi kaynak çalıştırmada birbirinden ayrı taşınabilir.
Doğrulanmış paketle üretilen macOS yayını modelleri
`.app/Contents/Resources/KitapKatalog-models` içine gömer; uygulama tek parça
olarak taşınabilir. Yerel platform uygulamasını üretmek için:

```bash
.venv/bin/python scripts/build_release.py native macos-arm64 \
  /mutlak/yol/KitapKatalog-macos-arm64 \
  --model-bundle /mutlak/yol/KitapKatalog-models
```

PySide/Nuitka paketleyicisinin yerel bağımlılıklarla uyumsuz olduğu bir build
ortamında aynı sözleşme çevrimdışı PyInstaller arka ucuyla üretilebilir:

```bash
.venv/bin/python scripts/build_release.py native macos-arm64 \
  /private/tmp/KitapKatalog-macos-arm64 \
  --backend pyinstaller \
  --model-bundle /mutlak/yol/KitapKatalog-models
```

Windows x64 yayını yalnız Windows x64 üzerinde `windows-x64` hedefiyle
üretilir; araç çapraz derleme yapmaz. Model eklenmeden oluşturulan uygulama
katalog, inceleme, dışa aktarım ve yedekleme için açılabilir; OCR durumu eksik
görünür ve işleme başlamaz.

Önce indirimsiz paketleme sözleşmesini görmek için aynı komuta `--dry-run`
eklenebilir. Build aracı `PIP_NO_INDEX=1` kullanır; seçilen arka uca göre
PySide6, Nuitka/ordered-set/zstandard veya PyInstaller build ortamında önceden
kurulu olmalıdır. macOS’ta File Provider özniteliklerinin imzayı bozmaması için
native hedefi iCloud/Documents dışındaki yerel bir klasörde üretin.

Paket tamamlandıktan sonra model yüklemeden çalışma zamanı kapsamını:

```bash
/private/tmp/KitapKatalog-macos-arm64/dist/KitapKatalog.app/Contents/MacOS/KitapKatalog \
  --runtime-smoke
```

ile; imzayı da `codesign --verify --deep --strict KitapKatalog.app` ile
doğrulayın. Frozen PaddleOCR‑VL/Surya işçileri aynı executable’ı
`--vision-sidecar` modunda kullanır; ayrı bir Python yorumlayıcısına güvenmez.

## RapidOCR tek oy politikası

PP-OCRv6-small her kanonik tam kapağı işler. Small geçişte hiç token çıkmazsa
veya herhangi bir token güveni yapılandırılmış yükseltme eşiğinin altındaysa
PP-OCRv6-medium detector+recognizer aynı tam kapakta ikinci geçişi yapar.
Örtüşen kutularda düşük güvenli small gözlemi daha güvenli medium gözlemiyle
değiştirilir; medium’un bulduğu yeni kutular eklenir. İki geçiş tek bir
`rapidocr_ppocrv6` sonucu ve tek bir ensemble oyu olarak kalır.

Eşikler, Tesseract `tur+eng`/PSM ayarı ve vision sidecar’ın motor profili/prompt
protokolü model digest’ine katılır. Bunlardan biri değiştiğinde eski OCR cache’i
yeniden kullanılmaz.

PaddleOCR-VL ve Surya aynı sidecar protokolünü kullansa da istekleri ayrıdır:
PaddleOCR-VL karmaşık kapak düzeni, perspektif ve kutu geometrisine; Surya uzun
arka kapak paragrafları ile okuma sırasına yönlendirilir. Sidecar yanıtındaki
motor kimliği istekle birebir uyuşmadığında sonuç reddedilir.

## Lisans notu

Uygulama kodunun MIT lisansı model ve üçüncü taraf runtime lisanslarını
kapsamaz. Özellikle bir Surya kaynak deposunun kod lisansı ile seçilen GGUF
model ağırlığının koşulları aynı olmayabilir; planlanan ağırlık
Modified-OpenRAIL-M koşulları taşıyabilir. “Apache-2.0” varsayımı yeniden
dağıtım izni yerine kullanılmamalıdır. Ticari veya geniş dağıtım öncesinde
indirilen kesin model sürümü, model kartı, dönüştürme kaynağı, llama.cpp,
Tesseract/tessdata ve Python bağımlılıkları için ayrı lisans envanteri ile
hukuk incelemesi yapılmalıdır.

## Bu çalışma alanındaki durum

Bu kaynak ağacında lisanslı tam beş-model paketi bulunmaz. Paket hazırlama ve
doğrulama kodu eksik/hash-uyuşmaz artifact’ta fail-closed çalışacak biçimde
hazırdır; bu durum tüm modellerin bu makinede gerçek kapaklarla birlikte
çalıştırılıp performans/doğruluk hedeflerini geçtiği anlamına gelmez.
