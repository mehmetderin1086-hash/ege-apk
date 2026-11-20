"""Dosyadan düz metin çıkarımı — biçim dağıtıcısı.

Her çıkarıcı `Parca` listesi döndürür: metin + nereden geldiği (PDF sayfası,
ses dosyasında saniye aralığı). Bu konum bilgisi alım önizlemesinde
gösterilir; öğretmen "bu soru kitabın 143. sayfasından" diye doğrulayabilsin
diye taşınır, sonra `Ornek.kaynak` alanına yazılır.
"""

from __future__ import annotations

import hashlib
from dataclasses import dataclass, field
from pathlib import Path


class AlimHatasi(RuntimeError):
    """Dosya okunamadığında veya biçim desteklenmediğinde oluşur."""


PDF_UZANTILARI = {".pdf"}
WORD_UZANTILARI = {".docx"}
METIN_UZANTILARI = {".txt", ".md", ".text"}
GORUNTU_UZANTILARI = {".png", ".jpg", ".jpeg", ".webp", ".tif", ".tiff", ".bmp"}
SES_UZANTILARI = {".mp3", ".m4a", ".wav", ".flac", ".ogg", ".aac", ".opus", ".wma"}
VIDEO_UZANTILARI = {".mp4", ".mov", ".mkv", ".avi", ".webm", ".m4v", ".mpg", ".mpeg"}

DESTEKLENEN_UZANTILAR = (
    PDF_UZANTILARI
    | WORD_UZANTILARI
    | METIN_UZANTILARI
    | GORUNTU_UZANTILARI
    | SES_UZANTILARI
    | VIDEO_UZANTILARI
)

# Bir sayfanın metin katmanı bu uzunluğun altındaysa "taranmış" sayılır ve
# OCR'a düşer. Sıfır eşiği yetmiyor: taranmış sayfalarda çoğu zaman sayfa
# numarası ya da birkaç harflik artık metin bulunuyor.
OCR_ESIGI_KARAKTER = 40

# Kitap taramaları büyük olabiliyor; sınırsız okuma belleği tüketir.
AZAMI_BOYUT_MB = 500


@dataclass
class Parca:
    """Metnin bir dilimi ve kaynaktaki yeri."""

    metin: str
    sayfa: int | None = None          # PDF/Word için
    baslangic_sn: float | None = None  # ses/video için
    bitis_sn: float | None = None

    def konum(self) -> str:
        if self.sayfa is not None:
            return f"s. {self.sayfa}"
        if self.baslangic_sn is not None:
            return f"{_sure_bicimle(self.baslangic_sn)}"
        return ""


@dataclass
class Kaynak:
    """Alınan dosyanın künyesi — örneklere atıf olarak yazılır."""

    ad: str
    tur: str                     # pdf | word | metin | ses | video
    imza: str                    # içerik SHA-256'sı (ilk 16 hane)
    parcalar: list[Parca] = field(default_factory=list)
    uyarilar: list[str] = field(default_factory=list)

    @property
    def metin(self) -> str:
        return "\n".join(p.metin for p in self.parcalar if p.metin.strip())

    def parca_bul(self, konum_indeksi: int) -> Parca | None:
        """Birleşik metindeki karakter konumunun düştüğü parça."""
        sayac = 0
        for parca in self.parcalar:
            if not parca.metin.strip():
                continue
            sayac += len(parca.metin) + 1
            if konum_indeksi < sayac:
                return parca
        return self.parcalar[-1] if self.parcalar else None

    def konum_bul(self, konum_indeksi: int) -> str:
        """Birleşik metindeki karakter konumunun hangi parçaya düştüğünü söyler."""
        parca = self.parca_bul(konum_indeksi)
        return parca.konum() if parca is not None else ""

    def kaynak_adi(self, konum_indeksi: int | None = None) -> str:
        """`Ornek.kaynak` alanına yazılacak insan-okunur atıf."""
        if konum_indeksi is None:
            return self.ad
        yer = self.konum_bul(konum_indeksi)
        return f"{self.ad} ({yer})" if yer else self.ad


