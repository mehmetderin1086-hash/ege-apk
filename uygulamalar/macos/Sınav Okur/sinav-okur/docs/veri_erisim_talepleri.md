# Gerçek Türkçe el yazısı veri erişim talepleri

Son doğrulama: 2026-07-23

Bu belgeler veri sahibine gönderilmek üzere hazırlanmış taslaklardır; henüz e-posta
gönderilmemiştir. Öğrenci adı, numarası veya sınav notu istenmez. İstenen paket
yalnız anonim yazar kodu, satır görüntüsü, doğru transkripsiyon ve kullanım iznidir.

## 1. Sabancı/Bilkent — 2.641 satır, 73 yazar

Kaynak: Fırat Kızılırmak, *Offline Handwriting Recognition Using Deep Learning
with Emphasis on Data Augmentation Effects* (2022).

- Tezde bildirilen resmî bölmeler: train 1.930 satır/44 yazar, test 711 satır/29
  yazar; aynı yazar iki bölmede bulunmuyor.
- Tezde verilen `https://github.com/firatkizilirmakk/handwriting-recognition`
  bağlantısı 23 Temmuz 2026 itibarıyla 404 döndürüyor.
- `selimfirat/bilkent-turkish-writings-dataset` adlı Hugging Face kaydı bu set
  değildir: yalnız dijital metin korpusudur; görüntü ve yazar kodu içermez.
- İletişim için tez danışmanı: `berrin.yanikoglu@sabanciuniv.edu`.

Konu: `2,641-line Turkish handwriting dataset — academic access request`

> Sayın Prof. Dr. Berrin Yanıkoğlu,
>
> Fırat Kızılırmak'ın 2022 tarihli tezinde tanımlanan 2.641 satırlık, 73 yazarlı
> Türkçe çevrimdışı el yazısı veri setini, yalnız akademik/özel araştırma amaçlı
> bir Türkçe sınav okuma modelinin yazar-ayrık CTC eğitimi ve değerlendirmesinde
> kullanmak istiyoruz. Tezde verilen GitHub deposu şu anda erişilemiyor.
>
> Uygunsa şu öğeleri paylaşabilir misiniz: (1) satır görüntüleri, (2) satır
> transkripsiyonları, (3) anonim yazar kimlikleri, (4) tezdeki resmî train/test
> bölmeleri ve (5) model eğitimi, türetilmiş ağırlıkların özel kullanımı ve
> sonuçların yayımlanması için izin/lisans koşulları?
>
> Ham görüntüleri yeniden dağıtmayacağız; doğrudan kimlik bilgilerini
> saklamayacağız; resmî test yazarlarını eğitim veya eşik ayarında
> kullanmayacağız. İsterseniz veri kullanım sözleşmesi imzalayabiliriz.
>
> Teşekkür ederiz.

## 2. Dokuz Eylül — gerçek programlama sınavlarından 7.093 karakter

Kaynak: Barış Kılıçlar ve Metehan Makinacı, *Recognition of Handwritten Source
Code Characters With Deep Neural Networks* (2019),
DOI `10.36287/setsci.4.6.111`.

- Makale 116 gerçek sınav görselinden 7.093 etiketli karakter bildiriyor ve sınıf
  listesinde `ÇİĞÖŞÜçığöşü` bulunuyor.
- Yayımlanmış karakter görüntüsü, yazar kimliği veya açık veri lisansı bulunamadı.
- Makaledeki iletişim adresleri: `metehan.makinaci@deu.edu.tr` ve
  `bariskiliclar@gmail.com`.

Konu: `7,093-character Turkish exam handwriting dataset — research access request`

> Sayın Dr. Metehan Makinacı ve Barış Kılıçlar,
>
> 2019 tarihli çalışmanızda oluşturduğunuz, 116 gerçek C programlama sınavından
> çıkarılmış 7.093 etiketli karakterlik veri setini Türkçe sınav el yazısı tanıma
> araştırmasında değerlendirmek istiyoruz.
>
> Uygunsa şu öğeleri ve koşulları paylaşabilir misiniz: (1) kırpılmış karakter
> görüntüleri ve etiketleri, mümkünse kaynak satır/sayfa görüntüleri ile
> transkripsiyonları, (2) kişisel bilgi içermeyen anonim yazar kodları, (3)
> train/test bölmeleri ve (4) akademik/özel model eğitimi ile türetilmiş model
> ağırlıklarının kullanımı için yazılı izin/lisans?
>
> Ham sınav görüntülerini yeniden dağıtmayacağız; öğrenci adı/numarası/notu
> istemiyoruz; yazar-ayrık değerlendirme uygulayacağız. Gerekirse veri kullanım
> sözleşmesi imzalayabiliriz.
>
> Teşekkür ederiz.

## Teslim paketi sözleşmesi

Veri geldiğinde beklenen `labels.jsonl` biçimi:

```json
{"image":"img/w001_0001.png","text":"Çözelti sıcaklığı arttı.","writer_id":"w-001","split":"train"}
```

- `writer_id` anonim ve sabit olmalı; ad, e-posta ve öğrenci numarası olmamalı.
- Kaynağın resmî test bölmesi varsa aynen korunmalı.
- Bütün görüntüler paket dizini içinde olmalı.
- Yazılı izin/lisans kanıtı ayrı dosya olarak bulunmalı.

Doğrulama ve standartlaştırma:

```bash
uv run sinav-okur satirpaketi paket/labels.jsonl \
  -o gercek_satir_verisi \
  --lisans "İzin metnindeki tam kapsam" \
  --izin-belgesi paket/IZIN.pdf \
  --kaynak-url "çalışmanın veya veri kaydının kalıcı URL'si"
```

Ardından `gercek_satir_verisi` ziplenip Colab'daki
`06_keras_ctc_gercek_satir.ipynb` ile eğitilir. Defter, girdideki resmî test
bölmesini korur; test yazarlarını eğitim/validation için yeniden bölmez.
