# Kes ve Çöz (Biyoloji)

Referans çözümlerden öğrenip **Türkçe biyoloji sorularını yerel olarak çözen** sistem.

Sen çözülmüş örnekler verirsin → sistem bunları kalıcı hafızaya alır → yeni bir soru
geldiğinde hafızadan **aynı muhakeme yapısındaki** örnekleri getirip kendi adım adım
çözümünü üretir. Aynı örnekler Colab'da LoRA ince ayarı için eğitim verisine dönüşür;
çıkarım Mac'te (Apple Silicon / MLX) yerelde çalışır.

## Tek yüklemeli kullanım

Günlük kullanımın ana yüzü `/kes-ve-coz` adresidir. Kullanıcı yalnız bir kitap
veya test yükler; uygulama aynı iş içinde sayfaları tarar, soruları keser,
belirsiz kesimleri işaretler ve her soruyu sırayla çözer. PDF, DOCX ve yaygın
sayfa görselleri desteklenir; tek iş sınırı 400 MB'dir. İşler ayrı bir SQLite
kuyruğunda tutulduğu için uygulama yeniden başlatılsa da yarım iş sürdürülebilir.

Soru Kesici varsayılan olarak `~/Developer/soru-kesici` altında aranır. Başka
bir kurulum için `SORU_KESICI_KOK=/tam/proje/yolu` verilebilir. Cevap anahtarı
bulunursa çözüm istemine eklenmez; yalnız çözüm üretildikten sonra karşılaştırma
ve inceleme amacıyla kullanılır.

Kesilmiş görsel sonuç kartında her zaman korunur. Metin ve şıklar yeterince
temiz çıkarılmışsa çözüm daha kararlı olan metin motoruna gider; şekil, grafik,
tablo, deney düzeneği veya soyağacı gerçekten gerekliyse görsel motor kullanılır.
Dar ve tek anlamlı soyağacı ile toksik-birikim sorularında model cevabı yerine
alan kuralları uygulanır; eksik OCR veya belirsiz kesim yine incelemeye düşer.

## Hızlı başlangıç

```bash
uv sync --extra dev                      # geliştirme
uv sync --extra mlx --extra web --extra gomme --extra alim   # tam yerel kurulum

# 1) Referans örnekleri ekle (SORU:/ÇÖZÜM: blokları, .json ya da .jsonl)
uv run biyo-cozucu ornek-ekle ornekler.txt

# 1b) Ya da doğrudan kitap/çözüm kaynağından al (PDF, Word, ses, video)
uv run biyo-cozucu al kitap.pdf              # önizleme — hiçbir şey yazılmaz
uv run biyo-cozucu al ders.mp4 --uygula      # onaylayıp hafızaya yaz
uv run biyo-cozucu al ~/Kitaplar --uygula    # klasörü özyinelemeli tara

# 2) Bir soru çöz
uv run biyo-cozucu coz "Mitoz bölünmede kromozom sayısı neden değişmez?"

# 3) Web arayüzü
uv run biyo-cozucu sunucu          # http://127.0.0.1:8000

# 4) Eğitim verisi üret → Colab'da LoRA → modeli kur
uv run biyo-cozucu disa-aktar --etiket v1
uv run biyo-cozucu model-kur ~/Downloads/biyo-lora-v1-adapter.zip
uv run python scripts/lora_birlestir.py      # adaptör + taban → birleşik model

# 5) Kör değerlendirme (test örnekleri hafızadan dışlanarak)
uv run biyo-cozucu degerlendir --ayrintili   # ya da arayüzde /degerlendirme
```

Eğitim akışının tamamı `colab/01_qwen35_lora.ipynb` içinde; Mac'te 16 GB RAM
4B modeli kanıtlı kayıtlarla eğitmeye yetmiyor (üretim token sınırında değil,
bellekte düşüyor), bu yüzden eğitim Colab'da yapılıp model geri getiriliyor.
İlk koşunun sonucu (12 soruluk dilim, sıcaklık 0): doğru 6/12 → 7/12, boş
cevap 2 → 1, adım örtüşmesi 0,49 → 0,54.

Geliştirirken tek komut: `make kontrol` (lint + tip denetimi + kapsamlı test).
Gerçek OCR motorlarını ve tarayıcıyı da süren tam koşu için `make tam-test`.

## macOS uygulaması

```bash
uv run python scripts/install_macos_app.py --replace
```

