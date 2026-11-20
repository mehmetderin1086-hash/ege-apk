"""Öğrenci gelişim sayfası ve veli raporu.

Not, devamsızlık, deneme ve sınav kazanım verisi başka modüllerde zaten
tutuluyor; burası yalnız aynı öğrencinin verisini tek ekranda ve tek PDF'te
birleştirir — yeni veri üretmez.
"""

from __future__ import annotations

from datetime import date

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import HTMLResponse

from ... import mufredat as mf
from ... import notlar as nt
from ... import servis
from ... import servis_olcme as so
from ... import takvim as tk
from ...cikti import belge, grafik, pdf
from ..ortak import _dosya_yaniti, _ortak, sablonlar


def _kazanim_ozeti(baglanti, ogrenci) -> list[dict]:
    """Kazanım profiline müfredattaki ifadeleri iliştirir."""
    profil = so.ogrenci_kazanim_profili(baglanti, ogrenci["id"])
    try:
        program = mf.yukle(ogrenci["mufredat_surumu"])
    except mf.MufredatYok:
        program = None
    ozet: list[dict] = []
    for kod, son in sorted(profil["son"].items()):
        ifade = ""
        if program is not None:
            try:
                ifade = program.cikti(kod).ifade
            except mf.MufredatYok:
                ifade = ""
        ozet.append(
            {
                "kod": kod,
                "ifade": ifade,
                "yuzde": son["yuzde"],
                "durum": son["durum"],
                "gecmis": profil["gecmis"][kod],
            }
        )
    return ozet


def _ogrenci_verisi(baglanti, ogrenci_id: int) -> dict:
    try:
        ogrenci = servis.ogrenci_al(baglanti, ogrenci_id)
    except servis.Bulunamadi as hata:
        raise HTTPException(status_code=404, detail=str(hata)) from hata
    karne = next(
        (k for k in servis.karneler(baglanti, ogrenci["sube_id"]) if k.ogrenci_id == ogrenci_id),
        None,
    )
    devamsizlik = next(
        (
            d
            for d in servis.devamsizlik_tablosu(baglanti, ogrenci["sube_id"])
            if d["id"] == ogrenci_id
        ),
        None,
    )
    olaylar: list[dict] = []
    for y in baglanti.execute(
        "SELECT tarih, ders_saati, durum FROM yoklama WHERE ogrenci_id = ?",
        (ogrenci_id,),
    ):
        olaylar.append(
            {
                "tarih": y["tarih"],
                "tur": "Yoklama",
                "aciklama": f"{y['ders_saati']}. ders: {y['durum']}",
            }
        )
    for n in baglanti.execute(
        "SELECT d.tarih, d.ad, d.tur, n.puan FROM not_kaydi n "
        "JOIN degerlendirme d ON d.id = n.degerlendirme_id "
        "WHERE n.ogrenci_id = ? AND n.puan IS NOT NULL",
        (ogrenci_id,),
    ):
        olaylar.append(
            {
                "tarih": n["tarih"] or "",
                "tur": "Not",
                "aciklama": f"{n['ad']}: {n['puan']:g}",
            }
        )
    for s in baglanti.execute(
        "SELECT x.tarih, x.ad, SUM(p.puan) AS puan, SUM(q.puan) AS tavan "
        "FROM soru_puani p JOIN sinav_sorusu q ON q.id = p.sinav_sorusu_id "
        "JOIN sinav x ON x.id = q.sinav_id WHERE p.ogrenci_id = ? "
        "GROUP BY x.id ORDER BY x.tarih",
        (ogrenci_id,),
    ):
        olaylar.append(
            {
                "tarih": s["tarih"] or "",
                "tur": "Sınav",
                "aciklama": f"{s['ad']}: {s['puan']:g}/{s['tavan']:g}",
            }
        )
    for d in baglanti.execute(
        "SELECT olusturma, kazanim_kodu, durum FROM ogrenci_destek_plani "
        "WHERE ogrenci_id = ?",
        (ogrenci_id,),
    ):
        olaylar.append(
            {
                "tarih": d["olusturma"][:10],
                "tur": "Destek",
                "aciklama": f"{d['kazanim_kodu']}: {d['durum']}",
            }
        )
    olaylar.sort(key=lambda o: (o["tarih"], o["tur"]), reverse=True)
    return {
        "ogrenci": ogrenci,
        "karne": karne,
        "devamsizlik": devamsizlik,
        "denemeler": so.ogrenci_deneme_netleri(baglanti, ogrenci_id),
        "kazanimlar": _kazanim_ozeti(baglanti, ogrenci),
        "olaylar": olaylar,
    }


def bagla(uygulama: FastAPI) -> None:
    @uygulama.get("/ogrenci/{ogrenci_id}", response_class=HTMLResponse)
    def ogrenci_sayfasi(istek: Request, ogrenci_id: int):
        veri = _ogrenci_verisi(istek.state.db, ogrenci_id)
        deneme_grafigi = grafik.cizgi_grafigi(
            [(d["ad"], d["net"]) for d in veri["denemeler"]],
            baslik="Deneme net gelişimi",
        )
        return sablonlar.TemplateResponse(
            istek,
            "ogrenci.html",
            _ortak(istek, tur_adlari=nt.TUR_ADLARI, deneme_grafigi=deneme_grafigi, **veri),
        )

    @uygulama.get("/ogrenci/{ogrenci_id}/rapor")
    def ogrenci_raporu_indir(istek: Request, ogrenci_id: int):
        baglanti = istek.state.db
        veri = _ogrenci_verisi(baglanti, ogrenci_id)
        okul, ogretmen = servis.belge_kunyesi(baglanti)
        html = belge.ogrenci_raporu(
            veri["karne"],
            veri["devamsizlik"],
            veri["denemeler"],
            veri["kazanimlar"],
            okul=okul,
            sube_adi=veri["ogrenci"]["sube_adi"],
            numara=veri["ogrenci"]["numara"],
            ogretmen=ogretmen,
            tarih_metni=tk.tarih_metni(date.today()),
        )
        ad = veri["ogrenci"]["ad_soyad"].replace(" ", "-")
        return _dosya_yaniti(
            pdf.html_pdfe(html), f"{ad}-gelisim-raporu.pdf", "application/pdf"
        )
