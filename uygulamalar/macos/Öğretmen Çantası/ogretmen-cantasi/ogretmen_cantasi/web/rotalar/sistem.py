"""Ayarlar, yedekleme/dışa aktarma ve sağlık uç noktası."""

from __future__ import annotations

import hashlib
import io
import json
from datetime import date, datetime

from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse, RedirectResponse

from ... import ayarlar as ayar_modulu
from ... import depo, servis, yardimci
from ... import mufredat as mf
from ... import ses as ses_modulu
from ..ortak import _dosya_yaniti, _ortak, _uygulama_surumu, sablonlar


def bagla(uygulama: FastAPI) -> None:
    # --- ayarlar ve yedek ------------------------------------------------

    @uygulama.get("/ayarlar", response_class=HTMLResponse)
    def ayarlar_sayfasi(istek: Request, mesaj: str = ""):
        yardimci.mufredat_kaynagini_kaydet(istek.state.db)
        yedekler = sorted(ayar_modulu.yedek_dizini().glob("*.db"), reverse=True)[:10]
        return sablonlar.TemplateResponse(
            istek,
            "ayarlar.html",
            _ortak(
                istek,
                mesaj=mesaj,
                yedekler=[(y.name, y.stat().st_size) for y in yedekler],
                veri_yolu=str(ayar_modulu.veritabani_yolu()),
                ses_durumu=ses_modulu.durum(),
                surumler=mf.mevcut_surumler(),
                mufredat_kaynaklari=istek.state.db.execute(
                    "SELECT * FROM mufredat_kaynagi WHERE etkin = 1 ORDER BY surum"
                ).fetchall(),
            ),
        )

    @uygulama.post("/ayarlar")
    async def ayarlar_kaydet(istek: Request):
        veri = await istek.form()
        uyarilar = servis.ayarlari_yaz(istek.state.db, {a: str(d) for a, d in veri.items()})
        mesaj = "Ayarlar kaydedildi"
        if uyarilar:
            mesaj += " — kabul edilmeyenler: " + "; ".join(uyarilar)
        return RedirectResponse(f"/ayarlar?mesaj={mesaj}", status_code=303)

    @uygulama.post("/yedek/al")
    def yedek_al(istek: Request):
        hedef = depo.yedekle()
        return RedirectResponse(
            f"/ayarlar?mesaj=Yedek+alındı:+{hedef.name if hedef else 'yok'}", status_code=303
        )

    @uygulama.get("/yedek/disa-aktar")
    def yedek_disa_aktar(istek: Request):
        import zipfile

        tampon = io.BytesIO()
        snapshot = depo.anlik_goruntu_baytlari()
        with zipfile.ZipFile(tampon, "w", zipfile.ZIP_DEFLATED) as paket:
            if snapshot:
                paket.writestr("veri.db", snapshot)
            materyaller = ayar_modulu.materyal_dizini()
            for dosya in materyaller.rglob("*"):
                if dosya.is_file() and not dosya.is_symlink():
                    paket.write(dosya, f"materyaller/{dosya.relative_to(materyaller)}")
            baglanti = istek.state.db
            sema = depo.sema_surumu(baglanti)
            yil = servis.aktif_yil(baglanti)
            paket.writestr(
                "künye.json",
                json.dumps(
                    {
                        "uygulama": ayar_modulu.UYGULAMA_ADI,
                        "surum": _uygulama_surumu(),
                        "sema_surumu": sema,
                        "ogretim_yili": yil.ad if yil else "",
                        "tarih": datetime.now().isoformat(),
                        "veri_sha256": hashlib.sha256(snapshot).hexdigest()
                        if snapshot
                        else "",
                    },
                    ensure_ascii=False,
                ),
            )
        ad = f"ogretmen-cantasi-{date.today().isoformat()}.zip"
        return _dosya_yaniti(tampon.getvalue(), ad, "application/zip")

    # --- sağlık ----------------------------------------------------------

    @uygulama.get("/saglik")
    def saglik():
        """Başlatıcının 'portta gerçekten bu program mı' kontrolü buraya bakar."""
        return {
            "uygulama": ayar_modulu.IMZA,
            "surum": _uygulama_surumu(),
            "sema_surumu": len(depo.GECISLER),
            "durum": "hazır",
        }
