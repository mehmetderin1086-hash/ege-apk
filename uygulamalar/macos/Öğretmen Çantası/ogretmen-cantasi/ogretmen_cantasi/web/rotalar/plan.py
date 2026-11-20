"""Yıllık plan ve günlük plan sayfaları."""

from __future__ import annotations

from typing import Annotated

from fastapi import FastAPI, Form, Request
from fastapi.responses import HTMLResponse, RedirectResponse

from ... import mufredat as mf
from ... import servis
from ... import takvim as tk
from ...cikti import belge, excel, pdf, word
from ..ortak import (
    DOCX_MIME,
    XLSX_MIME,
    _dosya_yaniti,
    _ortak,
    _saatleri_coz,
    _tarih_coz,
    _tema_sozlugu,
    sablonlar,
)


def bagla(uygulama: FastAPI) -> None:
    # --- yıllık plan -------------------------------------------------------

    @uygulama.get("/plan/{sube_id}", response_class=HTMLResponse)
    def plan_sayfasi(istek: Request, sube_id: int, gorunum: str = "yillik"):
        baglanti = istek.state.db
        sube = servis.sube_al(baglanti, sube_id)
        satirlar = servis.yillik_plan_oku(baglanti, sube)
        from ...plan import yillik as yp

        mufredat_var = sube.mufredat_surumu in mf.mevcut_surumler()
        kapsam = None
        if satirlar and mufredat_var:
            kapsam = yp.kapsam_raporu(
                mf.yukle(sube.mufredat_surumu).duzey(sube.sinif), satirlar
            )
        gerceklesme = servis.sube_gerceklesmesi(baglanti, sube)
        return sablonlar.TemplateResponse(
            istek,
            "plan.html",
            _ortak(
                istek,
                sube=sube,
                satirlar=satirlar,
                ozet=yp.plan_ozeti(satirlar) if satirlar else None,
                aylar=yp.aylik_ozet(satirlar) if satirlar else [],
                kapsam=kapsam,
                gerceklesme=gerceklesme,
                plan_gecmisi=servis.plan_gecmisi(baglanti, sube_id),
                gorunum=gorunum,
                mufredat_var=mufredat_var,
            ),
        )

    @uygulama.post("/plan/{sube_id}/uret")
    def plan_uret(istek: Request, sube_id: int):
        baglanti = istek.state.db
        yil = servis.subenin_yili(baglanti, sube_id)
        try:
            servis.yillik_plan_uret_ve_kaydet(baglanti, yil, servis.sube_al(baglanti, sube_id))
        except servis.Bulunamadi as hata:
            return RedirectResponse(f"/plan/{sube_id}?mesaj={hata}", status_code=303)
        return RedirectResponse(f"/plan/{sube_id}", status_code=303)

    @uygulama.post("/plan/{sube_id}/{plan_id}/durum")
    def plan_durum(
        istek: Request,
        sube_id: int,
        plan_id: int,
        durum: Annotated[str, Form()],
    ):
        try:
            servis.plan_durum_guncelle(
                istek.state.db, sube_id, plan_id, durum
            )
        except (ValueError, servis.Bulunamadi) as exc:
            return RedirectResponse(
                f"/plan/{sube_id}?mesaj={exc}", status_code=303
            )
        return RedirectResponse(
            f"/plan/{sube_id}?mesaj=Plan+durumu+güncellendi", status_code=303
        )

    @uygulama.get("/plan/{sube_id}/indir")
    def plan_indir(istek: Request, sube_id: int, bicim: str = "pdf", sablon: str = "meb"):
        baglanti = istek.state.db
        yil = servis.subenin_yili(baglanti, sube_id)
        sube = servis.sube_al(baglanti, sube_id)
        satirlar = servis.yillik_plan_oku(baglanti, sube)
        if not satirlar:
            try:
                satirlar = servis.yillik_plan_uret_ve_kaydet(baglanti, yil, sube)
            except servis.Bulunamadi as hata:
                return RedirectResponse(f"/plan/{sube_id}?mesaj={hata}", status_code=303)
        okul, ogretmen = servis.belge_kunyesi(baglanti)
        ad_govde = f"{sube.ad}-yillik-plan"

        if bicim == "docx":
            return _dosya_yaniti(
                word.yillik_plan_docx(
                    satirlar, okul=okul, sube_adi=sube.ad, ogretim_yili=yil.ad, ogretmen=ogretmen
                ),
                f"{ad_govde}.docx",
                DOCX_MIME,
            )
        if bicim == "xlsx":
            return _dosya_yaniti(
                excel.yillik_plan_xlsx(satirlar, sube_adi=sube.ad, ogretim_yili=yil.ad),
                f"{ad_govde}.xlsx",
                XLSX_MIME,
            )

        if sablon == "maarif":
            program = mf.yukle(sube.mufredat_surumu)
            temalar = [_tema_sozlugu(t) for t in program.duzey(sube.sinif).temalar]
            html = belge.yillik_plan_maarif(
                temalar, okul=okul, sube_adi=sube.ad, ogretim_yili=yil.ad, ogretmen=ogretmen
            )
            return _dosya_yaniti(
                pdf.html_pdfe(html), f"{sube.ad}-tema-plani.pdf", "application/pdf"
            )

        sayfalar = belge.yillik_plan_meb_sayfalari(
            satirlar, okul=okul, sube_adi=sube.ad, ogretim_yili=yil.ad, ogretmen=ogretmen
        )
        return _dosya_yaniti(
            pdf.html_sayfalari_pdfe(sayfalar, yatay=True),
            f"{ad_govde}.pdf",
            "application/pdf",
        )

    # --- günlük plan ---------------------------------------------------------

    def _gunluk_baglam(baglanti, sube_id: int, tarih: str | None, saatler: str):
        """Sayfa ve PDF ucu aynı bağlamı kurar; kural tek yerde durur."""
        yil = servis.subenin_yili(baglanti, sube_id)
        sube = servis.sube_al(baglanti, sube_id)
        gun = _tarih_coz(tarih)
        ders_saatleri = _saatleri_coz(saatler, varsayilan=[1, 2])
        try:
            plan = servis.gunluk_plan_uret(baglanti, yil, sube, gun, ders_saatleri)
        except servis.Bulunamadi:
            plan = None
        return sube, gun, ders_saatleri, plan

    @uygulama.get("/gunluk/{sube_id}", response_class=HTMLResponse)
    def gunluk_sayfasi(istek: Request, sube_id: int, tarih: str | None = None, saatler: str = ""):
        baglanti = istek.state.db
        sube, gun, ders_saatleri, plan = _gunluk_baglam(baglanti, sube_id, tarih, saatler)
        return sablonlar.TemplateResponse(
            istek,
            "gunluk.html",
            _ortak(
                istek,
                sube=sube,
                gun=gun,
                plan=plan,
                saatler=",".join(str(s) for s in ders_saatleri),
                tarih_metni=tk.tarih_metni(gun),
            ),
        )

    @uygulama.get("/gunluk/{sube_id}/indir")
    def gunluk_indir(
        istek: Request, sube_id: int, tarih: str | None = None, saatler: str = "", bicim: str = "pdf"
    ):
        baglanti = istek.state.db
        sube, gun, _saatler, plan = _gunluk_baglam(baglanti, sube_id, tarih, saatler)
        if plan is None:
            return RedirectResponse(f"/gunluk/{sube_id}?tarih={gun}", status_code=303)
        okul, ogretmen = servis.belge_kunyesi(baglanti)
        ad = f"{sube.ad}-{gun.isoformat()}-gunluk-plan"
        if bicim == "docx":
            return _dosya_yaniti(
                word.gunluk_plan_docx(plan, okul=okul, ogretmen=ogretmen),
                f"{ad}.docx",
                DOCX_MIME,
            )
        return _dosya_yaniti(
            pdf.html_pdfe(belge.gunluk_plan_belgesi(plan, okul=okul, ogretmen=ogretmen)),
            f"{ad}.pdf",
            "application/pdf",
        )
