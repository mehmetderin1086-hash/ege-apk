# Soru Kesici

Herhangi bir yayının çoktan seçmeli test sayfalarını (**PDF / JPG / PNG**)
soru soru kırpıp her soruyu ayrı bir PNG olarak bir `Arşiv.zip` dosyasına
koyar. Grafikli/şekilli sorularda kırpma koordinatları, sorunun figürü
kesilmeyecek ve komşu soru/ayraç yazısı girmeyecek biçimde ayarlanır.

Program yükleme sırasında dosyayı **ön izler ve kendini kalibre eder**:
metin katmanı var mı yoksa taranmış mı, kaç sütun, numara biçimi nasıl,
belge çoktan seçmeli mi otomatik tespit edilir. Böylece **yayınevi, sayfa
düzeni veya soru biçimi değişse de** sorular doğru kesilir.

## Kurulum

macOS'ta ek program (poppler/tesseract) gerekmez; taranmış sayfalar için
Apple'ın yerleşik **Vision** OCR'ı kullanılır.

```bash
cd ~/Documents/soru-kesici
python3 -m venv .venv
.venv/bin/pip install pymupdf pillow pyobjc-framework-Vision pyobjc-framework-Quartz
.venv/bin/pip install python-docx     # yalnız Word (.docx) dışa aktarma için
```

(Bu ortam zaten kuruludur; yukarısı sıfırdan kurulum içindir. `python-docx`
kurulu değilse Word dışında her şey çalışır; Word butonu nazik hata verir.)

## Kullanım

```bash
cd ~/Documents/soru-kesici

# PDF → yanına Arşiv.zip
.venv/bin/python soru_kes.py test.pdf

# TEST bölümlerini ve soru aralıklarını LİSTELE (neyi seçebileceğini gör)
.venv/bin/python soru_kes.py test.pdf --liste

# SEÇİMLİ KESİM: yalnız istenen testlerin istenen sorularını kes
#   "5. testin 2-10, 3. testin 10-15. soruları" →
.venv/bin/python soru_kes.py test.pdf --sec "test 5: 2-10; test 3: 10-15"
#   tüm test: "t5" · tek soru: "t5:7" · sayfa: "s12:3-5" · çıktı sırası: "27-40"
#   yinelenen test adı (Palme ünite-başı 'TEST 1'): --liste'deki #sıra ile
#   daralt → "t1#3: 1-4"

# SINAV KAĞIDI: seçilen sorulardan yazdırılabilir A4 PDF de üret
.venv/bin/python soru_kes.py test.pdf --sec "t5; t3" \
    --sinav-pdf ~/Desktop/deneme.pdf --baslik "11. Sınıf Biyoloji" \
    --kurum "Atatürk Anadolu Lisesi" --puan 100

# KİTAPÇIK (A/B/C/D): soru sırası karıştırılmış + her birine cevap anahtarı
.venv/bin/python soru_kes.py test.pdf --sinav-pdf ~/Desktop/sinav.pdf \
    --kitapcik 4 --tohum 7          # → sinav_A.pdf … sinav_D.pdf

# RASTGELE: her testten dengeli N soru örnekle (havuzdan seçim)
.venv/bin/python soru_kes.py test.pdf --rastgele 5 --tohum 1

# DIŞA AKTAR: soruları CSV / HTML / Markdown olarak kaydet
#   + otomatik konu etiketleme (konular.csv'yi kendi dersinize göre düzenleyin)
.venv/bin/python soru_kes.py test.pdf --disa csv,html --konu-csv konular.csv

# WORD / METİN-PDF: OCR ile editlenebilir belge — ŞEKİLSİZ soru düzenlenebilir
#   metin olur, ŞEKİLLİ/grafikli soruda şekil GÖRÜNTÜ olarak korunur, metni
#   editlenebilir yazılır (Word için python-docx gerekir)
.venv/bin/python soru_kes.py test.pdf --disa docx,pdf-metin

# Önce ön izle: tespit edilen soru kutularını görsel dene (kesmeden)
.venv/bin/python soru_kes.py test.pdf --onizleme

# Çıktı yerini seç / açık PNG klasörü de üret
.venv/bin/python soru_kes.py test.pdf -o ~/Desktop/Arşiv.zip --klasor

# Ekran görüntüsü / taranmış sayfalar (birden çok sayfa sırayla)
.venv/bin/python soru_kes.py sayfa1.png sayfa2.jpg -o Arşiv.zip

# Çözünürlük (varsayılan 300 DPI)
.venv/bin/python soru_kes.py test.pdf --dpi 220

# TOPLU: her PDF'i ayrı arşive işle (<girdi>_Arşiv.zip); -o çıktı klasörü olur
.venv/bin/python soru_kes.py a.pdf b.pdf c.pdf --coklu -o ~/Desktop/ciktilar

# Sütun/sayfa sonunda bölünen soruları birleştirme kapat (varsayılan açık)
.venv/bin/python soru_kes.py test.pdf --birlestirme kapali

# Taranmış PDF OCR'ını seri çalıştır (paralel sorun çıkarırsa)
.venv/bin/python soru_kes.py test.pdf --ocr-paralel 1
```

### Grafik / web arayüzü

```bash
.venv/bin/python soru_kes_web.py      # tarayıcıda açılır (önerilen)
open SoruKesici.command               # aynı web arayüzü (çift tıklanabilir)
.venv-gui/bin/python soru_kes_gui.py  # isteğe bağlı yerel Tk arayüzü
```

