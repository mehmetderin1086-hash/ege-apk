# DownloadHub

DownloadHub, Apple Silicon macOS üzerinde yalnız yerel makinede çalışan, Türkçe web
arayüzlü bir indirme yöneticisidir. Doğrudan HTTP/HTTPS dosyaları için aria2'yi ve
aria2 yokken güvenli tek akış geri dönüşünü; YouTube ve yt-dlp'nin desteklediği medya
siteleri için yt-dlp, FFmpeg ve Deno'yu tek bir kalıcı görev kuyruğunda birleştirir.

Uygulama özgün bir projedir; Internet Download Manager adı, kodu, logosu veya arayüz
varlıkları kullanılmaz. DRM, CAPTCHA ve erişim kontrollerini aşmaz. Yalnızca sahip
olduğunuz veya indirme izniniz olan içeriği indirin ve kaynak sitenin koşullarına uyun.

## Mevcut özellikler

- `http://127.0.0.1:8765` üzerinde FastAPI, Jinja2 ve yerel JavaScript web arayüzü
- HTTP/HTTPS ile medya URL'lerini ayıran indirmeden-önce inceleme
- aria2 ile segmentli, aria2 yokken tek akış doğrudan indirme ve ortak SQLite kuyruğu
- Duraklatma, sürdürme, iptal, yeniden deneme, zamanlama, öncelik ve hız bilgisi
- SSE ile canlı görev snapshot'ı ve olay akışı
- Video/ses profilleri, altyazı, küçük resim, bilgi JSON'u ve oynatma listesi seçimi
- Finder'da gösterme/açma, geçmiş, filtreler ve tip güvenli ayarlar
- Tek kullanımlık kodla eşleşen, Manifest V3 Chromium eklentisi
- Loopback zorlaması, URL/çıktı yolu korumaları, CSP, CSRF ve gizli bilgi maskeleme
- macOS kullanıcı veri dizinleri, döner loglar ve yeniden başlatmada görev kurtarma

Kanal/oynatma listesi abonelik tablosu ileri uyumluluk için vardır; otomatik abonelik
taraması v0.1 kullanıcı özelliği değildir. Torrent, magnet, FTP, DRM çözme, CAPTCHA
çözme ve sürekli tarayıcı trafiği gözetimi kapsam dışıdır.

## Gereksinimler

- Apple Silicon (`arm64`) Mac
- macOS 13 veya daha yeni
- İnternete açık kaynak bağımlılıklarını kurmak için `uv`
- Geliştirmede Python 3.12; bootstrap bunu uv ile yönetir

Homebrew gerekmez. Proje, uzak bir shell kurulum betiğini otomatik çalıştırmaz.

## Hızlı başlangıç

```bash
cd /Users/mehmetderin/Documents/DownloadHub
zsh scripts/bootstrap.sh
zsh scripts/run.sh --open
```

`bootstrap.sh`, Python 3.12'yi uv üzerinden hazırlar, yoksa `uv.lock` oluşturur ve
kilitli bağımlılıkların tüm geliştirme/paketleme ekleriyle birlikte düzenlenebilir
olmayan kurulumunu yalnız proje içindeki `.venv` ortamına yapar. Ardından SHA-256 ile
sabitlenmiş Deno 2.9.3 binary'sini indirip doğrular ve aria2 1.37.0'ı doğrulanmış resmî
kaynak arşivinden AppleTLS ile derlemeyi dener. aria2 derlemesi için Apple Command Line
Tools gerekir; derleme mümkün değilse uygulama güvenli tek akış HTTP motoruyla
çalışmaya devam eder. Daha sonra tarayıcıdan <http://127.0.0.1:8765> adresini
açabilirsiniz.

Veri ve sonuçlar kaynak kod deposuna yazılmaz:

| Amaç | Varsayılan yol |
|---|---|
| Veritabanı ve uygulama sırrı | `~/Library/Application Support/DownloadHub/` |
| Geçici/parçalı dosyalar | `~/Library/Caches/DownloadHub/` |
| Döner loglar | `~/Library/Logs/DownloadHub/` |
| İndirilenler | `~/Downloads/DownloadHub/` |

