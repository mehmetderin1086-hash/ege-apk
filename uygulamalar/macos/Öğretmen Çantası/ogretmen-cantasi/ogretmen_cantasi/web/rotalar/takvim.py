"""Sınav takvimi: tarihli resmî değerlendirmeler tek sayfada."""

from __future__ import annotations

from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse, RedirectResponse

from ... import servis
from ..ortak import _ortak, sablonlar


def bagla(uygulama: FastAPI) -> None:
    @uygulama.get("/takvim", response_class=HTMLResponse)
    def takvim_sayfasi(istek: Request):
        baglanti = istek.state.db
        yil = servis.aktif_yil(baglanti)
        if yil is None:
            return RedirectResponse("/kurulum", status_code=303)
        takvim = servis.sinav_takvimi(baglanti, yil)
        return sablonlar.TemplateResponse(
            istek,
            "takvim.html",
            # `yil` ve `subeler` _ortak bağlamından gelir; burada yeniden
            # üretmek subeleri_oku'yu istek başına iki kez koşturuyordu.
            _ortak(
                istek,
                girisler=takvim["girisler"],
                uyarilar=takvim["uyarilar"],
            ),
        )
