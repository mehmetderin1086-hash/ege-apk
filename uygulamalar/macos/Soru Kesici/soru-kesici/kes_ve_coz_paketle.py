#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Soru Kesici ile Kes ve Coz v1 soru paketi uret.

Bu modul Soru Kesici cekirdegi ile cozucu arasindaki dar, surumlu sinirdir.
Girdi tek bir PDF, DOCX veya gorseldir; cikti atomik yazilan bir ZIP'tir.
ZIP icindeki ``manifest.json`` yalniz cozulmesi gereken soru gorsellerini
isaret eder. Cevap/solusyon sayfalari kesime girmez ve cozum gorseli hicbir
zaman soruya ilistirilmez. Varsa resmi cevap, model girdisi olmayan ayri
``reference_answer`` alaninda korunur.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import math
import os
import re
import sys
import tempfile
import zipfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable, Dict, Iterable, List, Optional, Sequence, Tuple

import soru_kes as sk


SCHEMA = "kes-ve-coz-question-package-v1"
QUALITY_MODE = "balanced"
DEFAULT_MAX_INPUT_MB = 2048
DEFAULT_MAX_OUTPUT_MB = 4096
DEFAULT_MAX_PAGES = 2500
DEFAULT_MAX_QUESTIONS = 10000

# Cekirdegin sayfa rolu cezasi nedeniyle reddettigi bir adayi ancak bu dar
# kanit kumesiyle inceleme kovasina geri aliriz. Genel numarali paragraflar,
# cevap/cozum sayfalari ve sinir uyusmazligi olan ust yonergeler bu yola
# giremez.
RAW_RECOVERY_REQUIRED_EVIDENCE = {
    "soru_numarasi", "uygun_geometri", "gomulu_soru_gorseli"}
RAW_RECOVERY_BLOCKING_WARNINGS = {
    "soru_modeli_sinir_uyusmazligi", "soru_disinda_sayfa",
    "aday_cakismasi"}
RAW_RECOVERY_BLOCKING_ROLES = {
    "cevap_anahtari", "cozum", "çözüm", "kapak", "icindekiler",
    "içindekiler"}
RAW_OPTION_RE = re.compile(r"(?:^|\s)([A-E])\s*[.)]\s*")


class PaketlemeHatasi(RuntimeError):
    """Kullaniciya aciklanabilir ve kismi cikti birakmayan paketleme hatasi."""


EventSink = Callable[[Dict[str, Any]], None]


def _bos_olay(_olay: Dict[str, Any]) -> None:
    return None


def _json_olay(olay: Dict[str, Any], *, akim: Any = sys.stdout) -> None:
    print(json.dumps(olay, ensure_ascii=False, separators=(",", ":")),
          file=akim, flush=True)


def _pozitif_sayi(ad: str, deger: int) -> int:
    if deger <= 0:
        raise PaketlemeHatasi(f"{ad} sifirdan buyuk olmali")
    return deger


def _girdiyi_dogrula(girdi: Path, cikti: Path, azami_girdi_bayt: int) -> None:
    if not girdi.exists():
        raise PaketlemeHatasi(f"girdi bulunamadi: {girdi}")
    if not girdi.is_file():
        raise PaketlemeHatasi(f"girdi bir dosya olmali: {girdi}")
    if girdi.suffix.lower() not in sk.GIRDI_UZANTILARI:
        destek = ", ".join(sorted(sk.GIRDI_UZANTILARI))
        raise PaketlemeHatasi(
            f"desteklenmeyen girdi uzantisi: {girdi.suffix or '(yok)'}; "
            f"desteklenenler: {destek}")
    try:
        boyut = girdi.stat().st_size
    except OSError as exc:
        raise PaketlemeHatasi(f"girdi bilgisi okunamadi: {exc}") from exc
    if boyut <= 0:
        raise PaketlemeHatasi("girdi dosyasi bos")
    if boyut > azami_girdi_bayt:
        raise PaketlemeHatasi(
            f"girdi boyutu siniri asiyor: {boyut} > {azami_girdi_bayt} bayt")
    if girdi.resolve() == cikti.resolve(strict=False):
        raise PaketlemeHatasi("girdi ve cikti ayni dosya olamaz")
    if cikti.suffix.lower() != ".zip":
        raise PaketlemeHatasi("cikti yolu .zip uzantili olmali")


