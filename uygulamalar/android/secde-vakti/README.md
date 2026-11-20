# Secde Vakti — 2.2.1

Kaynak kodu olmadan, mevcut 1.0.0 APK'sı üzerine yapılan kapsamlı 2.2.1 geliştirmeleri.
Yeni Android katmanı (`49` Java modülü) `classes3.dex` olarak eklendi; `DurumAktivitesi` tekil (`singleTask`) `MAIN/LAUNCHER` ana ekranı yapıldı, eski 1.0.0 `MainActivity` ekranına düşüş tüm giriş noktalarında kökten kapatıldı ve uygulamanın özgün zümrüt-altın cami logosu + hilal-yıldız durum çubuğu simgesi eklendi.
Dart kodunda (`libapp.so`) varsayılan tema renkleri "Mihrap" paletine yamandı (`arm64-v8a`, `armeabi-v7a`, `x86_64`).

## 2.2.1'de yeni: Özgün Uygulama Logosu + Eski 1.0.0 Ekranının Kökten Kapatılması & 81 İl Konum Motoru

- **Özgün Uygulama Logosu & Hilal-Yıldız Durum Çubuğu Simgesi (`simge_uret.py`, `Kanallar`)**: Varsayılan Flutter simgesi yerine Secde Vakti'nin `1024×1024` zümrüt-altın Ayasofya cami logosu tüm Android `mipmap` yoğunluklarına (`48`–`192 px`) gömüldü; bildirim durum çubuğuna keskin hilal-yıldız silüeti eklendi.
- **Tekil Başlatıcı Mimari (`manifest_duzenle.py`)**: `MAIN/LAUNCHER` filtresi eski `MainActivity`'den alınıp doğrudan `DurumAktivitesi` (`launchMode="singleTask"`) etkinliğine taşındı; çift görev kartı ve altta bekleyen eski ekran tamamen kaldırıldı.
- **Sıfır Sızıntı Yaşam Döngüsü Koruması (`SecdeUygulama`)**: Eski masaüstü kısayolları, `SELECT_NOTIFICATION` bildirim tıklamaları, `EK_DOGRUDAN` niyetleri veya süreç yenilemeleri eski `MainActivity`'yi tetiklese bile `0 sn` içinde `DurumAktivitesi`'ne yönlendirilip kapatılır.
- **Android 14/15/16 Tahminî Geri Hareketi Desteği (`OnBackInvokedCallback`)**: `targetSdk=36` üzerinde sistem geri kaydırma hareketinin `onBackPressed()` metodunu atlayıp etkinliği kapatarak alttaki eski ekranı açması engellendi (`Alt sayfa -> Vakitler -> Ana ekran`).
- **Yerel 81 İl + GPS Konum Seçici & 35 Günlük Otomatik Takvim/Alarm Motoru (`KonumVeTakvim`)**: Eski ekrana hiç ihtiyaç duymadan 81 Türkiye ili + dünya merkezleri arama, GPS ile konum güncelleme, 35 günlük vakit/hicrî/kıble takvimi tazeleme ve yerel `AlarmManager` vakit bildirimleri eklendi.

## Kurulum (telefon)

1. `surumler/secde_vakti_2.0.0.apk.zip` dosyasını aç veya doğrudan `.derleme/secde_vakti_2.0.0.apk` dosyasını telefona yükle (`adb install -r secde_vakti_2.0.0.apk`).
2. Telefonda farklı anahtarla imzalı eski bir sürüm kuruluysa önce onu kaldırıp 2.0.0 sürümünü kurun.

## 2.0.0'da yeni: Tema Stüdyosu, İbadet Takibi ve Kapsamlı İslâmî Entegrasyonlar

App Store ve Google Play'deki öncü İslâmî uygulamalar (**Pillars**, **Muslim Pro**, **Ezan Vakti Pro**, **Sajda**, **Athan**, **Diyanet Namaz Vakti**) incelenerek 16 yeni yerel Java modülü eklendi:

