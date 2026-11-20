# Mehmet Asistan 0.16.0 build 26 ve 0.17.0 kaynak temeli

- 0.16.0 fiziksel iPhone 15'e derlendi, kuruldu ve normal açıldı. `devicectl` kurulu sürümü `0.16.0` olarak doğruladı. Ekran paylaşımı/iPhone Mirroring açılmadı.
- Sağlık ve hız merkezi CLIProxy, hesap, mikrofon, Türkçe STT, ses kataloğu ve sunucu durumunu denetler. Model ilk metin/toplam yanıt, STT ve TTS için son 160 içeriksiz ölçümden ortalama, p95 ve başarı oranı çıkarır.
- Tam simülatör paketi: 138 Swift testi geçti; 7 UI testi geçti, yalnız fiziksel kurulum için olan 4 otomasyon testi beklendiği gibi atlandı.
- 0.17.0 kaynak temeli: kısa ömürlü Gemini Live anahtarı, çift yönlü WebSocket, 16 kHz PCM mikrofon, 24 kHz PCM oynatma, giriş/çıkış transkripti, araya girme ve sıralı Live'a geri dönüş.
- Sunucu: 13 yerel test geçti. Yeni `/v1/asistan/live-token` kaynakta hazır; kalıcı Gemini anahtarını telefona göndermez.
- Açık dış bağımlılık: üretim VPS endpoint'i henüz dağıtılmadı; mevcut HTTPS yolunun sonucu HTTP 404. Bu makineden VPS SSH oturumu kurulamadı. Bu nedenle 0.17 fiziksel cihaza kurulmadı ve gerçek çift yönlü Live kabulü yapılmadı. Telefonda doğrulanmış sürüm 0.16.0 build 26'dır.

Dosyalar: `Asistan/Beyin/SaglikMerkezi.swift`, `Asistan/Arayuz/SaglikEkrani.swift`, `Asistan/Ses/GercekZamanliLive.swift`, `Asistan/Ses/CanliSesIO.swift`, `vps/asistan-jobs/server.py`.
