# Mehmet Asistan 0.17.0 build 27 fiziksel kurulum

- İmzalı dinamik uygulama köprüsü yeniden üretildi. Dosya Apple Encrypted Archive (AEA1) biçiminde, doğrulayıcıya göre bir kanonik Open App eylemi içeriyor. Mac'te com.apple.mobilesafari girdisiyle Kestirmeler çalıştırması sıfır çıkış koduyla tamamlandı.
- Simülatör birim paketi: 138 test, 34 test grubu geçti.
- Fiziksel iPhone 15 birim paketi: 138 test, 34 test grubu geçti.
- VPS asistan-jobs.service etkin. /v1/asistan/live-token endpoint'i dağıtıldı; kimliksiz loopback isteği 401 döndürerek korumayı doğruladı. Sunucudaki Gemini Live anahtar değişkeni henüz yapılandırılmadığından gerçek WebSocket Live başlatılamaz ve iPhone sıralı Live geri dönüşünü kullanır.
- telefona-kur.sh fiziksel iPhone'a ekran paylaşımı açmadan derledi, kurdu ve uygulamayı başlattı.
- devicectl fiziksel cihazda com.mehmetderin.asistan için sürüm 0.17.0, bundle sürümü 27 bildirdi.

Bu kanıt normal uygulama başlatma ve paket kurulumunu kapsar. Mikrofon, Hey Asistan ve gerçek Gemini Live kabulü için kullanıcı sesi ve sunucuda yapılandırılmış Gemini Live anahtarı gerekir.
