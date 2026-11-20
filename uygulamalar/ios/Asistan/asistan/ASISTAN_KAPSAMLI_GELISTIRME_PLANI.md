# Asistan — Kapsamlı geliştirme planı ve uygulama kaydı

Tarih: 21 Ekim 2026. Hedef: kişisel iPhone asistanı. Maliyet: ücretsiz ve mevcut hesaplar öncelikli.

Bu belge ürünün nihai kapsamını ve ilk uygulama paketinin gerçek durumunu birlikte tutar. Bir satırın kodda bulunması, üretime dağıtıldığı veya gerçek hesap/cihazda kabul edildiği anlamına gelmez.

## 1. Hedef ve değişmez kararlar

Asistan; konuşarak veya yazarak başlatılan işi kaynakları, dosyaları, hesapları ve izinli araçları kullanarak tamamlayan, sonucunu saklayan ve sonraki çalışmada sürdüren kişisel çalışma ortamı olacaktır.

- SwiftUI istemci, mevcut model zinciri, araç kayıtları, hafıza, projeler, ses köprüsü ve APNs korunur.
- Mevcut Python/SQLite görev hizmeti genişletilir. İkinci bağımsız zamanlayıcı kurulmaz.
- Yeni ücretli API kullanımı varsayılan kapalıdır. API anahtarının bulunması ücret yetkisi değildir.
- Modelin yaptığı işlem iddiası yerine gerçek araç ve çıktı sonucu esas alınır.
- Kaynak ve denetim blokları sohbeti doldurmaz; araştırma belgelerinin kendi kaynakçası korunur.
- Kullanıcının model, Azure Elif, Live ve tema varsayılanları değiştirilmez.
- Mevcut kirli çalışma ağacı korunur. Kullanıcı istemeden commit veya TestFlight dağıtımı yapılmaz.
- Üretim VPS/Caddy/servis değişikliği için repo AGENTS.md kuralındaki ayrı karar kapısı uygulanır.

## 2. Uygulama durumu

| Alan | Bu pakette | Henüz tamamlanmayan kabul/kapsam |
|---|---|---|
| Tuval | Yerel kalıcı belge, sürümler, seçili bölüm, geri alma, kurtarma taslağı, Markdown paylaşma, sohbet aracı; UI akışı geçti; Release iPhone'a kuruldu/açıldı | Telefonda bütün Tuval akışlarının kabulü; sunucu/yerel çift yönlü senkron |
| HTML mini uygulama | Ayrı geçici WKWebView, CSP, ağ/form/çerçeve kısıtları, gezinme engeli; gerçek WebKit ağ/resim/çerçeve engelleme testi geçti | Fiziksel cihazda örnek mini uygulama kabulü |
| Projeler | Mevcut kimlikler korunarak Tuval belgelerine bağlantı | Bütün dosya/görev türlerinin birleşik proje indeksi |
| V2 görevler | Kuyruk, atomik sahiplik, nesil, kalıcı adımlar, iptal/devam, olaylar, dosya/çıktı API'si; üretime dağıtıldı, dış HTTPS kabulü geçti | APNs yapılandırması ve telefon kapalıyken bildirim kabulü |
| Araştırma | Plan/rapor checkpoint'i; yüklenen kaynaklar, ücretsiz MediaWiki arama özeti fallback'i; PDFKit ile yerel sayfa numaralı PDF metin çıkarımı (200 sayfa/120.000 karakter) | Genel amaçlı web ve sayfa içeriği açma proxy yeteneği gerektirir; taranmış PDF için OCR; Claim/Evidence arşivi ve bağımsız çelişki denetimi |
| Veri analizi | CSV/JSON/XLSX girdisi, ayrı Docker runner, gerçek Python, indirilebilir grafik/tablo, kod kaydı; gerçek CSV/XLSX/PNG ve model→runner→indirme kabulü geçti | Kalıcı Python çekirdeği |
| Öğrenme | Tek soru ve cevap bekleme, cevap değerlendirme devam görevi | Kavram ustalığı, kalıcı StudySession ve aralıklı tekrar |
| Sesli anlatım | Kaynak alıntısı doğrulamalı iki konuşmacı senaryosu; mevcut Azure Elif/Aydın; parça checkpoint'leri; gerçek MP3/transkript üretimi ve indirme kabulü geçti | Bölüm zamanları, ayrıntılı oynatıcı |
| İETT | Canlı harita, yön, tazelik, favoriler, süreli yerel uyarı; eski kontrolün yeni kuralı silmesini engelleme; gerçek 34G konum testi geçti | Kesintisiz sunucu takibi, durak/güzergâh sırası, gerçek seyahat kabulü |
| Yaşam servisleri | Sınırlı disk önbelleği, iptal ayrımı, eksik polen ve geçersiz konum düzeltmeleri | Servis bazlı semantik önbellek doğrulaması ve kalan kalite maddeleri |
| Hesaplar | Mevcut MCP/OAuth altyapısı korunur | Hazır Drive/Gmail/GitHub/Calendar merkezi ve sağlayıcı kabulü |
| Kalıcı ajan | Özellik kapalı; mevcut tarayıcı aracı korunur | Ayrı çalışma VM'si, kalıcı tarayıcı, canlı görüntü, devralma |
| Kanallar | Özellik kapalı | Telegram/Discord kimlik eşleme, teslimat ve ses/dosya akışı |

