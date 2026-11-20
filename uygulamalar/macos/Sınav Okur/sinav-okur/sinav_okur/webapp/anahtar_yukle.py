"""Cevap anahtarını dosyadan veya fotoğraf/PDF'ten yükleme akışı.

Her iki giriş de aynı iki adımdan geçer: **önizleme** (depoya hiçbir şey
yazılmaz; ayrıştırılan anahtar, hata/uyarılar ve mevcut puanlara etkisi
gösterilir) ve **uygula** (öğretmen onaylarsa anahtar sürümlenir ve kâğıtlar
yeniden puanlanır). Ayrıştırmada tek bir hata varsa uygula düğmesi açılmaz.
"""

from __future__ import annotations

import hashlib
import json
from dataclasses import asdict
from pathlib import Path
from uuid import uuid4

from fastapi import APIRouter, File, Form, HTTPException, Request, UploadFile
from fastapi.responses import HTMLResponse, RedirectResponse
from starlette.concurrency import run_in_threadpool

from .baglam import WebBaglam

DOSYA_UZANTILARI = {".csv", ".xlsx", ".json", ".yaml", ".yml"}
BELGE_UZANTILARI = {".png", ".jpg", ".jpeg", ".heic", ".heif", ".pdf"}
# Taslak dosyaları uygulama adımına kadar diskte bekler; eski taslaklar
# birikmesin diye her yüklemede bu yaştan eskiler silinir.
TASLAK_OMRU_SANIYE = 24 * 60 * 60


