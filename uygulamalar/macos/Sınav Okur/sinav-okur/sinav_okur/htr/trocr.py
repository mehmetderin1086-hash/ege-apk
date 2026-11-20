"""TrOCR tabanlı satır-düzeyi tanıyıcı.

Varsayılan model İngilizce el yazısıyla eğitilmiştir; Türkçe için
``colab/08_trocr_tek_gecis.ipynb`` ile ince ayar yapılmış model dizinini verin.
Güven, üretilen token'ların ortalama olasılığından hesaplanır — düşük güvenli
cevaplar arayüzde insan onayına düşer.
"""

from __future__ import annotations

import os
from pathlib import Path

import numpy as np

from ..metin import nfc
from ..modeller import TanimaSonucu
from ..tarama.satir import satirlara_bol

VARSAYILAN_MODEL = "microsoft/trocr-base-handwritten"


def yerel_model_yolu(kok: Path | None = None) -> str | None:
    """İnce ayarlı Türkçe TrOCR modelinin yolunu bul.

    Öncelik: ``SINAV_OKUR_TROCR_MODEL`` ortam değişkeni, sonra proje kökündeki
    ``modeller/trocr-tr`` dizini. İkisi de yoksa ``None`` döner (İngilizce
    taban model kullanılır).
    """
    ozel = os.environ.get("SINAV_OKUR_TROCR_MODEL")
    if ozel:
        return ozel
    kok = kok or Path(__file__).resolve().parents[2]
    aday = kok / "modeller" / "trocr-tr"
    if (aday / "config.json").is_file():
        return str(aday)
    return None


class TrocrTaniyici:
    def __init__(self, model_yolu: str = VARSAYILAN_MODEL, cihaz: str | None = None):
        import torch
        from transformers import TrOCRProcessor, VisionEncoderDecoderModel

        self._torch = torch
        self.model_yolu = model_yolu
        if cihaz is None:
            cihaz = "mps" if torch.backends.mps.is_available() else "cpu"
        self.cihaz = cihaz
        self.device = cihaz
        # Eğitimin kaydedildiği yavaş görüntü işlemcisini açıkça seçerek
        # Transformers sürüm yükseltmelerinde ön işleme davranışını sabit tut.
        self.islemci = TrOCRProcessor.from_pretrained(model_yolu, use_fast=False)
        self.model = VisionEncoderDecoderModel.from_pretrained(model_yolu).to(cihaz).eval()

    def _satir_taniy(self, satir_bgr: np.ndarray) -> TanimaSonucu:
        torch = self._torch
        rgb = satir_bgr[..., ::-1].copy() if satir_bgr.ndim == 3 else np.stack([satir_bgr] * 3, -1)
        girdi = self.islemci(images=rgb, return_tensors="pt").pixel_values.to(self.cihaz)
        with torch.no_grad():
            cikti = self.model.generate(
                girdi,
                max_new_tokens=96,
                num_beams=3,
                num_return_sequences=2,
                early_stopping=True,
                output_scores=True,
                return_dict_in_generate=True,
            )
        metinler = self.islemci.batch_decode(
            cikti.sequences, skip_special_tokens=True
        )
        guvenler: list[float] = []
        try:
            gecis = self.model.compute_transition_scores(
                cikti.sequences,
                cikti.scores,
                cikti.beam_indices,
                normalize_logits=True,
            )
            for satir in gecis:
                gecerli = satir[satir < 0]
                guvenler.append(
                    float(torch.exp(gecerli.mean()).item()) if len(gecerli) else 0.5
                )
        except (AttributeError, RuntimeError, ValueError):
            guvenler = [0.5 for _ in metinler]
        while len(guvenler) < len(metinler):
            guvenler.append(0.5)
        alternatifler = [
            {"metin": nfc(m.strip()), "guven": g, "destek": 1}
            for m, g in zip(metinler, guvenler)
            if m.strip()
        ]
        metin = alternatifler[0]["metin"] if alternatifler else ""
        guven = alternatifler[0]["guven"] if alternatifler else 0.0
        ikinci = alternatifler[1]["guven"] if len(alternatifler) > 1 else 0.0
        return TanimaSonucu(
            metin=metin,
            guven=guven,
            alternatifler=alternatifler,
            uzlasma_guveni=(
                1.0 if len(alternatifler) < 2 or alternatifler[0]["metin"] == alternatifler[1]["metin"]
                else 0.0
            ),
            bagimsiz_motor_sayisi=1,
            karar_marji=max(0.0, guven - ikinci),
            belirsizlik_nedeni="Yalnız TrOCR sonucu var.",
            model_surumu={
                "boru_hatti": "siyah-kursun-v2",
                "motorlar": [{"ad": "trocr", "model_yolu": self.model_yolu, "aygit": self.cihaz}],
            },
        )

    def kutu_taniy(self, kirp: np.ndarray, dpi: int = 300) -> TanimaSonucu:
        satirlar = satirlara_bol(kirp, dpi)
        if not satirlar:
            return TanimaSonucu(metin="", guven=0.0)
        sonuclar = [self._satir_taniy(s) for s in satirlar]
        metin = "\n".join(s.metin for s in sonuclar if s.metin)
        guven = float(min(s.guven for s in sonuclar))
        return TanimaSonucu(metin=metin, guven=guven)