İndirme klasöründe `Videolar`, `Müzik`, `Resimler`, `Belgeler`, `Arşivler` ve `Diğer`
alt klasörleri otomatik hazırlanır.

## Runtime güvenlik modeli

Depodaki [`runtime-manifest.json`](runtime-manifest.json) bileşen bazında bilinçli
olarak **fail-closed** çalışır. Resmî macOS arm64 Deno 2.9.3 asset'i ve aria2 1.37.0
yayın kaynak arşivi SHA-256 değerleriyle sabitlenmiş ve etkindir. aria2, AppleTLS ile
HTTP/HTTPS odaklı arm64 binary olarak yerelde derlenir; Homebrew kullanılmaz. Bağımsız
FFmpeg ve isteğe bağlı bağımsız yt-dlp ise güvenilir yayın varlığı sabitlenene kadar
devre dışıdır. Bootstrap, runtime yöneticisini açıkça çağırarak yalnız manifestte etkin
olan bileşenleri resmî HTTPS adreslerinden indirir: Deno binary'sini doğrulayıp kurar,
aria2 kaynak arşivini doğrulayıp yerelde derler. Uzak shell betiği veya sabitlenmemiş
native binary çalıştırılmaz. Aynı işlemler aşağıdaki açık `install` komutlarıyla da
tekrarlanabilir.

Durumu görmek için:

```bash
.venv/bin/python scripts/runtime_manager.py status
.venv/bin/python scripts/diagnose.py
```

Devre dışı bir bileşeni etkinleştirecek yayın sorumlusu şunları yapmalıdır:

1. Resmî yayın sayfasından tam sürümü ve macOS arm64 varlığını seçmek.
2. Yayıncının checksum/imzasını bağımsız olarak doğrulamak.
3. Manifestte `version`, HTTPS `url`, arşiv içindeki `binary_path` ve gerçek 64 haneli
   küçük harf `sha256` değerini kaydetmek.
4. İlgili lisansları, build yapılandırmasını ve gerekiyorsa corresponding-source
   teklifini yayın malzemesine eklemek.
5. Ancak bundan sonra `enabled` değerini `true` yapmak ve kurulumu çalıştırmak.

```bash
.venv/bin/python scripts/runtime_manager.py install aria2c deno
.venv/bin/python scripts/runtime_manager.py verify aria2c
.venv/bin/python scripts/runtime_manager.py verify deno
.venv/bin/python scripts/runtime_manager.py verify --required
```

Kurucu HTTPS dışındaki adresi, placeholder/boş hash'i, hash uyuşmazlığını, beklenmeyen
arşiv üyesini ve arm64 olmayan Mach-O dosyasını reddeder. aria2 kaynak derlemesi için
Apple Command Line Tools içindeki `clang`, `make` ve sistem SDK'sı gerekir. Derleme
çıktısı yalnız Apple sistem kütüphanelerine bağlanır ve çalıştırılmadan önce mimarisi
doğrulanır. Yeni sürüm kurulurken mevcut binary `runtime/backups/` altında korunur;
açık geri alma işlemi şu şekildedir:

```bash
.venv/bin/python scripts/runtime_manager.py rollback aria2c
```

Geri alınan binary, eski manifest kaydı da geri yüklenene kadar üretim doğrulamasından
geçmez. Bu bilinçli davranış, eski binary'nin yeni bir manifest sürümü gibi sunulmasını
engeller.

Geliştirmede sistemde zaten bulunan araçlar aşağıdaki ortam değişkenleriyle açıkça
seçilebilir; uygulama yine yalnız loopback üzerinde çalışır:

```bash
export DOWNLOADHUB_ARIA2_PATH=/absolute/path/to/aria2c
export DOWNLOADHUB_FFMPEG_PATH=/absolute/path/to/ffmpeg
export DOWNLOADHUB_DENO_PATH=/absolute/path/to/deno
export DOWNLOADHUB_YT_DLP_PATH=/absolute/path/to/yt-dlp
zsh scripts/run.sh --open
```