def _sha256(yol: Path) -> str:
    ozet = hashlib.sha256()
    try:
        with yol.open("rb") as dosya:
            for parca in iter(lambda: dosya.read(1024 * 1024), b""):
                ozet.update(parca)
    except OSError as exc:
        raise PaketlemeHatasi(f"girdi okunamadi: {exc}") from exc
    return ozet.hexdigest()


def _sayfa_sayisi_on_kontrol(girdi: Path) -> Optional[int]:
    """PDF/cok-kareli gorseli pahali OCR'dan once sinirlamak icin say."""
    try:
        if girdi.suffix.lower() == ".pdf":
            with sk.fitz.open(str(girdi)) as belge:
                if belge.needs_pass:
                    raise PaketlemeHatasi("sifreli PDF desteklenmiyor")
                return int(belge.page_count)
        if girdi.suffix.lower() in sk.GORUNTU_UZANTILARI:
            with sk.Image.open(str(girdi)) as gorsel:
                return (max(1, int(getattr(gorsel, "n_frames", 1)))
                        if girdi.suffix.lower() in sk.COK_KARELI_UZANTILAR
                        else 1)
    except PaketlemeHatasi:
        raise
    except Exception as exc:
        raise PaketlemeHatasi(
            f"girdi on denetimde acilamadi: {exc}") from exc
    # DOCX sayfa sayisi ancak LibreOffice donusumunden sonra bilinir.
    return None


def _dosya_imzasi(yol: Path) -> Tuple[int, int]:
    try:
        bilgi = yol.stat()
    except OSError as exc:
        raise PaketlemeHatasi(f"girdi bilgisi okunamadi: {exc}") from exc
    return int(bilgi.st_size), int(bilgi.st_mtime_ns)


def _tekil_metinler(*kapsayicilar: Iterable[Any]) -> List[str]:
    sonuc: List[str] = []
    gorulen = set()
    for kapsayici in kapsayicilar:
        for deger in kapsayici or ():
            metin = str(deger).strip()
            if metin and metin not in gorulen:
                gorulen.add(metin)
                sonuc.append(metin)
    return sonuc


def _guven(deger: Any) -> float:
    try:
        sayi = float(deger)
    except (TypeError, ValueError):
        return 0.0
    if not math.isfinite(sayi):
        return 0.0
    return round(max(0.0, min(1.0, sayi)), 3)


def _kaynak_parcalari(plan: Sequence[Tuple[int, Sequence[float]]]) \
        -> List[Dict[str, Any]]:
    parcalar = []
    for sayfa, kutu in plan:
        if len(kutu) != 4:
            raise PaketlemeHatasi("cekirdek gecersiz kaynak kutusu dondurdu")
        degerler = [float(v) for v in kutu]
        if not all(math.isfinite(v) for v in degerler) or \
                degerler[2] <= degerler[0] or degerler[3] <= degerler[1]:
            raise PaketlemeHatasi("cekirdek gecersiz kaynak kutusu dondurdu")
        parcalar.append({
            "page": int(sayfa) + 1,
            "box": [round(v, 3) for v in degerler],
        })
    if not parcalar:
        raise PaketlemeHatasi("cekirdek kaynak kutusu dondurmedi")
    return parcalar


def _ana_kaynak_kutusu(parcalar: Sequence[Dict[str, Any]],
                        kaynak_sayfa: int) -> List[float]:
    """Ilk kaynak sayfadaki tum parcalarin birlesim kutusunu dondurur."""
    kutular = [p["box"] for p in parcalar if p["page"] == kaynak_sayfa]
    if not kutular:
        kutular = [parcalar[0]["box"]]
    return [
        min(k[0] for k in kutular), min(k[1] for k in kutular),
        max(k[2] for k in kutular), max(k[3] for k in kutular),
    ]