def rota_kur(baglam: WebBaglam) -> APIRouter:
    router = APIRouter()
    sablonlar = baglam.sablonlar
    depo = baglam.depo
    taslak_dizini = baglam.veri_kok / "anahtar_taslaklari"

    def _sinav(kimlik: str):
        try:
            return depo.sinav_yukle(kimlik)
        except KeyError as exc:
            raise HTTPException(404, "Sınav bulunamadı") from exc

    def _eski_taslaklari_temizle() -> None:
        import time

        if not taslak_dizini.is_dir():
            return
        simdi = time.time()
        # gelen/ altındaki yüklemeler normalde işlem sonunda silinir; uygulama
        # uzun bir OCR sırasında kapatılırsa orada kalır ve başka temizlik
        # onlara dokunmaz.
        for yol in (*taslak_dizini.glob("*.json"), *(taslak_dizini / "gelen").glob("*")):
            try:
                if yol.is_file() and simdi - yol.stat().st_mtime > TASLAK_OMRU_SANIYE:
                    yol.unlink()
            except OSError:
                continue

    def _sinav_parmakizi(sinav) -> str:
        """Önizlemenin dayandığı anahtar durumunun özeti."""
        from dataclasses import asdict as _asdict

        ham = json.dumps(
            [
                {"no": s.no, "tip": s.tip.value, "anahtar": _asdict(s.anahtar)}
                for s in sinav.sorular
            ],
            ensure_ascii=False,
            sort_keys=True,
        )
        return hashlib.sha256(ham.encode("utf-8")).hexdigest()

    def _taslagi_yaz(kimlik: str, sinav, sonuc) -> str:
        taslak_dizini.mkdir(parents=True, exist_ok=True)
        _eski_taslaklari_temizle()
        token = uuid4().hex
        veri = {
            "kimlik": kimlik,
            # Önizlemenin dayandığı sınav durumu: uygulama anında anahtar
            # başka bir sekmede değişmişse o değişikliği sessizce ezmeyelim.
            "parmakizi": _sinav_parmakizi(sinav),
            "sorular": {
                str(no): {"tip": tip.value, "anahtar": asdict(anahtar)}
                for no, (tip, anahtar) in sonuc.sorular.items()
            },
        }
        (taslak_dizini / f"{token}.json").write_text(
            json.dumps(veri, ensure_ascii=False), encoding="utf-8"
        )
        return token

    def _taslagi_tuket(kimlik: str, sinav, token: str) -> dict:
        """Taslağı okur ve aynı anda tüketir (çift uygulamayı engeller)."""
        import time

        # Token dosya adı olarak kullanılıyor; yol kaçışını engellemek için
        # yalnız onaltılık karakterler kabul edilir.
        if not token or not all(c in "0123456789abcdef" for c in token):
            raise HTTPException(400, "Geçersiz taslak kimliği.")
        yol = taslak_dizini / f"{token}.json"
        tuketilen = taslak_dizini / f"{token}.uygulanan"
        try:
            # rename atomiktir: eşzamanlı ikinci POST burada FileNotFoundError
            # alır ve yeniden puanlama iki kez çalışmaz.
            yol.rename(tuketilen)
        except OSError as exc:
            raise HTTPException(
                404, "Yükleme taslağı bulunamadı; dosyayı yeniden yükleyin."
            ) from exc
        try:
            yas = time.time() - tuketilen.stat().st_mtime
            veri = json.loads(tuketilen.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            tuketilen.unlink(missing_ok=True)
            raise HTTPException(400, "Yükleme taslağı okunamadı.") from exc
        finally:
            tuketilen.unlink(missing_ok=True)
        if yas > TASLAK_OMRU_SANIYE:
            raise HTTPException(
                400, "Bu yükleme önizlemesi eskimiş; dosyayı yeniden yükleyin."
            )
        if veri.get("kimlik") != kimlik:
            raise HTTPException(400, "Taslak bu sınava ait değil.")
        if veri.get("parmakizi") != _sinav_parmakizi(sinav):
            raise HTTPException(
                409,
                "Cevap anahtarı bu önizlemeden sonra değişti. Değişikliği "
                "ezmemek için dosyayı yeniden yükleyip önizleyin.",
            )
        return veri

    def _yeni_sinav_kur(sinav, sonuc_sorulari: dict):
        """Ayrıştırılan anahtarları mevcut sınava işleyip yeni Sinav döndürür."""
        from ..modeller import Sinav, Soru

        yeni_sorular = []
        for soru in sinav.sorular:
            secim = sonuc_sorulari.get(soru.no)
            if secim is None:
                yeni_sorular.append(soru)
                continue
            tip, anahtar = secim
            yeni_sorular.append(
                Soru(
                    no=soru.no,
                    tip=tip,
                    metin=soru.metin,
                    puan=soru.puan,
                    anahtar=anahtar,
                    kutu_yuksekligi_mm=soru.kutu_yuksekligi_mm,
                    kazanımlar=list(soru.kazanımlar),
                    esneklik=soru.esneklik,
                )
            )
        return Sinav(
            kimlik=sinav.kimlik,
            baslik=sinav.baslik,
            ders=sinav.ders,
            sorular=yeni_sorular,
        )

    def _onizleme_yaniti(
        request: Request, kimlik: str, sinav, sonuc, *, kaynak: str, ocr_metni=""
    ):
        from ..anahtar_duzen import anahtar_etkisini_onizle

        token = None
        etki = None
        satirlar = []
        if sonuc.uygulanabilir:
            try:
                yeni = _yeni_sinav_kur(sinav, sonuc.sorular)
            except ValueError as exc:
                # Soru modeli tip/anahtar uyumunu kendi doğruluyor; buradaki
                # ValueError öğretmene 500 değil, okunur bir hata olmalı.
                sonuc.hatalar.append(str(exc))
                sonuc.sorular = {}
            else:
                etki = anahtar_etkisini_onizle(
                    depo,
                    sinav,
                    yeni,
                    gomlemci=baglam.gomlemci(),
                    referans_indeks_dizini=baglam.referans_indeks_dizini,
                )
                token = _taslagi_yaz(kimlik, sinav, sonuc)
            for no in sorted(sonuc.sorular):
                tip, anahtar = sonuc.sorular[no]
                satirlar.append(
                    {
                        "soru_no": no,
                        "tip": tip.value,
                        "ozet": _anahtar_ozeti(anahtar),
                        "otomatik_puanlama": anahtar.otomatik_puanlama,
                        "onay_durumu": anahtar.onay_durumu,
                    }
                )
        return sablonlar.TemplateResponse(
            request,
            "anahtar_yukle.html",
            {
                "kimlik": kimlik,
                "sinav": sinav,
                "sonuc": sonuc,
                "satirlar": satirlar,
                "onizleme": etki,
                "token": token,
                "kaynak": kaynak,
                "ocr_metni": ocr_metni,
                "yerel_motor": baglam._yerel_motor_durumu(),
            },
        )

    def _anahtar_ozeti(anahtar) -> str:
        if anahtar.dogru_cevaplar:
            return " · ".join(anahtar.dogru_cevaplar)
        if anahtar.siralama:
            return " → ".join(anahtar.siralama)
        if anahtar.eslestirmeler:
            return " · ".join(f"{k} → {v}" for k, v in anahtar.eslestirmeler.items())
        return " · ".join(k.metin for k in anahtar.rubrik)

    @router.get("/sinav/{kimlik}/anahtar/yukle", response_class=HTMLResponse)
    def anahtar_yukle_formu(request: Request, kimlik: str):
        sinav = _sinav(kimlik)
        return sablonlar.TemplateResponse(
            request,
            "anahtar_yukle.html",
            {
                "kimlik": kimlik,
                "sinav": sinav,
                "sonuc": None,
                "satirlar": [],
                "onizleme": None,
                "token": None,
                "kaynak": None,
                "ocr_metni": "",
                "yerel_motor": baglam._yerel_motor_durumu(),
            },
        )

    @router.post("/sinav/{kimlik}/anahtar/yukle/dosya", response_class=HTMLResponse)
    async def anahtar_dosyasi_yukle(
        request: Request,
        kimlik: str,
        anahtar_dosyasi: UploadFile = File(...),
    ):
        from ..anahtar_dosya import AnahtarYuklemeSonucu, dosyadan_anahtar_uret

        sinav = _sinav(kimlik)
        try:
            gecici = await baglam._yuklemeyi_kaydet(
                anahtar_dosyasi,
                taslak_dizini / "gelen",
                DOSYA_UZANTILARI,
                azami_bayt=20 * 1024 * 1024,
            )
        except ValueError as exc:
            return _onizleme_yaniti(
                request,
                kimlik,
                sinav,
                AnahtarYuklemeSonucu(hatalar=[str(exc)]),
                kaynak="dosya",
            )
        # _yuklemeyi_kaydet geçici dosyayı "<uuid><özgün uzantı>" diye
        # adlandırıyor; ayrıştırıcı biçimi bu uzantıdan seçiyor.
        try:
            sonuc = await run_in_threadpool(dosyadan_anahtar_uret, gecici, sinav)
        finally:
            gecici.unlink(missing_ok=True)
        return _onizleme_yaniti(request, kimlik, sinav, sonuc, kaynak="dosya")

    @router.post("/sinav/{kimlik}/anahtar/yukle/belge", response_class=HTMLResponse)
    async def anahtar_belgesi_yukle(
        request: Request,
        kimlik: str,
        anahtar_belgeleri: list[UploadFile] = File(...),
    ):
        from ..anahtar_dosya import AnahtarYuklemeSonucu
        from ..anahtar_ocr import (
            anahtar_belgesinden_metin,
            metinden_anahtar_ayristir,
        )

        sinav = _sinav(kimlik)
        belgeler = [d for d in anahtar_belgeleri if d.filename]
        if not belgeler:
            return _onizleme_yaniti(
                request,
                kimlik,
                sinav,
                AnahtarYuklemeSonucu(hatalar=["Anahtar fotoğrafı/PDF'i seçilmedi."]),
                kaynak="belge",
            )
        yollar: list[Path] = []
        ocr_metni = ""
        # Tek dış finally: ikinci dosyada OSError çıksa bile ilk dosya silinir.
        try:
            try:
                for belge in belgeler:
                    yollar.append(
                        await baglam._yuklemeyi_kaydet(
                            belge, taslak_dizini / "gelen", BELGE_UZANTILARI
                        )
                    )

                taniyici = _taniyici_al()
                ocr_metni = await run_in_threadpool(
                    anahtar_belgesinden_metin, yollar, taniyici
                )
                # OCR bittikten SONRA model çağrılır: 16 GB'lık makinede OCR
                # havuzu ve MLX modeli aynı anda yüklenirse bellek yetmiyor.
                sonuc = await run_in_threadpool(
                    metinden_anahtar_ayristir, ocr_metni, sinav, _uret_al()
                )
            except ValueError as exc:
                sonuc = AnahtarYuklemeSonucu(hatalar=[str(exc)])
            except (OSError, RuntimeError) as exc:
                sonuc = AnahtarYuklemeSonucu(
                    hatalar=[f"Belge okunamadı: {exc}"]
                )
        finally:
            for yol in yollar:
                yol.unlink(missing_ok=True)
        return _onizleme_yaniti(
            request, kimlik, sinav, sonuc, kaynak="belge", ocr_metni=ocr_metni
        )

    def _taniyici_al():
        if baglam.taniyici_fabrikasi is not None:
            return baglam.taniyici_fabrikasi()
        from ..htr import taniyici_yukle

        onbellek = baglam.taniyici_onbellegi
        if "anahtar_ocr" not in onbellek:
            onbellek["anahtar_ocr"] = taniyici_yukle("coklu")
        return onbellek["anahtar_ocr"]

    def _uret_al():
        if baglam.yerel_uret is not None:
            return baglam.yerel_uret
        from ..yerel_motor import yerel_uret

        return yerel_uret

    @router.post("/sinav/{kimlik}/anahtar/yukle/uygula")
    def anahtar_yuklemesini_uygula(kimlik: str, token: str = Form(...)):
        from ..modeller import CevapAnahtari, RubrikKalemi, SoruTipi

        sinav = _sinav(kimlik)
        veri = _taslagi_tuket(kimlik, sinav, token)
        sorular: dict[int, tuple] = {}
        for ham_no, kayit in veri.get("sorular", {}).items():
            ham_anahtar = dict(kayit["anahtar"])
            ham_anahtar["rubrik"] = [
                RubrikKalemi(**k) for k in ham_anahtar.get("rubrik", [])
            ]
            sorular[int(ham_no)] = (
                SoruTipi(kayit["tip"]),
                CevapAnahtari(**ham_anahtar),
            )
        if not sorular:
            raise HTTPException(400, "Uygulanacak anahtar bulunamadı.")
        try:
            yeni = _yeni_sinav_kur(sinav, sorular)
        except ValueError as exc:
            raise HTTPException(400, str(exc)) from exc
        guncellenen, korunan = baglam._anahtari_uygula(kimlik, yeni)
        return RedirectResponse(
            f"/sinav/{kimlik}/anahtar?uygulandi={guncellenen}&korunan={korunan}",
            status_code=303,
        )

    return router