## 3. Kullanıcı akışları

### 3.1. Çalışma alanı

Atölye → Çalışma alanı ve Tuval:

1. Tuval veya İETT haritası sunucu güncellemesinden bağımsız açılır.
2. Sunucu yetenekleri alınır. Eski sunucu 404 verirse anlaşılır durum gösterilir.
3. Belge, araştırma veya öğrenme seçilir. Analiz/ses yalnız sunucu özelliği açıkken görünür.
4. İstem ve isteğe bağlı dosyalar gönderilir. Gönderim sürerken girişler kilitlenir.
5. Aynı isteğin ağ nedeniyle tekrar gönderilmesi aynı UUID anahtarını kullanır.
6. Görev listesi, olaylar ve sonuçlar uygulama açıkken yenilenir. Arka planda sürekli sorgu yapılmaz.
7. Sonuç Tuval'e alınabilir; analiz/ses dosyaları indirilip önizlenebilir/paylaşılabilir.
8. Bildirim, ilgili V2 görevin çalışma alanında açılmasına yönlendirilir.

### 3.2. Tuval

- Belgeler Application Support/Tuval altında, belge başına tek atomik JSON dosyasında tutulur.
- Her sürüm yeni UUID alır, önceki sürümü referanslar. Eski sürüm değişmez.
- Düzenleme temel sürüm kimliği taşır. Çakışmada güncel kullanıcı verisi ezilmez.
- Kurtarma taslağı ayrı kaydedilir. Başarısız kayıtta Geri düğmesi ekranı kapatmaz.
- Sürüm geri alma önce mevcut düzenlemeyi saklar, sonra eski metni yeni sürüm olarak ekler.
- Kaydetmeden önce kapanma durumunda kurtarma taslağı yeniden açılır.
- Metin seçimi UTF-16 aralıklarıyla doğrulanır; yanlış veya değişmiş aralık reddedilir.
- HTML önizleme kalıcı çerez veya native köprü almaz. Kaynak HTML'nin üstünden CSP kaldırılarak izin genişletilemez.

### 3.3. Araştırma

Nihai hedef: plan → alt sorular → kaynak bulma → çıkarım → iddia/kanıt → çelişki denetimi → rapor.

İlk paket plan/rapor checkpoint'lerini ve gerçek kaynak girdilerini sağlar. Proxy web araması çalışıyorsa tamamlanmış web araması ve kaynak olayları zorunludur. Proxy bu yeteneği taşımıyorsa ücretsiz MediaWiki REST aramasıyla Türkçe (sonuç yoksa İngilizce) Wikipedia'dan en çok üç başlık/özet alınır ve kaynaklandırılır; tam makale açılmaz, genel web kapsamı olduğu iddia edilmez. Canlı MediaWiki uç noktası kullanılabilirliği doğrulandı. Ücretli yola geçilmez. TXT/Markdown/CSV/JSON kaynaklarıyla araştırma üretimde geçti. PDF, iPhone'da PDFKit ile yerel olarak sayfa numaralı metne çevrilir ve sunucuya metin olarak verilir; OCR yapılmayan sayfalar raporlanır, metinsiz/taranmış PDF kendiliğinden okunmuş gibi gösterilmez.

Nihai araştırma raporunda sonuç, yöntem/kapsam, bulgular, çelişkiler, bilinmeyenler ve kaynakça bulunacaktır. Kaynağın tarihi ile erişim tarihi ayrı tutulacaktır. Erişilmeyen makale yalnız katalog kaydı olarak belirtilecektir.