def _external_id(kaynak_sha256: str, soru: Dict[str, Any],
                 parcalar: Sequence[Dict[str, Any]],
                 gorulen: Dict[str, int]) -> str:
    kimlik_malzemesi = {
        "source_sha256": kaynak_sha256,
        "source_parts": parcalar,
        "question_number": soru.get("soru_no"),
        "text": str(soru.get("govde") or soru.get("metin") or "").strip(),
    }
    ham = json.dumps(kimlik_malzemesi, ensure_ascii=False, sort_keys=True,
                     separators=(",", ":")).encode("utf-8")
    temel = "skq_" + hashlib.sha256(ham).hexdigest()[:24]
    tekrar = gorulen.get(temel, 0) + 1
    gorulen[temel] = tekrar
    return temel if tekrar == 1 else f"{temel}_{tekrar}"


def _soru_kaydi(soru: Dict[str, Any],
                 plan: Sequence[Tuple[int, Sequence[float]]],
                 kaynak_sha256: str, kaynak_adi: str, review: bool,
                 gorulen: Dict[str, int]) -> Dict[str, Any]:
    parcalar = _kaynak_parcalari(plan)
    try:
        kaynak_sayfa = int(soru.get("sayfa") or parcalar[0]["page"])
    except (TypeError, ValueError):
        kaynak_sayfa = int(parcalar[0]["page"])
    secenekler = soru.get("siklar") or {}
    if not isinstance(secenekler, dict):
        secenekler = {}
    choices = {
        str(harf).strip().upper(): str(metin).strip()
        for harf, metin in secenekler.items()
        if str(harf).strip() and str(metin).strip()
    }
    uyarilar = _tekil_metinler(
        soru.get("tespit_uyarilari") or (),
        soru.get("inceleme_gerekcesi") or ())
    if review and not uyarilar:
        uyarilar.append("quality_review_required")
    external_id = _external_id(
        kaynak_sha256, soru, parcalar, gorulen)
    cevap = str(soru.get("cevap") or "").strip() or None
    return {
        "external_id": external_id,
        "text": str(soru.get("govde") or soru.get("metin") or "").strip(),
        "choices": choices,
        "image": f"images/{external_id}.png",
        "source_document": str(soru.get("kaynak") or kaynak_adi),
        "source_page": kaynak_sayfa,
        "source_box": _ana_kaynak_kutusu(parcalar, kaynak_sayfa),
        # Bolunmus sorularda kaynak kutusunu kaybetmemek icin ek alan.
        "source_parts": parcalar,
        "cutter_version": str(
            soru.get("algoritma_surumu") or sk.KALIBRASYON_SURUMU),
        "confidence": _guven(soru.get("guven")),
        "quality_status": "review" if review else "automatic",
        "review_required": bool(review),
        "warnings": uyarilar,
        # Bu alan answer_policy geregi model girdisine verilemez.
        "reference_answer": cevap,
    }


def _kova_kes(sayfalar: Sequence[Any], fmt: str, girdi: Path,
              cevaplar: Any, *, review: bool, olay: EventSink) \
        -> Tuple[List[Any], List[Dict[str, Any]], List[Any], List[str]]:
    kova = "incele" if review else "cikti"
    plan, _meta, _testler = sk.kirpma_plani_meta(
        sayfalar, fmt, birlestir=True, agresif=False, kutu_atama=None,
        cevap_disla=True, kalite=QUALITY_MODE, kova=kova)

    def ilerleme(simdiki: int, toplam: int) -> None:
        olay({"event": "cut_progress",
              "bucket": "review" if review else "automatic",
              "current": simdiki, "total": toplam})

    kirpmalar, sorular, uyarilar = sk.kirpma_seti(
        sayfalar, fmt, girdiler=[str(girdi)], birlestir=True,
        agresif=False, kutu_atama=None, secim=None, secim_kutular=None,
        cevaplar=cevaplar, numara_temizle=False, ilerleme=ilerleme,
        # Guvenlik siniri: cevap/cozum sayfalari gorsel aday olamaz.
        cevap_disla=True, rastgele=None, tohum=None, konu_sozluk=None,
        etiketler=None, kalite=QUALITY_MODE, cevap_bandi=False,
        cevap_duzeltmeler=None, kova=kova)
    # cozumleri_ilistir bilincli olarak HIC cagrilmaz (cozum_ilistir=False).
    if len(kirpmalar) != len(sorular) or len(plan) != len(sorular):
        raise PaketlemeHatasi(
            "cekirdek kesim, metadata ve kaynak kutusu sayilari uyusmuyor")
    return list(kirpmalar), list(sorular), list(plan), list(uyarilar)


