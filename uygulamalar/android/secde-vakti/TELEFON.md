# Secde Vakti'yi telefondan yönetmek

Bilgisayar gerekmez ve kullanılmaz. Her şey telefondaki Claude uygulamasından (Claude Code, bu depo seçili) yapılır:
istek, derleme, test, imzalama, GitHub ve APK teslimi bulutta; sen yalnız APK'yı kurarsın.

## Yeni sürüm istemek

1. Claude uygulamasında **ege3435** deposuyla yeni bir Claude Code oturumu aç.
2. Ne istediğini yaz, başına `/secde-vakti` ekle. Örnek:
   `/secde-vakti Aylık sekmesine hicrî ayları ekle`
3. Oturum derleme için imza anahtarını isteyecek:
   ataş simgesi › Dosyalar › `secde_vakti_imza_anahtari.p12` dosyasını ekle ve anahtar parolasını yaz
   (parola depoda yazılı değil; anahtarla birlikte sakla).
4. Claude APK'yı derleyip sohbete gönderir. Dosyaya dokun › **Yükle**.
   Aynı anahtarla imzalı olduğu için eski sürümü kaldırmadan üzerine kurulur; ayarların kalır.

## Kurulum notları

- İlk kez kuruyorsan ya da telefonda **orijinal 1.0.0** varsa önce onu kaldır (farklı imza).
- "Bilinmeyen uygulamaları yükle" izni istenirse ver (Ayarlar › Uygulamalar › Claude / Dosyalar).
- Play Protect "bilinmeyen geliştirici" uyarısı verirse: **Yine de yükle**.

## Anahtarı kaybetme

`secde_vakti_imza_anahtari.p12` telefonunda (Dosyalar/İndirilenler) dursun; ayrıca Google Drive'a yedekle.
Anahtar depoda **yoktur** (gizli bilgi). Kaybolursa sonraki sürüm yeni anahtarla imzalanır ve
telefonda bir kez kaldır–kur gerekir (uygulama verisi silinir).

## Uygulamada nereye bakmalı

- Uygulamayı açınca **Secde ana menüsü** gelir: Vakitler, Kıble, Zikir, Takvim, Menü sekmeleri.
  Kur'an, dualar ve diğer bölümler için Menü'deki resimli butonlar ya da "Uygulamanın tüm bölümleri".
  İstemezsen: Menü › Görünüm › "Açılışta bu menü" kapat.
- Uygulama simgesine **uzun bas**: Vakitler, Kıble, Zikirmatik, Vakit sayacı kısayolları.
- Bildirim panelini aşağı çek › düzenle › **Sonraki vakit** kutucuğunu ekle.
- Menü sekmesi: bildirim kontrolleri, test bildirimi, teşhis raporu (kopyalayıp Claude'a yapıştırabilirsin).

## Sorun bildirmek

Menü › **Uygulamayı denetle** › Raporu kopyala, sonra Claude oturumuna yapıştır (veri, ses, internet, servis ve son hata dahil).

Menü › Ayrıntılar ve destek › **Raporu kopyala**, sonra Claude oturumuna yapıştır.
Ekranda bir şey bozuksa ekran görüntüsünü ataşla ekle.

## Uygulamada neler var

| Yer | Ne yapar |
|---|---|
| Vakitler | Geri sayım, günün vakitleri, günün ayeti, mübarek gün, takvim |
| Kur'an | 114 sure, Arapça + Türkçe meal, ayet ayet tilavet (3 hâfız), sesli meal (10 okuyucu), kelime meali (20 sure), yer imleri, kaldığın yer |
| Kur'an › Elif-Ba | 28 harf sesli, harekeler (üstün, esre, ötre, cezm), harf testi |
| Kur'an › Dualar / Esmâ | 12 dua, Esmâü'l-Hüsnâ (arama) |
| Kıble | Pusula, Kâbe yönü ve uzaklığı, kıble saati |
| Zikir | Zikirmatik, namaz tesbihatı |
| Menü | Bütün bölümler, bildirim ayarları, test, destek |

Tilavet ve sesli meal internetle çalışır (telefon kilitliyken de). Kur'an metni, meal, Elif-Ba sesleri internetsiz.

## Sınır

Uygulamanın kendi Flutter ekranları (ezan çalan tam ekran alarm, kaza/oruç takibi, ayarlar) derlenmiş koddur ve
kaynak kodu yok; onlar olduğu gibi kalır, "Menü › Kaza, oruç, ezan" ile açılır. Bütün yenilikler Secde ana
menüsünde (Android katmanı) yapılır.
