# iPhone PDF düzenleyici rakip envanteri (Ekim 2026)

Hazırlanma tarihi: 27 Ekim 2026. Amaç: "PDF Love gibi" yerel bir iPhone PDF düzenleyici için rakiplerin en iyi özelliklerini, fiyat/işleme-yeri/şikâyet bilgisiyle birlikte kanıta dayalı çıkarmak.

## 0. Yöntem, işaret sözlüğü ve sınırlar

**Kaynak sınıfları (güvenilirlik sırasıyla):**
- B1: Apple App Store sayfası / iTunes lookup (resmi liste, fiyat, sürüm notu, dil, gizlilik etiketi). 27 Ekim 2026'da ABD mağazasından okundu.
- B2: Üretici/Apple resmi yardım sayfaları (support.apple.com, support.microsoft.com, helpx.adobe.com vb.).
- B3: Üçüncü taraf özet/inceleme/forum (Adobe Community, G2/Capterra özetleri, Kimola önizlemeleri, Trustpilot). Bunlar örnek-çarpık ve çoğu eski; "şikâyet" bölümünde ayrıca etiketlendi.
- Yerel ölçüm: Bu Mac'te (macOS 27.2) Vision OCR dil listesi çalıştırılarak okundu (Bölüm 8.3).

**Matris işaretleri:**
- `+` var (ücretsiz/ücretli ayrımı kaynakta belirtilmemiş veya ücretsiz)
- `$` yalnız ücretli katmanda var
- `~` kısmi / dolaylı / başka bir araçla
- `-` kaynak açıkça "yok" veya "yalnız masaüstü" diyor
- `?` kaynakta belirtilmemiş: "yok" demek DEĞİLDİR, doğrulanamadı demektir

