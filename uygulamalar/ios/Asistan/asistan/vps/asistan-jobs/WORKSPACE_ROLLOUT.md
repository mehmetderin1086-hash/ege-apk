# V2 çalışma alanı — dağıtım kaydı ve geri alma

Kullanıcı 21 Ekim 2026'da “Evet, yedek alıp kur ve doğrula” diyerek üretim dağıtımını onayladı. Aşağıdaki dağıtım yapıldı; talimat bölümleri sonraki bakım için korunuyor.

## Yapılan dağıtım

- Yedek: `/var/backups/asistan-workspace/20261021T015306Z`; SQLite backup API ile alınan DB yedeği `integrity_check=ok`.
- Sınama dizini: `/srv/apps/asistan-workspace-stage/20261021T015306Z`; güncel sunucuda yerelde ve staging'de 60 test geçti.
- Kod: `/srv/apps/asistan-jobs/`; mevcut `voices.json` korundu.
- Caddy: korumalı Claude alanının eşlemesine yalnız `/claude/v2/asistan/*` eklendi; V2 gövde sınırı 52 MB. V1'in 40 KB sınırı ve diğer yollar korundu. Validate ve reload başarılı.
- `asistan-jobs` ve `asistan-runner` için `workspace-20261021.conf` drop-in dosyaları eklendi. Dosya işleme için Python hizmetlerinin bellek üst sınırı 512 MB. Analiz ve ses bayrakları gerçek kabulden sonra açıldı.
- Docker imajı: `asistan-analysis:1`, imaj kimliği `sha256:829ac7bdcf96547d6e6d8f2cbcb4d724eab74bc8963c288957919fc3b9ddf2fb`.
- Gerçek Docker: CSV toplamı 6, XLSX toplamı 12; PNG/CSV çıktıları; ağ ve host sır/soket erişimi engelli, girdi salt okunur.
- Gerçek runner HTTP ve Azure Elif/Aydın kabulü geçti. Dış HTTPS üzerinden belge, kaynaklı araştırma, öğrenme, analiz ve ses görevleri tamamlandı; PNG/CSV/MP3 indirildi.
- MP3 medya kontrolü: 14,256 saniye, 24 kHz, tek kanal. V2 ses kataloğu yalnız Azure listesini okur; ilgisiz SesLab ağ sorgusu görev bütçesini tüketmez.
- 62.500 bayt yükleme, aynı istek kimliğinin tekilleştirilmesi, görev iptali, yetkisiz erişim engeli ve V1 API kontrol edildi.
- APNs anahtarı tanımlı değil; push teslimatı etkin değil. Yeni ücretli API kullanımı kapalı.
- Proxy native web aramasını desteklemediğinde ücretsiz MediaWiki REST fallback'i eklendi; canlı aramada üç Türkçe Wikipedia sonucu geldi. En çok üç kısa özet kaynak olarak kullanılır; tam sayfalar açılmaz ve kapsam Wikipedia olarak açıklanır. Yeni ücretli API çağrılmaz. Üretim HTTPS araştırma işi tamamlandı, üç bağlantı ve kapsam notu çıktıda bulundu.
- Son hata açıklaması düzeltmesi öncesi runtime ayrıca `server.before-web-error-fix.py` adıyla aynı yedek dizinine alındı. Esas dağıtım öncesi `server.py` yedeği korundu.
- Wikipedia fallback dağıtımı öncesi çalışan sürüm `server.before-wikipedia-fallback.py` olarak ayrıca yedeklendi. Bu tamamlayıcı düzeltme öncesi sürüm de `server.before-web-parser-rename.py` olarak yedeklenir. Son kurulan `server.py` SHA-256: `7437d86904ce84429e008aa943b938548e06dea8285b1404270e80e187d1142f`.

## Dağıtım öncesindeki salt okunur inceleme — 21 Ekim 2026

- Python 3.12.3; Docker ve FFmpeg mevcut; `asistan-jobs` ve `asistan-runner` etkin.
- `server.py` SHA-256: `d1ac03e2594c2b3b0738da3b65754ca72bcdf9f4ffb09f1f040b2755c9d27307`.
- `runner.py` SHA-256: `c1327b9af0eecddac8ae560c74cad32f599c32da66132c2fd858544eec4c8611`.
- Dağıtım öncesinde V2 modülleri yoktu. Sunucu kodu repo HEAD'den de eskiydi: repodaki APNs cihaz kaydı/gönderim yolu bulunmuyordu. Paket bu mevcut repo kodunu da içerir; APNs yapılandırılmadıkça push etkinleşmez. Telefon kapalıyken bildirim kabulü bu yüzden ayrıca gereklidir.
- Dağıtımdan hemen önce bu hash'ler yeniden kontrol edildi. Sonraki dağıtımda yeni güncel hash'ler esas alınmalıdır; yukarıdaki değerler tarihsel kayıttır.

