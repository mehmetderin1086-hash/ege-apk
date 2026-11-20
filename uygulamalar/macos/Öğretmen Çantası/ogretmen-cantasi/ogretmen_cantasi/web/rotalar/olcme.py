"""Soru havuzu ve sınavlar."""

from __future__ import annotations

from typing import Annotated

from fastapi import FastAPI, Form, Request
from fastapi.responses import HTMLResponse, PlainTextResponse, RedirectResponse

from ... import depo, servis
from ... import mufredat as mf
from ... import servis_olcme as so
from ...cikti import belge, excel, pdf
from ..ortak import (
    BOS,
    XLSX_MIME,
    _dosya_yaniti,
    _form_revizyonu,
    _ortak,
    _revizyon_ilerlet,
    _sayi,
    _sayi_ayir,
    sablonlar,
)


def bagla(uygulama: FastAPI) -> None:
    @uygulama.get("/sorular", response_class=HTMLResponse)
    def sorular_sayfasi(
        istek: Request,
        sinif: int = 9,
        kazanim: str = "",
        arama: str = "",
        arsiv: bool = False,
        mesaj: str = "",
    ):
        baglanti = istek.state.db
        surum = servis.mufredat_surumu_sec(baglanti, sinif)
        kazanimlar: list[mf.OgrenmeCiktisi] = []
        mufredat_var = True
        try:
            kazanimlar = list(mf.yukle(surum).duzey(sinif).ogrenme_ciktilari)
        except mf.MufredatYok:
            mufredat_var = False
        return sablonlar.TemplateResponse(
            istek,
            "sorular.html",
            _ortak(
                istek,
                sorular=so.sorulari_oku(
                    baglanti,
                    sinif=sinif,
                    kazanim_kodu=kazanim,
                    arama=arama,
                    aktif=not arsiv,
                ),
                sinif=sinif,
                kazanim=kazanim,
                arama=arama,
                arsiv=arsiv,
                kazanimlar=kazanimlar,
                mufredat_var=mufredat_var,
                surum=surum,
                sayilar=so.kazanim_soru_sayilari(baglanti, sinif),
                mesaj=mesaj,
            ),
        )

    @uygulama.post("/sorular/ekle")
    def soru_ekle(
        istek: Request,
        sinif: Annotated[int, Form()],
        kazanim_kodu: Annotated[str, Form()],
        metin: Annotated[str, Form()],
        rubrik: Annotated[str, Form()] = "",
        zorluk: Annotated[str, Form()] = "orta",
    ):
        so.soru_ekle(
            istek.state.db,
            mufredat_surumu=servis.mufredat_surumu_sec(istek.state.db, sinif),
            kazanim_kodu=kazanim_kodu,
            sinif=sinif,
            metin=metin,
            rubrik=rubrik,
            zorluk=zorluk,
        )
        return RedirectResponse(f"/sorular?sinif={sinif}&mesaj=Soru+eklendi", status_code=303)

    @uygulama.post("/sorular/{soru_id}/sil")
    def soru_sil(istek: Request, soru_id: int, sinif: Annotated[int, Form()] = 9):
        so.soru_arsivle(istek.state.db, soru_id)
        return RedirectResponse(
            f"/sorular?sinif={sinif}&mesaj=Soru+arşivlendi", status_code=303
        )

    @uygulama.post("/sorular/{soru_id}/geri-al")
    def soru_geri_al(istek: Request, soru_id: int, sinif: Annotated[int, Form()] = 9):
        so.soru_geri_al(istek.state.db, soru_id)
        return RedirectResponse(
            f"/sorular?sinif={sinif}&arsiv=true&mesaj=Soru+geri+alındı", status_code=303
        )

    @uygulama.get("/sinavlar/{sube_id}", response_class=HTMLResponse)
    def sinavlar_sayfasi(istek: Request, sube_id: int, mesaj: str = ""):
        baglanti = istek.state.db
        sube = servis.sube_al(baglanti, sube_id)
        temalar: list = []
        try:
            temalar = list(mf.yukle(sube.mufredat_surumu).duzey(sube.sinif).temalar)
        except mf.MufredatYok:
            temalar = []
        return sablonlar.TemplateResponse(
            istek,
            "sinavlar.html",
            _ortak(
                istek,
                sube=sube,
                sinavlar=so.sinavlari_oku(baglanti, sube_id),
                temalar=temalar,
                soru_sayisi=len(so.sorulari_oku(baglanti, sinif=sube.sinif)),
                mesaj=mesaj,
            ),
        )

    @uygulama.post("/sinavlar/{sube_id}/uret")
    async def sinav_uret(istek: Request, sube_id: int):
        baglanti = istek.state.db
        veri = await istek.form()
        sube = servis.sube_al(baglanti, sube_id)
        # Virgüllü ondalık ("60,5") de kabul edilir: süzgeç `_sayi` ile
        # yapılıp değer `float()` ile yeniden çözülünce 500 alınıyordu.
        dagilim: dict[str, float] = {}
        for anahtar, deger in veri.items():
            if not anahtar.startswith("t_"):
                continue
            sayi = _sayi(str(deger))
            if sayi and sayi > 0:
                dagilim[anahtar.removeprefix("t_")] = sayi
        if not dagilim:
            return RedirectResponse(
                f"/sinavlar/{sube_id}?mesaj=En+az+bir+temaya+yüzde+verin", status_code=303
            )
        try:
            _, _, uyarilar = so.sinav_uret_ve_kaydet(
                baglanti,
                sube_id=sube_id,
                sube_adi=sube.ad,
                sinif=sube.sinif,
                mufredat_surumu=sube.mufredat_surumu,
                ad=str(veri.get("ad") or "Yazılı Sınav"),
                dagilim=dagilim,
                soru_sayisi=int(str(veri.get("soru_sayisi") or 8)),
                sure_dk=int(str(veri.get("sure_dk") or 40)),
                gruplar=("A", "B") if veri.get("ab_grubu") else ("A",),
                tarih=str(veri.get("tarih") or ""),
            )
        except Exception as hata:  # noqa: BLE001 - kullanıcıya iletilecek tek mesaj
            return RedirectResponse(f"/sinavlar/{sube_id}?mesaj={hata}", status_code=303)
        mesaj = " ".join(uyarilar) or "Sınav üretildi"
        return RedirectResponse(f"/sinavlar/{sube_id}?mesaj={mesaj}", status_code=303)

    @uygulama.get("/sinav/{sinav_id}", response_class=HTMLResponse)
    def sinav_detay(istek: Request, sinav_id: int, mesaj: str = ""):
        baglanti = istek.state.db
        kayit = so.sinav_kaydi(baglanti, sinav_id)
        if kayit is None:
            return RedirectResponse("/?mesaj=Sınav+bulunamadı", status_code=303)
        sinav = so.sinavi_yukle(baglanti, sinav_id)
        return sablonlar.TemplateResponse(
            istek,
            "sinav_detay.html",
            _ortak(
                istek,
                sinav_id=sinav_id,
                sinav=sinav,
                sube_id=kayit["sube_id"],
                ogrenciler=servis.ogrencileri_oku(baglanti, kayit["sube_id"]),
                puanlar=so.sinav_puanlari(baglanti, sinav_id),
                analiz=so.sinav_kazanim_analizi(baglanti, sinav_id),
                revizyon=depo.revizyon_oku(baglanti, f"sinav:{sinav_id}"),
                mesaj=mesaj,
            ),
        )

    @uygulama.post("/sinav/{sinav_id}/puanla")
    async def sinav_puanla(istek: Request, sinav_id: int):
        baglanti = istek.state.db
        veri = await istek.form()
        beklenen_revizyon = _form_revizyonu(veri)
        # Sorunun kendi puanı üst sınırdır: eskiden yalnız negatif değer
        # engelleniyordu, 25 puanlık soruya 52 yazılabiliyor ve kazanım analizi
        # o kazanım için %208 başarı raporluyordu.
        tavanlar = {s.id: s.puan for s in so.sinavi_yukle(baglanti, sinav_id).sorular}

        puanlar: list[tuple[int, int, float]] = []
        silinecekler: list[tuple[int, int]] = []
        gecersizler: list[str] = []
        for anahtar, deger in veri.items():
            if not anahtar.startswith("p_"):
                continue
            _, soru_id, ogrenci_id = anahtar.split("_")
            cozum = _sayi_ayir(str(deger))
            if cozum is BOS:
                # Boşaltma bir SİLME isteğidir; eskiden atlanıyordu ve yanlış
                # girilmiş bir puan hiçbir yoldan geri alınamıyordu.
                silinecekler.append((int(soru_id), int(ogrenci_id)))
                continue
            tavan = tavanlar.get(int(soru_id))
            if cozum is None or float(cozum) < 0 or (tavan is not None and float(cozum) > tavan):
                gecersizler.append(str(deger))
                continue
            puanlar.append((int(soru_id), int(ogrenci_id), float(cozum)))
        try:
            with depo.islem(baglanti, immediate=True):
                _revizyon_ilerlet(
                    baglanti, f"sinav:{sinav_id}", beklenen_revizyon
                )
                so.soru_puani_yaz(baglanti, sinav_id, puanlar)
                so.soru_puani_sil(baglanti, sinav_id, silinecekler)
        except ValueError as hata:
            return PlainTextResponse(str(hata), status_code=409)
        mesaj = "Puanlar kaydedildi"
        if gecersizler:
            mesaj += (
                f" — {len(gecersizler)} değer kabul edilmedi (0 ile sorunun puanı arasında "
                "olmalı): " + ", ".join(sorted(set(gecersizler))[:5])
            )
        return RedirectResponse(f"/sinav/{sinav_id}?mesaj={mesaj}", status_code=303)

    @uygulama.get("/sinav/{sinav_id}/indir")
    def sinav_indir(istek: Request, sinav_id: int, grup: str = "A", tur: str = "kagit"):
        baglanti = istek.state.db
        sinav = so.sinavi_yukle(baglanti, sinav_id)
        okul, ogretmen = servis.belge_kunyesi(baglanti)
        if tur == "anahtar":
            return _dosya_yaniti(
                pdf.html_pdfe(belge.cevap_anahtari(sinav, okul=okul), yatay=True),
                f"{sinav.sube_adi}-cevap-anahtari.pdf",
                "application/pdf",
            )
        if tur == "analiz":
            analiz = so.sinav_kazanim_analizi(baglanti, sinav_id)
            ogrenciler = [
                {"numara": v["numara"], "ad_soyad": v["ad_soyad"], "kazanimlar": v["kazanimlar"]}
                for v in analiz["ogrenciler"].values()
            ]
            return _dosya_yaniti(
                excel.kazanim_analizi_xlsx(ogrenciler, analiz["kazanimlar"], sube_adi=sinav.sube_adi),
                f"{sinav.sube_adi}-kazanim-analizi.xlsx",
                XLSX_MIME,
            )
        return _dosya_yaniti(
            pdf.html_pdfe(belge.sinav_kagidi(sinav, grup, okul=okul, ogretmen=ogretmen)),
            f"{sinav.sube_adi}-{grup}-grubu.pdf",
            "application/pdf",
        )

    @uygulama.post("/sinav/{sinav_id}/sil")
    def sinav_sil(istek: Request, sinav_id: int, sube_id: Annotated[int, Form()]):
        so.sinav_sil(istek.state.db, sinav_id, sube_id=sube_id)
        return RedirectResponse(f"/sinavlar/{sube_id}?mesaj=Sınav+silindi", status_code=303)
