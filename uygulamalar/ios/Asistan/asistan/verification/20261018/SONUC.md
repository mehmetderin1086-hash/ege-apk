# Asistan 0.3.0 (4) — 18 Ekim 2026

Gerçek iPhone 15 / iOS 27.0.1'e kuruldu. Ekran paylaşımı kapalı tutuldu.

## Doğrulananlar

- Uygulama: 54 test geçti; 10 canlı/donanım testi bu çalıştırmada atlandı. `web-tool-tests.log`.
- ProxyKit: 70 test geçti; 11 canlı test atlandı. `proxy-bridge-tests.log`.
- Gerçek cihaz ses hattı: 4 test geçti. İzin, mikrofon sinyali, Türkçe STT desteği, Türkçe TTS sesinin STT ile çözülmesi. `voice-without-mirror-final.log`.
- Claude Opus 5.5, GPT-6.1-Sol ve Gemini 3.8 Flash gerçek saat aracını çağırıp cevap verdi. `iphone-models-final.json`. Claude denemesinde sunucu yedeği nedeniyle 65 saniye, diğerleri yaklaşık 5 saniye sürdü. Önceki Claude denemesi 2–5 saniyeydi; sabit gecikme garantisi yoktur.
- Ortak Keychain'den 8 hesap / 66 model listesi. Info.plist'te eski API anahtarı/token alanları yok.
- Metin dosyasında 50.000 karakter sınırı ve taranmış PDF OCR test edildi.
- Atölye araştırması resmi Apple kaynağıyla cevap verdi. `iphone-workshop-final.json`. Buradaki `webAramaSayisi` eski Claude sunucu aracını sayar; yeni `webArastir` aracının sayacı değildir. Yeni araç, Responses sonucunda tamamlanmış gerçek web çağrısı ve kaynak URL'leri gerektirir.
- Yeni web servisi doğrudan iPhone'da ayrıca doğrulandı: `iphone-web-chatgpt.json`. Tamamlanmış web arama çıktısı ve Apple kaynak bağlantıları geldi. Son ayrıştırıcı, tüm arama listesinden önce yanıtın gerçekten atıf yaptığı bağlantıları seçer.
- Ana ekran son simülatör görüntüsü görsel olarak incelendi: `simulator-final.png`. Simülatörde telefon Keychain hesabı bulunmadığı için bağlantı bekleniyor yazması normaldir.

## Açık dış bağımlılıklar ve sınırlar

- Grok modeli bağlı hesapların listesinde yok; Grok için ayrı erişim gerekir.
- GPT Image 2.5 Flare HTTP 502 döndürdü; Gemini 3 Pro Image kendi yerel API yolunda HTTP 402 döndürdü. Görsel üretimi doğrulanmış değildir; hesap/kota/ödeme ve sunucu desteği gerektirir. UI gerçek hata kodunu gösterir.
- Claude sunucu web aracı boş yanıt/zaman aşımı verdi; üretim sohbet yolundan çıkarıldı. Kaynak araştırması CLIProxy ChatGPT bağlantısını kullanır, raporu seçili sohbet modeli yazar.
- Uzak terminal, bulut bilgisayar ajanı, X/Drive/e-posta hesap erişimleri bağlı değildir. Model seçimi ilgili ürünün bütün abonelik özelliklerini sağlamaz.
- Telefon araçlarının tüm izin ve donanım senaryoları tek tek canlı sınanmış değildir. Uygulama/kestirme açma isteği, hedef uygulamadaki işin tamamlandığının kanıtı değildir.
- Mikrofonun sıfır sinyal vermesinin ekran paylaşımıyla ilişkisi bu cihazda önce/sonra ölçüldü. Sesli kullanım sırasında ekran paylaşımını yeniden açmayın.

## Kaynaklar

- `/Users/mehmetderin/Developer/asistan`
- `/Users/mehmetderin/Developer/cliproxy-ios/ProxyKit`: OpenAI Responses araç yönlendirmesi ve Gemini imza koruması. `AssistantBridgeTests.swift` regresyonları sınar.
- `source-before.tgz` ilk uygulama kaynak yedeğidir; gizli yapılandırmayı içermez.