def _sure_bicimle(saniye: float) -> str:
    toplam = int(saniye)
    return f"{toplam // 60:02d}:{toplam % 60:02d}"


def _dosya_imzasi(yol: Path) -> str:
    ozet = hashlib.sha256()
    with yol.open("rb") as dosya:
        for blok in iter(lambda: dosya.read(1 << 20), b""):
            ozet.update(blok)
    return ozet.hexdigest()[:16]


def _boyutu_denetle(yol: Path) -> None:
    mb = yol.stat().st_size / (1024 * 1024)
    if mb > AZAMI_BOYUT_MB:
        raise AlimHatasi(
            f"Dosya çok büyük ({mb:.0f} MB, sınır {AZAMI_BOYUT_MB} MB)."
        )


# --- biçim çıkarıcıları ---


def _pdf_cikar(
    yol: Path, *, ocr: str = "oto", ocr_motoru: str = "", uyarilar: list[str] | None = None
) -> list[Parca]:
    """PDF'i sayfa sayfa okur; metin katmanı yoksa (taranmışsa) OCR'a düşer.

    `ocr`: "oto" (yalnız boş sayfalar), "kapali", "zorla" (tüm sayfalar).
    OCR pahalı olduğu için varsayılan "oto" — metin katmanı olan bir kitabı
    körlemesine OCR'lamak dakikalar sürer ve sonucu genelde daha kötüdür.
    """
    try:
        import pypdfium2
    except ImportError as exc:  # pragma: no cover - ortam bağımlı
        raise AlimHatasi(
            "PDF okumak için: uv sync --extra alim"
        ) from exc
    try:
        belge = pypdfium2.PdfDocument(str(yol))
    except Exception as exc:
        raise AlimHatasi(f"PDF açılamadı: {exc}") from exc

    parcalar: list[Parca] = []
    ocr_sayfalari: list[int] = []
    ocr_hatasi = ""
    try:
        for no, sayfa in enumerate(belge, 1):
            try:
                metin = sayfa.get_textpage().get_text_range()
            except Exception:  # noqa: BLE001 - bozuk sayfa tüm dosyayı düşürmesin
                metin = ""

            gerekli = ocr == "zorla" or (
                ocr == "oto" and len(metin.strip()) < OCR_ESIGI_KARAKTER
            )
            if gerekli and ocr != "kapali":
                try:
                    from .ocr import sayfayi_oku

                    sonuc = sayfayi_oku(sayfa, motor=ocr_motoru)
                    if sonuc.metin.strip():
                        metin = sonuc.metin
                        ocr_sayfalari.append(no)
                except AlimHatasi as exc:
                    # Tek bir hata mesajı yeter; her sayfa için tekrarlamak
                    # uyarı listesini kullanılamaz hale getirirdi.
                    ocr_hatasi = ocr_hatasi or str(exc)
            parcalar.append(Parca(metin=metin, sayfa=no))
    finally:
        belge.close()

    if uyarilar is not None:
        if ocr_sayfalari:
            uyarilar.append(
                f"{len(ocr_sayfalari)} sayfada metin katmanı yoktu, OCR uygulandı "
                f"(sayfa {', '.join(str(s) for s in ocr_sayfalari[:8])}"
                f"{'…' if len(ocr_sayfalari) > 8 else ''})."
            )
        if ocr_hatasi:
            uyarilar.append(f"OCR uygulanamadı: {ocr_hatasi}")
    return parcalar


def _goruntu_cikar(yol: Path, *, ocr_motoru: str = "") -> list[Parca]:
    from .ocr import goruntuyu_oku

    return [Parca(metin=goruntuyu_oku(yol, motor=ocr_motoru).metin)]


