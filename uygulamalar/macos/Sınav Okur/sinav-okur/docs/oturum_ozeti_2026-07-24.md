# Oturum özeti — 24 Temmuz 2026

Konu: TrOCR'ı diğer OCR motorlarıyla birlikte kullanmak ve Türkçe el yazısı için
ince ayar yapmak.

## Kısa sonuç

| Hedef | Durum |
|-------|-------|
| TrOCR'ı topluluk OCR'a katmak | **Tamamlandı**, çalışıyor |
| Modeli tek komutla kurulabilir yapmak | **Tamamlandı** |
| Sentetik veri hattındaki kusurları gidermek | **Tamamlandı** (3 kusur) |
| Türkçe ince ayarlı TrOCR modeli üretmek | **Tamamlandı** — sentetik test CER 0.000 |

Başarılı model `modeller/trocr-tr/` altına kuruldu; topluluk OCR ve
`--taniyici trocr` bunu otomatik kullanıyor.

## 1. Altı motorlu topluluk OCR

Serbest sınav okuma akışı artık altı motoru satır düzeyinde uzlaştırıyor:
Apple Vision, Tesseract, EasyOCR, PaddleOCR PP-OCRv5, Surya ve **TrOCR**.

TrOCR yalnız tanıma yapar, sayfada satır bulamaz. Bu yüzden `_trocr_ocr`, öncü
motorun (Vision, yoksa ilk başarılı motorun) satır kutularını kırpıp yeniden
okuyor ve aynı geometriyle topluluk oylamasına giriyor.

Sağlamlaştırmalar (code-review bulgularından):

- Model yüklemede kilitli singleton — eşzamanlı istekte çifte indirme ve MPS
  çakışması önlenir.
- Satır döngüsüne 420 sn süre bütçesi; aşılırsa o ana dek okunan bloklar yine
  topluluğa girer.
- İnce ayarlı Türkçe model yoksa İngilizce taban modelin güveni **0.75 ile
  sönümlenir** — akıcı İngilizce halüsinasyonun oylamayı kazanması engellenir.

Gerçek duman testi: Vision'ın `rnitokondn` diye okuduğu satırı TrOCR 0.996
güvenle `mitokondri` okudu; topluluk TrOCR'ı seçti.

## 2. Model kurulumu

Model iki yoldan bulunur: `SINAV_OKUR_TROCR_MODEL` ortam değişkeni ya da proje
kökündeki `modeller/trocr-tr/`. Colab'dan inen zip tek komutla yerine oturur:

```bash
sinav-okur model-kur ~/Downloads/trocr-tr.zip
```

Komut arşiv dışına yazmaya çalışan girdileri (zip-slip) reddeder ve model
dizinini kendisi bulur.

## 3. Sentetik veri hattında düzeltilen üç kusur

1. **Ezber + veri sızıntısı.** 30.000 satırda yalnız 6.346 benzersiz cümle
   vardı (10 sabit şablon × 117 terim) ve rastgele bölme yüzünden test
   cümlelerinin **%83'ü** eğitimde de yer alıyordu; doğrulama kaybının 3e-06
   olması bu yüzden sahteydi. Düzeltme: şablon havuzu 25'e çıkarıldı, rakam/ölçü
   kalıpları ve dil modeli kısayolunu kıran dilbilgisiz terim dizileri eklendi,
   `korpus_uret(benzersiz=True)` ve `metin_ayrik_bol` yazıldı.
   Benzersiz metin **6.346 → 20.873**.
2. **Yanlış başlangıç kimliği.** Checkpointin üretim yapılandırması
   `decoder_start_token_id=2` beklerken eski eğitim hücresi bunu tokenizer
   `cls_token_id=0` ile değiştiriyordu. Kayıp düşse de öğretmen-zorlamalı giriş
   ile serbest üretim bir konum kayıyordu.
3. **Örtük kayıp/kaydırma.** Transformers 4.57, bu yapılandırmada
   `ForCausalLMLoss` geri dönüşünü kullanıyordu. Düzeltilmiş hat, decoder
   girişini `[2] + labels[:-1]` olarak açıkça kuruyor ve çapraz entropiyi aynı
   konumdaki etiketlere karşı doğrudan hesaplıyor.

## 4. Eğitim sonuçları (Colab A100, dört tur)

| Tur | Veri | LR / epoch | Doğrulama kaybı | CER |
|-----|------|-----------|-----------------|-----|
| v1 | 30k satır, 6.346 benzersiz, rastgele bölme | 1e-4 / 2 | 3.5e-06 | 1.297 |
| v1b | aynı | 4e-5 / 5 | 3.5e-06 | 0.534 |
| v2 | 40k satır, 40k benzersiz, metin-ayrık bölme | 4e-5 / 4 | 0.0024 | 0.956 |
| v3 | v2 verisi + etiket hizalaması düzeltilmiş | 5e-5 / 6 | 0.0017 | **0.870** |
| v4 | v2 verisi + checkpoint start=2 + açık CE | 4e-5 / 4 | — | **0.000** |

v4 A100 koşusunda CER sırasıyla `0.01148`, `0.0005725`, `0.0000000` ve
`0.0000498` oldu. En iyi üçüncü epoch modeli kaydedildi. `lizozom sinaps
genotip`, `trombosit mitoz akciğer DNA karaciğer`, `mayoz görevini yapar`,
`peristaltik hareket görevini yapar` ve `hormon klorofil kas doku protein
sentezi` örnekleri birebir üretildi.

Bu sonuç 1.200 **sentetik font satırı** içindir; gerçek sınav, defter veya tıbbi
notlarda %100 anlamına gelmez. Gerçek kullanım iddiası için izinli,
yazar-ayrık, satır transkripsiyonlu veriyle ayrı benchmark gerekir.

## 5. Dosya değişiklikleri

- `sinav_okur/ocr.py` — TrOCR motoru, kilitli singleton, süre bütçesi, güven sönümü
- `sinav_okur/htr/trocr.py` — `yerel_model_yolu` ile model keşfi
- `sinav_okur/cli.py` — `model-kur` alt komutu
- `sinav_okur/veri/korpus.py` — genişletilmiş şablonlar, `benzersiz`, `metin_ayrik_bol`
- `sinav_okur/veri/sentetik.py` — `benzersiz_metin` seçeneği ve raporu
- `colab/08_trocr_tek_gecis.ipynb` — kendi kendine yeten defter (paket gömülü)
- `docs/trocr_egitim_tanisi.md` — ayrıntılı tanı notu
- Testler: 94 test, tümü geçiyor
