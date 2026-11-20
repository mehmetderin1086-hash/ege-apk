"""Anasayfa, yardım, gizlilik ve kalibrasyon durumu uçları."""
from __future__ import annotations

import os

from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse, RedirectResponse
from starlette.concurrency import run_in_threadpool

from .baglam import WebBaglam


def rota_kur(baglam: WebBaglam) -> APIRouter:
    router = APIRouter()
    depo = baglam.depo
    sablonlar = baglam.sablonlar
    proje_kok = baglam.proje_kok
    model_yollari = baglam.model_yollari
    taniyici_onbellegi = baglam.taniyici_onbellegi
    taniyici_fabrikasi = baglam.taniyici_fabrikasi

    @router.get("/yardim", response_class=HTMLResponse)
    def yardim(request: Request):
        return sablonlar.TemplateResponse(request, "yardim.html", {})

    @router.get("/gizlilik", response_class=HTMLResponse)
    def gizlilik(request: Request):
        from ..gizlilik import gizlilik_durumu

        return sablonlar.TemplateResponse(
            request,
            "gizlilik.html",
            {
                "durum": gizlilik_durumu(),
                "suresi_dolan": depo.suresi_dolan_kagitlar(),
                "anonimlestirilen": request.query_params.get("anonimlestirilen"),
            },
        )

    @router.post("/gizlilik/anonimlestir")
    def gizlilik_anonimlestir():
        adet = depo.suresi_dolanlari_anonimlestir()
        return RedirectResponse(
            f"/gizlilik?anonimlestirilen={adet}", status_code=303
        )

    @router.post("/kalibrasyon/guncelle")
    async def kalibrasyon_guncelle(request: Request):
        from ..ogrenme import ocr_kalibrasyonunu_guncelle

        yol = proje_kok / "modeller/ocr_kalibrasyon.json"
        sonuc = await run_in_threadpool(
            ocr_kalibrasyonunu_guncelle, depo, yol
        )
        if sonuc.get("uygulandi"):
            # Önbellekteki çoklu tanıyıcıya sıcak yükle (GIL altında atomik atama).
            from ..htr.kalibrasyon import KosulluGuvenKalibrasyonu

            coklu = taniyici_onbellegi.get("coklu")
            if coklu is not None and hasattr(coklu, "kalibrasyon"):
                coklu.kalibrasyon = KosulluGuvenKalibrasyonu.yukle(yol)
        durum = "guncellendi" if sonuc.get("uygulandi") else "uygulanmadi"
        return RedirectResponse(
            f"/?kalibrasyon={durum}&ornek={sonuc.get('ornek', 0)}",
            status_code=303,
        )

    @router.get("/", response_class=HTMLResponse)
    def anasayfa(request: Request):
        sinavlar = []
        for aday in depo.sinavlar():
            dosyalar = depo.sinav_dosyasi(aday["kimlik"])
            if (
                dosyalar
                and dosyalar["sablon_yolu"]
                and baglam._serbest_mi(dosyalar["sablon_yolu"])
            ):
                sinavlar.append(aday)
        veri = []
        toplam_kagit = toplam_bekleyen = toplam_onayli = 0
        ilk_bekleyen_kagit = None
        for s in sinavlar:
            kagitlar = depo.kagitlar(s["kimlik"])
            bekleyen_kagitlar = [
                k for k in kagitlar if any(b["incele"] for b in depo.kutular(k["id"]))
            ]
            bekleyen = len(bekleyen_kagitlar)
            if ilk_bekleyen_kagit is None and bekleyen_kagitlar:
                ilk_bekleyen_kagit = bekleyen_kagitlar[0]["id"]
            onayli = sum(1 for k in kagitlar if k["onaylandi"])
            kagit_sayisi = len(kagitlar)
            veri.append({
                "sinav": s,
                "kagit_sayisi": kagit_sayisi,
                "bekleyen": bekleyen,
                "onayli": onayli,
                "ilerleme": round(onayli / kagit_sayisi * 100) if kagit_sayisi else 0,
            })
            toplam_kagit += kagit_sayisi
            toplam_bekleyen += bekleyen
            toplam_onayli += onayli
        ozet = {
            "sinav": len(veri),
            "kagit": toplam_kagit,
            "bekleyen": toplam_bekleyen,
            "onayli": toplam_onayli,
            "ilk_bekleyen_kagit": ilk_bekleyen_kagit,
        }
        return sablonlar.TemplateResponse(
            request, "anasayfa.html",
            {
                "veri": veri,
                "ozet": ozet,
                "kapi": depo.guvenlik_kapisi_ozeti(),
                "kapi_modu": os.environ.get(
                    "SINAV_OKUR_GUVENLIK_KAPISI", "golge"
                ),
                "kalibrasyon": baglam._kalibrasyon_durumu(),
                "model_hazir": (
                    taniyici_fabrikasi is not None
                    or model_yollari["keras-karakter"].exists()
                ),
            },
        )

    return router