def _word_cikar(yol: Path) -> list[Parca]:
    try:
        import docx
    except ImportError as exc:  # pragma: no cover
        raise AlimHatasi("Word okumak için: uv sync --extra alim") from exc
    try:
        belge = docx.Document(str(yol))
    except Exception as exc:
        raise AlimHatasi(f"Word belgesi açılamadı: {exc}") from exc

    satirlar = [p.text for p in belge.paragraphs]
    # Sorular sıklıkla tabloya dizilir; yalnız paragrafları okumak
    # kitapların önemli bir kısmını görünmez yapardı.
    for tablo in belge.tables:
        for satir in tablo.rows:
            hucreler = [h.text.strip() for h in satir.cells if h.text.strip()]
            if hucreler:
                satirlar.append(" | ".join(hucreler))
    return [Parca(metin="\n".join(satirlar))]


def _metin_cikar(yol: Path) -> list[Parca]:
    for kodlama in ("utf-8", "utf-8-sig", "cp1254", "latin-1"):
        try:
            return [Parca(metin=yol.read_text(encoding=kodlama))]
        except UnicodeDecodeError:
            continue
    raise AlimHatasi("Metin dosyasının kodlaması çözülemedi.")


def _ses_cikar(yol: Path, *, video: bool) -> list[Parca]:
    from .ses import sesi_yaziya_dok

    return sesi_yaziya_dok(yol, video=video)


# --- genel giriş ---


def dosya_turu(yol: Path) -> str:
    uzanti = yol.suffix.casefold()
    if uzanti in PDF_UZANTILARI:
        return "pdf"
    if uzanti in WORD_UZANTILARI:
        return "word"
    if uzanti in METIN_UZANTILARI:
        return "metin"
    if uzanti in GORUNTU_UZANTILARI:
        return "goruntu"
    if uzanti in SES_UZANTILARI:
        return "ses"
    if uzanti in VIDEO_UZANTILARI:
        return "video"
    raise AlimHatasi(
        f"Desteklenmeyen dosya türü: {uzanti or '(uzantısız)'}. "
        f"Desteklenenler: {', '.join(sorted(DESTEKLENEN_UZANTILAR))}"
    )


def metni_cikar(
    yol: str | Path,
    *,
    ad: str = "",
    ocr: str = "oto",
    ocr_motoru: str = "",
) -> Kaynak:
    """Dosyayı türüne göre düz metne çevirir.

    `ocr`: "oto" (taranmış sayfalara uygula), "kapali", "zorla".
    `ocr_motoru`: "" (otomatik), "surya", "easyocr", "paddle", "tesseract".
    """
    yol = Path(yol)
    if not yol.is_file():
        raise AlimHatasi(f"Dosya bulunamadı: {yol}")
    _boyutu_denetle(yol)

    tur = dosya_turu(yol)
    uyarilar: list[str] = []
    if tur == "pdf":
        parcalar = _pdf_cikar(
            yol, ocr=ocr, ocr_motoru=ocr_motoru, uyarilar=uyarilar
        )
    elif tur == "word":
        parcalar = _word_cikar(yol)
    elif tur == "metin":
        parcalar = _metin_cikar(yol)
    elif tur == "goruntu":
        parcalar = _goruntu_cikar(yol, ocr_motoru=ocr_motoru)
    else:
        parcalar = _ses_cikar(yol, video=(tur == "video"))

    kaynak = Kaynak(
        ad=ad or yol.name,
        tur=tur,
        imza=_dosya_imzasi(yol),
        parcalar=parcalar,
        uyarilar=uyarilar,
    )
    if not kaynak.metin.strip():
        if tur == "pdf" and ocr == "kapali":
            kaynak.uyarilar.append(
                "Sayfalarda metin katmanı yok ve OCR kapalı. "
                "Taranmış PDF için OCR'ı açın."
            )
        else:
            kaynak.uyarilar.append(
                "Dosyadan hiç metin çıkmadı. Taranmış görüntü okunamamış "
                "ya da ses kaydı sessiz olabilir."
            )
    return kaynak
