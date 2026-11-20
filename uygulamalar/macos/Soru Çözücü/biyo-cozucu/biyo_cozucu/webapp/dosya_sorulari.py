"""Çöz ekranına yüklenen soru dosyalarını çözülebilir öğelere dönüştürür.

Bu akış ``Kaynaktan al`` sayfasından ayrıdır: burada dosyalar kalıcı referans
örneğe çevrilmez, doğrudan çözülür. Resimler tek soru, PDF'ler sayfa (ve metin
katmanı uygunsa sayfadaki numaralı sorular) bazında hazırlanır.
"""

from __future__ import annotations

import io
import re
from dataclasses import dataclass
from pathlib import Path

from ..alim import adaylari_cikar
from ..gorsel import GorselDeposu, GorselHatasi


class SoruDosyasiHatasi(RuntimeError):
    """Yüklenen soru dosyası güvenle hazırlanamadığında oluşur."""


GORSEL_UZANTILARI = {
    ".png",
    ".jpg",
    ".jpeg",
    ".webp",
    ".gif",
    ".bmp",
    ".tif",
    ".tiff",
}
METIN_UZANTILARI = {".txt", ".md", ".text"}
DESTEKLENEN_UZANTILAR = GORSEL_UZANTILARI | METIN_UZANTILARI | {".pdf"}

AZAMI_DOSYA_SAYISI = 12
AZAMI_DOSYA_MB = 25
AZAMI_TOPLAM_MB = 80
AZAMI_PDF_SAYFASI = 30
AZAMI_SORU_SAYISI = 60
AZAMI_SORU_KARAKTERI = 12_000
PDF_GORSEL_OLCEGI = 1.6

GORSEL_SORUSU = (
    "Görseldeki biyoloji sorusunu ve varsa şıkları dikkatle okuyup çöz. "
    "Şekil, grafik ve tablodaki bilgileri de kullan; doğru cevabı açıkça belirt."
)

_IMZA = re.compile(r"^[0-9a-f]{32}$")


@dataclass(frozen=True)
class DosyaSorusu:
    baslik: str
    soru: str
    secenekler: str = ""
    gorsel: str = ""
    kaynak_turu: str = "gorsel"

    def sozluk(self) -> dict[str, str]:
        return {
            "baslik": self.baslik,
            "soru": self.soru,
            "secenekler": self.secenekler,
            "gorsel": self.gorsel,
            "kaynak_turu": self.kaynak_turu,
        }


def guvenli_dosya_adi(ad: str) -> str:
    """Tarayıcıdan gelen yolu düşürür; boş ad için anlaşılır bir karşılık verir."""
    return Path((ad or "").replace("\\", "/")).name or "isimsiz-dosya"


def gorsel_imzasi_gecerli_mi(kok: str | Path, imza: str) -> bool:
    """İstemcinin verdiği imza yol gezintisi yapmadan mevcut bir PNG'yi gösteriyor mu?"""
    return bool(_IMZA.fullmatch(imza or "")) and GorselDeposu(kok).var_mi(imza)


def _not_ekle(soru: str, not_metni: str) -> str:
    not_metni = (not_metni or "").strip()
    soru = (soru or "").strip()
    if not not_metni:
        return soru[:AZAMI_SORU_KARAKTERI]
    if not soru or soru == GORSEL_SORUSU:
        return f"{not_metni}\n\n{GORSEL_SORUSU}"[:AZAMI_SORU_KARAKTERI]
    return f"Kullanıcı notu: {not_metni}\n\n{soru}"[:AZAMI_SORU_KARAKTERI]


def _secenek_metni(secenekler: dict[str, str]) -> str:
    return "\n".join(f"{harf}) {metin}" for harf, metin in secenekler.items())


def _metinden_sorular(
    metin: str,
    *,
    baslik: str,
    gorsel: str = "",
    kaynak_turu: str,
    soru_notu: str = "",
) -> list[DosyaSorusu]:
    """Metin katmanındaki numaralı soruları ayırır; bulunamazsa bütünü kullanır."""
    temiz = (metin or "").strip()
    adaylar = adaylari_cikar(temiz) if temiz else []
    if adaylar:
        return [
            DosyaSorusu(
                baslik=f"{baslik} · Soru {sira}",
                soru=_not_ekle(aday.soru, soru_notu),
                secenekler=_secenek_metni(aday.secenekler),
                gorsel=gorsel,
                kaynak_turu=kaynak_turu,
            )
            for sira, aday in enumerate(adaylar, 1)
        ]
    soru = temiz[:AZAMI_SORU_KARAKTERI] if temiz else GORSEL_SORUSU
    return [
        DosyaSorusu(
            baslik=baslik,
            soru=_not_ekle(soru, soru_notu),
            gorsel=gorsel,
            kaynak_turu=kaynak_turu,
        )
    ]


def _gorsel_hazirla(depo: GorselDeposu, ad: str, veri: bytes, soru_notu: str) -> list[DosyaSorusu]:
    try:
        imza = depo.yaz(veri)
    except GorselHatasi as exc:
        raise SoruDosyasiHatasi(f"{ad}: {exc}") from exc
    return [
        DosyaSorusu(
            baslik=ad,
            soru=_not_ekle(GORSEL_SORUSU, soru_notu),
            gorsel=imza,
            kaynak_turu="gorsel",
        )
    ]


