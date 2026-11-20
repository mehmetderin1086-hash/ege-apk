"""Kâğıt/serbest sınav yükleme, toplu işleme ve OCR modeli seçimi."""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import threading
import time
from functools import partial
from importlib.util import find_spec
from pathlib import Path
from uuid import uuid4

from fastapi import APIRouter, File, Form, HTTPException, Request, UploadFile
from fastapi.responses import FileResponse, HTMLResponse, RedirectResponse
from starlette.concurrency import run_in_threadpool

from .baglam import WebBaglam
from ..anahtar_duzen import formdan_anahtar_uret, rag_anahtarini_kur

# TrOCR topluluk ağırlığı. Model gerçek el yazısında doğrulanmadığı için
# Apple Vision'ın (1.0) ALTINDA tutulur; bkz docs/trocr_egitim_tanisi.md.
TROCR_AGIRLIGI = 0.85


def rota_kur(baglam: WebBaglam) -> APIRouter:
    router = APIRouter()
    depo = baglam.depo
    sablonlar = baglam.sablonlar
    kirp_kok = baglam.kirp_kok
    veri_kok = baglam.veri_kok
    sinav_dizini = baglam.sinav_dizini
    yukleme_dizini = baglam.yukleme_dizini
    serbest_taslak_dizini = baglam.serbest_taslak_dizini
    referans_indeks_dizini = baglam.referans_indeks_dizini
    toplu_sonuc_dizini = baglam.toplu_sonuc_dizini
    proje_kok = baglam.proje_kok
    model_yollari = baglam.model_yollari
    taniyici_onbellegi = baglam.taniyici_onbellegi
    taniyici_fabrikasi = baglam.taniyici_fabrikasi
    serbest_cozumleyici = baglam.serbest_cozumleyici

    def _sinav_mevcut(kimlik: str) -> bool:
        try:
            depo.sinav_yukle(kimlik)
            return True
        except KeyError:
            return False

    def _sablonu_yukle(yol: str | Path):
        if not baglam._serbest_mi(yol):
            raise ValueError(
                "Bu kayıt kaldırılmış eski düzene ait. "
                "Önce yazılının boş sayfalarını yeniden tanıtın."
            )
        from ..serbest import SerbestSablon

        sablon = SerbestSablon.json_yukle(yol)
        for gorsel in sablon.sayfa_gorselleri:
            gorsel_yolu = Path(gorsel).resolve()
            try:
                gorsel_yolu.relative_to(veri_kok.resolve())
            except ValueError as exc:
                raise ValueError(
                    "Yazılı tanımının ana sayfası güvenli veri dizininin dışında."
                ) from exc
            if not gorsel_yolu.is_file():
                raise ValueError("Yazılı tanımının ana sayfa görüntüsü bulunamadı.")
        return sablon

    def _taslak_yolu(token: str) -> Path:
        if not re.fullmatch(r"[0-9a-f]{32}", token):
            raise HTTPException(404, "Serbest sınav taslağı bulunamadı")
        yol = (serbest_taslak_dizini / token).resolve()
        try:
            yol.relative_to(serbest_taslak_dizini.resolve())
        except ValueError as exc:
            raise HTTPException(403, "Geçersiz taslak yolu") from exc
        if not (yol / "taslak.json").is_file():
            raise HTTPException(404, "Serbest sınav taslağı bulunamadı")
        return yol

    def _model_secenekleri() -> list[dict]:
        trocr_hazir = (
            taniyici_fabrikasi is not None
            or (model_yollari["trocr"] / "config.json").is_file()
        )
        # Apple Vision yalnız macOS'ta çalışır; orada "çoklu" varsayılan
        # önerilen kalır, başka platformda TrOCR öne çıkarılır.
        windows_da = sys.platform != "darwin"
        return [
            {
                "deger": "coklu",
                "ad": "Çoklu OCR uzlaşması — önerilen",
                "aciklama": (
                    "Siyah kurşun kalemi gölge/kontrast varyantlarıyla okur; "
                    "kurulu bağımsız yerel motorları uzlaştırır."
                ),
                "hazir": taniyici_fabrikasi is not None or model_yollari["coklu"].exists(),
                "onerilen": True,
            },
            {
                "deger": "vision",
                "ad": "Apple Vision Türkçe OCR",
                "aciklama": (
                    "Bu Mac'te hızlı ve yerel çalışır; gerçek kâğıtta en iyi "
                    "başlangıç seçeneğidir."
                ),
                "hazir": taniyici_fabrikasi is not None or model_yollari["vision"].exists(),
                "onerilen": False,
            },
            {
                "deger": "trocr",
                "ad": "TrOCR Türkçe el yazısı",
                "aciklama": (
                    "Deneysel satır modeli; gerçek kâğıt sonucunu mutlaka "
                    "görüntüyle karşılaştırın."
                ),
                "hazir": trocr_hazir,
                "onerilen": windows_da,
            },
            {
                "deger": "keras-karakter",
                "ad": "Keras karakter modeli",
                "aciklama": "Ayrık el yazısı için hızlı; düşük güveni incelemeye gönderir.",
                "hazir": taniyici_fabrikasi is not None or model_yollari["keras-karakter"].exists(),
                "onerilen": False,
            },
            {
                "deger": "keras-ctc",
                "ad": "Keras CTC satır modeli",
                "aciklama": "Bağlı el yazısı için; izinli gerçek satır modeli kurulduğunda kullanılır.",
                "hazir": taniyici_fabrikasi is not None or model_yollari["keras-ctc"].exists(),
                "onerilen": False,
            },
            {
                "deger": "mlx",
                "ad": "Qwen3-VL görsel-dil modeli",
                "aciklama": (
                    "Kutuyu bütün olarak okur ve sorunun terimlerini ipucu "
                    "alır; yavaştır ve 4 GB bellek ister. Yalnız zor kâğıtlarda "
                    "kullanın."
                ),
                # Model HF önbelleğinden yüklenir; kurulu değilse ilk kullanımda
                # iner. Fabrika enjekte edilmişse testler için hazır sayılır.
                # mlx yalnız Apple Silicon'da çalışır (mlx_vlm paketi yoksa
                # Windows/Linux'ta bu seçenek zaten kullanılamaz).
                "hazir": (
                    taniyici_fabrikasi is not None
                    or (sys.platform == "darwin" and find_spec("mlx_vlm") is not None)
                ),
                "onerilen": False,
            },
        ]

    def _yukleme_baglami(*, hata: str | None = None, secili_sinav: str = "") -> dict:
        sinavlar = []
        for s in depo.sinavlar():
            dosyalar = depo.sinav_dosyasi(s["kimlik"])
            if not (
                dosyalar
                and dosyalar["sablon_yolu"]
                and Path(dosyalar["sablon_yolu"]).is_file()
                and baglam._serbest_mi(dosyalar["sablon_yolu"])
            ):
                continue
            try:
                sablon = _sablonu_yukle(dosyalar["sablon_yolu"])
            except (ValueError, OSError, json.JSONDecodeError):
                continue
            if sablon.sinav_kimlik != s["kimlik"]:
                continue
            sinavlar.append({"sinav": s})
        return {
            "sinavlar": sinavlar,
            "modeller": _model_secenekleri(),
            "hata": hata,
            "secili_sinav": secili_sinav,
        }

    def _taniyici_getir(tur: str):
        if tur not in model_yollari:
            raise ValueError("Bilinmeyen tanıma modeli.")
        if tur == "coklu":
            if tur not in taniyici_onbellegi:
                from ..htr.coklu import CokluTaniyici
                from ..htr.kalibrasyon import KosulluGuvenKalibrasyonu

                if taniyici_fabrikasi is not None:
                    motorlar = [
                        ("apple-vision", taniyici_fabrikasi("vision"), 1.0)
                    ]
                else:
                    from ..htr import taniyici_yukle

                    # Apple Vision yalnız macOS'ta çalışır; başka platformda
                    # hiç eklenmez ve TrOCR (kuruluysa) ilk/tek motor olur.
                    motorlar = (
                        [("apple-vision", taniyici_yukle("vision"), 1.0)]
                        if sys.platform == "darwin"
                        else []
                    )
                    if (model_yollari["trocr"] / "config.json").is_file():
                        motorlar.append(
                            (
                                "trocr",
                                taniyici_yukle(
                                    "trocr", str(model_yollari["trocr"])
                                ),
                                # 1.05 → 0.85: bu modelin CER 0.000 sonucu
                                # yalnız 15 fonttan üretilmiş SENTETİK
                                # satırlarda ölçüldü, gerçek el yazısında hiç
                                # doğrulanmadı (docs/trocr_egitim_tanisi.md:93).
                                # Doğrulanmamış bir modelin Apple Vision'ın
                                # üstünde ağırlık taşıması gerekçesizdi.
                                TROCR_AGIRLIGI,
                            )
                        )
                kalibrasyon_yolu = proje_kok / "modeller/ocr_kalibrasyon.json"
                kalibrasyon = (
                    KosulluGuvenKalibrasyonu.yukle(kalibrasyon_yolu)
                    if kalibrasyon_yolu.is_file()
                    else KosulluGuvenKalibrasyonu()
                )
                taniyici_onbellegi[tur] = CokluTaniyici(
                    motorlar, kalibrasyon=kalibrasyon
                )
            return taniyici_onbellegi[tur]
        if taniyici_fabrikasi is not None:
            if tur not in taniyici_onbellegi:
                taniyici_onbellegi[tur] = taniyici_fabrikasi(tur)
            return taniyici_onbellegi[tur]
        model_yolu = model_yollari[tur]
        if not model_yolu.exists():
            raise ValueError("Seçilen model bu Mac'te kurulu değil.")
        if tur not in taniyici_onbellegi:
            from ..htr import taniyici_yukle

            taniyici_onbellegi[tur] = taniyici_yukle(
                tur, None if tur == "vision" else str(model_yolu)
            )
        return taniyici_onbellegi[tur]

    def _ogrenci_dosya_anahtari(dosya_adi: str) -> str:
        """Toplu yüklemede ``ogrenci__sayfa`` adından öğrenci grubunu çıkar."""
        govde = Path(dosya_adi).stem
        anahtar = govde.split("__", 1)[0].strip(" _-")
        return anahtar or govde

    def _ogrenci_bilgisi(anahtar: str) -> tuple[str, str]:
        temiz = re.sub(r"[_-]+", " ", anahtar).strip()
        eslesme = re.match(r"^(\d{1,20})\s+(.+)$", temiz)
        if eslesme:
            return eslesme.group(2).strip(), eslesme.group(1)
        return temiz or "İsimsiz öğrenci", ""

    def _dogal_sira(metin: str) -> list[object]:
        return [
            int(parca) if parca.isdigit() else parca.casefold()
            for parca in re.split(r"(\d+)", metin)
        ]

    @router.get("/serbest-yukle", response_class=HTMLResponse)
    def serbest_yukle_formu(request: Request):
        from ..ocr import motor_durumlari

        return sablonlar.TemplateResponse(
            request,
            "serbest_yukle.html",
            {"hata": None, "ocr_motorlari": motor_durumlari(), "ocr_profili": "akilli"},
        )

    @router.post("/serbest-yukle", response_class=HTMLResponse)
    async def serbest_yukle(
        request: Request,
        kimlik: str = Form(...),
        baslik: str = Form(...),
        ders: str = Form(""),
        ocr_profili: str = Form("akilli"),
        kaynak_dosyalari: list[UploadFile] | None = File(None),
        kaynak_dosyasi: UploadFile | None = File(None),
    ):
        token = uuid4().hex
        hedef = serbest_taslak_dizini / token
        try:
            kimlik = kimlik.strip()
            baslik = baslik.strip()
            if not re.fullmatch(r"[A-Za-z0-9_-]{3,64}", kimlik):
                raise ValueError(
                    "Sınav kodu 3–64 karakter olmalı; yalnız harf, rakam, - ve _ kullanın."
                )
            if not baslik:
                raise ValueError("Sınav başlığı gerekli.")
            if ocr_profili not in {"hizli", "akilli", "besli"}:
                raise ValueError("Geçersiz OCR çalışma profili.")
            if _sinav_mevcut(kimlik):
                raise ValueError("Bu sınav kodu zaten kullanılıyor.")
            hedef.mkdir(parents=True, exist_ok=False)
            yuklenen_kaynaklar = [
                d for d in (kaynak_dosyalari or []) if d and d.filename
            ]
            if kaynak_dosyasi and kaynak_dosyasi.filename:
                yuklenen_kaynaklar.append(kaynak_dosyasi)
            if not yuklenen_kaynaklar or len(yuklenen_kaynaklar) > 4:
                raise ValueError("Sınav için 1–4 PDF veya fotoğraf seçin.")
            kaynak_yollari = []
            for dosya in yuklenen_kaynaklar:
                kaynak_yollari.append(
                    await baglam._yuklemeyi_kaydet(
                        dosya,
                        hedef,
                        {
                            ".pdf", ".png", ".jpg", ".jpeg",
                            ".tif", ".tiff", ".bmp", ".webp",
                            ".heic", ".heif",
                        },
                    )
                )
            cozum_kaynagi = (
                kaynak_yollari[0] if len(kaynak_yollari) == 1 else kaynak_yollari
            )
            if serbest_cozumleyici is not None:
                taslak = await run_in_threadpool(
                    serbest_cozumleyici, cozum_kaynagi, hedef, token
                )
            else:
                from ..serbest import serbest_sinav_cozumle

                taslak = await run_in_threadpool(
                    partial(
                        serbest_sinav_cozumle,
                        cozum_kaynagi,
                        hedef,
                        token=token,
                        dpi=200,
                        ocr_profili=ocr_profili,
                    )
                )
            taslak.kimlik = kimlik
            taslak.baslik = baslik
            taslak.ders = ders.strip()
            taslak.json_kaydet(hedef / "taslak.json")
            return RedirectResponse(f"/serbest/{token}", status_code=303)
        except (ValueError, OSError, subprocess.SubprocessError) as exc:
            from ..ocr import motor_durumlari

            if hedef.exists():
                shutil.rmtree(hedef)
            return sablonlar.TemplateResponse(
                request,
                "serbest_yukle.html",
                {
                    "hata": str(exc),
                    "ocr_motorlari": motor_durumlari(),
                    "ocr_profili": ocr_profili,
                },
                status_code=400,
            )

    @router.get("/serbest/{token}/sayfa/{sayfa_no}.png")
    def serbest_sayfa(token: str, sayfa_no: int):
        from ..serbest import SerbestTaslak

        hedef = _taslak_yolu(token)
        taslak = SerbestTaslak.json_yukle(hedef / "taslak.json")
        if sayfa_no < 1 or sayfa_no > len(taslak.sayfa_gorselleri):
            raise HTTPException(404, "Sayfa bulunamadı")
        yol = Path(taslak.sayfa_gorselleri[sayfa_no - 1]).resolve()
        try:
            yol.relative_to(hedef)
        except ValueError as exc:
            raise HTTPException(403, "Geçersiz sayfa yolu") from exc
        return FileResponse(yol, media_type="image/png")

    @router.get("/serbest/{token}", response_class=HTMLResponse)
    def serbest_incele(request: Request, token: str):
        from ..serbest import SerbestTaslak
        from ..yapay_zeka import claude_api_durumu

        hedef = _taslak_yolu(token)
        taslak = SerbestTaslak.json_yukle(hedef / "taslak.json")
        return sablonlar.TemplateResponse(
            request,
            "serbest_incele.html",
            {
                "taslak": taslak,
                "token": token,
                "hata": None,
                "yapay_zeka_durumu": claude_api_durumu(),
                "yerel_rag_durumu": baglam._yerel_rag_durumu(),
            },
        )

    @router.post("/serbest/{token}/yapay-zeka-cevaplari", response_class=HTMLResponse)
    def serbest_yapay_zeka_cevaplari(
        request: Request,
        token: str,
        soru_no: list[str] = Form(...),
        soru_metin: list[str] = Form(...),
        soru_puan: list[str] = Form(...),
    ):
        from ..serbest import SerbestTaslak
        from ..yapay_zeka import (
            YapayZekaHatasi,
            cevap_anahtarlari_uret,
            claude_api_durumu,
        )

        hedef = _taslak_yolu(token)
        taslak = SerbestTaslak.json_yukle(hedef / "taslak.json")
        try:
            if not (len(soru_no) == len(soru_metin) == len(soru_puan)):
                raise ValueError("Soru alanları eksik.")
            guncel = {}
            for no_ham, metin, puan_ham in zip(soru_no, soru_metin, soru_puan):
                no = int(no_ham)
                puan = float(puan_ham.replace(",", "."))
                if not metin.strip() or puan <= 0:
                    raise ValueError(f"Soru {no}: metin ve puan gerekli.")
                guncel[no] = (metin.strip(), puan)
            for soru in taslak.sorular:
                if soru.no in guncel:
                    soru.metin, soru.puan = guncel[soru.no]
            cevaplar = cevap_anahtarlari_uret(
                [(s.no, s.metin, s.puan) for s in taslak.sorular],
                ders=taslak.ders,
            )
            cevap_haritasi = {c.soru_no: c for c in cevaplar}
            for soru in taslak.sorular:
                cevap = cevap_haritasi[soru.no]
                soru.yapay_zeka_cevabi = cevap.cevap
                soru.yapay_zeka_rubrik = cevap.rubrik
                soru.yapay_zeka_rubrik_es_anlamlilari = (
                    cevap.rubrik_es_anlamlilari or [[] for _ in cevap.rubrik]
                )
                soru.yapay_zeka_rubrik_kategorileri = (
                    cevap.rubrik_kategorileri
                    or ["kavram" for _ in cevap.rubrik]
                )
                soru.yapay_zeka_rubrik_celiskileri = (
                    cevap.rubrik_celiskileri
                    or [[] for _ in cevap.rubrik]
                )
                soru.yapay_zeka_yontem_adimlari = cevap.yontem_adimlari or []
                soru.yapay_zeka_yaygin_hatalar = cevap.yaygin_hatalar or []
                soru.yapay_zeka_yasak_celiskiler = cevap.yasak_celiskiler or []
                soru.yapay_zeka_alternatifler = (
                    cevap.kabul_edilen_alternatifler or []
                )
                soru.yapay_zeka_birimler = cevap.birimler or []
                soru.yapay_zeka_cevap_turu = cevap.cevap_turu
                soru.yapay_zeka_kaynagi = "Claude API"
                soru.yapay_zeka_kaynaklari = []
            taslak.json_kaydet(hedef / "taslak.json")
            return RedirectResponse(f"/serbest/{token}", status_code=303)
        except (ValueError, YapayZekaHatasi) as exc:
            return sablonlar.TemplateResponse(
                request,
                "serbest_incele.html",
                {
                    "taslak": taslak,
                    "token": token,
                    "hata": str(exc),
                    "yapay_zeka_durumu": claude_api_durumu(),
                    "yerel_rag_durumu": baglam._yerel_rag_durumu(),
                },
                status_code=400,
            )

    @router.post("/serbest/{token}/yerel-rag-cevaplari", response_class=HTMLResponse)
    def serbest_yerel_rag_cevaplari(
        request: Request,
        token: str,
        soru_no: list[str] = Form(...),
        soru_metin: list[str] = Form(...),
        soru_puan: list[str] = Form(...),
    ):
        from ..serbest import SerbestTaslak
        from ..yapay_zeka import claude_api_durumu

        hedef = _taslak_yolu(token)
        taslak = SerbestTaslak.json_yukle(hedef / "taslak.json")
        try:
            if not (len(soru_no) == len(soru_metin) == len(soru_puan)):
                raise ValueError("Soru alanları eksik.")
            guncel = {}
            for no_ham, metin, puan_ham in zip(soru_no, soru_metin, soru_puan):
                no = int(no_ham)
                puan = float(puan_ham.replace(",", "."))
                if not metin.strip() or puan <= 0:
                    raise ValueError(f"Soru {no}: metin ve puan gerekli.")
                guncel[no] = (metin.strip(), puan)
            for soru in taslak.sorular:
                if soru.no in guncel:
                    soru.metin, soru.puan = guncel[soru.no]
            soru_listesi = [(s.no, s.metin, s.puan) for s in taslak.sorular]
            cevaplar = baglam._rag_anahtarlari_uret(soru_listesi, ders=taslak.ders)
            harita = {c.soru_no: c for c in cevaplar}
            for soru in taslak.sorular:
                cevap = harita[soru.no]
                soru.yapay_zeka_cevabi = cevap.cevap
                soru.yapay_zeka_rubrik = cevap.rubrik
                soru.yapay_zeka_rubrik_es_anlamlilari = (
                    cevap.rubrik_es_anlamlilari or [[] for _ in cevap.rubrik]
                )
                soru.yapay_zeka_rubrik_kategorileri = (
                    cevap.rubrik_kategorileri
                    or ["kavram" for _ in cevap.rubrik]
                )
                soru.yapay_zeka_rubrik_celiskileri = (
                    cevap.rubrik_celiskileri
                    or [[] for _ in cevap.rubrik]
                )
                soru.yapay_zeka_yontem_adimlari = cevap.yontem_adimlari or []
                soru.yapay_zeka_yaygin_hatalar = cevap.yaygin_hatalar or []
                soru.yapay_zeka_yasak_celiskiler = cevap.yasak_celiskiler or []
                soru.yapay_zeka_alternatifler = (
                    cevap.kabul_edilen_alternatifler or []
                )
                soru.yapay_zeka_birimler = cevap.birimler or []
                soru.yapay_zeka_cevap_turu = cevap.cevap_turu
                soru.yapay_zeka_kaynagi = cevap.uretim_yontemi
                soru.yapay_zeka_kaynaklari = cevap.kaynaklar
                soru.yapay_zeka_puanlanabilir = cevap.puanlanabilir
                soru.yapay_zeka_uyari = cevap.uyari
            taslak.json_kaydet(hedef / "taslak.json")
            return RedirectResponse(f"/serbest/{token}", status_code=303)
        except (ValueError, OSError, json.JSONDecodeError) as exc:
            return sablonlar.TemplateResponse(
                request,
                "serbest_incele.html",
                {
                    "taslak": taslak,
                    "token": token,
                    "hata": str(exc),
                    "yapay_zeka_durumu": claude_api_durumu(),
                    "yerel_rag_durumu": baglam._yerel_rag_durumu(),
                },
                status_code=400,
            )

    @router.post("/serbest/{token}", response_class=HTMLResponse)
    def serbest_kaydet(
        request: Request,
        token: str,
        soru_no: list[str] = Form(...),
        soru_tip: list[str] = Form(...),
        soru_metin: list[str] = Form(...),
        soru_puan: list[str] = Form(...),
        soru_anahtar: list[str] = Form(...),
        anahtar_modu: str = Form("elle"),
        kutu_x: list[str] = Form(...),
        kutu_y: list[str] = Form(...),
        kutu_width: list[str] = Form(...),
        kutu_height: list[str] = Form(...),
    ):
        from ..modeller import CevapAnahtari, RubrikKalemi, Sinav, Soru, SoruTipi
        from ..serbest import SerbestKutu, SerbestSablon, SerbestTaslak
        from ..yapay_zeka import claude_api_durumu

        hedef = _taslak_yolu(token)
        taslak = SerbestTaslak.json_yukle(hedef / "taslak.json")
        try:
            alanlar = [
                soru_no, soru_tip, soru_metin, soru_puan, soru_anahtar,
                kutu_x, kutu_y, kutu_width, kutu_height,
            ]
            if len({len(x) for x in alanlar}) != 1 or not soru_no:
                raise ValueError("Algılanan soru alanları eksik.")
            if _sinav_mevcut(taslak.kimlik):
                raise ValueError("Bu sınav kodu artık kullanımda; yeniden içe aktarın.")
            if anahtar_modu not in {"otomatik_rag", "elle"}:
                raise ValueError("Geçersiz cevap anahtarı modu.")
            otomatik_harita = {}
            if anahtar_modu == "otomatik_rag":
                soru_listesi = []
                for no_ham, metin, puan_ham, tip_ham in zip(
                    soru_no, soru_metin, soru_puan, soru_tip
                ):
                    no = int(no_ham)
                    metin = metin.strip()
                    puan = float(puan_ham.replace(",", "."))
                    if SoruTipi(tip_ham) == SoruTipi.BOSLUK_DOLDURMA:
                        raise ValueError(
                            f"Soru {no}: boşluk doldurmada kabul edilen kısa "
                            "cevapları öğretmen 'Elle' modunda yazmalıdır."
                        )
                    if not metin or puan <= 0:
                        raise ValueError(f"Soru {no}: metin ve puan gerekli.")
                    soru_listesi.append((no, metin, puan))
                otomatik_harita = {
                    c.soru_no: c
                    for c in baglam._rag_anahtarlari_uret(
                        soru_listesi, ders=taslak.ders
                    )
                }
            taslak_kutular = {s.no: s.kutu for s in taslak.sorular}
            sorular = []
            kutular = []
            for (
                no_ham, tip_ham, metin, puan_ham, anahtar_ham,
                x_ham, y_ham, width_ham, height_ham,
            ) in zip(*alanlar):
                no = int(no_ham)
                tip = SoruTipi(tip_ham)
                puan = float(puan_ham.replace(",", "."))
                metin = metin.strip()
                rag_cevabi = otomatik_harita.get(no)
                if rag_cevabi is not None:
                    try:
                        algilanan_tip = SoruTipi(rag_cevabi.cevap_turu)
                        if tip == SoruTipi.ACIK_UCLU:
                            tip = algilanan_tip
                    except ValueError:
                        pass
                anahtarlar = (
                    list(rag_cevabi.rubrik)
                    if rag_cevabi is not None
                    else [
                        x.strip()
                        for x in re.split(r"[\n;]+", anahtar_ham)
                        if x.strip()
                    ]
                )
                if no not in taslak_kutular or not metin or not anahtarlar or puan <= 0:
                    raise ValueError(f"Soru {no}: metin, puan ve cevap anahtarı gerekli.")
                # Anahtar kurma mantığı anahtar_duzen modülünde; anahtar
                # düzenleyici de aynı fonksiyonları kullanır.
                if rag_cevabi is not None:
                    tip, anahtar = rag_anahtarini_kur(tip, puan, rag_cevabi)
                else:
                    tip, anahtar = formdan_anahtar_uret(tip, puan, anahtarlar)
                sorular.append(
                    Soru(
                        no=no,
                        tip=tip,
                        metin=metin,
                        puan=puan,
                        anahtar=anahtar,
                    )
                )
                taslak_kutu = taslak_kutular[no]
                x, y = float(x_ham), float(y_ham)
                width, height = float(width_ham), float(height_ham)
                if (
                    x < 0 or y < 0 or width <= 0.02 or height <= 0.02
                    or x + width > 1.001 or y + height > 1.001
                ):
                    raise ValueError(f"Soru {no}: cevap bölgesi sayfa sınırları dışında.")
                kutular.append(
                    SerbestKutu(
                        soru_no=no,
                        sayfa=taslak_kutu.sayfa,
                        x=x,
                        y=y,
                        width=width,
                        height=height,
                    )
                )

            sinav = Sinav(
                kimlik=taslak.kimlik,
                baslik=taslak.baslik,
                ders=taslak.ders,
                sorular=sorular,
            )
            kalici = sinav_dizini / taslak.kimlik
            if kalici.exists():
                raise ValueError("Bu sınava ait dosya dizini zaten var.")
            hedef.rename(kalici)
            eski_kok = str(hedef)
            yeni_kok = str(kalici)
            kaynaklar = taslak.kaynak_dosyalari or [taslak.kaynak_dosya]
            kalici_kaynaklar = [
                Path(yol.replace(eski_kok, yeni_kok)) for yol in kaynaklar
            ]
            kaynak = kalici_kaynaklar[0]
            gorseller = [
                yol.replace(eski_kok, yeni_kok) for yol in taslak.sayfa_gorselleri
            ]
            yaml_yolu = kalici / f"{taslak.kimlik}.yaml"
            sablon_yolu = kalici / f"{taslak.kimlik}_serbest.json"
            sinav.yaml_kaydet(yaml_yolu)
            SerbestSablon(
                sinav_kimlik=taslak.kimlik,
                dpi=taslak.dpi,
                sayfa_gorselleri=gorseller,
                kutular=[*kutular, *taslak.ek_kutular],
            ).json_kaydet(sablon_yolu)
            depo.sinav_kaydet(sinav)
            depo.sinav_dosya_kaydet(
                taslak.kimlik,
                yaml_yolu=yaml_yolu,
                sablon_yolu=sablon_yolu,
                form_pdf_yolu=kaynak,
            )
            return RedirectResponse(
                f"/sinav/{taslak.kimlik}?tanitildi=1", status_code=303
            )
        except (ValueError, OSError, KeyError) as exc:
            return sablonlar.TemplateResponse(
                request,
                "serbest_incele.html",
                {
                    "taslak": taslak,
                    "token": token,
                    "hata": str(exc),
                    "yapay_zeka_durumu": claude_api_durumu(),
                    "yerel_rag_durumu": baglam._yerel_rag_durumu(),
                },
                status_code=400,
            )

    @router.get("/yukle", response_class=HTMLResponse)
    def kagit_yukle_formu(request: Request, sinav: str = ""):
        return sablonlar.TemplateResponse(
            request, "yukle.html", _yukleme_baglami(secili_sinav=sinav)
        )

    @router.post("/yukle", response_class=HTMLResponse)
    async def kagit_yukle(
        request: Request,
        sinav_kimlik: str = Form(...),
        kagit_dosyalari: list[UploadFile] | None = File(None),
        kagit_dosyasi: UploadFile | None = File(None),
        islem_modu: str = Form("tek"),
        ogrenci_ad: str = Form(""),
        ogrenci_soyad: str = Form(""),
        ogrenci_no: str = Form(""),
        ogrenci_sinif: str = Form(""),
        ogrenci_sube: str = Form(""),
        model_turu: str = Form("coklu"),
        yazar_grubu: str = Form(""),
        egitim_izni: bool = Form(False),
    ):
        try:
            sinav_kimlik = sinav_kimlik.strip()
            if not _sinav_mevcut(sinav_kimlik):
                raise ValueError("Önce tanıtılmış geçerli bir yazılı seçin.")
            sinav = depo.sinav_yukle(sinav_kimlik)
            if egitim_izni and not yazar_grubu.strip():
                raise ValueError(
                    "Eğitim izni işaretliyse kişisel bilgi içermeyen anonim yazar kodu gerekli."
                )
            if islem_modu not in {"tek", "sinif"}:
                raise ValueError("Geçersiz yükleme biçimi.")
            yuklenenler = [
                d for d in (kagit_dosyalari or []) if d and d.filename
            ]
            if kagit_dosyasi and kagit_dosyasi.filename:
                yuklenenler.append(kagit_dosyasi)
            if not yuklenenler or len(yuklenenler) > 200:
                raise ValueError("1–200 arasında kâğıt dosyası seçin.")

            try:
                sablon_yolu = baglam._kayitli_dosya(sinav_kimlik, "sablon_yolu")
            except HTTPException as exc:
                raise ValueError(
                    "Bu yazılı henüz tanıtılmamış. Önce boş yazılı sayfalarını yükleyin."
                ) from exc
            sablon = _sablonu_yukle(sablon_yolu)
            if sablon.sinav_kimlik != sinav_kimlik:
                raise ValueError("Kayıtlı yazılı tanımı seçili sınavla eşleşmiyor.")

            yukleme_oturumu = yukleme_dizini / sinav_kimlik / uuid4().hex
            kaydedilenler: list[tuple[str, Path]] = []
            for dosya in yuklenenler:
                ad = Path(dosya.filename or "kagit").name
                yol = await baglam._yuklemeyi_kaydet(
                    dosya,
                    yukleme_oturumu,
                    {
                        ".pdf", ".png", ".jpg", ".jpeg",
                        ".tif", ".tiff", ".bmp", ".webp",
                        ".heic", ".heif",
                    },
                )
                kaydedilenler.append((ad, yol))

            gruplar: dict[str, list[tuple[str, Path]]] = {}
            if islem_modu == "tek":
                gruplar["tek-ogrenci"] = kaydedilenler
            else:
                for ad, yol in kaydedilenler:
                    gruplar.setdefault(_ogrenci_dosya_anahtari(ad), []).append((ad, yol))
            if islem_modu == "sinif":
                for grup in gruplar.values():
                    grup.sort(key=lambda x: _dogal_sira(x[0]))

            taniyici = await run_in_threadpool(_taniyici_getir, model_turu)
            from ..serbest import serbest_kagit_isle
            from ..referans import YerelRAGDeposu

            referans_deposu = (
                YerelRAGDeposu.yukle(referans_indeks_dizini)
                if YerelRAGDeposu.hazir_mi(referans_indeks_dizini)
                else None
            )

            def _grubu_isle(anahtar: str, grup: list) -> dict:
                """Tek bir öğrenci grubunu işleyip sonuç sözlüğü döndürür.

                Beklenen hatalarda istisna fırlatmaz; ``basarili=False`` döndürür.
                Senkron çalışır (arka plan thread'inden de çağrılabilir).
                """
                dosya_ad, dosya_no = (
                    (ogrenci_ad.strip(), ogrenci_no.strip())
                    if islem_modu == "tek"
                    else _ogrenci_bilgisi(anahtar)
                )
                ad, no = dosya_ad, dosya_no
                yollar = [yol for _dosya_adi, yol in grup]
                kirp_hedef = kirp_kok / f"kagit_{uuid4().hex}"
                try:
                    sonuc = serbest_kagit_isle(
                        yollar, sinav, sablon, taniyici, baglam.gomlemci(),
                        referans_deposu=referans_deposu, kirp_dizini=kirp_hedef,
                        duzeltme_ornekleri=[
                            dict(x) for x in depo.duzeltme_ornekleri(sinav.kimlik)
                        ],
                        ogrenilmis_kabuller={
                            s.no: [
                                k["yazim"]
                                for k in depo.ogrenilmis_kabuller(
                                    sinav.kimlik, s.no, onay_durumu="onayli"
                                )
                            ]
                            for s in sinav.sorular
                        },
                    )
                    if not sonuc.kutular:
                        raise ValueError(
                            " ".join(sonuc.uyarilar)
                            or "Sayfalarda okunabilir cevap kutusu bulunamadı."
                        )
                    otomatik_kimlik = sonuc.kimlik_bilgileri or {}
                    from ..ogrenci import ogrenci_esle

                    liste_eslesmesi = ogrenci_esle(
                        otomatik_kimlik,
                        [dict(x) for x in depo.ogrenci_listesi(sinav_kimlik)],
                    )
                    if liste_eslesmesi is not None:
                        otomatik_kimlik["liste_eslesmesi"] = liste_eslesmesi
                        otomatik_kimlik["guven"] = max(
                            float(otomatik_kimlik.get("guven", 0.0)),
                            float(liste_eslesmesi["eslesme_guveni"]),
                        )
                    ad = ogrenci_ad.strip() or otomatik_kimlik.get("ad", "") or dosya_ad
                    soyad = ogrenci_soyad.strip() or otomatik_kimlik.get("soyad", "")
                    no = ogrenci_no.strip() or otomatik_kimlik.get("numara", "") or dosya_no
                    sinif = ogrenci_sinif.strip() or otomatik_kimlik.get("sinif", "")
                    sube = ogrenci_sube.strip() or otomatik_kimlik.get("sube", "")
                    if liste_eslesmesi is not None:
                        ad = ogrenci_ad.strip() or liste_eslesmesi.get("ad", "") or ad
                        soyad = ogrenci_soyad.strip() or liste_eslesmesi.get("soyad", "") or soyad
                        no = ogrenci_no.strip() or liste_eslesmesi.get("ogrenci_no", "") or no
                        sinif = ogrenci_sinif.strip() or liste_eslesmesi.get("sinif", "") or sinif
                        sube = ogrenci_sube.strip() or liste_eslesmesi.get("sube", "") or sube
                    elle_kimlik = any(
                        x.strip()
                        for x in (
                            ogrenci_ad, ogrenci_soyad, ogrenci_no,
                            ogrenci_sinif, ogrenci_sube,
                        )
                    )
                    kagit_id = depo.kagit_kaydet(
                        sonuc,
                        ogrenci_ad=ad, ogrenci_soyad=soyad, ogrenci_no=no,
                        sinif=sinif, sube=sube,
                        kimlik_guveni=(
                            1.0 if elle_kimlik
                            else float(otomatik_kimlik.get("guven", 0.0))
                        ),
                        kimlik_bilgileri=otomatik_kimlik,
                        kaynak_dosya=json.dumps(
                            [str(yol) for yol in yollar], ensure_ascii=False
                        ),
                        yazar_grubu=(
                            f"{yazar_grubu.strip()}-{anahtar}"
                            if egitim_izni and islem_modu == "sinif"
                            else yazar_grubu.strip()
                        ),
                        egitim_izni=egitim_izni,
                        islem_uyarilari=sonuc.uyarilar,
                    )
                    return {
                        "basarili": True, "kagit_id": kagit_id,
                        "ogrenci_ad": ad, "ogrenci_soyad": soyad, "ogrenci_no": no,
                        "sinif": sinif, "sube": sube,
                        "dosya": len(yollar), "sayfa": len(sonuc.islenen_sayfalar),
                        "uyarilar": sonuc.uyarilar,
                    }
                except (ValueError, OSError, KeyError, TypeError) as exc:
                    return {
                        "basarili": False, "ogrenci_ad": ad, "ogrenci_soyad": "",
                        "ogrenci_no": no, "dosya": len(yollar), "hata": str(exc),
                    }

            if islem_modu == "tek":
                anahtar, grup = next(iter(gruplar.items()))
                sonuc = await run_in_threadpool(_grubu_isle, anahtar, grup)
                if not sonuc["basarili"]:
                    raise ValueError(sonuc["hata"])
                return RedirectResponse(
                    f"/kagit/{sonuc['kagit_id']}?yeni=1", status_code=303
                )

            # Sınıf modu: arka plan thread'inde işle, hemen ilerleme sayfasına dön.
            token = uuid4().hex
            durum_yolu = toplu_sonuc_dizini / f"{token}.json"

            def _durum_yaz(veri: dict) -> None:
                veri = {**veri, "guncellendi": time.time()}
                gecici = durum_yolu.with_suffix(f".{os.getpid()}.tmp")
                gecici.write_text(
                    json.dumps(veri, ensure_ascii=False, indent=2), encoding="utf-8"
                )
                os.replace(gecici, durum_yolu)

            _durum_yaz({
                "sinav_kimlik": sinav_kimlik, "durum": "isleniyor",
                "toplam": len(gruplar), "biten": 0,
                "islenen_ogrenci": "", "sonuclar": [],
            })

            def _arka_plan(gruplar_kopya):
                sonuclar: list[dict] = []
                try:
                    for i, (anahtar, grup) in enumerate(gruplar_kopya.items()):
                        _durum_yaz({
                            "sinav_kimlik": sinav_kimlik, "durum": "isleniyor",
                            "toplam": len(gruplar_kopya), "biten": i,
                            "islenen_ogrenci": _ogrenci_bilgisi(anahtar)[0] or anahtar,
                            "sonuclar": sonuclar,
                        })
                        try:
                            sonuclar.append(_grubu_isle(anahtar, grup))
                        except Exception as exc:  # tek kâğıt sınıfı iptal etmesin
                            sonuclar.append({
                                "basarili": False,
                                "ogrenci_ad": _ogrenci_bilgisi(anahtar)[0] or anahtar,
                                "ogrenci_soyad": "", "ogrenci_no": "",
                                "dosya": len(grup), "hata": str(exc) or type(exc).__name__,
                            })
                    _durum_yaz({
                        "sinav_kimlik": sinav_kimlik, "durum": "bitti",
                        "toplam": len(gruplar_kopya), "biten": len(gruplar_kopya),
                        "islenen_ogrenci": "", "sonuclar": sonuclar,
                    })
                except Exception as exc:
                    # Durum dosyası "işleniyor"da takılı kalmasın.
                    try:
                        _durum_yaz({
                            "sinav_kimlik": sinav_kimlik, "durum": "hata",
                            "toplam": len(gruplar_kopya), "biten": len(sonuclar),
                            "islenen_ogrenci": "", "sonuclar": sonuclar,
                            "hata": str(exc) or type(exc).__name__,
                        })
                    except OSError:
                        pass

            threading.Thread(
                target=_arka_plan, args=(dict(gruplar),), daemon=True
            ).start()
            return RedirectResponse(f"/toplu-sonuc/{token}", status_code=303)
        except (ValueError, OSError, KeyError, TypeError, json.JSONDecodeError) as exc:
            return sablonlar.TemplateResponse(
                request,
                "yukle.html",
                _yukleme_baglami(hata=str(exc), secili_sinav=sinav_kimlik),
                status_code=400,
            )

    def _toplu_durum_oku(token: str) -> dict:
        if not re.fullmatch(r"[0-9a-f]{32}", token):
            raise HTTPException(404, "Toplu işlem bulunamadı.")
        yol = toplu_sonuc_dizini / f"{token}.json"
        if not yol.is_file():
            raise HTTPException(404, "Toplu işlem bulunamadı.")
        try:
            veri = json.loads(yol.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            # Atomik yazımla eşzamanlı okuma nadiren yarışabilir; kısa bekleme.
            return {"durum": "isleniyor", "sonuclar": []}
        # Süreç yeniden başlar/çökerse daemon thread ölür ve durum "isleniyor"da
        # takılır. Uzun süre güncellenmeyen işlemi kesilmiş say.
        if veri.get("durum") == "isleniyor":
            guncellendi = veri.get("guncellendi")
            if guncellendi is not None and (time.time() - guncellendi) > 300:
                veri["durum"] = "hata"
                veri["hata"] = (
                    "İşlem uzun süredir güncellenmedi; büyük olasılıkla sunucu "
                    "yeniden başladı. İşlenen kâğıtlar kaydedildi, kalanları "
                    "yeniden yükleyin."
                )
        return veri

    @router.get("/toplu-sonuc/{token}", response_class=HTMLResponse)
    def toplu_sonuc(request: Request, token: str):
        veri = _toplu_durum_oku(token)
        sonuclar = veri.get("sonuclar", [])
        return sablonlar.TemplateResponse(
            request,
            "toplu_sonuc.html",
            {
                "veri": veri,
                "token": token,
                "isleniyor": veri.get("durum") == "isleniyor",
                "basarili": sum(1 for x in sonuclar if x.get("basarili")),
                "hatali": sum(1 for x in sonuclar if not x.get("basarili")),
            },
        )

    @router.get("/toplu-sonuc/{token}/durum.json")
    def toplu_sonuc_durumu(token: str):
        return _toplu_durum_oku(token)


    return router
