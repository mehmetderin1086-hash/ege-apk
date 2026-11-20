# Öğretmen Çantası

Biyoloji öğretmeni için yerel çalışan ders planı, not defteri, yoklama ve sınav
programı. Veriler bilgisayardan çıkmaz; internet gerekmez.

Masaüstündeki **Öğretmen Çantası** simgesine çift tıklayın — bağımsız ARM64
uygulama paketi yerel bir sunucu başlatır ve tarayıcıda açılır. Kaynak klasörü
ve geliştirme sanal ortamı çalışma anında gerekli değildir. İkinci kez
tıklarsanız yeni sunucu açmaz, var olan sekmeyi öne getirir.

## Ne yapar

| Modül | Ne işe yarar |
|---|---|
| **Bugün** | O günkü dersler sırayla; her dersin yanında yoklama, ders planı ve not girişi. Devamsızlık sınırına yaklaşan öğrenciler uyarı olarak görünür. |
| **Yıllık plan** | 2024 Maarif Modeli programından ünitelendirilmiş yıllık plan üretir. Tema saatlerini kazanımlara dağıtır, tatil haftalarını atlar. PDF (MEB tablosu ve tema tablosu), Word ve Excel çıktısı verir. |
| **Günlük plan** | O haftanın kazanımından süre bölümlü ders akışı: dikkat çekme, köprü kurma, işleniş, etkinlik, ölçme, kapanış. Metinler resmî programdan gelir. |
| **Yoklama** | Sesle: kaydı başlatıp yalnız gelmeyenleri söylersiniz, kalan herkes var sayılır. Onay ekranından geçmeden kaydedilmez; tek tık listesi her zaman açıktır. |
| **Notlar** | e-Okul kurallarına göre dönem ve yıl sonu puanı. Kişisel iç takip kayıtları (katılım, ödev) resmî ortalamaya girmez. |
| **Sınavlar** | Yalnız açık uçlu soru. Kazanım dağılımını siz verirsiniz, program belirtke tablosu üretir; A/B grubu ve cevap anahtarı çıkarır. |
| **Kazanım analizi** | Soru bazlı puanlardan öğrenci ve sınıf ısı haritası; sınıfça zayıf kazanımları işaretler. |
| **Denemeler** | YKS biyoloji netleri; yayınevi sonuç dosyasından ya da elle. Gelişim grafiği. |
| **Materyaller** | Sunum, video ve çalışma yaprağı arşivi, kazanım koduna bağlı. |
| **Kaynaklı yardımcı** | Müfredat ve yerel biyoloji kaynaklarına dayanarak ders, soru/rubrik ve telafi taslağı önerir. Kaynak ve öğretmen onayı olmadan resmî kayıt değiştirmez. |
| **Entegrasyonlar** | Soru Kesici'den soru, Sınav Okur'dan öğretmen onaylı soru puanı alır; sınav paketini Sınav Okur'a yollar. |

## Müfredat verisi

Resmî **Türkiye Yüzyılı Maarif Modeli Biyoloji Dersi Öğretim Programı (2024)**
PDF'inden bir kez çıkarılıp `veri/mufredat_maarif_2024.json` olarak depoya
işlendi: 4 sınıf düzeyi, 8 tema, 78 öğrenme çıktısı ve süreç bileşenleri,
içerik çerçevesi, anahtar kavramlar, ölçme önerileri, öğrenme-öğretme
yaşantıları. Program çalışırken PDF'e ihtiyaç duymaz.

Belge yeniden yayımlanırsa:

```
.venv/bin/python scripts/mufredat_cikar.py --pdf veri/kaynak/biyoloji_2024.pdf
```

Çıkarım, PDF'teki sayılarla otomatik karşılaştırılır (kazanım sayısı, tema
saatleri, boş alan denetimi); uyuşmazlık varsa betik hata koduyla döner.

