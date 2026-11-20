# Kâğıt — durum notu (27 Ekim 2026)

iPhone + iPad için yerel PDF düzenleyici (PDF Love / iLovePDF / PDF Expert benzeri). Bundle: `com.mehmetderin.kagit`, App Group `group.com.mehmetderin.kagit`, takım 838FF89FZ8.

## Kararlar (kullanıcı)
- Ayrı uygulama, iPhone + iPad. İşlemler cihazda yapılır, telefonun yapamadığı Office dönüşümleri isteğe bağlı olarak VPS'e gider.
- Yapay zekâ cihaz içinde çalışır, Claude bulutu yedektir. **iPhone 15 Apple Intelligence'ı desteklemiyor**, bu telefonda fiilen Claude kullanılacak.
- Öğretmen araçlarının dördü de olacak: işaretleme/puan, taranmış yığını bölme, A/B kitapçık ve çalışma kâğıdı, PDF'ten soru üretme.
- Depolama: uygulama kitaplığı (Belgeler klasörü). Dosyalar uygulamasında görünür.

## Bitenler
- `KagitKit` Swift paketi: Belge (güvenli kayıt + doğrulama + iOS 27 kayıt hatası düzeltmesi), SayfaAraligi, TurkceMetin, ZipYazici, PDFCizim, PdfiumBelge.
  - PdfiumBelge Türkçe metin değiştiriyor ve gerçek silme yapıyor.
  - `swift test`: 14/14 geçti.
- PDFium xcframework: `araclar/pdfium-hazirla.sh` → `KagitKit/Ikili/` (git dışı). Noto yazı tipleri (OFL) pakete eklendi.
- `project.yml` (xcodegen: `~/Developer/.tools/xcodegen/xcodegen/bin/xcodegen`). `Secrets.xcconfig` git dışı, `KAGIT_VEKIL_ANAHTARI` içeriyor.
- Uygulama iskeleti:
  - App: KagitApp, Yonlendirici, AnaGorunum
  - Kitaplık: Kitaplik, DosyalarGorunumu, KucukResim
  - Görüntüleyici: BelgeOturumu, PDFGorunumu, BelgeEkrani
  - Araçlar: Arac, AracSablonu, AraclarGorunumu
  - Ortak: OrtakKlasor

## Kalanlar (henüz DERLENMEDİ)
1. Eksik türler, önce saplama olarak eklenecek: AnaSayfa, Ayarlar + AyarlarGorunumu, Gizli (Keychain + `ilkAcilisAktarimi`), `kilitKatmani()`, TaramaEkrani, OgretmenMerkezi, TopluAracSecici, SayfaDuzenleyici, IsaretleCubugu, DuzenleCubugu, ImzalaCubugu, OgretmenCubugu, YapayZekaCubugu.
   - Ayrıca araç listeleri: sayfaAraclari, donusturAraclari, guvenlikAraclari, taramaAraclari, duzenleAraclari, ogretmenAraclari, yapayAraclari.
   - Ayrıca KagitPaylas uzantısı (PaylasimDenetcisi), Assets/AppIcon ve telefona-kur.sh.
2. Planlanan 4 paralel modül (ayrı worktree'lerde):
   - A: sayfa / damga / sıkıştırma / dönüştürme / karşılaştırma / toplu işlem + VPS PDF Studio istemcisi
   - B: düzenleyici (açıklama, PencilKit, şekil, damga, imza, form, PDFium ile metin düzenleme, sayfa düzenleyici)
   - C: tarama + OCR + güvenlik (şifre, karartma, üst veri) + Face ID + Spotlight + paylaşım uzantısı + Kısayollar
   - D: öğretmen + yapay zekâ (Claude vekili `…/dersdas/claude/v1`, X-Personal-Token; Foundation Models yalnız uygun cihazda) + çeviri + sesli okuma
3. VPS: Caddy'ye `/dersdas/claude/v1/pdf/*` → 127.0.0.1:8060 (PDF Studio) yolu eklenecek. Kaynak-ai bloğundaki gibi olacak: önce yedek, sonra `caddy validate`. LibreOffice VPS'te kurulu.
4. Code-review + Codex çaprazı (Codex MCP bu oturumda bağlanamadı), simülatör derlemesi, telefona kurulum (UDID 00008120-001C592421D8A01E; başka oturum kuruyorsa bekle).

## Araştırma
- Rakip envanteri: `/private/tmp/claude-501/-Users-mehmetderin/65364003-27b3-47f1-aa75-c685df2b9395/scratchpad/arastirma/rakip-envanteri.md`. Geçicidir; kalıcı olması için `docs/` altına kopyalanmalı.
- Teknik bulgular:
  - iOS 27'de PDFKit gerilemeleri var: açıklamalar pikselleşiyor, outline/link kayıtta düşüyor. Etkileşimsiz açıklamalar `burnIn` ile düzleştirilmeli.
  - Sıkıştırma: `burnIn + JPEG + screen` seçenekleri ölçümde 17,4 MB'ı 0,89 MB'a indirdi.
  - OCR: Vision tr-TR destekliyor. Aranabilir PDF görünmez metin katmanıyla yapılıyor.
  - Formlar: PDFKit'in oluşturduğu alanlar `/AcroForm` içermiyor. Çözüm pdf-lib (JSC) ya da `/AcroForm` yaması.
  - Gerçek karartma için en güvenli yol sayfayı rasterleştirmek.