### 3.4. Veri Laboratuvarı

- İlk sürüm tek çalıştırma tabanlıdır; kalıcı Jupyter oturumu olarak sunulmaz.
- Dosya toplamı 25 MB; XLSX açılmış toplamı 200 MB ve en çok 10.000 ZIP üyesi.
- Kod yalnız ayrı runner hizmetinde Docker ile yürür.
- Girdi dizini salt okunur; çıktı tmpfs; ağ yok; host anahtarı/soketi bağlanmaz.
- 2 CPU, 2 GB RAM, 64 süreç ve 60 saniye toplam çalıştırma sınırı.
- pandas, NumPy, Matplotlib, openpyxl, defusedxml imaja önceden kurulur.
- Üretilen kod için çalışma sırasında paket indirme yoktur.
- Başarılı çıkış olmadan hesap sonucu tamamlandı sayılmaz.
- Çıktı dosyaları ve checkpoint aynı SQLite transaction'ında kaydedilir; hata halinde yeni fiziksel dosyalar temizlenir.
- Kod, stdout ve dosyalar saklanır. Dosya bağlantıları gerçek çıktı kimliğine dayanır.

### 3.5. Sesli anlatım

- Kaynak metin zorunludur.
- Senaryo her parçada kaynak kimliği ve kaynakta birebir bulunan kısa alıntı taşır.
- Geçersiz alıntı ses üretimi başlamadan reddedilir.
- Mevcut Azure kataloğundan Elif öncelikli iki farklı ses kullanılır. Tek uygun ses varsa bu belirtilir.
- Her ses parçası ayrı checkpoint'tir. Aynı parça kaldığı yerden devamda yeniden ücretlendirilmez.
- TTS ve FFmpeg bekleme süreleri kalan görev süresiyle sınırlıdır. Geç gelen başarılı ses parçası korunur; süreyi aşmış görev tamamlandı sayılmaz.
- FFmpeg, yalnız yerel parça dosyalarından MP3 üretir; kaynak transkriptle ilişkilidir.
- Senaryo, kaynak uygunluğu bakımından insan denetimi gerektirebilir; alıntı kontrolü anlamsal doğruluk garantisi olarak gösterilmez.

## 4. Ortak veri ve API sözleşmesi

Eski `/v1/asistan/*` uçları ve eski kayıtlar korunur. V2 tabloları `workspace_` önekiyle eklenir. İlk geçişte tutarlı SQLite yedeği alınır.

| Uç | İşlev |
|---|---|
| GET `/v2/asistan/capabilities` | Gerçek etkin modüller, sınırlar, ücretli kullanım kapısı |
| POST/GET `/v2/asistan/jobs` | Oluşturma/listeleme |
| GET `/v2/asistan/jobs/{id}` | Durum ve çıktı kimlikleri |
| GET `/v2/asistan/jobs/{id}/events?after=N` | Artan olay sırası |
| POST `/v2/asistan/jobs/{id}/cancel` | İptal ve eski işçi neslini geçersizleştirme |
| POST `/v2/asistan/jobs/{id}/resume` | Kalıcı adımdan devam |
| POST `/v2/asistan/files` | Ham dosya; `X-Filename` yüzde kodlu ad |
| GET `/v2/asistan/files/{id}` | Kimliği doğrulanmış indirme |
| POST/GET `/v2/asistan/artifacts` | Çıktı oluşturma/listeleme |
| GET `/v2/asistan/artifacts/{id}` | İçerik, güncel sürüm ve ek dosyalar |
| GET/POST `/v2/asistan/artifacts/{id}/revisions` | Sürüm geçmişi/yeni sürüm |

Kimlik başlığı mevcut `X-Personal-Token` olmaya devam eder. Görev oluşturma ayrıca UUID `Idempotency-Key` ister. Aynı anahtar ve farklı gövde 409'dur. UUID'ler bütün sorgu ve dosya yollarında normalize edilir.

Hatalar `code`, `message`, `retryable`, `request_id` taşır. Sağlayıcı ham hataları ve sırları dışarı verilmez. `max_sources` henüz uygulanmadığından bu parametre sessizce kabul edilmez.

Görev durumları: queued, running, paused, failed, cancelled, completed, completed_with_warnings. İşçinin generation değeri her kalıcı adım/çıktı işleminde kontrol edilir. Sunucu yeniden başlarsa running işler paused olur; kullanıcı devam ettirebilir.

