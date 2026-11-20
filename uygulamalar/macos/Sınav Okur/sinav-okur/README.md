# sinav-okur

**Türkçe el yazısıyla yazılmış sınavları okuyup puanlayan** sistem — biyoloji ve
tıp/sağlık alanına odaklıdır. Açık uçlu, kısa cevaplı, boşluk doldurmalı, çoktan
seçmeli, sayısal, formül/ispat, sıralama, eşleştirme, tablo, grafik, çizim, deney
tasarlama, yorumlama ve etik sorularını destekler. Eğitim Google Colab'da
(ücretsiz T4), çıkarım Mac'te (Apple Silicon) yapılacak şekilde tasarlandı.

> **Neden sıfırdan?** Türkçe el yazısı koleksiyonları literatürde var; ancak açık
> lisanslı, indirilebilir, satır-transkripsiyonlu ve sınav alanına benzeyen yeterli
> büyüklükte bir eğitim seti bulunmuyor. Sistem bu nedenle yalnız izinli **gerçek**
> el yazısını kabul eden bir veri toplama/insan düzeltme döngüsü kurar.

## Mimari

```
Temiz yazılıyı yükle (PDF/fotoğraf, 1–4 sayfa)
   │
   ├──► soru + puan + cevap bölgesi algılama ──► cevap anahtarı/rubrik
   │
Öğrenci kâğıtlarını yükle
   │
   └──► kalite kapısı ──► ön/arka sayfa eşleme ──► el yazısı bölgeleri
                                                      │
                                   çoklu HTR uzlaşması ──► esnek puanlama
                                                      │
 Ders kitabı ──► kanıtlı cevap anahtarı ─────────────┘
                                                      ▼
                             FastAPI inceleme ──► Excel + sınav analizi
                             (risk öncelikli onay) + denetlenebilir öğrenme
```

**Yükleme-öncelikli tasarım:** Sistem kâğıt üretmez. Word, fotokopi, yayınevi veya
elde hazırlanmış temiz yazılının PDF/fotoğrafı doğrudan yüklenir. Basılı doku,
soru numaraları ve sayfa görünümü görsel referans olur; öğrenci kâğıdı buna
hizalanarak yalnız yeni el yazısı bölgeleri değerlendirilir. Ön–arka ve en fazla
dört sayfa desteklenir.

**Takılabilir HTR:**
- `keras-ctc` — gerçek, yazar-ayrık Türkçe satırlarla eğitilen asıl CNN–BiLSTM–CTC yolu.
- `keras-karakter` — T-H-E Version VI ile 29 harflik casefold karakter fallback'i;
  kalibre eşik altında ve bağlı yazıda insan incelemesine düşer.
- `trocr` — `microsoft/trocr-base-handwritten` (MIT), satır düzeyi, Mac'te CPU/MPS.
- `mlx` — `Qwen2.5-VL-7B` (Apache-2.0), kutu düzeyi, Apple Silicon'da mlx-vlm.

Hangisinin kazanacağına görülmemiş yazarların gerçek test setindeki CER/WER karar verir.

**Soru tipine göre puanlama:**
| Tip | Yöntem |
|-----|--------|
| Boşluk doldurma | rapidfuzz bulanık eşleme + eş anlamlı listesi + aksan toleransı |
| Kısa cevap | rubrik kalemi başına sözcüksel + anlamsal (gömme) eşleşme, kısmi puan |
| Açık uçlu | kavram kapsamı + anlamsal arama + doğru mantık/yöntem ve ara adıma kısmi puan |
| Sıralama / eşleştirme | doğru adım veya doğru çift başına kısmi puan |
| Sayısal / formül | tolerans, birim, yöntem adımları ve güvenli sembolik eşdeğerlik |
| Tablo / grafik / çizim | yapısal bileşen analizi + zorunlu görsel inceleme |

## Güvenli otomatik değerlendirme

- Kâğıt üzerindeki öğretmen puanı, kırmızı tik/çarpı, daire ve kenar notları
  cevap anahtarı veya doğruluk sinyali olarak **asla kullanılmaz**. Renkli
  öğretmen mürekkebi OCR görüntüsünden ayrılır; program öğrenci cevabını kendi
  cevap anahtarı ve rubriğiyle baştan puanlar.
