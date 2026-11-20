# TrOCR Türkçe ince ayarı — tanı notu (2026-07-24)

Colab A100'de başarısız turların ardından başlangıç kimliği ve kayıp hizalaması
düzeltildi. Sentetik veri için kullanılabilir model üretildi ve yerel programa
kuruldu.

## Sonuçlar

| Tur | Veri | LR / epoch | Doğrulama kaybı | CER |
|-----|------|-----------|-----------------|-----|
| v1 | 30k satır, 6346 benzersiz, rastgele bölme | 1e-4 / 2 | 3.5e-06 | 1.297 |
| v1b | aynı | 4e-5 / 5 | 3.5e-06 | 0.534 |
| v2 | 40k satır, 40k benzersiz, metin-ayrık bölme | 4e-5 / 4 | 0.0024 | 0.956 |
| v3 | v2 verisi + etiket hizalaması düzeltilmiş | 5e-5 / 6 | 0.0017 | 0.870 |
| v4 | v2 verisi + checkpoint start=2 + açık CE | 4e-5 / 4 | — | **0.000** |

CER 1.0 ≈ üretilen metin gerçek metin kadar hatalı; kabul edilebilir sınır 0.1.

## Kanıtlanan iki kusur (düzeltildi)

1. **Ezber + veri sızıntısı (v1).** 30k satırda yalnız 6346 benzersiz cümle
   vardı ve rastgele bölme yüzünden test cümlelerinin %83'ü eğitimde de yer
   alıyordu. Doğrulama kaybının 3e-06 olması bu yüzden sahteydi. Düzeltme:
   `korpus_uret(benzersiz=True)`, genişletilmiş şablon havuzu, `metin_ayrik_bol`.
2. **Yanlış `decoder_start_token_id`.** Checkpointin üretim yapılandırması `2`
   beklerken eski eğitim hücresi hem model hem üretim başlangıcını tokenizer
   `cls_token_id=0` yapıyordu. Düzeltme: checkpoint değeri `2` korunuyor.

## Çözülen çekirdek sorun

Eski koşularda **teacher-forcing kusursuz, serbest üretim bozuk** görünüyordu:

```
teacher-forcing : 'Bu yapı DNA adını alır'        (birebir doğru)
greedy          : 'Buap DNAı adn alr'
                  'lizozom sinaps genotip' -> 'loz sin genip'
                  'mayoz görevini yapar'   -> 'may grev yar'
```

Kök neden, checkpointin `2` başlangıcını `0` ile değiştirmek ve ardından
Transformers'ın örtük kaydırma/kayıp yoluna güvenmekti. Düzeltilmiş eğitim:

- decoder girişini açıkça `[2] + labels[:-1]` kurar;
- pad konumlarını `-100` ile maskeler;
- aynı konumdaki logit/etiket çiftlerine doğrudan çapraz entropi uygular;
- üretimde de checkpointin `decoder_start_token_id=2` değerini kullanır.

### Elenen hipotezler

- Görüntü sıkışması: satırlar 434×85 px, harf başına ~15.6 px — TrOCR için normal.
- Beam / `no_repeat_ngram` ayarları: greedy'de de aynı bozulma.
- KV önbelleği: `use_cache=False` ile sonuç değişmiyor.
- Başlangıç token'ı: hem `[<s>]` hem `[<s>,<s>]` ile üretim bozuk (farklı biçimde).
- Öğrenme oranı / epoch sayısı: 1e-4 ve 4e-5, 2–5 epoch denendi.

## Bulunan üçüncü kusur: etiket hizalaması (doğrulandı)

Etiketler `tokenizer(text).input_ids` ile üretiliyordu ve başta `<s>` taşıyordu;
`VisionEncoderDecoderModel` buna bir `decoder_start_token_id` daha ekleyerek
kaydırdığı için kodçözücü girişi **çift `<s>`** ile başlıyor, `generate` ise tek
`<s>` ile başlıyordu — üretim bir pozisyon kayıyordu.

Kontrollü deney (aynı veri, aynı ölçüm; yalnız etiketleme farklı):

| Etiketleme | Eğitim örneği | Epoch | CER |
|------------|---------------|-------|-----|
| `input_ids` (baştaki `<s>` var) | 38.800 | 4 | 0.956 |
| `input_ids[1:]` (`<s>` yok) | **6.000** | 3 | **0.768** |

6,5 kat az veriyle belirgin daha iyi sonuç → hizalama kusuru doğrulandı.
Düzeltme `colab/08_trocr_tek_gecis.ipynb` içindeki `donustur`'a işlendi.

## v4 sonucu

Etiket hizalaması düzeltilmiş tam eğitim (38.800 örnek, 6 epoch, lr 5e-5):

| Epoch | 1 | 2 | 3 | 4 | 5 | 6 |
|-------|---|---|---|---|---|---|
| CER | 1.114 | **0.870** | 1.092 | 1.108 | 1.160 | 1.106 |

Doğrulama kaybı 0.0017'ye inerken CER iyileşmedi. Yani hizalama gerçek bir
kusurdu ama tek başına belirleyici değilmiş.

| Epoch | 1 | 2 | 3 | 4 |
|-------|---|---|---|---|
| CER | 0.01148 | 0.0005725 | **0.0000000** | 0.0000498 |

En iyi üçüncü epoch modeli `modeller/trocr-tr/` altına kuruldu.
`model.safetensors` 1.335.747.032 bayt; `config.json` ve
`generation_config.json` içinde başlangıç kimliği `2`. ZIP bütünlük testi ve
TrOCR/topluluk testleri geçti.

## Geçerlilik sınırı

Bu CER, 15 Türkçe-tam el-yazısı fontundan üretilen 1.200 metin-ayrık sentetik
satırda ölçüldü. Gerçek sınav, defter ve tıbbi notlarda %100 doğruluk iddiası
değildir. Sonraki kalite kapısı, izinli gerçek satırların yazar-ayrık
benchmarkıdır; sentetik sonuç yalnız ön-eğitim ve entegrasyon kanıtıdır.

## Bu arada üretim davranışı

Türkçe model `modeller/trocr-tr/` altında bulunduğunda topluluk OCR bunu
otomatik kullanır. Model kaldırılırsa İngilizce taban TrOCR'a dönülür ve güven
0.75 ile sönümlenir (`sinav_okur/ocr.py`).