## Hazırlanan değişiklik

- `server.py`: mevcut v1 uçları korunarak v2 yönlendirme ve aynı işçi döngüsünde yeni görevler.
- `workspace.py`: eklemeli SQLite şeması, kalıcı adımlar, çıktı/sürüm/dosya deposu.
- `analysis_runner.py` ve `runner.py`: mevcut 8053 hizmetine dosyalı yalıtılmış analiz ucu.
- `audio_workspace.py`: mevcut ses köprüsü ve FFmpeg ile parça bazlı üretim.
- `Dockerfile.analysis`: yeni, ayrı analiz imajı. Eski Python runner imajı değiştirilmez.

## Üretimden önce

1. Sunucudaki mevcut kodun checksum/sürümünü al; yerel repo ile farkını incele. Arada başka değişiklik varsa kör kopyalama yapma.
2. Mevcut SQLite dosyasını SQLite backup API ile tutarlı biçimde yedekle. Sır dosyalarını rapora veya repoya kopyalama.
3. Yeni kodu ayrı staging dizininde, sahte token/model ve ayrı geçici DB ile test et.
4. `python3 -m unittest discover -p 'test_*.py'` çalıştır.
5. Analiz imajını staging için oluştur: `docker build -f Dockerfile.analysis -t asistan-analysis:1 .`.
6. İmajın gerçek digest'ini kayıt altına al. Kabul testinde yalnız beklenen imajı kullan.
7. Runner ile bilinen CSV: 1,2,3 toplamı 6; PNG dosyası gerçek PNG imzası taşımalı. Ağ erişimi ve host dosya erişimi reddedilmeli.
8. Ses işinde mevcut Azure ses kataloğu ve ses köprüsü doğrulanmalı; yeni ücretli sağlayıcı açılmamalı.

## Uygulama sırası

1. Uygulama hizmetinin mevcut kodunun tarihli yedeğini al.
2. Yeni Python modüllerini hizmet klasörüne birlikte koy. `workspace.py`, `analysis_runner.py`, `audio_workspace.py` olmadan server.py tek başına dağıtılmaz.
3. Dosya deposunun hizmet kullanıcısına ait 0700 bir dizin olduğunu doğrula. Varsayılan `<SQLite yolu>.files`.
   Sert kapanıştan kalan, DB kaydı bulunmayan UUID dosyaları açılışta `workspace_orphans` tablosuna alınır. Dosyalar silinmez ve boyutları kotaya dahil edilir. Kurtarma gerektiğinde önce bu tablo ve dosya deposu birlikte yedeklenir; dosya kimliği tek başına kullanıcı çıktısı olarak yayımlanmaz.
4. Mevcut Caddy uygulama yönlendirmesine yalnız `/v2/asistan/*` eşlemesini ekle; v1 ve diğer uygulama yollarını değiştirme. Gerçek mevcut yapı okunmadan hazır bir Caddyfile ile üzerine yazma.
5. Caddy yapılandırmasını validate et; yalnız başarılıysa reload.
6. Görev hizmetini yeniden başlat. Yeni şema ilk açılışta eklenir, çalışan V2 iş varsa paused olur.
7. Yetkisiz v2 isteğinin 401, yetkili capabilities isteğinin 200 döndüğünü test et. Token çıktıda görünmemeli.
8. Temel belge görevini çalıştır; olaylar, çıktı ve iptal/devamı doğrula.
9. Runner güncellemesi ve imaj testi geçince `ASISTAN_ANALYSIS_ENABLED=1` aç. Öncesinde analiz kapalı kalır.
10. Mevcut ses hesabı/kotası doğrulanınca `ASISTAN_AUDIO_ENABLED=1` aç. Öncesinde sesli anlatım kapalı kalır.
11. Fiziksel iPhone'da kapalı ekran → görev tamamlanması → bildirim → doğru çıktı akışını doğrula.

## Geri alma