- Aynı bölge farklı görüntü ön işlemleri ve kullanılabilir OCR motorlarıyla
  okunur. Uzlaşmayan okumalar alternatifleriyle gösterilir ve incelemeye düşer.
- Bulanıklık, parlama, gölge, eğrilik, düşük çözünürlük, eksik kâğıt, yinelenen
  veya karışmış sayfa tarama kalite kapısında denetlenir.
- Ad, soyad, numara, sınıf ve şube en fazla dört sayfanın üst bilgisinden
  çıkarılır; öğrenci listesi içe aktarıldıysa yerel ve bulanık eşleştirme yapılır.
- Cevap anahtarı soru metni ve yerel ders kaynaklarından taslak olarak
  oluşturulabilir. Her anahtar kaynak kanıtı, sürüm ve öğretmen onayı taşır.
- Esnek puanlama yalnız sonuca değil doğru mantık, bilimsel gerekçe, yöntem ve
  ara adımlara da puan verir. Açık çelişkiler ve zorunlu kritik hatalar ayrıca
  gösterilir; OCR güveniyle puanlama güveni birbirinden ayrıdır.
- Öğretmenin arayüzde açıkça yaptığı düzeltmeler denetim kaydına girer. Tek bir
  düzeltme sistemi değiştirmez; ancak aynı soruda yeterli sayıda tutarlı örnek
  oluşursa sınırlı ve geri izlenebilir bir kalibrasyon önerisi doğar.
- Sınav analizi soru başarılarını, riskli cevapları, olası hatalı anahtarı,
  benzer cevaplara tutarsız puanları ve öğretmen düzeltme farklarını gösterir.
- Kimlik verisi cihazdan çıkmaz; saklama süresi dolan kimlikler akademik
  puan ve denetim izi korunarak anonimleştirilebilir.

**Referanslı puanlama:** `referans` komutuyla ders kitapları indekslenir. Her soru için
en ilgili kitap pasajı bulunur; öğretmene gözden geçirmede kanıt gösterilir ve öğrenci
cevabı kitapla güçlü örtüşüyor ama rubrik kaçırmışsa sonuç **incele**ye işaretlenir
(haksız sıfırı engeller).

**İnsan onayı (flywheel):** Düşük güvenli tanıma/puanlar webapp'te öğretmene düşer;
düzeltilmiş transkripsiyonlar `disaaktar` ile toplanıp modeli yeniden eğitmek için
JSONL'e akar.

## Kurulum

```bash
cd sinav-okur
uv sync                    # çekirdek
uv sync --extra gomme      # anlamsal puanlama (sentence-transformers)
uv sync --extra htr        # yerel TrOCR çıkarımı (torch + transformers)
uv sync --extra mlx        # Apple Silicon'da Qwen-VL (mlx-vlm)
uv sync --extra keras      # Keras CNN/CTC çıkarımı (TensorFlow)
```

`gomme`, `htr`, `mlx` opsiyoneldir — kurulu değilse sistem düşük yetenekle **çalışmaya
devam eder** (ör. gömme yoksa puanlama sözcüksel katmanla sınırlanır).

## Kullanım

```bash
# 1) Uygulamayı aç
sinav-okur webapp        # http://127.0.0.1:8000

# 2) (Opsiyonel) ders kitaplarından yerel referans indeksi kur
sinav-okur referans ders_kitabi.pdf konu_notlari.pdf -o referans_indeks/

# 3) Not dökümü + izinli/düzeltilmiş yeniden eğitim verisi
sinav-okur rapor BIYO9-2026-01 -o notlar.xlsx
sinav-okur disaaktar -o egitim_verisi.jsonl
```

Arayüzde önce **Yazılıyı tanıt** ekranından temiz 1–4 sayfayı yükleyin, bulunan
soruları ve otomatik cevap anahtarını doğrulayın. Ardından **Kâğıt yükle**
ekranında tek öğrenci veya tüm sınıf dosyalarını seçin. OCR motoru aynı ekrandan
seçilir; düşük güvenli sonuçlar otomatik olarak incelemeye ayrılır.

