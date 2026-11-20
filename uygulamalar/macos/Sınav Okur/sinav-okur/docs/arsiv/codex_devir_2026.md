> **ARŞİV — GÜNCEL DEĞİL (2026-07-24).** Bu belge bir devir anının anlık
> görüntüsüdür. "3 commit / 50 test", silinmiş `sablon/`, `isle.py`,
> `kagit_simule.py` modülleri ve "sıradaki adımlar" bölümü artık geçerli
> değildir. Projenin güncel durumu için `README.md` ve `docs/oturum_ozeti_*.md`
> dosyalarına, kalıcı geliştirme kuralları için kökteki `CLAUDE.md`'ye bakın.
> Belge, T-H-E veri bulguları ve kullanıcı yön tercihleri gibi tarihsel bağlam
> için korunmaktadır.

# sinav-okur — Codex Devir Dökümanı

Bu proje Claude Code tarafından başlatıldı; bundan sonrasını sen (Codex) devralıyorsun.
Kod tabanı `~/Developer/sinav-okur` altında, git deposu (3 commit), 50 test geçiyor.
Aşağıdakiler kendi kendine yeten bir özettir; ayrıntı için dosyaları doğrudan okuyabilirsin.

---

## 1. Proje amacı

**Kağıda Türkçe EL YAZISIYLA yazılmış sınavları okuyup puanlayan sistem.**
- Alan: **biyoloji ve tıp/sağlık**.
- Soru tipleri: **açık uçlu · kısa cevaplı · boşluk doldurmalı**. (Çoktan seçmeli / optik YOK.)
- Eğitim **Google Colab**'da (kullanıcının Colab Pro+ hesabı var), çıkarım **Mac**'te (Apple Silicon).
- Kullanıcı tek kişi: kendi sınavlarını puanlayan bir öğretmen.

## 2. KULLANICININ GÜNCEL VE KRİTİK YÖN TERCİHLERİ (en önemli bölüm)

Kullanıcı süreç içinde yönü netleştirdi — bunlara MUTLAKA uy:

1. **YAPAY / SENTETİK VERİ İSTEMİYOR.** Başta font ile sentetik satır üreten bir hat
   kurulmuştu (`sinav_okur/veri/sentetik.py`); kullanıcı bunu açıkça reddetti.
   **GERÇEK Türkçe el yazısı verisi kullanılacak.**
2. **TensorFlow / Keras** ile **CNN tabanlı el yazısı KARAKTER tanıma** istiyor
   (referans: "TFLearn ile el yazısı tanıma" eğitim serisi; ancak TFLearn TF2/Colab ile
   çalışmıyor — modern **Keras** karşılığı kullanılıyor). Gri tonlamalı görüntüler.
3. **Colab'da eğitimi kendisi izlemek istiyor** ("her şeyi sen yap" dedi ama Colab
   otomasyonu tarayıcı üzerinden kırılgan ilerledi; en sağlam yol defteri hazırlayıp
   Colab'da çalıştırmaktır).
4. Nihai hedef yine aynı: kağıttaki Türkçe el yazısını en yüksek doğrulukla okumak,
   biyoloji/tıp sınavı puanlamak.

## 3. ARAŞTIRMA BULGULARI (kanıtlanmış — tekrar araştırmana gerek yok)

İki derin araştırma turu (web + GitHub + HuggingFace, 23 ajan) + doğrudan HF API taraması yapıldı:

- **Hazır Türkçe el yazısı sınav-puanlama sistemi YOK.**
- **HuggingFace'te GERÇEK Türkçe el yazısı GÖRÜNTÜ veri seti YOK** (HF datasets API ile
  doğrulandı): `turkish handwriting/handwritten/htr/el yazısı` aramaları **boş**; sadece
  `turkish ocr` birkaç set veriyor ve hepsi **font-render (sentetik) veya basılı**:
  - `orkungedik/ocr_turkish_char_dataset` → kolonlarında **`font_size`** var (= fontla
    üretilmiş, gerçek el yazısı değil).
  - `emredeveloper/turkish-ocr` → sentetik/render (%30 basılı). Yalnız **eval** için.
  - `esengul3/turkish-word-ocr`, `sfidan42/...noise-corpus` → sentetik/basılı.
- **Tek GERÇEK Türkçe el yazısı görüntü verisi: T-H-E.**
  - Repo: `https://github.com/bartosgaye/thedataset` (git-lfs ile CSV).
  - 200 gerçek yazar, 28×28 gri **KARAKTER** görüntüleri, 78 sınıf, Türkçe harfler dahil
    (ç ğ ı ş ö ü + büyükleri; i/ı ve I/İ ayrık).
  - **HuggingFace'te YOK** (`bartosgaye/thedataset` 401 verir). GitHub'dan git-lfs ile gelir.
  - Format: her CSV satırı = etiket + 784 piksel (28×28). `version1.csv`..`version6.csv`.
  - Lisans: repoda LICENSE yok → atıfla eğitim (Ediboğlu Bartos ve ark., Acta Polytechnica
    Hungarica 2020); veriyi yeniden dağıtma.