Müfredatın resmî kaynak künyesi `veri/mufredat_kaynaklari.json`, hangi öğretim
yılında hangi sınıfın hangi programı kullanacağı ise
`veri/mufredat_gecerlilik.json` içinde tutulur. Belgenin programda bulunması,
tek başına o sınıfta yürürlükte olduğu anlamına gelmez.

### 12. sınıf

Maarif Modeli kademeli geçişte 2026-2027'de **9, 10 ve 11. sınıflarda**
uygulanıyor; **12. sınıf 2018 programıyla** devam ediyor. Program iki müfredatı
birden taşır: her şube bir müfredat sürümüne bağlanır. 2018 programı ünite/
kazanım düzeninde olduğundan mevcut çıkarım betiği onu ayrıştıramaz (`--surum`
bayrağı bunu açıkça reddeder); belge geldiğinde ayrı bir ayrıştırıcı yazılıp
`veri/mufredat_mfp_2018.json` üretilecek. O zamana kadar 12. sınıfta plan
üretimi kapalıdır; not, yoklama, sınav ve deneme modülleri çalışmaya devam eder.

## Geliştirme

```
uv sync --extra dev      # ortamı kur
make kontrol             # ruff + pytest
make sunucu              # http://127.0.0.1:8040
make kur-app             # masaüstü uygulamasını yeniden paketle ve imzala
```

**Program güncellendikten sonra çalışan sunucuyu kapatın:**

```
.venv/bin/ogretmen-cantasi durdur
```

Başlatıcı, portta zaten bu program çalışıyorsa yeni sunucu açmaz — normalde
doğru davranış, ama kod değiştiğinde eski sürüm çalışmaya devam eder. Şablonlar
diskten okunduğu için yeni şablonla eski kod karışabilir ve sayfa hata verir.
`durdur` komutundan sonra `.app`'e yeniden tıklamak yeter.

Veriler `~/Library/Application Support/OgretmenCantasi/` altında tutulur
(`OGRETMEN_CANTASI_VERI` ile değiştirilebilir). Her sunucu oturumunda ve şema
geçişinden önce SQLite bütünlüğü doğrulanmış yedek alınır; son 30 kopya
saklanır. “Tüm yılı dışa aktar” paketi de canlı WAL dosyasını kopyalamak yerine
tutarlı SQLite anlık görüntüsü üretir.

Sesli yoklama, KitapKatalog için derlenmiş whisper.cpp kurulumunu yeniden
kullanır; bulunamazsa modül kapanır ve tek tık listesi çalışmaya devam eder.
Yollar `OGRETMEN_WHISPER_SERVER`, `OGRETMEN_WHISPER_MODEL`, `OGRETMEN_FFMPEG`
ile değiştirilebilir.

## Yerel uygulama protokolü

Öğretmen Çantası, Soru Kesici, Sınav Okur ve Biyo Çözücü arasında `v1`
protokolü kullanılır. Her uygulama `/api/v1/health` ve
`/api/v1/capabilities` uçlarını sunar. Uçlar yalnız loopback adresinde ve
Öğretmen Çantası'nın kullanıcı izinli veri dizininde ürettiği yerel Bearer
belirteciyle çalışır.

- Soru paketleri `manifest.json + görseller` ZIP'idir.
- Sınav paketi soru anlık görüntülerini, rubrikleri ve öğrenci dış kimliklerini taşır.
- Sonuç paketi yalnız öğretmen tarafından onaylanmış kâğıtların soru puanlarını taşır.
- Aynı dış kimlik ve SHA-256 ile gelen paket ikinci kez uygulanmaz.
- Kardeş uygulama kapalıysa ZIP indirme/yükleme yolu çalışmaya devam eder.

Port aralığı **8040-8050**. Kardeş programlar: 8000 PDF Studio, 8000-8010 Sınav
Okur, 8010 SesLab, 8020-8030 Soru Çözücü, 8317 CLI Proxy, 8766 BioProf.