- Analiz ve sesi ilgili bayraklarını kaldırarak kapat.
- Bu dağıtımın bayrak/bellek ayarları `/etc/systemd/system/asistan-jobs.service.d/workspace-20261021.conf` ve `/etc/systemd/system/asistan-runner.service.d/workspace-20261021.conf` içindedir. Geri alırken yalnız bu dosyaları kaldırıp `systemctl daemon-reload` uygula; diğer drop-in dosyalarına dokunma.
- Kod yedeğine dön ve görev hizmetini yeniden başlat; v1 kayıtları değişmediği için eski API çalışır.
- Eklenen v2 Caddy eşlemesini kaldıracaksan diğer sonradan yapılan değişiklikleri koru, validate/reload yap.
- V2 tablolarını ve kullanıcı dosyalarını silme.
- Tüm DB'yi eski yedeğe otomatik döndürme; yeni kullanıcı verisi kaybolabilir.

## Açık kabul farkları

Bu pakette OAuth hesap merkezi, Telegram/Discord geçidi ve ayrı masaüstü VM'si dağıtıma dahil değildir. Onlar capabilities içinde kapalıdır. Araştırma henüz bağımsız Claim/Evidence veritabanı ve PDF sayfa çıkarımı içermez. Analiz bir kod çalıştırmasıdır; kalıcı Python oturumu değildir.
## 21 Ekim ek dağıtım — GB yükleme

`uploads.py` zorunlu sunucu modülü olarak eklendi. Dosya başına 10 GiB, kota 50 GiB, parça 8 MiB; disk payı 2 GiB. Mevcut Caddy sınırı yeterli olduğu için Caddy ve servis ayarları değiştirilmedi. Üretimden önce yerelde ve ayrı VPS staging dizininde 77 test geçti.

- İlk kod/SQLite yedeği: `/var/backups/asistan-workspace/large-upload-20261021T022956Z`.
- Son dosya bağlantısı korumalarından önceki yedek: `/var/backups/asistan-workspace/large-upload-20261021T023218Z`.
- Kodlar: `server.py`, `workspace.py`, `uploads.py`; hizmet sağlık kontrolü başarılı, SQLite `integrity_check=ok`.
- Son canlı HTTPS kabulü: 2.147.483.665 bayt; kayıp cevap sonrası devam, dosyanın tamamını indirme ve SHA-256 eşitliği, yetkisiz erişimin reddi, V1 sağlığı. Sentetik dosya temizlendi; yarım yükleme sayısı 0.
- Son `server.py` SHA-256: `b370a74c3dee3bddf06120fd06d773f07aa14663d8446ec28080800577de15f6`.
- Son `workspace.py` SHA-256: `76402d1c6676a2c5c9a1cd29a17d58474d5fe0fdeafe26ab713ccfd435d0f336`.
- Son `uploads.py` SHA-256: `22d9c23019bba225c4c481a16509ad97e29b80d26a74ae9e47940d480d181b55`.
- Staging kanıtı: `/srv/apps/asistan-workspace-stage/large-upload-20261021/deployment.json` ve `acceptance.json`. Geri almada kod yedeğine dönülür; eklemeli tablolar ve kullanıcı dosyaları silinmez.

## 21 Ekim ek dağıtım — büyük kaynak araştırması

- Yedek: `/var/backups/asistan-workspace/retrieval-20261021T024415Z`. Etkin iş/yükleme olmadığı kontrol edildi; hizmet durdurulduktan sonra tutarlı SQLite yedeği alındı.
- `server.py`, `workspace.py`, yeni `source_retrieval.py` birlikte kuruldu. Caddy/servis yapılandırması ve mevcut ses kataloğu değiştirilmedi. Sağlık başarısızlığında kod yedeğine otomatik dönüş vardır; DB otomatik geri alınmaz.
- Yerel ve staging Python regresyonu: 98 test geçti. Staging'e mevcut `voices.json` kopyalanmalıdır; test fixture'ı eksik olan ilk staging denemesi bunun ardından tekrar çalıştırılıp geçti.
- Canlı HTTPS: 16.777.250 bayt kaynak, sonda bulunan `982731` gerçek model yanıtında doğru kaynak pasajına bağlandı. 23,28 saniye; servis tepe RSS yaklaşık 43,7 MiB. V1 kontrolü başarılı; test verileri temizlendi.
- `source_retrieval` açık, sınırlar 64 MiB/dosya ve 128 MiB/toplam; `paid_enabled=false`.
- Kanıtlar: `/srv/apps/asistan-workspace-stage/retrieval-20261021/{deployment.json,acceptance.json,acceptance-output.md,tests.log}`.
- Geri alma: bu dağıtımın `server.py` ve `workspace.py` yedeklerini geri koy; önceki sürümde olmayan `source_retrieval.py` kaldırılabilir. `uploads.py` ve eski kullanıcı kayıtları değişmez. Yeni görev checkpoint'leri DB'de korunur.
