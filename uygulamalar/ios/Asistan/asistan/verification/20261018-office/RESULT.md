# Mehmet Asistan 0.12.0 · Ofis ve son istek kabulü

Tarih: 18 Ekim 2026

## Son isteğin kök nedeni ve düzeltmesi

Fiziksel cihazın SwiftData kaydındaki son istek `Kitapyurdu'da simyacıının bütüni'ni bul Excel dosyasında ver` idi; sonrasında asistan yanıtı kaydedilmemişti. İstek daha önce sohbet kipine düşüyor, gerçek XLSX aracı bulunmuyor ve araştırma sonucu dosya aracına kesin bağlanmıyordu.

İstek artık araştırma kipine gider. Kitapyurdu + Excel isteği, genel model turunu beklemeden iPhone'da salt okunur katalog taraması ve gerçek XLSX yazımı yapan kesin akışa sahiptir. Fiziksel kabul sonucu:

- model/yol: `iPhone · Kitapyurdu katalog`
- 40 benzersiz ürün
- `Kitapyurdu-Simyacı.xlsx`
- 41 çalışma sayfası satırı: 1 başlık + 40 veri
- 40 `https://www.kitapyurdu.com/` bağlantısı
- ZIP bütünlük sınaması hatasız

Ham kanıt: `../20261018-last-request-fix/device-result-012.json`, `../20261018-last-request-fix/sheet1.xml` ve üretilen XLSX.

## Ofis yetenekleri

- Oluşturma: DOCX, XLSX, PPTX, PDF, TXT, Markdown, CSV, JSON.
- Okuma: DOCX, XLSX, PPTX ve PDF; PDF'de gerektiğinde cihaz içi OCR.
- Düzenleme: kullanıcı mevcut dosyayı sohbete ekler, değişikliği ister; araç yeni dosya üretir. Özgün dosya korunur.
- Çıktı: iPhone `Documents/Indirmeler`; Quick Look, paylaşma ve Dosyalar'a kaydetme.
- Sınırlar: 20 MB giriş, 50.000 karakter model bağlamı; güncel OOXML biçimleri. Parolalı/şifreli veya eski DOC/XLS/PPT önce dönüştürülmelidir.

## Doğrulama

- Fiziksel iPhone dört biçimi oluşturdu ve tekrar okudu: `device-result.json`.
- `file`: Microsoft Word 2007+, Microsoft Excel 2007+, Microsoft PowerPoint 2007+, PDF 1.3/1 sayfa.
- `unzip -t`: DOCX/XLSX/PPTX üçünde de hata yok.
- 126 test / 31 test paketi geçti: `all-tests.log`.
- 0.12.0 build 20 fiziksel iPhone'a kuruldu.
- Device Hub ve iPhone ekran paylaşımı açılmadı.

## 0.12.1 dosya dönüşümü

- Menü ve + menüsüne **Dosya dönüştür** ekranı eklendi.
- Hedefler: DOCX, XLSX, PPTX, PDF, CSV, Markdown, TXT ve JSON.
- Özgün kaynak korunur; sonuç `-Dönüştürüldü` adlı yeni dosyadır.
- Fiziksel iPhone'da DOCX→XLSX/PDF/PPTX/CSV ve XLSX→DOCX dönüşümlerinin beşi üretildi ve `BelgeOkuyucu` ile yeniden okundu.
- 0.12.1 build 21 fiziksel cihaza kuruldu; 127 test / 31 paket geçti.
- Ham kanıt: `conversion-device-result.json`, `conversion-device-build.log`, `all-tests-0121.log`.

## 0.13.0 ZIP/RAR

- ZIP oluşturma ve açma; RAR4/RAR5 açma; isteğe bağlı RAR parolası.
- Yol geçişi/symlink reddi, 1.000 öğe ve 1 GB açılmış veri sınırı.
- Fiziksel cihaz: iki dosyalı ZIP oluşturuldu, geri açıldı ve içerik doğrulandı; gerçek RAR5 içindeki `README.md` 40 bayt olarak çıkarıldı.
- Üretilen cihaz ZIP'i `unzip -t` ile hatasız: `archive-device-result.json`, `iphone-archive.zip`, `archive-tests.log`.
- RAR oluşturma, RARLAB lisansı nedeniyle desteklenmez; ZIP oluşturma kullanılır.

## 0.14.0 Grok Bot özellik katmanı

- 6 hazır uzman, en fazla 6 kişilik ekip, `@Uzman` yönlendirmesi, özel uzman oluşturma/çoğaltma/profil paylaşımı.
- Hazır ve özel beceri kütüphanesi.
- VPS üzerinde 5–10080 dakikalık metin/araştırma/kod rutinleri; oluştur/listele/duraklat/sürdür/sil ve sohbet aracı.
- Sunucu canlı kabulü: HTTP 201 oluşturma, 200 listeleme, duraklatma ve silme. Servis `active`; SQLite `routines` tablosu hazır.
- Fiziksel iPhone kabulü: 6 uzman, 4 beceri, uzman bağlamı ve rutin oluştur/duraklat/sil başarılı: `grok-device-result.json`.
- 132 iOS testi / 32 paket ve 13 sunucu testi geçti. 0.14.0 build 23 fiziksel iPhone'a kuruldu. Device Hub/iPhone ekran paylaşımı açılmadı.
