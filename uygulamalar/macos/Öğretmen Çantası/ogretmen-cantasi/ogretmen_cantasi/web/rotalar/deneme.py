"""Deneme sınavı sonuçlarının yüklenmesi ve elle girilmesi."""

from __future__ import annotations

from datetime import date
from typing import Annotated

from fastapi import FastAPI, Form, HTTPException, Request, UploadFile
from fastapi.responses import HTMLResponse, PlainTextResponse, RedirectResponse

from ... import servis
from ... import servis_olcme as so
from ... import yoklama as yk
from ...cikti import grafik
from ...okuma import deneme as deneme_okuma
from ...okuma import tablo as tablo_okuma
from ..ortak import (
    TABLO_YUKLEME_SINIRI,
    _onizleme_ac,
    _onizleme_imzala,
    _ortak,
    _sayi,
    _sinirli_oku,
    _yuklenen_dosya,
    sablonlar,
)


def bagla(uygulama: FastAPI) -> None:
    @uygulama.get("/denemeler/{sube_id}", response_class=HTMLResponse)
    def denemeler_sayfasi(istek: Request, sube_id: int, mesaj: str = ""):
        baglanti = istek.state.db
        gelisim = so.deneme_gelisimi(baglanti, sube_id)
        noktalar = [
            (d["ad"], d["ortalama"]) for d in gelisim["denemeler"] if d["ortalama"] is not None
        ]
        # Kıvılcım ve ilk-son değişimi aynı seriden türetilir; seri şablonda
        # ikinci kez kurulmasın diye ikisi de burada hesaplanır.
        kivilcimlar: dict[int, str] = {}
        degisimler: dict[int, float] = {}
        for oid, o in gelisim["ogrenciler"].items():
            netler = [o["netler"][d["id"]] for d in gelisim["denemeler"] if d["id"] in o["netler"]]
            kivilcimlar[oid] = grafik.kivilcim(netler)
            if len(netler) > 1:
                degisimler[oid] = round(netler[-1] - netler[0], 2)
        return sablonlar.TemplateResponse(
            istek,
            "denemeler.html",
            _ortak(
                istek,
                sube=servis.sube_al(baglanti, sube_id),
                gelisim=gelisim,
                gelisim_grafigi=grafik.cizgi_grafigi(
                    noktalar, baslik="Sınıf net ortalaması gelişimi"
                ),
                kivilcimlar=kivilcimlar,
                degisimler=degisimler,
                ogrenciler=servis.ogrencileri_oku(baglanti, sube_id),
                mesaj=mesaj,
            ),
        )

    @uygulama.post("/denemeler/{sube_id}/yukle")
    async def deneme_yukle(
        istek: Request,
        sube_id: int,
        dosya: UploadFile,
        ad: Annotated[str, Form()] = "Deneme",
        tarih: Annotated[str, Form()] = "",
        yayin: Annotated[str, Form()] = "",
    ):
        baglanti = istek.state.db
        icerik = await _sinirli_oku(dosya, TABLO_YUKLEME_SINIRI)
        try:
            with _yuklenen_dosya(dosya, icerik) as gecici:
                sonuc = deneme_okuma.denemeyi_coz(tablo_okuma.tabloyu_oku(gecici))
        except tablo_okuma.OkunamadiError as hata:
            return RedirectResponse(f"/denemeler/{sube_id}?mesaj={hata}", status_code=303)

        ogrenciler = [
            yk.Ogrenci(o["id"], o["numara"], o["ad_soyad"])
            for o in servis.ogrencileri_oku(baglanti, sube_id)
        ]
        indeks = yk.eslesme_indeksi((o.numara, o.ad_soyad, o) for o in ogrenciler)
        onizleme: list[dict] = []
        for satir in sonuc.satirlar:
            adaylar = yk.aday_bul(indeks, satir.numara, satir.ad_soyad)
            secili = adaylar[0].id if len(adaylar) == 1 else 0
            durum = "Kesin eşleşme" if secili else "Eşleşmeyen — öğrenci seçilmeli"
            onizleme.append(
                {
                    "ad_soyad": satir.ad_soyad,
                    "numara": satir.numara,
                    "dogru": satir.dogru,
                    "yanlis": satir.yanlis,
                    "bos": satir.bos,
                    "net": satir.net,
                    "secili": secili,
                    "durum": durum,
                }
            )
        paket = _onizleme_imzala(
            istek.app,
            {
                "tur": "deneme",
                "sube_id": sube_id,
                "ad": ad,
                "tarih": tarih or date.today().isoformat(),
                "yayin": yayin,
                "satirlar": [
                    {
                        "ad_soyad": s.ad_soyad,
                        "numara": s.numara,
                        "dogru": s.dogru,
                        "yanlis": s.yanlis,
                        "bos": s.bos,
                        "net": s.net,
                    }
                    for s in sonuc.satirlar
                ],
            },
        )
        return sablonlar.TemplateResponse(
            istek,
            "deneme_onizle.html",
            _ortak(
                istek,
                sube=servis.sube_al(baglanti, sube_id),
                satirlar=onizleme,
                ogrenciler=ogrenciler,
                paket=paket,
                uyarilar=sonuc.uyarilar,
            ),
        )

    @uygulama.post("/denemeler/{sube_id}/aktar")
    async def deneme_aktar(istek: Request, sube_id: int):
        veri = await istek.form()
        paket = _onizleme_ac(istek.app, str(veri.get("paket", "")))
        if paket.get("tur") != "deneme" or int(paket.get("sube_id", 0)) != sube_id:
            raise HTTPException(status_code=400, detail="Deneme önizlemesi hedefle uyuşmuyor.")
        mevcut = {
            o["id"]: o for o in servis.ogrencileri_oku(istek.state.db, sube_id)
        }
        kullanilan: set[int] = set()
        kayitlar: list[tuple[int, int, int, int, float]] = []
        for sira, satir in enumerate(paket.get("satirlar", [])):
            try:
                ogrenci_id = int(str(veri.get(f"eslesme_{sira}", "0")))
            except ValueError:
                ogrenci_id = 0
            if ogrenci_id == 0:
                continue
            if ogrenci_id not in mevcut:
                return PlainTextResponse("Geçersiz öğrenci seçimi.", status_code=409)
            if ogrenci_id in kullanilan:
                return PlainTextResponse(
                    "Aynı öğrenci birden çok sonuç satırına atanamaz.", status_code=409
                )
            kullanilan.add(ogrenci_id)
            kayitlar.append(
                (
                    ogrenci_id,
                    int(satir.get("dogru", 0)),
                    int(satir.get("yanlis", 0)),
                    int(satir.get("bos", 0)),
                    float(satir.get("net", 0)),
                )
            )
        if not kayitlar:
            return PlainTextResponse("Aktarılacak deneme sonucu yok.", status_code=409)
        so.deneme_kaydet(
            istek.state.db,
            ad=str(paket.get("ad") or "Deneme"),
            tarih=str(paket.get("tarih") or date.today().isoformat()),
            yayin=str(paket.get("yayin") or ""),
            sonuclar=kayitlar,
            sube_id=sube_id,
        )
        return RedirectResponse(
            f"/denemeler/{sube_id}?mesaj={len(kayitlar)}+sonuç+kaydedildi",
            status_code=303,
        )

    @uygulama.post("/denemeler/{sube_id}/elle")
    async def deneme_elle(istek: Request, sube_id: int):
        baglanti = istek.state.db
        veri = await istek.form()
        kayitlar: list[tuple[int, int, int, int, float]] = []
        for anahtar, deger in veri.items():
            if not anahtar.startswith("d_"):
                continue
            ogrenci_id = int(anahtar.removeprefix("d_"))
            dogru = int(_sayi(str(deger)) or 0)
            yanlis = int(_sayi(str(veri.get(f"y_{ogrenci_id}", "0"))) or 0)
            bos = int(_sayi(str(veri.get(f"b_{ogrenci_id}", "0"))) or 0)
            if min(dogru, yanlis, bos) < 0:
                return RedirectResponse(
                    f"/denemeler/{sube_id}?mesaj=Negatif+sayı+kabul+edilmez",
                    status_code=303,
                )
            if dogru or yanlis or bos:
                kayitlar.append(
                    (ogrenci_id, dogru, yanlis, bos, deneme_okuma.net_hesapla(dogru, yanlis))
                )
        if kayitlar:
            try:
                so.deneme_kaydet(
                    baglanti,
                    ad=str(veri.get("ad") or "Deneme"),
                    tarih=str(veri.get("tarih") or date.today().isoformat()),
                    yayin=str(veri.get("yayin") or ""),
                    sonuclar=kayitlar,
                    sube_id=sube_id,
                )
            except ValueError as hata:
                # Başka şubeye ait öğrenci kimliği 500 değil anlaşılır mesaj
                # olarak dönmeli.
                return RedirectResponse(
                    f"/denemeler/{sube_id}?mesaj={hata}", status_code=303
                )
        return RedirectResponse(
            f"/denemeler/{sube_id}?mesaj={len(kayitlar)} sonuç kaydedildi", status_code=303
        )
