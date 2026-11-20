"""Biyoloji kitabı/kaynak yükleme ve yerel RAG durumu ekranı."""
from __future__ import annotations

import json
import re
from pathlib import Path
from uuid import uuid4

from fastapi import APIRouter, File, Request, UploadFile
from fastapi.responses import HTMLResponse
from starlette.concurrency import run_in_threadpool

from .baglam import WebBaglam
from ..yeniden_puanlama import rag_onbellegini_temizle


def rota_kur(baglam: WebBaglam) -> APIRouter:
    router = APIRouter()
    sablonlar = baglam.sablonlar
    referans_kaynak_dizini = baglam.referans_kaynak_dizini
    referans_indeks_dizini = baglam.referans_indeks_dizini

    @router.get("/referans", response_class=HTMLResponse)
    def referans_formu(request: Request):
        return sablonlar.TemplateResponse(
            request,
            "referans.html",
            {
                "hata": None,
                "basari": None,
                "durum": baglam._yerel_rag_durumu(),
                "kitaplar": sorted(
                    [p.name.split("-", 1)[-1] for p in referans_kaynak_dizini.iterdir()]
                ),
            },
        )

    @router.post("/referans", response_class=HTMLResponse)
    async def referans_yukle(
        request: Request,
        kitap_dosyalari: list[UploadFile] = File(...),
    ):
        from ..referans import YerelRAGDeposu

        eklenen: list[Path] = []
        try:
            dosyalar = [d for d in kitap_dosyalari if d.filename]
            if not dosyalar or len(dosyalar) > 20:
                raise ValueError("Bir işlemde 1–20 kitap/not dosyası yükleyin.")
            for dosya in dosyalar:
                orijinal = Path(dosya.filename or "kitap").name
                guvenli_ad = re.sub(r"[^A-Za-z0-9çğıöşüÇĞİÖŞÜ._ -]+", "_", orijinal)
                gecici = await baglam._yuklemeyi_kaydet(
                    dosya,
                    referans_kaynak_dizini,
                    {".pdf", ".txt", ".md"},
                    azami_bayt=250 * 1024 * 1024,
                )
                hedef = referans_kaynak_dizini / f"{uuid4().hex}-{guvenli_ad}"
                gecici.replace(hedef)
                eklenen.append(hedef)
            tum_kaynaklar = sorted(
                p for p in referans_kaynak_dizini.iterdir() if p.is_file()
            )
            depo_rag = await run_in_threadpool(YerelRAGDeposu.kur, tum_kaynaklar)
            await run_in_threadpool(depo_rag.kaydet, referans_indeks_dizini)
            rag_onbellegini_temizle()
            return sablonlar.TemplateResponse(
                request,
                "referans.html",
                {
                    "hata": None,
                    "basari": (
                        f"{len(eklenen)} kaynak eklendi; "
                        f"{len(depo_rag.pasajlar)} pasaj yerel olarak indekslendi."
                    ),
                    "durum": baglam._yerel_rag_durumu(),
                    "kitaplar": sorted(
                        [p.name.split("-", 1)[-1] for p in tum_kaynaklar]
                    ),
                },
            )
        except (ValueError, OSError, json.JSONDecodeError) as exc:
            for yol in eklenen:
                yol.unlink(missing_ok=True)
            return sablonlar.TemplateResponse(
                request,
                "referans.html",
                {
                    "hata": str(exc),
                    "basari": None,
                    "durum": baglam._yerel_rag_durumu(),
                    "kitaplar": sorted(
                        [
                            p.name.split("-", 1)[-1]
                            for p in referans_kaynak_dizini.iterdir()
                            if p.is_file()
                        ]
                    ),
                },
                status_code=400,
            )

    return router