Colab'dan indirilen karakter veya satır modeli `modeller/` altına kurulduğunda
arayüzde OCR seçeneği olarak görünür:

```bash
uv sync --extra keras
sinav-okur webapp
```

Gerçek, izinli ve yazar-ayrık satırlarla 06 defterinde CTC modeli eğitildikten sonra
`modeller/gercek_satir_ctc/turkce_gercek_satir_ctc.keras` yoluna kurulur ve
arayüzde `keras-ctc` seçilir. Her iki backend
de etiket ve kalibrasyon JSON dosyalarını modelin bulunduğu dizinden otomatik yükler.

## Colab defterleri (`colab/`)

| Defter | Ne yapar | Donanım |
|--------|----------|---------|
| `01_sentetik_veri.ipynb` | **Eski demo/test hattı; gerçek eğitime alınmaz** | CPU |
| `02_trocr_finetune.ipynb` | Eski deney hattı; gerçek satır manifesti olmadan ürün modeli sayılmaz | T4 |
| `03_qwen_vl_qlora.ipynb` | Qwen2.5-VL-7B QLoRA (Unsloth) | T4 |
| `04_puanlayici_ft.ipynb` | Türkçe gömme modelini öğretmen puanlarıyla uyarlar (CoSENT) | T4 |
| `05_keras_cnn_karakter.ipynb` | T-H-E Version VI, 29 casefold Türkçe harfi, artırmasız Keras CNN + seçici kabul | T4 |
| `06_keras_ctc_gercek_satir.ipynb` | İzinli gerçek sınav satırları, yazar-ayrık Keras CTC | T4 |
| `07_gercek_benchmark.ipynb` | Keras CTC / TrOCR / PaddleOCR aynı testte CER/WER | T4 |

Gerçek-veri-only sıra: **05 → kendi izinli kâğıtlarını düzelt/dışa aktar → 06 → 07**.

### Gerçek Türkçe el yazısı verisi

T-H-E'nin altı CSV'si üst üste eklenmez: sürümler örtüşür; Version I artırılmış
veri içerir, Version V farklı sınıf semantiğine sahiptir. Yalnız artırılmamış
`version6.csv` alınır. Kaynak README 78.000 örnek dese de gerçek dosya 76.000
satır/76 sınıftır; büyük `Ç` ve `Ş` eksiktir. Makalede **public-domain/free-to-use**
ifadeleri bulunsa da depoda açık bir SPDX lisansı yoktur; bu nedenle kullanım
özel/izinli kabul edilir ve yeniden dağıtım yapılmaz. Kanıt manifestte makale
bağlantısıyla kaydedilir. Kaynak hatasını sentetik veriyle kapatmak yerine,
büyük/küçük el yazısının görsel belirsizliği 29 harflik casefold modelinde
birleştirilir; büyük harf bağlamdan geri kurulur:

```bash
git clone https://github.com/bartosgaye/thedataset
cd thedataset && git lfs install && git lfs pull --include=version6.csv
sinav-okur theveri thedataset/version6.csv -o the_karakter_verisi
```

T-H-E karakterlerini yan yana dizmek gerçek insan satırı olmadığı için bu yol
engellenmiştir. Yazar kimliği bulunmadığından Version VI test skoru da ürün/sınav
doğruluğu olarak raporlanmaz. 2026-07-23 tarihli dik-eksenli ve ürün ön işlemesiyle
eşleşen Colab koşusunda ham casefold doğruluğu %97,2321; güven ≥0,9374898 olan
5.380/5.600 örnekte doğruluk %99,0149 ve kapsama %96,0714 ölçülmüştür. **Uyarı:**
bu bölme yazar-ayrık DEĞİLDİR (`karakter_metrikleri.json` → `writer_disjoint:
false`); aynı yazarın örnekleri eğitim ve test kümelerine birlikte düştüğü için
rakamlar iyimserdir ve gerçek sınav doğruluğu olarak okunmamalıdır. Kalan
örnekler otomatik puanlanmaz, insan incelemesine gider.

Kendi gerçek kâğıtlarınızı eğitim izni ve anonim yazar koduyla işleyin:

