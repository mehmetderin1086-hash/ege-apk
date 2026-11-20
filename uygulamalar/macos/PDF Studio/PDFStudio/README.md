# PDF Studio

**iLovePDF benzeri, tamamen yerel çalışan, gelişmiş bir PDF düzenleme uygulaması.**
Dosyalarınız bilgisayarınızdan çıkmaz — tüm işlemler kendi makinenizde yapılır.

Python (FastAPI + PyMuPDF) arka uç + modern web arayüzü.

## Özellikler

- **Organize:** Birleştir, böl (aralık/sayfa sayısı/çıkar), sayfa sil, sayfa çıkar, sürükle-bırak yeniden sırala, döndür, kırp
- **Optimize:** Sıkıştır (düşük/orta/yüksek), onar, **OCR** (aranabilir PDF, Türkçe + İngilizce)
- **PDF'e Dönüştür:** Görsel → PDF, Word → PDF, HTML → PDF, Metin → PDF
- **PDF'ten Dönüştür:** PDF → JPG/PNG, PDF → Word, PDF → Excel, PDF → Metin
- **Editör:** Metin/görsel/şekil/çizim ekle, vurgu, filigran, sayfa numarası, üst/alt bilgi, redaksiyon
- **Güvenlik:** Şifrele (parola + izinler), şifre kaldır, imza, düzleştir, meta veri düzenle
- **Formlar:** Form doldur, form verisi çıkar, formu düzleştir
- **Oturum Dosyaları:** Yükleme ve çıktıları tek merkezde görüntüle, yeniden indir, tek tek sil veya tüm geçici alanı temizle

## Kurulum

Gereksinim: [uv](https://docs.astral.sh/uv/) (Python paket yöneticisi) ve Python 3.10+.

```bash
cd PDFStudio
uv sync
```

## Çalıştırma

```bash
uv run python run.py
```

Tarayıcı otomatik olarak `http://127.0.0.1:8060` adresinde açılır.
(Port `PDFSTUDIO_PORT` ortam değişkeniyle değiştirilebilir; 8000-8010 aralığı bu Mac'te Sınav Okur'a ayrılıdır.)

### macOS Masaüstü uygulaması

Özel simgeli `PDF Studio.app` paketini oluşturup Masaüstü'ne kurmak için:

```bash
zsh scripts/install_macos_app.sh
```

Uygulama Terminal penceresi açmadan yerel sunucuyu başlatır. Sunucu zaten
çalışıyorsa ikinci bir süreç başlatmadan mevcut arayüzü tarayıcıda açar.

## Test

```bash
uv run pytest
```

## Notlar

- **OCR** ilk kullanımda ONNX modellerini indirir (rapidocr-onnxruntime) — sistemde tesseract kurulu olması gerekmez.
- **Word → PDF** tam biçim sadakati için sistemde LibreOffice veya Microsoft Word varsa otomatik kullanılır; yoksa temel bir dönüşüm uygulanır.
- Tüm işlemler yereldir; dosyalar geçici `storage/` klasöründe tutulur ve süresi dolunca otomatik temizlenir.