Masaüstündeki mevcut **Soru Çözücü** uygulaması tek ürünün başlatıcısıdır ve
doğrudan **Kes ve Çöz** yüzünü açar. Çift tıklayınca sunucuyu boş bir portta
başlatıp tarayıcıyı açar; zaten çalışıyorsa ikinci sunucu
başlatmaz, var olanı öne getirir. Port aralığı **8020–8030**; 8000'i PDF
Studio, 8000–8010'u Sınav Okur, 8010'u SesLab kullandığı için bilinçli olarak
ayrı tutuldu. Günlükler `~/Library/Logs/BiyoCozucu/` altında.

Motor türü `BIYO_MOTOR` ile verilebilir. Masaüstü uygulamasının varsayılanı
`karma`dır: metin sorularını ince ayarlı MLX modeline, görsel bilgi gerektiren
soruları görsel modele yollar. Bir PDF'den kırpım üretilmesi tek başına görsel
motor zorunluluğu sayılmaz. Modeller tembel yüklendiğinden sunucu hemen açılır;
hazırlık ilk soruda olur.

## Soru Kesici arşivlerini çözme

[Soru Kesici](../soru-kesici) PDF soru bankalarından soruları kırpıp her biri
için hem görüntü hem yapılandırılmış metin üretiyor. Bu çıktı burada
doğrudan tanınıyor:

```bash
uv run biyo-cozucu arsiv-coz "~/Downloads/10.sınıf Arşiv.zip"          # künye önizlemesi
BIYO_MOTOR=vlm uv run biyo-cozucu arsiv-coz arşiv.zip --coz --limit 20  # gerçekten çöz
```

Arşiv bir `.zip` ya da açılmış klasör olabilir; içinde `soru_NN.png`
görüntüleri ve `sorular.json` künyesi aranır. Her sorunun metni ve şıkları
künyeden, şekli ise görüntüden gelir — yani görsel motorla birlikte kullanmak
anlamlı.

**Bu arşivler referans örnek değildir:** incelenen üç arşivin hiçbirinde
cevap ya da çözüm alanı dolu değil, hepsi saf soru kümesi. Bu yüzden
`arsiv-coz` onları hafızaya örnek olarak yazmaz; **çözer**. Üretilen çözümler
**Çözümler** sekmesinde onayını bekler ve onayladıkların var olan döngüyle
referans örneğe dönüşür — hafızayı doldurmanın en hızlı yolu budur.

Çözme soru başına bir model çağrısı demek; 1200 soruluk bir arşiv saatler
sürer. Bu yüzden varsayılan yalnız önizlemedir, çözmek `--coz` ister.

Örnek dosyası biçimi:

```
SORU: Aşağıdakilerden hangisi mitokondride gerçekleşir?
A) Fotosentez
B) Krebs döngüsü
ÇÖZÜM:
Mitokondri oksijenli solunumun merkezidir.
Krebs döngüsü mitokondri matriksinde gerçekleşir.
Fotosentez kloroplastta olur, bu yüzden A elenir.
CEVAP: B
```

## Kaynaktan referans alma

Kitap, çözüm föyü, ders videosu ya da ses kaydından soru+çözüm çiftleri
çıkarılıp hafızaya alınabilir (`al` komutu ya da arayüzdeki **Kaynaktan al**).

| Girdi | Nasıl okunur | Atıf |
|---|---|---|
| `.pdf` | sayfa sayfa metin katmanı; yoksa OCR | `s. 42` |
| `.docx` | paragraflar + tablolar | — |
| `.txt` `.md` | doğrudan | — |
| `.png` `.jpg` … | OCR | — |
| `.mp3` `.m4a` `.wav` … | ffmpeg → yerel Whisper (Türkçe) | `01:05` |
| `.mp4` `.mov` `.mkv` … | ses ayıklanır → aynı yol | `01:05` |

### YouTube soru çözümü videoları

Bir video ya da oynatma listesinin sesi indirilip yazıya dökülür, çözülen
sorular çıkarılıp **onay kuyruğuna** yazılır. Hafızaya yalnız onayladıklarınız
girer — model çıktısı doğrudan referans örneğe dönüşmez.

```bash
uv sync --extra youtube                                   # yt-dlp

uv run biyo-cozucu youtube-al "<url>"                     # önizleme: künye + süre
uv run biyo-cozucu youtube-al "<url>" --uygula --limit 3  # indir, dök, kuyruğa yaz
uv run biyo-cozucu kuyruk                                 # kuyruk özeti
uv run biyo-cozucu kuyruk 1                               # dosyadaki adayları listele
uv run biyo-cozucu kuyruk 1 --onayla 1,3,5-9              # satır işaretle
uv run biyo-cozucu kuyruk-onayla --hepsi                  # hafızaya aktar + indeksle
```