> **Not (macOS):** Sistem Tcl/Tk'si (8.5) modern macOS'ta pencereyi boş çizer.
> Bu nedenle çift tıklanabilir `SoruKesici.command` ve masaüstündeki
> **Soru Kesici.app** doğrudan web arayüzünü açar. Yerel Tk arayüzünü ayrıca
> kullanmak isterseniz Tk 8.6+ içeren `.venv-gui` ortamını çalıştırın.

Web arayüzü en zengin olandır (banka görünümü + panel); yerel Tk arayüzü
kesim tarafında web ile eşdeğerdir ve tarayıcısız çalışır. Web'de üstteki
anahtardan **üç görünüm** vardır:
**✂️ Kesim** (dosya yükle → soru kes), **🗂 Soru Bankası** (biriken soruları
gözat, filtrele, sınav üret) ve **📊 Panel** (analitik gösterge paneli). Sağ
üstteki 🌙/☀️ düğmesiyle **açık/koyu tema** değiştirilir (tercih tarayıcıda
saklanır; ilk açılışta sistem temasını izler). URL kısayolu: `/#panel`,
`/#banka`, `/#panel,light` doğrudan o görünümü/temayı açar. Kesim görünümünde
dosyaları **sürükleyip bırakabilir** ya da "Dosya Seç"le açabilir; iki çalışma
modu (Düzenle / Seç) kullanabilirsiniz:

- **✏️ Düzenle**: kutuları **elle düzeltme** — tıklayıp taşıma, köşeden
  boyutlandırma, silme (Delete), yeni kutu çizme ("Kutu Ekle") ve seçili
  kutuları birleştirme ("Birleştir"). Değişiklikler otomatik kaydedilir.
- **☑️ Seç**: soruları **toplu seçme** — kutulara tıklayarak (etikette
  `T5 S12` = test 5, soru 12), aralık yazarak (`test 5: 2-10; t3: 10-15`) ya da
  **konu/kelime araması** yaparak ("fotosentez", "nöron" → eşleşen sorular
  seçilir). Seçili sorulara **etiket** (konu/kazanım) atanabilir. Yan panelde
  testler listelenir; test kutucuğuyla o testin tümü seçilir.

**📄 Sınav Kağıdı**: kurum adı, başlık, ad/sınıf/tarih alanları, toplam puan,
1'den yeniden numaralama, **A/B/C/D kitapçık** (soru sırası karıştırılmış,
kopya önleme) ve **her testten rastgele N soru** seçenekleriyle A4 PDF üretir.
**➕ Soru Bankasına Aktar**: kesilen soruları kalıcı bankaya ekler (numara +
otomatik konu ile gruplu; içerik-hash ile tekilleştirilir — aynı soru iki kez
girmez). "Kesince bankaya da ekle" onay kutusuyla kes-ve-aktar tek adımda.
**📦 Dışa Aktar**: soruları CSV / HTML (görüntü gömülü) / Markdown, ya da OCR ile
**Word (.docx) / metin-PDF** olarak kaydeder (şekilsiz soru editlenebilir metin,
şekilli soru şekil korunur). **🕘 Geçmiş**: eski çıktıları listeler. Kısayollar:
←/→ sayfa, `D`/`S` mod, Seç modunda `A` tümü/temizle, Delete kutu sil, Cmd+Enter kes.

#### 🖥 Masaüstü (Tkinter) arayüzü

Web arayüzünün çevrimdışı masaüstü karşılığı; aynı çekirdek API'yi kullanır
(`kirpma_seti`, `test_ozeti`, `kalite_kapisi` — çekirdeğe dokunmaz):

- **Etkileşimli kutu editörü**: taşıma, köşe tutamacıyla boyutlandırma, yeni
  kutu çizme (✏️), silme (⌫), birleştirme, sayfayı sıfırlama; belge-genel
  **geri al / yinele** (⌘Z / ⇧⌘Z, başka sayfadaki değişikliğe atlar), zoom
  (⌘± / ⌘0 / Sığdır / Cmd+scroll — imleç altı sabit kalır) ve pan
  (space+sürükle ya da orta tuş). Kutular çekirdek inceleme diliyle renklenir:
  yeşil=otomatik, turuncu=incele, kırmızı=reddedildi; büyük sayfalarda yalnız
  görünür bölge render edilir (300 DPI + 4x zoom akıcıdır).
- **Test/soru ağacı** (sol panel): test düğümleri altında sorular (cevap ve
  sayfa sütunlarıyla). Tıkla-seç, aralık ifadesi (`test 5: 2-10; t3: 10-15`)
  ve Türkçe-normalize **kelime araması**; tek soruya tıklanınca editör o
  sayfaya atlayıp kutuyu seçer. Seçim kesime aynen yansır ("Kes (N seçili)").