Kilitli Python `yt-dlp` 2026.07.04 paketi standalone yt-dlp geri dönüşüdür.
`imageio-ffmpeg` 0.6.0, Homebrew olmadan FFmpeg 7.1 arm64 binary'si sağlar; açıkça
yapılandırılmış veya manifestten kurulmuş FFmpeg bunun önüne geçer. Tam YouTube desteği
için FFmpeg ile güncel yt-dlp JavaScript desteği/Deno gerekir. aria2 bulunmazsa
HTTP/HTTPS dosyaları tek akışla
indirilebilir; çok segmentli hızlandırma ve aria2 oturum devamı için doğrulanmış aria2c
gerekir.

## Web API

Etkileşimli OpenAPI belgesi servis çalışırken <http://127.0.0.1:8765/api/docs>
adresindedir. Temel uçlar:

| Yöntem ve yol | Davranış |
|---|---|
| `GET /health`, `GET /readyz` | Servis ve runtime hazırlığı |
| `POST /api/v1/inspect` | URL'yi indirmeden inceler |
| `POST /api/v1/jobs` | İdempotent görev oluşturur |
| `GET /api/v1/jobs` | Sayfalı ve filtrelenebilir görev listesi |
| `GET /api/v1/jobs/{id}` | Görev, öğe ve artifact ayrıntıları |
| `POST /api/v1/jobs/{id}/pause` | Görevi idempotent biçimde duraklatır |
| `POST /api/v1/jobs/{id}/resume` | Görevi sürdürür |
| `POST /api/v1/jobs/{id}/cancel` | Görevi iptal eder |
| `POST /api/v1/jobs/{id}/retry` | Başarısız görevi yeniden kuyruğa alır |
| `POST /api/v1/jobs/{id}/reveal` | Kayıtlı artifact'ı Finder'da gösterir |
| `POST /api/v1/jobs/{id}/open` | Kayıtlı artifact'ı açar |
| `GET /api/v1/events?after=…` | Snapshot ve artımlı SSE olayları |
| `GET`, `PUT /api/v1/settings` | Tip güvenli uygulama ayarları |
| `POST /api/v1/pair/start` | Beş dakikalık eşleştirme kodu üretir |
| `POST /api/v1/pair/complete` | Eklentiye kapsamlı yerel token verir |
| `GET /api/v1/pair/clients` | Panelde etkin eşleştirilmiş istemcileri listeler |
| `POST /api/v1/pair/revoke` | Eklenti erişimini iptal eder |

API ham shell/yt-dlp argümanları veya serbest çıktı yolları kabul etmez. URL'lerde yalnız
HTTP/HTTPS desteklenir; loopback, link-local, metadata ve özel ağ hedefleri varsayılan
olarak engellenir. İnceleme ve indirme trafiği yerel `SafeOutboundProxy` üzerinden
geçer: hedef her yeni bağlantıda yeniden çözümlenir, tüm IP'ler politika açısından
doğrulanır ve bağlantı doğrulanan IP'ye sabitlenir. Her yönlendirme hedefi de aynı
işlemden geçtiği için DNS rebinding veya yönlendirmeyle özel ağa kaçış kabul edilmez.

Sorgu bölümünde token, imza veya benzeri sır taşıdığı algılanan URL'lerin gizli
değerleri veritabanına ve loglara yazılmaz. Ham kaynak URL yalnız çalışan süreçte RAM'de
tutulur; uygulama yeniden başlatılırsa bu tür kesilmiş bir görevin yeni ve geçerli
kaynağı edinmek için yeniden incelenmesi gerekir.

## Chromium eklentisi

Geliştirme kurulumu:

1. Chrome, Edge veya Brave'de eklentiler sayfasını açın.
2. Geliştirici modunu etkinleştirip **Paketlenmemiş öğe yükle** seçeneğiyle bu deponun
   `extension/` klasörünü seçin.
3. DownloadHub web panelinden eşleştirme kodu üretin.
4. Eklenti popup'ında kodu girin.