Arayüzde aynı akış **YouTube'dan al** ve **Onay kuyruğu** sayfalarında; indirme
ve döküm arka planda yürür, kuyruk satırları düzenlenebilir ve her satırda
videonun ilgili saniyesine bağlantı vardır.

Bilinmesi gerekenler: 30 dakikalık bir video ~3-4 dakika döküm demek (transkript
önbelleğe alınır, ikinci koşuda tekrarlanmaz); şıklar çoğu videoda tek tek
okunmadığı için adayların bir bölümü açık uçlu düşer.

Model çıktısı ham kabul edilmez; her aday şu uyarılardan geçer ve uyarı alan
kaydın güveni düşürülür (eleme değil **işaretleme** — karar öğretmenindir):

| Uyarı | Anlamı |
|---|---|
| `dokumde_dayanagi_zayif` | Soru metni dökümde yeterince geçmiyor; model ezberinden yazmış olabilir |
| `cozum_dokumde_yok` | Çözüm videonun anlatımı değil, modelin kendi ders kitabı bilgisi |
| `sohbet_sikki` | Şıklar dökümdeki sohbet cümlelerinden uydurulmuş; küme tümden düşürülür |
| `sohbet_sorusu` | Öğrencinin ara sorusu, çözülen sınav sorusu değil |
| `sik_okunmadi` | Şıklar okunmamış, cevap harfi tek başına kalmış |
| `eksik_secenek` | Yarım şık listesi (yanlış cevap anahtarı üretirdi) |

`--pencere` varsayılanı (3600 karakter) gerçek bir videoda ölçülerek seçildi:
küçük pencere soruyu şıklarından ayırdığı için model eksik bağlamı çevredeki
konuşmayla tamamlayıp sahte şık üretiyor. Ayrıntı `alim/konusma.py` içinde.

#### Uzun videolar: dökümü Colab'de yap

Yerel yazıya dökme kabaca gerçek zamanın altıda biri hızında. Bir saati aşan
videolarda bu sürdürülemez hâle geliyor: 10 saatlik bir ders videosu ~100
dakika döküm, ~1 GB'lık WAV ve whisper çağrısındaki **1 saatlik zaman aşımını
aşma** demek. Böyle videolarda döküm Colab GPU'sunda yapılır:

1. `colab/02_youtube_dokum.ipynb` defterini Colab'de aç, çalışma zamanını
   **GPU** yap, adresleri gir ve çalıştır. Çıktı `<video_id>.json`.
2. İnen dosyaları yerel önbelleğe kur, sonra normal akışa devam et:

```bash
uv run biyo-cozucu transkript-al ~/Downloads/<video_id>.json
uv run biyo-cozucu youtube-al "<url>" --uygula   # indirmez, dökmez
```

`youtube-al` önbellekte döküm bulduğunda indirmeyi ve yazıya dökmeyi atlayıp
doğrudan soru çıkarımına geçer; ekranda "önbellekteki döküm kullanılıyor" yazar.

### OCR (taranmış PDF ve fotoğraf)

Metin katmanı olmayan sayfalar OCR'a düşer. Dört motor desteklenir, Türkçe
kalitesine göre sıralı — kurulu olanlardan en iyisi otomatik seçilir:

| Motor | Not |
|---|---|
| `surya` | En iyi. Okuma sırasını da çözer, sütunlu soru kitabında doğru sıra. `llama-server` ikilisi gerekir. |
| `easyocr` | İyi ve kurulumu kolay; olgun Türkçe desteği. |
| `paddle` | İyi, ama PaddlePaddle Apple Silicon'da kırılgan olabiliyor. |
| `tesseract` | En hafifi; temiz baskıda yeterli, bozuk taramada geriler. `tur` dil verisi şart. |

```bash
uv sync --extra ocr             # surya + easyocr
uv sync --extra ocr-tesseract   # ayrıca `tesseract` ikilisi ve tur dil verisi gerekir
uv sync --extra ocr-paddle

uv run biyo-cozucu al tarama.pdf --ocr-motoru easyocr
uv run biyo-cozucu al kitap.pdf --ocr kapali     # OCR'ı hiç çalıştırma
uv run biyo-cozucu al kitap.pdf --ocr zorla      # metin katmanı olsa da OCR'la
```