def _pdf_hazirla(depo: GorselDeposu, ad: str, veri: bytes, soru_notu: str) -> list[DosyaSorusu]:
    try:
        import pypdfium2
    except ImportError as exc:  # pragma: no cover - kurulum ortamına bağlı
        raise SoruDosyasiHatasi("PDF çözmek için pypdfium2 gerekli: uv sync --extra alim") from exc
    try:
        belge = pypdfium2.PdfDocument(veri)
    except Exception as exc:
        raise SoruDosyasiHatasi(f"{ad}: PDF açılamadı: {exc}") from exc

    try:
        sayfa_sayisi = len(belge)
        if sayfa_sayisi > AZAMI_PDF_SAYFASI:
            raise SoruDosyasiHatasi(
                f"{ad}: {sayfa_sayisi} sayfa var; tek yüklemede sınır {AZAMI_PDF_SAYFASI} sayfa."
            )
        sonuclar: list[DosyaSorusu] = []
        for sayfa_no in range(sayfa_sayisi):
            sayfa = belge[sayfa_no]
            try:
                metin = sayfa.get_textpage().get_text_range()
            except Exception:  # noqa: BLE001 - görsel sayfa yine çözülebilir
                metin = ""
            try:
                goruntu = sayfa.render(scale=PDF_GORSEL_OLCEGI).to_pil().convert("RGB")
                tampon = io.BytesIO()
                goruntu.save(tampon, format="PNG", optimize=True)
                imza = depo.yaz(tampon.getvalue())
            except Exception as exc:
                raise SoruDosyasiHatasi(
                    f"{ad} · sayfa {sayfa_no + 1}: görüntüye çevrilemedi: {exc}"
                ) from exc
            sonuclar.extend(
                _metinden_sorular(
                    metin,
                    baslik=f"{ad} · Sayfa {sayfa_no + 1}",
                    gorsel=imza,
                    kaynak_turu="pdf",
                    soru_notu=soru_notu,
                )
            )
        return sonuclar
    finally:
        belge.close()


def _metin_hazirla(ad: str, veri: bytes, soru_notu: str) -> list[DosyaSorusu]:
    metin = ""
    for kodlama in ("utf-8", "utf-8-sig", "cp1254", "latin-1"):
        try:
            metin = veri.decode(kodlama)
            break
        except UnicodeDecodeError:
            continue
    if not metin.strip():
        raise SoruDosyasiHatasi(f"{ad}: metin dosyası boş veya okunamadı.")
    return _metinden_sorular(metin, baslik=ad, kaynak_turu="metin", soru_notu=soru_notu)


def dosya_sorularini_hazirla(
    kok: str | Path,
    dosyalar: list[tuple[str, bytes]],
    *,
    soru_notu: str = "",
) -> list[DosyaSorusu]:
    """Resim/PDF/metin dosyalarını sınırlı, sıralı çözüm öğelerine dönüştürür."""
    dolu = [(guvenli_dosya_adi(ad), veri) for ad, veri in dosyalar if veri]
    if not dolu:
        raise SoruDosyasiHatasi("En az bir dolu soru dosyası seçin.")
    if len(dolu) > AZAMI_DOSYA_SAYISI:
        raise SoruDosyasiHatasi(f"Tek seferde en fazla {AZAMI_DOSYA_SAYISI} dosya yüklenebilir.")
    toplam = sum(len(veri) for _, veri in dolu)
    if toplam > AZAMI_TOPLAM_MB * 1024 * 1024:
        raise SoruDosyasiHatasi(f"Dosyaların toplamı {AZAMI_TOPLAM_MB} MB sınırını aşıyor.")

    depo = GorselDeposu(kok)
    sonuclar: list[DosyaSorusu] = []
    for ad, veri in dolu:
        if len(veri) > AZAMI_DOSYA_MB * 1024 * 1024:
            raise SoruDosyasiHatasi(f"{ad}: dosya {AZAMI_DOSYA_MB} MB sınırını aşıyor.")
        uzanti = Path(ad).suffix.casefold()
        if uzanti not in DESTEKLENEN_UZANTILAR:
            destek = ", ".join(sorted(DESTEKLENEN_UZANTILAR))
            raise SoruDosyasiHatasi(f"{ad}: desteklenmeyen dosya türü. Desteklenenler: {destek}")
        if uzanti == ".pdf":
            yeni = _pdf_hazirla(depo, ad, veri, soru_notu)
        elif uzanti in METIN_UZANTILARI:
            yeni = _metin_hazirla(ad, veri, soru_notu)
        else:
            yeni = _gorsel_hazirla(depo, ad, veri, soru_notu)
        if len(sonuclar) + len(yeni) > AZAMI_SORU_SAYISI:
            raise SoruDosyasiHatasi(
                f"Dosyalardan {AZAMI_SORU_SAYISI} adetten fazla soru/sayfa çıktı; "
                "daha küçük gruplar hâlinde yükleyin."
            )
        sonuclar.extend(yeni)
    return sonuclar
