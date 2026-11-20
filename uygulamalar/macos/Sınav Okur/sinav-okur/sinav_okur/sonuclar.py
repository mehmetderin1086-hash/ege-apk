"""Kâğıt işleme hattının ortak sonuç veri yapıları.

Bu modeller belirli bir form düzenine bağlı değildir. Serbest düzenli, 1–4
sayfalık yazılıların OCR, puanlama ve inceleme sonuçlarını depo katmanına taşır.
"""

from __future__ import annotations

from dataclasses import dataclass, field

from .modeller import PuanSonucu, TanimaSonucu


@dataclass
class KutuSonucu:
    soru_no: int
    tanima: TanimaSonucu
    puan: PuanSonucu
    kirp_yolu: str | None = None
    kalite: dict = field(default_factory=dict)
    # Alan sözlüğünün OCR metninde yaptığı düzeltmeler ({onceki, sonraki}).
    sozluk_duzeltmeleri: list[dict] = field(default_factory=list)


@dataclass
class KagitSonucu:
    sinav_kimlik: str
    islenen_sayfalar: list[int]
    kutular: list[KutuSonucu] = field(default_factory=list)
    uyarilar: list[str] = field(default_factory=list)
    kimlik_bilgileri: dict = field(default_factory=dict)
    kalite_raporu: list[dict] = field(default_factory=list)
    sayfa_eslesmeleri: list[dict] = field(default_factory=list)

    @property
    def toplam_puan(self) -> float:
        return sum(k.puan.puan for k in self.kutular)

    @property
    def max_puan(self) -> float:
        return sum(k.puan.max_puan for k in self.kutular)