- **Gerçek SATIR/KELİME düzeyi Türkçe el yazısı veri seti HİÇBİR YERDE YOK.**
  Sadece karakter düzeyi (T-H-E) var.
- **Gerçek BİYOLOJİ/TIP Türkçe el yazısı veri seti YOK.**
- `denizdoktur/turkish-handwritten-ocr` (GitHub): gerçek Türkçe el yazısıyla eğitilmiş
  **CRNN+CTC .pt** ağırlıkları (128×1024 gri, satır-HTR). Veri değil; pseudo-labeling /
  transfer temeli olarak değerli.
- Satır-HTR modelleri (ileride): `microsoft/trocr-base-handwritten` (MIT),
  `Qwen2.5-VL-7B-Instruct` (Apache); puanlama gömlemesi
  `emrecan/bert-base-turkish-cased-mean-nli-stsb-tr` (Apache).

**Sonuç:** Gerçek-veri-only bir yaklaşımla bugün eğitilebilecek tek şey T-H-E ile
**karakter tanıma**dır. Kağıttaki kelime/satırlar için ya karakter segmentasyonu + karakter
CNN, ya da ileride gerçek satır verisi toplanması gerekir (kullanıcının kendi kâğıtları →
flywheel). Bu gerçeği kullanıcıya net tut.

## 4. NEREDE KALINDI (senin başlangıç noktan)

Colab'da (kullanıcının `Untitled1.ipynb` defteri) **T-H-E gerçek verisiyle Keras CNN
karakter tanıma** eğitimini başlatmak üzereydik. Eğitim kodu HAZIR:

- **`/private/tmp/claude-501/-Users-mehmetderin/ad78c4d4-e5bc-41d7-ad23-0ea31adf85bf/scratchpad/cnn_karakter.py`**
  → T-H-E'yi git-lfs ile indirir, CSV okur, gri 28×28 CNN (Conv×3 + Dense) eğitir,
  `/content/turkce_karakter_cnn.keras` + `etiketler.json` kaydeder. **Gerçek veri, sentetik değil.**
- (Alternatif satır-düzeyi CTC kodu da var ama kullanıcı önce karakter CNN istedi:
  `scratchpad/keras_ctc_egitim.py` — bu font-sentetik kullanıyor, kullanıcının "yapay
  istemiyorum" tercihi nedeniyle ŞU AN KULLANMA.)

Colab'a base64 bootstrap ile yazılıyordu (editör autocomplete'i bozmasın diye). Kullanıcı
tarayıcı otomasyonunu durdurup seni devreye soktu.

**Senin ilk işin:** Bu CNN eğitim kodunu repoya kalıcı taşı (`colab/05_keras_cnn_karakter.ipynb`
veya `.py`), Colab'da çalıştırılabilir hale getir ve kullanıcıyla birlikte eğitimi tamamla.

## 5. YAPILMIŞ OLAN SİSTEM (mevcut kod tabanı)

Python uv projesi. `uv sync` ile kurulur. Modüller:

- `sinav_okur/modeller.py` — Sinav/Soru/CevapAnahtari/Rubrik veri modelleri; YAML yükleme
  (özel `_TrLoader`: YAML `no:` → boolean tuzağını kapatır); tip zorlaması (str/float).
- `sinav_okur/metin.py` — Türkçe normalizasyon: NFC, ı/İ küçültme, aksan katlama, eşleşme biçimi.
- `sinav_okur/serbest.py` — temiz 1–4 sayfalık yazılıyı tanıma, basılı dokuya
  göre ön/arka sayfa eşleme, el yazısı farkını çıkarma ve serbest düzenli
  kâğıdı puanlama.
- `sinav_okur/tarama/` — `kes.py` (mürekkep oranı, boş tespit),
  `satir.py` (projeksiyon-profili satır bölme), `pdfoku.py`
  (PDF/PNG/JPG/TIFF/BMP/WEBP/HEIC/HEIF → en fazla dört sayfa).
- `sinav_okur/htr/` — `trocr.py` (satır, transformers), `mlxvlm.py` (Qwen-VL, mlx). Takılabilir
  `Taniyici` arayüzü + `YapayTaniyici` (test). **DİKKAT: bu PyTorch yolu; kullanıcı şimdi
  Keras/CNN istiyor — yeni bir Keras backend eklenmeli.**
- `sinav_okur/puanlama/` — `bosluk.py` (rapidfuzz + aksan toleransı), `rubrik.py` (sözcüksel +
  anlamsal gömme + ders kitabı örtüşmesi), `gomme.py` (sentence-transformers), `ayarlar.py`.
