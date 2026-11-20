# sinav-okur — Geliştirici Kılavuzu

Türkçe **el yazısı** biyoloji/tıp sınavlarını okuyup puanlayan yerel araç.
Tek kullanıcı: kendi sınavlarını puanlayan bir öğretmen. Eğitim Google Colab'da,
çıkarım Mac'te (Apple Silicon).

## Komutlar

```bash
uv sync --extra dev        # geliştirme bağımlılıkları
make kontrol               # KALİTE KAPISI: testler + altın set regresyonu + kapı teşhisi
uv run pytest -q           # yalnız testler (~570); değişiklikten sonra ZORUNLU
uv run sinav-okur webapp   # yerel arayüz → http://127.0.0.1:8000
uv run sinav-okur tezgah --altin-uret --kaynak hepsi --zincir ikisi
uv run sinav-okur motor-sagligi          # elenen OCR motorları (--sifirla ile geri al)
uv run sinav-okur motor-karsilastir      # hangi OCR motoru sizin kâğıtlarınızda daha iyi
```

## Kalıcı kurallar

- **Türkçe adlandırma**: modül, fonksiyon, değişken, test adları ve commit mesajları
  Türkçedir. Yeni kod mevcut geleneğe uyar (`serbest_kagit_isle`, `kutu_taniy`,
  `guvenlik_kapisi_ozeti` gibi).
- **Sentetik veri değil, gerçek veri**: kullanıcı font-render/sentetik eğitim verisini
  açıkça reddetti. Gerçek eğitimde sentetik üretim engellidir (yalnız `--test-amacli`).
  Tek gerçek veri kaynağı izinli el yazısı + insan-düzeltme döngüsüdür.
- **`transformers<5`**: 5.x TrOCR tokenizer'ını yükleyemiyor; pin korunmalı.
- **Sistem kâğıt üretmez**: şablon/form üretimi ve ArUco hizalama bilinçli olarak
  kaldırıldı. Serbest düzenli sınavlar ORB+homografi ile hizalanır.

## Modül haritası (`sinav_okur/`)

- `serbest.py` — ana orkestratör: sınav çözümleme + öğrenci kâğıdı işleme hattı.
- `ocr.py` + `htr/` — çoklu OCR: `coklu.py` topluluk oylaması (+ kanıt zayıfsa
  kendi bütçesiyle çalışan **aşama-2** yeniden okuma), `trocr/vision/mlxvlm/
  keras_*` motorları, `kalibrasyon.py` Platt + **dilimli** (`KosulluGuvenKalibrasyonu`)
  güven kalibrasyonu, `yeniden_siralama.py` dar marjda aday seçimi, `Taniyici`
  protokolü (fabrika `htr/__init__.py`). Sahte motor: `yapay` backend.
- `terim_sozlugu.py` — alan sözlüğüyle OCR sonrası terim düzeltme (anahtar + kitap
  RAG + öğretmen düzeltmeleri + taban terim listesi). Sentetik üretim ÇAĞIRMAZ.
- `puanlama/` — `__init__.py:PUANLAYICILAR` kayıt defteri (yeni soru tipi eklemek
  için buraya giriş yeter): `bosluk` (çok boşlukta kısmi puan + öğrenilmiş kabul),
  `rubrik` (sözcüksel+anlamsal), `yapisal` (sıralama/eşleştirme/sayısal/formül),
  `akran` (kohort tutarlılık kapısı — puanı asla değiştirmez), `gomme`.
- `yeniden_puanlama.py` — puanlamayı depo yazımından ayıran ortak servis
  (`metni_puanla` saf, `kutuyu_yeniden_puanla` yazar).
- `anahtar_duzen.py` — form/RAG girdisinden `CevapAnahtari` kurma + anahtar
  değişikliğinin etkisini **yazmadan** önizleme.
- `anahtar_dosya.py` — öğretmenin hazırladığı CSV/XLSX/JSON/YAML anahtar
  dosyasını `CevapAnahtari`'ya çevirir. Tek hata varsa **hiçbir soru
  uygulanmaz** (kısmi uygulama sessiz puan kaybı üretir). Öğretmen verisi
  sayılır: `onayli` + `otomatik_uretildi=False`. Koleksiyon alanları tip
  denetiminden geçer (metin gelirse dataclass onu karakterlere bölerdi).
- `anahtar_ocr.py` — anahtar kâğıdının fotoğrafı/PDF'i: OCR → yerel model ile
  yapılandırma → **dayanak denetimi**. Her satır yalnız O SORUNUN belge
  bölümünde (`soru_bolumu`) aranır; kısa satırlarda bulanık eşleşme
  kullanılmaz. Dayanağı bulunmayan satır anahtarı taslakta bırakır ve o
  sorunun otomatik puanlamasını kapatır. Çıktı hep `taslak` +
  `otomatik_uretildi=True`.