```bash
sinav-okur webapp
# Kâğıt yükle ekranında eğitim iznini ve anonim yazar kodunu işaretleyin.
sinav-okur disaaktar -o gercek_satir/labels.jsonl
```

### macOS masaüstü uygulaması

Logolu, çift tıklanabilir uygulamayı kurmak veya yenilemek için:

```bash
uv run python scripts/install_macos_app.py --replace
```

Gerçek uygulama `~/Applications/Sınav Okur.app` altında tutulur; Masaüstündeki
`Sınav Okur.app` buna güvenli bir sembolik bağlantıdır. Uygulama sunucuyu
başlatır, hazır olmasını bekler ve varsayılan tarayıcıda sınav panelini açar.
Başlatma günlükleri `~/Library/Logs/SinavOkur/` altında tutulur.

### Her türlü yazılıyı yükleyip tanıma

Ana paneldeki **Yazılıyı tanıt** düğmesi temiz okul yazılılarını doğrudan alır.
Tek PDF veya en fazla dört ayrı ön–arka fotoğraf yüklenir; yerel OCR motorları
soru numaralarını, puanları, tek/çift sütunları
ve cevap bölgelerini çıkarır. Algılanan mavi bölgeler sürüklenip yeniden
boyutlandırılabilir; öğretmen OCR metnini ve cevap anahtarını doğrular.
PDF, PNG, JPG, TIFF, BMP, WEBP ve iPhone HEIC/HEIF fotoğrafları desteklenir;
HEIC/HEIF dönüşümü macOS üzerinde yerel yapılır.

Doldurulmuş öğrenci kâğıdı yüklenince basılı ana sayfaya ORB+RANSAC homografiyle
hizalanır ve ana sayfada olmayan koyu pikseller el yazısı olarak ayrılır. Böylece
basılı metin, tablo ve şekiller cevap sanılmaz. Serbest düzenli yazılıların
ilk otomatik sonuçları güvenlik için öğretmen incelemesine gönderilir.
Ayrı cevap kâğıdı kullanılan, sınavla aynı basılı düzeni taşımayan belgelerde
cevap bölgeleri öğretmen tarafından önizlemede elle tanımlanmalıdır.

### Çok sayfalı öğrenci ve toplu sınıf yükleme

**Kâğıt yükle** ekranında iki çalışma biçimi vardır:

- **Tek öğrenci · çok sayfa:** 1–4 PDF/fotoğraf aynı öğrencinin ön–arka
  sayfalarıdır. Sayfa sırası karışırsa basılı görsel dokuya göre otomatik eşlenir.
  Bir soru sayfa sonunda başlayıp arka yüzde devam ediyorsa cevap bölgeleri
  birleştirilir ve soru yalnız bir kez puanlanır.
- **Tüm sınıfı toplu oku:** her PDF ayrı öğrenci sayılır. Bir öğrencinin ayrı
  fotoğrafları `123_Ayse_Yilmaz__1.jpg`, `123_Ayse_Yilmaz__2.jpg` biçiminde
  adlandırılır; `__` öncesi aynı olan dosyalar tek öğrenci altında doğal sayfa
sırasıyla birleştirilir.

Tek toplu işlemde 200 dosyaya kadar seçim yapılabilir. Her öğrenci ayrı
değerlendirme kaydı olur; bir kâğıttaki hata diğer öğrencilerin işlenmesini
durdurmaz ve işlem sonunda başarı/hata özeti gösterilir.

Kâğıdın üst bilgisindeki **ad, soyad, öğrenci numarası, sınıf ve şube** iki OCR
görüşüyle çıkarılır; okul, tarih, ders, grup ve kitapçık gibi bulunan ek alanlar
da kayıtla tutulur. Kimlik OCR'ı puanı etkilemez. Görüşler uyuşmazsa alan kesin
bilgi gibi kaydedilmez; kâğıt ekranında güven yüzdesi ve öğretmen doğrulama alanı
gösterilir.

