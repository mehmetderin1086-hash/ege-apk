"""Gölge kapı telemetri paneli: kapının ne yaptığını öğretmene görünür kılar.

Kapı eşiklerine dokunmaz; yalnız kayıtlı kararları raporlar. Aktivasyon
hedefi docs/ml_dl_guvenilirlik.md'deki ~300 kapılı kutu telemetrisidir.
"""
from __future__ import annotations

import io
import json
import os
import tempfile
import zipfile
from pathlib import Path

from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse, Response

from .baglam import WebBaglam

AKTIVASYON_HEDEFI = 300


def rota_kur(baglam: WebBaglam) -> APIRouter:
    router = APIRouter()
    depo = baglam.depo
    sablonlar = baglam.sablonlar

    @router.get("/kapi", response_class=HTMLResponse)
    def kapi_paneli(request: Request):
        from ..analiz import esik_supurmesi
        from ..guvenlik_kapisi import ASGARI_OCR_GUVENI
        from ..tezgah import perf_ozeti

        ozet = depo.guvenlik_kapisi_ozeti()
        kayitlar = depo.kapi_kayitlari()
        nedenler = sorted(
            ozet["neden_sayimlari"].items(), key=lambda x: -x[1]
        )
        en_cok_neden = nedenler[0][1] if nedenler else 0
        return sablonlar.TemplateResponse(
            request,
            "kapi.html",
            {
                "ozet": ozet,
                "kapi_modu": os.environ.get("SINAV_OKUR_GUVENLIK_KAPISI", "golge"),
                "nedenler": nedenler,
                "en_cok_neden": en_cok_neden,
                "supurme": esik_supurmesi(kayitlar),
                "mevcut_esik": ASGARI_OCR_GUVENI,
                "aktivasyon_hedefi": AKTIVASYON_HEDEFI,
                "aktivasyon_yuzdesi": min(
                    100, round(ozet["kapili_kutu"] / AKTIVASYON_HEDEFI * 100)
                ),
                "kalibrasyon": baglam._kalibrasyon_durumu(),
                "perf": perf_ozeti(baglam.serbest_taslak_dizini),
            },
        )

    @router.get("/disaaktar.zip")
    def disaaktar_zip():
        """İzinli düzeltme verisini (JSONL + kırpıntılar) tek zip'te indirir.

        Colab eğitim defterine tek tık taşıma içindir. Kırpıntısı silinmiş
        satırlar atlanır ve manifestte raporlanır — sessiz veri kaybı yok.
        """
        with tempfile.TemporaryDirectory() as gecici:
            jsonl_yolu = Path(gecici) / "labels.jsonl"
            depo.egitim_verisi_disa_aktar(jsonl_yolu)
            satirlar = [
                json.loads(s)
                for s in jsonl_yolu.read_text(encoding="utf-8").splitlines()
                if s.strip()
            ]
            manifest_yolu = jsonl_yolu.with_suffix(".jsonl.manifest.json")
            disa_manifest = (
                json.loads(manifest_yolu.read_text(encoding="utf-8"))
                if manifest_yolu.is_file()
                else {}
            )
        tampon = io.BytesIO()
        # Dışa aktarım sırasında zaten atlanmış kırpıntılar + zip anındakiler.
        # Pakete mutlak yerel yollar sızmasın: yalnız dosya adı raporlanır.
        atlanan: list[str] = [
            Path(x).name for x in disa_manifest.get("skipped_missing_crops", [])
        ]
        with zipfile.ZipFile(tampon, "w", zipfile.ZIP_DEFLATED) as paket:
            yeni_satirlar = []
            for i, satir in enumerate(satirlar):
                kaynak = Path(satir["image"])
                if not kaynak.is_file():
                    atlanan.append(kaynak.name)
                    continue
                zip_ici = f"kirpintilar/{i:05d}_{kaynak.name}"
                paket.write(kaynak, zip_ici)
                yeni_satirlar.append({**satir, "image": zip_ici})
            paket.writestr(
                "labels.jsonl",
                "".join(
                    json.dumps(s, ensure_ascii=False) + "\n" for s in yeni_satirlar
                ),
            )
            paket.writestr(
                "manifest.json",
                json.dumps(
                    {
                        **disa_manifest,
                        "ornek": len(yeni_satirlar),
                        "atlanan_kirpinti": atlanan,
                    },
                    ensure_ascii=False,
                    indent=2,
                ),
            )
        return Response(
            tampon.getvalue(),
            media_type="application/zip",
            headers={
                "Content-Disposition": "attachment; filename=gercek-satir-verisi.zip"
            },
        )

    return router