def _ocr_coktan_secmeli_ayristir(metin: str) \
        -> Tuple[str, Dict[str, str]]:
    """OCR'nin A-E sirasi bozuk olsa da govde ve benzersiz siklari ayir."""
    eslesmeler = list(RAW_OPTION_RE.finditer(str(metin or "")))
    siklar: Dict[str, str] = {}
    ilk = len(metin or "")
    for sira, eslesme in enumerate(eslesmeler):
        harf = eslesme.group(1).upper()
        if harf in siklar:
            continue
        son = (eslesmeler[sira + 1].start(1)
               if sira + 1 < len(eslesmeler) else len(metin))
        icerik = metin[eslesme.end():son].strip()
        if icerik:
            siklar[harf] = icerik
            ilk = min(ilk, eslesme.start(1))
    govde = metin[:ilk].strip() if siklar else str(metin or "").strip()
    return govde, siklar


def _referans_cevabi(cevaplar: Any, test_no: Any,
                     soru_no: Any) -> Optional[str]:
    if soru_no is None:
        return None
    bloklar = [b for b in (cevaplar or ()) if isinstance(b, dict)]
    for hedef_test in (test_no, None):
        for blok in bloklar:
            if blok.get("test_no") != hedef_test:
                continue
            cevap = (blok.get("cevaplar") or {}).get(soru_no)
            if cevap:
                return str(cevap).strip().upper() or None
    return None


