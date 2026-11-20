"""Excel, CSV, PDF ve yapıştırılmış metni ortak bir satır listesine çevirir.

Böylece her ayrıştırıcı tek bir veri biçimiyle çalışır: `list[list[str]]`.
Kaynak biçimini tanımak burada bir kez yapılır.
"""

from __future__ import annotations

import csv
import io
import re
import zipfile
from dataclasses import dataclass, field
from pathlib import Path

EXCEL_UZANTILARI = {".xlsx", ".xlsm"}
CSV_UZANTILARI = {".csv", ".tsv", ".txt"}
PDF_UZANTILARI = {".pdf"}
EXCEL_ACILMIS_SINIR = 100 * 1024 * 1024
EXCEL_DOSYA_SINIR = 5000


class OkunamadiError(ValueError):
    """Dosya biçimi tanınmadı ya da içi boş."""


@dataclass
class Tablo:
    satirlar: list[list[str]] = field(default_factory=list)
    kaynak: str = ""
    uyarilar: list[str] = field(default_factory=list)

    def __len__(self) -> int:
        return len(self.satirlar)

    def dolu_satirlar(self) -> list[list[str]]:
        return [s for s in self.satirlar if any(h.strip() for h in s)]


def _hucre(deger: object) -> str:
    if deger is None:
        return ""
    if isinstance(deger, float) and deger.is_integer():
        return str(int(deger))
    return str(deger).strip()


def _excelden(yol: Path) -> list[list[str]]:
    from openpyxl import load_workbook

    try:
        with zipfile.ZipFile(yol) as paket:
            uyeler = paket.infolist()
            toplam = sum(u.file_size for u in uyeler)
            if len(uyeler) > EXCEL_DOSYA_SINIR or toplam > EXCEL_ACILMIS_SINIR:
                raise OkunamadiError(
                    "Excel dosyasının açılmış içeriği güvenli boyut sınırını aşıyor."
                )
            if any(
                u.compress_size > 0 and u.file_size / u.compress_size > 1000
                for u in uyeler
            ):
                raise OkunamadiError("Excel dosyasında olağan dışı sıkıştırma oranı var.")
    except zipfile.BadZipFile as hata:
        raise OkunamadiError(
            "Excel dosyası okunamadı; geçerli bir XLSX arşivi değil."
        ) from hata

    kitap = load_workbook(yol, data_only=True, read_only=True)
    satirlar: list[list[str]] = []
    for sayfa in kitap.worksheets:
        for satir in sayfa.iter_rows(values_only=True):
            satirlar.append([_hucre(h) for h in satir])
        # Birden çok sayfa varsa aralarına boş satır koyulur ki ayrıştırıcı
        # iki ayrı tabloyu birbirine karıştırmasın.
        satirlar.append([])
    kitap.close()
    return satirlar


def _csvden(metin: str) -> list[list[str]]:
    ornek = metin[:4096]
    try:
        lehce = csv.Sniffer().sniff(ornek, delimiters=",;\t|")
        ayirici = lehce.delimiter
    except csv.Error:
        ayirici = "\t" if "\t" in ornek else ","
    okuyucu = csv.reader(io.StringIO(metin), delimiter=ayirici)
    return [[h.strip() for h in satir] for satir in okuyucu]


def _csv_metni_oku(yol: Path) -> str:
    ham = yol.read_bytes()
    hatalar: list[str] = []
    for kodlama in ("utf-8-sig", "cp1254"):
        try:
            return ham.decode(kodlama)
        except UnicodeDecodeError as hata:
            hatalar.append(f"{kodlama}: {hata}")
    raise OkunamadiError(
        f"{yol.name} Türkçe UTF-8 veya Windows-1254 olarak çözülemedi "
        f"({'; '.join(hatalar)})."
    )


def _pdften(yol: Path) -> list[list[str]]:
    import pymupdf

    satirlar: list[list[str]] = []
    with pymupdf.open(yol) as belge:
        for sayfa in belge:
            # PDF'te sütun ayrımı yoktur; iki ve daha fazla boşluk sütun
            # sınırı sayılır. Tablo çizgileriyle hizalanmış çıktılarda işe
            # yarar, serbest metinde tek sütunlu satır üretir.
            for ham in sayfa.get_text("text").splitlines():
                if not ham.strip():
                    continue
                satirlar.append([p.strip() for p in re.split(r"\s{2,}|\t", ham.strip())])
    return satirlar


