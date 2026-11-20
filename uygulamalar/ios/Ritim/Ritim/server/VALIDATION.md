# Doğrulama kaydı — 26 Ekim 2026

- Python 3.9.6, yt-dlp 2026.10.21, FFmpeg 6.0, Node 24 ile yerel Mac üzerinde çalıştırıldı.
- `python3 -m unittest discover -s tests -v`: **15/15 geçti** (11.781 saniye). Ağsız testler; kimlik doğrulama, URL/SSRF reddi, kuyruk/sınırlar, subprocess ilerleme/iptal, restart, gerçek FFmpeg dönüşümü ve HTTP dosya aktarımı içerir.
- `GET /health`: 200; anahtarsız korunan istek: 401; doğru Bearer ile `GET /v1/status`: 200.
- Gerçek YouTube kaynak testi: yt-dlp'nin [kendi test listesinde](https://github.com/yt-dlp/yt-dlp/blob/master/yt_dlp/extractor/youtube/_video.py) bulunan 5 saniyelik `gHKT4uU8Zng`, “dlp test video title primary (en-GB)” / cole-dlp-test-acc.
- Bu kaynaktan MP3 işi tamamlandı; authenticated dosya isteği **200, audio/mpeg, 123000 byte**. İndirilen dosyanın tamamı FFmpeg ile hatasız çözüldü.
- Aynı kaynaktan MP4 işi tamamlandı; authenticated dosya isteği **200, video/mp4, 24267 byte**. İndirilen dosyanın tamamı FFmpeg ile hatasız çözüldü.
- Eski `BaW_jenozKc` örneği artık mevcut değil; servis “Video kullanılamıyor…” hatasını doğru verdi. [Upstream kaldırılan test URL kaydı](https://github.com/yt-dlp/yt-dlp/issues/12263).
- `start.sh`, `bootstrap.sh`, `install-launch-agent.sh` için `sh -n` geçti.

Bu kayıt sunucu ve üretilen medya doğrulamasıdır. iPhone'a kurulum, iOS içe aktarma, cihazda oynatma ve kilit ekranı kabulünü tek başına kanıtlamaz. YouTube erişimi kaynağa/ağa/zamana göre değişebilir.


## Toplu indirme / API 1.1 doğrulaması

- `python3 -m unittest discover -s tests -v`: **27/27 geçti** (13.942 saniye). Önceki 15 test korunmuştur. Yeni testler: 600 kaynak öğe içinde 7 yinelenen/özel/silinmiş/geçersiz/canlı öğenin ayrılması, 1.100 öğeden 1.000 sınırı, sıra ve kanonik video kimliği, sınırlı Mix çözümlemesi, Bearer, tek çözümleyici, iptal/zaman/çıktı sınırı, restart, 2.500 terminal kayıt, kalıcı aktarım onayı, onay sırasında disk yazma hatası ve çökme aralığı.
- Yeni kodla **yalıtılmış yerel HTTP sunucusu** üzerinden gerçek Bearer istekleri kullanıldı; canlı launchd servisi bu doğrulama tarafından yeniden başlatılmadı.
- Kullanıcının `RDEMTPfPURSbYpb0YHCKyIG37Q` bağlantısı **“Mix - Adele”** olarak çözüldü: `limit:1000` ile **66 öğe**, `skipped:0`, `truncated:false`, **4.31 saniye**. Bu işlem yalnızca metadata okudu; bu Mix'ten medya indirilmedi. Otomatik Mix o anki öneri listesidir; farklı zamanda farklı sayıda/sırada öğe dönebilir.
- Aynı Mix için `limit:25` önizlemesi 25 öğe ve `truncated:true` verdi. Canlı inceleme `playnext=1` çıkarıldığında YouTube'un “unviewable” yanıtını ortaya çıkardı; RD normalizasyonu bu sabit parametreyi ekler. Takip parametreleri tutulmaz.
- [yt-dlp'nin herkese açık test listesi](https://github.com/yt-dlp/yt-dlp/blob/master/yt_dlp/extractor/youtube/_tab.py) içindeki `PLt5yu3-wZAlQLfIN0MMgp0wVV6MP3bM4_` listesi 1 öğe ile **1.36 saniyede** çözüldü; medya indirilmedi.
- Beş saniyelik upstream `gHKT4uU8Zng` örneği MP3 (**123000 byte, audio/mpeg, 6.36 saniye**) ve MP4 (**24267 byte, video/mp4, 6.31 saniye**) olarak indirildi. Her dosya authenticated HTTP 200 ile alındı ve tamamı gerçek FFmpeg ile hata vermeden çözüldü. Kalıcı kopya sonrası `POST /ack` HTTP 200 ve sonraki `/file` HTTP 410 verdi.
- Makinece okunabilir sonuçlar: [validation_bulk_live.json](validation_bulk_live.json). Kaynak değişikliklerinde `git diff --check -- server` temiz.

Bu sonuçlar sunucu davranışını doğrular. Yüzlerce gerçek medya dosyası indirilmedi; 1.000 öğe sınırı ve hata senaryoları kontrollü test verisiyle sınandı. iPhone kabulü ayrıca uygulama testleri ve fiziksel cihaz akışıyla doğrulanmalıdır.


## Paralel hazırlama / API 1.2 doğrulaması

- `python3 -m unittest discover -s tests -v`: **33/33 geçti** (22.252 saniye). Mevcut 27 test korunmuş, altı eşzamanlılık testi eklenmiştir.
- Kontrollü indirme aracıyla **dört farklı gerçek subprocess aynı anda canlı** olarak doğrulandı; beşinci iş kuyrukta kaldı. Bir iş iptal edilince yalnızca onun işlemi/dosyaları durdu; diğer üç indirme sürdü ve boşalan yere beşinci iş geçti.
- Bir dosya tamamlanıp aktarım onayı alırken diğer üç işin kısmi dosyaları korundu. Toplam depolama hesaplaması tamamlanma ve eşzamanlı onaylarda iki kez saymadı; tüm onaylardan sonra disk ve önbellek sayaçları sıfırlandı.
- Dört işin ayrı ayrı sınır altında kalıp toplamda 3.500 byte sınırını aştığı senaryo durduruldu. Toplam kota yalnızca kontrol edilen işin dosyasına bakılarak hesaplanmaz.
- Dört aktif + iki bekleyen iş sırasında servis düzgün kapatıldı; tüm çalışan süreçler durdu. Yeniden başlatmada altı işin tamamı kimliği korunarak kuyruğa döndü ve tamamlandı. Eski tamamlanmış/onaylanmış kayıt testleri de geçti.
- Varsayılan çalışan sayısı **4**; `RITIM_WORKERS` / `--workers` için **1–6** aralığı doğrulandı. Tek çalışan seçeneğinde ikinci işin kuyrukta beklediği sınandı. `health` ve `status` uç noktalarında `worker_limit` ve `parallel_jobs` yeteneği test edildi.
- Gerçek FFmpeg MP3/MP4 üretme, tam çözme ve MP4 faststart kontrolü yeni işlem başına CPU sınırlarıyla da geçti: çözme/kodlama için ikişer, filtreleme için bir iş parçacığı.

Bu paralellik testleri gerçek subprocess'ler ve kontrollü medya verisi kullanır; aynı anda dört gerçek YouTube videosu indirilmiş olduğunu iddia etmez. Bu çalışma canlı launchd servisini yeniden başlatmadı veya kullanıcının sürmekte olan kuyruğunu değiştirmedi; canlı geçiş root tarafından koordine edilir.