Motor `BIYO_OCR` ile de sabitlenebilir. OCR pahalı olduğu için varsayılan
`oto`: yalnız metin katmanı bulunmayan sayfalara uygulanır.

Soru ayırma sezgiseldir: numaralı sorular (`1.`, `SORU 3`), konuşma dilindeki
karşılıkları (`Birinci soru`), `A) B) C)` şıkları, `ÇÖZÜM` bölümü ve
`CEVAP: B` / `Yanıt C şıkkıdır` işaretleri yakalanır. Her adaya bir **güven**
değeri verilir; **hiçbir aday otomatik yazılmaz** — CLI'da `--uygula`,
arayüzde onay kutusu gerekir. Taranmış (görüntü) PDF'lerde metin katmanı
yoksa uyarı verilir.

Ses/video için harici ikililer aranır; yolları ortam değişkenleriyle
değiştirilebilir: `BIYO_FFMPEG`, `BIYO_WHISPER_SERVER`, `BIYO_WHISPER_MODEL`.

## Görselli sorular (şekil, grafik, tablo)

Biyoloji soruları sık sık bir şekle dayanır. Soruya görüntü iliştirilebilir:

```bash
uv sync --extra vizyon                       # mlx-vlm >= 0.3.4 + pillow
BIYO_MOTOR=vlm uv run biyo-cozucu coz --gorsel grafik.png "Grafikte hız neden sabitleniyor?"
```

**Günlük kullanımda doğru seçim `karma`**, salt `vlm` değil: `vlm` seçildiğinde
şekilsiz sorular da görsel modele gider ve metin tarafındaki **ince ayarlı LoRA
modeli devre dışı kalır**. Korpusun yalnız ~%30'u şekle bağlı olduğundan bu,
çoğunluğu ince ayarsız tabana düşürmek demek. `karma` motor soruyu içeriğine
göre yönlendirir — şekilsizse metin modeli, şekilliyse görsel model:

```bash
BIYO_MOTOR=karma uv run biyo-cozucu sunucu     # arayüz de şekil yükleyebiliyor
uv run biyo-cozucu degerlendir --motor karma --yalniz-gorselli   # görsel dilimi ölç
```

Arayüzde **Çöz** sayfasındaki dosya alanına yüklenebilir ya da doğrudan
**panodan yapıştırılabilir** (sınav sorusu çoğunlukla ekran görüntüsüdür).

| | |
|---|---|
| Model | `mlx-community/Qwen3.5-4B-MLX-4bit` (4-bit, ~3 GB); 50 gerçek görselli kör testte 9B'den iyi çıktı, `BIYO_VLM_MODEL` ile değiştirilir |
| Bellek | Görsel motor yüklenirken metin modeli bellekten bırakılır — 16 GB'da ikisinin tepe kullanımı aynı anda sığmıyor |
| Kanıtlar | Görüntü önce cevap içermeyen yapılandırılmış kanıta çevrilir; Campbell/Guyton ve referans çözümlerle birlikte kullanılır |
| Saklama | Görüntüler `<kök>/gorseller/<imza>.png`, veritabanında yalnız imza |

Görsel motor kurulu değilse sistem çökmez: soru metinle çözülür, **uyarı
verilir ve çözüm incelemeye düşürülür** — sessizce metne dönmek, kullanıcının
şekle bakıldığını sanmasına yol açardı. Bu durumda isteme "şekildeki veriyi
oku" talimatı da **eklenmez**: görüntü modele ulaşmıyorken o talimat modeli
var olmayan bir veriyi aramaya itiyor ve ölçümde boş cevabı artırıyordu.
Önbellek anahtarı görüntü imzasını da içerir; aynı metin farklı şekille
sorulduğunda eski cevap dönmez.

Kör koşu değerlendirmesi de örneğin görselini çözücüye geçirir; böylece ölçüm
gerçek çözüm yoluyla aynı girdiyi kullanır ve şekilli sorular `BIYO_MOTOR=vlm`
ile ölçülebilir.