Rubrik motoru tam anahtar kelime aramakla sınırlı değildir. Öğrenci nihai sonucu
yanlış yazsa bile doğru denklem, deney adımı, bilimsel gerekçe veya yeterli
kavram kapsamı varsa kalem puanının sınırlı bir bölümünü verir ve kararı
incelemeye ayırır. Açık olumlu/olumsuz çelişkiler benzer sözcükler taşısa da
puanlanmaz.

`disaaktar`, adı/öğrenci numarasını yazmaz; yalnız izinli, düzeltilmiş ve anonim
`writer_id` taşıyan kayıtları çıkarır. Veri kaynaklarının ayrıntılı erişim/lisans
durumu `docs/veri_envanteri.md` içindedir. Hugging Face adaptörü eğitim amacında
gerçeklik ve açık eğitim izni doğrulanmayan setleri reddeder.

Dışarıdan izinli ve satır transkripsiyonlu bir paket geldiğinde önce doğrulayın:

```bash
uv run sinav-okur satirpaketi gelen/labels.jsonl \
  -o gercek_satir_verisi \
  --lisans "Yazılı akademik model eğitimi izni" \
  --izin-belgesi gelen/IZIN.pdf \
  --kaynak-url "https://ornek.edu/veri"
```

Bu kapı `image`, `text`, anonim `writer_id` ve varsa resmî `split` alanlarını
doğrular; bir yazarın train/test arasında sızmasını reddeder ve denetlenebilir
`manifest.json` üretir. Hazır erişim yazıları ve teslim şeması
[`docs/veri_erisim_talepleri.md`](docs/veri_erisim_talepleri.md) içindedir.

## Türkçe'ye özgü kararlar

- **Fontlar cmap ile doğrulanır** — popüler el yazısı fontlarının çoğu ğ/İ/ş'yi sessizce
  atlar; `fontlar` komutu ve `veri_uret` yalnızca tüm Türkçe karakterleri içeren fontları
  kullanır.
- **ı/İ büyük-küçük dönüşümü** ve **NFC normalizasyonu** eşleştirmeden önce uygulanır.
- **Aksan toleransı:** OCR aksanı kaçırırsa (hucre↔hücre) küçük cezayla yine eşleşir.

## Testler

```bash
uv run pytest
```

Entegrasyon testleri (`test_entegrasyon.py`) serbest akışı uçtan uca sınar: örnek
sınav tanımından basılı bir ana sayfa üretilir, üzerine "el yazısı" cevaplar çizilmiş
öğrenci kâğıdı hazırlanır ve `serbest_kagit_isle` ile hizalama → kutu eşleştirme →
puanlama → Excel dökümü zinciri işletilir. OCR'ı deterministik kılmak için sahte
tanıyıcı (`YapayTaniyici`) kullanılır; böylece test motor kurulumundan bağımsız çalışır
ve dolu/boş ayrımı, düşük güvende incelemeye düşme, sayfa uyuşmazlığı gibi kenar
durumlar doğrulanır. Ortak kurgu araçları `tests/conftest.py` altındaki fixture'larda
(`ornek_sinav`, `basili_sayfa`, `serbest_ortam`) toplanır; ağır bağımlılıklar
`pytest.importorskip` ile atlanır.

## Türkçe altı motorlu OCR

Hazır sınav içe aktarma akışı Apple Vision, Tesseract Türkçe, EasyOCR,
PaddleOCR PP-OCRv5, Surya OCR ve Microsoft TrOCR sonuçlarını satır düzeyinde
uzlaştırabilir. İlk beş motorun bağımlılıkları ana uygulama ortamından ayrıdır:

```bash
zsh scripts/ocr_kur.sh all
```

TrOCR ana ortamın `htr` eklentisiyle çalışır (`pip install 'sinav-okur[htr]'`).
Kendi satır algılayıcısı olmadığından öncü motorun (Vision) satır kutularını
yeniden okuyup topluluk oylamasına el yazısı uzmanı olarak katılır. İnce
ayarlı Türkçe model iki yoldan bulunur: `SINAV_OKUR_TROCR_MODEL` ortam
değişkeni ya da proje kökündeki `modeller/trocr-tr/` dizini. Türkçe yerel model
yoksa motor merkezi TrOCR'ı hazır saymaz.

