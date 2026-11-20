"""Materyal listesi yönetimi."""

from __future__ import annotations

from typing import Annotated

from fastapi import FastAPI, Form, Request
from fastapi.responses import HTMLResponse, RedirectResponse

from ... import servis_olcme as so
from ..ortak import _ortak, sablonlar


def bagla(uygulama: FastAPI) -> None:
    @uygulama.get("/materyaller", response_class=HTMLResponse)
    def materyaller_sayfasi(istek: Request, kazanim: str = "", sinif: int | None = None, mesaj: str = ""):
        baglanti = istek.state.db
        return sablonlar.TemplateResponse(
            istek,
            "materyaller.html",
            _ortak(
                istek,
                materyaller=so.materyalleri_oku(baglanti, kazanim_kodu=kazanim, sinif=sinif),
                kazanim=kazanim,
                sinif=sinif,
                mesaj=mesaj,
            ),
        )

    @uygulama.post("/materyaller/ekle")
    def materyal_ekle(
        istek: Request,
        baslik: Annotated[str, Form()],
        kazanim_kodu: Annotated[str, Form()] = "",
        sinif: Annotated[int, Form()] = 0,
        url: Annotated[str, Form()] = "",
        etiketler: Annotated[str, Form()] = "",
    ):
        so.materyal_ekle(
            istek.state.db,
            baslik=baslik,
            kazanim_kodu=kazanim_kodu.strip(),
            sinif=sinif or None,
            url=url,
            etiketler=etiketler,
        )
        return RedirectResponse("/materyaller?mesaj=Materyal+eklendi", status_code=303)

    @uygulama.post("/materyaller/{materyal_id}/sil")
    def materyal_sil(istek: Request, materyal_id: int):
        so.materyal_sil(istek.state.db, materyal_id)
        return RedirectResponse("/materyaller?mesaj=Silindi", status_code=303)
