# Mehmet Asistan yardımcı görev servisi

Ana uygulama iPhone'da çalışır. Bu servis metin, araştırma ve otomatik yönlendirilen kodlama işlerini yürütür. Telefon kontrolü ve mesaj gönderimi yoktur; görev bitince isteğe bağlı APNs bildirimi gider (aşağıda).

## V2 çalışma alanı — 21 Ekim 2026

V2 üretime kurulmuştur. `/v2/asistan/*` mevcut kimlik doğrulaması altında belge, kaynak dosyalı araştırma, öğrenme, dosyalı veri analizi ve sesli anlatım görevlerini sunar. Çıktılar ve sürümler kalıcıdır; iptal/devam ve adım kayıtları desteklenir. Yeni ücretli API kullanımı kapalıdır. V1 davranışı aşağıda ayrı açıklanır.

Gerçek kabul: 60 sunucu testi, dış HTTPS üzerinden beş görev türü, CSV/XLSX hesabı, PNG/CSV/MP3 indirme, Azure Elif/Aydın ve ağsız Docker analizi. Proxy native web aramasını reddederse sunucu ücretsiz MediaWiki REST API'ye düşer; en çok üç Wikipedia arama özeti kullanır, tam sayfa açmaz ve kapsamı açıkça bildirir. Canlı MediaWiki araması geçti. Yeni ücretli API kullanılmaz. APNs anahtarı tanımlı olmadığı için push teslimatı henüz etkin değildir.

Dağıtım yedeği, imaj kimliği, sınırlar ve geri alma: [WORKSPACE_ROLLOUT.md](WORKSPACE_ROLLOUT.md).

## Mevcut V1 hizmeti

- Sunucu: mevcut VPS, `/srv/apps/asistan-jobs/server.py`, systemd `asistan-jobs.service`, yalnız `127.0.0.1:8052`.
- Caddy: mevcut `/dersdas/claude/v1/asistan/*` korumalı uygulama alanı, mevcut kişisel kimlik doğrulaması. Servis de kimliği doğrular. Anahtarlar repo/iPhone paketinde değil, `/etc/asistan-jobs.env` içinde.
- Ana sağlayıcı: mevcut CLIProxy `/v1/responses`, GPT-6.1-Sol. Araştırmada proxy `unsupported_capability` HTTP 400 verirse mevcut `image-fallback.env` OpenAI API hesabı resmi Responses/web_search yoluyla kullanılır. API ücret doğurabilir; uygulamada belirtilir. Yeni hesap/abonelik oluşturulmadı.
- SQLite: `/var/lib/asistan-jobs/jobs.sqlite3`; FIFO tek işçi, en çok 10 etkin iş, 8000 karakter/görev, 7 gün saklama. Aynı UUID tekrarında aynı görev döner. Servis yeniden başlarsa çalışan iş hata olarak işaretlenir, otomatik tekrar yapılmaz; sıradakiler devam eder.
- Zamanlanmış rutinler: `/v1/asistan/routines`; metin/araştırma/kod, 5–10080 dakika aralığı, en çok 50 kayıt. Her çalışma normal görev kuyruğuna benzersiz ve yinelenemez bir kimlikle eklenir. Duraklatma, sürdürme ve silme desteklenir; telefon kapalıyken sunucu zamanlayıcısı çalışır.
- İptal sağlayıcıya gönderilmiş isteği kesmeyebilir; sonucu kaydetmez. Python kodu aşağıdaki izole ortamda çalıştırılır; diğer diller yalnız üretilir.
- Kapatma: uygulama Ayarlar'dan yeni sunucu işleri kapatılabilir. Önceki işler Atölye > Sunucu görevleri bölümünden durdurulur.
- Sunucu geri alma: `systemctl disable --now asistan-jobs`; yalnız eklenen `handle /v1/asistan/*` bloğunu Caddy'den kaldırıp validate/reload yap. Caddy başlangıç yedeği `/etc/caddy/Caddyfile.bak-asistan-jobs-20261018`; başka sonradan değişiklik varsa tamamını geri kopyalama. Diğer servisler değiştirilmez.