Colab defteri `colab/08_trocr_tek_gecis.ipynb` veriyi üretip modeli tek geçişte
eğitir (paket kaynağı defterin içine gömülüdür; GitHub klonu gerekmez). İnen
zip tek komutla yerine oturur:

```bash
sinav-okur model-kur ~/Downloads/trocr-tr.zip
```

Arayüzde üç profil vardır: **Akıllı kademeli** yalnız gerektiğinde ağır
motorları (TrOCR dâhil) açar; **Tam motor denetimi** her kurulu motoru
çalıştırır; **Hızlı** yalnız Apple Vision kullanır. Surya belge/yerleşim OCR
motorudur ve el yazısı için uzmanlaşmış değildir; öğrenci cevapları uygulamanın
HTR modelleriyle okunmaya devam eder.

## Yerel kitap RAG ve BioProf

**Biyoloji kitapları** ekranına metin katmanlı PDF, TXT veya Markdown kaynaklar
yüklenebilir. Uygulama bunları Mac üzerinde kalıcı bir pasaj indeksine dönüştürür.
Hazır sınav incelemesindeki **Kitaplardan kaynaklı anahtar oluştur** işlemi,
düzeltilmiş her sorunun yerel pasajlarını ayrı ayrı getirir. Claude API anahtarı
tanımlıysa model yalnız bu RAG kanıtlarıyla sınırlandırılarak kısa örnek cevap, birbirini
tekrarlamayan atomik rubrik maddeleri ve kabul edilecek eşdeğer ifadeler üretir.
Kitap/pasaj kaynakları nihai sınav YAML/DB kaydında cevap anahtarıyla birlikte
saklanır.

Claude API veya yerel model kullanılamazsa yerel pasajlardan bir taslak yine
gösterilir; fakat öğretmen doğrulayana kadar o sorunun otomatik puanlaması
kapatılır. Kaynaklarda yeterli kanıt yoksa ya da fotoğrafta soru metni kesilmişse
sistem cevap/puan uydurmaz ve soruyu insan incelemesine bırakır. Claude API'de
geçici aşırı yük veya istek sınırı olduğunda yedek model denenir.

Mevcut bir sınavda **RAG anahtarını yenile ve puanla** işlemi kaynaklı anahtarı
yeniden üretir ve daha önce tanınmış veya öğretmence düzeltilmiş tüm cevapları
güncel rubriğe göre tekrar puanlar. Tek bir cevabın metni düzeltildiğinde
**Düzelt ve otomatik puanla** aynı işlemi yalnız o cevap için yapar.

Kitap bilgisini fine-tuning ile ezberletmek yerine RAG kullanılır: kaynak
değiştiğinde yeniden model eğitmek gerekmez, cevapla birlikte dayanak
gösterilebilir. Fine-tuning yalnız modelin yazım/çıktı davranışını özelleştirmek
için ayrı ve izinli bir çalışma olarak değerlendirilmelidir.

## Claude API ile cevap anahtarı

Hazır sınav inceleme ekranındaki **Yapay zekâ ile cevapları oluştur** düğmesi,
algılanan ve öğretmenin düzelttiği soru metinlerini doğrudan Anthropic Claude
API'sine (`api.anthropic.com`) gönderir; araya vekil sunucu girmez. Giden yük
yalnız ders adı, soru metni ve puanı ile (kaynaklı üretimde) kitap pasajlarından
oluşur; öğrenci kâğıdı, cevabı veya kimliği için alan yoktur.

**Anahtar.** Sırasıyla `ANTHROPIC_API_KEY` ortam değişkeni, yoksa
`~/Library/Application Support/SinavOkur/claude-api.key` dosyası (`0600`)
okunur. Dosyayı kurmak için (kaynak varsayılan `~/.config/claude-api/key`):

```bash
uv run python scripts/claude_api_bagla.py            # kur / doğrula
uv run python scripts/claude_api_bagla.py --canli    # + token harcamayan canlı sınama
```

Betik anahtarı hiçbir zaman yazdırmaz; yalnız "kuruldu" ya da "doğrulandı" der.
Hedefte farklı bir anahtar varsa `--degistir` gerekir. Eski `cli-proxy.key`
dosyası artık kullanılmaz.

