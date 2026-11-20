"""Keras karakter CNN'i için temkinli, ayrık-yazı tanıyıcı.

Bu backend yalnız birbirinden ayrılabilen karakterlerde güvenilirdir. Geniş,
birleşik bileşen gördüğünde güveni düşürür; bağlı el yazısında asıl yol
``KerasCtcTaniyici`` olmalıdır.
"""

from __future__ import annotations

import json
from pathlib import Path

import cv2
import numpy as np

from ..metin import nfc
from ..modeller import TanimaSonucu
from ..tarama.satir import satirlara_bol


def _softmax(x: np.ndarray) -> np.ndarray:
    x = np.asarray(x, dtype=np.float64)
    if np.all(x >= 0) and np.all(x <= 1) and np.allclose(x.sum(-1), 1, atol=1e-3):
        return x
    x = x - x.max(axis=-1, keepdims=True)
    e = np.exp(x)
    return e / e.sum(axis=-1, keepdims=True)


def _etiketleri_yukle(yol: str | Path) -> list[str]:
    veri = json.loads(Path(yol).read_text(encoding="utf-8"))
    if isinstance(veri, list):
        return [str(x) for x in veri]
    if isinstance(veri, dict):
        return [str(veri[str(i)] if str(i) in veri else veri[i]) for i in range(len(veri))]
    raise ValueError("Etiket dosyası JSON liste veya indeks→karakter sözlüğü olmalı")