def tabloyu_oku(
    yol: Path | None = None, *, metin: str | None = None, ad: str = ""
) -> Tablo:
    """Dosyayı ya da yapıştırılmış metni tabloya çevirir."""
    if metin is not None:
        return Tablo(satirlar=_csvden(metin), kaynak=ad or "yapıştırılan metin")
    if yol is None:
        raise OkunamadiError("Dosya ya da metin verilmedi.")

    uzanti = yol.suffix.lower()
    okuyucular = {
        **dict.fromkeys(EXCEL_UZANTILARI, _excelden),
        **dict.fromkeys(CSV_UZANTILARI, lambda y: _csvden(_csv_metni_oku(y))),
        **dict.fromkeys(PDF_UZANTILARI, _pdften),
    }
    okuyucu = okuyucular.get(uzanti)
    if okuyucu is None:
        raise OkunamadiError(
            f"Tanınmayan dosya biçimi: {uzanti or yol.name}. "
            "Excel (.xlsx), CSV veya PDF gönderin."
        )
    try:
        satirlar = okuyucu(yol)
    except OkunamadiError:
        raise
    except Exception as hata:
        # openpyxl bozuk bir dosyada zipfile.BadZipFile, PyMuPDF kendi
        # istisnasını atıyor; bunlar sızarsa kullanıcı anlaşılır bir uyarı
        # yerine 500 görüyordu. Uzantısı doğru ama içi bozuk dosya yaygın:
        # ".xls" olarak kaydedilmiş HTML tablolar buradan geçiyor.
        raise OkunamadiError(
            f"{yol.name} okunamadı; dosya bozuk ya da adındaki biçimde değil ({hata})."
        ) from hata

    tablo = Tablo(satirlar=satirlar, kaynak=yol.name)
    if not tablo.dolu_satirlar():
        raise OkunamadiError(f"{yol.name} boş görünüyor.")
    return tablo


def baslik_satirini_bul(
    satirlar: list[list[str]], anahtarlar: tuple[str, ...], en_fazla: int = 25
) -> int:
    """İçinde beklenen sütun adları geçen ilk satırın indeksini verir.

    Okulların dosyalarında başlıktan önce logo, okul adı, boş satır olabiliyor;
    bu yüzden ilk satır başlık varsayılamaz.
    """
    for i, satir in enumerate(satirlar[:en_fazla]):
        kucuk = " ".join(h.casefold() for h in satir)
        if sum(1 for a in anahtarlar if a in kucuk) >= 2:
            return i
    for i, satir in enumerate(satirlar[:en_fazla]):
        kucuk = " ".join(h.casefold() for h in satir)
        if any(a in kucuk for a in anahtarlar):
            return i
    return -1


def sutun_bul(basliklar: list[str], adaylar: tuple[str, ...]) -> int:
    # Önce tam eşleşme: "öğrenci" ad adayı, "Öğrenci No" sütununu; tek
    # harfli "y" de "Adı Soyadı" sütununu ele geçirmemeli.
    aday_norm = tuple(a.casefold().strip() for a in adaylar)
    for i, baslik in enumerate(basliklar):
        if baslik.casefold().strip() in aday_norm:
            return i
    # Bazı yayınevleri "Biyoloji Doğru Sayısı" gibi ekli başlıklar kullanır.
    # İçerme yalnız anlamlı uzunluktaki adaylara uygulanır: eşik 3, çünkü
    # "boş" ve "net" meşru üç harfli adaylardır ("Boş Sayısı" başlığı 4
    # eşiğinde bulunamıyor ve boş sessizce 0 yazılıyordu); tek harfli "y"
    # ise hâlâ "Adı Soyadı"yı ele geçiremez.
    for i, baslik in enumerate(basliklar):
        kucuk = baslik.casefold().strip()
        if any(len(a) >= 3 and a in kucuk for a in aday_norm):
            return i
    return -1