- Sağ panelde **seçili sorunun kırpma önizlemesi** canlı gösterilir.
- **Araçlar**: Sınav PDF'i (kitapçık A/B/…, her testten rastgele N, tohum),
  soru bankasına aktarma (içerik-hash tekilleştirme), CSV / Markdown / HTML /
  Word / metin-PDF dışa aktarma ve **Toplu İşlem** (çok dosya → her biri kendi
  Arşiv.zip'ine, hatalı dosya atlanıp raporlanır).
- **Katı kalite kapısı** (`strict`) seçiliyse inceleme bekleyen sayfalar risk
  nedenleri + bindirme görseliyle diyalogda onaylanır ("sayfa doğru" /
  "soru yok"); elle düzeltilen sayfa kapıdan otomatik geçer ve engellenen
  eylem kararlardan sonra kendiliğinden yeniden denenir.
- Tüm ağır işler tek worker thread'inde sıraya girer (arayüz donmaz) ve
  **Durdur** ile iptal edilebilir.

#### Otomatik Kalibrasyon V2.2

- Belge profili kapak, konu, soru, çözüm, cevap anahtarı ve karma sayfaları
  ayırır; sütun aileleri ile tekrarlanan üst/altbilgileri belge hash'iyle
  önbelleğe alır.
- Sütun kararı artık tek projeksiyona bağlı değildir: altı farklı ölçek/eşik,
  üst-orta-alt sayfa bölgeleri, OCR soru-numarası hizaları ve isteğe bağlı
  DocLayout-YOLO aynı sınırlar üzerinde oy verir. Eski sınır ancak destekliyse
  korunur; kenar numara şeridi bağımsız soru sütunu sayılamaz.
- Taranmış sayfalarda küçük eğiklik ölçülür. Belirsiz DocLayout sayfası önce
  global, sonra iki örtüşen yüksek çözünürlüklü yerel parçada analiz edilir;
  kesin sayfalarda ikinci geçiş çalışmaz. Arayüz ortalama/en düşük sütun
  güvenini, düşük güvenli, geçişli ve eğik sayfa sayılarını gösterir.
- Adaylar soru türü, sayfa rolü, güven, kanıt ve uyarı taşır. `≥0,82`
  **Otomatik**, `0,55–0,82` **İncele**, daha düşük sonuçlar **Reddedildi** olur.
- PDF ile PNG/JPG/TIFF/BMP/WebP/GIF; metin katmanlı, taranmış, tek/çok sütunlu,
  açık uçlu, kısa cevaplı, doğru-yanlış, eşleştirme ve çoktan seçmeli düzenler
  aynı kalite kapısından geçer. Ortak metin/şekil ilgili her soruya eklenir.
- İnceleme veya ret durumundaki aday kullanıcı onayı/düzeltmesi olmadan bankaya
  girmez. Gemini Vision varsayılan kapalıdır ve açılırsa yalnız düşük güvenli
  sayfalarda yerel kanıtla doğrulanmış yedek olarak çalışır.
- Banka V4 göçü mevcut kayıtları koruyup önce yedek alır. Yeniden işleme
  karşılaştırması ayrı sahne tablosundadır; kullanıcı onaylamadan eski kayıtlar
  değiştirilmez.

### 🗂 Soru Bankası görünümü

Kesilip **bankaya aktarılan** tüm sorular (tüm PDF'leriniz arası) tek bir yerel
kütüphanede birikir (`~/Library/Application Support/soru-kesici/banka/`, SQLite).

- **Filtreleme**: konu, kaynak dosya, doğru cevap (A–E), **zorluk**
  (kolay/orta/zor), cevaplı/cevapsız, **etiket** (`konu=zor`) ve **tam-metin
  arama** (Türkçe-güvenli). Sonuçlar küçük-resim ızgarasında, sayfalı. Her kartta
  **zorluk rozeti** görünür; karta **çift tıklayınca** tam-boy önizleme (lightbox)
  açılır. **Konuya göre grupla** ile sorular konu başlıkları altında toplanır.
- **🤖 AI ile konu/başlık belirle**: Google **Gemini** ile her sorunun konusu
  (konular.csv listesinden), kısa **başlığı** ve **zorluğu** (kolay/orta/zor)
  otomatik belirlenir; kaba kelime-eşleştirme etiketleri düzeltilir. Kapsam:
  filtredekiler / sepettekiler / tüm banka. Anahtar **⚙ AI Anahtarı** alanından
  girilir (`~/.soru_kesici.json` ya da `GEMINI_API_KEY` ortam değişkeni; repo
  dışı, commit edilmez). Anahtar yoksa/hata olursa kelime-eşleştirme yedeği
  çalışmaya devam eder.
- **Bankadan sınav**: sorulari **sınav sepetine** ekleyin (tek tek, "sayfadakileri
  ekle" ya da "filtreden N rastgele"), sırala, sonra kurum/başlık/kitapçık/cevap
  anahtarı ayarlarıyla **PDF** ya da **Word** sınav üretin. Belgeler arası soru
  karıştırma serbesttir — bir konudan farklı kitaplardan sorularla sınav kurun.

Aynı yetenekler CLI'dan da: `--disa docx,pdf-metin` (kesim yanına yazar).

### 📊 Panel (analitik gösterge paneli)

Bankanın anlık durumunu tek ekranda özetler (bağımsız, harici kütüphane yok —
tüm grafikler satır-içi, offline). **Özet kutuları**: toplam soru, konu sayısı,
kaynak sayısı, cevaplı %, AI-etiketli %. **Grafikler** (yatay bar): konu dağılımı
(ilk 10), **zorluk** (kolay/orta/zor + etiketsiz), doğru cevap (A–E), kaynağa göre
(ilk 8). Bir bara **tıklayınca** o değerle filtrelenmiş Soru Bankası açılır.
Altta **son aktivite** (kesim/aktarım/sınav geçmişi). Renkler erişilebilir
paletten seçilmiştir ve açık/koyu temaya uyum sağlar.

### İndirme

Kesim/sınav/dışa-aktarma çıktıları **doğrudan tarayıcının İndirilenler**
klasörüne iner (yerleşik "kaydet" penceresi kullanılmaz — pencerenin arkada
kalıp akışı durdurması sorunu böylece ortadan kalkar). Kitapçık gibi çok dosyalı
çıktılar tek zip olarak indirilir. Bir kopya `~/Library/Application Support/
soru-kesici/ciktilar/` altında geçmiş/Finder için tutulur (son 60 dosya).

Çalıştırınca bir satırlık **tespit özeti** yazılır, örn:
`Tespit: 4 sayfa · 2 sütun · metin katmanı · çoktan seçmeli`.
Kutuların doğruluğundan emin olmak için önce `--onizleme` ile bakın;
`<çıktı>_onizleme/` klasöründe her sayfada kutular kırmızı çizilir.

Zip içeriği: test tespit edilirse `test05_soru02.png` (yoksa `soru_027.png`),
artı her sorunun test/soru numarası, kaynak sayfası, gövde+şık metni, (varsa)
cevabı ve konu/etiketlerini taşıyan `sorular.json`.

### Konu etiketleme sözlüğü (`konular.csv`)

Otomatik konu/kazanım etiketlemesi proje kökündeki `konular.csv` ile yapılır.
Biçim: her satır `Konu Adı;anahtar kelime 1,anahtar kelime 2,…`. Kendi
dersinize/müfredatınıza göre serbestçe düzenleyin (Türkçe büyük/küçük harf ve
ç/ğ/ı/ö/ş/ü farkı gözetilmez). Web'de `--konu-csv` gerekmez, kök dosya
otomatik okunur; CLI'da `--konu-csv konular.csv` ile açılır.

## Nasıl çalışıyor? (görsel layout analizi + otomatik kalibrasyon)

1. **Sayfa kaynağı**: Metin katmanlı PDF sayfaları koordinatlardan okunur ve
   ~300 DPI vektörden yeniden render edilir (en yüksek kalite). Taranmış PDF
   sayfaları ve JPG/PNG'ler render edilip Apple **Vision OCR** ile okunur.
2. **Çok-yöntemli görsel sütun tespiti**: Sayfanın **dikey mürekkep
   projeksiyonu** (metin sayfasında bbox'lardan, taranmışta pikselden) altı
   ölçek/eşikte ve üst/orta/alt bölgelerde ayrı hesaplanır. Beyaz seam'ler,
   OCR numara hizaları ve varsa DocLayout-YOLO bölgeleri güven ağırlıklı
   uzlaşmada birleşir. Yöntem farkı güven puanını düşürür; uzlaşma güveni
   `0,70` altındaysa sonuç incelemeye iner, yüksek güvenli uzlaşma ise yalnız
   izlenebilir bir uyarı taşır. Her kutu ait olduğu sütuna **hard-clamp**
   edilir → sol+sağ sütun birleşmesi fiziksel olarak engellenir. Yan yana iki
   soru aynı yatay hizada olsa bile birleşmez; başka sütuna geçiş yalnız V3.4
   tarafından sayfanın o y-aralığında doğrulanmış gerçek tam-genişlik bölgesi
   varsa açılır.
3. **Format tespiti**: Belge (ve her sayfa) otomatik olarak
   çoktan-seçmeli / açık-uçlu / çözümlü / konu-anlatımı olarak sınıflanır.
   Doğrulama kuralı formata göre seçilir — bir blok gerçek soru sayılır ancak
   **şık (A–E)** VEYA **soru gövdesi** (…mıdır/hangisi/yazınız) VEYA **yazma
   alanı** (noktalı satır / "a. b." alt madde) içeriyorsa. Böylece talimatlar,
   konu maddeleri ("1. Duyu Nöronu:"), **künye/telif ve İÇİNDEKİLER** sayfaları
   ("… Başlık ……… 21" lider satırları) ve minik/boş parçalar elenir; açık uçlu
   ve çözümlü sorular da doğru kesilir. Şekillerdeki küçük `(a) (b) (c)` panel
   etiketleri seçenek sayılmaz; gerçek `a)` / `10. a.` seçenekleri korunur.
   Numara çapası olmayan (görsel blokla
   kurtarılan) bloklar daha katı doğrulanır (tek "A)" satırı gibi parça sayılmaz).
4. **Numara zinciri + sınır**: Her sayfa bağımsız; numara kaçtan başlarsa
   başlasın en uzun **artan zincir** seçilir. Dikey aralık bir sonraki soruya
   kadar; yatay aralık görsel sütun bandına kısıtlanır. Metin sayfalarında
   gömülü resimler bölgeye eklenir (şekil garantisi); taranmışta sütunun
   tamamı alınıp fazla beyaz traşlanır. Numara önündeki tek gürültü jetonu
   ("büyüteç ikonu → 0 3.") toleranslıdır.
5. **Kutusuz sütun kurtarma**: Bir sütunun numaralarını OCR kaçırırsa (ya da o
   sütundaki numaralar aslında konu-listesi maddesiyse), numara zinciri o
   sütunu boş bırakır. O sütunda gerçek çoktan seçmeli kanıt (≥3 şık) veya
   açık uçlu içerik varsa, sütun **görsel büyük-boşluk blok segmentasyonuyla**
   kurtarılır. Şıksız yan bilgi paneli / İÇİNDEKİLER / kapak kurtarmaya girmez.
6. Yüksek örtüşen kutular teke indirilir (tekrarlı kırpma olmaz).
7. Beyaz kenar boşlukları traşlanır, eşit beyaz pay eklenir. Sütun/sayfa
   sonunda birleştirilen devam ve çözüm parçaları büyütülmeden aynı piksel
   ölçeğinde dikilir; dar parça sırf daha geniş kırpmaya uysun diye esnetilmez.

`numpy` önerilir (görsel projeksiyonu hızlandırır); yoksa Pillow ile çalışır.

## Performans (taranmış PDF'ler)

- **OCR disk önbelleği**: Taranmış sayfaların Vision OCR sonuçları
  `~/Library/Caches/soru-kesici/ocr/` altında (dosya + sayfa + dpi anahtarıyla)
  saklanır. Aynı belgeyi tekrar açtığınızda (ön izle → kes, ya da yeniden
  çalıştırma) OCR atlanır → dakikalarca bekleme kalkar. Önbellek OCR çıktısının
  birebir kopyasıdır; sonuç değişmez. `--ocr-cache-kapat` ile devre dışı.
- **Paralel OCR**: Taranmış sayfalar aynı anda birden çok iş parçacığıyla
  OCR'lanır (`--ocr-paralel N`, varsayılan `min(4, çekirdek)`; `1` = seri).
- Büyük görüntü dosyalarında OCR'a küçültülmüş kopya gider (Vision doğruluğu
  ~200 DPI'da doyar); kırpma yine tam çözünürlükten yapılır.
- **Türkçe OCR onarımı**: OCR çıktısındaki sistematik diakritik ayrışmaları
  (`˘G→Ğ`, `¸S→Ş`, `˙I→İ`, `Ì→İ`) otomatik onarılır; ölçüm için
  `python ocr_kiyas.py <belge.pdf>` (metin katmanlı PDF'i gerçek kabul edip
  Vision'ın CER'ini ve Türkçe karakter doğruluğunu raporlar).

## Çok-motorlu OCR (Türkçe için 5 yerel motor, isteğe bağlı)

Taranmış sayfalarda Apple Vision **birincil** OCR olarak kalır; isteğe bağlı
**akıllı hakemlik** modunda yalnız ŞÜPHELİ satırlarda diğer yerel motorlar
(EasyOCR, RapidOCR/PP-OCR, Tesseract, Surya) devreye girip oy verir.

- **Kurulum**: `.venv-ml/bin/python ocr_kur.py` (temel üçlü: EasyOCR +
  RapidOCR/onnxruntime + Tesseract — brew gerekmez; `--tam` ile Surya). Model
  ve tessdata (tur+eng) `~/Library/Application Support/soru-kesici/ocr-modeller/`
  altına iner; çalışma zamanında ağ erişimi yoktur.
- **Modlar** (web ayar panelinde ya da CLI `--ocr-modu`): **hızlı** (yalnız
  Vision, varsayılan) · **dengeli** (şüpheli satırlarda RapidOCR+Tesseract
  hakemliği) · **tam** (tüm sayfa oylaması, yavaş).
- **Hakemlik muhafazakârdır**: bir hakem kazananı Vision'ı belli bir marjla
  aşmadıkça satır DEĞİŞMEZ (yalnız aday havuzu zenginleşir); numara/çapa
  satırında ≥2 motor aynı numarayı okursa Vision'a karşı bile kazanır. Motor
  yoksa ya da hızlı modda davranış BİREBİR eski Vision-yalnız yoludur.
- **Ölçüm**: `python ocr_kiyas.py <belge.pdf>` artık 5 motoru + `ensemble`
  yolunu karşılaştırır (metin katmanlı PDF gerçek kabul edilir).

## Cevap bandı, elle cevap düzeltme ve çözüm iliştirme

- **Cevap bandı**: cevap anahtarından bulunan cevap, kesilen soru görüntüsünün
  ALTINA "Cevap: X" bandı olarak basılır (web "Cevabı görüntünün altına bas"
  kutusu, CLI `--cevap-bandi`). Bant yalnız ZIP/kes çıktısına uygulanır; banka
  ve sınav PDF'i bantsız kalır (dedup ve sınav gizliliği için).
- **Elle cevap düzeltme**: yanlış eşlenen cevaplar web'de soru rozetinden
  (A/B/C/D/E/∅/otomatik) ya da masaüstünde ağaçtaki cevap hücresine çift
  tıkla düzeltilir; kesime ve dışa aktarmaya yansır.
- **Çözüm iliştirme**: çözümlü kaynaklarda çözüm, aynı numaralı sorunun altına
  iliştirilir (web kutusu / CLI `--cozum-ilistir`); eşleşme belirsizse
  iliştirilmez, uyarılır.

## 🧙 Sınav Sihirbazı (5 adımlı)

Web'deki "Sınav Sihirbazı" sekmesi bankadan çok adımlı, kotalı sınav kurar:
**1** Kapsam (kaynak/konu/tarih/arama + canlı havuz sayacı) → **2** Taslak
(konu×zorluk kota matrisi, hücre başına "stok", "dengeli dağıt", eksik-kota
uyarısı) → **3** Gözden geçirme (kart ızgarası, soru çıkar/yenile) → **4**
Sınav ayarları (başlık/kurum/sütun/kitapçık/puan/numaralama) → **5** Çıktılar
(PDF / Word / optik form + önizleme + şablon kaydet). Tohumla tekrarlanabilir;
şablonlar bankaya kaydedilir.

## ML düzen tespiti (isteğe bağlı, deneysel)

Hibrit (gömülü-görüntü) ve taranmış sayfalarda tespit, DocLayout-YOLO düzen
modeliyle güçlendirilebilir: gömülü-görüntü sezgiseli eşiği geçemediğinde ML
bölgeleri soru numaralarıyla eşlenir; taranmışlarda son metin satırının altına
taşan şekiller (OCR'ın göremediği grafikler) soru kutusuna dahil edilir.

- **Kurulum**: `python3 duzen_kur.py` — torch modern Python istediği için ana
  `.venv`'e dokunmadan ayrı bir `.venv-ml` kurar (Python 3.10+ arar; yoksa
  bağımsız CPython 3.12 indirir ~45 MB). İndirme: torch ~150-300 MB + model
  ~40 MB; disk ~1 GB. Model ve tespit önbelleği `~/Library/` altındadır.
- **Açma/kapama**: web arayüzünde "ML düzen tespiti" kutusu, CLI'da
  `--duzen-model acik|kapali`, ayar dosyasında `duzen_model_aktif`.
- Model/ortam yokken veya kapalıyken davranış BİREBİR eskisi gibidir
  (regresyon nötr); işçi süreç hatasında sessizce sezgisel yola düşülür.
  Günlük: `~/Library/Caches/soru-kesici/duzen/isci.log`.

### Soru-özel model (question_layout_v3, kendi arşivinizden eğitin)

Genel DocLayout modeline ek olarak, kesim doğruluğunu artırmak için 4 sınıflı
(`question_anchor`, `question_body`, `shared_stimulus`, `solution_or_answer`)
soru-özel bir model eğitilebilir. Eğitim tamamen yereldir ve modelin bulduğu
bölgeler tespite yalnız EK OY olarak katılır (tek başına eşik geçiremez;
model yoksa sıfır-etki).

```bash
# 1) Sözde-etiket veri seti (yalnız yüksek-güvenli sayfalar etiketlenir)
.venv/bin/python soru_model_veri.py --korpus "Desktop/Yeni klasör (3)" \
    --cikti ~/Library/Application\ Support/soru-kesici/egitim/ql_v3 --dpi 200
# İsteğe bağlı örnekleme denetimi (kutular çizili kontak sayfaları):
.venv/bin/python soru_model_veri.py --cikti <veri_koku> --denetim 150

# 2) Eğit (.venv-ml, MPS; imgsz 1280, saatler sürebilir)
.venv/bin/python soru_model_egitim.py <veri_koku>/manifest.json --calistir

# 3) Değerlendir + kalite kapısından geçerse üretime al
.venv/bin/python soru_model_egitim.py <veri_koku>/manifest.json \
    --yayinla <cikti>/runs/ql_v3/weights/best.pt
```

Veri hattı belge+yayınevi split izolasyonu uygular (manifest sızıntıyı hata
sayar); kaynak dosya adları manifestte tutulmaz. Yayın kapısı holdout'ta
`question_body` F1 eşiğini geçmeyi ister — geçemezse manifest yazılmaz ve
üretim davranışı değişmez.

### Kalite regresyon koşumu

`kalite_kosusu.py` sabit belge koleksiyonunu (`kalite/koleksiyon.json`) işleyip
her belgeyi önceki anlık görüntüyle karşılaştırır. Soru modeli açık/kapalı ikili
koşum ve golden F1 de raporlanabilir.

```bash
.venv/bin/python kalite_kosusu.py            # tüm koleksiyon
.venv/bin/python kalite_kosusu.py --sert     # sarı bulguları da hata say
.venv/bin/python kalite_kosusu.py --ikili    # model açık vs kapalı
```

**Kapı yalnız anomali sayısına bakmaz.** Anomali bir proxy'dir ve recall kaybını
göremez: gerçek bir vakada bir belgenin kutu sayısı 27→18 düşerken anomali iki
koşumda da 0 kaldı ve kapı yeşil verdi. `_kayma_degerlendir` bu sınıfı kapatır:

| Bulgu | Anlamı | Seviye |
|---|---|---|
| `aday-dusus` | ham numara çapası azaldı → **dedektör** gerilemesi | kırmızı |
| `kutu-dusus` | kutu %5+ ve ≥3 düştü | kırmızı |
| `sayfa-sifirlandi` | bir sayfa tümüyle boşaldı | kırmızı |
| `anomali-tur-artis` | toplam sabit olsa da bir tür arttı | kırmızı |
| `kutu-artis` / `sayfa-kayma` | aşırı bölünme olabilir | sarı |
| `filtre-kaymasi` | aday sabit, reddedilen arttı → precision değişimi | sarı |
| `anlik-gecersiz` | kaynak/örneklem/format/ML değişmiş, kıyas geçersiz | bilgi |

Yanlış alarm üretmemek için önce geçerlilik kapısı çalışır (kaynak SHA-256,
sayfa sayısı, format ve ML durumu aynı değilse hiçbir kayma kuralı uygulanmaz).
`--guncelle` kırmızı bulgu varken snapshot tazelemeyi reddeder (`--zorla` ile
gerekçelendirilerek geçilir) — aksi halde regresyon snapshot tazelenerek
kalıcı olarak gizlenebiliyordu.

Kesim SINIRI kalitesi ayrı bir kolonla (`F1@.75`) ölçülür: IoU 0,5 eşiğinde F1
doygunlaştığı için birkaç yüzdelik traşlama/taşma orada görünmez.

### Sayım-altını (`altin_sayim.py`) — ucuz recall ölçümü

Anomali sayısı bir proxy'dir; **kaçan soruyu görmeyebilir**. Ölçülen gerçek
vaka: bir çözüm kâğıdında motor 39 sorunun 27'sini buluyordu (recall 0,69) ve
anomali sayısı **0**'dı. Kutu koordinatı üretmek pahalıdır (~25 sn/soru), ama
recall'ü ölçmek için koordinat gerekmez — sayfa başına doğru soru **sayısı**
yeter (~45 sn/sayfa).

```bash
.venv/bin/python altin_sayim.py --belge cozumyazili --hazirla   # çıplak render
#   (insan ÇIPLAK görselden sayar; motorun kutuları GÖSTERİLMEZ)
.venv/bin/python altin_sayim.py --belge cozumyazili --kilitle   # mühürle
.venv/bin/python altin_sayim.py --belge cozumyazili --olc       # ölç
```

Kör sayım zorunludur: motorun taslağına bakılarak sayılırsa ölçüm motorun kendi
hatasına kör kalır (döngüsellik). `--kilitle` boş alan bırakılmadığını,
numara adedinin sayımla uyuştuğunu ve kaynak PDF'in değişmediğini doğrular.
Şema `soru-kesici.golden-count/v1`; golden-v2'den kasten ayrıdır (v2'ye boş
`questions` listesi eklemek tüm tahminleri false-positive sayıp metrikleri
bozar).

V3.3 kabul koşumunda 292 otomatik test geçti. Sabit 10-belgelik gerçek korpusta
ham geometri anomali sinyali toplamı 10'dur; hiçbir belgede artış olmadı.
Bu sayı gerçek insan-etiketli IoU/F1 yerine geçmez: kesin doğruluk iddiası için
`kalite/altin/` altında bağımsız onaylı golden kutular gerekir.

Metin katmanı bulunan iki sütunlu MEBİ TYT kitaplarında motorun kendi
tahminlerini kopyalamadan golden-v2 üretmek için:

```bash
.venv/bin/python altin_pdf_katmani.py kitap.pdf \
  --cikti kalite/altin/tyt1.json \
  --dataset tyt1 --split holdout --denemeler 7-8 --sayfalar 291-384 \
  --onizleme kalite/altin_onizleme/tyt1
```

Araç PDF'nin yerleşik kelime koordinatlarını kullanır, her denemede
`40 Türkçe + 25 Sosyal + 40 Matematik + 20 Fen` bütünlüğünü zorunlu tutar,
ortak paragrafları ayrı `shared_stimulus` bölgesi olarak etiketler ve bütün
sayfaları kapsayan kutulu temas sayfaları üretir. Üretilen veri önce
`dogrula` golden-v2 yükleyicisinden geçirilir. Uzun altın koşuları normal
regresyon turunu yavaşlatmamak için koleksiyonda `varsayilan: false` tutulup
adıyla çağrılır:

```bash
.venv/bin/python kalite_kosusu.py --sadece tyt1_2026_holdout
```

`tyt-1 (1).pdf` için hazırlanan bağımsız ve görsel denetimli küme:

- `tyt1_2026_full.json`: 398 sayfa, 8 deneme, 1.000 soru.
- `tyt1_2026_calibration.json`: ilk 6 deneme, 750 soru; geliştirme/tuning.
- `tyt1_2026_holdout.json`: son 2 deneme, 250 soru; tuning sırasında
  hata ayrıntıları açılmadan son doğrulama.
- V3.3 sonucu: kalibrasyon F1 `0,975`, holdout F1 `0,984`; iki koşumda da
  geometri anomali sayısı `0`. Holdout'ta 250 altın soruya karşı 251 nihai
  kesim üretilmiştir.

V3.3 metinli PDF yolunda numaralı test yönergelerini soru çapası olmaktan
çıkarır, şekil içi numaraları sınır adayı yapmaz, son soruyu vektör metnin son
gerçek içerik satırında kapatır, şekille ayrılmış numara-gövdeyi yeniden bağlar
ve farklı render boyutundan kalan yerel-model önbellek koordinatlarını fiziksel
sayfa sınırına kırpar.

## Optik okuyucu (ZipGrade tarzı cevap kâğıdı üret + oku + analiz)

Kendi optik cevap kâğıtlarınızı üretir, telefon fotoğrafından veya tarayıcı
PDF'inden okur, netleri hesaplar, madde/kazanım analizi ve karne üretir.
Üretici ile okuyucu **aynı şablonu** paylaşır (kapalı döngü): PDF basılırken
balon koordinatları `<form>.sablon.json` olarak yazılır — elle şablon ölçümü
yoktur. Hizalama 4 köşedeki **ArUco işaretçileriyle** yapılır (köşe kimlikli →
döndürülmüş/perspektifli fotoğraf sorun değil; 3 işaretçiyle de çalışır),
sayfa kimliği QR ile yedeklenir. Doldurma kararı sayfa-uyarlamalı eşikle
verilir; **asla argmax kullanılmaz** — her soru `bos/tek/coklu/belirsiz`
hükmü ve güven puanı alır, şüpheliler web'deki inceleme ekranına düşer
(balona tıklayarak düzeltilir).

- **Kurulum** (okuma motoru): `python3 optik_kur.py` — ana `.venv`'e
  dokunmadan `.venv-ml`'e yalnız `opencv-python-headless` (~40 MB) kurar
  (duzen_kur kurduysa hiçbir şey kurulmaz). Form ÜRETİMİ kurulumsuz çalışır.
- **Web akışı**: `python3 soru_kes_web.py` → **🔘 Optik** sekmesi.
  Formlar (hazır tipler: yazılı 20/50/100, LGS sözel/sayısal, TYT, AYT +
  parametrik tasarımcı; kitapçık A-D, öğrenci no, T.C. kimlik, Türk alfabeli
  ad-soyad grid'i) → Tara (fotoğraf/PDF sürükle-bırak) → Sonuçlar (anahtar
  gir veya işaretli kâğıdı anahtar yap; net = D−Y/4, D−Y/3 veya cezasız;
  CSV / klasik optik TXT / e-Okul / karne PDF indir) → İncele → Analiz
  (p, ayırt edicilik, nokta-çiftserili, çeldirici, KR-20 + kazanım analizi).
- **CLI**: `python3 optik.py uret|sinavlar|oku|anahtar|puanla|analiz|disa`
  (örnekler: `python3 optik.py uret --on-ayar lgs-sozel -o form.pdf`,
  `python3 optik.py oku --sinav <kimlik> taramalar/*.jpg`).
- **İptal işaretleri (X/karalama)**: klasik erozyon-dayanımı sezgiseli +
  isteğe bağlı CNN çapraz kontrolü. Model tamamen sentetik veriyle eğitilir:
  `.venv-ml/bin/python optik_model_egitim.py hepsi` (torch gerektirir;
  yoksa okuma klasik sezgiselle aynen çalışır).
- Veriler `~/Library/Application Support/soru-kesici/optik/` altındadır
  (SQLite + taranmış kâğıt arşivi); işçi günlüğü
  `~/Library/Caches/soru-kesici/optik/isci.log`.

### Soru Kesici ile birlikte çalışma (kes → sınav + optik → tara → karne)

Sınav üreten her akış eşleşen optik cevap kâğıdını da üretebilir
(`optik_koprusu`): kesilen soruların **cevapları kitapçık anahtarlarına**,
**konu etiketleri kazanım eşlemesine** otomatik yazılır — kitapçık
permütasyonları sınav PDF'iyle aynı tohumdan hesaplandığı için A/B/C/D
anahtarları elle girilmeden doğru eşleşir; tarar taramaz puanlama ve
kitapçık-farkındalı kazanım analizi hazırdır.

- **Web**: Kesim → "📄 Sınav Kağıdı" ve Soru Bankası → sepet panelinde
  "🔘 Optik cevap kâğıdı da üret" onay kutusu (Sınav Sihirbazı'nın optik
  çıktısı da aynı köprüyü kullanır). İndirilen zip'e optik PDF de girer;
  sınav, 🔘 Optik sekmesinde taramaya hazır görünür.
- **CLI**: `soru_kes.py test.pdf --sec "t5" --sinav-pdf sinav.pdf
  --kitapcik 2 --tohum 7 --optik-form` → `sinav_optik.pdf` + kimlik;
  taramalar `python3 optik.py oku --sinav <kimlik> …` ile okunur.
- **Masaüstü**: Araçlar → Sınav PDF'i Üret → "Optik cevap kâğıdı da üret".

## Test edildiği düzenler

MEB Kazanım/Tarama Testleri, YKS TYT/AYT resmi kitapçıkları (ÖSYM filigranlı),
Palme/İlk Önce/Tudem/Aydın/Final/Prf/Oky yayınları soru bankaları, MEB "DÖRT
DÖRTLÜK" ve çözümlü kaynaklar, **açık uçlu** (yazma alanlı) sorular, 3 sütun +
yan bilgi kutusu, yatay 2-sayfa taramalar — metin katmanlı ve taranmış (OCR)
biçimlerde, çoktan seçmeli/açık uçlu/çözümlü formatlarda.

Ek destekli düzenler: **slayt/sunum** (16:9 yatay, koyu zemin — sayfa başına
tek soru/cevap, tek kutu olarak kesilir), **numarasız** başlıkla ayrılan
sorular (görsel büyük-boşluk blok segmentasyonu), ve metin katmanı yalnız
başlıktan ibaret **resim-içerikli** sayfalar (otomatik OCR'a düşülür).

## Bilinen sınırlamalar

Aşağıdaki durumların çoğu **web ya da masaüstü arayüzünde kutuları elle
düzelterek** çözülebilir (taşı/boyutlandır/çiz/birleştir).

- Sütun/sayfa sonunda ikiye bölünen sorular, ikinci parçanın numarasız kalan
  şıkları (C, D, E gibi) ilk parçanın eksik şıklarını tamamladığında otomatik
  birleştirilir (`--birlestirme`). Bu yüksek-kesinlik kanıtı yoksa (ör. gövdesi
  ortadan bölünmüş, şık ipucu olmayan sorular) birleşme yapılmaz — elle
  "Birleştir" ile düzeltilebilir.
- Çözümlü kaynaklarda çözüm bölümü sayfaları ("Soru 1 :", "Çözüm 2"
  başlıklarıyla) her çözüm ayrı kesilir; ancak sütunları çok dar boşlukla
  ayrılan yoğun çözüm sayfalarında bazı çözümler tek blok kalabilir.
- Çok düşük çözünürlüklü taramalarda OCR bazı numaraları kaçırabilir; bu
  sütunlar çoğunlukla görsel blok segmentasyonuyla kurtarılır, ama şık da
  okunamıyorsa sütun eksik kalabilir. `--onizleme` ile kontrol edin.
- Yan yana iki farklı soru sütunu içeren karşılaştırma broşürleri (ör.
  "ÖSYM SORDU / BİZ YAKALADIK") kısmen kesilebilir.
- **Konu-anlatımlı-hibrit** kaynaklarda (yan "BİLGİ" paneli + numaralı
  şema düğümleri + çözümlü örnek bir arada) bazı örnekler yatay traşlanabilir
  veya panel bir kutu olabilir. Saf soru bankaları ve açık uçlu testler
  etkilenmez.
- Çok büyük yüksek-çözünürlüklü taranmış PDF'lerde ilk OCR sayfa başına
  yavaştır (dakikalar sürebilir); ama sonuç önbelleğe alınır, ikinci açılış
  hızlıdır. `--dpi` düşürmek de hızlandırır.
