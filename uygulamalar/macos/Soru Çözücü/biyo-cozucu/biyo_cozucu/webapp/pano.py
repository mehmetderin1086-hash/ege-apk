"""Hafıza ve kalite panosu."""

from __future__ import annotations

from fastapi import APIRouter, Form, Request
from fastapi.responses import HTMLResponse, RedirectResponse

from .durum import Uygulama
from .yardimcilar import guvenli_geri


def yonlendirici(durum: Uygulama, sablon) -> APIRouter:
    yonlendirici = APIRouter()

    @yonlendirici.post("/indeks/yenile")
    def indeksi_yenile(geri: str = Form("")):
        """Bayat indeksi arayüzden yeniden kurar (eskiden yalnız CLI'da vardı)."""
        indeks = durum.indeksi_yenile()
        durum.depo.denetim_yaz("indeks_yenile", f"{len(indeks)} örnek")
        return RedirectResponse(guvenli_geri(geri, "/pano"), status_code=303)

    @yonlendirici.get("/pano", response_class=HTMLResponse)
    def pano(request: Request):
        from ..kapsam import LORA_ESIGI, RAG_ESIGI, kapsami_cikar

        ozet = durum.durum()
        kapsam = kapsami_cikar(durum.depo.kapsam_matrisi())
        cozumler = durum.depo.cozumler(limit=500)
        toplam = len(cozumler)
        incelenecek = sum(1 for s in cozumler if s["incele"])
        onaylanan = sum(1 for s in cozumler if s["onay_durumu"] == "onaylandi")
        duzeltilen = sum(1 for s in cozumler if s["onay_durumu"] == "duzeltildi")
        degerlendirilen = onaylanan + duzeltilen
        yontem_dagilimi: dict[str, int] = {}
        for satir in cozumler:
            yontem_dagilimi[satir["uretim_yontemi"]] = (
                yontem_dagilimi.get(satir["uretim_yontemi"], 0) + 1
            )
        ortalama_guven = (
            sum(float(s["guven"]) for s in cozumler) / toplam if toplam else 0.0
        )
        return sablon.TemplateResponse(
            request,
            "pano.html",
            {
                "durum": ozet,
                "olcumler": {
                    "cozum": toplam,
                    "incelenecek": incelenecek,
                    "onaylanan": onaylanan,
                    "duzeltilen": duzeltilen,
                    # Öğretmen değerlendirmesi olmayan çözümler paydaya girmez;
                    # aksi halde henüz bakılmamış çözümler "yanlış" gibi görünür.
                    "onay_orani": (onaylanan / degerlendirilen) if degerlendirilen else None,
                    "ortalama_guven": ortalama_guven,
                },
                "yontem_dagilimi": yontem_dagilimi,
                "kapsam": kapsam,
                "esikler": {"rag": RAG_ESIGI, "lora": LORA_ESIGI},
            },
        )

    return yonlendirici