- **Tema ve Görünüm Stüdyosu (`TemaMotoru`, `TemaGalerisi`, `GeometrikDesen`)**:
  - **16 İslâmî Renk Teması**: Zümrüt Mihrap, Dinamik Gökyüzü, Saf AMOLED Gece, İznik Çinisi, Medîne Ravza, Kâbe Kisvesi, Osmanlı Sahaf, Sade Modern (Pillars), Şafak & Seher, Kandil Kehribarı, Ayasofya Kubbesi, Gece Mavisi, Selçuklu Çiviti, Kubbetü's-Sahra, Hicaz Akşamı ve gündüz okuma için açık mod **İnci Gündüz**.
  - **5 İslâmî Geometrik Desen (`Canvas`)**: Selçuklu 8 Köşeli Yıldızı, İznik Rûmî Çini, Mihrap Kemeri, Kâbe Kisvesi Kafesi ve Kubbe Halkası + 4 kart üslûbu, 4 sahne modu, 4 Mushaf hattı, yazı ölçeği ve yüksek kontrast seçeneği.
- **7 Vakit Hesaplama Yöntemi (`HesapMotoru`)**: Diyanet İşleri Başkanlığı (hibrit çevrimdışı + önbellek), Muslim World League (MWL), ISNA, Ümmü'l-Kurâ (Mekke), Mısır Genel Fetva, Karaçi İslâmî İlimler ve IGMG Avrupa + **Hanefî Asr-ı Sânî** ikindi gölge seçimi.
- **Kerahet & Nâfile Vakitler Rehberi (`Kerahet`)**: 3 kerahet vakti uyarısı ile İşrâk, Duhâ (Kuşluk), Evvâbîn ve Teheccüd vakit pencereleri.
- **Şefkatli Namaz Takibi & 84 Günlük Isı Haritası (`NamazTakip`)**: 5 vakit edâ/kazâ/cemaat kaydı, son 12 haftalık (84 gün) Pillars tarzı ısı haritası, son 7 gün geçmiş düzenleyici ve hanımlar/yolcular için seriyi kırmayan **Özel Hâl / Seri Dondurma Modu**.
- **Kazâ Namazı & Oruç Defteri (`KazaTakip`)**: Sabah–Vitir 6 vakit kazâ çetelesi, akıllı **Kazâ Borcu Hesaplama Sihirbazı**, günlük hedef / tahmini bitiş tarihi ve Ramazan / Kazâ / Şevval 6 Gün / Pazartesi-Perşembe / Eyyâm-ı Bîz oruç defteri.
- **Ramazan Modu & 30 Günlük İmsakiye (`RamazanModu`)**: Canlı 1 saniyelik İftar/Sahur geri sayım kartı, oruç ilerleme çubuğu, Arapça-okunuş-mealli İftar & Sahur niyet duâları ve 30 günlük hibrit İmsakiye.
- **3D Dokunsal Boncuklu Zikirmatik (`BoncukluZikirView`, `Zikir`)**: Kehribar, Zümrüt Yeşim, Oltu Taşı, İnci Sedef ve Firuze Çini dokularında parmakla aşağı çekilebilen 3D tesbih boncukları, özel zikir ekleme ve son 7 günlük zikir sütun grafiği.
- **5 Vakit Rehberli Namaz Tesbihatı (`TesbihatRehberi`)**: Farz sonrası 8 adımlı rehberli tesbihat, çevrimdışı Âyetü'l-Kürsî tilaveti ve 33×3 etkileşimli sayaç.
- **30 Cüz Hatim Takibi & Cüz Sesli Meal (`HatimTakip`)**: 30 cüz ilerleme ızgarası (Okunmadı / Okunuyor / Tamamlandı), hedef bitiş tarihi hesaplayıcı, Kur'an okuyucuya doğrudan geçiş ve 30 cüz sesli Türkçe meal dinleme.
- **Çevrimdışı Ezan & Namaz Sûreleri Ezber Stüdyosu (`EzanStudyo`)**: Çevrimdışı Tam Ezan ve Medîne Ezanı önizleme, Âyetü'l-Kürsî + 6 namaz sûresi için `1× / 3× / 7× / ∞` ezber döngüsü ve "Ezberledim ✓" takibi.
- **Yakındaki Camiler, Kıble Radarı & Fıkıh Rehberi (`CamilerSayfasi`)**: Çift sunuculu Overpass + çevrimdışı önbellekli cami bulucu, altın kıble ışınlı canlı radar, 8 maddelik Cuma Sünnetleri listesi ve Bayram / Terâvih / Teheccüd / Vitir-Kunut / Cenâze namazları adım adım rehberi.
- **Hicrî Takvim, Ay Evresi & Tarih Dönüştürücü (`HicriTakvim`)**: Gerçek zamanlı ay evresi çizimi (% aydınlanma), çift yönlü Milâdî ↔ Hicrî tarih dönüştürücü ve 12 mübarek gün/kandil geri sayımı.
- **Vaktin Manevî Paketi (`ManeviPaket`)**: Vaktin âyeti, 30 sahih hadis seçkisi, sabah-akşam nebevî zikirleri ve günün Esmâü'l-Hüsnâ'sı (doğrudan Zikirmatik'e aktarım).
- **Yüksek Çözünürlüklü İslâmî Paylaşım Kartı Stüdyosu (`PaylasimKarti`)**: Aktif tema ve geometrik desenle `1080×1350` (4:5) ve `1080×1920` (9:16 Hikâye) boyutlarında 4 şablonlu PNG kart üretimi, galeriye kayıt ve paylaşım.
- **Uçtan Uca Testler (`AnaMenuTesti`)**: 22 Robolectric native-graphics testi ve 25 otomatik ekran görüntüsü çıktısı.

## Araştırma: namaz vakti uygulamalarında ne öne çıkıyor

Mağaza sayfaları ve karşılaştırma yazılarında tekrar eden noktalar:
- Sade uygulamaların ana ekranı üç şeyden oluşuyor: tarih, günün vakitleri, sıradaki vakte geri sayım.
- Kullanıcıların en çok önem verdiği şey ezan bildiriminin güvenilirliği; Android'de pil ve bildirim
  güvenilirliği en sık şikâyet.
- Vakitte telefonu sessize / titreşime alma (ör. Sebat), widget'lar, reklamsızlık.

Kaynaklar: [makkahcompass karşılaştırması](https://makkahcompass.pages.dev/comparisons/prayer-apps),
[Sebat (Google Play)](https://play.google.com/store/apps/details?id=com.sebat.app),
[Al-Azan (F-Droid)](https://f-droid.org/tr/packages/com.github.meypod.al_azan/),
[fiveprayer: Athan alternatifleri](https://www.fiveprayer.app/blog/athan-app-alternative).

Bu sürüm buna göre: yeni sade tema, ana ekranda yalnız vakitler, tek bakışta "Vakitler" ekranı,
güvenilirlik denetimleri ve vakitte titreşim.

## 1.5.1: onarım ve telefonda denetim

- **Düzeltme:** 1.2.0–1.5.0, "sade ana ekran" için uygulamanın kendi ana ekranında Öğrenme (Kur'an, Elif-Ba),
  Manevi ve Keşfet bölümlerini gizliyordu; uygulamanın kendi Kur'an ve diğer ekranlarına bu yüzden girilemiyordu.
  1.5.1 bunları bir kez geri açar (`Gorunum.bolumleriGeriAc`); artık gizlenmez.
- **Uygulamayı denetle** (Menü): Flutter verileri, Kur'an verisi, yazı tipi, Elif-Ba sesleri, sesli meal dizini,
  uygulamanın ana ekranı, gizli bölüm, tilavet servisi, tilavet/meal sunucularına erişim, bildirim ayarları ve son
  hata; kopyalanabilir/paylaşılabilir rapor (`Denetim`).
- **Hata kaydı** (`Hata`): çökme ve açılamayan bölümler kaydedilir; bölüm açılışları korumalıdır (`guvenli`), hata
  olursa uygulama kapanmaz, mesaj verir.
- Testler: 16 (gizli bölümlerin geri açılması, denetim, hata kaydı eklendi).

## 1.5.0'da yeni: Kur'an-ı Kerim bölümü

Uygulamanın içindeki Flutter verileri (`assets/flutter_assets/assets/...`) Android katmanından okunur (`Varlik`):
Kur'an metni ve meal internetsiz çalışır; tilavet ve sesli meal internetle akış olarak çalar.

- **Kur'an sekmesi** (sekmeler artık: Vakitler, Kur'an, Kıble, Zikir, Menü; Takvim alt sayfa): kaldığın yer,
  şimdi çalan çubuğu, Öğren ve dinle (Elif-Ba, Sesli meal, Dualar, Esmâ, Yer imleri), 114 sure listesi ve arama
  (ad ya da numara, Türkçe karakter duyarsız).
- **Sure okuyucu** (`KuranArayuz`): sure başlığı (Arapça ad, Mekkî/Medenî, ayet sayısı), besmele, her ayet için
  AmiriQuran yazı tipiyle Arapça (sağa yaslı), Türkçe meal (quranenc, Rowwad) ve dipnot. Tilavet sırasında okunan
  ayet altınla vurgulanır ve listede kendiliğinden kaydırılır. A−/A+ yazı boyutu, görünüm (Arapça+meal / yalnız
  Arapça / yalnız meal), son okunan ayet otomatik saklanır. Ayete dokununca: buradan dinle, yalnız bu ayeti dinle,
  yer imi, **kelime kelime meal** (uygulamada bulunan 20 sure), kopyala, paylaş.
- **Tilavet** (`TilavetServisi`, ön plan medya servisi): ayet ayet everyayah.com — Mişârî Râşid el-Afâsî,
  Mahmûd Halîl el-Husarî, Muhammed Sıddîk el-Minşâvî (uygulamanın kendi ayet zamanlama dosyalarıyla aynı okuyucular).
  Telefon kilitliyken çalar; bildirimde Duraklat / Sonraki / Durdur; bildirime dokununca Kur'an sekmesi açılır.
- **Sesli meal**: 114 surenin hepsi, 10 okuyucu (Vav Radyo: Ercan Demirel, Hakan Vanlı, Ayhan Kahya, Kaya Akarsu,
  İbrahim Sadri, Nüvit Candaner, Atilla Olgaç, Turgay Tanülkü, Ali Gül, Mazlum Kiper). Dizin derlemede
  `araclar/meal_ses_uret.py` ile uygulamanın `official_meal_audio.json` kaydından üretilir (`assets/secde/meal_ses.json`).
- **Elif-Ba**: 28 harf (uygulamanın ses kayıtları), dokununca okunur ve zıplar; seçilen harfin harekeleri
  (üstün/esre/ötre/cezm, kalın harflerde a-ı-u, ince harflerde e-i-u okunuşu); **harf testi**: sesi dinle, 4 harften
  doğrusunu seç, doğru/yanlış animasyonu ve titreşim, puan saklanır.
- **Dualar** (12, okunuş + anlam + kaynak, uzun basınca kopyala) ve **Esmâü'l-Hüsnâ** (100, arama).
- Alt sayfalar sağdan kayarak açılır, kendi arka planı olur; geri tuşu ya da "‹" kapatır.
- Manifest: `TilavetServisi` (foregroundServiceType=mediaPlayback), `FOREGROUND_SERVICE_MEDIA_PLAYBACK` izni.
- Higgsfield: `kuran_bg`, `elifba_bg` arka planları.

## 1.4.0'da yeni: Secde ana menüsü

Uygulama simgesine dokununca (soğuk açılışta) önce **Secde ana menüsü** açılır; Flutter ekranı altta hazır
bekler. Bildirime dokunma, tam ekran ezan ve "doğrudan" açılışlar menüye takılmadan Flutter'a gider. İlk kurulum
bitmeden menü çıkmaz. Menü › Görünüm › "Açılışta bu menü" ile kapatılabilir. Geri tuşu: önce Vakitler sekmesine,
oradan uygulamadan çıkış.

Beş sekme, her birinin kendi fotoğraflı canlı arka planı (Higgsfield, 18 görsel, ~1,3 MB):

| Sekme | İçerik | Arka plan |
|---|---|---|
| **Vakitler** | Halka içinde geri sayım, günün 6 vakti (şu anki nabız atar), resimli hızlı erişim şeridi, **günün ayeti**, **yaklaşan mübarek gün** (geri sayımlı), bildirim durumu, hızlı anahtarlar | O anki vaktin camisi |
| **Kıble** | Sensörle dönen pusula (`Pusula`): kadranda Kâbe görseli kıble yönünde, telefon ±4° içine gelince altın ışık halkası + titreşim; derece, 8 yönlü ad, Kâbe'ye uzaklık, **günün kıble saati**, "sağa/sola X° dönün" yönlendirmesi, kalibrasyon ipuçları | Kâbe (gece) |
| **Zikir** | Zikirmatik (`ZikirDaire`): 8 zikir (Arapça, okunuş, anlam), dokununca dalga + titreşim, 33 dönen tesbih tanesi, ilerleme halkası, hedef (33/99/100/500/1000), hedefte altın patlama, **namaz tesbihatı** (33·33·33 otomatik geçiş), sıfırla, günlük ve toplam sayım (kalıcı) | Tesbih ve seccade |
| **Takvim** | 31 günlük vakit tablosu, her günün hicrî tarihi, bugün altın, cumalar altın, **mübarek günler** pembe işaretli | Kandiller |
| **Menü** | Resimli bölüm butonları (Kur'an, Dualar, Esmâü'l-Hüsnâ, Ramazan, Kaza ve oruç, Elif-Ba → uygulamada açılır; Kıble, Zikirmatik → sekme), görünüm, bildirim ayarları, seçenekler, test, ayrıntılar ve destek | Mihrap |

- **Resimli butonlar** (`Kutucuk`): yuvarlak köşeli fotoğraf yavaşça yakınlaşıp kayar, renkli alt geçiş,
  ~7 sn'de bir çapraz ışıltı, basınca çöküp yaylanır, titreşim.
- **Sekme çubuğu**: kodla çizilmiş simgeler (`Simge`: hilal, pusula, tesbih, takvim, ızgara), altın gösterge
  yaylanarak kayar, seçilen simge döner, metin rengi geçişli; yatay kaydırma ile sekme değişir.
- Uzun basma kısayolları: Vakitler, Kıble, Zikirmatik, Vakit sayacı.
- Flutter'ın içindeki bölümlere (Kur'an, dualar…) doğrudan atlanamıyor: uygulamada adlandırılmış rota yok;
  butonlar uygulamayı açar.

## Test (Robolectric, gerçek çizim)

```
./test.sh
```
13 uçtan uca test (1.5.0: Kur'an verisi ve ses adresleri, Kur'an sekmesi ve Bakara okuyucusu, Elif-Ba harfleri ve testi, dualar/Esmâ/takvim/sesli meal alt sayfaları dahil) (`test/…/AnaMenuTesti.java`), İstanbul örnek verisiyle: 5 sekmenin çizimi ve sekme butonları,
resimli butonların sekme açması, Flutter bölüm butonunun doğru niyetle uygulamayı açması, ana menüden çıkış,
zikirmatikte 33 dokunuş + tesbihat geçişi + kalıcı sayım, kıble hesabı (İstanbul 151,6°, 2.405 km) ve pusula
hizalaması, açılış menüsü ayarı, uygulama açılışında menünün gelmesi (ve bildirim açılışında gelmemesi),
takvim/bildirim okuyucuları. Ekran görüntüleri `.derleme/test-cikti/*.png`.
Google Maven bu ortamda kapalı olduğu için androidx.test kaynaktan derlenir (`test-destek/`).

## 1.3.0'da yeni: canlı Vakitler ekranı

Flutter ekranları (ana sayfa, sekmeler, geçişler) derlenmiş Dart kodu olduğu için kaynak olmadan yeniden
yazılamıyor; Flutter tarafında görsel dosyası da yok (desenler kodla çiziliyor). Bu yüzden yenilik, Android
katmanındaki **Vakitler** ekranında (uzun basma kısayolu, Hızlı Ayarlar kutucuğu, sayaç bildirimi):

- **Cami arka planları** (Higgsfield, `gpt_image_2_6`, 9:16): her vakte bir fotoğraf (tan yeri, gün doğumu,
  öğle avlusu, ikindi ışığı, gün batımı, gece) + Aylık sekmesinde kandiller, Ayarlar'da mihrap.
  `gorseller/*.webp` → APK'da `assets/secde/` (toplam ~730 KB). Yavaş yakınlaşıp kayar (Ken Burns, 40 sn),
  vakit ya da sekme değişince 1,6 sn'lik yumuşak geçiş.
- **Efektler** (`Sahne`): gece parıldayan yıldızlar ve ~11 sn'de bir kayan yıldız; gündüz süzülen ışık zerreleri;
  okunabilirlik için alttan koyulaşan perde. Görsel yoksa kodla çizilen animasyonlu cami silueti (kubbeler,
  şerefeli minareler, alem, suda yansıma, titreyen kandil ışıkları).
- **Sekmeler**: Bugün · Aylık · Ayarlar. Altın gösterge yaylanarak kayar, sayfalar kayma + saydamlıkla geçer,
  yatay kaydırmayla sekme değişir, dokunsal geri bildirim.
- **Bugün**: `Halka` — önceki vakitten sıradakine ilerleme halkası (açılışta dolarak gelir, ucunda nabız gibi
  parlayan nokta), ortasında geri sayım (her dakika başında küçük "tık"); günün vakitleri sırayla süzülerek
  gelir, şu anki vakit altın renkte nabız atar; durum hapı; sayaç ve titreşim anahtarları.
- **Aylık**: 31 güne kadar vakit tablosu; bugün vurgulu, cumalar altın.
- **Ayarlar**: sistem ayarları, kurulu bildirimler, seçenekler, test, ayrıntılar ve destek; buzlu cam kartlar.
- Tüm düğmelerde basma/yaylanma animasyonu; ekran açılışında içerik aşağıdan süzülür.

## 1.2.0'da yeni

### Mihrap teması (uygulamanın tamamı)
Varsayılan "Zümrüt" teması, `libapp.so` içinde yeni bir paletle **Mihrap** olarak değiştirildi:
gece mavisi–çivit ana renk, kehribar vurgu, sade nötr zeminler; açık ve koyu modda.

| Alan | Eski (Zümrüt) | Yeni (Mihrap) |
|---|---|---|
| Ana renk (açık / koyu) | `#1F6E5C` / `#4FB89E` | `#3D4A9C` / `#9AA6F5` |
| Vurgu / açık vurgu | `#B5893C` / `#D9B76A` | `#C07A1E` / `#F0B35A` |
| Yüzey (açık / koyu) | `#EAF2EE` / `#24322B` | `#EEF0F8` / `#1C2033` |
| Zemin (açık / koyu) | `#F4F7F1` / `#121C17` | `#F7F7FA` / `#12142A` |
| Üst kart geçişi | `#123F35 → #255F4E` | `#1E2559 → #3D4A9C` |

Nasıl: `ColorTheme` sabitlerinin renk alanları AOT snapshot'ta Dart'ın işaretli değişken uzunluklu tamsayı
biçimiyle yazılı (64 bitte her alanı üç, 32 bitte bir `0xc0` izliyor). Yeni renkler aynı bayt uzunluğunda
seçildi; dosyada hiçbir şey kaymıyor (`araclar/tema_yamasi.py`, arm64 / armeabi-v7a / x86_64).
Doğrulama: yamalı arm64 `libapp.so` blutter ile yeniden çözüldü; Dart VM sorunsuz yükledi ve
`ColorTheme.zumrut` → ad "Mihrap", 10 rengin hepsi yeni değerlerle okundu. Diğer 11 temaya dokunulmadı;
Ayarlar › Tema'dan hâlâ seçilebilir.

### Sade ana ekran (bir kez uygulanır)
Güncellemeden sonraki ilk açılışta, Flutter başlamadan önce:
- Tema: Mihrap
- Arka plan deseni kapalı
- Ana ekranda Öğrenme, Manevi içerik ve Keşfet bölümleri gizli; yalnız vakitler

Hepsi uygulama içinden ("Ana ekranı düzenle", Ayarlar) geri açılabilir.

### Vakitler ekranı (yeniden tasarlandı)
Uygulama simgesine uzun basınca ("Vakitler"), Hızlı Ayarlar kutucuğundan ya da bildirimlerden açılır.
1. Yer, miladî ve hicrî tarih
2. Sıradaki vakit: büyük geri sayım (saniye saniye), saat
3. Bugünün altı vakti; şu anki vakit vurgulu, geçenler soluk
4. Tek satır durum: "Bildirimler çalışıyor · 42 vakit kurulu · 22 Aralık'a kadar" ya da sorun + **Düzelt**
5. İki anahtar: **Vakit sayacı**, **Vakitte titreşime al** (+ süre seçimi); Test bildirimi, Uygulamayı aç
6. **Ayrıntılar** (kapalı gelir): sistem ayarları, kurulu bildirimler, araçlar, yaklaşan bildirimler, teşhis raporu

Vakitler uygulamanın vakit önbelleğinden (`flutter.schedule.json`) okunur; kapatılmış vakitler ve Güneş de görünür.

### Vakitte titreşime al (yeni, varsayılan kapalı)
Her vakit girdiğinde (Güneş hariç) telefon zil modundaysa titreşime alınır; 10/15/20/30/45 dk sonra zile döner.
Bildirimde geri sayım ve "Zili şimdi aç". Kullanıcı arada modu kendisi değiştirdiyse dokunulmaz;
telefon kapalıyken süre dolduysa açılışta düzeltilir. Rahatsız Etmeyin izni gerektirmez.

## Önceki sürümlerden (devam ediyor)

- **Açılışta denetim**: bildirim izni, ezan kanalı, tam alarm izni, arka plan kısıtı, pil optimizasyonu;
  Türkçe uyarı + Düzelt (12 saatte bir; yalnız pil için haftada bir, "Bir daha sorma").
- **Vakit sayacı**: kalıcı sessiz bildirim, geri sayım ve günün vakitleri (artık takvimden: Güneş dahil).
- **Bildirim bekçisi**: kurulu vakit bildirimi kalmadıysa / 36 saatte bitecekse uyarır.
- **Kısayollar**: Vakitler, Test bildirimi, Vakit sayacı. **Hızlı Ayarlar**: "Sonraki vakit" kutucuğu.
- Test bildirimi (anında / 1 dk sonra, ezan kanalından), üreticiye göre otomatik başlatma yönlendirmesi.

## 1.0.0 inceleme sonucu

Dart kodu `blutter` ile çözüldü (Dart 3.13.7). Bildirim zinciri sağlam: `cancelAll` → `buildSchedulingPlan`
(en fazla 240) → `zonedSchedule(exactAllowWhileIdle)`, hata olursa `inexact`; saat dilimi yedeği; çevrimdışı
vakit hesabı. **Kodda bildirimi engelleyen hata yok**; neden telefon ayarları ve üretici kısıtlamaları.

## Kod

| Dosya | Görev |
|---|---|
| `SecdeUygulama` | Application; sade görünüm, kısayollar, kanallar, denetim, sayaç, titreşim planı |
| `Gorunum` | Mihrap paleti (Android tarafı) ve bir kezlik sade görünüm ayarları |
| `DurumAktivitesi` | Vakitler ekranı: üç sekme, geçişler (XML kaynaksız) |
| `Sahne` | Canlı arka plan: fotoğraf + Ken Burns ya da çizilmiş cami, yıldız/zerre efektleri |
| `Halka` | Dairesel ilerleme halkası |
| `Kutucuk` | Resimli, canlı menü butonu |
| `Simge` | Sekme simgeleri (kodla çizilir) |
| `Pusula`, `Kible` | Kıble pusulası ve yön/uzaklık hesabı |
| `ZikirDaire`, `Zikir` | Zikirmatik görünümü ve kalıcı verisi |
| `Gorseller` | assets/secde görsellerini yükleme ve önbellek |
| `VakitTakvimi` | `flutter.schedule.json` okuma (UTC / yerel / ofsetli ISO tarihleri) |
| `VakitDeposu`, `Vakit` | `flutter_local_notifications` kaydını salt okunur çözme |
| `SessizMod` | Vakitte titreşim |
| `VakitSayaci`, `Bekci`, `ZamanlayiciAlici` | Sayaç, bekçi, alarmlar ve açılış olayları |
| `BildirimKontrol`, `TestAlarmAlici` | Denetim, uyarılar, düzeltme yönlendirmeleri, test |
| `SonrakiVakitKutucugu` | Hızlı Ayarlar kutucuğu |
| `Kanallar`, `Tercihler`, `Metinler` | Kanallar, ayarlar, Türkçe biçimler (İkindi'ye, 22 Aralık'a) |
| `araclar/tema_yamasi.py` | libapp.so tema yaması |
| `araclar/manifest_duzenle.py` | İkili manifest düzenleme |
| `araclar/repack.py`, `Sign.java`, `Dogrula.java`, `checkalign.py` | Paketleme, hizalama, v2 imza, doğrulama |

## Doğrulama

- `derle.sh` baştan sona çalışıyor; v2 imza geçerli, `.so` 16 KB / diğerleri 4 bayt hizalı.
- Tema yaması blutter ile doğrulandı (yukarıda); üç mimaride de 38 bayt değişti.
- `Metinler`, `VakitDeposu`, `VakitTakvimi` JVM'de denendi: ekler, süreler, beş tarih biçimi, haftalık cuma tekrarı.
- **Cihazda denenmedi** (emülatör yok). Yeni Android kodu `try/catch` ile sarılı.

## Yeniden derleme

```
./derle.sh <secde_vakti-1.0.0.apk> <anahtar.p12> <parola> [takma-ad]
```
Android SDK gerekmez; araçlar betikte indirilir. İmza anahtarı depoda **yok** (bkz. CLAUDE.md).

## Sınırlar

- Flutter ekranları (tam ekran ezan alarmı, kaza/oruç, uygulama ayarları) kaynak kodsuz derlenmiş Dart'tır;
  yalnız tema renkleri yamalanabilir. Yeni her şey Android katmanında (ana menü) yapılır.
- Ana ekran widget'ı: APK'ya kaynak (XML) eklemeyi gerektirir; yapılmadı.