- `sinav_okur/referans/kitap.py` — ders kitabı pasaj indeksi (gömme) + referanslı puanlama.
- `sinav_okur/veri/` — `sentetik.py` (font sentetik — KULLANICI İSTEMİYOR), `fontlar.py`
  (cmap Türkçe doğrulama; 15 OFL font Türkçe-tam), `korpus.py` (biyoloji/tıp terimler),
  `gercek.py` (HF adaptörü `hf_labels_uret`), **`the_karakter.py`** (T-H-E karakter→satır
  köprüsü; gerçek glifler).
- `sinav_okur/depo.py` (SQLite), `sonuclar.py` (düzenden bağımsız işlem sonucu),
  `rapor.py` (Excel), `webapp/` (FastAPI yükleme ve gözden geçirme arayüzü),
  `cli.py` (komutlar: fontlar, veri, gercekveri, theveri, satirpaketi, referans,
  rapor, disaaktar, model-kur, webapp).
- `colab/` — `01_sentetik_veri.ipynb` (T-H-E harmanlama dahil), `02_trocr_finetune.ipynb`,
  `03_qwen_vl_qlora.ipynb`, `04_puanlayici_ft.ipynb`.
- `tests/` — 50 test.

## 6. TEKNİK KARARLAR / TUZAKLAR (kod tabanı dışı, bilmen gereken)

- **`transformers<5` ŞART** (pyproject `htr` extra'sında sabit). transformers 5.x TrOCR
  tokenizer'ını yükleyemiyor ("Couldn't instantiate the backend tokenizer"). 4.57.6 çalışıyor.
- Gerçek TrOCR base ile uçtan uca test edildi: fine-tune'suz bile simüle "mitokondri"/
  "kloroplast" doğru okundu (cihaz mps). Yani PyTorch boru hattı sağlam.
- Türkçe tuzakları: **ı/İ büyük-küçük**, **NFC**, **cmap font doğrulama** (bazı el yazısı
  fontları ğ/İ/ş'yi sessizce atlar). T-H-E'de **i≠ı, I≠İ ayrık sınıflar** (haritada doğru).
- Kod incelemesi 12 bulgu bulundu ve GİDERİLDİ (regresyon testleri var): rubrik ret güveni
  min/max, mürekkep-var-tanıma-boş→incele, mükerrer sayfa puan çiftlenmesi, YAML sayısal
  cevap str zorlaması, kısa rubrik kalemi alt-dize yanlış pozitifi, homografi köşegen şartı vb.
- git: 3 commit (`23fd775`, `9444313`, `1174fc9`). `main` dalı. Remote YOK (yalnız yerel).
- Colab defterlerindeki font indirme URL'leri (15 OFL) erişilebilir doğrulandı (200).

## 7. SENİN İÇİN SIRADAKİ ADIMLAR (öneri)

1. **Öncelik:** T-H-E gerçek verisiyle Keras CNN karakter tanıyıcıyı repoya kalıcılaştır
   (`scratchpad/cnn_karakter.py` → `colab/05_keras_cnn_karakter.ipynb`) ve Colab'da çalıştır.
   Sentetik veri EKLEME (kullanıcı tercihi).
2. Karakter CNN'i sisteme bir **Keras `Taniyici` backend'i** olarak bağla
   (`sinav_okur/htr/keras_cnn.py`): kutu kırpıntısı → karakter segmentasyonu → CNN → metin.
   Satır/kelime için karakter segmentasyonu (bağlı bileşen / dikey projeksiyon) gerekir.
3. Kağıt satır/kelime doğruluğu için gerçek veri toplama planı: kullanıcının kendi
   kâğıtları → `sinav-okur disaaktar` flywheel'i (tek gerçekçi yol; alan-özel gerçek veri yok).
4. Kullanıcı isterse: `denizdoktur/turkish-handwritten-ocr` gerçek CRNN+CTC ağırlıklarını
   satır-HTR transfer/pseudo-labeling için değerlendir.
5. Codex kuralı (kullanıcının global talimatı): **kod önerini körü körüne uygulama; diff'i
   önce göster, mantığını doğrula, sonra uygula.**

## 8. HIZLI ÇALIŞTIRMA

```bash
cd ~/Developer/sinav-okur
uv sync --extra dev            # çekirdek + test
uv run pytest -q               # 50 test
uv run sinav-okur --help       # komutlar
uv run sinav-okur gercekveri --listele   # bilinen HF setleri (hepsi eval/sentetik)
# T-H-E gerçek veri:
git clone https://github.com/bartosgaye/thedataset && cd thedataset && git lfs install && git lfs pull
```

Colab CNN eğitim kodu: `scratchpad/cnn_karakter.py` (T-H-E git-lfs → gri 28×28 CNN → eğit).
```