- `yerel_motor.py` — cevap anahtarı üretimini biyo-cozucu'nun yerel MLX
  modeline bağlar. Çalışan .app'i arar (8020–8030), yoksa kendi venv'inden
  alt süreç başlatır (**8031–8039**; 8040 Öğretmen Çantası'nın) ve `/healthz`
  poll eder. Başlatma tek kilitle serileştirilir; `/api/v1/uret` ucu olmayan
  eski sürüm sunucu kara listeye alınıp kendi sürecimize düşülür. Yalnız
  kendi başlattığı süreci kapatır. Env: `SINAV_OKUR_BIYO_URL/KOK/PORTLAR/
  MOTOR/PY` (`PY`: başlatıcı yorumlayıcı/araç — Windows'ta varsayılan
  `<biyo_kok>/runtime/python.exe -m biyo_cozucu.cli`), üretici seçimi
  `SINAV_OKUR_ANAHTAR_URETICI=otomatik|yerel|bulut`.
- `gelisim.py` — öğrencinin sınavlar arası puan serisi ve sınıf matrisi.
- `psikometri.py` — sınavın KENDİ kalitesi: Cronbach α (güvenilirlik),
  düzeltilmiş madde-toplam korelasyonu (r_pbis; negatifse `anahtar_supheli`
  bayrağına OR'lanır), puan dağılımı, program–öğretmen uyumu. **Az örneklemde
  sayı uydurmaz**: `{"deger": None, "neden": "yetersiz_ornek", ...}` döner.
- `motor_etkisi.py` — puanlama motoru değişikliğinin mevcut puanlara etkisini
  yazmadan ölçer; "açılabilir mi" sorusunu gerekçeleriyle cevaplar.
- `guvenlik_kapisi.py` — seçici kabul/inceleme kapısı (`SINAV_OKUR_GUVENLIK_KAPISI`
  env: `kapali`/`golge`/`aktif`).
- `depo.py` (+ `sonuclar.py`) — SQLite depo ve sonuç modelleri.
- `kalite.py` — görüntü ön işleme + kalite kapıları; `tarama/` satır/kutu bölme, PDF.
- `analiz.py`, `rapor.py` — sınav analizi ve Excel dökümü.
- `kimlik.py`, `ogrenci.py`, `gizlilik.py` — öğrenci kimlik okuma ve anonimleştirme.
- `referans/`, `rag_anahtar.py`, `bioprof.py` — kitap RAG ve BioProf köprüsü.
- `yapay_zeka.py` — cevap anahtarı üretimi **doğrudan Anthropic Messages API**
  ile, `urllib` üzerinden. `anthropic` SDK'sı bilinçli olarak YOK: Windows
  paketi (cumhuriyet-paket) bağımlılıklarını kendi `sinav-okur-req.in`
  listesinden kurar, yeni paket orada ImportError olur. Anahtar:
  `ANTHROPIC_API_KEY` → `~/Library/Application Support/SinavOkur/claude-api.key`
  (0600; kurulum `scripts/claude_api_bagla.py`). Varsayılan `claude-opus-5-5` +
  `effort: high`, yedek `claude-sonnet-5-5` (`SINAV_OKUR_CLAUDE_API_*`).
  `temperature`/`thinking` GÖNDERİLMEZ (bu modellerde 400). Çıktı
  `output_config.format` JSON şemasıyla (`anahtar_cikti_semasi`) alınır;
  `stop_reason` içerikten ÖNCE denetlenir: ret → yedek model, hâlâ ret ya da
  kesik çıktı ise grup tek tek yeniden istenir (bilinmeyen durma nedeni geçici
  hata sayılır, yarım JSON ayrıştırılmaz). Hatalar `ClaudeApiHatasi(tur=...)`;
  kullanıcı mesajı ham üst
  akış gövdesi taşımaz, ayrıntı günlüğe gider. `_json_istek` artık yalnız yerel
  sunucular (BioProf, biyo-cozucu) içindir. Testlerde `conftest` gerçek anahtarı
  yalıtır; ağ `urlopen` seviyesinde sahtelenir.
- `ogrenme.py` — öğretmen düzeltmelerinden öğrenme / kalibrasyon verisi.
- `webapp/` — FastAPI + Jinja2 arayüzü. `__init__.py` yalnız fabrikadır;
  rotalar `rota_kur(baglam) -> APIRouter` veren modüllerdedir: `api_v1`
  (Öğretmen Çantası yerel API'si; Bearer token `OGRETMEN_API_TOKEN_YOLU`,
  içe aktarılan sorular hep `otomatik_puanlama=False`, okunmuş kâğıdı olan
  sınava yeniden içe aktarma 409), `referans`, `gelisim`, `yukle` (serbest
  akış dahil), `kagit`, `sinav` (tezgâh/tutarlılık/anahtar/itiraz), `kapi`
  (**gölge kapı telemetri paneli** `/kapi`: aktivasyon ilerlemesi, veto
  histogramı, eşik süpürme simülasyonu — yalnız rapor; `/disaaktar.zip`
  flywheel paketi), `genel`. Paylaşılan durum/yardımcılar `baglam.py`
  (`WebBaglam`); modül düzeyi mutable global YASAK (test yalıtımı).
  `tests/test_webapp_rota_paritesi.py` rota kümesini sabitler — rota
  ekleyince/çıkarınca listeyi güncelle. Ortak arayüz JS'i
  `webapp/statik/arac.js` (`/statik` mount): tablo arama/filtre
  (`data-tablo-ara`/`data-filtre-hedef`), sütun sıralama (`th[data-sirala]`,
  sayısal olmayan hücreye `data-deger`), klavye gezinme
  (`#onceki/#sonraki-baglanti`), uzun işlem form kilidi
  (`form[data-yukleniyor]`). Hata sayfası içerik-müzakerelidir: `/api/*` ve
  programatik istemciler JSON alır, tarayıcı `hata.html` görür.
- `tezgah.py` — altın örnek regresyon tezgâhı (`sinav-okur tezgah`):
  altın set üretimi (`--kaynak onay|duzeltme|hepsi` — **onay şartı yok**,
  öğretmen düzeltmesi tek başına etikettir), CER/tam eşleşme/puan MAE,
  `olcumler/` anlık görüntüsü + gerileme farkı, `--supurme` kapsam tablosu,
  `--perf` motor süre kırılımı. Yalnız ölçer, eşik değiştirmez.
  `--zincir ham|uretim|ikisi`: **varsayılan `uretim`** — tezgâh üründeki
  zinciri (bağlam + sözlük + yeniden sıralama) ölçer, çıplak `kutu_taniy`'i
  değil. `ikisi` katman kazancını raporlar. Ayrıca **hata bütçesini ikiye
  böler** (`rubrik_hatasi` = anahtar hatası, `ocr_puan_hatasi` = okuma
  hatası) ve kapıyı altın sette simüle edip yanlış otomatik kabulü ölçer.
- `tanima_zinciri.py` — üretimdeki okuma zinciri tek imzada (`kutuyu_oku`);
  `serbest.py` ve `tezgah.py` aynı kodu kullanır. Sıra: kâğıt yalıtımı
  (kapalı) → bağlamlı OCR → **basılı metin ayıklama** → sözlük → yeniden
  sıralama.
- `ocr_havuz.py` — `SINAV_OKUR_SICAK_HAVUZ=1` ile sayfa-OCR alt süreçleri
  kalıcı `--sunucu` modunda çalışır (model bir kez yüklenir); zaman
  aşımı/çökmede tek-atımlık yola düşülür. `ocr.py`'de motor başına
  **devre kesici**: art arda 2 çökme → motor o süreç ömründe atlanır.

## El yazısı okuma: ölçülen en büyük hata kaynağı

Öğrenci cevabını **soru kâğıdının üstüne** yazdığında OCR basılı soru metnini
de okuyor. Gerçek bir kâğıtta ölçüldü: ham CER **8.86**, basılı metin
ayıklandığında **3.40** — tek başına %62 iyileşme, puan MAE 2.63 → 1.27.
Ayıklama (`serbest.basili_metin_karisimi` + `_basili_metni_cikar`) artık
kâğıt tipine değil METNE bakarak tetikleniyor: karışım oranı eşiği aşarsa
uygulanır, temiz kesilmiş kutuda uygulanmaz (yoksa sorunun kelimelerini
kullanan bir cevap silinebilir). Eşleştirme bulanıktır — OCR basılı metni de
hatalı okur, tam eşitlik aramak kalıntı bırakıyordu.

**Kâğıt yalıtımı varsayılan KAPALI** (`SINAV_OKUR_KAGIT_YALITIMI=acik`):
arka planı (masa, örtü, komşu kâğıt) beyazlatmak CER'i bazı kutularda
düşürüyor (3.31 → 1.11) ama ölçümde bir kutuda okumayı bozup puanı 4.67'den
0'a çöktürdü (puan MAE 1.27 → 2.20). **CER iyileşmesi tek başına kanıt
değildir** — hata bütçesi ayrımı (`rubrik_hatasi` / `ocr_puan_hatasi`) tam
bu yüzden var.

### Motor karşılaştırması (2 gerçek kutu, Türkçe el yazısı, ayıklama sonrası)

| motor | CER | süre/kutu |
|---|---|---|
| **qwen3-vl (mlx, kenar 2200)** | **0.594** | 8.7 sn |
| apple-vision | 0.845 | 0.4 sn |
| topluluk (vision+vlm) | 0.884 | 23.8 sn |
| surya | 1.256 | 28.8 sn |
| easyocr | 1.456 | 4.8 sn |
| tesseract | 1.887 | 1.2 sn |
| **trocr-tr (proje modeli)** | **7.73** | 26.4 sn |
| trocr (İngilizce taban) | 15.35 | 16.5 sn |
| paddle | — | 177 sn, çöküyor |

**TrOCR neden bu kadar geride?** Model 15 fonttan üretilmiş 1.200 *sentetik*
satırda eğitildi (`docs/trocr_egitim_tanisi.md`) ve gerçek el yazısı hiç
görmedi; ayrıca satır modeli olduğu için tam sayfa kutuda `satirlara_bol`
çıktısına bağımlı. Temiz tek satırda bile gerçek metin yerine eğitim
verisinden hatırladığı terimleri üretti (`'511ştırıcı, RNA ve bağıştırıcı'`).
Kullanılabilir hale gelmesi için gerçek, yazar-ayrık el yazısıyla fine-tune
edilmeli — `colab/08_trocr_tek_gecis.ipynb` bunun için duruyor, eksik olan
veri.

Üç sonuç kalıcı olarak not edilmeli:

1. **Görsel-dil modeli geleneksel OCR'ın belirgin önünde** — CER > 1.0 olan
   motorlar el yazısını fiilen okumuyor, basılı metni okuyup el yazısını
   atlıyorlar. (Web araştırması da aynı yönde: frontier VLM'ler IAM'de
   ~%1.2 CER, TrOCR sınıfı modeller artık fine-tuning tabanı.)
2. **Topluluk tek motordan KÖTÜ olabilir.** Vision+VLM oylaması 0.884
   verdi, yalnız VLM 0.594. Kalite farkı büyükken kümeleme, zayıf motorun
   uzun/gürültülü çıktısını öne çıkarıyor. "Motor eklemek iyileştirir"
   varsayımı ölçülmeden kabul edilmemeli.
3. **Çözünürlük el yazısında belirleyici:** 1200 → 0.946, 1600 → 0.612,
   2200 → 0.594. İnce kurşun kalem izleri küçültmede kayboluyor.
   `kursun_kalem_gri` ön işlemesi VLM'e **zarar veriyor** (0.612 → 0.661).
4. **VLM aşırı dar şeritte uydurur.** 3889×81 (48:1) bir satır şeridinde
   Qwen3-VL görüntüyle ilgisiz biçimde pi sayısını yazdı. Bu okuma hatası
   değil halüsinasyondur ve puanlamaya girmesi tehlikelidir; `mlxvlm.py`
   `AZAMI_EN_BOY_ORANI` üstünde boş dönüyor. Satır şeritleri satır
   motorlarının işidir.

`sinav-okur motor-karsilastir` bu tabloyu KENDİ altın setinizde yeniden
üretir — sıralama yazıya ve kâğıda bağlıdır, buradaki sayılar 2 örnekten
gelir ve istatistik değildir.

Qwen3-VL'e *"yalnız el yazısını oku, basılı metni yok say"* demek **işe
yaramıyor**: model basılı soru metnini el yazısı sanıp aynen aktarıyor.
Ayrıntılı "Türkçe karakterlere dikkat et" istemi de sonucu kötüleştiriyor
(0.612 → 0.857). Sade istem + metin düzeyinde ayıklama doğru yol.

## Kritik değişmezler

- **Kapı sözleşmesi:** hiçbir kod `TanimaSonucu.karar_marji`, `uzlasma_guveni`
  veya `bagimsiz_motor_sayisi` alanlarını şişirmez — `guvenlik_kapisi.py`
  eşikleri bunlara bağlı, gölge modun telemetrisi bozulmamalı. Yeni bir veto
  gerekiyorsa `otomatik_karari_degerlendir(..., ek_nedenler=[...])` ile verilir.
- **Öğrenilen hiçbir şey otomatik puanlamaz:** öğrenilmiş kabul yazımları,
  akran uzlaşması ve aday yeniden sıralama yalnız öneri üretir; puan
  değişikliği her zaman öğretmen onayından geçer.
- **Metni değişen kutu kalibrasyona girmez:** sözlük düzeltmesi veya yeniden
  sıralama uygulanmış kutular `kalibrasyon_ornekleri`'nden elenir (öznitelik ile
  etiket farklı adaylara ait olurdu).
- **Anlamsal puanlama varsayılan kapalı ve rolü "kurtarma":**
  `WebBaglam.gomlemci()` yalnız `SINAV_OKUR_GOMLEMCI=acik` ile yüklenir.
  Açılsa bile `ayarlar.anlamsal_rol="kurtarma"` olduğu için katman TEK BAŞINA
  tam puan vermez — yalnız kısmi puan tabanı, kitap örtüşmesi kurtarması ve
  akran kümelemesi. Gerekçe ölçüldü: eşdeğer cevaplarla farklı kavramların
  benzerlik dağılımları örtüşüyor ("mayoz çeşitlilik sağlar" ↔ "mitoz
  kromozom korunur" = 0.692), olumsuzluk görünmüyor ("üretir" ↔ "üretmez"
  = 0.646). `anlamsal_rol="tam"` seçilse bile 0.75 eşiği + sözcüksel destek
  şartı korur.
- **Motor değişikliği ÖLÇÜLMEDEN açılmaz:** `motor_etkisi.motor_etkisini_onizle`
  (depoya yazmaz) + `GET /sinav/{kimlik}/puanlama-motoru`. Kilit ölçü
  `ogretmen_puaniyla_uyum` — öğretmenin elle puanladığı kutular hazır altın
  settir. Elle puanlanmış kutu yoksa ve cevapların %10'undan fazlası
  değişiyorsa kapı "açma" der: ölçemediğimiz bir şeyi açmak, "düşen puan yok"
  gerekçesiyle bile doğru değildir.
- **Toplu onay yalnız düşük riskliyi mühürler:** `webapp/kagit.py`
  `_toplu_onaya_uygun` — kararsız terim, sınırda eşleşme, kısmi rubrik
  kararı, ara işlemde eşleşen sayısal sonuç ve kapı vetosu atlanır ve
  öğretmene nedeniyle listelenir. Ayrım yapmayan toplu onay, yanlış puanı
  tek tıkla kalıcılaştırıyordu.
- **Çelişki denetimi cümle düzeyindedir:** yön tersliği (`_OLUMSUZ`) cevabın
  tamamında aranırsa bulaşır — doğru cevabın yanına eklenen doğru bir
  olumsuz cümle bütün olumlu kalemleri sıfırlıyordu.
- **Sayısalda nihai sonuç ile ara işlem ayrıdır:** doğru değerin cevabın
  herhangi bir yerinde geçmesi tam puan vermez; nihai sonuç yanlışsa yöntem
  payı verilir ve `incele=True` olur.
- **İnceleme kuyruğunun sinyali puan payıdır:** kalem güvenleri `min` ile
  değil puan ağırlıklı birleştirilir; asıl ölçüt riskteki puanın oranı
  (`kararsiz_puan_payi_esigi`). Gömlemcisiz güven tavanı inceleme eşiğinin
  ÜSTÜNDE tutulur, yoksa her açık uçlu cevap kuyruğa düşer.
- **Motor sağlığı oturumlar arası hatırlanır:** `sinav_okur_veri/
  motor_saglik.json`; sürekli başarısız motor varsayılan profillerden düşer
  (`besli` profilinde yine denenir). Testlerde `conftest` bunu yalıtır —
  yalıtılmazsa hem gerçek dosya kirlenir hem testler birbirini etkiler.
- **Yüklenen anahtar önizlediği sınava bağlıdır:** taslak, sınav anahtarının
  parmak izini taşır; arada anahtar değişmişse uygulama 409 verir ve
  öğretmenin öbür değişikliğini ezmez. Taslak token'ı tek kullanımlıktır
  (atomik `rename`), çift tıklama iki kez yeniden puanlamaz.

## Test konvansiyonları

- Ortak fixture'lar `tests/conftest.py`'de: `ornek_sinav`, `soru_yap`, `beyaz_sayfa`/
  `basili_sayfa`, `serbest_ortam`, `depo`, `SahteGomlemci`.
- OCR gerektirmeyen deterministik testlerde `YapayTaniyici` (sabit metin döner) kullan.
- Ağır/opsiyonel bağımlılıklar (`cv2`, `PIL`, `fastapi`, mlx) `pytest.importorskip` ile
  test gövdesinde atlanır — conftest modül düzeyinde bunları import etmez.
