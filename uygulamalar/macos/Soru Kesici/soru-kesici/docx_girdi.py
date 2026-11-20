#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""DOCX girdilerini yerel LibreOffice ile güvenli biçimde PDF'ye dönüştürür.

Bu modül yalnız girdi hazırlama işini üstlenir. Dönüşüm sonucu, kaynak DOCX'in
kimliğini kaybetmemesi için :class:`DocxDonusumKaydi` ile birlikte döner.
Kaynak belge hiçbir zaman değiştirilmez; üretilen PDF sürümlü kullanıcı önbelleğine
atomik olarak yerleştirilir.
"""

from __future__ import annotations

import hashlib
import os
import shutil
import subprocess
import tempfile
import threading
import zipfile
import zlib
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Dict, Optional
from xml.etree import ElementTree

import fitz  # PyMuPDF — üretilen/cache PDF'in gerçekten açılabildiğini doğrular

import veri_yollari

DOCX_DONUSUM_SURUMU = "3.0"
DOCX_CACHE_DIZIN = os.path.join(veri_yollari.onbellek_koku(), "docx-v3")
SOFFICE_MAC_YOLU = "/Applications/LibreOffice.app/Contents/MacOS/soffice"
SOFFICE_WIN_YOLLARI = (
    r"C:\Program Files\LibreOffice\program\soffice.exe",
    r"C:\Program Files (x86)\LibreOffice\program\soffice.exe",
)
SOFFICE_ENV = "SORU_KESICI_SOFFICE"


class DocxGirdiHatasi(ValueError):
    """Kaynak DOCX boş, bozuk veya desteklenmeyen bir paket olduğunda."""


class SofficeBulunamadiHatasi(RuntimeError):
    """Yerel LibreOffice dönüştürücüsü bulunamadığında."""


class DocxDonusumHatasi(RuntimeError):
    """LibreOffice çalıştığı halde geçerli bir PDF üretemediğinde."""


@dataclass(frozen=True)
class DocxDonusumKaydi:
    """Bir DOCX→PDF dönüşümünün JSON'a çevrilebilir kaynak kaydı."""

    kaynak_yolu: str
    kaynak_adi: str
    kaynak_sha256: str
    kaynak_boyutu: int
    kaynak_mtime_ns: int
    pdf_yolu: str
    onbellek_anahtari: str
    onbellekten: bool
    donusturucu_yolu: str
    donusturucu_surumu: str
    donusum_surumu: str = DOCX_DONUSUM_SURUMU

    def sozluk(self) -> Dict[str, object]:
        """Kayıt/metadata katmanları için bağımsız bir sözlük döndürür."""
        return asdict(self)

    def to_dict(self) -> Dict[str, object]:
        """İngilizce ad kullanan mevcut metadata katmanları için eş ad."""
        return self.sozluk()


def _calistirilabilir_dosya(yol: str) -> bool:
    return os.path.isfile(yol) and os.access(yol, os.X_OK)


def soffice_bul() -> str:
    """``soffice`` yolunu ortam değişkeni, PATH ve macOS uygulamasında ara.

    Ortam değişkeni açık bir kullanıcı tercihi olduğundan, tanımlı ama hatalıysa
    sessizce başka bir LibreOffice sürümüne geçilmez; anlaşılır hata verilir.
    """
    ortam = os.environ.get(SOFFICE_ENV, "").strip()
    if ortam:
        genisletilmis = os.path.abspath(os.path.expanduser(ortam))
        # Değer yalnız komut adı olarak verilmişse PATH çözümlemesine izin ver.
        aday = (shutil.which(ortam) if os.path.sep not in ortam else None)
        aday = aday or genisletilmis
        if _calistirilabilir_dosya(aday):
            return os.path.realpath(aday)
        raise SofficeBulunamadiHatasi(
            f"{SOFFICE_ENV} çalıştırılabilir bir soffice dosyasını "
            f"göstermiyor: {ortam}")

    path_adayi = shutil.which("soffice")
    if path_adayi and _calistirilabilir_dosya(path_adayi):
        return os.path.realpath(path_adayi)
    if os.name == "nt":
        for aday in SOFFICE_WIN_YOLLARI:
            if _calistirilabilir_dosya(aday):
                return os.path.realpath(aday)
    elif _calistirilabilir_dosya(SOFFICE_MAC_YOLU):
        return os.path.realpath(SOFFICE_MAC_YOLU)
    raise SofficeBulunamadiHatasi(
        "LibreOffice/soffice bulunamadı. DOCX desteği için LibreOffice'i "
        f"kurun veya {SOFFICE_ENV} ortam değişkenini soffice yoluna ayarlayın.")


def _dosya_sha256(yol: Path) -> str:
    ozet = hashlib.sha256()
    with yol.open("rb") as dosya:
        for parca in iter(lambda: dosya.read(1024 * 1024), b""):
            ozet.update(parca)
    return ozet.hexdigest()


