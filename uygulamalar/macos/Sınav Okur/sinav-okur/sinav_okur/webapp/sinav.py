"""Sınav detayı, analiz, cevap anahtarı, inceleme/tutarlılık ve rapor uçları."""
from __future__ import annotations

import json
import mimetypes
import os
import re
import tempfile
from collections import defaultdict
from pathlib import Path

from fastapi import APIRouter, File, Form, HTTPException, Request, UploadFile
from fastapi.responses import FileResponse, HTMLResponse, RedirectResponse
from starlette.background import BackgroundTask

from .baglam import WebBaglam
from ..anahtar_duzen import anahtar_etkisini_onizle, anahtar_satirlari, formdan_anahtar_uret


def rota_kur(baglam: WebBaglam) -> APIRouter:
    router = APIRouter()
    depo = baglam.depo
    sablonlar = baglam.sablonlar
    yukleme_dizini = baglam.yukleme_dizini
    referans_indeks_dizini = baglam.referans_indeks_dizini

    @router.get("/sinav/{kimlik}/itirazlar", response_class=HTMLResponse)
    def sinav_itirazlari(request: Request, kimlik: str):
        try:
            sinav = depo.sinav_yukle(kimlik)
        except KeyError as exc:
            raise HTTPException(404, "Sınav bulunamadı") from exc
        durum = request.query_params.get("durum") or None
        kayitlar = []
        for itiraz in depo.itirazlar(kimlik, durum):
            kutu = depo.kutu(itiraz["kutu_id"]) if itiraz["kutu_id"] else None
            kayitlar.append(
                {
                    "itiraz": itiraz,
                    "kutu": kutu,
                    "metin": (
                        (
                            kutu["duzeltilmis_metin"]
                            if kutu["duzeltilmis_metin"] is not None
                            else kutu["taninan_metin"]
                        )
                        or ""
                    )
                    if kutu
                    else "",
                    "kirp_url": baglam._kirp_url(kutu["kirp_yolu"]) if kutu else None,
                }
            )
        return sablonlar.TemplateResponse(
            request,
            "itirazlar.html",
            {
                "kimlik": kimlik,
                "sinav": sinav,
                "kayitlar": kayitlar,
                "durum": durum or "",
                "karar": request.query_params.get("karar"),
            },
        )

    @router.post("/itiraz/{itiraz_id}/karar")
    def itiraz_karar(
        itiraz_id: int,
        karar: str = Form("kabul"),
        yeni_puan: str = Form(""),
        karar_notu: str = Form(""),
        kimlik: str = Form(...),
    ):
        kabul = karar == "kabul"
        puan = None
        if kabul and str(yeni_puan).strip():
            try:
                puan = float(str(yeni_puan).replace(",", "."))
            except ValueError as exc:
                raise HTTPException(400, "Puan sayı olmalı") from exc
        try:
            depo.itiraz_karara_bagla(itiraz_id, kabul, puan, karar_notu)
        except KeyError as exc:
            raise HTTPException(404, "İtiraz bulunamadı") from exc
        return RedirectResponse(
            f"/sinav/{kimlik}/itirazlar?karar={'kabul' if kabul else 'ret'}",
            status_code=303,
        )

    @router.get("/sinav/{kimlik}/kaynak")
    def sinav_kaynagi_indir(kimlik: str):
        yol = baglam._kayitli_dosya(kimlik, "form_pdf_yolu")
        uzanti = yol.suffix.lower() or ".bin"
        return FileResponse(
            yol,
            filename=f"{kimlik}_kaynak{uzanti}",
            media_type=mimetypes.guess_type(yol.name)[0] or "application/octet-stream",
        )

    def _toplu_sonuc_ozeti(request: Request) -> dict | None:
        """`?toplu=&atlanan=` parametrelerini şablon için sayıya çevirir."""
        ham = request.query_params.get("toplu")
        if ham is None:
            return None
        try:
            islenen = int(ham)
            atlanan = int(request.query_params.get("atlanan") or 0)
        except ValueError:
            return None
        return {
            "islenen": islenen,
            "atlanan": atlanan,
            "islem": request.query_params.get("islem") or "",
        }

    @router.get("/sinav/{kimlik}", response_class=HTMLResponse)
    def sinav_detay(request: Request, kimlik: str):
        try:
            sinav = depo.sinav_yukle(kimlik)
        except KeyError as exc:
            raise HTTPException(404, "Sınav bulunamadı") from exc
        kagitlar = []
        toplam_bekleyen = toplam_onayli = 0
        puan_yuzdeleri: list[float] = []
        ilk_bekleyen_kagit = None
        for k in depo.sinav_kagit_ozetleri(kimlik):
            toplam = float(k["toplam_puan"] or 0.0)
            maxp = float(k["azami_puan"] or 0.0)
            bekleyen = int(k["bekleyen"] or 0)
            yuzde = toplam / maxp * 100 if maxp else 0
            try:
                uyarilar = json.loads(k["islem_uyarilari"] or "[]")
            except (json.JSONDecodeError, TypeError):
                uyarilar = []
            try:
                kalite = json.loads(k["kalite_json"] or "[]")
            except (json.JSONDecodeError, TypeError):
                kalite = []
            kritik = any(r.get("kritik") for r in kalite)
            kagitlar.append({
                "k": k, "toplam": toplam, "max": maxp,
                "bekleyen": bekleyen, "yuzde": yuzde,
                "uyari_sayisi": len(uyarilar), "kritik": kritik,
            })
            toplam_bekleyen += bekleyen
            if ilk_bekleyen_kagit is None and bekleyen:
                ilk_bekleyen_kagit = k["id"]
            toplam_onayli += int(bool(k["onaylandi"]))
            if maxp:
                puan_yuzdeleri.append(yuzde)
        ozet = {
            "kagit": len(kagitlar),
            "bekleyen": toplam_bekleyen,
            "onayli": toplam_onayli,
            "ortalama": (
                sum(puan_yuzdeleri) / len(puan_yuzdeleri)
                if puan_yuzdeleri else None
            ),
            "ilk_bekleyen_kagit": ilk_bekleyen_kagit,
        }
        dosya_kaydi = depo.sinav_dosyasi(kimlik)
        kaynak_hazir = bool(
            dosya_kaydi and dosya_kaydi["form_pdf_yolu"]
            and Path(dosya_kaydi["form_pdf_yolu"]).exists()
        )
        yazili_hazir = bool(
            dosya_kaydi and dosya_kaydi["sablon_yolu"]
            and Path(dosya_kaydi["sablon_yolu"]).exists()
            and baglam._serbest_mi(dosya_kaydi["sablon_yolu"])
        )
        return sablonlar.TemplateResponse(
            request, "sinav.html",
            {
                "kimlik": kimlik, "sinav": sinav, "kagitlar": kagitlar, "ozet": ozet,
                "kaynak_hazir": kaynak_hazir,
                "yazili_hazir": yazili_hazir,
                "tanitildi": request.query_params.get("tanitildi") == "1",
                "rag_yenilendi": request.query_params.get("rag_yenilendi") == "1",
                "ogrenci_listesi_adet": len(depo.ogrenci_listesi(kimlik)),
                "liste_yuklendi": request.query_params.get("liste_yuklendi"),
                "anahtar_onaylandi": (
                    request.query_params.get("anahtar_onaylandi") == "1"
                ),
                "toplu_sonuc": _toplu_sonuc_ozeti(request),
                "kabul_yazimlari": depo.ogrenilmis_kabuller(kimlik),
                "kabul_onerisi": request.query_params.get("kabul_onerisi"),
                "kabul_karari": request.query_params.get("kabul_karari"),
                "esneklik_kaydedildi": (
                    request.query_params.get("esneklik")
                    if request.query_params.get("esneklik")
                    in {"kati", "dengeli", "esnek"}
                    else None
                ),
                "esneklik_profili": (
                    sinav.sorular[0].esneklik if sinav.sorular else "dengeli"
                ),
            },
        )

    @router.post("/sinav/{kimlik}/ogrenci-listesi")
    async def sinav_ogrenci_listesi_yukle(
        kimlik: str,
        liste_dosyasi: UploadFile = File(...),
    ):
        try:
            depo.sinav_yukle(kimlik)
        except KeyError as exc:
            raise HTTPException(404, "Sınav bulunamadı") from exc
        gecici = await baglam._yuklemeyi_kaydet(
            liste_dosyasi,
            yukleme_dizini / kimlik / "ogrenci-listesi",
            {".csv", ".xlsx", ".xlsm"},
            azami_bayt=10 * 1024 * 1024,
        )
        try:
            from ..ogrenci import ogrenci_listesi_oku

            kayitlar = ogrenci_listesi_oku(gecici)
            adet = depo.ogrenci_listesi_kaydet(kimlik, kayitlar)
        finally:
            gecici.unlink(missing_ok=True)
        return RedirectResponse(
            f"/sinav/{kimlik}?liste_yuklendi={adet}",
            status_code=303,
        )

    @router.get("/sinav/{kimlik}/puanlama-motoru", response_class=HTMLResponse)
    def sinav_puanlama_motoru(request: Request, kimlik: str):
        """Anlamsal puanlamayı açmanın mevcut puanlara etkisini ÖLÇER.

        Şalter kapalıyken de rapor üretilebilir: karar ölçüme dayanmalı,
        "aç ve gör" denemesi öğrencilerin notları üzerinde yapılamaz.
        """
        from ..motor_etkisi import motor_etkisini_onizle
        from ..puanlama.gomme import gomlemci_yukle

        try:
            sinav = depo.sinav_yukle(kimlik)
        except KeyError as exc:
            raise HTTPException(404, "Sınav bulunamadı") from exc
        aday = baglam.gomlemci() or gomlemci_yukle()
        rapor = motor_etkisini_onizle(
            depo,
            sinav,
            yeni_gomlemci=aday,
            referans_indeks_dizini=referans_indeks_dizini,
        )
        return sablonlar.TemplateResponse(
            request,
            "puanlama_motoru.html",
            {
                "kimlik": kimlik,
                "sinav": sinav,
                "rapor": rapor,
                "gomlemci_yuklendi": aday is not None,
                "gomlemci_acik": baglam.gomlemci() is not None,
            },
        )

    @router.get("/sinav/{kimlik}/analiz", response_class=HTMLResponse)
    def sinav_analiz(request: Request, kimlik: str):
        try:
            sinav = depo.sinav_yukle(kimlik)
        except KeyError as exc:
            raise HTTPException(404, "Sınav bulunamadı") from exc
        from ..analiz import kazanim_analizi, sinav_analizi
        from ..referans import YerelRAGDeposu

        pasaj_bul = None
        if YerelRAGDeposu.hazir_mi(referans_indeks_dizini):
            rag = YerelRAGDeposu.yukle(referans_indeks_dizini)

            def pasaj_bul(kavram: str):
                sonuc = rag.ilgili(kavram, k=1)
                if not sonuc:
                    return None
                pasaj, _skor = sonuc[0]
                ozet = pasaj.metin.strip().replace("\n", " ")
                return {
                    "kaynak": pasaj.kaynak,
                    "ozet": ozet[:180] + ("…" if len(ozet) > 180 else ""),
                }

        return sablonlar.TemplateResponse(
            request,
            "analiz.html",
            {
                "kimlik": kimlik,
                "sinav": sinav,
                "analiz": sinav_analizi(depo, sinav, referans_pasaj_bul=pasaj_bul),
                "kazanim": kazanim_analizi(depo, sinav),
                "akran": request.query_params.get("akran"),
            },
        )

    @router.get("/sinav/{kimlik}/soru/{soru_no}", response_class=HTMLResponse)
    def sinav_soru_karsilastir(request: Request, kimlik: str, soru_no: int):
        try:
            sinav = depo.sinav_yukle(kimlik)
            soru = sinav.soru(soru_no)
        except KeyError as exc:
            raise HTTPException(404, "Sınav veya soru bulunamadı") from exc
        cevaplar = []
        for satir in depo.sinav_cevaplari(kimlik):
            if int(satir["soru_no"]) != soru_no:
                continue
            cevaplar.append(
                {
                    "satir": satir,
                    "metin": (
                        satir["duzeltilmis_metin"]
                        if satir["duzeltilmis_metin"] is not None
                        else satir["taninan_metin"] or ""
                    ),
                    "kirp_url": baglam._kirp_url(satir["kirp_yolu"]),
                }
            )
        cevaplar.sort(
            key=lambda x: (
                -float(x["satir"]["risk"] or 0),
                float(x["satir"]["son_puan"] or 0),
            )
        )
        return sablonlar.TemplateResponse(
            request,
            "soru_karsilastir.html",
            {"sinav": sinav, "soru": soru, "cevaplar": cevaplar},
        )

    def _soru_satirlari(kimlik: str, soru_no: int) -> list:
        return [
            s for s in depo.sinav_cevaplari(kimlik) if int(s["soru_no"]) == soru_no
        ]

    @router.get("/sinav/{kimlik}/soru/{soru_no}/tezgah", response_class=HTMLResponse)
    def sinav_soru_tezgahi(request: Request, kimlik: str, soru_no: int):
        """Aynı sorunun cevaplarını kümeleyip kümeye tek hamlede puan verdirir."""
        from ..analiz import benzer_cevap_kumeleri, kutu_metni

        try:
            sinav = depo.sinav_yukle(kimlik)
            soru = sinav.soru(soru_no)
        except KeyError as exc:
            raise HTTPException(404, "Sınav veya soru bulunamadı") from exc
        satirlar = _soru_satirlari(kimlik, soru_no)
        kumeler = []
        for sira, kume in enumerate(benzer_cevap_kumeleri(satirlar), start=1):
            kumeler.append(
                {
                    "sira": sira,
                    "temsilci": kume["temsilci"],
                    "adet": kume["adet"],
                    "bekleyen": kume["bekleyen"],
                    "ortak_puan": kume["ortak_puan"],
                    "uyeler": [
                        {
                            "satir": u,
                            "metin": kutu_metni(u),
                            "kirp_url": baglam._kirp_url(u["kirp_yolu"]),
                        }
                        for u in kume["uyeler"]
                    ],
                }
            )
        return sablonlar.TemplateResponse(
            request,
            "soru_tezgahi.html",
            {
                "sinav": sinav,
                "soru": soru,
                "kumeler": kumeler,
                "toplam": len(satirlar),
                "toplu_puan": request.query_params.get("toplu_puan"),
            },
        )

    @router.post("/sinav/{kimlik}/soru/{soru_no}/toplu-puan")
    def sinav_soru_toplu_puan(
        kimlik: str,
        soru_no: int,
        kutu_id: list[int] = Form(default=[]),
        puan: str = Form(""),
        islem: str = Form("elle"),
    ):
        """Kümeye tek puan uygular ya da kümeyi güncel anahtarla yeniden puanlar."""
        try:
            sinav = depo.sinav_yukle(kimlik)
            soru = sinav.soru(soru_no)
        except KeyError as exc:
            raise HTTPException(404, "Sınav veya soru bulunamadı") from exc
        gecerli = {s["id"] for s in _soru_satirlari(kimlik, soru_no)}
        hedefler = [k for k in kutu_id if k in gecerli]
        if islem == "elle":
            try:
                deger = float(str(puan).replace(",", "."))
            except ValueError as exc:
                raise HTTPException(400, "Puan sayı olmalı") from exc
            if not 0 <= deger <= soru.puan:
                raise HTTPException(400, "Puan 0 ile soru puanı arasında olmalı")
            for kid in hedefler:
                depo.kutu_guncelle(
                    kutu_id=kid,
                    son_puan=deger,
                    incele=False,
                    neden=(
                        "Toplu puanlama tezgâhı: öğretmen benzer cevap kümesine "
                        "aynı puanı verdi"
                    ),
                )
        elif islem == "yeniden_puanla":
            for kid in hedefler:
                kutu = depo.kutu(kid)
                if kutu is None:
                    continue
                metin = (
                    kutu["duzeltilmis_metin"]
                    if kutu["duzeltilmis_metin"] is not None
                    else kutu["taninan_metin"] or ""
                )
                baglam._kutu_metnini_otomatik_puanla(kutu, sinav, metin)
        else:
            raise HTTPException(400, "Bilinmeyen tezgâh işlemi")
        return RedirectResponse(
            f"/sinav/{kimlik}/soru/{soru_no}/tezgah?toplu_puan={len(hedefler)}",
            status_code=303,
        )

    def _anahtar_formu_metni(soru) -> str:
        """Anahtarı düzenleyici formunun beklediği satır biçimine çevirir."""
        from ..modeller import SoruTipi

        anahtar = soru.anahtar
        if soru.tip in {SoruTipi.BOSLUK_DOLDURMA, SoruTipi.COKTAN_SECMELI}:
            return "\n".join(anahtar.dogru_cevaplar)
        if soru.tip == SoruTipi.SIRALAMA:
            return "\n".join(anahtar.siralama)
        if soru.tip == SoruTipi.ESLESTIRME:
            return "\n".join(f"{k} = {v}" for k, v in anahtar.eslestirmeler.items())
        if soru.tip in {SoruTipi.SAYISAL, SoruTipi.FORMUL_ISPAT}:
            return "\n".join(anahtar.dogru_cevaplar)
        return "\n".join(k.metin for k in anahtar.rubrik)

    def _formdan_sinav_kur(sinav, soru_no, soru_tip, soru_anahtar, soru_kazanim):
        """Form alanlarından yeni bir Sinav nesnesi kurar (depoya yazmaz)."""
        from ..modeller import Sinav, Soru, SoruTipi

        mevcut = {s.no: s for s in sinav.sorular}
        yeni_sorular = []
        for no_ham, tip_ham, anahtar_ham, kazanim_ham in zip(
            soru_no, soru_tip, soru_anahtar, soru_kazanim
        ):
            no = int(no_ham)
            if no not in mevcut:
                raise HTTPException(400, f"Soru {no} bu sınavda yok.")
            eski = mevcut[no]
            satirlar = anahtar_satirlari(anahtar_ham)
            if not satirlar:
                raise HTTPException(400, f"Soru {no}: cevap anahtarı boş olamaz.")
            tip, anahtar = formdan_anahtar_uret(
                SoruTipi(tip_ham), eski.puan, satirlar
            )
            yeni_sorular.append(
                Soru(
                    no=no,
                    tip=tip,
                    metin=eski.metin,
                    puan=eski.puan,
                    anahtar=anahtar,
                    kutu_yuksekligi_mm=eski.kutu_yuksekligi_mm,
                    kazanımlar=[
                        k.strip()
                        for k in re.split(r"[\n;,]+", kazanim_ham or "")
                        if k.strip()
                    ],
                    esneklik=eski.esneklik,
                )
            )
        return Sinav(
            kimlik=sinav.kimlik,
            baslik=sinav.baslik,
            ders=sinav.ders,
            sorular=yeni_sorular,
        )

    @router.get("/sinav/{kimlik}/anahtar", response_class=HTMLResponse)
    def sinav_anahtar_duzenle(request: Request, kimlik: str):
        """Cevap anahtarını sonradan düzenleme ekranı."""
        try:
            sinav = depo.sinav_yukle(kimlik)
        except KeyError as exc:
            raise HTTPException(404, "Sınav bulunamadı") from exc
        sorular = [
            {
                "soru": soru,
                "anahtar_metni": _anahtar_formu_metni(soru),
                "kazanim_metni": "; ".join(soru.kazanımlar),
            }
            for soru in sinav.sorular
        ]
        return sablonlar.TemplateResponse(
            request,
            "anahtar.html",
            {
                "kimlik": kimlik,
                "sinav": sinav,
                "sorular": sorular,
                "onizleme": None,
                "uygulandi": request.query_params.get("uygulandi"),
            },
        )

    @router.post("/sinav/{kimlik}/anahtar/onizle", response_class=HTMLResponse)
    def sinav_anahtar_onizle(
        request: Request,
        kimlik: str,
        soru_no: list[str] = Form(...),
        soru_tip: list[str] = Form(...),
        soru_anahtar: list[str] = Form(...),
        soru_kazanim: list[str] = Form(default=[]),
    ):
        """Değişikliğin etkisini gösterir; DEPOYA HİÇBİR ŞEY YAZMAZ."""
        try:
            sinav = depo.sinav_yukle(kimlik)
        except KeyError as exc:
            raise HTTPException(404, "Sınav bulunamadı") from exc
        soru_kazanim = list(soru_kazanim) + [""] * (
            len(soru_no) - len(soru_kazanim)
        )
        yeni = _formdan_sinav_kur(
            sinav, soru_no, soru_tip, soru_anahtar, soru_kazanim
        )
        onizleme = anahtar_etkisini_onizle(
            depo,
            sinav,
            yeni,
            gomlemci=baglam.gomlemci(),
            referans_indeks_dizini=baglam.referans_indeks_dizini,
        )
        sorular = [
            {
                "soru": s,
                "anahtar_metni": anahtar_ham,
                "kazanim_metni": kazanim_ham,
            }
            for s, anahtar_ham, kazanim_ham in zip(
                yeni.sorular, soru_anahtar, soru_kazanim
            )
        ]
        return sablonlar.TemplateResponse(
            request,
            "anahtar.html",
            {
                "kimlik": kimlik,
                "sinav": yeni,
                "sorular": sorular,
                "onizleme": onizleme,
                "uygulandi": None,
            },
        )

    @router.post("/sinav/{kimlik}/anahtar")
    def sinav_anahtar_kaydet(
        kimlik: str,
        soru_no: list[str] = Form(...),
        soru_tip: list[str] = Form(...),
        soru_anahtar: list[str] = Form(...),
        soru_kazanim: list[str] = Form(default=[]),
    ):
        """Yeni anahtarı sürümleyip tüm kâğıtları yeniden puanlar."""
        try:
            sinav = depo.sinav_yukle(kimlik)
        except KeyError as exc:
            raise HTTPException(404, "Sınav bulunamadı") from exc
        soru_kazanim = list(soru_kazanim) + [""] * (
            len(soru_no) - len(soru_kazanim)
        )
        yeni = _formdan_sinav_kur(
            sinav, soru_no, soru_tip, soru_anahtar, soru_kazanim
        )
        guncellenen, korunan = baglam._anahtari_uygula(kimlik, yeni)
        return RedirectResponse(
            f"/sinav/{kimlik}/anahtar?uygulandi={guncellenen}&korunan={korunan}",
            status_code=303,
        )

    @router.post("/sinav/{kimlik}/akran-uzlasmasi")
    def sinav_akran_uzlasmasi(kimlik: str):
        """Benzer cevaplara öğretmenin verdiği puandan sapan kutuları işaretle."""
        from ..puanlama.akran import akran_uzlasmasini_degerlendir

        try:
            sinav = depo.sinav_yukle(kimlik)
        except KeyError as exc:
            raise HTTPException(404, "Sınav bulunamadı") from exc
        sonuc = akran_uzlasmasini_degerlendir(depo, sinav, uygula=True)
        return RedirectResponse(
            f"/sinav/{kimlik}/analiz?akran={len(sonuc['isaretlenen'])}",
            status_code=303,
        )

    @router.post("/sinav/{kimlik}/kabul-yazimlari-tara")
    def sinav_kabul_yazimlarini_tara(kimlik: str):
        """Öğretmenin tam puan verdiği anahtar-dışı yazımları öneri olarak kaydeder."""
        from ..modeller import SoruTipi
        from ..ogrenme import ogrenilmis_kabul_yazimlari

        try:
            sinav = depo.sinav_yukle(kimlik)
        except KeyError as exc:
            raise HTTPException(404, "Sınav bulunamadı") from exc
        duzeltmeler = [dict(x) for x in depo.duzeltme_ornekleri(kimlik)]
        toplam = 0
        for soru in sinav.sorular:
            if soru.tip != SoruTipi.BOSLUK_DOLDURMA:
                continue
            for oneri in ogrenilmis_kabul_yazimlari(
                duzeltmeler,
                soru_no=soru.no,
                max_puan=soru.puan,
                anahtar_yazimlari=list(soru.anahtar.dogru_cevaplar),
            ):
                depo.ogrenilmis_kabul_kaydet(
                    kimlik, soru.no, oneri["yazim"], oneri["destek"]
                )
                toplam += 1
        return RedirectResponse(
            f"/sinav/{kimlik}?kabul_onerisi={toplam}", status_code=303
        )

    @router.post("/kabul-yazimi/{kabul_id}")
    def kabul_yazimi_karar(
        kabul_id: int,
        karar: str = Form("onayla"),
        kimlik: str = Form(...),
    ):
        depo.ogrenilmis_kabul_onayla(kabul_id, onayli=(karar == "onayla"))
        return RedirectResponse(
            f"/sinav/{kimlik}?kabul_karari={karar}#kabul-yazimlari",
            status_code=303,
        )

    @router.post("/sinav/{kimlik}/anahtar-onayla")
    def sinav_anahtar_onayla(kimlik: str):
        try:
            sinav = depo.sinav_yukle(kimlik)
        except KeyError as exc:
            raise HTTPException(404, "Sınav bulunamadı") from exc
        for soru in sinav.sorular:
            soru.anahtar.onay_durumu = "onayli"
            soru.anahtar.surum += 1
        depo.sinav_kaydet(sinav)
        for kagit in depo.kagitlar(kimlik):
            for kutu in depo.kutular(kagit["id"]):
                metin = (
                    kutu["duzeltilmis_metin"]
                    if kutu["duzeltilmis_metin"] is not None
                    else kutu["taninan_metin"] or ""
                )
                baglam._kutu_metnini_otomatik_puanla(kutu, sinav, metin)
            depo.kagit_onayini_kaldir(kagit["id"])
        return RedirectResponse(
            f"/sinav/{kimlik}?anahtar_onaylandi=1",
            status_code=303,
        )

    @router.post("/sinav/{kimlik}/esneklik")
    def sinav_esneklik(kimlik: str, profil: str = Form("dengeli")):
        if profil not in {"kati", "dengeli", "esnek"}:
            raise HTTPException(400, "Geçersiz puanlama profili")
        try:
            sinav = depo.sinav_yukle(kimlik)
        except KeyError as exc:
            raise HTTPException(404, "Sınav bulunamadı") from exc
        for soru in sinav.sorular:
            soru.esneklik = profil
            soru.anahtar.esneklik = profil
        depo.sinav_kaydet(sinav)
        return RedirectResponse(
            f"/sinav/{kimlik}?esneklik={profil}", status_code=303
        )

    @router.get("/sinav/{kimlik}/inceleme", response_class=HTMLResponse)
    def sinav_inceleme(request: Request, kimlik: str):
        """En şüpheli kutuyu önce gösteren odak inceleme kuyruğu."""
        try:
            sinav = depo.sinav_yukle(kimlik)
        except KeyError as exc:
            raise HTTPException(404, "Sınav bulunamadı") from exc
        bekleyenler = [
            b for b in depo.sinav_cevaplari(kimlik)
            if b["incele"] and not b["onaylandi"]
        ]
        # En şüpheli önce: yüksek risk, düşük tanıma güveni, düşük puanlama güveni.
        bekleyenler.sort(
            key=lambda b: (
                -float(b["risk"] or 0),
                float(b["tanima_guveni"] or 0),
                float(b["puanlama_guveni"] or 0),
            )
        )
        toplam = len(bekleyenler)
        try:
            konum = max(0, int(request.query_params.get("kutu", 0)))
        except ValueError:
            konum = 0
        konum = min(konum, max(0, toplam - 1))
        aktif = bekleyenler[konum] if bekleyenler else None
        kart = None
        if aktif is not None:
            soru = sinav.soru(aktif["soru_no"])
            kart = {
                "b": aktif,
                "soru": soru,
                "metin": (
                    aktif["duzeltilmis_metin"]
                    if aktif["duzeltilmis_metin"] is not None
                    else aktif["taninan_metin"]
                ),
                "kirp_url": baglam._kirp_url(aktif["kirp_yolu"]),
            }
        return sablonlar.TemplateResponse(
            request, "inceleme.html",
            {
                "kimlik": kimlik, "sinav": sinav,
                "kart": kart, "konum": konum, "toplam": toplam,
                "onceki": konum - 1 if konum > 0 else None,
                "sonraki": konum + 1 if konum + 1 < toplam else None,
                "kuyruk_sagligi": _kuyruk_sagligi(bekleyenler),
            },
        )

    def _kuyruk_sagligi(bekleyenler: list) -> dict:
        """Kuyruğun neden dolu olduğunu özetler.

        Tek bir neden bekleyenlerin neredeyse tamamını üretiyorsa kuyruk
        sinyal taşımıyor demektir — öğretmen "hangisi gerçekten şüpheli"
        bilgisini kaybeder. Bunu saklamak yerine göstermek gerekir.
        """
        if not bekleyenler:
            return {}
        sayimlar: dict[str, int] = {}
        for kutu in bekleyenler:
            try:
                nedenler = json.loads(kutu["kabul_nedenleri_json"] or "[]")
            except (TypeError, ValueError):
                nedenler = []
            for neden in nedenler or ["Belirtilmemiş"]:
                kisa = str(neden).split("(")[0].strip().rstrip(".")
                sayimlar[kisa] = sayimlar.get(kisa, 0) + 1
        if not sayimlar:
            return {}
        sirali = sorted(sayimlar.items(), key=lambda x: -x[1])
        baskin_ad, baskin_sayi = sirali[0]
        return {
            "toplam": len(bekleyenler),
            "nedenler": [
                {"ad": ad, "adet": adet} for ad, adet in sirali[:5]
            ],
            "baskin": (
                {"ad": baskin_ad, "oran": round(baskin_sayi / len(bekleyenler), 3)}
                if baskin_sayi / len(bekleyenler) >= 0.9
                else None
            ),
        }

    @router.get("/sinav/{kimlik}/tutarlilik", response_class=HTMLResponse)
    def sinav_tutarlilik(request: Request, kimlik: str):
        """Benzer yazılıp farklı puan almış cevap çiftlerini yan yana çözer."""
        from ..analiz import kutu_metni, tutarsiz_ciftler

        try:
            sinav = depo.sinav_yukle(kimlik)
        except KeyError as exc:
            raise HTTPException(404, "Sınav bulunamadı") from exc
        satirlar = defaultdict(list)
        for satir in depo.sinav_cevaplari(kimlik):
            satirlar[int(satir["soru_no"])].append(satir)
        ciftler = []
        for soru in sinav.sorular:
            for cift in tutarsiz_ciftler(satirlar.get(soru.no, []), soru.puan):
                ciftler.append({"soru_no": soru.no, **cift})
        # En büyük puan farkı önce: aynı cevaba en aykırı puanlar en acil.
        ciftler.sort(key=lambda c: -float(c["puan_farki"]))
        toplam = len(ciftler)
        try:
            konum = max(0, int(request.query_params.get("cift", 0)))
        except ValueError:
            konum = 0
        konum = min(konum, max(0, toplam - 1))
        kart = None
        if ciftler:
            secili = ciftler[konum]
            soru = sinav.soru(secili["soru_no"])
            taraflar = []
            for anahtar in ("kutu_a", "kutu_b"):
                kutu = depo.kutu(secili[anahtar])
                if kutu is None:
                    taraflar = []
                    break
                kagit = depo.kagit(kutu["kagit_id"])
                ad = " ".join(
                    p
                    for p in (
                        (kagit["ogrenci_ad"] if kagit else "") or "",
                        (kagit["ogrenci_soyad"] if kagit else "") or "",
                    )
                    if p
                )
                taraflar.append(
                    {
                        "kutu": kutu,
                        "ogrenci": ad or f"Kâğıt #{kutu['kagit_id']}",
                        "metin": kutu_metni(kutu),
                        "kirp_url": baglam._kirp_url(kutu["kirp_yolu"]),
                    }
                )
            if taraflar:
                kart = {"cift": secili, "soru": soru, "taraflar": taraflar}
        return sablonlar.TemplateResponse(
            request,
            "tutarlilik.html",
            {
                "kimlik": kimlik,
                "sinav": sinav,
                "kart": kart,
                "konum": konum,
                "toplam": toplam,
                "onceki": konum - 1 if konum > 0 else None,
                "sonraki": konum + 1 if konum + 1 < toplam else None,
            },
        )





    @router.post("/sinav/{kimlik}/rag-anahtar-yenile")
    def sinav_rag_anahtar_yenile(kimlik: str):
        """Mevcut sınavın anahtarını RAG'dan yenile ve tüm kâğıtları puanla."""
        from ..modeller import CevapAnahtari, RubrikKalemi, SoruTipi

        try:
            sinav = depo.sinav_yukle(kimlik)
        except KeyError as exc:
            raise HTTPException(404, "Sınav bulunamadı") from exc
        if any(s.tip == SoruTipi.BOSLUK_DOLDURMA for s in sinav.sorular):
            raise HTTPException(
                400,
                "RAG anahtarı yenileme yalnız açık uçlu/kısa cevaplı sınavlarda "
                "kullanılabilir; boşluk doldurma cevapları elle korunmalıdır.",
            )
        try:
            cevaplar = baglam._rag_anahtarlari_uret(
                [(s.no, s.metin, s.puan) for s in sinav.sorular],
                ders=sinav.ders,
            )
        except (ValueError, OSError, json.JSONDecodeError) as exc:
            raise HTTPException(400, str(exc)) from exc
        harita = {x.soru_no: x for x in cevaplar}
        for soru in sinav.sorular:
            cevap = harita[soru.no]
            if (
                not cevap.puanlanabilir
                and soru.anahtar.otomatik_uretildi
                and soru.anahtar.otomatik_puanlama
            ):
                # Geçici sağlayıcı/RAG hatası daha önce doğrulanıp saklanmış
                # çalışan anahtarı silmesin. Yeni taslaklarda ise güvenli kapalı
                # sonuç kaydedilmeye devam eder.
                continue
            parca = soru.puan / len(cevap.rubrik)
            esler = cevap.rubrik_es_anlamlilari or [
                [] for _ in cevap.rubrik
            ]
            kategoriler = cevap.rubrik_kategorileri or [
                "kavram" for _ in cevap.rubrik
            ]
            celiskiler = cevap.rubrik_celiskileri or [
                [] for _ in cevap.rubrik
            ]
            soru.anahtar = CevapAnahtari(
                rubrik=[
                    RubrikKalemi(
                        metin=metin,
                        puan=(
                            soru.puan - parca * (len(cevap.rubrik) - 1)
                            if i == len(cevap.rubrik) - 1 else parca
                        ),
                        esanlamlilar=esler[i] if i < len(esler) else [],
                        kategori=(
                            kategoriler[i] if i < len(kategoriler) else "kavram"
                        ),
                        celiskiler=celiskiler[i] if i < len(celiskiler) else [],
                    )
                    for i, metin in enumerate(cevap.rubrik)
                ],
                ornek_cevap=cevap.cevap,
                kaynaklar=cevap.kaynaklar,
                uretim_yontemi=cevap.uretim_yontemi,
                otomatik_uretildi=True,
                otomatik_puanlama=cevap.puanlanabilir,
                uyari=cevap.uyari,
                kabul_edilen_alternatifler=(
                    cevap.kabul_edilen_alternatifler or []
                ),
                yaygin_hatalar=cevap.yaygin_hatalar or [],
                yasak_celiskiler=cevap.yasak_celiskiler or [],
                yontem_adimlari=cevap.yontem_adimlari or [],
                birimler=cevap.birimler or [],
                onay_durumu="taslak",
                kaynak_kanitlari=[
                    {"kaynak": x} for x in cevap.kaynaklar
                ],
            )
        depo.sinav_kaydet(sinav)
        dosyalar = depo.sinav_dosyasi(kimlik)
        if dosyalar and dosyalar["yaml_yolu"]:
            yaml_yolu = Path(dosyalar["yaml_yolu"])
            if yaml_yolu.is_file():
                sinav.yaml_kaydet(yaml_yolu)
        for kagit in depo.kagitlar(kimlik):
            for kutu in depo.kutular(kagit["id"]):
                metin = (
                    kutu["duzeltilmis_metin"]
                    if kutu["duzeltilmis_metin"] is not None
                    else kutu["taninan_metin"] or ""
                )
                baglam._kutu_metnini_otomatik_puanla(kutu, sinav, metin)
            depo.kagit_onayini_kaldir(kagit["id"])
        return RedirectResponse(
            f"/sinav/{kimlik}?rag_yenilendi=1",
            status_code=303,
        )




    @router.post("/sinav/{kimlik}/toplu-islem")
    def sinav_toplu_islem(
        kimlik: str,
        kagit_id: list[int] = Form(default=[]),
        islem: str = Form("onayla"),
    ):
        """Seçilen kâğıtlara tek hamlede onay/yeniden puanlama/incelemeye alma."""
        if islem not in {"onayla", "yeniden_puanla", "incelemeye_al"}:
            raise HTTPException(400, "Bilinmeyen toplu işlem")
        try:
            sinav = depo.sinav_yukle(kimlik)
        except KeyError as exc:
            raise HTTPException(404, "Sınav bulunamadı") from exc
        islenen = atlanan = 0
        for kid in kagit_id:
            kagit = depo.kagit(kid)
            if kagit is None or kagit["sinav_kimlik"] != kimlik:
                atlanan += 1  # başka sınavın kâğıdı bu listeden yönetilemez
                continue
            if islem == "onayla":
                if depo.cozulmemis_kutular(kid):
                    atlanan += 1
                    continue
                depo.kagit_onayla(kid)
            elif islem == "yeniden_puanla":
                for kutu in depo.kutular(kid):
                    metin = (
                        kutu["duzeltilmis_metin"]
                        if kutu["duzeltilmis_metin"] is not None
                        else kutu["taninan_metin"] or ""
                    )
                    baglam._kutu_metnini_otomatik_puanla(kutu, sinav, metin)
                depo.kagit_onayini_kaldir(kid)
            else:
                for kutu in depo.kutular(kid):
                    depo.kutu_guncelle(
                        kutu_id=kutu["id"],
                        incele=True,
                        neden="Toplu işlem: öğretmen kâğıdı incelemeye aldı",
                    )
                depo.kagit_onayini_kaldir(kid)
            islenen += 1
        return RedirectResponse(
            f"/sinav/{kimlik}?toplu={islenen}&atlanan={atlanan}&islem={islem}",
            status_code=303,
        )


    @router.get("/sinav/{kimlik}/rapor.xlsx")
    def sinav_raporu(kimlik: str):
        try:
            depo.sinav_yukle(kimlik)
        except KeyError as exc:
            raise HTTPException(404, "Sınav bulunamadı") from exc
        from ..rapor import excel_dokum

        gecici = tempfile.NamedTemporaryFile(prefix="sinav-okur-", suffix=".xlsx", delete=False)
        gecici.close()
        try:
            excel_dokum(depo, kimlik, gecici.name)
        except Exception:
            os.unlink(gecici.name)
            raise
        guvenli_ad = re.sub(r"[^A-Za-z0-9._-]+", "_", kimlik).strip("._") or "sinav"
        return FileResponse(
            gecici.name,
            filename=f"{guvenli_ad}_notlar.xlsx",
            media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            background=BackgroundTask(os.unlink, gecici.name),
        )




    @router.get("/sinav/{kimlik}/geri-bildirimler", response_class=HTMLResponse)
    def sinav_geri_bildirimleri(request: Request, kimlik: str):
        try:
            sinav = depo.sinav_yukle(kimlik)
        except KeyError as exc:
            raise HTTPException(404, "Sınav bulunamadı") from exc
        gorsel = request.query_params.get("gorsel") == "1"
        # ?kagit=3&kagit=7 verilirse yalnız seçilenler basılır; yoksa
        # onaylanmış tüm kâğıtlar (mevcut davranış).
        secilenler = set()
        for ham in request.query_params.getlist("kagit"):
            try:
                secilenler.add(int(ham))
            except ValueError:
                continue
        def _basilir(kagit) -> bool:
            if secilenler:
                return kagit["id"] in secilenler
            return bool(kagit["onaylandi"])

        # Kazanım analizi sınavın TÜM cevaplarını okur; kâğıt başına
        # çağrılırsa sayfa O(N²) olur. Bir kez hesaplanıp paylaşılır.
        from ..analiz import kazanim_analizi

        basilacaklar = [k for k in depo.kagitlar(kimlik) if _basilir(k)]
        kazanim = kazanim_analizi(depo, sinav) if basilacaklar else None
        kagitlar = [
            baglam._geri_bildirim_kagidi(
                k["id"], gorsel, sinav=sinav, kazanim=kazanim
            )
            for k in basilacaklar
        ]
        return sablonlar.TemplateResponse(
            request, "geri_bildirim.html",
            {"sinav": sinav, "kagitlar": kagitlar, "gorsel": gorsel,
             "toplu": True, "kimlik": kimlik},
        )

    return router