Eklenti yalnız `activeTab`, `scripting`, `contextMenus`, `storage` ve
`http://127.0.0.1:8765/*` izinlerini kullanır. `<all_urls>` ve `webRequest` yoktur.
Geçerli sayfayı, sağ tıklanan bağlantı/resmi ve DOM'da bulunan bağlantı, resim, video ve
ses kaynaklarını kuyruğa gönderebilir. `blob:` medya için geçici blob yerine sayfa URL'si
medya incelemesine gönderilir. Web paneli etkin eşleştirilmiş istemcileri gösterir;
kaybolan veya artık güvenilmeyen bir eklentinin token'ı panelden anında iptal edilebilir.

Dağıtım ZIP'i oluşturmak için:

```bash
zsh scripts/package_extension.sh
```

Paketleyici Manifest V3'ü ve dar izin kümesini tekrar doğrular, anahtar/gizli dosya
adlarını reddeder ve mevcut ZIP'in üzerine yazmaz.

## Veritabanı migration'ları

Alembic, `downloadhub.models.Base.metadata` ile uygulamanın gerçek veritabanı URL'sini
kullanır. İlk şema ve sonraki revizyonlar `migrations/versions/` altında tutulur.

```bash
PYTHONPATH=src uv run --locked alembic upgrade head
PYTHONPATH=src uv run --locked alembic current
```

Yeni revizyon:

```bash
PYTHONPATH=src uv run --locked alembic revision --autogenerate -m "kısa açıklama"
```

Otomatik üretilen migration mutlaka incelenmelidir. Kullanıcı veritabanında downgrade
öncesinde yedek alın.

## Test ve geliştirme

```bash
PYTHONPATH=src uv run --locked pytest
uv run --locked ruff check .
PYTHONPATH=src uv run --locked alembic check
.venv/bin/python scripts/diagnose.py --json
```

Yerel geliştirme sunucusu:

```bash
zsh scripts/run.sh --reload --open
```

`DOWNLOADHUB_` önekiyle ayarlar değiştirilebilir. `DOWNLOADHUB_HOST` için yalnız
`127.0.0.1` kabul edilir. Testlerde gerçek kullanıcının veri dizinini kullanmak yerine
geçici `DOWNLOADHUB_DATA_DIR`, `DOWNLOADHUB_CACHE_DIR`, `DOWNLOADHUB_LOG_DIR` ve
`DOWNLOADHUB_DOWNLOAD_DIR` değerleri verin.

## `.app`, DMG ve imzalama

Doğrulanmış aria2 ve zorunlu Deno runtime'ları, kilitli imageio-ffmpeg ve Python yt-dlp
geri dönüşleriyle üretim paketi:

```bash
zsh scripts/build_app.sh
zsh scripts/build_dmg.sh
```

Paketlenen `DownloadHub.app`, `assets/DownloadHub.icns` içindeki yerel macOS
simgesini kullanır.

File Provider özniteliklerinin imzalı paketi etkilememesi için gerçek uygulamayı
`~/Applications` altına kurup Masaüstü'ne bağlantı ekleyin:

```bash
zsh scripts/install_desktop_app.sh
```

Runtime manifesti henüz yayın için hazır değilken yalnız yerel arayüz/paketleme testi:

```bash
zsh scripts/build_app.sh --development
```

`--development`, zorunlu runtime doğrulamasını yalnız paketleme iskeletini sınamak için
atlar ve dağıtım için kullanılmamalıdır. Normal üretim paketi doğrulanmış aria2'yi
gömerek segmentli HTTP indirmelerini etkinleştirir; çalışma anında aria2 kullanılamazsa
güvenli tek akış geri dönüşü korunur. Her paketleme betiği mevcut çıktının üzerine
yazmayı reddeder. DMG; uygulamanın yanında GPLv3 metnini, üçüncü taraf bildirim ve
kurulu Python paketlerinin lisans dosyalarını, runtime manifestini ve derlemede
kullanılan DownloadHub kaynak kodu ZIP'ini içerir. Aynı kaynak ZIP'i doğrulama ve GPL
kaynak sunumu için `dist/DownloadHub-<sürüm>-source.zip` olarak ayrıca üretilir.