def _ham_review_kurtar(sayfalar: Sequence[Any], fmt: str,
                       analizler: Sequence[Any], girdi: Path, cevaplar: Any,
                       olay: EventSink) \
        -> Tuple[List[Any], List[Dict[str, Any]], List[Any], List[str], int]:
    """Yuksek kanitli gomulu soru gorsellerini yalniz REVIEW olarak kurtar.

    Cekirdek ``reddedildi`` adaylarini bilerek cikti/incele kovalarina almaz.
    Bazi Soru Kesici sinav PDF'lerinde sayfa ``konu`` sanildigi icin tam soru
    gorselleri de 0.35'e tavanlanir. Burada cekirdegin final sozlesmesini
    degistirmeden, rol cezasindan ONCEKI kalibre guveni yuksek olan gomulu
    gorseli yeniden OCR ile kanitlariz. En az uc A-E sikki ve soru yonergesi
    bulunmayan aday (ornegin ust kitapcik talimati) geri alinmaz.
    """
    adaylar = []
    for sayfa_idx, analiz in enumerate(analizler or ()):
        for aday in getattr(analiz, "adaylar", ()) or ():
            if getattr(aday, "devam_aday", False) or \
                    getattr(aday, "inceleme_durumu", "") != "reddedildi":
                continue
            kanitlar = set(getattr(aday, "kanitlar", ()) or ())
            kalibre = getattr(aday, "kalibre_guven", None)
            try:
                kalibre = float(kalibre)
            except (TypeError, ValueError):
                kalibre = 0.0
            if kalibre < float(sk.GUVEN_OTOMATIK) or not \
                    RAW_RECOVERY_REQUIRED_EVIDENCE.issubset(kanitlar):
                continue
            adaylar.append((sayfa_idx, analiz, aday, kalibre))
    if not adaylar:
        return [], [], [], [], 0

    try:
        dislanacak, _soru_sayfalari = sk._belge_sayfa_rolleri(
            sayfalar, QUALITY_MODE, fmt=fmt)
    except Exception as exc:
        # Sayfa guvenlik sinifi kurulamiyorsa geri kazanmak yerine reddet.
        return [], [], [], [
            f"ham review kurtarma guvenlik sinifi kurulamadi: "
            f"{type(exc).__name__}: {exc}"], 0

    gorseller: List[Any] = []
    sorular: List[Dict[str, Any]] = []
    planlar: List[Any] = []
    uyarilar: List[str] = []
    for sayfa_idx, analiz, aday, kalibre in adaylar:
        no = getattr(aday, "numara", None)
        neden = None
        rol = str(getattr(analiz, "sayfa_rolu", "") or "").lower()
        aday_rolu = str(getattr(aday, "sayfa_rolu", "") or "").lower()
        aday_uyarilari = set(getattr(aday, "uyarilar", ()) or ())
        if sayfa_idx in dislanacak or rol in RAW_RECOVERY_BLOCKING_ROLES or \
                aday_rolu in RAW_RECOVERY_BLOCKING_ROLES:
            neden = "guvensiz_sayfa_rolu"
        elif aday_uyarilari & RAW_RECOVERY_BLOCKING_WARNINGS:
            neden = "sinir_veya_icerik_uyusmazligi"
        elif no is None or not (0 <= sayfa_idx < len(sayfalar)):
            neden = "soru_numarasi_veya_sayfa_eksik"
        if neden:
            olay({"event": "recovery_candidate", "page": sayfa_idx + 1,
                  "question_number": no, "status": "skipped",
                  "reason": neden})
            continue

        try:
            kutu = tuple(float(v) for v in getattr(aday, "kutu"))
            if len(kutu) != 4:
                raise ValueError("kutu dort koordinatli degil")
            gorsel, _ofset = sk._trasla_ofset(
                sayfalar[sayfa_idx].kirp(kutu))
            ocr = sk.soru_metni_ocr(gorsel)
            metin = str((ocr or {}).get("metin") or "").strip()
            govde, siklar = _ocr_coktan_secmeli_ayristir(metin)
            yonerge = bool("?" in govde or sk.SORU_YONERGE_GUCLU.search(govde))
            if not yonerge or len(siklar) < 3:
                raise ValueError(
                    "OCR en az uc sik ve soru yonergesi dogrulamadi")
        except Exception as exc:
            olay({"event": "recovery_candidate", "page": sayfa_idx + 1,
                  "question_number": no, "status": "skipped",
                  "reason": "ocr_question_contract_failed"})
            uyarilar.append(
                f"sayfa {sayfa_idx + 1} soru {no} ham adayi kurtarilmadi: "
                f"{type(exc).__name__}: {exc}")
            continue

        test_no = getattr(aday, "test_no", None)
        sorun = _tekil_metinler(
            aday_uyarilari,
            ("raw_rejected_candidate_recovered_for_review",
             f"pre_role_confidence:{kalibre:.3f}"))
        sorular.append({
            "soru_no": no,
            "sayfa": sayfa_idx + 1,
            "kaynak": girdi.name,
            "metin": metin,
            "govde": govde,
            "siklar": siklar,
            "cevap": _referans_cevabi(cevaplar, test_no, no),
            "algoritma_surumu": sk.KALIBRASYON_SURUMU,
            "guven": getattr(aday, "guven", 0.0),
            "inceleme_durumu": "incele",
            "tespit_uyarilari": list(aday_uyarilari),
            "inceleme_gerekcesi": sorun,
        })
        gorseller.append(gorsel)
        planlar.append([(sayfa_idx, kutu)])
        olay({"event": "recovery_candidate", "page": sayfa_idx + 1,
              "question_number": no, "status": "recovered",
              "bucket": "review"})
    return gorseller, sorular, planlar, uyarilar, len(sorular)