Kaydedilmiş belge görev geçmişi temizlenirken silinmez. Gelecek otomatik saklama politikasında bu ayrım korunmalıdır. Bu pakette otomatik V2 belge silme yoktur.

Sert kapanış sırasında dosya yazılıp transaction tamamlanmamışsa dosya açılışta `workspace_orphans` ile kayda alınır, korunur ve kotaya dahil edilir. Bu davranış ayrı süreci commit öncesinde kesen testle doğrulanır.

## 5. Nihai hesap bağlantıları kapsamı

Sıra: Drive → GitHub → Gmail → Calendar.

- Resmî OAuth giriş ekranı, uygun yerde PKCE ve kısa ömürlü state.
- Gerekli en dar kapsamlar; ilk sürüm okuma ağırlıklı.
- Seçilmiş klasör/depo indeksleme, bütün hesabın otomatik kopyalanmaması.
- Token'lar kaynak kodunda, iPhone paketinde veya logda bulunmaz.
- Bağlantı kaldırıldığında token/indeks/önbellek temizlenir, bağlı rutinler duraklar.
- Kullanıcının ayrıca kaydettiği rapor silinmez.
- Gönderim/paylaşım yetkisi belirli hedef ve içerikle eşleşir; dış kaynak metni yetki oluşturmaz.
- Gerçek hesapla bağla → ara → oku → iptal et kabulü olmadan hazır gösterilmez.

## 6. Nihai kalıcı ajan ve kanallar kapsamı

Kalıcı ajan üretim API sunucusunun terminali değildir. Ayrı çalışma VM'si, kalıcı Chromium profili, Playwright, çalışma dizini, ekran akışı ve kullanıcı devralması gerektirir. Kullanıcı kontrolü aldığında ajan girdi üretmez. Giriş/2FA/ödeme kullanıcıya bırakılır. Sonucu belirsiz dış eylem otomatik tekrarlanmaz.

Kanallar önce Telegram özel sohbeti, sonra Discord özel mesajdır. Kısa ömürlü eşleme kodu ve sağlayıcının değişmez kullanıcı kimliği kullanılır. Gruplar ilk aşamada kapalıdır. Olay kimliği tekilleştirilir; görev motoru ortaktır. Kanala özel raporun tamamı kendiliğinden dökülmez. Bot token'ları ayarlardan/sunucunun özel sır deposundan sağlanır; sohbete veya repoya konmaz.

## 7. İETT ve ücretsiz servislerin nihai kapsamı

- Planlanan kalkış ile canlı araç konumu ayrı gösterilir.
- Ölçüm zamanı İstanbul zaman diliminde ayrıştırılır; string sıralamasıyla en yeni kayıt seçilmez.
- Zamanı bilinmeyen veya 120 saniyeden eski araç yaklaşma bildirimi üretmez.
- Hat, yön ve hedef durak aynı anda eşleşmelidir.
- Uyarılar 60 dakika sonra sona erer. Başarısız bildirim kuralı tamamlamaz.
- Kullanıcı kuralı değiştirirse eski denetim yeni kaydı silemez.
- Gerçek ETA yoksa dakika tahmini uydurulmaz.
- Kesintisiz takip için sunucuda ortak hat sorgusu ve servis kullanım koşulu/kota doğrulaması gerekir; bu paket bunu vaat etmez.
- GitHub yıldız sayısı tek entegrasyon ölçütü değildir. Lisans, bakım, resmî servis, ücretsiz limit ve gerçek test kaydı gerekir.
- OpenAlex katalog sonucu tam metin analizi değildir; OpenFoodFacts boş alanı sıfır değildir; polen verisi yokluğu polen olmadığı anlamına gelmez.

## 8. Test ve kabul planı

### Hermetik

- Eski kayıt/şema uyumluluğu.
- Aynı kimlikle tekrar, içerik çakışması, büyük/küçük harf UUID.
- Eşzamanlı tek işçi sahipliği.
- Yeniden başlama ve aynı adımın tekrar yürümemesi.
- İptal sırasında model/runner yanıtının gelmesi.
- Dosyalı checkpoint'te kota veya yazım hatası: tümü ya da hiçbiri.
- Ücretli yolun kapalı kalması, yapılandırılmamış modülün görünmemesi.
- Tuval sürüm çakışması, emoji/Türkçe seçim, bozuk dosya ve taslak kurtarma.
- HTML CSP ve gerçek runtime ağ engelleme.
- İETT eski/gelecek zaman, karşı yön, kural nesli.
- HTTP kimlik doğrulama ve yapılandırılmış hatalar.
- Gerçek FFmpeg ile sentetik iki WAV parçasının MP3'e dönüşmesi.

