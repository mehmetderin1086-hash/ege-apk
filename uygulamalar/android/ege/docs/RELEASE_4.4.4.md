# Ege 4.4.4 (57)

4.4.3 cihazında PCM ve yerel çözümleme çalışırken tekrarlı `wake=false`
sonuçları görüldü. Önceki cihaz tanılamasında kullanıcının “Hey Ege” sözü
İngilizce çözümleyicide “Hey, egg” olarak okunmuştu. İngilizce denetim
yalnız tanılama ekranında çalışıyor, normal uyandırmada kullanılmıyordu.

- Türkçe denetim eşleşmezse 0,5–4,5 saniyelik kısa seslerde yerel İngilizce
  yedek denetimi çalışır. Türkçe eşleşme varsa ikinci çözümleme yapılmaz.
- Standart açık uyandırma ifadesine ek olarak yalnız tek başına “Hey egg”
  varyantı kabul edilir; “egg”, “Hey egg timer”, Ece ve Jarvis eşleşmez.
- Ses kimliği filtresi ve 0,65 eşiği korunur; yedek ifade bu doğrulamayı atlamaz.
- Kayıtlara tr/en/fallback sonuçları eklenir; konuşma metni yazılmaz.
- Ses profili silme işlemi artık onay penceresi gerektirir. Test sırasında
  ekranın kayması nedeniyle gerçekleşen yanlış dokunmanın tekrarı önlenir.
  Genel profil sonrasında kullanıcı tarafından yeniden oluşturulduğu
  arayüzde görüldü; kısa profilin durumu bu aşamada doğrulanmadı.

Doğrulama: Android birim test görevi başarılı, 11 odaklı Flutter testi geçti.
Değişen Dart dosyalarında analiz hata/uyarısı yok (bir biçim önerisi).
Gerçek kullanıcı sesiyle uygulama dışından uyandırma henüz doğrulanmadı.

Release APK başarıyla derlendi (202 saniye) ve USB `install -r` ile kuruldu.
Cihaz sürümü 4.4.4 / 57, güncelleme zamanı 17 Kasım 2026 16:13:03 olarak
doğrulandı. Arka plan motoru başladı ve PCM akışı görüldü; telefon ana
ekranına dönülerek kullanıcıdan gerçek ses denemesi istendi.

APK: `C:/Users/mehmet/Desktop/JARVIS/dist/Ege-4.4.4.apk`
SHA-256: `5963b5dae5fce3b83f38a33dff9123711c5e86dd33bfa4a3fc4ae381be0cae18`.

## Cihaz tanılaması — 17 Kasım 16:19–16:22

İlk kullanıcı denemesi başarısızdı. Açık tanılama sırasında mikrofonun
susturulmadığı, en yüksek RMS'nin 0,02209 olduğu görüldü. KWS üç kez
tetiklendi; ses kimliği kontrolü 0,44–0,52 / 0,65 ile reddetti. Yerel Türkçe
çözümleme sonraki örnekte “Hey, ege.” ifadesini de doğru duydu; filtre yine
reddetti. Dolayısıyla bu denemede engel yalnız sözcük tanıma değildi.

Ses profili ekranında genel profil hazırken kısa uyandırma profilinin eksik
olduğu doğrulandı. Kullanıcı üç kısa örneği kaydetti; “Hey Ege kalibrasyonu
hazır. Genel ses profilin korundu.” durumu görüldü. Ekrandan çıkılarak
16:22:09'da arka plan motoru yeniden başlatıldı. Telefon ana ekranından
gerçek sesle son doğrulama bekleniyor. Filtre eşiği düşürülmedi.