**Bilinen sınırlar (dürüstlük notu):**
1. `indielabs.app` (PDF Love'un geliştirici sitesi, gizlilik ve şartlar sayfaları) bu ortamdan açılamadı (SSL bağlantı hatası, hem WebFetch hem curl). PDF Love'un gizlilik/şartlar metni OKUNAMADI.
2. Reddit alan adı arama aracı tarafından engelli (HTTP 400). Reddit şikâyetleri DOĞRULANAMADI. Apple'ın müşteri yorumu RSS ucu bu uygulamalar için boş döndü; tek tek App Store yorumları okunamadı. Şikâyet kanıtı bu yüzden ikincil kaynaklardan (Adobe Community, G2/Capterra özetleri, Kimola önizlemesi, Trustpilot) ve listelerin kendisinden (SKU karmaşası, dil eksikliği, izleme etiketleri) çıkarıldı.
3. App Store sayfa özetleri araç tarafından kısaltıldı/parafraz edildi; fiyatların bir kısmında dönem (aylık/yıllık) listede yazmıyor, "dönem belirtilmemiş" diye işaretlendi.
4. Fiyatlar ABD mağazası, USD. Türkiye mağazasında fiyatlar farklı (ör. Acrobat TR listesinde ₺12,99 ile ₺264,99 arası SKU'lar görünüyor, hangisinin hangi dönem olduğu belirtilmemiş).
5. "Cihaz içi mı sunucuda mı" bilgisi çoğu listede yazmıyor; yazmayanlar "belirtilmemiş" olarak bırakıldı, tahmin işaretlendi.

---

## 1. PDF Love ayrıntılı profil (kullanıcının referansı)

**Kimlik**
- App Store başlığı: "Photo to PDF Scanner: PDF Love"; alt başlık: "Image Converter Document OCR". App Store id6758917744.
- Satıcı: Sasikumar Chhotelal Das, marka "indielabs" (© 2025 indielabs). Aynı geliştiricinin 10 başka küçük uygulaması var (MP3 çalar, ters çalma, HTML editör, bütçe, mesai saati, blok bulmaca, ayin alarmı, şifre kasası, yapılacaklar, döviz). Bu bir "çok sayıda küçük yardımcı uygulama" portföyü (çıkarım: tek ürüne derin yatırım yapan bir ekip olması beklenmemeli).
- Kategori: Yardımcı Programlar (ikincil: Verimlilik). Yaş 4+. Yalnız iPhone için tasarlanmış (macOS/visionOS'ta "doğrulanmadı").
- iOS 17.0+, boyut yaklaşık 5,9 MB (5.857.280 bayt). Dil: yalnız İngilizce (Türkçe arayüz YOK).
- Yayın: 5 Mart 2026 (1.0.0). 1.0.1: 11 Mart. 1.0.2: 24 Mart 2026, notu "minor fixes and perfomances". 27 Ekim itibarıyla yaklaşık 7 aydır güncelleme yok.
- Puan/yorum: hiç yok (ABD ve TR mağazasında 0 oy; "yeterli puan yok"). Dolayısıyla gerçek kullanıcı şikâyeti kaynağı yok (doğrulanamadı).
- Fiyat: ücretsiz + uygulama içi satın alma. Abonelik: Haftalık 4,99 USD, Aylık 6,99 USD, Yıllık 29,99 USD. Listede "Try Pro!" yükseltme çağrısı var. Hangi özelliğin ücretsiz, hangisinin Pro olduğu listede yazmıyor (doğrulanamadı).
- Gizlilik etiketi (geliştirici beyanı, Apple doğrulamamış): izleme yok; "kullanıcıya bağlı olmayan" analitik (ürün etkileşimi) ve tanılama (çökme/performans).

**Resmî özellik listesi (App Store açıklaması, kelimesi kelimesine kapsam)**
- TARA VE İÇE AKTAR: kamerayla belge tarama (otomatik kenar algılama ve iyileştirme); fotoğraf kitaplığından veya Dosyalar'dan içe aktarma; görselleri anında PDF'e çevirme.
- İMZALA VE AÇIKLAMA: imza çizme veya kayıtlı imza kullanma; PDF'e metin, şekil ve görsel ekleme; önemli bölümleri işaretleme/vurgulama.
- "20+ PDF aracı": birleştirme; bölme ve belirli sayfaları çıkarma; sıkıştırma; parola ekleme/kaldırma; üstbilgi, altbilgi ve sayfa numarası ekleme; filigran; sayfa döndürme ve yeniden sıralama; hassas içeriği bulanıklaştırma ve karartma (redact).
- DÖNÜŞTÜR: PDF'ten görsele; görselden PDF'e; OCR ile PDF'ten metne; Word'den PDF'e; PDF'ten ZIP'e.
- DÜZENLE: klasörler; tüm dosyalarda arama; depolama kullanımı görünümü ve alan yönetimi.
- GÜVENLİK: Face ID veya Touch ID ile uygulama kilidi; parolalı PDF; "belgeleriniz cihazınızda kalır".
- iCLOUD EŞİTLEME: belgeler Apple cihazları arasında otomatik eşitlenir (iPhone, iPad).

**Mağaza görsellerinden (6 ekran görüntüsü, B1) çıkan UI kanıtı**
- Pazarlama iddiaları: "#1 PDF SCANNER APP" ve beş yıldızlı rozet (oysa mağazada hiç puan yok); bir görselde "10+ PDF TOOLS", açıklamada "20+ PDF tools" (tutarsız).
- Kamera tarama ekranı: arka plan kameranın canlı görüntüsü, belge çevresinde mavi çerçeve ve dört köşede sarı sürüklenebilir tutamaç, altta büyük deklanşör, sağda flaş, solda son çekimin küçük resmi, en altta İptal/Kaydet.
- İmza yerleştirme: imza, kırmızı köşe tutamaçlı döndürülebilir/boyutlandırılabilir kutu olarak sayfaya konur; altta renk paleti; üstte geri al/yinele okları.
- Görsel→PDF: çok seçimli fotoğraf ızgarası, seçilenlerde onay rozeti ("Select" başlığı).
- Dosyalar ekranı: "Files" başlığı, renkli klasör listesi (Documents, Work, Photos, Archive; öğe sayısıyla), altında PDF satırları (ad, tarih, boyut), alt çubukta "Recents | Browse" sekmeleri.
- Ana ekran araç ızgarası ekran görüntülerinde GÖRÜNMÜYOR (doğrulanamadı); görseller ağırlıkla stok/maket.

**Teknik çıkarımlar (kanıta dayalı tahmin, kesin değil)**
- 5,9 MB boyut; rakiplerin 47 MB (PDFgear) ile 579 MB (Acrobat) arasındaki boyutlarıyla karşılaştırınca, üçüncü taraf bir PDF motoru (Apryse/PDFium/Nutrient ağırlığı) gömülü değil gibi görünüyor; büyük olasılıkla Apple PDFKit/VisionKit/Vision gibi sistem çerçeveleri kullanılıyor. Bu yüzden "mevcut metni düzenleme" ve "PDF→Word/Excel/PPT" listede YOK. Bu bir çıkarımdır, doğrulanmadı.
- "Word'den PDF'e" ve "PDF'ten ZIP'e"nin ne yaptığı (ZIP = sayfa görselleri mi?) ve OCR'ın hangi dilleri tanıdığı listede yazmıyor (doğrulanamadı). "Belgeleriniz cihazınızda kalır" beyanı var ama Word→PDF'in cihazda mı sunucuda mı çalıştığı belirtilmemiş.

**Listede OLMAYANLAR (rakiplerde yaygın olup PDF Love açıklamasında geçmeyen)**
Mevcut metin/görsel düzenleme; PDF→Word/Excel/PPT; form doldurma; form oluşturma; dijital sertifika imzası; yapay zekâ (özet, sohbet, çeviri); sesli okuma; karşılaştırma; widget/Kısayollar/paylaşım uzantısı; toplu tarama ve filtre listesi; Türkçe arayüz ve Türkçe OCR beyanı; meta veri temizleme; çok pencereli kullanım; iPad ayrı arayüz.

**PDF Love'dan alınacak/alınmayacak dersler**
- Alınacak: hızlı kapsam (tara, imzala, birleştir/böl/sıkıştır, üstbilgi/sayfa no/filigran, bulanıklaştır/karart, Face ID kilidi, iCloud, klasör+arama) küçük bir uygulamaya sığıyor; "Files" sekmesi sade; köşe tutamaçlı kamera ve dönüştürülebilir imza kutusu iyi desenler.
- Alınmayacak: haftalık 4,99 USD abonelik; yalnız İngilizce; hiç sürüm notu yok; birbiriyle çelişen pazarlama sayıları ("10+" / "20+"); doğrulanmamış "#1" iddiası; gizlilik/şartlar sayfasının erişilememesi.


---

## 2. Uygulama başına kısa profil

Her profilde: kimlik/boyut/puan (B1), fiyat, öne çıkanlar, işleme yeri, Türkçe, şikâyet/risk. "Belirtilmemiş" = listede yazmıyor.

### 2.1 iLovePDF (iOS) — id1207332399
- iLovePDF; v4.2.0; 276,6 MB; iOS 18+; 4,8 puan / 52 bin oy. Türkçe arayüz VAR (25 dil).
- Fiyat: Premium aylık 5,49 USD, yıllık 44,99 USD (liste dönem belirtmeden tekrar eden SKU'lar içeriyor). Ücretsiz katmanda günlük görev sınırı (listede ve G2/GetApp özetlerinde "günde 3 görev" dolaylı geçiyor, B3).
- Özellikler: tarayıcı (çok sayfa modu + OCR); JPG→PDF, Office→PDF, PDF→Word/Excel/PPT, PDF'ten görsel çıkarma; vurgulama, not/yorum, çizim, görsel ekleme; form doldurma ve parmakla e-imza; sıkıştırma, birleştirme, bölme, döndürme, parola ekle/kaldır, sayfa numarası, metin/görsel filigran; Google Drive ve Dropbox. Sürüm notlarından: PDF çevirisi, Kısayollar entegrasyonu, SSO, karartma (redaction), dosya boyutuna göre bölme, Excel dışa aktarımı iyileştirmesi, Okuyucu görünümü (4.1.0), Görsel görüntüleyici, iPad/iPhone Duo'da çoklu PDF penceresi (4.2.0).
- UX: alt çubuk Home / Files / Tools / Scanner / Settings; Home'da "Recent files", "Favorites", "Recent Tools"; Tools sekmesi 3 sütunlu araç ızgarası (Image to PDF, Word to PDF, Excel to PDF, PowerPoint to PDF, Compress, Merge, PDF to Word/Excel/PowerPoint/JPG, Split, Text Recognition (OCR), Edit PDF, Organize PDF, Unlock PDF...) (App Store ekran görüntüsü, B1).
- İşleme yeri: mobil için belirtilmemiş. Web/mobil güvenlik beyanı "yüklenen belgeler 2 saat sonra silinir" (2020 blog, B3) sunucu işlemeyi ima eder; doğrulanamadı. Bir B3 özeti "PDF'lerin harici sunuculara yüklenmesi" kaygısını not ediyor.
- Şikâyet temaları (B3): ücretsiz katman günlük/dosya boyutu sınırı; abonelik pahalı; karmaşık PDF→Word'de düzen kayması; yavaşlık.

### 2.2 Smallpdf — id1485259500
- Smallpdf GmbH; v1.53.83; 117,4 MB; iOS 15.6+; 4,8 / 6,9 bin oy; Türkçe VAR (24 dil).
- Fiyat: Aylık 7,99 / 11,99 / 14,99 USD; Yıllık 49,99 / 59,99 / 107,99 / 119,99 USD (aynı ürün için çok sayıda SKU; liste hangisinin hangi plan olduğunu belirtmiyor). Günlük görev limiti, Pro için 7 gün deneme.
- Özellikler: PDF→Word/Excel/PPT/JPG/PNG ve görsel→PDF; metin, görsel, şekil ekleme; açıklama/vurgu; sayfa döndür/sil/sırala; sıkıştır; e-imza ve dijital imza; birleştir; kamerayla tarama (otomatik kırpma, iyileştirme); çok dilli OCR; yerel/bulut kaydetme.
- İşleme yeri: sunucu. Liste açıkça "Yüklenen tüm dosyalar işlendikten 1 saat sonra silinir (yerel veya buluta kaydedilmedikçe)" diyor. Gizlilik etiketi: Tanımlayıcılar "sizi izlemek için kullanılan veri".
- Şikâyet: fiyat dağınıklığı (SKU çokluğu); kullanıcı içeriği analitikte "kullanıcı içeriği" olarak etiketli (B1).

### 2.3 Adobe Acrobat Reader / Acrobat — id469337564
- Adobe; v26.09.50; 579 MB; iOS 18.3+; 4,6 / 663 bin oy; Türkçe VAR.
- Ücretsiz: görüntüleyici, Liquid Mode, Fill & Sign, açıklama (not/yorum/vurgu), arama, bulut hesabı bağlama (OneDrive, Dropbox, Google Drive), Adobe Scan taramaları, temel sesli okuma.
- Ücretli (Premium): metin/görsel düzenleme (yalnız mobilde), OCR, birleştirme/bölme, oluşturma/dışa aktarma (Word/Excel/PPT/görsel), sıkıştırma, parola, sayfa ekleme/silme/döndürme/kırpma/sıralama, yüksek kaliteli sesli okuma, AI Assistant (sesli/yazılı sohbet, alıntılı yanıt, özet; "sınırlı süre ücretsiz"), PDF Spaces. 26.09.00 ile Apple CarPlay'de PDF dinleme.
- Fiyat (liste): Premium aylık 12,99 / 14,99; yıllık 48,99 / 69,99; haftalık 9,99; AI Assistant 6,99; PDF Pack 9,99 USD (dönemler belirtilmemiş).
- İşleme yeri: belirtilmemiş; bulut depolama ve Document Cloud entegre. Gizlilik etiketi çok geniş (satın alma, kişiler, kullanıcı içeriği, arama geçmişi izleme/bağlı).
- Şikâyet (B3, Adobe Community, çoğu 2021-2023, son Ekim 2025): iptale rağmen ücretlendirme, iade için Apple'a yönlendirme, premium alınmasına rağmen "ücretsiz kullanıcı" görünmesi, "restore purchases" başarısızlığı, yer imi ekleme/silme ve iPad'de salt-okunur dosya sorunları, yüklemede takılma. Açıklamanın "iOS 16" ile mağaza gereksinimi (iOS 18.3) çelişkisi.

### 2.4 PDF Expert (Readdle) — id743974925
- Readdle; v7.26.3; 315,5 MB; iOS 16+; 4,67 / 216 bin oy; Editors' Choice. Türkçe YOK (10 dil).
- Ücretsiz: okuma (gündüz/gece/sepya), arama, TTS, vurgu/alt çizgi/üstü çizili, kalem, şekil, metin, not, damga, sesli not (ses kaydı), form doldurma (AcroForm ve statik XFA), imza (çizme/içe aktarma/kayıtlı).
- Premium: metin yerinde düzenleme, görsel ekleme/değiştirme/boyutlandırma, bağlantılar, anahat; Word/görsel/PDF oluşturma ve dönüştürme (Word/Excel/PPT/JPG/PNG/TXT); birleştirme, sayfa çıkarma/ekleme/silme/döndürme/sıralama; sıkıştırma; "PDF Copilot" (ana noktalar, özet, referanslı soru-yanıt, sözcük açıklama); uygulama parolası; kalıcı karartma; ölçüm/çokgen/redline araçları (inşaat); özelleştirilebilir araç çubuğu; sunum modu. Çeviri "uygulama içinde çevrimdışı" yapılıyor (liste ifadesi). Tek abonelik iPhone+iPad+Mac.
- Fiyat (liste, dönem belirtilmemiş): Premium 49,99 USD; Basic 9,99; Education 39,99; Mac & iOS 79,99. Üçüncü taraf bayi sayfası yıllık çoklu cihaz planını 79,99 USD gösteriyor (B3, doğrulanamadı). 2023'te v7 ile abonelik modeline geçti.
- UX (ekran görüntüleri): üstte "Annotate ⌄" mod seçici ve araç çubuğu; Tools ızgarası: Annotate, Edit PDF, Convert PDF, PDF Copilot, Fill & Sign, Translate PDF, Manage Pages, Reduce File Size.
- Şikâyet (B3, Kimola önizlemesi, eski): abonelik modeli değişikliği, "kenar boşluğu gizleme" gibi eksik özellikler, silgi sorunları, yavaş destek; bir bayi sayfası faturalandırma ve kimlik doğrulama sonrası özellik kısıtı şikâyetlerini aktarıyor (örneklem küçük, düşük ağırlık).

### 2.5 Documents by Readdle — id364901807
- Readdle; v8.22.10; 430 MB; iOS 16+; 4,79 / 633 bin oy; yaş 16+ (kısıtsız web erişimi). Türkçe YOK (11 dil).
- Dosya yöneticisi + PDF + tarayıcı + ZIP/RAR + medya: mevcut metni düzenleme, vurgu, not, çıkartma, birleştir/böl/döndür/sırala, Word/görsel dönüşüm, imza, form (metin, onay işareti, baş harf), sıkıştırma (PDF/foto/dosya), OCR'lı aranabilir PDF tarama, ses/video yazıya dökme, Smart Eraser, Wi-Fi aktarım, yerleşik tarayıcıyla indirme, bulut sürücüleri (indirmeden erişim), renkli etiketler. 8.22: "Smart Insights" (özet, ana çıkarımlar, önyargı tespiti), PDF olarak dışa aktarım; 8.21: yerleşik medya dönüştürücü/sıkıştırıcı. iPhone Duo uyumu.
- Fiyat: Documents Plus 9,99 / 14,99 / 49,99 USD; Documents VPN 12,49 / 89,99 USD (dönemler belirtilmemiş). Hangi özellik ücretsiz/ücretli net değil (kullanıcı yorumları "aylık yükseltme, VPN ve pro PDF için gerekli" diyor, resmi değil).
- İşleme yeri: belirtilmemiş.

### 2.6 PDFelement (Wondershare) — id1516765045
- Wondershare; v6.1.21; 208,6 MB; iOS 15+; 4,6 / 7,6 bin oy; yaş 9+. Türkçe YOK (13 dil).
- AI: PDF sohbeti, özet, 60+ dile seçili metin çevirisi, zihin haritası, sesli not kaydı + yazıya dökme. Düzenleme: metin, görsel, bağlantı, filigran; yazı tipi koruma. Okuma: Liquid Mode, yer imi, sesli okuma (ses/hız seçilebilir). Tarama+OCR (fiş, fatura, kimlik); birden çok taramayı tek PDF'e. Dönüşüm: PDF→Word/Excel/PPT/görsel; Office/görselden PDF. Açıklama: vurgu, alt çizgi, çizim, yapışkan not, mesafe/çevre/alan ölçümü. Boş şablon (özgeçmiş, fatura, planlayıcı, sözleşme, davetiye). Sıkıştır/birleştir/sayfa yönetimi. Form + yazılı/çizili imza + özel damgalar. PDFelement Cloud. Parola/şifreleme. 6.1.21: el yazısı notları tanıyıp metne çevirme. Özelleştirilebilir araç çubuğu.
- Fiyat (liste): haftalık 6,99 / 9,99; üç aylık 9,99; yıllık 29,99; aylık AI 3,99; PDF Editor & Converter & Scanner 6,99; tek seferlik/yıllık karışık SKU'lar (39,99).
- İşleme yeri: belirtilmemiş (AI/OCR/çeviri/dökme). Gizlilik etiketi: üçüncü taraf reklam için tanımlayıcı/kullanım verisi.
- B3: kullanıcı yorumunda yavaş destek, ikinci cihazda oturum sorunu.

### 2.7 UPDF — id1595826623
- Superace; v2.5.4; 205 MB; iOS 14+; 4,6 / 697 oy. Türkçe YOK (12 dil).
- Düzenleme: metin rengi/yazı tipi/boyut, görsel döndür/ayıkla/değiştir/kırp, filigran, bağlantı. AI: özet, çeviri, açıklama, yeniden yazma, sohbet, sayfa bazlı özet/çeviri, sohbeti Markdown/TXT'ye aktarma; 2.5.0 ile AI yer imi, anlamsal arama, AI yazma/ton/dilbilgisi; sohbet DeepSeek-R1 modeline geçti (1.5.26 notu). Okuma: dikey/yatay kaydırma, iki sayfa, karanlık mod, yer imi, arama, slayt gösterisi, sesli okuma. Açıklama: kalem, vurgu, alt çizgi, dalgalı, kutu, yorum, belirtme çizgisi, yapışkan not, şekil, damga, çıkartma. OCR: 38 dil. Tarama, kimlik kartı taraması (tek sayfaya iki yüz). Dönüşüm: PDF→Word/Excel/PPT/görsel. Sayfa: ekle/değiştir/çıkar/böl/döndür/sil/sırala/birleştir/kopyala-yapıştır. İmza (çizili/görsel/bulutta kayıtlı), form. Yeni PDF: boş, çizgili, noktalı, kareli, milimetrik kâğıt. Güvenlik: açma/düzenleme/yazdırma parolası, dijital imza ekleme (sertifika ayrıntısı doğrulanamadı), Security Space (Face ID/Touch ID/parola, ücretsiz denemede 10 öge sınırı). Dosya yönetimi: zip aç/oluştur, çöp kutusu, çoklu seçim; Wi-Fi ile bilgisayardan alma; iCloud harici dosya düzenleme (2.5.4); SMB, SFTP, FTP, WebDAV (2.5.1-2.5.2). Bulut: 1 GB ücretsiz, 10 GB ücretli. Toplu işlem ve OCR dönüşümü gibi gelişmiş özellikler MASAÜSTÜ'NE özgü deniyor.
- Fiyat (liste): Aylık 9,99; Üç aylık 19,00; Yıllık 49,99; Süresiz 79,99; Pro+AI Unlimited 18,99; AI Standard aylık 15 / yıllık 69; AI Unlimited 15 / 79; "UPDF & AI Add-on for iOS" 148,99 USD. Ücretsiz denemede tarama 5 sayfa ile sınırlı.
- İşleme yeri: belirtilmemiş. B3 (G2 özeti): "sınırlı özellik", "OCR sorunları (9 yorum)", "sezgisel değil (8)", "performans sorunları (7)"; üçüncü taraf yaşam boyu fırsat sayfası AI eklentisinin dahil olmadığını ve 2 mobil cihaz sınırını yazıyor.

### 2.8 Xodo — id805075929
- Xodo Technologies (Apryse altyapısı); v9.18.1; 108 MB; iOS 16+; 4,4 / 1,7 bin oy. Türkçe YOK.
- Sıkıştır, düzleştir (flatten), döndür, kırp, sayfa ekle/sil/sırala, böl/çıkar, boş veya şablondan yeni PDF; kamerayla tarama + isteğe bağlı OCR; elle veya yazılı imza (Apple Pencil); Office/iWork→PDF, JPG/PNG↔PDF; gündüz/gece/sepya, yer imi, çoklu sekme, yazdırma; vurgu, görsel, bağlantı, damga; küçük resim görünümünde sayfa düzenleme; dosya yöneticisi; iCloud/OneDrive/Google Drive/Dropbox; parola ekle/kaldır.
- Abonelikle: PDF→Office, karartma, yüksek sıkıştırma, birleştirme, doldurulabilir form oluşturma, akıllı kalem, okuyucu modunda açıklama, katman görüntüleme, OCR, özel araç çubuğu.
- Fiyat (liste): Mobile aylık 11,99; yıllık 107,99; PDF Converter & Editor 11,99 / 39,99 USD.
- Gizlilik: "sizi izlemek için kullanılan veri: kullanım verisi" (diğer şirketlerin uygulamalarında takip), reklam amaçlı tanımlayıcı.

### 2.9 Foxit PDF Editor (mobil) — id507040546
- Foxit; v2026.5.1; 344 MB; iOS 17+; 4,5 / 4,8 bin oy; Türkçe YOK.
- Ücretsiz: görüntüleme, yeniden akış (reflow), yer imi, arama, sesli okuma, açıklama/damga, form doldurma + form verisi içe/dışa aktarma + HTTP/FTP/e-posta ile gönderme, el yazısı imza, Wi-Fi aktarım, bulut. Abonelikle: boş PDF/Office-görsel-metin-HTML'den oluşturma, PDF→Office/görsel/metin/HTML, birleştirme, ses/video/bağlantı ekleme, metin/görsel nesne düzenleme, belge özellikleri, optimize, sayfa yönetimi, XFA formlar, mevcut dijital sertifikayla imza, parola + Microsoft Information Protection, karartma, taranmış/el yazısı metni dijitale çevirme. AI Assistant: sohbet-ajan, özel "beceriler", görsel/grafik oluşturma, çeviri, otomatik yer imi, akıllı sesli okuma (2026.5.1: çok modelli, diyagram oluşturma).
- Fiyat: PDF Editor yıllık 39,99 / aylık 6,99; Editor+ yıllık 139,99; AI Assistant yıllık 49,99 USD.
- İşleme yeri: belirtilmemiş; AI için yönetici politikası/Foxit hesabı gerekli (sunucu bileşeni ima ediyor, doğrulanmadı). Kurumsal (Intune) odaklı.

### 2.10 PDFgear — id6465897558
- PDF Gear Tech; v2.29; 47,5 MB; iOS 14+; 4,7 / 8,9 bin oy; Türkçe YOK. Ücretsiz, listede uygulama içi satın alma YOK ve "filigran/sayfa sınırı yok". (9to5Mac 2023: şirket ileride ücretli premium planlıyor; Gizmodo sayfası premium yok diyor; güncel durum doğrulanamadı.)
- Özellikler: görüntüleme/yazdırma, vurgu/alt çizgi/üstü çizili, metin ekleme, dikdörtgen/daire/çizgi/ok, kalem+silgi, sayfa ekle/sil/döndür/çıkar, form (metin, onay/çarpı), damga, imza (görsel/klavye/çizim), dosya yönetimi/iCloud. Sürüm geçmişinden: Tools sekmesi (birleştir, böl, kırp), PDF çevirisi, Wi-Fi aktarım, metin ve görsel düzenleme, yer imi, form alanı vurgulama, iPad Split View. AI "PDF ile sohbet" (özet, çeviri, düzenle/açıklama/sırala komutları). Sıkıştırma ve Word↔PDF dönüşüm rehberleri üretici sitesinde.
- Yalnız "kullanım verisi (analitik)" gizlilik etiketi: listedeki en temiz gizlilik etiketlerinden biri.
- İşleme yeri: belirtilmemiş (çeviri/dönüşüm/AI).

### 2.11 Nitro PDF Pro — id1608616539
- Nitro Software; v26.2; 61,8 MB; iOS 18+; 3,9 / 161 oy. Türkçe YOK (5 dil). 14 gün deneme. Yıllık 19,99 USD; "Nitro PDF Pro for iOS" 9,99 USD.
- Metin düzenleme, görsel ekleme, çizim, yorum, vurgu, form doldur/kaydet, imza kitaplığı (imza/metin/görsel), parola + şifreleme düzeyi, birleştir, sayfa ekle/sil/döndür/sırala, koyu mod, okuyucu modu, iPad'de iki belge. Apple Pencil/Pencil Pro. 26.2 ana ekranı yeniden tasarlandı: hızlı eylemler (Open, Scan, Encrypt, Combine, Table Extract, Form Extract), son dosyalar, arama, New düğmesi. Yeni: tarayıp PDF oluşturma, taranmış belge OCR, tablo/form verisi çıkarma (Nitro hesabıyla), metin karartma.
- B3: iPad'de doldurulabilir PDF'te çökme, "basit işler için sezgisel değil", bir yorumcu Pencil desteği eksik demiş (resmî liste Pencil desteği diyor: çelişki).

### 2.12 Nutrient (PSPDFKit) PDF Viewer — id1120099014
- PSPDFKit GmbH; v2026.13; 114,5 MB; iOS 17+; 4,6 / 9,1 bin oy; Türkçe VAR (28 dil).
- Ücretsiz: görüntüle, tam metin arama, Document Browser/Open In Place, vurgu/işaretleme (parmak/Pencil), yorum (not/metin/çizim/görsel/ses), imza (taşı/boyutlandır/düzleştir), sayfa taşı/döndür/sil/ekle, yer imi, form doldurma + düzleştirme, klasör, TTS, okuma konumu eşitleme. Pro: görsel açıklama (JPEG/PNG, orijinale dokunmadan), nota yanıt, belge birleştirme, parola (kullanıcı/sahip izinleri), karartma, harici ekranda sunum modu. Meta veriyi GÖRÜNTÜLER (silme belirtilmemiş).
- AI Assistant (Beta, 2025.12): "belgeleri ve soruları tamamen cihazınızda işler"; iOS 26 + Apple Intelligence gerekir (liste ifadesi). Yani cihaz içi AI örneği.
- Fiyat: Pro 3 ay 6,99; yıllık 19,99 USD; 7 gün deneme.

### 2.13 GoodReader — id777310222
- Good.iWare; v6.0.1238; 56 MB; ücretli uygulama 6,99 USD; yalnız İngilizce; 4,66 / 13,8 bin oy.
- Okuma motoru (PDF, TXT, Office, iWork, HTML, görsel, ses, video), yeniden akış, not/çizim/vurgu, açıklama özetini paylaşma, kategorili not alma, dosya yöneticisi (masaüstü benzeri), Dropbox/OneDrive/Google Drive/Box, WebDAV/SMB/FTP/SFTP. v6: sürükle-bırak, Mac desteği, açıklamalarda geri al/yinele, Widget ve Kısayollar, PDF köprüleri, yer imi/anahat arama, renkli dosya sekmeleri. Pro Pack: AES-256 şifreleme (Apple Data Protection'dan ayrı), özel OneDrive/SharePoint ve Dropbox Team Space.
- Pro Pack aylık 3,99 / yıllık 24,99 / 89,99; Auto Sync 59,99 USD.

### 2.14 Genius Scan — id377672876
- The Grizzly Labs; v8.15.1; 104,6 MB; iOS 17+; 4,9 / 1,4 milyon oy; Türkçe VAR.
- Ücretsiz: otomatik algılama/kırpma, bozulma düzeltme, gölge/leke giderme, S/B + beyaz tahta + fotoğraf filtreleri, toplu tarama, birleştir/böl, çok sayfalı PDF, foto/PDF içe aktarma, etiketleme, içerik/meta arama, e-posta. Plus: Face ID kilidi, PDF parolası, akıllı yeniden adlandırma, Box/Dropbox/Drive/OneDrive/WebDAV dışa aktarma ve otomatik arka plan dışa aktarma, OCR (metin, aranabilir PDF, kartvizit). Genius Cloud ayrı abonelik (yedek, eşitleme, boşaltma). 8.15.1: A4 PDF tam ISO boyutu, Kısayollar dışa aktarma, Spotlight.
- İşleme yeri: sayfa "belge işleme cihazda yapılır" diyor; OCR yeri belirtilmemiş; yeniden adlandırma Genius Cloud isteği. Genius Scan SDK dokümanı OCR dillerinde Türkçeyi (`tr`) listeliyor (uygulamanın aynı motoru olduğu doğrulanmadı).
- Fiyat: Plus 1,99 / 11,99; Ultra 4,99 / 39,99 / 49,99 USD (dönemler belirtilmemiş).

### 2.15 Scanner Pro (Readdle) — id333710667
- Readdle; v9.0.3; 289,6 MB; iOS 18+; 4,87 / 337 bin oy.
- Otomatik kenar algılama + perspektif düzeltme (belge, fiş, kimlik, kitap, foto); eski fotoğraf renklendirme/S-B/gri; tarama üzerinde açıklama; aranabilir PDF; PDF/Word/PPT/JPG dışa aktarma; sayfa birleştirme; PDF parola ekle/kaldır; imza; form (metin, onay, baş harf); OCR ile düzenlenebilir metin, tam metin arama, metni kopyala/çevir; QR kod; iCloud eşitleme; Dropbox, Evernote, Google Drive, Box, OneDrive, OneNote, WebDAV; faks. Son notlar: akıllı filtreler, Auto Name, Ölçüm Modu, İmza aracı, Çevirmen (iOS 26, "doğrudan cihazda"), kâğıt boyutu algılama. ISO 27001.
- Dil: açıklama "25+ dil" ve Türkçeyi sayıyor; mağaza metaverisi ise 10 dil gösteriyor (Türkçe yok): çelişki, doğrulanamadı.
- Fiyat: Scanner Pro Plus 3,99 / 6,99 / 7,99 / 19,99 / 29,99 / 59,99; Fax Pack 0,99; Gider Raporu 4,99 USD.

### 2.16 Adobe Scan — id1199564834
- Adobe; v26.10.19; 419,7 MB; iOS 18+; 4,9 / 1,6 milyon oy; Türkçe VAR.
- Toplu tarama (High-speed), eğrilik düzeltme, kenar algılama/netleştirme, fiş/kimlik/not/kartvizit/beyaz tahta; sihirli silgi (parmak, gölge, leke, kırışık giderme), değiştir (kırp, döndür, yeniden boyutla, renk), sayfa yeniden sıralama, sayfa çıkarma (ücretli), OCR (el yazısı dâhil; Digitize beta), klasörler, kartvizitten kişi, parola, Smart Library; Word/Excel/PPT dışa aktarım; Acrobat'ta açma.
- Ücretsiz: tarama + temel düzenleme. Ücretli: tarama birleştirme, OCR 5→100 sayfa, sihirli silgi geliştirmeleri, sayfa çıkarma. Plus aylık 4,99 / yıllık 19,99; Premium 9,99–69,99 USD.
- İşleme yeri: taramalar otomatik Adobe Document Cloud'a kaydedilir; PDF'ler Scan'de açılınca Document Cloud'a yüklenir (liste ifadesi). Gizlilik: kullanıcı içeriği, arama geçmişi dahil bağlı veri.

### 2.17 CamScanner — id388627783
- INTSIG; v7.28.0; 393 MB; iOS 15+; 4,84 / 1,96 milyon oy; Türkçe VAR (58 dil).
- Çok sayfalı PDF/JPG tarama; kimlik/pasaport, Slides ve Mega Scan (büyük nesne/plan) modları; QR; metin çıkarma ve tara-çevir (yan yana); web sayfası/Office/metin/görselden PDF; filtreler + gürültü giderme; klasör (sürükle-bırak) ve parolalı klasör/dosya; PDF için mozaik (hassas içeriği maskeleme); Word düzenleme, Markdown; e-imza ve CS Sign; paylaşım + çok kişili yorum; e-posta/bulut (Dropbox, Drive, Evernote, OneDrive) ve yazdırma.
- Fiyat: Premium 4,99 – 69,99 USD (hafta 9,99; ay 9,99; yıl 49,99/59,99/69,99), tek sayfa faks 0,99.
- Gizlilik: "sizi izlemek için": tanımlayıcılar ve kullanım verisi (üçüncü taraf reklam).
- İşleme yeri: tarama cihazda; OCR/çeviri/AI yeri belirtilmemiş; çevrimiçi paylaşım sunucu.

### 2.18 SwiftScan (Maple Media, "AI Document Scanner") — id834854351
- v9.6.82; 521,7 MB; iOS 15+; 4,8 / 19 bin oy; yaş 18+ (reklam); Türkçe VAR.
- 200 dpi+ PDF/JPG tarama; kenar algılama; QR/barkod/kartvizit/fiş/beyaz tahta; ön ayarlı boyutlar; tüm sayfaları aynı anda kırpma; AI özet/çeviri/AI OCR/AI dosya adları; filtreler; yorum/çizim; e-imza; metin karartma; sayfa taşı/döndür/ekle/sil/birleştir/sırala; e-posta/yazdır/faks; iCloud Drive, Dropbox, Drive, Box, Evernote, WebDAV, FTP/SFTP/FTPS; PDF parola; Touch/Face ID kilidi; ana ekran/kilit ekranı/ekstra büyük widget; Quick Actions; hatırlatıcı; temalar; Family Sharing (Plus).
- Fiyat: Plus aylık 7,99 / 9,99; yıllık 59,99; VIP aylık 5,99 / yıllık 34,99; Pro 3,99 / 6,99 / 8,99 USD (çoklu SKU).
- Geliştirici beyanı: "Tüm belge etkinliği cihazınızda veya seçtiğiniz bulut yedeğinde gerçekleşir"; AI'nin yeri belirtilmemiş. Ayrı bir "SwiftScan Pro Document Scanner" (id1007355333, 199,99 USD) listesi var (aynı marka, ayrı ürün; karıştırma).

### 2.19 Microsoft Lens — KAPANDI
- Microsoft resmi sayfası: iOS/Android'de emeklilik 9 Ocak 2026'da başladı; 9 Şubat 2026'da mağazalardan kaldırıldı ve destek bitti; 9 Mart 2026'da yeni tarama sona erdi. Önerilen alternatif OneDrive uygulamasının yerleşik tarayıcısı (taramalar yerel cihaza kaydedilemiyor, OneDrive'a kaydediliyor). Dolayısıyla "rakip" değil; ders: ücretsiz tarama kapanabilir, kullanıcı verisi taşınabilir olmalı.

### 2.20 Apple yerleşik: Preview (iOS 26+), Dosyalar, Notlar, Markup
- Preview iPhone'da (iOS 26 ile geldi; Apple yardım sayfaları iOS 27 sürümünü anlatıyor): PDF/görsel açma, belge tarama (otomatik yakalama, manuel deklanşör; küçük resimlerden kırp/döndür/renk ayarla), form doldurma (AutoFill önerisi, imza alanında parmakla/iPhone Duo'da Apple Pencil USB-C), PDF'i parolayla kilitleme (Lock), vurgu/alt çizgi, Markup (çizim, metin kutusu, şekil, çıkartma, imza), sayfa ekle (boş sayfa, dosyadan ekle, tarayıp ekle)/sil/döndür/taşı/kırp, dışa aktar/sıkıştır, yeniden adlandır/taşı/çoğalt, görsel düzenleme (arka plan kaldırma).
- Notlar: tarama (otomatik/manuel, iOS 26'da filtre/flaş), köşe kırpma, Markup ile imza ekleme. Dosyalar: Daha Fazla menüsünden tarama.
- Kısayollar (Shortcuts): Make PDF, PDF boyutunu optimize etme gibi eylemler var; birleştirme/bölme için eylem zinciri kuruluyor (B3, Apple listesi doğrulanamadı).
- Ücretsiz, Türkçe sistem arayüzü. Apple Intelligence Türkçe desteği iOS 26.1 ile eklendi (9to5Mac).

### 2.21 Goodnotes — id1444383602 (yalnız PDF açıklama yönü)
- Goodnotes Limited; v7.1.32; 4,7 / 465 bin oy; Türkçe VAR (15 dil).
- PDF içe aktar (e-posta ile adresine gönderme dâhil), el yazısı/yazılı açıklama, PDF içindekiler tablosunu otomatik alma, özel anahat, PDF dışa aktarma/paylaşma/yazdırma. Listede PDF tarama, form doldurma, OCR geçmiyor. AI (AI Pass 9,99 USD aylık). Fiyat: Essential yıllık 11,99; Pro yıllık 35,99; Goodnotes 6 tek sefer 28,99 USD.
- Goodnotes Classroom (ayrı uygulama, id6499033382; sayfası şu an 404, yalnız arama özetinden): öğretmenin el yazısı geri bildirimi, "soruya göre işaretleme", AI ile model cevaba göre notlama, Google Classroom eşitleme (satıcı iddiaları, doğrulanamadı).

### 2.22 LiquidText — id922765270 (yalnız PDF açıklama yönü)
- LiquidText Inc.; v7.3.16; 332 MB; iPhone iOS 17.6+ (iPad, Mac, Vision da); 4,6 / 6,4 bin oy; yalnız İngilizce.
- Çalışma alanı + alıntı/bağlantı: metinden alıntı çıkarma, "ink link", zihin haritası (ücretli), iki parmakla sıkıştırarak uzak sayfaları yan yana karşılaştırma, aramayı yan yana daraltma, 3 belgeye kadar aynı anda (ücretli), anında OCR, tam belge OCR (ücretli), Zotero/Mendeley (ücretli), PDF/Word dışa aktarma, gerçek zamanlı eşitleme (ücretli).
- Fiyat: Live aylık 10,90 / yıllık 99,99; öğrenci 5,49 / 54,90; Unlimited yıllık 189,99; Pro II 89,99 USD.

### 2.23 MarginNote 4 — id1531657269 (yalnız PDF açıklama yönü)
- Beijing Yunsi; v4.4.6; iOS 17+; 4,5 / 737 oy; yalnız İngilizce, Japonca, Korece, Çince (Türkçe YOK).
- Her alıntı = PDF vurgusu + zihin haritası düğümü + flashcard ("Card Axis"); uzun basarak PDF'in herhangi yerine yazı alanı; Immersive Mode (Oku/Yaz/Hatırla); "AI Extract Questions" (alıştırma ve sınav kâğıtlarını soru-cevap kartlarına böler); AI flashcard üretimi; FSRS aralıklı tekrar; çift belge karşılaştırma; Study Set (PDF, EPUB, video, ses); Apple Intelligence ile cihaz içi hatırlatma ipuçları veya bulut LLM, özel AI sağlayıcı.
- Fiyat: PRO süresiz 12,99; MAX yıllık 12,99 / 16,99; MAX süresiz 51,99 USD (SKU karışık).


---

## 3. Özellik x uygulama matrisi

İşaretler: `+` var, `$` ücretli katman, `~` kısmi/dolaylı, `-` yok/yalnız masaüstü, `?` kaynakta belirtilmemiş (yok demek değil). Kaynak: App Store listesi (B1) + Bölüm 2. Tarayıcı odaklı uygulamalarda (GS = Genius Scan, SP = Scanner Pro, AS = Adobe Scan, CS = CamScanner, SW = SwiftScan) düzenleme sütunları çoğunlukla `?` kalır çünkü bunlar belge düzenleyici değildir.

### 3.1 Düzenleme ve sayfa işlemleri

| Uygulama | Mevcut metni düzenle | Metin/görsel/şekil ekle | Açıklama (vurgu/çizim/not) | Sayfa düzenle (sırala/sil/döndür/kırp) | Birleştir | Böl/çıkar | Sıkıştır | Filigran | Sayfa no / üst-alt bilgi |
|---|---|---|---|---|---|---|---|---|---|
| PDF Love | ? | + | + | + (kırp ?) | + | + | + | + | + |
| iLovePDF | ? | + | + | + | + | + (dosya boyutuna göre de) | + | + (metin/görsel) | + (sayfa no) |
| Smallpdf | ? | + | + | + | + | + | + | ? | ? |
| Acrobat | $ | $ | + | $ | $ | $ | $ | ? | ? |
| PDF Expert | $ | + (görsel $) | + | $ | $ | $ | $ | ? | ? |
| Documents | + | + | + | + | + | + | + | ? | ? |
| PDFelement | + | + | + (+ ölçüm) | + | + | + | + | + | ? |
| UPDF | + | + | + | + | + | + | ? | + | ? |
| Xodo | ? | + | + | + (kırp +) | $ | + | + ($ yüksek) | ? | ? |
| Foxit | $ | $ | + | $ | $ | $ | $ (optimize) | ? | ? |
| PDFgear | + | + | + | + | + | + | + | ? | ? |
| Nitro | + | + | + | + | + | ? | ? | ? | ? |
| Nutrient | ? | + (görsel/ses/yorum) | + | + | $ | ? | ? | ? | ? |
| GoodReader | - (TXT düzenler) | ~ (not/çizim) | + | ? | ? | ? | ? | ? | ? |
| Genius Scan | - | ? | ? | ? | + | + | ? | ? | ? |
| Scanner Pro | - | ~ | + | ? | + | ? | ? | ? | ? |
| Adobe Scan | - | ? | ? | + (çıkar $) | $ | $ | ? | ? | ? |
| CamScanner | ~ (Word/Markdown düzenleme) | ? | ~ (mozaik) | ~ (klasörde sürükle) | ? | ? | ? | ? | ? |
| SwiftScan | - | ? | + | + | + | ? | ? | ? | ? |
| Apple Preview | - | + (metin kutusu, şekil, çıkartma, imza) | + | + | ~ (sayfa sürükleyerek) | ~ (sil/çıkar) | + (dışa aktar/sıkıştır) | ? | ? |

Açıklama-odaklı üç araç (ayrı tablo, çünkü tasarımları farklı):

| Uygulama | PDF açıklama | Alıntı/bağlantı | Yan yana karşılaştırma | El yazısı | iPhone |
|---|---|---|---|---|---|
| Goodnotes | + (el yazısı + yazı) | ? | ? | + | + |
| LiquidText | $ (çizim ücretli) | + (ink link $) | + (sıkıştırma; 3 belge $) | $ | + (iOS 17.6+) |
| MarginNote 4 | + | + (Card Axis) | + (çift belge) | + (katman) | + (iOS 17+) |

### 3.2 Dönüştürme ve tarama

| Uygulama | PDF→Office (Word/Excel/PPT) | Office→PDF | PDF↔görsel | HTML/metin/EPUB | Kamera tarama (kenar algılama) | Çok sayfa/toplu tarama | OCR | Türkçe OCR açık beyanı |
|---|---|---|---|---|---|---|---|---|
| PDF Love | ? | + (yalnız Word) | + | ~ (OCR ile PDF→metin, PDF→ZIP) | + | ? | + | ? |
| iLovePDF | + | + | + (+ görsel çıkarma) | ? | + | + | + | ? |
| Smallpdf | + | ~ | + | ? | + | ? | + (çok dilli) | ? |
| Acrobat | $ | $ (+ web sayfası) | $ | ? | ~ (Adobe Scan ile) | ~ | $ | ? |
| PDF Expert | $ | $ | $ | ~ (TXT) | ? | ? | ? ("Recognize text" araç listesinde) | ? |
| Documents | + | + | + | ? | + | ? | + | ? |
| PDFelement | + | + | + | ? | + | + | + | ? |
| UPDF | + | + (iWork/HTML/XML açar) | + | + | + (+ kimlik kartı) | + | + (38 dil) | ? (liste Türkçeyi adıyla vermedi) |
| Xodo | $ | + (Office/iWork) | + (JPG/PNG) | ? | + | ? | $ | ? |
| Foxit | $ | $ | $ | $ (HTML, metin) | + | ? | $ | ? |
| PDFgear | + (site rehberi) | + (site rehberi) | ? | ? | ? | ? | ? | ? |
| Nitro | ? | ? | ? | ? | + | ? | + | ? |
| Nutrient | - | - | ~ (JPEG/PNG açıklama) | ? | - | - | - | - |
| GoodReader | ? | ~ (Office okur) | ? | ~ (HTML okur) | - | - | - | - |
| Genius Scan | ? | ? | + (foto/PDF içe aktar) | ? | + | + | $ | ~ (SDK dokümanı `tr` listeler) |
| Scanner Pro | + (Word, PPT, JPG) | ? | + | ? | + | + | + | + (açıklama adıyla sayıyor; metaveri çelişkili) |
| Adobe Scan | + (Word/Excel/PPT) | ? | + (JPEG) | ? | + | + (toplu) | + ($ 5→100 sayfa) | ? |
| CamScanner | ? | + (Office/metin/görsel/web) | + | ~ (Markdown) | + (+ kimlik, Mega Scan) | + | + | ? |
| SwiftScan | ? | ? | + (JPG) | ? | + | + | $ (AI OCR) | ? |
| Apple Preview/Notlar | - | - | ~ | ? | + | + | ~ (Live Text; metin seçme) | ~ (macOS 27.2'de Vision `tr-TR` ölçüldü; iOS'ta doğrulanmadı) |

### 3.3 Form, imza, güvenlik

| Uygulama | Form doldur | Form oluştur | Kayıtlı el imzası | Dijital sertifika imzası | Dosya parolası/izin | Redaksiyon (karartma) | Meta veri temizleme | Uygulama kilidi (Face ID) |
|---|---|---|---|---|---|---|---|---|
| PDF Love | ? | ? | + | ? | + (ekle/kaldır) | + (bulanıklaştır/karart; kalıcı silme mi: doğrulanamadı) | ? | + |
| iLovePDF | + | ? | + (parmakla) | ? | + | + (sürüm notu) | ? | ? |
| Smallpdf | + | ? | + (+ "dijital imza") | ? | ? | ? | ? | ? |
| Acrobat | + (Fill & Sign) | ? | + | ? | $ | ? (Adobe mobil için doğrulamıyor) | ? | ? |
| PDF Expert | + (AcroForm, statik XFA) | ~ (3. taraf: alan üretmez) | + | ? | ? | $ | ? | $ (uygulama parolası) |
| Documents | + | ? | + | ? | ? | ? | ? | ? |
| PDFelement | + | ? | + (+ özel damga) | ? | + | ? | ? | ? |
| UPDF | + | ? | + (bulutta kayıtlı) | ~ (liste "dijital imza ekleme" der; sertifika ayrıntısı yok) | + (açma/düzenleme/yazdırma) | - (üretici: gerçek karartma masaüstünde) | ? | + (Security Space) |
| Xodo | + | $ | + (yazılı kayıtlı) | ? | + (ekle/kaldır) | $ | ? | ? |
| Foxit | + (+ XFA $) | ? | + | $ (mevcut sertifikayla) | $ (+ MIP) | $ | ~ (belge özelliklerini düzenle $) | ? |
| PDFgear | + | ? | + | ? | ? | ? | ? | ? |
| Nitro | + | ? | + (imza kitaplığı) | ? | + (şifreleme düzeyi) | + (metin karartma) | ? | ? |
| Nutrient | + (+ düzleştir) | ? | + | ? | $ (kullanıcı/sahip izinleri) | $ | ~ (görüntüler) | ? |
| GoodReader | ? | ? | ? | ? | $ (AES-256 Pro Pack) | ? | ? | ? |
| Genius Scan | - | - | - | - | $ (PDF parola) | - | - | $ |
| Scanner Pro | + | ? | + | ? | + (ekle/kaldır) | ? | ? | ? |
| Adobe Scan | - | - | ~ (Acrobat'ta) | ? | + (tarama parolası) | ~ (Acrobat'a yönlendirir) | ? | ? |
| CamScanner | ? | ? | + (CS Sign) | ? | + (klasör/dosya parolası) | ~ (mozaik) | ? | ? |
| SwiftScan | ? | ? | + | ? | + | + (metin) | ? | + |
| Apple Preview | + (AutoFill ile) | - | + (kayıtlı imzalar, birden çok) | ? | + (Lock) | ? | ? | ~ (sistem) |

### 3.4 AI, çeviri, sesli okuma, bulut, otomasyon, fiyat

| Uygulama | Özet / sohbet | Çeviri | Sesli okuma (TTS) | Belge karşılaştırma | Bulut / eşitleme | Kısayollar / widget / uzantı | Fiyat modeli (USD, ABD) | Türkçe arayüz |
|---|---|---|---|---|---|---|---|---|
| PDF Love | - (listede yok) | ? | ? | ? | iCloud | ? | Haftalık 4,99 / Aylık 6,99 / Yıllık 29,99 | Yok |
| iLovePDF | ? | + | ? | ? | Drive, Dropbox | Kısayollar (sürüm notu) | Aylık 5,49 / Yıllık 44,99; günlük görev limiti | Var |
| Smallpdf | ? | ? | ? | ? | opsiyonel bulut | ? | Aylık 7,99-14,99 / Yıllık 49,99-119,99; günlük limit | Var |
| Acrobat | $ (AI Assistant; geçici ücretsiz) | ? | + (kaliteli ses $; CarPlay) | ? | OneDrive/Dropbox/Drive + Adobe | ? | Aylık 12,99-14,99 / Yıllık 48,99-69,99 / Haftalık 9,99 | Var |
| PDF Expert | $ (Copilot) | + (çevrimdışı) | + | ? | iCloud vb.; Mac eşitleme | Özel araç çubuğu | Yıllık 49,99 (liste); Education 39,99 | Yok |
| Documents | + (Smart Insights) | ? | ? | ? | Çok sağlayıcı, Wi-Fi | ? | Plus 9,99-49,99 (+ VPN ayrı) | Yok |
| PDFelement | + (sohbet, özet, zihin haritası) | + (60+ dil) | + | ? | PDFelement Cloud | ? | Haftalık 6,99-9,99 / Üç aylık 9,99 / Yıllık 29,99 | Yok |
| UPDF | + (özet, sohbet, AI yer imi, anlamsal arama) | + | + | ? | UPDF Cloud + SMB/SFTP/FTP/WebDAV | ? | Aylık 9,99 / Yıllık 49,99 / Süresiz 79,99 + AI ayrı | Yok |
| Xodo | - | ? | ? | ? | iCloud/OneDrive/Drive/Dropbox | ? | Aylık 11,99 / Yıllık 107,99 | Yok |
| Foxit | $ (sohbet-ajan, beceriler) | $ | + | ? | Drive/OneDrive | ? | Aylık 6,99 / Yıllık 39,99; Editor+ 139,99; AI 49,99 | Yok |
| PDFgear | + (PDF ile sohbet) | + (sürüm geçmişi) | ? | ? | iCloud | ? | Ücretsiz, listede IAP yok | Yok |
| Nitro | ? | ? | ? | ? | iCloud/Dropbox/Drive/OneNote | Hızlı eylemler ana ekranda | Yıllık 19,99; 14 gün deneme | Yok |
| Nutrient | $ (cihaz içi, Apple Intelligence beta) | ? | + | ? | Document Browser; okuma konumu | ? | 3 ay 6,99 / Yıllık 19,99; 7 gün deneme | Var |
| GoodReader | ? | ? | ? | ? | WebDAV/SMB/FTP/SFTP + 4 bulut | Widget + Kısayollar (v6) | 6,99 + Pro Pack 3,99/ay-24,99/yıl | Yok |
| Genius Scan | ? | ? | ? | ? | Genius Cloud (ayrı abonelik) | Kısayol dışa aktarma, Spotlight | Plus 1,99/11,99; Ultra 4,99-49,99 | Var |
| Scanner Pro | ~ (metni çevir; iOS 26) | + (cihazda) | ? | ? | iCloud + 8 hedef | ? | Plus 3,99-59,99 (SKU karışık) | Çelişkili |
| Adobe Scan | ? | ? | ? | ? | Adobe Document Cloud (otomatik) | ? | Plus 4,99/ay-19,99/yıl; Premium 9,99+ | Var |
| CamScanner | ? | + (tara-çevir) | ? | ? | Bulut + çevrimiçi paylaşım | ? | Premium 4,99-69,99 | Var |
| SwiftScan | + (AI özet) | + | ? | ? | 8 hedef | Widget (ana/kilit/XL), Quick Actions | Plus 59,99/yıl; VIP 34,99/yıl | Var |
| Apple (Preview/Dosyalar/Notlar) | ~ (Apple Intelligence; Türkçe iOS 26.1'den beri) | ? | ? | ? | iCloud | Kısayollar (Make PDF vb., B3) | Ücretsiz | Var |
| Goodnotes | $ (AI Pass) | ? | ? | ? | Goodnotes Cloud, OneDrive yedek | ? | Yıllık 11,99 / Pro 35,99 / v6 tek sefer 28,99 | Var |
| LiquidText | ? | ? | ? | + (sıkıştır-karşılaştır) | $ (eşitleme) | ? | Aylık 10,90 / Yıllık 99,99 | Yok |
| MarginNote 4 | + (AI soru çıkarma, kart üretimi) | + | ? | + (çift belge) | iCloud | ? | PRO süresiz 12,99; MAX 12,99-51,99 | Yok |

### 3.5 Cihaz içi mi sunucuda mı (kanıt düzeyiyle)

| Uygulama | Kanıt | Sonuç |
|---|---|---|
| Smallpdf | Listede "yüklenen dosyalar 1 saat sonra silinir" (B1) | Sunucu (dönüşümler) |
| iLovePDF | Mobil için belirtilmemiş; blog "belgeler 2 saat sonra silinir" (2020, B3) | Büyük olasılıkla sunucu; doğrulanamadı |
| Adobe Scan | Taramalar Adobe Document Cloud'a otomatik kaydedilir (B1) | Bulut bağlı |
| Acrobat | Belirtilmemiş; Adobe bulutu ve AI Assistant | Karışık; doğrulanamadı |
| PDF Expert | Çeviri "çevrimdışı uygulama içinde"; Copilot yeri belirtilmemiş | Karışık |
| Genius Scan | "Belge işleme cihazda" (B1); OCR yeri belirtilmemiş | Cihaz içi (OCR hariç belirsiz) |
| SwiftScan | Geliştirici: "belge etkinliği cihazda veya seçtiğiniz bulutta"; AI yeri belirtilmemiş | Çoğunlukla cihaz; AI belirsiz |
| Scanner Pro | Çevirmen "cihazda"; OCR yeri belirtilmemiş | Karışık |
| Nutrient | AI Assistant "tamamen cihazınızda" (Apple Intelligence) | Cihaz içi AI |
| MarginNote | Apple Intelligence ile cihazda veya bulut LLM seçeneği | Seçmeli |
| UPDF, PDFelement, Foxit, PDFgear | AI/OCR/dönüşüm yeri belirtilmemiş; UPDF sohbeti DeepSeek-R1 | Doğrulanamadı (AI için sunucu varsayımı, kanıtsız) |
| PDF Love | "Belgeleriniz cihazınızda kalır" (iddia); iCloud eşitleme | Cihaz içi iddiası; Word→PDF/OCR yeri doğrulanamadı |


---

## 4. Temel set, ayırt edici özellikler ve boşluklar

### 4.1 "Her rakipte olan" temel set (genel amaçlı editörlerde yaygın; tarayıcılar kısmen)
- Görüntüleme: yakınlaştırma, sayfaya git, tam metin arama, koyu/sepya okuma modu (PDF Expert, Xodo, GoodReader, Nitro, UPDF, PDFgear).
- Açıklama: vurgu, alt çizgi, üstü çizili, serbest çizim, metin kutusu, şekil, yapışkan not (PDF Expert, Xodo, UPDF, PDFgear, Foxit, Nutrient, iLovePDF, PDF Love, Apple Preview).
- Form doldur + kayıtlı el imzası (çizme/görsel/klavye): Acrobat, PDF Expert, iLovePDF, Xodo, UPDF, PDFgear, Foxit, Nitro, Nutrient, Scanner Pro, Preview, PDF Love (form yok, imza var).
- Sayfa işlemleri: sırala, sil, döndür, sayfa ekle; birleştir; böl/çıkar. Çoğu zaman ücretli katmanda.
- Sıkıştırma ve parola koruma (ekle/kaldır).
- Görsel→PDF ve kamerayla tarama (otomatik kenar algılama); dosya yöneticisi (klasör, yeniden adlandır, taşı, paylaş); bulut (iCloud + Drive/Dropbox/OneDrive).
- Paylaşma: AirDrop/e-posta/Dosyalar.

### 4.2 Ayırt edici / premium özellikler (kimde, kanıt)
- Mevcut metni yerinde düzenleme: PDF Expert $, Acrobat $, Foxit $, Documents, PDFelement, UPDF, Nitro; PDFgear'da (sürüm geçmişine göre) ücretsiz.
- PDF→Word/Excel/PPT: iLovePDF, Smallpdf, Acrobat $, PDF Expert $, PDFelement, UPDF, Xodo $, Foxit $, Documents, Scanner Pro, Adobe Scan (dışa aktarım). Büyük olasılıkla sunucuda (Smallpdf için beyan var).
- Çok dilli OCR: UPDF (38 dil), Smallpdf, Genius Scan $ (SDK ~90 dil, `tr` dâhil), Adobe Scan (5→100 sayfa $), CamScanner, Scanner Pro (25+ dil, Türkçe adıyla).
- Gerçek karartma: PDF Expert $, Foxit $, Xodo $, Nutrient $, Nitro, iLovePDF, SwiftScan (metin), PDF Love ("bulanıklaştır ve karart"). UPDF "masaüstü" diyor. Kalıcı silme olup olmadığı çoğunda doğrulanamadı.
- AI: PDF Expert Copilot $, Acrobat AI Assistant $, PDFelement (60+ dil çeviri, zihin haritası), UPDF (AI yer imi, anlamsal arama, yeniden yazma), Foxit (beceriler/ajan, grafik üretimi), Documents Smart Insights (önyargı tespiti), SwiftScan (AI özet/çeviri/AI dosya adı), Goodnotes AI Pass, MarginNote (soru çıkarma, flashcard).
- Cihaz içi AI: Nutrient (Apple Intelligence, beta), Scanner Pro Çevirmen, MarginNote (isteğe bağlı).
- Kurumsal/gelişmiş: XFA, mevcut dijital sertifikayla imza, Microsoft Information Protection, Intune (Foxit); AES-256 (GoodReader Pro Pack); Security Space (UPDF).
- Okuma deneyimi: Liquid Mode ve CarPlay'de PDF dinleme (Acrobat); yeniden akış (Foxit, GoodReader, PDFelement); sunum modu/harici ekran (PDF Expert, Nutrient $).
- Ölçüm: mesafe/çevre/alan (PDFelement), ölçek/çokgen/redline (PDF Expert), Measure Mode (Scanner Pro).
- Sesli not: PDF Expert, Nutrient (ses yorumu).
- El yazısı notu metne çevirme: PDFelement 6.1.21, Foxit $, Adobe Scan Digitize (beta), PDF Expert 7.26.3 (el yazısı tanıma iyileştirmesi), Goodnotes.
- Yapılandırılmış veri çıkarma: tablo/form çıkarma (Nitro, Nitro hesabıyla).
- Yeni belge oluşturma: kareli/çizgili/noktalı/milimetrik kâğıt (UPDF), şablonlar (PDFelement, Xodo).
- Tarama sanatı: sihirli silgi ve "Digitize" (Adobe Scan), kimlik/pasaport ve Mega Scan (CamScanner), eski fotoğraf restorasyonu (Scanner Pro), akıllı adlandırma (Genius Scan $, Scanner Pro Auto Name, SwiftScan AI adlar), tüm sayfaları aynı anda kırpma (SwiftScan), eğrilik düzeltme anahtarı (Genius Scan).
- Bilgi çalışması: alıntı/ink link/sıkıştırma ile karşılaştırma (LiquidText); Card Axis, FSRS, AI soru çıkarma (MarginNote).
- Dosya erişimi: SMB/SFTP/FTP/WebDAV (GoodReader, UPDF, SwiftScan WebDAV/FTP), ZIP/RAR (Documents, UPDF), ses/video yazıya dökme (Documents).
- Otomasyon: Kısayollar (iLovePDF, Genius Scan dışa aktarma, GoodReader), widget (GoodReader, SwiftScan), Spotlight (Genius Scan), çoklu pencere (iLovePDF 4.2.0, Nitro iPad).

### 4.3 Kimsede iyi yapılmamış veya hiç beyan edilmemiş boşluklar
Etiketler: [kanıt] doğrudan bir kaynak gösteriyor; [çıkarım] listelerde yokluktan çıkarıldı, kesin değil.

1. Tam yerel (sunucusuz) PDF→Word/Excel/PPT ve "hiçbir şey yüklenmez" garantisi. Smallpdf açıkça sunucu (1 saat silme) [kanıt]; diğerlerinin hiçbiri dönüşümlerin cihazda çalıştığını beyan etmiyor [çıkarım].
2. Türkçe: Türkçe arayüz yalnız Acrobat, Adobe Scan, iLovePDF, Smallpdf, Nutrient, Genius Scan, CamScanner, SwiftScan ve Goodnotes'ta var; PDF Expert, Documents, PDFelement, UPDF, Xodo, Foxit, PDFgear, Nitro, GoodReader, LiquidText, MarginNote ve PDF Love'da YOK [kanıt, B1 dil listeleri]. Türkçe OCR'ı adıyla beyan eden yalnız Scanner Pro (açıklama metni; metaveri çelişkili) [kanıt]; Genius Scan SDK dokümanı `tr` listeliyor [kanıt]. Türkçe diakritik (ğ, ş, ı, İ, ö, ü, ç) başarımı hiçbir kaynakta ölçülmemiş [çıkarım].
3. Telefonda toplu işlem: UPDF toplu işlemi açıkça masaüstüne bırakıyor [kanıt]; diğerlerinin listelerinde "N dosyaya aynı filigran/sıkıştırma/sayfa numarası" yok [çıkarım]. Apple Kısayollar tek genel yol (B3).
4. Gerçek karartma + meta veri temizliğinin tek akışta olması: Nutrient'in rehberi karartmanın başlık/yazar meta verisini silmediğini söylüyor [kanıt, B3]; ikisini birlikte yapan tek örnek niş "Redact Kit" (id6769065437; karartmada sayfayı görüntüye düzleştiriyor) [kanıt, B3]. Ana akım uygulamalar ikisini birlikte beyan etmiyor [çıkarım]. PDF Love'un "bulanıklaştır/karart"ının kalıcı olup olmadığı doğrulanamadı.
5. Belge karşılaştırma (iki PDF sürümü): ana akım iOS uygulamalarında beyan bulunamadı (Acrobat/UPDF/PDFelement iOS için doğrulanamadı); yalnız niş "Autopilot3" (iPhone, çevrimdışı) bulundu; LiquidText ve MarginNote görsel yan yana sunuyor [kanıt/çıkarım].
6. Telefonda doldurulabilir FORM OLUŞTURMA: yalnız Xodo (abonelik) [kanıt]; PDF Expert alan üretmez (B3); ONLYOFFICE iOS rehberi "yalnız masaüstü/çevrimiçi" diyor (B3).
7. Ders kitabı/PDF'ten SORU veya çalışma kâğıdı ÜRETME: MarginNote sınav kâğıdını soru-cevap kartına BÖLÜYOR (üretmiyor) [kanıt]; Goodnotes Classroom öğrenci cevabını notluyor (satıcı iddiası) [kanıt]; Türkçe soru üreten bir PDF uygulaması bulunamadı [çıkarım].
8. Uçtan uca sınav kâğıdı hattı (sınıf yığınını tara → öğrenciye göre böl/adlandır → puanla → öğrenciye ayrı PDF): hiçbir uygulama bütün hattı beyan etmiyor; parçalar farklı uygulamalara dağılmış (Adobe Scan toplu + Genius/Scanner Pro adlandırma + iLovePDF bölme + işaretleme uygulaması) [çıkarım]. iLovePDF bölmeyi yalnız "dosya boyutuna göre" duyurmuş [kanıt]; "her N sayfada bir böl" hiçbir listede açıkça yok [çıkarım].
9. Cihaz içi AI: yalnız Nutrient (beta, iOS 26 + Apple Intelligence gerekli) [kanıt]. Apple Intelligence Türkçe desteği iOS 26.1 ile eklendi (9to5Mac, B3) [kanıt]; Foundation Models çerçevesinin Türkçe desteği ayrı doğrulanamadı.
10. Reklam izleme etiketi olmayan, abonelik duvarı olmayan tam özellikli editör: PDFgear en yakını (ücretsiz, yalnız analitik etiketi) ama Türkçe yok, OCR belirsiz, ücretsiz kalma sözü kesin değil [kanıt]. Xodo, CamScanner, Adobe Scan, Foxit, PDFelement, SwiftScan "sizi izlemek için" etiketi taşıyor [kanıt, B1].
11. iPhone Duo (katlanabilir, 23 Ekim 2026'da satışta; iPhone'a ilk Apple Pencil desteği; iOS 27): PDF Expert, Documents, Scanner Pro, PDFelement, SwiftScan, Nutrient sürüm notlarında Duo optimizasyonu duyurdu; iLovePDF 4.2.0 çoklu pencere ekledi [kanıt]. İç ekranda iki sütunlu sayfa düzenleyici/yan yana belge gibi somut Duo desenleri ayrıntılı doğrulanamadı.

---

## 5. Öğretmen kullanımı için değerli özellikler

(Mehmet Bey bir biyoloji öğretmeni; aşağıdakiler rakip kanıtına dayanan değerlendirme, karar önerisidir.)

### 5.1 Sınav kâğıdı (tarama ve düzenleme)
| İhtiyaç | En iyi kanıtlı örnek |
|---|---|
| Çok sayfa tarama, otomatik yakalama | Apple Preview (otomatik yakalama, çoklu sayfa), Adobe Scan (toplu/High-speed), Genius Scan (toplu), SwiftScan (tüm sayfaları aynı anda kırp) |
| Fotokopi gibi temiz görüntü | Genius Scan filtre şeridi (None/Auto/B&W/Color/Photo) + eğrilik düzeltme + gölge/leke giderme; Adobe Scan sihirli silgi |
| Öğrenci numarası/QR ile adlandırma | QR okuma: CamScanner, Scanner Pro, SwiftScan; otomatik adlandırma: Scanner Pro Auto Name, Genius Scan akıllı adlandırma $, SwiftScan AI dosya adı |
| Türkçe metin OCR | Scanner Pro (Türkçe adıyla), Genius Scan SDK (`tr`), Apple Vision (macOS 27.2'de `tr-TR` ölçüldü); el yazısı Türkçe: hiçbir kaynakta doğrulanmadı |
| Sayfa yığınını öğrenciye böl | Gerçek boşluk (Bölüm 4.3 madde 8) |
| Kâğıt üstüne puan/işaret | Açıklama araçları + damga (PDF Expert, UPDF, PDFelement özel damga, Foxit) |

### 5.2 Çalışma kâğıdı hazırlama
- Boş kareli/çizgili/milimetrik sayfadan başlama (UPDF); şablon (PDFelement, Xodo).
- Metin kutusu, şekil (ok/daire/dikdörtgen), görsel ekleme (hücre şeması, kalıtım çaprazı yerleştirme); PDF Expert, PDFgear, UPDF, Preview.
- Ders kitabından şekil kırpma: Preview sayfa kırpma (mavi tutamaçlar), Xodo kırpma; görsel çıkarma: iLovePDF, UPDF; PDF→JPG.
- Filigran ("ÖRNEK", "CEVAP ANAHTARI"), sayfa numarası, üst/alt bilgi (okul, sınav adı): PDF Love, iLovePDF, UPDF/PDFelement (filigran).
- Parola/izin: cevap anahtarı (UPDF, Nutrient, Foxit, Preview Lock, PDF Love).
- Doldurulabilir form: oluşturma yalnız Xodo $; doldurma yaygın (öğrenci formu doldurup geri gönderir).
- Flatten (Xodo, Nutrient): işaretli kopyayı düzenlenemez yapma.

### 5.3 Öğrenci ödevini işaretleme
- Hızlı işaret araç çubuğu: vurgu, kalem, metin, damga ("Doğru", "Yanlış", puan), yapışkan not (PDF Expert, UPDF, Foxit, PDFelement).
- Sesli geri bildirim: PDF Expert (sesli not), Nutrient (ses yorumu); Kami (web) ses/video yorumu (B3).
- Açıklama özetini dışa aktarma: GoodReader "annotation summaries".
- Sınıf düzeyinde notlama: Goodnotes Classroom ("soruya göre işaretle", AI ile model cevap karşılaştırma; satıcı iddiası, ayrı uygulama) ve Kami (Class View; LMS entegrasyonu gerekir). Ana akım PDF uygulamalarında karşılığı bulunamadı.
- Cep telefonunda parmakla işaretleme: Apple Pencil yok; Duo cihazında Pencil var (Apple yardım sayfası).

### 5.4 Toplu işlem
- Birleştir (sınıf yığını), böl, filigran, sıkıştır (e-postaya sığdırma), sayfa numarası: tek tek değil dosya grubuna uygulanması hiçbir mobil listede açık değil. Kısayollar (Make PDF, boyut optimize) ile elle zincir kurulabilir (B3).
- Düzen: klasör + arama (PDF Love, UPDF çoklu seçim, Documents renk etiketleri), Spotlight (Genius Scan).

### 5.5 Önerilen öncelik (öneri, karar kullanıcıya ait)
- P0 (PDF Love paritesi, tüm rakiplerde temel): tarama, imza, açıklama, birleştir/böl/sıkıştır/döndür/sırala, parola, filigran/sayfa no, görsel↔PDF, klasör+arama, Face ID kilidi, iCloud.
- P1 (öğretmen değeri, ücretsiz rakipte bile az bulunan): Türkçe arayüz ve Türkçe OCR (cihaz içi), toplu işlem, hızlı damga/yorum çubuğu, sınav kâğıdı toplu tarama + adlandırma + öğrenciye böl, düzleştirme, kareli/çizgili boş sayfa, şekil kırpma.
- P2 (ayırt edici): mevcut metni düzenleme (yerel), gerçek karartma + meta veri temizleme, cihaz içi özet/soru üretme (Apple Intelligence; Türkçe iOS 26.1+), belge karşılaştırma, sesli not, Kısayollar/widget/paylaşım uzantısı.


---

## 6. UX desenleri (kanıtlı)

1. **Alt sekme çubuğu + ana ekran.** iLovePDF: Home / Files / Tools / Scanner / Settings. Home'da "Recent files" yatay kaydırma, "Favorites", "Recent Tools" (App Store ekran görüntüsü). PDF Love: Dosyalar ekranında "Recents | Browse" alt sekmeleri.
2. **Araç ızgarası.** iLovePDF Tools sekmesi: 3 sütunlu kutucuk ızgarası, her kutucuk simge + iki satırlık ad (Image to PDF, Word to PDF, Compress, Merge, PDF to Word, Split, Text Recognition (OCR), Edit PDF, Organize PDF, Unlock PDF...). PDF Expert'in tanıtım ekranı iki sütunlu ızgara: Annotate, Edit PDF, Convert PDF, PDF Copilot, Fill & Sign, Translate PDF, Manage Pages, Reduce File Size. PDF Love'un ana ekran ızgarası mağaza görsellerinde görünmüyor (doğrulanamadı).
3. **Hızlı eylem şeridi.** Nitro 26.2 yeniden tasarım: Open, Scan, Encrypt, Combine, Table Extract, Form Extract + son dosyalar + arama + "New" düğmesi (sürüm notu).
4. **Araç zinciri (çıktıyı başka araca verme).** Belgelenmiş örnekler az: Apple Preview'da sayfa küçük resmine uzun basınca "Insert from File / Scan Pages"; Adobe Scan→Acrobat devri; Genius Scan'in otomatik dışa aktarımı; iLovePDF "Recent Tools". İşlem sonunda "Sıradaki: sıkıştır / parola / paylaş" önerme deseni rakip listelerinde belgelenmemiş (tasarım fırsatı, doğrulanmadı).
5. **Sayfa düzenleyici (Apple Preview iPhone, resmî).** Küçük resim kenar çubuğu düğmeyle açılır; küçük resme uzun basınca menü: Insert Blank Page, Insert from File, Scan Pages, Delete Page; sayfa döndürme (Sola/Sağa); küçük resmi uzun basıp yukarı/aşağı sürükleyerek taşıma; kırpmada mavi tutamaçlar ve Crop düğmesi; "Undo" menüsü. Xodo da küçük resim görünümünde sayfa düzenliyor; iLovePDF'te ayrı "Organize PDF" kutucuğu.
6. **Mod seçici.** PDF Expert: üstte "Annotate ⌄" açılır seçici + yatay araç çubuğu (seçim, vurgu, alt çizgi, üstü çizili, metin, işaretleyici, silgi). Nitro: üstte iki düğmeli segment (okuma gözlüğü / düzenleme kalemi). Apple Markup: araç çubuğunu gizle/göster, çizgi cetveli, kement (lasso), piksel silgi / nesne silgi, kalınlık-opaklık-renk (Grid/Spectrum/Sliders).
7. **Bağlamsal seçim menüsü.** Nitro: metin seçilince "Definition | Correct Text".
8. **Tarama sonrası düzenleme sayfası (Genius Scan).** Alt sayfada sekmeler: Image / Text / Smart data; Recrop, Sola/Sağa döndür; filtre şeridi (None, Auto, B&W, Color, Photo); "Curvature correction" anahtarı; "Format: Fit".
9. **Kamera.** Köşe tutamaçları (PDF Love ve Apple), deklanşör, flaş, son çekim küçük resmi, "Auto/Manual" geçişi (Apple), tarama sonrası küçük resimden kırp/döndür/renk.
10. **İmza.** Birden çok kayıtlı imza (ör. baş harfler) (Apple); sayfaya yerleştirilince döndürülebilir/boyutlandırılabilir kutu, renk paleti, geri al/yinele (PDF Love).
11. **Özelleştirilebilir araç çubuğu.** PDF Expert, PDFelement; Xodo'da abonelikle.
12. **Ücretli özellik işaretleme.** Genius Scan ve LiquidText listede premium maddeleri işaretliyor ("+"/"*"); ücretsiz çekirdek (Genius Scan: tarama, birleştir/böl, etiket, arama).
13. **Çoklu pencere / geniş ekran.** iLovePDF 4.2.0 çoklu PDF penceresi; GoodReader çoklu dosya; Duo cihazında Split View ve aynı uygulamanın iki penceresi (haber kaynakları).
14. **Dosya gezgini ağırlıklı uygulama.** Documents (klasör, renk etiketi, sekme), GoodReader (masaüstü benzeri, renkli sekmeler), UPDF (çoklu seçim, çöp kutusu, geri alma). "Önce dosya yöneticisi" yaklaşımı ile "önce araç ızgarası" yaklaşımı iki ayrı okul.

---

## 7. Kaçınılacak şikâyetler (ne yapılmamalı)

Kanıt sınıfı: B1 = App Store listesi, B3 = ikincil kaynak/forum/özet (örneklem küçük ve çoğu eski).

| # | Şikâyet / kötü desen | Kanıt (sınıf) | Tasarım kuralı |
|---|---|---|---|
| 1 | İptale rağmen ücretlendirme, iade için mağazaya yönlendirme, premium alınmasına rağmen "ücretsiz kullanıcı" görünmesi, Restore Purchases başarısızlığı | Adobe Community başlıkları, 2021-Ekim 2025 (B3) | Kişisel uygulamada abonelik/IAP hiç olmasın; olursa tek durum kaynağı StoreKit |
| 2 | Düzenlemeyi bitirtip İNDİRME anında ödeme duvarı; 1,50 USD deneme sonra 46-75-334 USD faturalar | pdf.net/files-editor Trustpilot ve forum, 2026 (B3; mobil uygulama değil, web servisleri) | Hiçbir akışta "bitirdikten sonra duvar" olmasın |
| 3 | Haftalık abonelik | PDF Love 4,99; PDFelement 6,99-9,99; Acrobat 9,99; CamScanner 9,99 USD (B1) | Gerek yok (ticari değil) |
| 4 | SKU/fiyat karmaşası | Smallpdf aylık 7,99-14,99, yıllık 49,99-119,99; PDF Expert "Trial/No Trial/New/Existing" SKU'ları; UPDF 9 SKU + AI ayrı; PDF Expert yıllık fiyat 30-60 EUR arası oynamış (B1, B3) | Tek ve sade durum |
| 5 | Ücretsiz katmanda günlük görev/boyut limiti, deneme sınırı | iLovePDF günlük görev; Smallpdf günlük görev; UPDF denemede 5 sayfa tarama, 10 öge Security Space (B1, B3) | Hiçbir özellik sayaçla kısıtlanmasın |
| 6 | Dosyaların harici sunucuya yüklenmesi (gizlilik kaygısı) | Smallpdf 1 saat saklama; iLovePDF blogu 2 saat; Adobe Scan otomatik Document Cloud; Kimola özeti yükleme kaygısı (B1, B3) | Her şey cihazda; ağ kullanan özellik açıkça etiketli ve isteğe bağlı |
| 7 | PDF→Word düzen kayması, yavaşlık | iLovePDF GetApp yorumu (B3) | Yerel dönüşüm yapılacaksa kalite testi şart |
| 8 | Sezgisel olmayan arayüz, OCR sorunları, performans, çökme | UPDF G2 özeti (OCR 9, sezgisel değil 8, performans 7); Nitro (iPad'de doldurulabilir PDF çökmesi, basit işte sezgisel değil) (B3) | Büyük/taranmış PDF'te performans ve bellek testi |
| 9 | Türkçe arayüz yok | PDF Expert, Documents, PDFelement, UPDF, Xodo, Foxit, PDFgear, Nitro, GoodReader, LiquidText, MarginNote, PDF Love (B1) | Türkçe arayüz, Türkçe hata iletileri |
| 10 | İzleme/reklam etiketleri | "Sizi izlemek için": Acrobat, Smallpdf, Xodo, Foxit, PDFelement, CamScanner, Adobe Scan, Scanner Pro, SwiftScan, Goodnotes; SwiftScan yaş 18+ (reklam); Documents yaş 16+ ve VPN satışı (B1) | Sıfır izleme, SDK'sız |
| 11 | Şişkin boyut | Acrobat 579 MB, SwiftScan 522 MB, Documents 430 MB, Adobe Scan 420 MB (B1) | Sistem çerçeveleri ile küçük kalma (PDF Love 5,9 MB) |
| 12 | Yavaş destek, kaldırılan/kısıtlanan özellik | PDF Expert (Kimola önizlemesi, bayi sayfası), PDFelement yorumu (B3, düşük ağırlık) | Kişisel proje: kapsam kayması ve gerileme için test paketi |
| 13 | Uygulamanın kapatılması | Microsoft Lens 9 Şubat 2026 mağazadan kalktı, 9 Mart 2026 tarama bitti; OneDrive yerel kaydetmiyor (B2) | Dosyalar standart PDF olarak Dosyalar'da kalsın; kilitli biçim kullanma |
| 14 | Tutarsız/aşırı pazarlama | PDF Love: "#1" ve 5 yıldız rozeti puansızken; "10+" ile "20+" araç; Acrobat açıklamasında "iOS 16", mağaza gereksinimi iOS 18.3 (B1) | Kişisel uygulamada gereksiz; yine de yerleşik "Hakkında" sayfasında doğru yetenek listesi tut |
| 15 | Güncellenmeyen uygulama | PDF Love son sürüm 24 Mart 2026 (7 ay) (B1) | Kendi uygulamanda iOS sürümlerine uyum testi planla |
| 16 | Aynı marka altında karışık ürünler | SwiftScan: ücretsiz "AI Document Scanner" ile ayrı 199,99 USD "SwiftScan Pro" listesi; UPDF AI ayrı satış (B1, B3) | Tek uygulama, tek yetenek listesi |

---

## 8. Kaynak URL listesi ve ek notlar

### 8.1 Birincil: App Store sayfaları ve iTunes lookup (B1, 27 Ekim 2026'da okundu)
- PDF Love: https://apps.apple.com/us/app/id6758917744 ; https://itunes.apple.com/lookup?id=6758917744&country=us ; geliştirici: https://apps.apple.com/us/developer/sasikumar-chhotelal-das/id1836448885
- iLovePDF: https://apps.apple.com/us/app/id1207332399
- Smallpdf: https://apps.apple.com/us/app/id1485259500
- Acrobat Reader: https://apps.apple.com/us/app/id469337564 ; TR: https://apps.apple.com/tr/app/id469337564
- PDF Expert: https://apps.apple.com/us/app/id743974925
- Documents: https://apps.apple.com/us/app/id364901807
- PDFelement: https://apps.apple.com/us/app/id1516765045
- UPDF: https://apps.apple.com/us/app/id1595826623
- Xodo: https://apps.apple.com/us/app/id805075929
- Foxit PDF Editor: https://apps.apple.com/us/app/id507040546
- PDFgear: https://apps.apple.com/us/app/id6465897558
- Nitro PDF Pro: https://apps.apple.com/us/app/id1608616539
- Nutrient PDF Viewer: https://apps.apple.com/us/app/id1120099014
- GoodReader: https://apps.apple.com/us/app/id777310222
- Genius Scan: https://apps.apple.com/us/app/id377672876
- Scanner Pro: https://apps.apple.com/us/app/id333710667
- Adobe Scan: https://apps.apple.com/us/app/id1199564834
- CamScanner: https://apps.apple.com/us/app/id388627783
- SwiftScan (Maple Media): https://apps.apple.com/us/app/id834854351
- Goodnotes: https://apps.apple.com/us/app/id1444383602
- LiquidText: https://apps.apple.com/us/app/id922765270
- MarginNote 4: https://apps.apple.com/us/app/id1531657269
- Toplu lookup (puan/sürüm/dil): https://itunes.apple.com/lookup?id=469337564,743974925,364901807,1199564834,975925059,388627783,364932006,333710667,1099490957,777310222,1444383602,922765270&country=us
- Mağaza ekran görüntüleri (UX): PDF Love, iLovePDF, PDF Expert, Nitro, Genius Scan sayfalarının `screenshotUrls` alanı (mzstatic.com).

### 8.2 Resmî yardım/duyuru ve ikincil kaynaklar
- Apple Preview'a giriş (iOS 27 kılavuzu): https://support.apple.com/guide/iphone/iph7239ea3b5/ios
- Preview'da tarama: https://support.apple.com/guide/iphone/scan-text-and-documents-iphd81075862/ios
- Preview sayfa ekle/sil/döndür/taşı/kırp: https://support.apple.com/guide/iphone/add-delete-rotate-move-or-crop-pdf-pages-iphbf4977cff/27/ios/27
- Preview kaydet/yeniden adlandır/taşı: https://support.apple.com/guide/iphone/save-rename-or-move-pdfs-and-images-iph0bd249ff4/27/ios/27
- Markup (çizim/silgi/cetvel): https://support.apple.com/guide/iphone/write-and-draw-in-documents-iph893c6f8bf/ios
- Notlar/Dosyalar'da tarama: https://support.apple.com/en-us/108963
- Form doldurma ve imza: https://support.apple.com/guide/iphone/fill-forms-sign-documents-create-signatures-iph1d3607e5c/ios
- Microsoft Lens emeklilik: https://support.microsoft.com/en-us/lens/ ; haber özetleri: https://www.windowscentral.com/software-apps/microsoft-just-killed-this-5-star-app-say-goodbye-to-a-windows-phone-legend/ ; https://www.neowin.net/news/microsoft-killing-its-free-highly-rated-document-scanner-app-soon-this-year
- iLovePDF iPhone blogu (2020): https://www.ilovepdf.com/blog/iphone-app-version
- PDF Expert iOS sayfası: https://pdfexpert.com/ios ; PDF Expert abonelik geçişi (2023): https://thesweetsetup.com/pdf-expert-releases-version-7-switches-to-subscription-model/ ; https://www.macstories.net/news/pdf-expert-moves-to-annual-subscription-business-model/ ; fiyat oynaması: https://www.iphone-ticker.de/pdf-expert-7-zukuenftig-nur-noch-als-abo-version-144195/
- PDFgear iOS: https://www.pdfgear.com/pdfgear-for-ios ; ücretlendirme tartışması: https://9to5mac.com/2023/12/04/get-pdfgear-iphone-ipad-mac-free/ ; karşılaştırma: https://www.audeus.com/product-reviews/pdf-expert-vs-pdfgear
- iPhone Preview uygulaması (iOS 26) haberleri: https://www.tomsguide.com/phones/iphones/ios-26-brings-a-new-app-to-your-iphone-heres-how-to-try-it ; https://macmost.com/10-tips-for-using-the-preview-app-on-your-iphone.html ; https://iphonelife.com/content/how-to-use-preview-app-iphone-ipad-new-ios-26
- iPhone Duo: https://tidbits.com/2026/09/11/apple-unfolds-the-iphone-duo/ ; https://www.nippon.com/en/news/yjj2026102300195/
- Apple Intelligence Türkçe (iOS 26.1): https://9to5mac.com/2025/11/11/ios-26-1-brings-apple-intelligence-to-these-eight-new-languages/ ; Foundation Models dil kısıtı forumu: https://developer.apple.com/forums/thread/805378
- Genius Scan SDK OCR dilleri: https://geniusscansdk.com/docs/v5/supported-ocr-languages
- Karartma/meta veri: https://nutrient.io/guides/ios/redaction/introduction-to-redaction ; https://www.adobe.com/acrobat/hub/how-to/how-to-redact-pdf-iphone.html ; Redact Kit: https://mwm.ai/apps/redact-kit-clean-privacy/6769065437
- Karşılaştırma uygulaması (niş): https://apps.apple.com/qa/app/autopilot3/id6503720005
- Şikâyet kaynakları (B3): https://community.adobe.com/t5/acrobat-reader-mobile-discussions/cancel-subscription/td-p/14018403 ; https://community.adobe.com/t5/acrobat-reader-mobile-discussions/problem/m-p/12622955 ; https://www.trustpilot.com/review/pdf.net?page=9 ; https://singletrackworld.com/forum/off-topic/psa-pdf-scam-files-editor-com/ ; https://kimola.com/reports/explore-in-depth-customer-insights-on-pdf-expert-app-store-us-148340 ; https://www.getapp.de/software/125451/ilovepdf ; https://www.capterra.com.de/software/173963/ilovepdf ; https://g2.com/products/updf/reviews?page=10
- Öğretmen araçları (satıcı sayfaları, B3): https://apps.apple.com/us/app/-/id6499033382 (Goodnotes Classroom; doğrudan açılamadı, arama özeti) ; https://www.avid.org/digital-tools/Kami ; https://teachthought.com/technology/best-pdf-tools-for-teachers
- Kısayollar PDF eylemleri (B3): https://macscripter.net/t/pdf-shortcut-examples/75136 ; https://maketecheasier.com/combine-pdf-files-ios/

### 8.3 Yerel ölçüm (bu Mac, 27 Ekim 2026)
- macOS 27.2'de `VNRecognizeTextRequest.supportedRecognitionLanguages()` çalıştırıldı. Revision 3 + accurate kipinde 33 dil döndü ve `tr-TR` listede VAR (en-US, fr-FR, it-IT, de-DE, es-ES, pt-BR, zh-Hans/Hant, yue, ko-KR, ja-JP, ru-RU, uk-UA, th-TH, vi-VT, ar-SA, tr-TR, id-ID, cs-CZ, da-DK, nl-NL, no, ms-MY, pl-PL, ro-RO, sv-SE, fi-FI, hi-IN, mr-IN). Revision 2'de ve "fast" kipinde Türkçe YOK (fast: yalnız en/fr/it/de/es/pt). Bu, bir arama sonucunun "Türkçe yok" iddiasıyla ÇELİŞİR; o kaynak eski OS sürümlerini yansıtıyor. iOS 27 cihazında aynı listenin geçerli olduğu varsayımdır, cihazda doğrulanmadı. Ölçüm kodu: scratchpad/swifttest/langs.swift.

### 8.4 Doğrulanamayanlar ("Aranamayan sorular")
- indielabs.app (PDF Love sitesi, gizlilik, şartlar): SSL hatası, açılamadı. PDF Love'un hangi özelliğin Pro olduğu, OCR dilleri, Word→PDF'in yeri, ZIP işlevi, karartmanın kalıcılığı.
- Reddit içeriği: arama aracı alan adını engelliyor.
- Tek tek App Store yorumları: RSS ucu boş döndü.
- Ana ekran "araç ızgarası" PDF Love'da var mı: mağaza görselleri göstermiyor.
- Kullanıcı şikâyetlerinin güncel ağırlığı: kaynakların çoğu 2021-2025 ve küçük örneklem.
- Acrobat mobilde karartma ve meta veri temizleme; PDF Expert/Foxit meta veri temizleme; Acrobat/UPDF/PDFelement iOS'ta belge karşılaştırma; UPDF dijital imzasının sertifika tabanlı olup olmadığı; Scanner Pro'da Türkçe dil desteği (açıklama ile metaveri çelişkili); UPDF OCR listesinde Türkçe; Foundation Models çerçevesinin Türkçe desteği.
- PDF Expert güncel yıllık fiyatı (App Store listesi 49,99; bir bayi 79,99 diyor).
- Goodnotes Classroom ve Kami'nin iPhone'daki durumu ve fiyatı.
- PDFgear'ın ücretsiz kalma sürdürülebilirliği.
