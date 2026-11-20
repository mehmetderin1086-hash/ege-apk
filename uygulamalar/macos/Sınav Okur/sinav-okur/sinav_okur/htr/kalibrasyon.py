"""OCR güvenlerini gerçek doğruluk olasılığına kalibre etme araçları.

Ham OCR güveni, farklı motorlarda aynı anlama gelmez. Bu küçük Platt ölçekleyici
öğretmen tarafından doğrulanmış bir kalibrasyon kümesinde eğitilip JSON olarak
saklanabilir. Üretimde etiket öğrenmez; yalnız önceden doğrulanmış parametreyi
uygular.
"""

from __future__ import annotations

import json
import math
from dataclasses import asdict, dataclass
from pathlib import Path

import numpy as np


def _logit(deger: np.ndarray) -> np.ndarray:
    p = np.clip(deger.astype(float), 1e-5, 1 - 1e-5)
    return np.log(p / (1 - p))


def _sigmoid(deger: np.ndarray) -> np.ndarray:
    deger = np.clip(deger, -35, 35)
    return 1.0 / (1.0 + np.exp(-deger))


@dataclass
class GuvenKalibrasyonu:
    """Tek değişkenli, sürümlenebilir Platt güven kalibrasyonu."""

    egim: float = 1.0
    kesme: float = -0.35
    egitildi: bool = False
    ornek_sayisi: int = 0
    surum: str = "muhafazakar-v1"

    def olasilik(self, ham_guven: float) -> float:
        x = float(_logit(np.asarray([ham_guven]))[0])
        return float(1.0 / (1.0 + math.exp(-max(-35, min(35, self.egim * x + self.kesme)))))

    def egit(
        self,
        ham_guvenler: list[float],
        dogru_etiketleri: list[int | bool],
        *,
        adim: float = 0.04,
        tur: int = 1200,
    ) -> "GuvenKalibrasyonu":
        if len(ham_guvenler) != len(dogru_etiketleri):
            raise ValueError("Güven ve etiket sayıları eşit olmalı.")
        if len(ham_guvenler) < 20:
            raise ValueError("Kalibrasyon için en az 20 doğrulanmış örnek gerekli.")
        y = np.asarray(dogru_etiketleri, dtype=float)
        if len(np.unique(y)) < 2:
            raise ValueError("Kalibrasyon kümesinde doğru ve yanlış örnek bulunmalı.")
        x = _logit(np.asarray(ham_guvenler, dtype=float))
        a, b = 1.0, 0.0
        for _ in range(max(1, int(tur))):
            p = _sigmoid(a * x + b)
            hata = p - y
            # Hafif L2, küçük kalibrasyon kümelerinde aşırı uyumu sınırlar.
            a -= adim * (float(np.mean(hata * x)) + 0.002 * a)
            b -= adim * float(np.mean(hata))
        self.egim = float(a)
        self.kesme = float(b)
        self.egitildi = True
        self.ornek_sayisi = len(y)
        self.surum = "platt-v1"
        return self

    def metrikler(
        self, ham_guvenler: list[float], dogru_etiketleri: list[int | bool]
    ) -> dict[str, float]:
        y = np.asarray(dogru_etiketleri, dtype=float)
        p = np.asarray([self.olasilik(x) for x in ham_guvenler])
        brier = float(np.mean((p - y) ** 2)) if len(y) else 0.0
        ece = 0.0
        for alt in np.linspace(0, 0.9, 10):
            maske = (p >= alt) & (p < alt + 0.1)
            if np.any(maske):
                ece += float(np.mean(maske)) * abs(
                    float(np.mean(p[maske])) - float(np.mean(y[maske]))
                )
        return {"brier": round(brier, 6), "ece": round(ece, 6)}

    def kaydet(self, yol: str | Path) -> None:
        Path(yol).write_text(
            json.dumps(asdict(self), ensure_ascii=False, indent=2),
            encoding="utf-8",
        )

    @classmethod
    def yukle(cls, yol: str | Path) -> "GuvenKalibrasyonu":
        veri = json.loads(Path(yol).read_text(encoding="utf-8"))
        # Koşullu dosya biçimi de tek eğri olarak okunabilsin (geriye uyum).
        if "genel" in veri:
            veri = veri["genel"]
        return cls(**{k: v for k, v in veri.items() if k in cls.__dataclass_fields__})


# --- Koşullu (dilimli) kalibrasyon --------------------------------------

# Kanıt koşulu dilimleri: aynı ham güven, iki bağımsız motorun anlaştığı
# temiz bir kutuda tek motorun tahmininden çok daha anlamlıdır. Dilim
# başına ayrı eğri bu farkı kalibrasyona taşır.
MOTOR_BANTLARI = ("motor1", "motor2", "motor3+")
# Dilim sütunları yazılmadan önce kaydedilmiş satırlar; dilim eğrisi
# eğitilmez, genel eğriye bırakılır.
DILIM_BILINMIYOR = "bilinmiyor"
KALITE_BANTLARI = ("kalite_dusuk", "kalite_iyi")
# Girdi kalitesi bandı sınırı; guvenlik_kapisi.ASGARI_GIRDI_KALITESI ile aynı.
KALITE_SINIRI = 0.62
# Dilimin kendi eğrisine güvenmek için gereken asgari örnek.
DILIM_ASGARI_ORNEK = 20
# Shrinkage yumuşatma sabiti: w = n / (n + SHRINKAGE_SABITI)
SHRINKAGE_SABITI = 30.0


