# Kâğıt — geliştirici kılavuzu

## Yapı
- `KagitKit/` — arayüzsüz çekirdek (Swift paketi, iOS 27 + macOS 27). Mac'te `cd KagitKit && swift test`.
  - `Temel/`: `Belge` (aç/kaydet/doğrula), `KayitSecenekleri`, `Izinler`, `Isaret` (açıklama /T işaretleri "kagit:puan:5"), `SayfaAraligi`, `TurkceMetin`, `ZipYazici`/`ZipOkuyucu`, `PDFCizim` (Yazici, goruntu, metin, paragraf), `Gecici`, `KagitHata`, `Ilerleme`.
  - `Pdfium/PdfiumBelge`: metin nesneleri, nesne silme, Türkçe metin ekleme (gömülü Noto), düzleştirme, kaydetme. Bütün PDFium çağrıları `PdfiumKilit` altında.
- `Kagit/` — SwiftUI uygulaması (varsayılan MainActor yalıtımı, Swift 6 sıkı eşzamanlılık).
  - `App/`: KagitApp, `Yonlendirici` (sekme, `ac(oge, kip:)`, `aracAc(id:girdiler:)`, `taramaAcik`), `AnaGorunum`, `Tema`.
  - `Kitaplik/`: `Kitaplik` (Belgeler klasörü; `iceAktar`, `ciktiKaydet`, `tasi`, `copeAt`, bilgiler/etiket/yıldız), `DosyalarGorunumu`, `AnaSayfa`, `KucukResim`.
  - `Goruntuleyici/`: `BelgeOturumu` (belge, pdfView, `degistir(ad:yap:geriAl:)` geri alma, `aciklamaEkle`, `dokunusIsleyici`, `veriAl()`, `belgeyiDegistir(_:)`, `sayfalarDegisti()`, `kaydet()`), `PDFGorunumu`, `BelgeEkrani` (kip seçici + `KipCubugu`).
  - `Araclar/`: `Arac`, `AracKatalogu` (+ modül başına uzantı dosyası), `AracSablonu` (girdi listesi → seçenekler → Başlat → kitaplığa kayıt + zincirleme), `SayfaAraligiAlani`, `kaynakSecici`.
  - `Sistem/Gizli`: Keychain (`Gizli.vekilAnahtari`), `Sunucu.kok/mesajlar/pdfStudio`.
- `KagitPaylas/` paylaşım uzantısı → App Group `Gelenler`.

## Kurallar
- Türkçe adlandırma (mevcut koddaki gibi), Türkçe kullanıcı metinleri, Türkçe hata (`KagitHata`).
- Ağır işler `Task.detached` içinde; `PDFDocument` iş parçacıkları arasında paylaşılmaz — URL/`Data` geçir, arka planda yeni belge aç.
- Kayıt her zaman `Belge.kaydet/yaz` (doğrulamalı, atomik) ile.
- iOS 27 PDFKit: açıklamalar pikselleşebilir → dışa aktarımda `aciklamalariGom` seçeneği sun. Sıkıştırma: `aciklamalariGom + gorselleriJPEG + ekranIcinOptimize` birlikte etkili.
- Swift'te `is`, `in`, `default` gibi anahtar sözcükleri parametre adı yapma.
- Yeni dosya eklemek için `xcodegen generate` yeterli (klasör tabanlı). `project.yml`'e yalnız gerekiyorsa dokun.
- Mantığı KagitKit'e koy ve `swift test` ile sına; arayüzü uygulamaya koy.

## Derleme
```
ln -sfn ~/Developer/kagit/KagitKit/Ikili KagitKit/Ikili     # worktree'de PDFium (git dışı)
cp ~/Developer/kagit/Secrets.xcconfig .                     # git dışı
cd KagitKit && swift test && cd ..
~/Developer/.tools/xcodegen/xcodegen/bin/xcodegen generate
xcodebuild -project Kagit.xcodeproj -scheme Kagit -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath ~/Developer/.build/kagit-<modul> build 2>&1 | grep -E "error:|\*\* BUILD"
```
Telefona kurulum yalnız birleşik dalda: `./telefona-kur.sh`.