def _docx_dogrula(yol: Path) -> None:
    if yol.suffix.lower() != ".docx":
        raise DocxGirdiHatasi(f"DOCX uzantısı bekleniyordu: {yol.name}")
    if not yol.exists():
        raise FileNotFoundError(f"DOCX dosyası bulunamadı: {yol}")
    if not yol.is_file():
        raise DocxGirdiHatasi(f"DOCX yolu bir dosya değil: {yol}")
    if yol.stat().st_size == 0:
        raise DocxGirdiHatasi(f"DOCX dosyası boş: {yol.name}")

    try:
        with zipfile.ZipFile(str(yol), "r") as paket:
            adlar = set(paket.namelist())
            eksik = {"[Content_Types].xml", "word/document.xml"} - adlar
            if eksik:
                raise DocxGirdiHatasi(
                    f"DOCX paketi bozuk; zorunlu içerik eksik: {yol.name}")
            # CRC ve sıkıştırılmış akış hatalarını da dönüşümden önce yakala.
            bozuk = paket.testzip()
            if bozuk:
                raise DocxGirdiHatasi(
                    f"DOCX paketi bozuk; okunamayan parça: {bozuk}")
            for parca in ("[Content_Types].xml", "word/document.xml"):
                veri = paket.read(parca)
                if not veri:
                    raise DocxGirdiHatasi(
                        f"DOCX paketi bozuk; {parca} boş: {yol.name}")
                try:
                    ElementTree.fromstring(veri)
                except ElementTree.ParseError as exc:
                    raise DocxGirdiHatasi(
                        f"DOCX paketi bozuk; geçersiz XML: {parca}") from exc
    except DocxGirdiHatasi:
        raise
    except (EOFError, OSError, RuntimeError, zlib.error, zipfile.BadZipFile,
            zipfile.LargeZipFile) as exc:
        raise DocxGirdiHatasi(
            f"DOCX dosyası bozuk veya geçersiz: {yol.name}") from exc


def _soffice_surumu(soffice_yolu: str) -> str:
    try:
        sonuc = subprocess.run(
            [soffice_yolu, "--version"], capture_output=True, text=True,
            encoding="utf-8", timeout=15, check=False)
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise DocxDonusumHatasi(
            f"LibreOffice sürümü okunamadı: {soffice_yolu}") from exc
    cikti = (sonuc.stdout or sonuc.stderr or "").strip().splitlines()
    if sonuc.returncode != 0 or not cikti or not cikti[0].strip():
        ayrinti = " ".join(cikti).strip()[:300]
        ek = f" ({ayrinti})" if ayrinti else ""
        raise DocxDonusumHatasi(
            f"LibreOffice sürümü okunamadı{ek}")
    return cikti[0].strip()


def _onbellek_anahtari(kaynak_sha256: str, surum: str) -> str:
    donusturucu = hashlib.sha256(surum.encode("utf-8")).hexdigest()[:16]
    return f"{kaynak_sha256}-{donusturucu}-v{DOCX_DONUSUM_SURUMU}"


def _pdf_gecerli(yol: Path) -> bool:
    try:
        if not yol.is_file() or yol.stat().st_size < 12:
            return False
        with yol.open("rb") as dosya:
            bas = dosya.read(1024)
            if b"%PDF-" not in bas:
                return False
            dosya.seek(max(0, yol.stat().st_size - 2048))
            if b"%%EOF" not in dosya.read():
                return False
        with fitz.open(str(yol)) as belge:
            return belge.page_count > 0 and not belge.needs_pass
    except (OSError, RuntimeError, ValueError):
        return False


def _hata_ayrintisi(sonuc: subprocess.CompletedProcess) -> str:
    metin = (sonuc.stderr or sonuc.stdout or "").strip()
    return " ".join(metin.split())[:600]


