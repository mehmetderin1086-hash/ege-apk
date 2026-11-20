"""Ana sayfa: bugünün ders programı ve ders defteri kaydı."""

from __future__ import annotations

import sqlite3
from datetime import date
from typing import Annotated

from fastapi import FastAPI, Form, Request
from fastapi.responses import HTMLResponse, RedirectResponse

from ... import servis
from ... import takvim as tk
from ..ortak import _ortak, _saatleri_coz, _tarih_coz, sablonlar


def gunun_ozeti(baglanti: sqlite3.Connection, yil: servis.OgretimYili, gun: date) -> dict:
    """Günün blokları (plan satırı, yoklama ve defter durumu), tatil ve devamsızlık uyarıları.

    Ana sayfa (HTML) ile salt okunur `/api/v1/bugun` ve MCP `bugun` aracı aynı
    hesabı kullanır; böylece iki yüz birbirinden ayrışmaz.
    """
    tatiller = {t.tarih: t for _, t in servis.tatilleri_oku(baglanti, yil.id)}

    bloklar = servis.gunun_bloklari(baglanti, yil.id, gun)
    for blok in bloklar:
        sube = servis.sube_al(baglanti, blok["sube_id"])
        satirlar = servis.yillik_plan_oku(baglanti, sube)
        blok["plan_satiri"] = servis.haftanin_kazanimlari(satirlar, gun)
        blok["yoklama_alindi"] = bool(
            servis.gunun_yoklamasi(baglanti, sube.id, gun, blok["saatler"][0])
        )
        blok["ders_kaydi"] = servis.gunun_ders_kaydi(
            baglanti, sube.id, gun, ders_saatleri=blok["saatler"]
        )

    uyarilar: list[str] = []
    for sube in servis.subeleri_oku(baglanti, yil.id):
        for kayit in servis.devamsizlik_tablosu(baglanti, sube.id):
            if kayit["uyari"]:
                uyarilar.append(f"{sube.ad} — {kayit['ad_soyad']}: {kayit['uyari']}")

    return {"bloklar": bloklar, "tatil": tatiller.get(gun), "uyarilar": uyarilar}


def ders_kaydi_sozluk(kayit: sqlite3.Row | None) -> dict | None:
    """Ders defteri satırını JSON'a uygun sözlüğe çevirir (yoksa None)."""
    if kayit is None:
        return None
    return {
        "tarih": kayit["tarih"],
        "ders_saatleri": [int(p) for p in str(kayit["ders_saatleri"]).split(",") if p.strip().isdigit()],
        "kazanim_kodlari": servis.kod_listesi(kayit["kazanim_kodlari"] or ""),
        "durum": kayit["durum"],
        "aciklama": kayit["aciklama"],
    }


def gunun_ozeti_json(baglanti: sqlite3.Connection, gun: date) -> dict:
    """`gunun_ozeti`nin JSON biçimi; aktif öğretim yılı yoksa boş bloklarla `kurulum_gerekli`."""
    yil = servis.aktif_yil(baglanti)
    temel = {"tarih": gun.isoformat(), "gun_adi": tk.GUN_ADLARI[gun.weekday()]}
    if yil is None:
        return {**temel, "kurulum_gerekli": True, "tatil": None, "bloklar": [], "uyarilar": []}
    ozet = gunun_ozeti(baglanti, yil, gun)
    tatil = ozet["tatil"]
    bloklar = []
    for blok in ozet["bloklar"]:
        plan = blok["plan_satiri"]
        bloklar.append(
            {
                "sube_id": blok["sube_id"],
                "sube_adi": blok["sube_adi"],
                "sinif": blok["sinif"],
                "saatler": list(blok["saatler"]),
                "plan": None
                if plan is None
                else {
                    "hafta_no": plan.hafta_no,
                    "tema_adi": plan.tema_adi,
                    "kazanim_kodlari": list(plan.kazanim_kodlari),
                    "kazanim_ifadeleri": list(plan.kazanim_ifadeleri),
                },
                "yoklama_alindi": blok["yoklama_alindi"],
                "ders_kaydi": ders_kaydi_sozluk(blok["ders_kaydi"]),
            }
        )
    return {
        **temel,
        "kurulum_gerekli": False,
        "tatil": None
        if tatil is None
        else {"tur": tatil.tur, "aciklama": tatil.aciklama},
        "bloklar": bloklar,
        "uyarilar": ozet["uyarilar"],
    }


def bagla(uygulama: FastAPI) -> None:
    @uygulama.get("/", response_class=HTMLResponse)
    def bugun(istek: Request, tarih: str | None = None, mesaj: str = ""):
        baglanti = istek.state.db
        yil = servis.aktif_yil(baglanti)
        if yil is None:
            return RedirectResponse("/kurulum", status_code=303)

        gun = _tarih_coz(tarih)
        ozet = gunun_ozeti(baglanti, yil, gun)

        return sablonlar.TemplateResponse(
            istek,
            "bugun.html",
            _ortak(
                istek,
                gun=gun,
                bloklar=ozet["bloklar"],
                tatil=ozet["tatil"],
                uyarilar=ozet["uyarilar"][:8],
                gun_adi=tk.GUN_ADLARI[gun.weekday()],
                tarih_metni=tk.tarih_metni(gun),
                mesaj=mesaj,
            ),
        )

    @uygulama.post("/ders-kaydi/{sube_id}")
    def ders_kaydi_yaz(
        istek: Request,
        sube_id: int,
        tarih: Annotated[str, Form()],
        saatler: Annotated[str, Form()] = "",
        kazanim_kodlari: Annotated[str, Form()] = "",
        durum: Annotated[str, Form()] = "islendi",
        aciklama: Annotated[str, Form()] = "",
    ):
        gun = _tarih_coz(tarih)
        try:
            # Şube doğrulaması FK hatasının 500 olmasını engeller.
            servis.sube_al(istek.state.db, sube_id)
            servis.ders_kaydi_yaz(
                istek.state.db,
                sube_id,
                gun,
                ders_saatleri=_saatleri_coz(saatler),
                kazanim_kodlari=servis.kod_listesi(kazanim_kodlari),
                durum=durum,
                aciklama=aciklama.strip(),
            )
        except (ValueError, servis.Bulunamadi) as hata:
            return RedirectResponse(f"/?tarih={gun.isoformat()}&mesaj={hata}", status_code=303)
        return RedirectResponse(f"/?tarih={gun.isoformat()}", status_code=303)
