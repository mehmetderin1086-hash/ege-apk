"""Okulun verdiği haftalık ders programından öğretmenin derslerini çıkarır.

Bu dosyaların biçimi okuldan okula değişir; iki yaygın yerleşim desteklenir:

  - Günler SÜTUN başlığında, ders saatleri satırda (en yaygın)
  - Günler SATIR başlığında, ders saatleri sütunda (devrik)

Ayrıştırma başarısızsa akış durmaz: `ders_programi_coz` boş sonuç ve uyarı
döner, kullanıcı arayüzdeki ızgaradan elle işaretler.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

from .tablo import Tablo

GUN_ADLARI = {
    "pazartesi": 1,
    "salı": 2,
    "sali": 2,
    "çarşamba": 3,
    "carsamba": 3,
    "perşembe": 4,
    "persembe": 4,
    "cuma": 5,
    "cumartesi": 6,
    "pazar": 7,
}

SUBE_KALIBI = re.compile(r"\b(9|1[0-2])\s*[-/ ]?\s*([A-ZÇĞİÖŞÜ])\b")
SAAT_KALIBI = re.compile(r"^\s*(\d{1,2})\s*\.?\s*(ders|saat)?\s*$", re.IGNORECASE)


@dataclass(frozen=True)
class DersHucresi:
    gun: int
    ders_saati: int
    sube_adi: str


@dataclass
class ProgramSonucu:
    hucreler: list[DersHucresi] = field(default_factory=list)
    uyarilar: list[str] = field(default_factory=list)

    @property
    def subeler(self) -> list[str]:
        return sorted({h.sube_adi for h in self.hucreler})

    def sube_ders_gunleri(self, sube_adi: str) -> dict[int, int]:
        """Bir şube için {gün: o gün yapılan ders saati} tablosu."""
        sayac: dict[int, int] = {}
        for hucre in self.hucreler:
            if hucre.sube_adi == sube_adi:
                sayac[hucre.gun] = sayac.get(hucre.gun, 0) + 1
        return sayac

    def haftalik_saat(self, sube_adi: str) -> int:
        return sum(1 for h in self.hucreler if h.sube_adi == sube_adi)


def sube_ayikla(hucre: str) -> str:
    eslesme = SUBE_KALIBI.search(hucre.upper())
    if not eslesme:
        return ""
    return f"{eslesme.group(1)}-{eslesme.group(2)}"


def _gun_indeksi(hucre: str) -> int:
    kucuk = hucre.casefold().strip()
    for ad, no in GUN_ADLARI.items():
        if kucuk.startswith(ad):
            return no
    return 0


def _saat_no(hucre: str) -> int:
    eslesme = SAAT_KALIBI.match(hucre)
    if not eslesme:
        return 0
    no = int(eslesme.group(1))
    return no if 1 <= no <= 12 else 0


def _gunler_sutunda(satirlar: list[list[str]]) -> ProgramSonucu | None:
    """Günler sütun başlığında olan yerleşimi çözer."""
    for i, satir in enumerate(satirlar[:20]):
        gun_sutunlari = {j: _gun_indeksi(h) for j, h in enumerate(satir) if _gun_indeksi(h)}
        if len(gun_sutunlari) < 3:
            continue
        sonuc = ProgramSonucu()
        sira = 0
        for govde in satirlar[i + 1 :]:
            if not any(h.strip() for h in govde):
                continue
            saat = next((_saat_no(h) for h in govde[:2] if _saat_no(h)), 0)
            if not saat:
                sira += 1
                saat = sira
            else:
                sira = saat
            for sutun, gun in gun_sutunlari.items():
                if sutun >= len(govde):
                    continue
                sube = sube_ayikla(govde[sutun])
                if sube:
                    sonuc.hucreler.append(DersHucresi(gun=gun, ders_saati=saat, sube_adi=sube))
        if sonuc.hucreler:
            return sonuc
    return None


def _gunler_satirda(satirlar: list[list[str]]) -> ProgramSonucu | None:
    """Günler satır başında olan devrik yerleşimi çözer."""
    sonuc = ProgramSonucu()
    for satir in satirlar:
        if not satir:
            continue
        gun = _gun_indeksi(satir[0])
        if not gun:
            continue
        for sutun, hucre in enumerate(satir[1:], start=1):
            sube = sube_ayikla(hucre)
            if sube:
                sonuc.hucreler.append(DersHucresi(gun=gun, ders_saati=sutun, sube_adi=sube))
    return sonuc if sonuc.hucreler else None


def ders_programi_coz(tablo: Tablo) -> ProgramSonucu:
    satirlar = tablo.dolu_satirlar()
    if not satirlar:
        return ProgramSonucu(uyarilar=["Dosyada okunabilir satır yok."])

    for cozucu in (_gunler_sutunda, _gunler_satirda):
        sonuc = cozucu(satirlar)
        if sonuc:
            sonuc.uyarilar.append(
                f"{len(sonuc.hucreler)} ders saati okundu ({', '.join(sonuc.subeler)}). "
                "Izgarada kontrol edip düzeltebilirsiniz."
            )
            return sonuc

    return ProgramSonucu(
        uyarilar=[
            "Ders programı tanınamadı. Dosyada gün adları ve 9-A gibi şube "
            "yazımları aranıyor. Izgaradan elle işaretleyebilirsiniz."
        ]
    )
