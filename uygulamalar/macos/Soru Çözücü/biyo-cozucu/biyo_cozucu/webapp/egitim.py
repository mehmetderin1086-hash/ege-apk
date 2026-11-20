"""Eğitim verisi dışa aktarma ve model/adaptör yönetimi rotaları."""

from __future__ import annotations

from pathlib import Path

from fastapi import APIRouter, Form, Request
from fastapi.responses import FileResponse, HTMLResponse, RedirectResponse

from ..veri.disa_aktar import bol, egitim_verisi_yaz
from .durum import Uygulama
from .yardimcilar import hata_yaniti


def yonlendirici(durum: Uygulama, sablon) -> APIRouter:
    yonlendirici = APIRouter()

    @yonlendirici.get("/egitim", response_class=HTMLResponse)
    def egitim_sayfasi(request: Request):
        ornekler = durum.depo.ornekler()
        egitim, dogrulama, test = bol(ornekler) if ornekler else ([], [], [])
        return sablon.TemplateResponse(
            request,
            "egitim.html",
            {
                "durum": durum.durum(),
                "onizleme": {
                    "egitim": len(egitim),
                    "dogrulama": len(dogrulama),
                    "test": len(test),
                },
                "surumler": durum.depo.egitim_surumleri(),
            },
        )

    @yonlendirici.post("/egitim/disa-aktar")
    def disa_aktar(
        request: Request,
        etiket: str = Form("v1"),
        kanitli: str = Form("evet"),
        kanit_sayisi: int = Form(2),
    ):
        ornekler = durum.depo.ornekler()
        if not ornekler:
            return hata_yaniti(
                sablon, durum, request,
                "Hafızada hiç örnek yok; dışa aktarılacak bir şey bulunamadı.",
                baslik="Dışa aktarma yapılamadı",
                oneri="Önce birkaç referans örnek ekleyin.",
                geri="/ornek/toplu",
            )
        # Etiket dosya yolu oluşturuyor: dizin kaçışına izin verilmemeli.
        # Noktaya izin veriliyor ("v1.2" meşru), ama yalnız noktalardan oluşan
        # bir etiket ("." / "..") hedefi bir üst dizine taşırdı.
        guvenli_etiket = "".join(
            k for k in etiket.strip() if k.isalnum() or k in "-_."
        ).strip(".") or "surum"
        hedef = (durum.kok / "egitim" / guvenli_etiket).resolve()
        egitim_koku = (durum.kok / "egitim").resolve()
        if not hedef.is_relative_to(egitim_koku):
            return hata_yaniti(
                sablon, durum, request,
                "Geçersiz sürüm etiketi.", baslik="Dışa aktarma yapılamadı",
                geri="/egitim",
            )
        if hedef.exists():
            return hata_yaniti(
                sablon, durum, request,
                f"'{guvenli_etiket}' sürümü zaten var.",
                kod=409, baslik="Sürüm çakışması",
                oneri="Eski dışa aktarımı sessizce ezmemek için farklı bir etiket verin.",
                geri="/egitim",
            )
        ozet = egitim_verisi_yaz(
            ornekler,
            hedef,
            etiket=guvenli_etiket,
            kanitli=kanitli == "evet",
            kanit_sayisi=max(0, min(5, int(kanit_sayisi))),
            gomlemci=durum.gomlemci,
        )
        durum.depo.egitim_surumu_ekle(
            ozet.etiket, str(ozet.dizin), ozet.egitim, ozet.dogrulama,
            notlar=f"kanitli={ozet.kanitli}",
        )
        durum.depo.denetim_yaz("egitim_disa_aktar", f"{ozet.etiket}: {ozet.egitim} kayıt")
        return RedirectResponse("/egitim", status_code=303)

    @yonlendirici.get("/egitim/indir/{surum_id}/{dosya}")
    def indir(request: Request, surum_id: int, dosya: str):
        # Beyaz liste: dosya adı yol parçası olarak kullanıldığından
        # serbest bırakmak dizin kaçışına açık kapı bırakırdı.
        if dosya not in {"train.jsonl", "valid.jsonl", "test.jsonl", "ozet.json"}:
            return hata_yaniti(
                sablon, durum, request,
                f"'{dosya}' indirilebilir dosyalar arasında değil.",
                baslik="İndirme reddedildi", geri="/egitim",
            )
        for satir in durum.depo.egitim_surumleri():
            if int(satir["id"]) == surum_id:
                yol = Path(satir["yol"]) / dosya
                if not yol.is_file():
                    return hata_yaniti(
                        sablon, durum, request,
                        f"'{dosya}' bu sürümün dizininde bulunamadı.",
                        kod=404, baslik="Dosya bulunamadı", geri="/egitim",
                    )
                return FileResponse(yol, filename=f"{satir['etiket']}-{dosya}")
        return hata_yaniti(
            sablon, durum, request,
            f"#{surum_id} numaralı eğitim sürümü bulunamadı.",
            kod=404, baslik="Sürüm bulunamadı", geri="/egitim",
        )

    return yonlendirici
