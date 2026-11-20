# Mehmet Asistan 0.11.0 build 18 — iPhone web veri çıkarma

- İndirmeler ekranına **Bu web sayfasından veri çıkar** eylemi eklendi.
- Tarama bütünüyle iPhone içindeki geçici WKWebView oturumunda çalışır; VPS, CLIProxy veya başka indirme sunucusu kullanılmaz.
- Çıkarılan türler: sayfa başlığı/açıklaması/dili, görünür metin, bağlantı, görsel, doğrudan ses/video, belge, altyazı, tablo satırları ve JSON-LD.
- Sonuçlarda metin arama ve tür filtresi; en fazla 10 doğrudan dosyayı indirme kuyruğuna ekleme; tüm raporu JSON veya CSV dışa aktarma eklendi.
- Sınırlar: tarama başına 1.200 öğe ve 2 MB sonuç; sayfanın tarayıcıya yüklediği veriyle sınırlı. Giriş, DRM, CAPTCHA veya parçalı medya aşılmaz. YouTube/desteklenen medya indirmesi Kepçe üzerinden sürer.
- Asistan `indirmeler` aracına `tara` işlemi eklendi. Sistem talimatı web kazıma taleplerini bu araca yönlendirir ve tamamlanmamış işi tamamlandı diye bildirmez.

## Doğrulama

- 122 Swift testi, 31 suite: geçti. Mevcut 10 canlı/donanım koşullu test bu toplamın dışında atlandı.
- Yeni indirme/veri modelleri: 5 test geçti; JSON/CSV kodlama ve tüm veri türlerinin çözülmesi doğrulandı.
- XCUITest: gerçek `https://example.com` sayfası açıldı, 7 öğe çıkarıldı; JSON/CSV düğmeleri ve sonuç ekranı doğrulandı. Görsel `ui-attachments-final/` altında.
- Fiziksel iPhone: gömülü kapsam sayfasından 9 öğe; dosya, görsel, metin, ses, tablo, video ve JSON-LD türleri; PDF bağlantısı; 664 bayt CSV ve 1.577 bayt JSON doğrulandı.
- Aynı fiziksel testte `https://example.com/` canlı sayfasının başlığı `Example Domain`, kaynak adresi ve 7 öğesi doğrulandı.
- Fiziksel cihaz derlemesi ve kurulum başarılı. Ekran paylaşımı/iPhone Mirroring açılmadı.
