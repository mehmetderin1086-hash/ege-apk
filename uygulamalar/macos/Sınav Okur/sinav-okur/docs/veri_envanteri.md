# Gerçek el yazısı veri envanteri

Son doğrulama: 2026-07-23

Bu envanter “internette bulunuyor” ile “model eğitiminde kullanılabilir” ayrımını
korur. İndirme bağlantısı bulunması; açık lisans, transkripsiyon veya yeniden
dağıtım izni bulunduğu anlamına gelmez.

| Kaynak | Gerçek | Düzey | Erişim/lisans | Karar |
|---|---:|---|---|---|
| [T-H-E Version VI](https://github.com/bartosgaye/thedataset) | Evet | README/makale 78.000 der; yayımlanan dosya 76.000/76 sınıf, büyük `Ç` ve `Ş` yok | [Makale](https://acta.uni-obuda.hu/EdibogluBartos_Hoscan_Kauer_Hajnal_106.pdf) `public-domain/free-to-use` ifadeleri içeriyor; depo açık SPDX lisansı yayımlamıyor | LicenseRef + atıf; izin doğrulanana kadar özel kullanım; yeniden dağıtma yok; 29 casefold sınıfı eğit |
| [Dokuz Eylül kaynak kodu sınavları](https://doi.org/10.36287/setsci.4.6.111) | Evet | 116 gerçek sınav görselinden 7.093 karakter; Türkçe `ÇŞçş` dahil | Makale açık; karakter verisi yayımlanmamış | Yazarlardan veri/izin gelirse değerli tamamlayıcı kaynak |
| [Azeri HTR pilotu](https://huggingface.co/ismatsamadov/azeri_handwriting_detection) | Evet | 12 belge/80 satır; tıbbi form dahil | MIT model deposu; kartta görüntüler anlatılıyor fakat depoda görüntü dosyaları yok | Şu hâliyle eğitim girdisi değil; yalnız kaynak adayı |
| [Kızılırmak Türkçe satırları](https://research.sabanciuniv.edu/id/eprint/47179/1/10483904.pdf) | Evet | 2.641 satır, 73 yazar; resmî train 1.930/44, test 711/29 | Tezin verdiği `firatkizilirmakk/handwriting-recognition` deposu 23.07.2026'da 404; görüntüler alınamadı | Yazardan görüntü+transkripsiyon+yazar kodu+izin istenecek |
| [Bilkent Turkish Writings (HF)](https://huggingface.co/datasets/selimfirat/bilkent-turkish-writings-dataset) | Hayır; metin | 9.119 dijital yazı; yalnız `text` kolonu | Academic Use Only; görüntü ve `writer_id` yok | HTR/CTC verisi değildir; dil modeli/korpus olabilir |
| [Kabakus–Erdoğmuş](https://doi.org/10.1002/cpe.6429) | Evet | 25.875 harf | Yazardan makul talep üzerine | İzin sonrası değerlendir |
| [KTÜ 2024](https://thesis.rawdatalibrary.net/thesis/derin-ogrenme-yontemleri-turkce-el-yazs-tanma) | Evet | 400 yazar, karakter | Tüm hakları saklı | Kullanma |
| [Türkçe Satır Bölümleme](https://dergipark.org.tr/tr/download/article-file/3874269) | Evet | 1.610 sayfa, 183 yazar | İndirme bulunamadı; tam transkripsiyon değil | Yalnız bölümleme için izin sonrası |
| [Sinecen–Göçer](https://doi.org/10.2139/ssrn.6993518) | Evet | 365 satır, 15 yazar | Kontrollü erişim | Erişim sonrası |
| [Sakarya aynı metin](https://www.kaggle.com/datasets/emrahaydemr/handwriting-same-text-image/data) | Evet | 3.250 görüntü, tek ifade | Kaggle lisansı `Unknown` | İzin olmadan eğitim yok |
| [FutureBeeAI Türkçe notlar](https://www.futurebeeai.com/dataset/ocr-dataset/turkish-sticky-notes-ocr-image-dataset) | Evet | 2.000+ görüntü | Ticari, transkripsiyon yok | Satın alma ve etiketleme kararı kullanıcıya ait |
| [MathWriting human](https://github.com/google-research/google-research/tree/master/mathwriting) | Evet | 230 bin çevrimiçi matematik ifadesi | Açık araştırma seti | Denklem/formül alt modeli için; Türkçe metin modeli değil |
| [ICDAR NoTeS-Bank](https://rrc.cvc.uab.es/?ch=33) | Evet | 2.000+ bilimsel not sayfası | Yarışma koşulları; tam satır transkripsiyonu değil | Düzen/anlama benchmarkı |
| [Mendeley sınavları](https://data.mendeley.com/datasets/sf3kvjwknt/1) | Evet | 50 Data Science sınavı | CC BY 4.0 | Sayfa/puanlama benchmarkı; Türkçe HTR eğitimi değil |
| [Turkish Medical Notes](https://huggingface.co/datasets/AhmetSemih/Turkce-Tip-Notlari) | Hayır; metin | Tıbbi metin | CC BY-NC 4.0 | Sözlük/dil modeli; görsel HTR eğitimi değil |

## Kabul kuralları

Bir örnek eğitime ancak aşağıdaki koşulların tamamında girer:

1. İnsan tarafından gerçekten yazılmıştır.
2. Görüntü ile insan-doğrulanmış transkripsiyon eşleşir.
3. Kullanım izni/lisansı kayıtlıdır.
4. Doğrudan öğrenci kimliği eğitim manifestine girmez.
5. `writer_id` vardır ve train/validation/test yazarları kesişmez.
6. Test kümesi eğitim ve eşik ayarı sırasında kullanılmaz.

İzinli bir satır paketi geldiğinde önce `satirpaketi` kapısından geçirilir:

```bash
uv run sinav-okur satirpaketi gelen/labels.jsonl \
  -o gercek_satir_verisi \
  --lisans "Yazılı akademik model eğitimi izni" \
  --izin-belgesi gelen/IZIN.pdf \
  --kaynak-url "https://research.sabanciuniv.edu/id/eprint/47179/"
```

Komut görüntü yollarını, anonim `writer_id` değerlerini, varsa resmî
`train/validation/test` bölmelerindeki yazar sızıntısını ve izin belgesinin SHA-256
özetini doğrular. Çıktıdaki `manifest.json`, `ÇĞİÖŞÜçğıöşü` kapsamını ve her
görüntünün özetini kaydeder. İzin belgesinin kendisi veri paketine kopyalanmaz.

T-H-E yazar kimliği yayımlamadığı için onun sample-random testi yalnız karakter
benchmarkıdır; ürün metriği değildir. İndirilen `version6.csv` SHA-256 değeri
`83cc4140456d83e664448ba722fae0b9885444c90bf6adee6a47234f9b287440`
olarak doğrulanmıştır. `version1.csv` de ayrıca doğrulandı: o da iddia edilen
156.000/78 yerine 152.000/76 sınıftır ve aynı iki etiketi içermez. Bu bir kaynak
bütünlüğü kusurudur; sentetik `Ç/Ş` üretilmez.

## Başarı ölçütü

- Ham metin: CER ve WER.
- Türkçe: `i/ı/İ`, `s/ş`, `g/ğ`, `o/ö`, `u/ü`, `c/ç` karışıklıkları.
- Ürün: otomatik kabul edilen örneklerde CER ≤ %1 ve bunun kapsama oranı.
- Düşük güvenli veya model yollarının anlaşamadığı cevaplar insan incelemesine gider.

23 Temmuz 2026 dik-eksenli ve ürün ön işlemesiyle eşleşen gerçek Colab koşusu:
29 casefold sınıfta ham test doğruluğu %97,2321; güven eşiği 0,9374898 ile
otomatik kabul edilen 5.380/5.600 örnekte %99,0149 doğruluk ve %96,0714 kapsama.
Bu sonuç yazar-ayrık olmadığı için yalnız T-H-E karakter kapısıdır; sınav/satır
CER iddiası değildir.

Teknik bütünlük notu: upstream CSV görüntüleri sütun-major düzleştirilmiştir.
`reshape(28,28)` tek başına glifleri transpoze/yatık üretir. Ürün hattı eksenleri
`.T`/`transpose(0,2,1)` ile dik konuma getirir ve eğitimle çıkarımda aynı sıkı
kırpma + 24 piksel merkezleme dönüşümünü kullanır.
