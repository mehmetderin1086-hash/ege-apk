# Kör sayım kuralları — "bir soru" neyi sayar?

**Amaç:** sayım-altını (`soru-kesici.golden-count/v1`) belgeden belgeye ve
sayıcıdan sayıcıya **tutarlı** olsun. Kural yazılı değilse aynı sayfa iki farklı
sayı alır ve kapı gürültü üretir; daha kötüsü, motor doğruyken altın yanlış olur.

## Değişmez kural: KÖR sayım

Sayan kişi/ajan **motorun kutularını GÖRMEZ**. Yalnız `--hazirla` ile üretilmiş
**çıplak render**'a bakar. Motorun çıktısına bakarak sayım yapmak ölçümü
motorun hatasına kör bırakır — altın veri sözde etikete dönüşür.

## Bir soru sayılır

Öğrencinin **cevaplaması gereken**, kendi başına kesilip bir soru bankasına
konabilecek her madde:

* çoktan seçmeli soru (gövde + şıklar);
* açık uçlu / boşluk doldurma sorusu;
* doğru-yanlış maddesi (`( ... ) 20. Taşıma yavaştır.` gibi her satır **ayrı**
  bir sorudur);
* eşleştirme sorusunun **her bir maddesi** (eşleştirilecek liste değil, sorulan
  madde);
* çözüm kitabında **her bir çözüm bloğu** (`Soru 7 :` … ) — çözüm kitabında
  kesilen birim çözümdür;
* aynı uyaranı paylaşan sorular **ayrı ayrı** sayılır (paylaşılan metin/şekil
  bir kez, sorular kaç taneyse o kadar).

## Bir soru SAYILMAZ

* etkinlik/çalışma yönergesi ("Raporunuzu arkadaşlarınızla paylaşınız",
  "Aşağıdaki soruları dikkatle okuyunuz") — numaralı olsa bile;
* **paylaşılan uyaran**: soruların ortak metni, tablosu, grafiği ya da
  eşleştirme gridi (a) … o) kutucukları) — bunlar soru değil, girdi;
* konu anlatımı, örnek/çözümlü örnek gösterimi (soru olarak sorulmuyorsa);
* içindekiler, kapak, ünite başlığı, kazanım listesi;
* cevap anahtarı satırları (cevap anahtarı sayfasının rolü
  `cevap_anahtari`, `question_count = 0`);
* sayfa altbilgisi, kenar notu, QR kod kutuları.

## Sınır durumları

| Durum | Karar |
|---|---|
| Soru sayfanın altında başlayıp diğer sayfada bitiyor | **Başladığı** sayfada sayılır, devam ettiği sayfada sayılmaz |
| Bir soru gövdesi + a/b/c alt şıkları (tek cevap isteniyor) | **1** soru |
| Bir gövde + "a) … b) … c) …" **ayrı ayrı cevaplanacak** alt sorular | Alt soru kadar (a, b, c → 3) |
| Numaralar sayfa içinde sıfırlanıyor (iki test yan yana) | Toplam adet sayılır; `question_numbers` alanına gerçek numaralar yazılır |
| Numara okunamıyor / yok | `question_count` yine sayılır, `question_numbers: null` |
| Sayfa tamamen konu anlatımı | `question_count: 0`, `role: "konu"` |
| Ders kitabı sayfası (Campbell gibi), soru yok | `question_count: 0`, `role: "konu"` |

`question_numbers` verilirse **uzunluğu `question_count` ile eşit olmak
zorundadır** (`--kilitle` bunu denetler).

## Hakemlik (zorunlu)

Motorun sayısı ile altın arasındaki fark **> 3** olan her sayfa **ikinci kez,
yine kör** sayılır. Bugüne kadar tek geçişli sayıldı ve bu, yanlış bir altının
kalıcı kapı gürültüsüne dönüşmesi riskini taşıyor. İkinci sayımda:

* iki sayım aynıysa → altın kesinleşir, `verifier` alanına iki kayıt yazılır;
* farklıysa → sayfa `notes` alanına gerekçe yazılır ve **insan** karar verir;
  karara varılamıyorsa sayfa altından **çıkarılır** (yanlış altın, altın
  olmamasından kötüdür).

## Akış

```bash
.venv/bin/python altin_sayim.py --belge <ad> --hazirla --sayfalar 25 41 61 85
#   → kalite/altin_onizleme/<ad>_sayim/ciplak_s<no>.png  (motor kutusu YOK)
#   → kalite/altin_sayim_taslak/<ad>.json  (question_count/role null)
# ... çıplak render'lara bakılır, taslak doldurulur, verifier yazılır ...
.venv/bin/python altin_sayim.py --belge <ad> --kilitle
.venv/bin/python altin_sayim.py --belge <ad> --olc
```
