"""Puanlama motoru: soru tipine göre strateji seçen tek giriş noktası."""

from __future__ import annotations

from typing import Callable

from ..modeller import PuanSonucu, Soru, SoruTipi, TanimaSonucu
from .ayarlar import PuanlamaAyar
from .bosluk import bosluk_puanla
from .gomme import Gomlemci, SbertGomlemci, gomlemci_yukle
from .rubrik import rubrik_puanla
from .yapisal import (
    eslestirme_puanla,
    formul_puanla,
    gorsel_cevap_kapisi,
    sayisal_puanla,
    siralama_puanla,
    soru_turunu_belirle,
)

__all__ = [
    "PuanlamaAyar",
    "Gomlemci",
    "SbertGomlemci",
    "gomlemci_yukle",
    "puanla",
    "bosluk_puanla",
    "rubrik_puanla",
    "soru_turunu_belirle",
    "PUANLAYICILAR",
    "puanlayici_kaydet",
    "puanlayici_coz",
]


def _bosluk_stratejisi(tanima, soru, gomlemci, ayar, referans_pasajlari, ek):
    return bosluk_puanla(
        tanima.metin,
        soru,
        ayar,
        ek.get("ogrenilmis_kabuller"),
        bilinen_terimler=ek.get("bilinen_terimler"),
    )


def _siralama_stratejisi(tanima, soru, gomlemci, ayar, referans_pasajlari, ek):
    return siralama_puanla(tanima.metin, soru)


def _eslestirme_stratejisi(tanima, soru, gomlemci, ayar, referans_pasajlari, ek):
    return eslestirme_puanla(tanima.metin, soru)


def _sayisal_stratejisi(tanima, soru, gomlemci, ayar, referans_pasajlari, ek):
    """Rubrik varsa yöntem payı hesaplanır, sonra sayısal/formül sonucu."""
    rubrik_sonucu = (
        rubrik_puanla(tanima.metin, soru, gomlemci, ayar, referans_pasajlari)
        if soru.anahtar.rubrik
        else None
    )
    if soru.tip == SoruTipi.FORMUL_ISPAT:
        return formul_puanla(tanima.metin, soru, rubrik_sonucu)
    return sayisal_puanla(tanima.metin, soru, rubrik_sonucu)


def _rubrik_stratejisi(tanima, soru, gomlemci, ayar, referans_pasajlari, ek):
    return rubrik_puanla(tanima.metin, soru, gomlemci, ayar, referans_pasajlari)


def _gorsel_stratejisi(tanima, soru, gomlemci, ayar, referans_pasajlari, ek):
    """Görsel cevaplar rubrikle puanlanır ama otomatik kesinleşemez."""
    sonuc = rubrik_puanla(tanima.metin, soru, gomlemci, ayar, referans_pasajlari)
    return gorsel_cevap_kapisi(sonuc, soru.tip)


# Soru tipi → puanlama stratejisi. Yeni bir tip eklemek için buraya giriş
# yapmak yeterlidir; `puanla`nın gövdesi değişmez.
PUANLAYICILAR: dict[SoruTipi, Callable] = {
    SoruTipi.BOSLUK_DOLDURMA: _bosluk_stratejisi,
    SoruTipi.COKTAN_SECMELI: _bosluk_stratejisi,
    SoruTipi.SIRALAMA: _siralama_stratejisi,
    SoruTipi.ESLESTIRME: _eslestirme_stratejisi,
    SoruTipi.SAYISAL: _sayisal_stratejisi,
    SoruTipi.FORMUL_ISPAT: _sayisal_stratejisi,
    SoruTipi.GRAFIK: _gorsel_stratejisi,
    SoruTipi.CIZIM: _gorsel_stratejisi,
    SoruTipi.TABLO: _gorsel_stratejisi,
    SoruTipi.ACIK_UCLU: _rubrik_stratejisi,
    SoruTipi.KISA_CEVAP: _rubrik_stratejisi,
    SoruTipi.DENEY_TASARLAMA: _rubrik_stratejisi,
    SoruTipi.YORUMLAMA: _rubrik_stratejisi,
    SoruTipi.ETIK: _rubrik_stratejisi,
}


