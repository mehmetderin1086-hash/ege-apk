"""Kademeli grounding'in ikinci basamağı: NLI (entailment) hakemi.

Kelime-eşleşme kapısı (answering._claim_supported) ucuz ve muhafazakârdır;
geçtiği iddia kabul edilir ve hakem HİÇ çağrılmaz. Geçemeyenler burada
"bu iddia bu kanıttan çıkar mı?" sorusuyla topluca yeniden yargılanır.
Çelişki ayrı bir kapıdır: entailment olasılığı eşiği aşsa bile çelişki
olasılığı yüksekse iddia reddedilir.

Model süreç içinde lazy yüklenir (CrossEncoderReranker deseni) ve
`birak()` ile bellek iade edilir — M4 16 GB'da LLM + NLI + XTTS aynı anda
sığmaz; TTS'e geçmeden önce LLM ile birlikte bu model de bırakılır.
"""

from __future__ import annotations

import gc
import threading
from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True)
class NliCift:
    """Tek bir yargı: iddia, dayandırıldığı kanıt ve eşik kaydırması.

    ``esik_kaydirma`` pozitifse karar eşiği o kadar yükselir; etiketi bizim
    taktığımız kurtarma yolunda kullanılır (atıf, filtreden daha yüksek
    güven ister).
    """

    iddia: str
    kanit: str
    esik_kaydirma: float = 0.0


class NLIVerifier:
    """Çok dilli NLI çapraz kodlayıcısı üstünde toplu entailment kararı."""

    def __init__(
        self,
        model_name: str = "MoritzLaurer/mDeBERTa-v3-base-mnli-xnli",
        *,
        esik: float = 0.8,
        karsi_esik: float = 0.35,
        parti_boyu: int = 16,
        azami_cift: int = 64,
        yalniz_yerel: bool = True,
    ) -> None:
        self.model_name = model_name
        self.esik = esik
        self.karsi_esik = karsi_esik
        self.parti_boyu = parti_boyu
        self.azami_cift = azami_cift
        self.yalniz_yerel = yalniz_yerel
        self._model: object | None = None
        self._tokenizer: object | None = None
        self._cihaz: str | None = None
        # RLock: toplu() tüm yargı boyunca kilidi tutar, birak() süren bir
        # yargının ortasında modeli elinden alamaz (16 GB'da XTTS yüklenirken
        # NLI'nın gerçekten bellekte olmaması bu sıralamaya dayanır).
        self._kilit = threading.RLock()

    # -- yükleme / bırakma -------------------------------------------------

    def _load(self) -> tuple[object, object, str]:
        with self._kilit:
            if self._model is None:
                import torch
                from transformers import (
                    AutoModelForSequenceClassification,
                    AutoTokenizer,
                )

                # local_files_only: yerel-öncelikli bir uygulamada ilk sorunun
                # arkasında habersiz ~1 GB'lık indirme başlatılmaz. Model yoksa
                # istisna fırlar; çağıran hakem yokmuş gibi kelime kapısına
                # düşer. İndirme bilinçli bir hazırlık adımıdır: `bioprof nli-esik`.
                tokenizer = AutoTokenizer.from_pretrained(
                    self.model_name, local_files_only=self.yalniz_yerel
                )
                model = AutoModelForSequenceClassification.from_pretrained(
                    self.model_name, local_files_only=self.yalniz_yerel
                )
                cihaz = "mps" if torch.backends.mps.is_available() else "cpu"
                model.to(cihaz)
                model.eval()
                self._tokenizer = tokenizer
                self._model = model
                self._cihaz = cihaz
            assert self._tokenizer is not None and self._cihaz is not None
            return self._model, self._tokenizer, self._cihaz

    def yuklu_mu(self) -> bool:
        return self._model is not None

    def birak(self) -> None:
        """Modeli bellekten çıkarır; bir sonraki çağrı yeniden yükler."""
        with self._kilit:
            if self._model is None:
                return
            self._model = None
            self._tokenizer = None
            self._cihaz = None
        gc.collect()
        try:
            import torch

            if torch.backends.mps.is_available():
                torch.mps.empty_cache()
        except Exception:  # noqa: BLE001 - bırakma en iyi çabadır, çökertmez
            pass

    # -- yargı -------------------------------------------------------------

    def destekliyor_mu(self, iddia: str, kanit: str) -> bool:
        return self.toplu([NliCift(iddia=iddia, kanit=kanit)])[0]

    def toplu(self, ciftler: list[NliCift]) -> list[bool]:
        """Her çift için entailment kararı; sıra korunur.

        Azami çift sınırını aşan kuyruk YARGILANMADAN reddedilir (muhafazakâr
        taraf: sınırsız girdiyle sınırsız çıkarım yapılmaz, fazlası eski
        davranışa — kelime-eşleşme reddine — düşer).
        """
        if not ciftler:
            return []
        yargilanacak = ciftler[: self.azami_cift]
        sonuc = [False] * len(ciftler)

        import torch

        with self._kilit:
            return self._yargila(yargilanacak, sonuc, torch)

    def _yargila(
        self, yargilanacak: list[NliCift], sonuc: list[bool], torch: Any
    ) -> list[bool]:
        model, tokenizer, cihaz = self._load()
        etiketler = {
            str(ad).lower(): int(indeks)
            for indeks, ad in model.config.id2label.items()  # type: ignore[attr-defined]
        }
        entail = etiketler.get("entailment", 0)
        celiski = etiketler.get("contradiction", 2)

        for bas in range(0, len(yargilanacak), self.parti_boyu):
            parti = yargilanacak[bas : bas + self.parti_boyu]
            girdiler = tokenizer(  # type: ignore[operator]
                [cift.kanit for cift in parti],
                [cift.iddia for cift in parti],
                truncation=True,
                max_length=512,
                padding=True,
                return_tensors="pt",
            ).to(cihaz)
            with torch.no_grad():
                logits = model(**girdiler).logits  # type: ignore[operator]
            olasiliklar = torch.softmax(logits, dim=-1).cpu()
            for sira, cift in enumerate(parti):
                entail_p = float(olasiliklar[sira, entail])
                celiski_p = float(olasiliklar[sira, celiski])
                sonuc[bas + sira] = (
                    entail_p >= min(0.99, self.esik + cift.esik_kaydirma)
                    and celiski_p < self.karsi_esik
                )
        return sonuc
