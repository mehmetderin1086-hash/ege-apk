"""Yoklama sayfası ve ses ile yoklama alma."""

from __future__ import annotations

import asyncio

from fastapi import FastAPI, Request, UploadFile
from fastapi.responses import HTMLResponse, PlainTextResponse, RedirectResponse

from ... import depo, servis
from ... import ses as ses_modulu
from ... import takvim as tk
from ... import yoklama as yk
from ..ortak import (
    SES_YUKLEME_SINIRI,
    _form_revizyonu,
    _ortak,
    _revizyon_ilerlet,
    _sinirli_oku,
    _tarih_coz,
    sablonlar,
)


def bagla(uygulama: FastAPI) -> None:
    @uygulama.get("/yoklama/{sube_id}", response_class=HTMLResponse)
    def yoklama_sayfasi(istek: Request, sube_id: int, tarih: str | None = None, saat: int = 1):
        baglanti = istek.state.db
        sube = servis.sube_al(baglanti, sube_id)
        gun = _tarih_coz(tarih)
        return sablonlar.TemplateResponse(
            istek,
            "yoklama.html",
            _ortak(
                istek,
                sube=sube,
                gun=gun,
                saat=saat,
                ogrenciler=servis.ogrencileri_oku(baglanti, sube_id),
                mevcut=servis.gunun_yoklamasi(baglanti, sube_id, gun, saat),
                durum_adlari=yk.DURUM_ADLARI,
                ses_durumu=ses_modulu.durum(),
                tarih_metni=tk.tarih_metni(gun),
                revizyon=depo.revizyon_oku(
                    baglanti, f"yoklama:{sube_id}:{gun.isoformat()}:{saat}"
                ),
            ),
        )

    @uygulama.post("/yoklama/{sube_id}")
    async def yoklama_kaydet(istek: Request, sube_id: int):
        baglanti = istek.state.db
        veri = await istek.form()
        gun = _tarih_coz(str(veri.get("tarih", "")))
        saat = int(str(veri.get("saat", "1")) or 1)
        beklenen_revizyon = _form_revizyonu(veri)
        durumlar = {
            int(anahtar.removeprefix("o_")): str(deger)
            for anahtar, deger in veri.items()
            if anahtar.startswith("o_")
        }
        try:
            with depo.islem(baglanti, immediate=True):
                _revizyon_ilerlet(
                    baglanti,
                    f"yoklama:{sube_id}:{gun.isoformat()}:{saat}",
                    beklenen_revizyon,
                )
                servis.yoklama_kaydet(baglanti, sube_id, gun, saat, durumlar)
        except ValueError as hata:
            return PlainTextResponse(str(hata), status_code=409)
        return RedirectResponse(f"/sube/{sube_id}?mesaj=Yoklama+kaydedildi", status_code=303)

    @uygulama.post("/yoklama/{sube_id}/ses")
    async def yoklama_ses(istek: Request, sube_id: int, kayit: UploadFile):
        baglanti = istek.state.db
        ogrenciler = [
            yk.Ogrenci(o["id"], o["numara"], o["ad_soyad"])
            for o in servis.ogrencileri_oku(baglanti, sube_id)
        ]
        try:
            ses_baytlari = await _sinirli_oku(kayit, SES_YUKLEME_SINIRI)
            async with istek.app.state.ses_kilidi:
                dokum = await asyncio.to_thread(ses_modulu.yaziya_dok, ses_baytlari)
        except ses_modulu.SesKullanilamiyor as hata:
            return {"hata": str(hata)}
        cozum = yk.cozumle(dokum, ogrenciler)
        return {
            "dokum": dokum,
            "atamalar": [
                {"ogrenci_id": a.ogrenci.id, "ad": a.ogrenci.ad_soyad, "durum": a.durum, "skor": a.skor}
                for a in cozum.atamalar
            ],
            "belirsizler": [
                {"ogrenci_id": a.ogrenci.id, "ad": a.ogrenci.ad_soyad, "durum": a.durum, "duyulan": a.duyulan}
                for a in cozum.belirsizler
            ],
            "eslesmeyenler": [{"duyulan": d, "durum": t} for d, t in cozum.eslesmeyenler],
        }