def puanlayici_kaydet(tip: SoruTipi, strateji) -> None:
    """Bir soru tipi için puanlama stratejisini değiştirir/ekler."""
    PUANLAYICILAR[SoruTipi(tip)] = strateji


def puanlayici_coz(tip: SoruTipi):
    """Tipin stratejisi; kayıtlı değilse rubrik stratejisine düşer."""
    return PUANLAYICILAR.get(SoruTipi(tip), _rubrik_stratejisi)


def puanla(
    tanima: TanimaSonucu | str,
    soru: Soru,
    gomlemci: Gomlemci | None = None,
    ayar: PuanlamaAyar | None = None,
    referans_pasajlari: list[str] | None = None,
    ogrenilmis_kabuller: list[str] | None = None,
    bilinen_terimler: set[str] | None = None,
) -> PuanSonucu:
    """Tanınan cevabı soru tipine göre puanlar; HTR güvenini incele kararına katar.

    ``referans_pasajlari`` verilirse (o sorunun ders kitabındaki karşılığı),
    rubrikli sorularda referanslı tespit devreye girer.
    ``bilinen_terimler`` verilirse boşluk doldurmada rakip terim kapısı
    çalışır: iki gerçek terime eşit yakın bir yazım tam puan almaz.
    """
    ayar = ayar or PuanlamaAyar()
    if isinstance(tanima, str):
        tanima = TanimaSonucu(metin=tanima)

    if not soru.anahtar.otomatik_puanlama:
        ayrinti = (
            soru.anahtar.uyari
            or "Cevap anahtarı otomatik puanlama için doğrulanmadı."
        )
        return PuanSonucu(
            0.0,
            soru.puan,
            0.0,
            [f"⚠ Otomatik puanlama kapalı: {ayrinti}"],
            incele=True,
        )

    strateji = puanlayici_coz(soru.tip)
    sonuc = strateji(
        tanima, soru, gomlemci, ayar, referans_pasajlari,
        {
            "ogrenilmis_kabuller": ogrenilmis_kabuller or [],
            "bilinen_terimler": bilinen_terimler,
        },
    )

    # HTR güveni düşükse metnin kendisi şüpheli demektir → her durumda incele
    if tanima.metin.strip() and tanima.guven < ayar.tanima_guven_esigi:
        sonuc.incele = True
        sonuc.guven = min(sonuc.guven, tanima.guven)
        sonuc.detaylar.append(f"⚠ HTR güveni düşük ({tanima.guven:.2f})")
    if len(tanima.alternatifler) > 1:
        sonuc.detaylar.append(
            f"OCR uzlaşması: {len(tanima.alternatifler)} farklı okuma adayı "
            "karşılaştırıldı."
        )
    if tanima.motor_sonuclari or tanima.model_surumu:
        sonuc.detaylar.append(
            "OCR kanıtı: "
            f"{tanima.bagimsiz_motor_sayisi} bağımsız motor · "
            f"uzlaşma %{tanima.uzlasma_guveni * 100:.0f} · "
            f"karar marjı %{tanima.karar_marji * 100:.0f}."
        )
    if soru.anahtar.otomatik_uretildi and soru.anahtar.onay_durumu != "onayli":
        sonuc.incele = True
        sonuc.detaylar.append(
            "Otomatik RAG rubriği henüz öğretmen tarafından anahtar olarak onaylanmadı."
        )
    sonuc.tanima_guveni = float(tanima.guven)
    sonuc.puanlama_guveni = float(sonuc.guven)
    sonuc.risk = max(
        float(sonuc.risk),
        1.0 - float(sonuc.guven),
        1.0 - float(tanima.guven) if tanima.metin.strip() else 0.0,
    )
    return sonuc
