# Mehmet Asistan 0.10.0 build17 — indirme yöneticisi / Kepçe

- Kullanıcının son talimatı: indirmeler yalnız iPhone üzerinde; sunucu kullanılmaz. İlk hazırlanan sunucu medya kodu kaldırıldı, mevcut server.py SHA256 f9bcc7e1c09d44ccd52139190bccef901a3fa1b6c0c3e1f9b01b2a165ca60d35 değişmedi. Sunucuya eklenen geçici media-venv kaldırıldı; medya endpoint'i dağıtılmadı.
- Asistan: arka plan URLSession doğrudan HTTPS dosyası, ilerleme, iptal, tekrar, yerel kalıcı liste, Quick Look, paylaşma. 10 etkin iş / 1 GB dosya sınırı. Duraklat-devam veya IDM parçalı indirme yok.
- Kepçe: mevcut kepce://indir URL sözleşmesi; video/ses seçimi korunur. Ayrı uygulamadaki yerel motor/kuyruk/kütüphane, Asistan'a gömülü motor değil. Aktarım başarıyla tamamlanma anlamına gelmez; Asistan listesi bunu açık söyler. Kepçe yoksa WebKit doğrudan medya bulucu.
- Derleme: simulator ve fiziksel iPhone başarılı. 121 Swift test: 111 geçti, 10 mevcut donanım/canlı koşullu atlandı. Yeni indirme UI testi geçti, ekran görüntüsü incelendi. Son HTTPS navigation delegate ve doğrudan-medya yönlendirme düzeltmesinden sonra 4 indirme testi tekrar geçti; final cihaz derlemesi ve kurulum başarılı.
- Gerçek iPhone: W3C örnek PDF 13,264 byte indirildi, %PDF başlığı doğrulandı. Test PDF'si kayıtla beraber temizlendi. Kepçe'ye aktarım doğrulandı.
- Kepçe canlı testleri: YouTube jNQXAC9IVRw video ve ses başarılı. Kütüphanede Videolar/Me at the zoo.mp4 (788,333 byte, 240p H.264,19sn) ve Sesler/Me at the zoo.m4a (356,391 byte,AAC,19sn). Diğer BaW_jenozKc örneği kullanılabilir biçim vermedi; evrensel başarı iddiası yok.
- İlk doğrudan samplelib MP4 Kepçe biçim seçicisinde hata verdi; Asistan son kodu doğrudan medya uzantısını yerel dosya yoluna yönlendiriyor. Kepçe motoru değiştirilmedi. Doğrudan dosya aktarımı gerçek PDF ile doğrulandı; son MP4 dalı için ayrı fiziksel aktarım yapılmadı.
- Yeni indirme aracı çağrı şeması kayda ve sistem talimatına eklendi. Gerçek LLM/sesli komuttan bu araca uçtan uca yeni test yapılmadı; araç/arayüz ve yerel aktarım sınandı.
- Ekran paylaşımı / iPhone Mirroring açılmadı. Final normal-launch.log: güncel Asistan normal argümansız başlatıldı.