def _pdf_uret(kaynak: Path, hedef: Path, soffice_yolu: str,
              zaman_asimi: int) -> None:
    cache = hedef.parent
    with tempfile.TemporaryDirectory(prefix="docx_donusum_",
                                     dir=str(cache)) as gecici:
        gecici_yol = Path(gecici)
        # FILENAME alanı gibi ada duyarlı Word alanları aynı render edilsin.
        # ``kaynak.name`` dizin bileşeni içermez; geçici dizinin dışına çıkamaz.
        girdi = gecici_yol / kaynak.name
        cikti_dizini = gecici_yol / "cikti"
        profil = gecici_yol / "lo-profil"
        cikti_dizini.mkdir()
        profil.mkdir()
        shutil.copyfile(str(kaynak), str(girdi))
        # Hash ile okunan kaynak, kopyalama sırasında değişmişse yanlış anahtarlı
        # PDF üretme; kullanıcı belgeyi kaydetmeyi bitirince yeniden deneyebilir.
        if _dosya_sha256(girdi) != hedef.name.split("-", 1)[0]:
            raise DocxDonusumHatasi(
                "DOCX dosyası dönüşüm sırasında değişti; lütfen yeniden deneyin.")

        komut = [
            soffice_yolu,
            "--headless", "--nologo", "--nodefault", "--nofirststartwizard",
            "--nolockcheck", f"-env:UserInstallation={profil.as_uri()}",
            "--convert-to", "pdf:writer_pdf_Export",
            "--outdir", str(cikti_dizini), str(girdi),
        ]
        try:
            sonuc = subprocess.run(
                komut, capture_output=True, text=True, encoding="utf-8",
                timeout=zaman_asimi, check=False)
        except FileNotFoundError as exc:
            raise SofficeBulunamadiHatasi(
                f"LibreOffice dönüşüm sırasında bulunamadı: {soffice_yolu}") from exc
        except subprocess.TimeoutExpired as exc:
            raise DocxDonusumHatasi(
                f"DOCX dönüşümü {zaman_asimi} saniyede tamamlanamadı") from exc
        except OSError as exc:
            raise DocxDonusumHatasi(
                f"LibreOffice başlatılamadı: {exc}") from exc

        if sonuc.returncode != 0:
            ayrinti = _hata_ayrintisi(sonuc)
            raise DocxDonusumHatasi(
                "DOCX, LibreOffice ile PDF'ye dönüştürülemedi"
                + (f": {ayrinti}" if ayrinti else ""))

        adaylar = sorted(cikti_dizini.glob("*.pdf"))
        uretilen = adaylar[0] if len(adaylar) == 1 else None
        if uretilen is None or not _pdf_gecerli(uretilen):
            ayrinti = _hata_ayrintisi(sonuc)
            raise DocxDonusumHatasi(
                "LibreOffice geçerli bir PDF üretmedi"
                + (f": {ayrinti}" if ayrinti else ""))
        os.replace(str(uretilen), str(hedef))


_ONBELLEK_KILIDI = threading.Lock()


def docx_pdf_hazirla(yol: str, onbellek_dizini: Optional[str] = None,
                     zaman_asimi: int = 180) -> DocxDonusumKaydi:
    """DOCX'i yerel ``soffice`` ile PDF'ye dönüştür ve kaynak kaydını döndür.

    Önbellek anahtarı kaynak SHA-256, LibreOffice sürümü ve bu modülün dönüşüm
    sürümünden oluşur. Aynı içerik/sürüm ikinci kez çağrıldığında LibreOffice
    çalıştırılmaz. ``zaman_asimi`` pozitif saniye olmalıdır.
    """
    kaynak = Path(os.path.abspath(os.path.expanduser(os.fspath(yol))))
    _docx_dogrula(kaynak)
    if zaman_asimi <= 0:
        raise ValueError("DOCX dönüşüm zaman aşımı pozitif olmalıdır")

    stat = kaynak.stat()
    kaynak_sha = _dosya_sha256(kaynak)
    soffice_yolu = soffice_bul()
    soffice_surumu = _soffice_surumu(soffice_yolu)
    anahtar = _onbellek_anahtari(kaynak_sha, soffice_surumu)
    varsayilan_cache = os.environ.get(
        "SORU_KESICI_DOCX_CACHE", DOCX_CACHE_DIZIN)
    cache = Path(os.path.abspath(os.path.expanduser(
        onbellek_dizini or varsayilan_cache)))
    try:
        cache.mkdir(parents=True, exist_ok=True)
    except OSError as exc:
        raise DocxDonusumHatasi(
            f"DOCX önbellek dizini oluşturulamadı: {cache}") from exc
    pdf_yolu = cache / f"{anahtar}.pdf"

    onbellekten = _pdf_gecerli(pdf_yolu)
    if not onbellekten:
        # Aynı süreçte eşzamanlı yüklenen aynı DOCX yalnız bir kez dönüştürülsün.
        with _ONBELLEK_KILIDI:
            onbellekten = _pdf_gecerli(pdf_yolu)
            if not onbellekten:
                _pdf_uret(kaynak, pdf_yolu, soffice_yolu, zaman_asimi)

    return DocxDonusumKaydi(
        kaynak_yolu=str(kaynak),
        kaynak_adi=kaynak.name,
        kaynak_sha256=kaynak_sha,
        kaynak_boyutu=stat.st_size,
        kaynak_mtime_ns=getattr(stat, "st_mtime_ns", int(stat.st_mtime * 1e9)),
        pdf_yolu=str(pdf_yolu),
        onbellek_anahtari=anahtar,
        onbellekten=onbellekten,
        donusturucu_yolu=soffice_yolu,
        donusturucu_surumu=soffice_surumu,
    )


__all__ = [
    "DOCX_CACHE_DIZIN", "DOCX_DONUSUM_SURUMU", "DocxDonusumHatasi",
    "DocxDonusumKaydi", "DocxGirdiHatasi", "SofficeBulunamadiHatasi",
    "docx_pdf_hazirla", "soffice_bul",
]