def dilim_anahtari(bagimsiz_motor: int, girdi_kalitesi: float) -> str:
    """(motor bandı × kalite bandı) dilim anahtarı."""
    sayi = int(bagimsiz_motor or 0)
    motor = MOTOR_BANTLARI[0] if sayi <= 1 else (
        MOTOR_BANTLARI[1] if sayi == 2 else MOTOR_BANTLARI[2]
    )
    kalite = (
        KALITE_BANTLARI[1]
        if float(girdi_kalitesi or 0.0) >= KALITE_SINIRI
        else KALITE_BANTLARI[0]
    )
    return f"{motor}/{kalite}"


@dataclass
class KosulluGuvenKalibrasyonu:
    """Genel eğri + kanıt dilimi başına shrinkage'lı Platt eğrileri."""

    genel: GuvenKalibrasyonu = None  # type: ignore[assignment]
    dilimler: dict[str, GuvenKalibrasyonu] = None  # type: ignore[assignment]

    def __post_init__(self) -> None:
        if self.genel is None:
            self.genel = GuvenKalibrasyonu()
        if self.dilimler is None:
            self.dilimler = {}

    @property
    def egitildi(self) -> bool:
        return bool(self.genel.egitildi)

    def olasilik(self, ham_guven: float, dilim: str | None = None) -> float:
        egri = self.dilimler.get(dilim or "", self.genel)
        return egri.olasilik(ham_guven)

    def egit_dilimli(
        self,
        ham_guvenler: list[float],
        dogru_etiketleri: list[int | bool],
        dilimler: list[str],
    ) -> "KosulluGuvenKalibrasyonu":
        """Genel eğriyi ve her dilimin eğrisini eğitir (logit uzayında shrinkage).

        Az örnekli dilim genele yaklaşır; böylece veri açlığı çeken bir
        dilim kendi gürültüsüne aşırı uymaz.
        """
        self.genel = GuvenKalibrasyonu().egit(ham_guvenler, dogru_etiketleri)
        gruplar: dict[str, tuple[list[float], list[int]]] = {}
        for guven, etiket, dilim in zip(ham_guvenler, dogru_etiketleri, dilimler):
            gruplar.setdefault(dilim, ([], []))
            gruplar[dilim][0].append(float(guven))
            gruplar[dilim][1].append(int(etiket))
        yeni_dilimler: dict[str, GuvenKalibrasyonu] = {}
        for dilim, (guvenler, etiketler) in gruplar.items():
            if dilim == DILIM_BILINMIYOR:
                continue  # kanıt koşulu bilinmiyor; genel eğri kullanılır
            if len(guvenler) < DILIM_ASGARI_ORNEK or len(set(etiketler)) < 2:
                continue
            try:
                ham_egri = GuvenKalibrasyonu().egit(guvenler, etiketler)
            except ValueError:
                continue
            agirlik = len(guvenler) / (len(guvenler) + SHRINKAGE_SABITI)
            yeni_dilimler[dilim] = GuvenKalibrasyonu(
                egim=agirlik * ham_egri.egim + (1 - agirlik) * self.genel.egim,
                kesme=agirlik * ham_egri.kesme + (1 - agirlik) * self.genel.kesme,
                egitildi=True,
                ornek_sayisi=len(guvenler),
                surum="platt-dilim-v1",
            )
        self.dilimler = yeni_dilimler
        return self

    def metrikler(
        self,
        ham_guvenler: list[float],
        dogru_etiketleri: list[int | bool],
        dilimler: list[str] | None = None,
    ) -> dict[str, float]:
        """Dilim seçimini de hesaba katan Brier/ECE."""
        if dilimler is None:
            return self.genel.metrikler(ham_guvenler, dogru_etiketleri)
        y = np.asarray(dogru_etiketleri, dtype=float)
        p = np.asarray(
            [
                self.olasilik(guven, dilim)
                for guven, dilim in zip(ham_guvenler, dilimler)
            ]
        )
        brier = float(np.mean((p - y) ** 2)) if len(y) else 0.0
        ece = 0.0
        for alt in np.linspace(0, 0.9, 10):
            maske = (p >= alt) & (p < alt + 0.1)
            if np.any(maske):
                ece += float(np.mean(maske)) * abs(
                    float(np.mean(p[maske])) - float(np.mean(y[maske]))
                )
        return {"brier": round(brier, 6), "ece": round(ece, 6)}

    def kaydet(self, yol: str | Path) -> None:
        Path(yol).write_text(
            json.dumps(
                {
                    "genel": asdict(self.genel),
                    "dilimler": {k: asdict(v) for k, v in self.dilimler.items()},
                },
                ensure_ascii=False,
                indent=2,
            ),
            encoding="utf-8",
        )

    @classmethod
    def yukle(cls, yol: str | Path) -> "KosulluGuvenKalibrasyonu":
        """Hem koşullu hem eski düz JSON biçimini okur."""
        veri = json.loads(Path(yol).read_text(encoding="utf-8"))
        if "genel" not in veri:
            # Eski düz dosya: tek eğri, dilim yok.
            return cls(genel=GuvenKalibrasyonu(**veri), dilimler={})
        alanlar = GuvenKalibrasyonu.__dataclass_fields__
        return cls(
            genel=GuvenKalibrasyonu(
                **{k: v for k, v in veri["genel"].items() if k in alanlar}
            ),
            dilimler={
                ad: GuvenKalibrasyonu(
                    **{k: v for k, v in egri.items() if k in alanlar}
                )
                for ad, egri in (veri.get("dilimler") or {}).items()
            },
        )