Görsel **LoRA eğitimi kapsam dışıdır** (mlx-vlm #824); yalnız çıkarım.

Bir soru kırpımının bulunması, sorunun şekle bağlı olduğu anlamına gelmez.
`auto` yönlendirme; metni ve şıkları tam olan düz soruları ince ayarlı metin
motoruna, grafik/tablo/soyağacı/şema gerektirenleri görsel motora yollar. CLI'da
`--gorsel-modu zorla` ve `--gorsel-modu yok` ile karar açıkça değiştirilebilir.
Görsel yolunda beyaz sayfa kenarları kırpılır; VLM önce yalnız eksen, değer,
sembol ve ilişkileri JSON kanıtına çevirir, sonra ortak hafıza bu kanıtla çözer.

## Desteklenen soru türleri

Yalnız çoktan seçmeli değil; tür, modele cevabı **hangi biçimde** vereceğini
söyler ve cevap o biçime göre otomatik denetlenir.

| Tür | Beklenen cevap | Denetim |
|---|---|---|
| Çoktan seçmeli | tek şık harfi | harf verilen şıklardan biri mi |
| Doğru / Yanlış | `Doğru` \| `Yanlış` | "D"/"evet" gibi girdiler normalleştirilir |
| Boşluk doldurma | boşluk sayısı kadar sözcük, sırayla | sözcük sayısı boşluk sayısıyla eşleşiyor mu |
| Eşleştirme | `I-c, II-a, III-b` | çift biçimi doğrulanır ve kanonikleştirilir |
| Sıralama | `III, I, IV, II` | en az iki öğe var mı |
| Kısa cevap | tek sözcük/sayı | paragraf dönerse uyarılır |
| Açık uçlu | kısa özet cümlesi | — |

Tür arayüzde elle seçilebilir; boş bırakılırsa soru metninden çıkarılır
(`(D/Y)`, `……`, "eşleştiriniz", "sıralayınız", "kaç ATP" gibi ipuçları).
Elle seçim çıkarımı her zaman ezer.

## Hafızayı doldurmak ve ölçmek

Sistemin kalitesini belirleyen tek şey hafızadaki örneklerdir; model ikinci
sıradadır. Bu yüzden arayüz "sırada ne eklemeliyim" sorusuna cevap verir.

**Kapsam boşlukları** (`biyo-cozucu durum` ya da **Pano**): 22 konu × 7 çözüm
türünden hangi hücrelerin boş olduğunu gösterir. Öncelik hiç örneği olmayan
**çözüm türleridir** — erişim katmanı örnekleri tür uyumuna göre kademelediği
için, boş bir tür o türdeki her soruyu yapı uyumsuz kanıtla çözdürür.

**Kör değerlendirme** (**Değerlendirme** sekmesi): test örneklerini hafızadan
dışlayarak çözer, sonucu tür bazında kırar ve koşuyu geçmişe yazar. Ölçümün
değeri tek bir sayıda değil, koşular arası farktadır — taban modeli ve ince
ayarlı modeli aynı test kümesinde koşturup karşılaştır. Bölme sorunun imzasına
bağlı olduğundan yeni örnek eklemek eski koşuları karşılaştırılamaz yapmaz.
Anlamlı bir ölçüm için kabaca 30 örnek gerekir (test dilimi %10'dur).

**Seçici doğruluk.** Hedef "her soruyu cevaplamak" değil, *cevapladığı* soruda
yanılmamak: emin olmadığını incelemeye düşürmek öğrenci için yanlış cevaptan
güvenli. Bu yüzden tek başına doğruluk yanıltıcıdır — kapsamayı düşürerek
doğruluğu şişirmek kolaydır, ikisi **birlikte** okunur:

```bash
uv run biyo-cozucu degerlendir --esik 0.55    # kapsama + o kümedeki doğruluk
uv run biyo-cozucu degerlendir --deneme 3     # her soruyu 3 kez çözüp oyla
uv run biyo-cozucu kalibre                    # tür bazlı güven çarpanlarını öğren
```

Rapor ayrıca **%95 seçici doğruluğu veren en düşük eşiği** (yani en yüksek
kapsamayı) yazar; hiçbir eşik tutturamıyorsa bunu da açıkça söyler — o durumda
sorun eşik değil, güvenin kalibre olmamasıdır. `--deneme N` oylama (*self
consistency*) açar: aynı soru N kez çözülür, en kalabalık cevap kazanır ve
güven **oy oranıyla çarpılır**. 3/3 birleşen cevapla 2/3 bölünen cevabı ayırt
etmek, modelin kendi beyan ettiği güvenden çok daha dürüst bir sinyaldir.
Maliyet doğrusaldır (üretimler seri koşar), bu yüzden varsayılan 1'dir.

**Tür bazlı kalibrasyon** (`kalibre`). Sistem her muhakeme türünde aynı
değil — 125 soruluk ölçümde sınıflandırma %88, mekanizma %63, grafik %31,
kalıtım %18 çıktı. Model ise zayıf olduğu türde de 0,9 güven bildiriyor.
`kalibre` komutu tür bazlı başarıyı ölçüp `<kök>/kalibrasyon.json` dosyasına
çarpan olarak yazar; sonraki her çalıştırma bunu kendiliğinden yükler ve zayıf
türde güveni indirip soruyu incelemeye düşürür.

Tablo **doğrulama diliminden** öğrenilir, test diliminden değil — test
kümesinden öğrenip aynı kümede ölçmek, ölçümü kendi kendini doğrulayan bir
şeye çevirirdi. Az örnekli türlere çarpan yazılmaz (`--asgari-ornek`, öntanımlı
8): orada ölçülen doğruluk gürültüdür ve sistemi rastgele bir türde
susturmak olurdu.

**Açık veri setleri** (`biyo-cozucu set-listele` / `set-al`): takviye
kaynakları. Lisans bir kural olarak uygulanır — türev üretimine izin vermeyen
setler eğitime giremez, istendiğinde hata verir. Setlerin bir kısmı şu an
alınamıyor ve nedeni açıkça yazılır (HuggingFace'te kapılı olma, ya da
sorularının yalnız görüntüden oluşması).

## Nasıl çalışır

1. **Önbellek** — neredeyse aynı soru daha önce çözülmüşse model hiç çalışmaz.
2. **Getirme** — hibrit erişim (BM25 + gömme, RRF birleşimi), ardından **çözüm türü**
   ve konu uyumuna göre yeniden sıralama. Aynı konudan ama farklı muhakeme
   yapısındaki örnek modeli yanlış yola sokabildiği için tür uyumu ayrı ağırlıklanır.
3. **Üretim** — getirilen örnekler gerçek çok turlu diyalog olarak verilir; model
   JSON çözüm döndürür (adımlar, cevap, güven, uyarı).
4. **Öz-kontrol** — şık uyumu, boş adım/cevap, kanıtsızlık cezası; düşük güven
   incelemeye düşer.
5. **Döngü** — arayüzde onayladığın/düzelttiğin çözümler yeni referans örnek olur.

Model yoksa sistem çökmez: en benzer referans çözümü gösterir ve her zaman
incelemeye düşürür.

## Ortam değişkenleri

| Değişken | Anlamı |
|---|---|
| `BIYO_VERI` | Veri kökü (varsayılan `~/.biyo-cozucu`) |
| `BIYO_MOTOR` | `mlx` \| `vlm` \| `karma` \| `http` \| `sahte` |
| `BIYO_VLM_MODEL` | Görsel model (varsayılan `mlx-community/Qwen3-VL-4B-Instruct-4bit`) |
| `BIYO_MLX_MODEL` | Yerel model yolu/adı (varsayılan `mlx-community/Qwen3.5-4B-MLX-4bit`) |
| `BIYO_MLX_ADAPTOR` | LoRA adaptör dizini |
| `BIYO_MOTOR_URL` | OpenAI-uyumlu uç (varsayılan `http://127.0.0.1:8080/v1`) |
| `BIYO_GOMME_MODEL` | Gömme modeli (varsayılan `ytu-ce-cosmos/turkish-e5-large`) |
| `BIYO_DUSUNME` | `0` ile düşünme modunu kapat (hızlı, daha zayıf muhakeme) |
| `BIYO_FFMPEG` | ffmpeg ikilisi (varsayılan `~/.local/bin/ffmpeg`, yoksa PATH) |
| `BIYO_WHISPER_SERVER` | whisper.cpp `whisper-server` ikilisi (KitapKatalog kurulumu) |
| `BIYO_WHISPER_MODEL` | ggml model dosyası (varsayılan `ggml-large-v3-turbo-q5_0.bin`) |
| `BIYO_YTDLP` | yt-dlp ikilisi (varsayılan: PATH, yoksa `python -m yt_dlp`) |

Bu değişkenlerin **tek kaynağı `~/.biyo-cozucu/ortam.sh`**: hem `macos/launcher.sh`
hem kabuk profili onu okur. Finder'dan açılan bir `.app` kabuk profilini
okumadığı için, ayarı yalnız `.zshrc`'ye yazmak arayüzün sessizce taban modele
düşmesine yol açıyordu.

Eğitim akışı için `docs/egitim_runbook.md`.
