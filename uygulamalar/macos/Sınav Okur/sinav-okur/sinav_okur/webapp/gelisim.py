"""Öğrenci gelişim panosu: sınavlar arası puan serisi ve sınıf matrisi."""
from __future__ import annotations

from fastapi import APIRouter, Form, HTTPException, Request
from fastapi.responses import HTMLResponse, RedirectResponse

from .baglam import WebBaglam


def rota_kur(baglam: WebBaglam) -> APIRouter:
    router = APIRouter()
    depo = baglam.depo
    sablonlar = baglam.sablonlar

    @router.get("/gelisim", response_class=HTMLResponse)
    def gelisim_panosu(request: Request):
        """Öğrenci × sınav matrisi; sınavlar arası gelişim."""
        from ..gelisim import sinif_gelisimi

        sinif = request.query_params.get("sinif") or None
        veri = sinif_gelisimi(depo, sinif)
        sinav_basliklari = {}
        for kimlik in veri["sinavlar"]:
            try:
                sinav_basliklari[kimlik] = depo.sinav_yukle(kimlik).baslik
            except KeyError:
                sinav_basliklari[kimlik] = kimlik
        siniflar = sorted(
            {(o["sinif"] or "").strip() for o in depo.ogrenciler() if o["sinif"]}
        )
        return sablonlar.TemplateResponse(
            request,
            "gelisim.html",
            {
                "veri": veri,
                "sinav_basliklari": sinav_basliklari,
                "siniflar": siniflar,
                "secili_sinif": sinif or "",
                "eslesme": request.query_params.get("eslesme"),
            },
        )

    @router.post("/gelisim/esle")
    def gelisim_esle(sinav_kimlik: str = Form("")):
        """Kâğıtları kalıcı öğrenci kayıtlarına bağlar (öğretmen tetikler)."""
        sonuc = depo.ogrencileri_esle(sinav_kimlik or None)
        return RedirectResponse(
            f"/gelisim?eslesme={sonuc['baglanan']}", status_code=303
        )

    @router.get("/ogrenci/{ogrenci_kimlik}", response_class=HTMLResponse)
    def ogrenci_detay(request: Request, ogrenci_kimlik: int):
        from ..analiz import kazanim_analizi
        from ..gelisim import ogrenci_serisi

        seri = ogrenci_serisi(depo, ogrenci_kimlik)
        if not seri:
            raise HTTPException(404, "Öğrenci bulunamadı")
        # Son sınavın kazanım zayıflıkları öğrenciye özel çalışma önerisidir.
        zayif: list[str] = []
        if seri["noktalar"]:
            son = seri["noktalar"][-1]
            try:
                sinav = depo.sinav_yukle(son["sinav_kimlik"])
                kazanim = kazanim_analizi(depo, sinav)
                zayif = next(
                    (
                        o["zayif"]
                        for o in kazanim["ogrenciler"]
                        if o["kagit_id"] == son["kagit_id"]
                    ),
                    [],
                )
            except KeyError:
                zayif = []
        return sablonlar.TemplateResponse(
            request, "ogrenci.html", {"seri": seri, "zayif": zayif}
        )

    return router
