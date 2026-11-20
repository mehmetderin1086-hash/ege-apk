JARVIS 4.3.5 (48) — Türkçe uyandırma yedeği

4.3.4 üzerinde yapılan gerçek telefon denemesinde mikrofon sessize alınmıyordu, ses paketleri ve işlenen örnek sayısı artıyordu; kullanıcı Hey Jarvis söylediğini bildirdiği halde KWS tetiklemesi gözlenmedi. Bu nedenle yalnız arka plan servisinin açık olması başarı olarak kabul edilmedi.

Yeni davranış
- Hızlı KWS algılayıcısı çalışmaya devam eder.
- Yerel Base (yoksa Tiny) Whisper modeli hazırsa, kısa konuşma parçaları konuşma/sessizlik kapısıyla ayrılır ve telefonda Türkçe kontrol edilir.
- Yalnız hey + Jarvis/benzer söyleyiş veya tek başına asistan adı uyandırır; normal cümle, model açıklaması ve boş sonuç reddedilir.
- Ses ağ üzerinden gönderilmez veya dosyaya kaydedilmez. En fazla yaklaşık 3,8 saniyelik parça bellekte tutulur; aynı anda bir yerel çözümleme çalışır. Oturum değişirse eski sonuç uygulama açamaz.
- Yerel yedek bir miktar ek gecikme ve pil tüketimi getirir; sürekli kayıt yerine konuşma parçaları işlenir. İşletim sistemi başka görüşme nedeniyle mikrofonu susturursa bu kısıtlama aşılmaz.
- PCM, çözümleme, HIT kaynağı, asistan çağrısı ve Activity açılışı ayrı kaydedilir; konuşmanın metni teşhis günlüğüne yazılmaz.

Doğrulama
- WakeSpeechGate ve WakePhrasePolicy: 3 JVM testi geçti; önceki indirme politikası testleri de geçti.
- 4.3.4 ortak Flutter değişiklikleriyle 172 test, kod analizinde sorun yok.
- Gerçek cihazda 17.11.2026 09:56:50.979: HIT source=kws; 09:56:51.122 SHOW_ASSISTANT accepted=true; 09:56:51.162 SESSION_SHOW source=wake; 09:56:51.220 ACTIVITY_LAUNCH source=wake. JARVIS ön planda doğrulandı. Bu deneme hızlı KWS üzerinden başarılı; yerel Whisper yedeğinin gerçek uyandırma başarısı henüz doğrulanmadı.
- Sonraki ekranda telefon görüşmesi görüldüğünden görüşmeye müdahale edilmedi; 09:57:13 sonrası yeni PCM/decodedSamples sayacı artışıyla uyandırma motorunun yeniden başladığı doğrulandı; telefon görüşmesinin bitişiyle ilişkisi ayrıca ölçülmedi.
- Son APK 4.3.5 / 48, arm64, telefona veriler korunarak yüklendi.
