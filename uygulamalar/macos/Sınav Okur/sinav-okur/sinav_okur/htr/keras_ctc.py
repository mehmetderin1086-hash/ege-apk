"""Gerçek satır görüntüleriyle eğitilen Keras CNN-BiLSTM-CTC tanıyıcı."""

from __future__ import annotations

import json
from pathlib import Path

import cv2
import numpy as np

from ..metin import nfc
from ..modeller import TanimaSonucu
from ..tarama.satir import satirlara_bol
from .keras_cnn import _softmax


def _satir_girdisi(gri: np.ndarray, yukseklik: int = 64, genislik: int = 1024) -> np.ndarray:
    """Oranı koru, sağa beyaz dolgu yap ve mürekkebi 1 yönüne normalize et."""
    h, w = gri.shape[:2]
    olcek = min(yukseklik / max(h, 1), genislik / max(w, 1))
    nw, nh = max(1, round(w * olcek)), max(1, round(h * olcek))
    kucuk = cv2.resize(gri, (nw, nh), interpolation=cv2.INTER_AREA)
    tuval = np.full((yukseklik, genislik), 255, dtype=np.uint8)
    y = (yukseklik - nh) // 2
    tuval[y:y + nh, :nw] = kucuk
    return (1.0 - tuval.astype(np.float32) / 255.0)[..., None]


class KerasCtcTaniyici:
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
                raise ValueError("Keras CTC model yolu gerekli")
            try:
                from tensorflow import keras
            except ImportError as e:
                raise ImportError(
                    "Keras CTC için TensorFlow gerekli: uv sync --extra keras"
                ) from e
            model = keras.models.load_model(model_yolu, compile=False)
        self.model = model
        if etiketler is None:
            if etiket_yolu is None:
                if model_yolu is None:
                    raise ValueError("CTC etiket dosyası gerekli")
                etiket_yolu = Path(model_yolu).with_name("ctc_etiketler.json")
            etiketler = json.loads(Path(etiket_yolu).read_text(encoding="utf-8"))
        self.etiketler = [str(x) for x in etiketler]
        self.blank = len(self.etiketler)
        cikti_boyutu = getattr(self.model, "output_shape", None)
        if cikti_boyutu is not None:
            if isinstance(cikti_boyutu, list):
                if len(cikti_boyutu) != 1:
                    raise ValueError("Keras CTC modeli tek çıktı üretmeli")
                cikti_boyutu = cikti_boyutu[0]
            sinif_sayisi = cikti_boyutu[-1]
            beklenen = len(self.etiketler) + 1
            if sinif_sayisi is not None and int(sinif_sayisi) != beklenen:
                raise ValueError(
                    "CTC model/etiket uyuşmazlığı: "
                    f"model {int(sinif_sayisi)} sınıf, etiketler+blank "
                    f"{beklenen} sınıf gerektiriyor"
                )
        self.kabul_esigi = kabul_esigi
        if self.kabul_esigi is None and model_yolu is not None:
            metrik_yolu = Path(model_yolu).with_name("ctc_metrikleri.json")
            if metrik_yolu.exists():
                try:
                    metrikler = json.loads(metrik_yolu.read_text(encoding="utf-8"))
                    secici = metrikler.get("auto_accept_99")
                    if secici:
                        self.kabul_esigi = float(secici["threshold"])
                except (OSError, ValueError, TypeError, KeyError, json.JSONDecodeError):
                    pass

    def _coz(self, cikti: np.ndarray) -> TanimaSonucu:
        olasilik = _softmax(cikti)
        yol = olasilik.argmax(axis=-1)
        onceki, karakterler, gucler = None, [], []
        for t, indeks in enumerate(yol):
            indeks = int(indeks)
            if indeks != self.blank and indeks != onceki and indeks < len(self.etiketler):
                karakterler.append(self.etiketler[indeks])
                gucler.append(float(olasilik[t, indeks]))
            onceki = indeks
        guven = float(np.mean(gucler)) if gucler else 0.0
        if self.kabul_esigi is not None and guven < self.kabul_esigi:
            # Puanlama katmanının varsayılan 0.75 kapısını kesin olarak geçmesin.
            # Eşik, görülmemiş yazarlardan ayrılan test kümesinde <=%1 CER için
            # 06_keras_ctc_gercek_satir.ipynb tarafından kalibre edilir.
            guven = min(guven, 0.74)
        return TanimaSonucu(nfc("".join(karakterler).strip()), guven)

    def _satir_taniy(self, satir: np.ndarray) -> TanimaSonucu:
        gri = cv2.cvtColor(satir, cv2.COLOR_BGR2GRAY) if satir.ndim == 3 else satir
        cikti = np.asarray(self.model.predict(_satir_girdisi(gri)[None, ...], verbose=0))
        if cikti.ndim != 3 or cikti.shape[0] != 1:
            raise ValueError(f"CTC model çıktısı [1,zaman,sınıf] olmalı: {cikti.shape}")
        return self._coz(cikti[0])

    def kutu_taniy(self, kirp: np.ndarray, dpi: int = 300) -> TanimaSonucu:
        satirlar = satirlara_bol(kirp, dpi)
        if not satirlar:
            return TanimaSonucu("", 1.0)
        sonuclar = [self._satir_taniy(s) for s in satirlar]
        return TanimaSonucu(
            "\n".join(s.metin for s in sonuclar if s.metin),
            min(s.guven for s in sonuclar),
        )
