"""macOS Apple Vision tabanlı kutu-düzeyi Türkçe metin tanıyıcı."""

from __future__ import annotations

import tempfile
from pathlib import Path

import cv2
import numpy as np
from rapidfuzz import fuzz

from ..metin import nfc
from ..modeller import TanimaSonucu


class VisionTaniyici:
    """Yerel Apple Vision OCR ile cevap kırpıntısındaki satırları okur."""

    def __init__(self, arac_dizini: str | Path | None = None):
        proje_koku = Path(__file__).resolve().parents[2]
        self.arac_dizini = Path(arac_dizini or proje_koku / ".ocr-tools")

    def kutu_taniy(self, kirp: np.ndarray, dpi: int = 300) -> TanimaSonucu:
        return self.kutu_taniy_baglamli(kirp, dpi, [])

    def kutu_taniy_baglamli(
        self,
        kirp: np.ndarray,
        dpi: int = 300,
        baglam: list[str] | None = None,
    ) -> TanimaSonucu:
        """Rubrik terimlerini Vision'a özel sözcük olarak vererek HTR hatasını azalt."""
        # ``vision_ocr`` dosya yolu kabul ediyor; geçici görüntü her koşulda
        # silinir ve sınav verisi kalıcı araç dizinine kopyalanmaz.
        gecici = tempfile.NamedTemporaryFile(
            prefix="sinav-okur-vision-", suffix=".png", delete=False
        )
        gecici.close()
        gecici_yolu = Path(gecici.name)
        try:
            if not cv2.imwrite(str(gecici_yolu), kirp):
                return TanimaSonucu(metin="", guven=0.0)
            # Döngüsel modül yüklemesini önlemek için çalışma anında içe aktar.
            from ..serbest import vision_ocr

            kelimeler = []
            for ifade in baglam or []:
                kelimeler.extend(
                    k.strip(".,;:()[]{}!?\"'").lower()
                    for k in str(ifade).split()
                    if len(k.strip(".,;:()[]{}!?\"'")) >= 4
                )
            ozel_kelimeler = list(dict.fromkeys(kelimeler))[:160]
            bloklar = (
                vision_ocr(gecici_yolu, self.arac_dizini, ozel_kelimeler)
                if ozel_kelimeler
                else vision_ocr(gecici_yolu, self.arac_dizini)
            )
        finally:
            gecici_yolu.unlink(missing_ok=True)
        if not bloklar:
            return TanimaSonucu(metin="", guven=0.0)
        sirali = sorted(bloklar, key=lambda b: (b.y, b.x))
        metin = "\n".join(b.text.strip() for b in sirali if b.text.strip())
        if not metin:
            return TanimaSonucu(metin="", guven=0.0)
        guven = float(np.mean([b.confidence for b in sirali]))
        alternatifler = [{"metin": nfc(metin), "guven": guven, "destek": 1}]
        azami_aday = max(
            (len(getattr(b, "alternatives", [])) for b in sirali),
            default=0,
        )
        for sira in range(azami_aday):
            satirlar, guvenler = [], []
            for b in sirali:
                blok_adaylari = getattr(b, "alternatives", [])
                if sira < len(blok_adaylari):
                    aday = blok_adaylari[sira]
                    satirlar.append(str(aday.get("metin", b.text)))
                    guvenler.append(float(aday.get("guven", b.confidence)))
                else:
                    satirlar.append(b.text)
                    guvenler.append(float(b.confidence))
            aday_metni = nfc("\n".join(satirlar))
            if aday_metni != nfc(metin):
                alternatifler.append(
                    {
                        "metin": aday_metni,
                        "guven": float(np.mean(guvenler)),
                        "destek": 1,
                    }
                )
        ikinci = alternatifler[1]["guven"] if len(alternatifler) > 1 else 0.0
        uzlasma = (
            fuzz.ratio(metin.casefold(), alternatifler[1]["metin"].casefold()) / 100
            if len(alternatifler) > 1
            else 1.0
        )
        return TanimaSonucu(
            metin=nfc(metin),
            guven=max(0.0, min(1.0, guven)),
            alternatifler=alternatifler,
            uzlasma_guveni=float(uzlasma),
            bagimsiz_motor_sayisi=1,
            karar_marji=max(0.0, guven - float(ikinci)),
            belirsizlik_nedeni="Yalnız Apple Vision OCR sonucu var.",
            model_surumu={
                "boru_hatti": "siyah-kursun-v2",
                "motorlar": [{"ad": "apple-vision", "sinif": "Vision VNRecognizeTextRequest"}],
            },
        )
