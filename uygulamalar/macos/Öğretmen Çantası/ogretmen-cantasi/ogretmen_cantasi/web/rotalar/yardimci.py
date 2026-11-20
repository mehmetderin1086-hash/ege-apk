"""Kaynaklı yardımcı önerileri ve öğrenci destek planları."""

from __future__ import annotations

from typing import Annotated

from fastapi import FastAPI, Form, Request
from fastapi.responses import HTMLResponse, RedirectResponse

from ... import servis, yardimci
from ..ortak import _ortak, sablonlar


def bagla(uygulama: FastAPI) -> None:
    @uygulama.get("/yardimci", response_class=HTMLResponse)
    def yardimci_sayfasi(istek: Request, mesaj: str = ""):
        baglanti = istek.state.db
        subeler = servis.subeleri_oku(
            baglanti, servis.aktif_yil(baglanti).id
        ) if servis.aktif_yil(baglanti) else []
        return sablonlar.TemplateResponse(
            istek,
            "yardimci.html",
            _ortak(
                istek,
                sayfa="yardimci",
                oneriler=yardimci.oneriler(baglanti),
                destekler=yardimci.destek_planlari(baglanti),
                secenek_subeler=subeler,
                mesaj=mesaj,
            ),
        )

    @uygulama.post("/yardimci/uret")
    def oneri_uret(
        istek: Request,
        tur: Annotated[str, Form()],
        sube_id: Annotated[int, Form()],
        kazanim_kodu: Annotated[str, Form()],
        ogrenci_id: Annotated[int | None, Form()] = None,
        ek_istek: Annotated[str, Form()] = "",
    ):
        no = yardimci.oneri_uret(
            istek.state.db,
            tur=tur,
            sube_id=sube_id,
            kazanim_kodu=kazanim_kodu,
            ogrenci_id=ogrenci_id,
            ek_istek=ek_istek,
        )
        return RedirectResponse(
            f"/yardimci?mesaj={no}+numaralı+kaynaklı+taslak+üretildi",
            status_code=303,
        )

    @uygulama.post("/yardimci/{oneri_id}/karar")
    def oneri_karar(
        istek: Request,
        oneri_id: int,
        durum: Annotated[str, Form()] = "onaylandi",
        duzeltme: Annotated[str, Form()] = "",
    ):
        yardimci.oneri_karari(
            istek.state.db, oneri_id, durum=durum, duzeltme=duzeltme
        )
        return RedirectResponse("/yardimci?mesaj=Öneri+kararı+kaydedildi", status_code=303)

    @uygulama.post("/yardimci/sinav/{sinav_id}/destek-turet")
    def destek_turet(istek: Request, sinav_id: int):
        adet = yardimci.destek_planlarini_turet(istek.state.db, sinav_id)
        return RedirectResponse(
            f"/yardimci?mesaj={adet}+destek+taslağı+oluşturuldu", status_code=303
        )

    @uygulama.post("/yardimci/destek/{plan_id}")
    def destek_guncelle(
        istek: Request,
        plan_id: int,
        durum: Annotated[str, Form()],
        calisma: Annotated[str, Form()] = "",
        takip_tarihi: Annotated[str, Form()] = "",
    ):
        yardimci.destek_plani_guncelle(
            istek.state.db,
            plan_id,
            durum=durum,
            calisma=calisma,
            takip_tarihi=takip_tarihi,
        )
        return RedirectResponse("/yardimci?mesaj=Destek+planı+güncellendi", status_code=303)