Yerel test: `python3 -m unittest discover -s vps/asistan-jobs -v`. `probe.py` sadece sunucuda mevcut kimlikleri okuyup kişisel veri içermeyen iki test işi gönderir; kimlikleri çıktıya yazmaz.

Python çalıştırıcı: `runner.py`, `asistan-runner.service`, loopback 8053, ayrı gizli kimlik. Docker `python:3.12-alpine`, ağ yok, salt okunur kök, 128 MB, 32 PID, 0.5 CPU, 25 saniye; yalnız görev dosyası salt okunur bağlanır. Anahtar/host dizini/Docker soketi konteynere verilmez. Çıkış kodu ve stdout gerçek sonuç olarak raporlanır. Genel amaçlı uzak bilgisayar ajanı değildir.

Ses köprüsü: GET `/v1/asistan/voices`, POST `/v1/asistan/speak`. Mevcut İkra loopback 8788 `/v1/status` ve `/v1/speak` kullanılır. `ASISTAN_SPEECH_TOKEN` sunucudaki özel environment dosyasından alınır. Azure kuyruğu mevcut sağlayıcı servisiyle ortaktır; yeni bağımsız Azure istek sırası yoktur. `voices.json` İkra kataloğundan oluşturulmuştur; SesLab sesleri canlı eklenir.

Gerçek zamanlı Live: POST `/v1/asistan/live-token`, sunucudaki `ASISTAN_GEMINI_API_KEY` veya `GEMINI_API_KEY` ile tek kullanımlık ve kısa ömürlü, yalnız `gemini-3.8-live` ses yapılandırmasına kilitli anahtar üretir. Kalıcı sağlayıcı anahtarı iPhone'a gönderilmez. `ASISTAN_DIRECT_LIVE=0` iken uygulama WebSocket beklemeden Antigravity hesabındaki Gemini 3.8 Flash ile sıralı, kesilebilir sesli diyaloğa geçer. Bu varsayılan iPhone deneyiminde daha hızlıdır; doğrudan Gemini kredisi hazır olduğunda değişken tekrar `1` yapılabilir.

Telefona bildirim (APNs, P4.6): uygulama açılışta (bildirim izni verilmiş ve sunucu görevleri açıkken) APNs cihaz jetonunu POST `/v1/asistan/devices` ile kaydeder (`{token, ortam: development|production, paket}`; jeton 64-200 onaltılık karakter, en çok 5 cihaz, en eskisi düşer). DELETE `/v1/asistan/devices/<token>` kaydı siler. Görev ya da rutin çalışması bittiğinde (yalnız satır gerçekten güncellendiyse; bu arada iptal edilen işte bildirim gitmez) kayıtlı cihazlara 'Sunucu görevi bitti' / 'Sunucu görevi tamamlanamadı' başlıklı, görev metninin ilk 120 karakterini taşıyan bildirim gider; `gorev` alanı görev kimliğidir, dokununca uygulama Atölye'yi açar. Gönderim hatası görevi etkilemez; 410 ya da 400 BadDeviceToken dönen jeton silinir.