### Canlı ve cihaz

- Gerçek Docker analiz imajıyla bilinen CSV/XLSX sayıları ve PNG.
- Gerçek modelle kaynaklı araştırma ve Türkçe öğrenme döngüsü.
- Mevcut Azure ses hizmetiyle iki konuşmacı.
- Gerçek İETT hattı ve fiziksel yolculuk.
- iPhone'da soğuk açılış, çevrimdışı kullanım, arka plan, kilit, bağlantı değişimi.
- Bildirimden aynı göreve dönüş.
- Kurulum, launch ve gerçek özellik kabulü ayrı sonuçlardır.

## 9. Dağıtım ve geri alma

Somut dağıtım kaydı ve geri alma adımları `vps/asistan-jobs/WORKSPACE_ROLLOUT.md` içindedir. Kullanıcı onayı sonrası V2, analiz ve ses üretime kuruldu; gerçek hizmet kontrolleri geçti. APNs yapılandırması henüz yoktur.

Önce v2 temel görevler ve yerel Tuval doğrulanır. Analiz ve ses ayrı bayraklarla açılır. Kullanıcı çıktıları geri almada silinmez. Eski sunucu koduna dönmek v1'i çalıştırmaya devam ettirir; V2 tabloları eklemelidir.

## 10. Referans ürün yetenekleri

- [Claude Artifacts](https://support.anthropic.com/en/articles/9487310-what-are-artifacts-and-how-do-i-use-them)
- [Claude Research ve integrations](https://www.anthropic.com/news/integrations)
- [ChatGPT veri analizi](https://help.openai.com/en/articles/8437071-data-analysis-with-chatgpt)
- [ChatGPT Study Mode](https://help.openai.com/en/articles/11780217-using-study-mode-in-chatgpt)
- [Gemini Canvas](https://support.google.com/gemini/answer/16047321?co=GENIE.Platform%3DDesktop&hl=en)
- [Gemini Audio Overview](https://blog.google/products-and-platforms/products/gemini/gemini-collaboration-features/)
- [Grok Bot çalışma ortamı](https://docs.x.ai/grok-bot/computer-and-apps)
- [Hermes Agent](https://github.com/NousResearch/hermes-agent)

Bu referanslar ürün hedefini açıklar; Asistan'da uygulanmış özellik kanıtı değildir.
# 21 Ekim devamı — büyük dosya ve ortak altyapı

Dosya kasasında 10 GiB aktarım, 8 MiB parçalar, SHA-256 doğrulama, kesintiden devam ve sunucudan yarım yükleme kurtarma uygulandı. 2 GiB + 17 bayt gerçek HTTPS aktarımı doğrulandı. Ortak belge yollarında ana aktör dışı disk işlemleri, gereksiz kopyanın kaldırılması, paralel yenileme ve sınırlı/iptal edilebilir Ofis arşivi açma eklendi. 1.528 iOS ve 77 Python testi geçti. [Uygulama ve doğrulama raporu](ASISTAN_BUYUK_DOSYA_VE_HIZ_2026-10-21.md).

Sonraki genişletme kapsamı: her özelliğin gerçek cihaz gecikme ölçümleri, GB kaynakların kontrollü indekslenmesi, arka plan aktarımı ve aşağıdaki ürün özelliklerinin tamamlanması. Büyük dosya saklama ile modelin tüm içeriği işlemesi ayrı yeteneklerdir.

## 21 Ekim ikinci devamı — büyük metinden kaynak seçimi ve akış

64 MiB/dosya, 128 MiB/toplam UTF-8 araştırma; sınırlı bellekle tarama, örtüşen pasajlar, Türkçe sözcük sıralaması, kaynak konumları ve kalıcı seçim checkpoint'i eklendi. Sohbet + menüsünden dosya kasasına ve kasadan kaynaklı araştırmaya geçiş bağlandı. SSE tamamlanmasında TCP kapanmasını bekleme ve ses akışındaki parçalanmış ondalık sayı sorunları düzeltildi. [Uygulama, sınırlar ve doğrulama](ASISTAN_ARASTIRMA_VE_AKIS_2026-10-21.md).

GB belgelerin kalıcı anlamsal indeksi, PDF OCR ve tüm belgeyi kapsayan çok aşamalı özetleme hâlâ açık kapsamdır.