**Model.** Varsayılan `claude-opus-5-5` (`effort: high`), yedek
`claude-sonnet-5-5`. Aşırı yük (529), istek sınırı (429, kısa `Retry-After`
beklenir), sunucu hatası, zaman aşımı, bulunamayan model ve güvenlik filtresi
reddinde yedeğe geçilir; kimlik, izin ve kredi hatalarında geçilmez (aynı
hesap, aynı sonuç). Çıktı JSON şemasıyla alınır; yanıt uzunluk sınırında
kesilirse ya da üç soruluk bir grup güvenlik filtresine takılırsa sorular tek
tek yeniden istenir ve hata, takılan sorunun numarasını söyler.

| Ortam değişkeni | Anlamı |
|---|---|
| `SINAV_OKUR_CLAUDE_API_MODEL` | birincil model |
| `SINAV_OKUR_CLAUDE_API_FALLBACK_MODELS` | virgülle ayrılmış yedek modeller (boş = yedek yok) |
| `SINAV_OKUR_CLAUDE_API_EFFORT` | `low` / `medium` / `high` / `xhigh` / `max` (varsayılan `high`) |
| `SINAV_OKUR_CLAUDE_API_KEY_FILE` | anahtar dosyasının yolu |

Hata iletileri Türkçedir (geçersiz anahtar, kredi bitmesi, istek sınırı, aşırı
yük, filtre reddi…) ve üst akışın ham gövdesini taşımaz; ayrıntı yalnız sunucu
günlüğüne (`~/Library/Logs/SinavOkur/server.log`) yazılır.

Üretilen örnek cevap ve rubrik maddeleri öneridir. Eksik OCR sorularında model
uyarı verir; öğretmen onayı olmadan cevap anahtarı kesinleştirilmez.

## Öğretmen Çantası entegrasyonu (yerel API v1)

Öğretmen Çantası uygulaması sınav tanımlarını Sınav Okur'a gönderip onaylı
sonuçları geri alabilir. Dört uç vardır (tümü Bearer token ister):

- `GET /api/v1/health` ve `GET /api/v1/capabilities` — durum ve yetenek bildirimi.
- `POST /api/v1/exams/import` — `manifest.json` içeren sınav paketi (zip, en çok
  100 MiB; manifest açılmış hâliyle en çok 10 MiB). İçe aktarılan sorular
  `otomatik_puanlama=False` ve taslak anahtarla gelir; öğretmen onayı olmadan
  hiçbir soru otomatik puanlanmaz. Aynı `external_id` ile yeniden gönderim,
  sınavın okunmuş kâğıdı yoksa güncelleme sayılır; okunmuş kâğıt varsa `409` ile
  reddedilir (sessiz üzerine yazma yok).
- `GET /api/v1/exams/{kimlik}/results` — yalnız onaylanmış kâğıtların puanlarını
  zip manifesti olarak döker.

Token `~/Library/Application Support/OgretmenCantasi/entegrasyonlar/yerel-api.token`
dosyasından okunur (`OGRETMEN_API_TOKEN_YOLU` ile değiştirilebilir); dosya yoksa
tüm istekler `401` alır (kapalı-varsayılan).

## Lisans

MIT. Kullanılan modeller kendi lisanslarına tabidir (TrOCR: MIT, Qwen2.5-VL-7B ve
emrecan gömme modeli: Apache-2.0). Qwen2.5-VL **3B** sürümü ticari değildir; 7B kullanın.
Tesseract/EasyOCR/PaddleOCR bağımsız motorlarının ve modellerinin kendi lisansları
geçerlidir. Surya kodu GPL, Surya ağırlıkları ise değiştirilmiş OpenRAIL lisanslıdır;
ticari dağıtımdan önce güncel lisans koşulları ayrıca doğrulanmalıdır.
Siyah kurşun kalem güvenilirlik mimarisi, çoklu HTR uzlaşması, güven
kalibrasyonu ve seçici otomatik karar ayrıntıları:
[`docs/ml_dl_guvenilirlik.md`](docs/ml_dl_guvenilirlik.md).
