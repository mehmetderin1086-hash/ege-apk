JARVIS 4.3.4 (47) — uyandırma teşhisi ve düşük ses düzeltmesi

Değişiklikler
- Mikrofonun düşük seviyeli konuşmasına sınırlı, yumuşatılmış kazanç uygulanır. Dijital sessizlik sıfır kalır; kazanç 32 katı aşmaz, örnekler taşmaz.
- Uyandırma servisi artık gelen PCM paketlerini, algılayıcının işlediği örnekleri, RMS seviyesini, Android sessize alma durumunu ve tetikleme sayısını ölçer. Ses kaydı saklanmaz.
- Android başka görüşme nedeniyle mikrofonu sessize alırsa bildirim bunu açıkça belirtir; mikrofon geri verilince dinleme durumu yenilenir.
- Ayarlar > Görünüm ve telefon > Asistan ve Arka Plan altında Uyandırma durumunu kontrol et düğmesi eklendi.
- Controller kapanırken geç tamamlanan arka plan işlemlerinin kapanmış arayüze bildirim göndermesi engellendi; Whisper indirmesi iptal edilir.

Ölçümler
- 172 Flutter testi geçti. Kod analizi: No issues found.
- Aynı 5 olumlu ses örneği normal / 0,1 / 0,01 genlikte test edildi. Eski algılayıcı 4/5, 3/5, 0/5; yeni ses dengelemesi 4/5, 4/5, 3/5. 7 olumsuz örnek 3 seviyede toplam 21 denemede yanlış tetiklenmedi. Bunlar sentetik örneklerdir, gerçek kullanıcı başarısını garanti etmez.
- Cihazda PCM paket sayısı ve decodedSamples artışı doğrulandı; sesli görüşme dışında silenced=false gözlendi.
- Gerçek kullanıcının Hey Jarvis söyleyişiyle Chrome'dan açılma testi halen bekliyor; otomatik ses örneği fiziksel mikrofon testinin yerini tutmaz.

Kaynak: https://developer.android.com/reference/android/media/AudioRecordingConfiguration#isClientSilenced()