Developer ID varsa kimlik ortamdan verilebilir; betikler kimlik bilgisi saklamaz:

```bash
export DOWNLOADHUB_CODESIGN_IDENTITY='Developer ID Application: Example (TEAMID)'
zsh scripts/build_app.sh
zsh scripts/build_dmg.sh
```

Kimlik yoksa `.app` ad-hoc imzalanır ve notarize edilemez. Notarizasyon, kimlik
bilgilerini yalnız Keychain profilinden okuyan ayrı bir yayın adımıdır:

```bash
export DOWNLOADHUB_NOTARY_PROFILE='downloadhub-notary'
zsh scripts/notarize.sh dist/DownloadHub-0.1.0-macOS-arm64.dmg
```

Dağıtımdan önce GPL kaynak sunumu ve
[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) içindeki her yükümlülük kontrol
edilmelidir.

İmzalı uygulama `/Applications` altındayken isteğe bağlı oturum açılışı görevi:

```bash
.venv/bin/python scripts/launch_agent.py install
.venv/bin/python scripts/launch_agent.py status
.venv/bin/python scripts/launch_agent.py disable
```

`disable`, plist'i silmek yerine uygulama veri dizininde zaman damgalı yedeğe taşır.
LaunchAgent servisi loopback'e zorlar ve oturum açılışında tarayıcı penceresi açmaz.

## Proje yapısı

```text
src/downloadhub/       FastAPI uygulaması, kuyruk, motorlar ve güvenlik
src/downloadhub/templates/
src/downloadhub/static/ Türkçe yerel web arayüzü
extension/              Manifest V3 Chromium eklentisi
migrations/             Alembic ortamı ve sürümlü şema değişiklikleri
scripts/                Tanılama, runtime, başlatma ve paketleme araçları
runtime/                Doğrulanmış yerel binary'ler; Git'e girmez
tests/                  Birim, entegrasyon ve güvenlik testleri
```

## Sorun giderme

- **Health `degraded`:** `scripts/diagnose.py` ve `runtime_manager.py status` çıktısına
  bakın. imageio-ffmpeg geri dönüşünü ve kurulu Deno'yu doğrulayın.
- **aria2 bulunamadı:** doğrulanmış runtime'ı kurun veya mutlak
  `DOWNLOADHUB_ARIA2_PATH` verin. Kaynaktan kurulum için Apple Command Line Tools'un
  hazır olduğunu doğrulayın. Tek akış geri dönüşü çalışmaya devam eder; segmentli
  hızlandırma devre dışıdır. aria2 RPC dış ağa açılmaz.
- **YouTube extractor hatası:** önce yt-dlp, Deno ve FFmpeg sürümlerini doğrulayın.
  CAPTCHA/DRM aşma otomasyonu yapılmaz.
- **Eklenti bağlanmıyor:** uygulamanın tam olarak `127.0.0.1:8765` üzerinde çalıştığını,
  kodun beş dakika içinde kullanıldığını ve eklentinin yeniden yüklenmediğini kontrol
  edin; gerekirse eski istemciyi iptal edip yeniden eşleştirin.
- **Port dolu:** `lsof -nP -iTCP:8765 -sTCP:LISTEN` ile süreci inceleyin. Bilinmeyen
  süreci otomatik sonlandırmayın.
- **Finder/aç işlemi reddedildi:** yalnız uygulamanın veritabanına artifact olarak
  kaydettiği ve izin verilen indirme kökünde bulunan dosyalar açılabilir.

## Lisans

DownloadHub, yalnız GNU General Public License v3 (`GPL-3.0-only`) altında sunulur.
Tam metin [`LICENSE`](LICENSE) dosyasındadır. Üçüncü taraf bileşenleri kendi lisansları
altındadır; ayrıntılar [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) içindedir.

Yazılım hiçbir garanti olmaksızın sunulur.