def _kalite_ozeti(kapi: Any, analizler: Sequence[Any], otomatik: int,
                  inceleme: int, kurtarilan: int = 0) \
        -> Tuple[Dict[str, Any], List[str]]:
    kapi_sozluk = kapi.to_dict() if hasattr(kapi, "to_dict") else dict(kapi)
    reddedilen = 0
    for analiz in analizler or ():
        for aday in getattr(analiz, "adaylar", ()) or ():
            if not getattr(aday, "devam_aday", False) and \
                    getattr(aday, "inceleme_durumu", "") == "reddedildi":
                reddedilen += 1
    uyarilar = []
    kurtarilan = max(0, min(reddedilen, int(kurtarilan)))
    kurtarilmayan = max(0, reddedilen - kurtarilan)
    if kurtarilan:
        uyarilar.append(
            f"{kurtarilan} yuksek kanitli reddedilmis aday guvenli "
            "olarak review kovasina kurtarildi")
    if kurtarilmayan:
        uyarilar.append(
            f"{kurtarilmayan} ham aday kesici tarafindan "
            "reddedildi; ilgili kaynak sayfalar elle incelenmeli")
    bekleyen_sayfalar = kapi_sozluk.get("bekleyen_sayfalar") or ()
    if bekleyen_sayfalar:
        uyarilar.append(
            f"{len(bekleyen_sayfalar)} kaynak sayfa kalite incelemesi "
            "gerektiriyor; belirsiz kesimler review kovasinda")
    if otomatik + inceleme == 0:
        uyarilar.append("belgede paketlenebilir soru tespit edilmedi")
    for hata in kapi_sozluk.get("pipeline_hatalari") or ():
        uyarilar.append("pipeline_hatasi: " + json.dumps(
            hata, ensure_ascii=False, sort_keys=True))
    return ({
        "mode": QUALITY_MODE,
        "automatic_count": otomatik,
        "review_count": inceleme,
        "packaged_count": otomatik + inceleme,
        "rejected_candidate_count": reddedilen,
        "recovered_to_review_count": kurtarilan,
        "unrecovered_rejected_candidate_count": kurtarilmayan,
        "gate": kapi_sozluk,
    }, uyarilar)


def _atomik_zip_yaz(cikti: Path, manifest: Dict[str, Any],
                     soru_gorselleri: Sequence[Tuple[Dict[str, Any], Any]],
                     azami_cikti_bayt: int, olay: EventSink) -> int:
    try:
        cikti.parent.mkdir(parents=True, exist_ok=True)
        fd, gecici_ad = tempfile.mkstemp(
            prefix=f".{cikti.name}.", suffix=".tmp", dir=str(cikti.parent))
    except OSError as exc:
        raise PaketlemeHatasi(f"cikti hazirlanamadi: {exc}") from exc
    gecici = Path(gecici_ad)
    acilmis_boyut = 0
    try:
        with os.fdopen(fd, "w+b") as ham:
            with zipfile.ZipFile(
                    ham, "w", compression=zipfile.ZIP_DEFLATED,
                    compresslevel=6, allowZip64=True) as arsiv:
                toplam = len(soru_gorselleri)
                for sira, (soru, gorsel) in enumerate(soru_gorselleri, 1):
                    tampon = io.BytesIO()
                    gorsel.save(tampon, format="PNG")
                    veri = tampon.getvalue()
                    acilmis_boyut += len(veri)
                    if acilmis_boyut > azami_cikti_bayt:
                        raise PaketlemeHatasi(
                            "soru gorselleri cikti boyutu sinirini asiyor")
                    arsiv.writestr(soru["image"], veri)
                    if ham.tell() > azami_cikti_bayt:
                        raise PaketlemeHatasi(
                            "sikistirilmis paket cikti boyutu sinirini asiyor")
                    olay({"event": "package_progress", "current": sira,
                          "total": toplam})
                manifest_veri = json.dumps(
                    manifest, ensure_ascii=False, indent=2,
                    sort_keys=True).encode("utf-8")
                acilmis_boyut += len(manifest_veri)
                if acilmis_boyut > azami_cikti_bayt:
                    raise PaketlemeHatasi("manifest cikti boyutu sinirini asiyor")
                arsiv.writestr("manifest.json", manifest_veri)
            ham.flush()
            os.fsync(ham.fileno())
        boyut = gecici.stat().st_size
        if boyut > azami_cikti_bayt:
            raise PaketlemeHatasi("paket cikti boyutu sinirini asiyor")
        with zipfile.ZipFile(gecici, "r") as dogrulama:
            bozuk_uye = dogrulama.testzip()
            if bozuk_uye is not None or "manifest.json" not in \
                    dogrulama.namelist():
                ayrinti = bozuk_uye or "manifest.json eksik"
                raise PaketlemeHatasi(f"paket dogrulanamadi: {ayrinti}")
        os.replace(str(gecici), str(cikti))
        return boyut
    except Exception:
        try:
            gecici.unlink()
        except FileNotFoundError:
            pass
        raise