Kurulum (hesap ve sunucu işi, ajanlar yapmaz):
1. Apple Developer → Certificates, Identifiers & Profiles → Keys → yeni anahtar, "Apple Push Notifications service (APNs)" işaretli; .p8 bir kez indirilir, Key ID not edilir.
2. Uygulama kimliği `com.mehmetderin.asistan` için Push Notifications yeteneği açık olmalı (otomatik imza `aps-environment` yetkisiyle profili yeniler).
3. VPS'te .p8 dosyasını `/etc/asistan-jobs/apns.p8` gibi yalnız servis kullanıcısının okuyabileceği (600) bir yere koy; `/etc/asistan-jobs.env`'e `APNS_KEY_PATH=…`, `APNS_KEY_ID=…`, `APNS_TEAM_ID=838FF89FZ8`, `APNS_TOPIC=com.mehmetderin.asistan` ekle.
4. Yeni `server.py`'yi `/srv/apps/asistan-jobs/` altına kopyala, `systemctl restart asistan-jobs`. Caddy değişmez (`/v1/asistan/*` bloğu devices ucunu kapsar).
5. İmza `cryptography` kuruluysa onunla, değilse `openssl dgst -sha256 -sign` alt süreciyle atılır; ek paket gerekmez. Gönderim `curl --http2` ile yapılır; sağlayıcı belirteci 50 dk önbellekte tutulur ve komut satırına yazılmaz (600 izinli geçici başlık dosyası).
6. APNS_KEY_PATH ya da APNS_KEY_ID yoksa ya da dosya bulunamazsa bildirim sessizce kapalıdır; cihaz kaydı yine kabul edilir.

Geliştirme kurulumu (`./telefona-kur.sh`) sandbox jetonu üretir (`ortam: development` → api.sandbox.push.apple.com); TestFlight/App Store sürümü production jetonu üretir.
## 21 Ekim 2026 — büyük dosya kasası

`uploads.py` ile dosya başına 10 GiB, toplam 50 GiB kota ve 8 MiB parçalı aktarım desteklenir. Kota `ASISTAN_FILE_MAX_BYTES` ve `ASISTAN_STORAGE_BYTES` ile sunucuda sınırlandırılabilir; gerçek boş alan ayrıca denetlenir, 2 GiB disk payı korunur. Yarım yüklemenin toplam boyutu kotadan rezerve edilir. `GET capabilities` gerçek sınırları ve `resumable_uploads` yeteneğini verir.

- `POST /v2/asistan/uploads`: `Idempotency-Key` UUID; JSON `{name,size,sha256}`.
- `GET /v2/asistan/uploads`: yarım yüklemeleri başka istemcide de kurtarır.
- `GET /v2/asistan/uploads/{id}`: kalıcı `offset`, toplam boyut, durum.
- `PUT /v2/asistan/uploads/{id}`: ham parça; `Upload-Offset`, `X-Chunk-SHA256`, `Content-Length` gerekir. Konum çatışmasında GET ile yeniden eşitle.
- `POST /v2/asistan/uploads/{id}/complete`: tam dosya SHA-256 doğrulaması, idempotent yayınlama.
- `DELETE /v2/asistan/uploads/{id}`: yarım parçaları siler, kotayı serbest bırakır.
- `GET /v2/asistan/files`: dosya listesi; `GET /files/{id}` akışla indirir. `DELETE /files/{id}` yalnız çalışmalara/ara sonuçlara bağlı olmayan dosyaları siler.

Her uç mevcut kişisel token yetkisini ister. Caddy'nin 52 MB sınırı korunur; her parça bunun altındadır. Aynı anda üç gövde okunur. Dosya yükleme sınırı model/analiz işleme sınırından ayrıdır. PDF kaynak dönüştürme istemcide yapılır; ham GB dosyaları otomatik olarak modele gönderilmez.
## Büyük metin kaynak araştırması

`source_retrieval.py`, `workspace.py` ve `server.py` birlikte dağıtılır. Araştırmada UTF-8 TXT/Markdown/CSV/JSON dosya başına 64 MiB, toplam 128 MiB desteklenir. 64 KiB akışlı tarama, 300 karakter örtüşme ve Türkçe sözcük/önek sıralaması kullanılır; en fazla 12 pasaj/36.000 karakter model bağlamına girer. Kaynak SHA-256, bayt/satır konumları ve kısmi kapsam notu korunur. Seçim mevcut görev checkpoint'inde saklanır. Embedding servisi veya yeni bağımlılık yoktur. Diğer görevlerin ve ham PDF'in sınırları değişmez.

Staging testlerini çalıştırırken mevcut `voices.json` kataloğunu da staging'e koyun; üretim ses kataloğunu şablonla değiştirmeyin. Test komutu: `python3 -m unittest discover -p 'test_*.py'`.
