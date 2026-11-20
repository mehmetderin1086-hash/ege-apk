"""Not tablosu ve değerlendirme yönetimi."""

from __future__ import annotations

from typing import Annotated

from fastapi import FastAPI, Form, Request
from fastapi.responses import HTMLResponse, PlainTextResponse, RedirectResponse

from ... import depo, servis
from ... import notlar as nt
from ...cikti import excel
from ..ortak import (
    BOS,
    XLSX_MIME,
    _dosya_yaniti,
    _form_revizyonu,
    _ortak,
    _revizyon_ilerlet,
    _sayi_ayir,
    sablonlar,
)


def bagla(uygulama: FastAPI) -> None:
    @uygulama.get("/notlar/{sube_id}", response_class=HTMLResponse)
    def notlar_sayfasi(istek: Request, sube_id: int, mesaj: str = ""):
        baglanti = istek.state.db
        sube = servis.sube_al(baglanti, sube_id)
        satirlar, degerlendirmeler = servis.not_tablosu(baglanti, sube_id)
        karneler = servis.karneler(baglanti, sube_id)
        return sablonlar.TemplateResponse(
            istek,
            "notlar.html",
            _ortak(
                istek,
                sube=sube,
                satirlar=satirlar,
                degerlendirmeler=degerlendirmeler,
                tur_adlari=nt.TUR_ADLARI,
                istatistik={
                    d: nt.sinif_istatistigi(karneler, d, servis.not_kurallari(baglanti))
                    for d in (1, 2)
                },
                kurallar=servis.not_kurallari(baglanti),
                revizyon=depo.revizyon_oku(baglanti, f"notlar:{sube_id}"),
                mesaj=mesaj,
            ),
        )

    @uygulama.post("/notlar/{sube_id}/degerlendirme")
    def degerlendirme_ekle(
        istek: Request,
        sube_id: int,
        ad: Annotated[str, Form()],
        tur: Annotated[str, Form()],
        donem: Annotated[int, Form()],
        tarih: Annotated[str, Form()] = "",
    ):
        baglanti = istek.state.db
        # Sütun kümesi değişti: açık not formları bayatladı. SQLite silinen
        # kimliği yeniden kullanabildiğinden, revizyon ilerletilmezse eski
        # formdaki puan yeni değerlendirmeye yazılabiliyordu. Mutasyonla aynı
        # işlemde artar ki ikisi birlikte görünür olsun.
        with depo.islem(baglanti, immediate=True):
            servis.degerlendirme_ekle(baglanti, sube_id, donem, tur, ad.strip(), tarih=tarih)
            _revizyon_ilerlet(baglanti, f"notlar:{sube_id}", None)
        return RedirectResponse(f"/notlar/{sube_id}?mesaj=Değerlendirme+eklendi", status_code=303)

    @uygulama.post("/notlar/{sube_id}/degerlendirme/{degerlendirme_id}/sil")
    def degerlendirme_sil(istek: Request, sube_id: int, degerlendirme_id: int):
        baglanti = istek.state.db
        with depo.islem(baglanti, immediate=True):
            servis.degerlendirme_sil(baglanti, degerlendirme_id, sube_id=sube_id)
            _revizyon_ilerlet(baglanti, f"notlar:{sube_id}", None)
        return RedirectResponse(f"/notlar/{sube_id}?mesaj=Silindi", status_code=303)

    @uygulama.post("/notlar/{sube_id}/kaydet")
    async def notlar_kaydet(istek: Request, sube_id: int):
        baglanti = istek.state.db
        veri = await istek.form()
        beklenen_revizyon = _form_revizyonu(veri)
        # Üst sınır değerlendirmenin kendi tam puanından gelir; 100 gömmek,
        # farklı tam puanlı bir değerlendirme tanımlandığında yanlış olur.
        tam_puanlar = {
            d["id"]: d["tam_puan"] for d in servis.degerlendirmeleri_oku(baglanti, sube_id)
        }
        gruplu: dict[int, dict[int, float | None]] = {}
        gecersizler: list[str] = []
        for anahtar, deger in veri.items():
            if not anahtar.startswith("n_"):
                continue
            _, degerlendirme_id, ogrenci_id = anahtar.split("_")
            cozum = _sayi_ayir(str(deger))
            if cozum is None:
                # Geçersiz değer kaydı SİLMEZ: eski puan olduğu gibi kalır.
                gecersizler.append(str(deger))
                continue
            tavan = tam_puanlar.get(int(degerlendirme_id), 100.0)
            if cozum is not BOS and not (0 <= float(cozum) <= tavan):
                gecersizler.append(str(deger))
                continue
            gruplu.setdefault(int(degerlendirme_id), {})[int(ogrenci_id)] = (
                None if cozum is BOS else float(cozum)
            )
        try:
            with depo.islem(baglanti, immediate=True):
                _revizyon_ilerlet(
                    baglanti, f"notlar:{sube_id}", beklenen_revizyon
                )
                for degerlendirme_id, puanlar in gruplu.items():
                    servis.not_yaz(baglanti, degerlendirme_id, puanlar)
        except ValueError as hata:
            return PlainTextResponse(str(hata), status_code=409)
        mesaj = "Notlar kaydedildi"
        if gecersizler:
            mesaj += (
                f" — {len(gecersizler)} değer kabul edilmedi (0 ile değerlendirmenin tam puanı arasında olmalı): "
                + ", ".join(sorted(set(gecersizler))[:5])
                + ". Bu hücrelerdeki eski notlar korundu."
            )
        return RedirectResponse(f"/notlar/{sube_id}?mesaj={mesaj}", status_code=303)

    @uygulama.get("/notlar/{sube_id}/indir")
    def notlar_indir(istek: Request, sube_id: int, tur: str = "notlar"):
        baglanti = istek.state.db
        sube = servis.sube_al(baglanti, sube_id)
        if tur == "devamsizlik":
            return _dosya_yaniti(
                excel.devamsizlik_xlsx(servis.devamsizlik_tablosu(baglanti, sube_id), sube_adi=sube.ad),
                f"{sube.ad}-devamsizlik.xlsx",
                XLSX_MIME,
            )
        satirlar, degerlendirmeler = servis.not_tablosu(baglanti, sube_id)
        return _dosya_yaniti(
            excel.not_cizelgesi_xlsx(satirlar, degerlendirmeler, sube_adi=sube.ad),
            f"{sube.ad}-notlar.xlsx",
            XLSX_MIME,
        )