def paketle(girdi_yolu: str, cikti_yolu: str, *, dpi: int = 300,
            max_input_mb: int = DEFAULT_MAX_INPUT_MB,
            max_output_mb: int = DEFAULT_MAX_OUTPUT_MB,
            max_pages: int = DEFAULT_MAX_PAGES,
            max_questions: int = DEFAULT_MAX_QUESTIONS,
            emit: Optional[EventSink] = None) -> Dict[str, Any]:
    """Tek girdiyi v1 Kes ve Coz paketine cevir ve final ozeti dondur."""
    olay = emit or _bos_olay
    girdi = Path(girdi_yolu).expanduser()
    cikti = Path(cikti_yolu).expanduser()
    max_input_mb = _pozitif_sayi("max_input_mb", int(max_input_mb))
    max_output_mb = _pozitif_sayi("max_output_mb", int(max_output_mb))
    max_pages = _pozitif_sayi("max_pages", int(max_pages))
    max_questions = _pozitif_sayi("max_questions", int(max_questions))
    if not 72 <= int(dpi) <= 600:
        raise PaketlemeHatasi("dpi 72 ile 600 arasinda olmali")
    azami_girdi_bayt = max_input_mb * 1024 * 1024
    azami_cikti_bayt = max_output_mb * 1024 * 1024
    _girdiyi_dogrula(girdi, cikti, azami_girdi_bayt)
    on_sayfa = _sayfa_sayisi_on_kontrol(girdi)
    if on_sayfa is not None and on_sayfa > max_pages:
        raise PaketlemeHatasi(
            f"sayfa sayisi siniri asiyor: {on_sayfa} > {max_pages}")
    kaynak_imzasi = _dosya_imzasi(girdi)
    kaynak_boyutu = kaynak_imzasi[0]
    kaynak_sha256 = _sha256(girdi)
    if _dosya_imzasi(girdi) != kaynak_imzasi:
        raise PaketlemeHatasi(
            "girdi dosyasi okunurken degisti; kaydetme bittikten sonra "
            "yeniden deneyin")
    olay({"event": "started", "schema": SCHEMA,
          "input": str(girdi), "output": str(cikti)})

    sayfalar = None
    acik = None
    try:
        sayfalar, acik, fmt, _sutunlar = sk.belge_hazirla(
            [str(girdi)], int(dpi))
        if len(sayfalar) > max_pages:
            raise PaketlemeHatasi(
                f"sayfa sayisi siniri asiyor: {len(sayfalar)} > {max_pages}")
        olay({"event": "document_ready", "pages": len(sayfalar),
              "format": fmt})
        kapi, _profil, analizler = sk.kalite_kapisi(
            sayfalar, fmt, [str(girdi)], kalite=QUALITY_MODE)
        # Resmi cevap yalniz manifestte ayri referans alani olur. Asagidaki
        # iki kesim cagrisi cevap_disla=True oldugu icin anahtar sayfalari
        # hicbir zaman images/ altina girmez.
        cevaplar = sk.cevap_anahtari_bul(sayfalar)
        oto_img, oto_soru, oto_plan, oto_uyari = _kova_kes(
            sayfalar, fmt, girdi, cevaplar, review=False, olay=olay)
        inc_img, inc_soru, inc_plan, inc_uyari = _kova_kes(
            sayfalar, fmt, girdi, cevaplar, review=True, olay=olay)
        ham_img, ham_soru, ham_plan, ham_uyari, kurtarilan = \
            _ham_review_kurtar(
                sayfalar, fmt, analizler, girdi, cevaplar, olay)
        inc_img.extend(ham_img)
        inc_soru.extend(ham_soru)
        inc_plan.extend(ham_plan)
        toplam = len(oto_soru) + len(inc_soru)
        if toplam > max_questions:
            raise PaketlemeHatasi(
                f"soru sayisi siniri asiyor: {toplam} > {max_questions}")
        kalite, kalite_uyari = _kalite_ozeti(
            kapi, analizler, len(oto_soru), len(inc_soru), kurtarilan)
        paket_uyarilari = _tekil_metinler(
            oto_uyari, inc_uyari, ham_uyari, kalite_uyari)

        gorulen: Dict[str, int] = {}
        soru_gorselleri: List[Tuple[Dict[str, Any], Any]] = []
        for review, gorseller, sorular, planlar in (
                (False, oto_img, oto_soru, oto_plan),
                (True, inc_img, inc_soru, inc_plan)):
            for gorsel, soru, plan in zip(gorseller, sorular, planlar):
                kayit = _soru_kaydi(
                    soru, plan, kaynak_sha256, girdi.name, review, gorulen)
                soru_gorselleri.append((kayit, gorsel))

        manifest = {
            "schema_version": SCHEMA,
            "source_app": "Soru Kesici",
            "source_version": sk.KALIBRASYON_SURUMU,
            "created_at": datetime.now(timezone.utc).isoformat(),
            "producer": {
                "name": "Soru Kesici",
                "cutter_version": sk.KALIBRASYON_SURUMU,
            },
            "source": {
                "document": girdi.name,
                "sha256": kaynak_sha256,
                "size_bytes": kaynak_boyutu,
                "page_count": len(sayfalar),
            },
            "answer_policy": {
                "solution_images_included": False,
                "answer_pages_included": False,
                "model_input_fields": [
                    "external_id", "text", "choices", "image"],
                "withheld_from_model": ["reference_answer"],
                "reference_answer_purpose": "post-solve-evaluation-only",
            },
            "quality": kalite,
            "warnings": paket_uyarilari,
            "questions": [soru for soru, _gorsel in soru_gorselleri],
        }
        if _dosya_imzasi(girdi) != kaynak_imzasi:
            raise PaketlemeHatasi(
                "girdi dosyasi isleme sirasinda degisti; yeniden deneyin")
        boyut = _atomik_zip_yaz(
            cikti, manifest, soru_gorselleri, azami_cikti_bayt, olay)
    finally:
        if acik is not None:
            sk.belge_kapat(acik)

    ozet = {
        "event": "completed", "schema": SCHEMA,
        "output": str(cikti), "bytes": boyut,
        "questions": toplam, "automatic": len(oto_soru),
        "review": len(inc_soru), "warnings": len(paket_uyarilari),
    }
    olay(ozet)
    return ozet


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="PDF/DOCX/gorseli Soru Kesici ile kesip Kes ve Coz v1 "
                    "paketi uretir.")
    parser.add_argument("input", help="PDF, DOCX veya gorsel dosyasi")
    parser.add_argument("-o", "--output", required=True,
                        help="atomik yazilacak .zip cikti yolu")
    parser.add_argument("--dpi", type=int, default=300,
                        help="kesim DPI degeri (72-600; varsayilan 300)")
    parser.add_argument("--max-input-mb", type=int,
                        default=DEFAULT_MAX_INPUT_MB)
    parser.add_argument("--max-output-mb", type=int,
                        default=DEFAULT_MAX_OUTPUT_MB)
    parser.add_argument("--max-pages", type=int, default=DEFAULT_MAX_PAGES)
    parser.add_argument("--max-questions", type=int,
                        default=DEFAULT_MAX_QUESTIONS)
    return parser


def main(argv: Optional[Sequence[str]] = None) -> int:
    args = _parser().parse_args(argv)
    try:
        paketle(args.input, args.output, dpi=args.dpi,
                max_input_mb=args.max_input_mb,
                max_output_mb=args.max_output_mb,
                max_pages=args.max_pages,
                max_questions=args.max_questions,
                emit=_json_olay)
        return 0
    except (PaketlemeHatasi, OSError, ValueError, RuntimeError) as exc:
        _json_olay({"event": "error", "error": str(exc)}, akim=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