def _karakter_girdisi(gri: np.ndarray) -> np.ndarray:
    """Tek bileşeni oranı koruyarak 28×28, koyu-zemin/parlak-mürekkep yap."""
    if gri.size == 0:
        return np.zeros((28, 28, 1), dtype=np.float32)
    _, ink = cv2.threshold(gri, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)
    ys, xs = np.where(ink > 0)
    if len(xs) == 0:
        return np.zeros((28, 28, 1), dtype=np.float32)
    ink = ink[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    # T-H-E Version VI glifleri 28×28 tuvalin büyük bölümünü kullanır. 24 piksel,
    # taranmış bileşenleri kaynak dağılıma yaklaştırırken dört piksellik güvenli
    # kenar payı bırakır.
    olcek = min(24 / max(ink.shape[1], 1), 24 / max(ink.shape[0], 1))
    yeni = (
        max(1, round(ink.shape[1] * olcek)),
        max(1, round(ink.shape[0] * olcek)),
    )
    ink = cv2.resize(ink, yeni, interpolation=cv2.INTER_AREA)
    tuval = np.zeros((28, 28), dtype=np.uint8)
    x = (28 - ink.shape[1]) // 2
    y = (28 - ink.shape[0]) // 2
    tuval[y:y + ink.shape[0], x:x + ink.shape[1]] = ink
    return (tuval.astype(np.float32) / 255.0)[..., None]


def _bilesen_kutulari(gri: np.ndarray) -> list[tuple[int, int, int, int]]:
    """Dikey izdüşümle nokta/aksanları taban harfle aynı kutuda tut.

    Bağlı bileşenleri doğrudan karakter saymak ``ç, ğ, i, ö, ş, ü`` gibi ayrı
    nokta/aksan parçaları olan glifleri iki-üç harfe böler. Bunun yerine mürekkep
    bulunan sütunları kullanır, çok dar iç boşlukları kapatır ve yalnız gerçek
    yatay aralıkları karakter sınırı kabul eder.
    """
    _, ikili = cv2.threshold(gri, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)
    n, bilesenler, ist, _ = cv2.connectedComponentsWithStats(ikili, 8)
    h, w = gri.shape[:2]
    asgari = max(2, round(h * w * 0.00008))
    temiz = np.zeros_like(ikili)
    for i in range(1, n):
        if int(ist[i, cv2.CC_STAT_AREA]) >= asgari:
            temiz[bilesenler == i] = 255
    aktif = np.flatnonzero(np.any(temiz > 0, axis=0))
    if len(aktif) == 0:
        return []

    azami_ic_bosluk = max(1, round(h * 0.07))
    sinirlar = np.flatnonzero(np.diff(aktif) > azami_ic_bosluk + 1)
    baslangiclar = np.r_[0, sinirlar + 1]
    bitisler = np.r_[sinirlar, len(aktif) - 1]
    kutular = []
    for bas, bit in zip(baslangiclar, bitisler):
        x0, x1 = int(aktif[bas]), int(aktif[bit])
        ys = np.flatnonzero(np.any(temiz[:, x0:x1 + 1] > 0, axis=1))
        if len(ys):
            y0, y1 = int(ys[0]), int(ys[-1])
            kutular.append((x0, y0, x1 - x0 + 1, y1 - y0 + 1))
    return kutular


class KerasKarakterTaniyici:
    def __init__(
        self,
        model_yolu: str | Path | None = None,
        etiket_yolu: str | Path | None = None,
        *,
        model=None,
        etiketler: list[str] | None = None,
        kabul_esigi: float | None = None,
    ):
        if model is None:
            if model_yolu is None:
                raise ValueError("Keras karakter modeli yolu gerekli")
            try:
                from tensorflow import keras
            except ImportError as e:
                raise ImportError(
                    "Keras CNN için TensorFlow gerekli: uv sync --extra keras"
                ) from e
            model = keras.models.load_model(model_yolu)
        self.model = model
        if etiketler is None:
            if etiket_yolu is None:
                if model_yolu is None:
                    raise ValueError("Etiket dosyası gerekli")
                etiket_yolu = Path(model_yolu).with_name("etiketler.json")
            etiketler = _etiketleri_yukle(etiket_yolu)
        self.etiketler = etiketler
        cikti_boyutu = getattr(self.model, "output_shape", None)
        if cikti_boyutu is not None:
            if isinstance(cikti_boyutu, list):
                if len(cikti_boyutu) != 1:
                    raise ValueError("Keras karakter modeli tek çıktı üretmeli")
                cikti_boyutu = cikti_boyutu[0]
            sinif_sayisi = cikti_boyutu[-1]
            if sinif_sayisi is not None and int(sinif_sayisi) != len(self.etiketler):
                raise ValueError(
                    "Model/etiket uyuşmazlığı: "
                    f"model {int(sinif_sayisi)} sınıf, etiket dosyası "
                    f"{len(self.etiketler)} sınıf içeriyor"
                )
        self.kabul_esigi = kabul_esigi
        if self.kabul_esigi is None and model_yolu is not None:
            kok = Path(model_yolu).parent
            for ad in ("casefold_metrikleri.json", "karakter_metrikleri.json"):
                metrik = kok / ad
                if not metrik.exists():
                    continue
                try:
                    veri = json.loads(metrik.read_text(encoding="utf-8"))
                    secici = veri.get("selective", {}).get("0.99")
                    if secici:
                        self.kabul_esigi = float(secici["threshold"])
                        break
                except (OSError, ValueError, TypeError, KeyError, json.JSONDecodeError):
                    continue

    def _satir_taniy(self, satir: np.ndarray) -> TanimaSonucu:
        gri = cv2.cvtColor(satir, cv2.COLOR_BGR2GRAY) if satir.ndim == 3 else satir
        kutular = _bilesen_kutulari(gri)
        if not kutular:
            return TanimaSonucu("", 1.0)
        girdiler, riskli = [], False
        for x, y, w, h in kutular:
            pay = max(2, round(h * 0.08))
            kirp = gri[max(0, y - pay):min(gri.shape[0], y + h + pay),
                        max(0, x - pay):min(gri.shape[1], x + w + pay)]
            girdiler.append(_karakter_girdisi(kirp))
            if w > h * 1.25:
                riskli = True  # muhtemel bağlı/birleşik harf
        tahmin = self.model.predict(np.stack(girdiler), verbose=0)
        olasilik = _softmax(np.asarray(tahmin))
        indeksler = olasilik.argmax(axis=1)
        gucler = olasilik[np.arange(len(indeksler)), indeksler]

        genislikler = [w for _, _, w, _ in kutular]
        tipik = max(float(np.median(genislikler)), 1.0)
        metin = ""
        onceki_son = None
        for indeks, (x, _, w, _) in zip(indeksler, kutular):
            if onceki_son is not None and x - onceki_son > tipik * 1.15:
                metin += " "
            metin += self.etiketler[int(indeks)]
            onceki_son = x + w
        # Satırın otomatik kabulü en zayıf karakter kadar güvenlidir. Ortalama
        # kullanmak tek bir düşük-güvenli glifi gizleyebilir.
        guven = float(np.min(gucler))
        if self.kabul_esigi is not None and np.any(gucler < self.kabul_esigi):
            # Varsayılan puanlama kapısı 0.75'tir; kalibre eşik altındaki satırı
            # insan incelemesine kesin olarak gönder.
            guven = min(guven, 0.74)
        if riskli:
            guven = min(guven, 0.45)
        return TanimaSonucu(nfc(metin), guven)

    def kutu_taniy(self, kirp: np.ndarray, dpi: int = 300) -> TanimaSonucu:
        satirlar = satirlara_bol(kirp, dpi)
        if not satirlar:
            return TanimaSonucu("", 1.0)
        sonuclar = [self._satir_taniy(s) for s in satirlar]
        return TanimaSonucu(
            "\n".join(s.metin for s in sonuclar if s.metin),
            min(s.guven for s in sonuclar),
        )
