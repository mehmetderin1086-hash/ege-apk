# Büyük dosya, hız ve güvenilirlik — 21 Ekim 2026

## Kullanım

Menü → Araçlar → Atölye → Çalışma alanı ve Tuval → Dosya kasası → Dosya seç ve yükle.

- Dosya başına **10 GiB** (10.737.418.240 bayt); sunucu kotası **50 GiB**. Diskin son 2 GiB alanı korunur. Başlatılan yüklemenin tamamı için alan ayrılır; yeterli alan yoksa yükleme başlatılmaz.
- Her ağ isteği en fazla **8 MiB**. Dosyanın tamamı iPhone veya sunucu belleğine alınmaz.
- İlerleme, aktarılmış boyut, ortalama hız ve yaklaşık kalan süre gösterilir.
- Duraklatma, bağlantı hatalarında sınırlı otomatik yeniden deneme, aynı dosyayı yeniden seçerek devam etme.
- Uygulama arka plana geçince aktarım duraklar. Arka planda kesintisiz yükleme iddiası yoktur.
- Yarım yüklemeler sunucuda listelenir. Uygulama yeniden kurulduğunda aynı sunucuya bağlanarak bulunabilir; aynı dosya seçilip doğrulandıktan sonra devam edilir.
- Her parça ve tamamlanan dosya SHA-256 ile doğrulanır. İndirme de boyut ve SHA-256 ile doğrulanır.
- Kullanılmayan dosyalar onayla silinebilir. Çalışmalara veya ara sonuçlara bağlı dosyalar korunur.

## Saklama ve işleme ayrımı

Dosya kasası her dosya türünü saklar. Saklanabilen 10 GiB dosyanın tamamı otomatik olarak modele gönderilmez.

| Kullanım | Sınır |
|---|---|
| Dosya kasası | Dosya başına 10 GiB, toplam 50 GiB ve gerçek boş disk denetimi |
| Araştırma metin kaynağı | Son devam paketiyle 64 MiB/dosya, 128 MiB/toplam; en fazla 36.000 karakter seçili bağlam |
| Diğer metin çalışmaları | Dosya başına 200 KB, toplam 120.000 karakter |
| Veri analizi | Dosya başına 25 MiB |
| Yerel PDF çıkarımı | 25 MiB, 200 sayfa, 120.000 karakter; taranmış sayfalara bu yolda OCR yok |
| Sohbet Ofis belgesi okuma | Sıkıştırılmış dosya 20 MiB; açılan XML bölüm başına 8 MB, toplam 32 MB |

## Ortak hız ve güvenilirlik iyileştirmeleri

- Çalışma kaynağı okuma ve PDF hazırlama ana aktörden çıkarıldı; dosya sağlayıcısı beklerken arayüz çalışabilir.
- İndirilmiş çıktılar tekrar `Data` ile belleğe alınıp kopyalanmaz; dosya taşıma/değiştirme kullanılır.
- Çalışma alanında yetenek ve görev listesi istekleri aynı anda çalışır.
- Ofis arşivleri açılırken hem bildirilen hem gerçek açılmış bayt sayısı denetlenir; iptal kontrolü uygulanır.
- Sunucuda aynı anda en fazla üç dosya gövdesi kabul edilir; bellek kullanımı istek sayısıyla sınırsız büyümez.
- Kaynak silme ve görev oluşturma yarışları, UUID yazım farkları, kayıp ağ yanıtları ve yeniden başlama durumları için korumalar eklendi.

## Doğrulama

- iOS: **1.528 test / 229 grup geçti**; yeni büyük ofset, parça, SHA-256, kaynak sınırı ve Ofis dosyası testleri dahil.
- Python sunucu: **77 test geçti**, hem yerelde hem VPS staging dizininde.
- Canlı HTTPS: **2.147.483.665 bayt** dosya yüklendi; kayıp yanıt sonrası devam, dosyanın tamamının indirilip aynı SHA-256 ile doğrulanması, yetkisiz isteğin reddi ve V1 servis kontrolü geçti. Sentetik test dosyası silindi.
- Son canlı turda sunucu tepe belleği yaklaşık 36 MiB'dan 47 MiB'a çıktı; dosya boyutuyla aynı oranda büyümedi. Yükleme ve sunucu doğrulaması 20,69 saniye, indirme ve temizlik dahil toplam 28,71 saniye. Bu, aynı VPS'ten genel HTTPS adresine yapılan altyapı testidir; iPhone veya mobil bağlantı hız ölçümü değildir.
- Yeni dosya kasası arayüz testi geçti; Tuval oluşturma/sürüm geçmişi testi de geçti. Release 0.21.0 (202610210531) fiziksel iPhone'a kuruldu, sürüm doğrulandı ve uygulama başlatıldı. GB aktarımı telefondan uçtan uca ayrıca ölçülmedi.

Kanıt günlükleri: `~/Developer/.build/asistan-large-upload-tests.log`, `asistan-upload-tests.log`, `asistan-large-upload-ui-final.log`, `asistan-large-upload-live-final.log`, `asistan-large-upload-device.log`.

## Dağıtım

Mevcut üretim onayı kapsamında SQLite tutarlı yedeği ve kod yedeği alındı. İlk yedek `/var/backups/asistan-workspace/large-upload-20261021T022956Z`; ek dosya bağlantısı korumalarından önceki yedek `/var/backups/asistan-workspace/large-upload-20261021T023218Z`.

Yeni sürüm `server.py`, `workspace.py`, `uploads.py` ile kuruldu. Caddy'nin mevcut gövde sınırı parçalara yeterlidir; Caddy veya diğer hizmetlerin ayarları değiştirilmedi. Yeni ücretli API açılmadı.

## Kalan kapsam

Bu sürüm dosya aktarımını ve ortak dosya altyapısını geliştirir. Bütün özelliklerin kapsamlı yeniden tasarımı, her sağlayıcının gerçek cihazda hız karşılaştırması, tam arka plan yüklemesi ve GB belgelerin tamamını işleyen indeksleme ayrı işlerdir. Tüm uygulama için hata olmayacağı veya belirli yanıt süresi garantisi verilmez.

Son devamda sohbetin + menüsüne kasa erişimi ve 64 MiB metin araştırması eklendi; [güncel uygulama ve doğrulama raporu](ASISTAN_ARASTIRMA_VE_AKIS_2026-10-21.md). Bu belgedeki 2 GiB aktarım ölçümleri önceki paket kanıtıdır; yeni metin araştırması ayrıca canlı sınandı.
