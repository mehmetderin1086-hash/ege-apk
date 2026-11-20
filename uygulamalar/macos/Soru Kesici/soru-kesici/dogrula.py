#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Soru Kesici — otomatik doğrulama / anomali tespit harness'ı.

Kaynağa (soru_kes.py) dokunmadan, bir belgeyi işleyip kutu metriklerini ve
anomalileri (minik/dev parça, sütun-taşma = birleşme, boş kutu, numara
kopukluğu) çıkarır. Ayrıca tüm kırpmaları tek bir "kontakt sayfası" PNG'sine
dizerek görsel incelemeyi ölçeklendirir.

Büyük sınav kitapçıklarında (kapak+yönerge+soru+cevap anahtarı, yüzlerce sayfa)
ilk-N sayfa kapak olur → metrik yanıltıcı. Belge büyükse örnekleme BELGE BOYUNCA
eşit aralıklı yapılır (soru sayfalarını yakalar); küçük belgede ilk-N korunur.

Kullanım:
    python dogrula.py <belge.pdf> [max_sayfa] [--kontakt cikti.png]
    python dogrula.py <belge.pdf> --aralik BAS SON   # belirli sayfa aralığı
    python dogrula.py <belge.pdf> --bas N            # N'den itibaren
    python dogrula.py <belge.pdf> --rapor-yaz tahminler.json
    python dogrula.py --rapor-oku tahminler.json --altin altin.json
JSON metrik satırı basar (Workflow agent'ları bunu okur). ornek_no = işlenen
gerçek sayfa numaraları; soru_sayfa = kutu üreten örnek sayfa sayısı.
"""

import argparse
import collections
import hashlib
import io
import json
import math
import os
import re
import sys
import tempfile
import unicodedata

from PIL import Image

import soru_kes as sk


ALTIN_SEMA_SURUMU_V1 = "soru-kesici.golden/v1"
ALTIN_SEMA_SURUMU_V2 = "soru-kesici.golden/v2"
TAHMIN_SEMA_SURUMU_V1 = "soru-kesici.predictions/v1"
TAHMIN_SEMA_SURUMU_V2 = "soru-kesici.predictions/v2"
KALITE_RAPORU_SURUMU_V1 = "soru-kesici.quality-report/v1"
KALITE_RAPORU_SURUMU_V2 = "soru-kesici.quality-report/v2"

# Kesim SINIRI kalitesi için ikinci (sıkı) eşleştirme eşiği. Varsayılan 0.5
# eşiğinde F1 doygunlaştığı için birkaç yüzde traşlama/taşma görünmez kalır;
# rapor bu eşikte ikinci bir F1 daha taşır (`final_cuts_strict_iou`).
SIKI_IOU_ESIGI = 0.75

# V1 adlari kamuya acik API'dir. Varsayilanlari degistirmek eski rapor
# uretecilerini ve kayitli fixture'lari gereksiz yere kirar; V2 isteyen kod
# yukaridaki acik surum sabitini kullanir.
ALTIN_SEMA_SURUMU = ALTIN_SEMA_SURUMU_V1
TAHMIN_SEMA_SURUMU = TAHMIN_SEMA_SURUMU_V1
KALITE_RAPORU_SURUMU = KALITE_RAPORU_SURUMU_V1

ALTIN_SEMA_SURUMLERI = {ALTIN_SEMA_SURUMU_V1, ALTIN_SEMA_SURUMU_V2}
TAHMIN_SEMA_SURUMLERI = {TAHMIN_SEMA_SURUMU_V1, TAHMIN_SEMA_SURUMU_V2}

SAYFA_ROLLERI = {
    "kapak", "icindekiler", "konu", "soru", "cozum",
    "cevap_anahtari", "karma",
}
TAHMIN_SAYFA_ROLLERI = SAYFA_ROLLERI | {"bilinmiyor"}
SORU_TURLERI = {
    "coktan_secmeli", "acik_uclu", "kisa_cevapli", "dogru_yanlis",
    "eslestirme", "karma", "bilinmiyor",
}

INCELEME_DURUMLARI = {
    "otomatik", "incele", "reddedildi", "bilinmiyor", "onaylandi",
}
SAYFA_INCELEME_DURUMLARI = {
    "temiz", "bekliyor", "incele", "onaylandi", "reddedildi",
    "gerekli_degil", "bilinmiyor",
}
ZORUNLU_BOLGE_TURLERI = {
    "sekil", "tablo", "formul", "metin", "secenek", "yazma_alani",
    "diger",
}
YASAK_BOLGE_TURLERI = {
    "komsu_soru", "baslik", "altbilgi", "cevap", "cozum", "diger",
}
PARCA_TURLERI = {
    "soru_govdesi", "devam", "ortak_uyaran", "sekil", "tablo", "formul",
    "diger",
}


def _ascii_anahtar(deger):
    """Turkce/Unicode etiketleri kararlı, küçük ASCII anahtara cevirir."""
    if not isinstance(deger, str):
        return deger
    metin = deger.strip().casefold().replace("ı", "i")
    metin = "".join(
        harf for harf in unicodedata.normalize("NFKD", metin)
        if not unicodedata.combining(harf))
    metin = re.sub(r"[^a-z0-9]+", "_", metin).strip("_")
    return re.sub(r"_+", "_", metin)


_ROL_ESANLAMLILARI = {
    "kapak": "kapak",
    "icindekiler": "icindekiler",
    "konu": "konu",
    "konu_anlatimi": "konu",
    "soru": "soru",
    "sorular": "soru",
    "cozum": "cozum",
    "cozumler": "cozum",
    "cevap_anahtari": "cevap_anahtari",
    "karma": "karma",
    "karisik": "karma",
    "bilinmiyor": "bilinmiyor",
    "bilinmeyen": "bilinmiyor",
    "unknown": "bilinmiyor",
}

_TUR_ESANLAMLILARI = {
    "coktan_secmeli": "coktan_secmeli",
    "acik_uclu": "acik_uclu",
    "kisa_cevap": "kisa_cevapli",
    "kisa_cevapli": "kisa_cevapli",
    "dogru_yanlis": "dogru_yanlis",
    "eslestirme": "eslestirme",
    "karma": "karma",
    "karisik": "karma",
    "bilinmiyor": "bilinmiyor",
    "bilinmeyen": "bilinmiyor",
    "unknown": "bilinmiyor",
}


def kanonik_sayfa_rolu(deger):
    """Core'un Unicode rollerini kalite şemasının ASCII değerine getirir."""
    return _ROL_ESANLAMLILARI.get(_ascii_anahtar(deger),
                                  _ascii_anahtar(deger))


def kanonik_soru_turu(deger):
    """Core'un Unicode soru turlerini tek ASCII sozluge getirir."""
    return _TUR_ESANLAMLILARI.get(_ascii_anahtar(deger),
                                  _ascii_anahtar(deger))


def _json_oku(yol):
    try:
        with open(yol, "r", encoding="utf-8") as dosya:
            veri = json.load(dosya)
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError(f"JSON raporu okunamadi: {yol}: {exc}") from exc
    if not isinstance(veri, dict):
        raise ValueError("Raporun kok degeri bir JSON nesnesi olmali")
    return veri


def _nesne(deger, yol):
    if not isinstance(deger, dict):
        raise ValueError(f"{yol} bir nesne olmali")
    return deger


def _liste(deger, yol):
    if not isinstance(deger, list):
        raise ValueError(f"{yol} bir liste olmali")
    return deger


def _metin(deger, yol):
    if not isinstance(deger, str) or not deger.strip():
        raise ValueError(f"{yol} bos olmayan bir metin olmali")
    return deger


def _kutu_dogrula(kutu, yol, genislik=None, yukseklik=None):
    _liste(kutu, yol)
    if len(kutu) != 4 or any(
            isinstance(v, bool) or not isinstance(v, (int, float))
            or not math.isfinite(v) for v in kutu):
        raise ValueError(f"{yol} dort sonlu sayidan olusmali")
    x0, y0, x1, y1 = kutu
    if x0 < 0 or y0 < 0 or x1 <= x0 or y1 <= y0:
        raise ValueError(f"{yol} gecerli [x0, y0, x1, y1] olmali")
    if genislik is not None and x1 > genislik + 1e-6:
        raise ValueError(f"{yol} sayfa genisligini asiyor")
    if yukseklik is not None and y1 > yukseklik + 1e-6:
        raise ValueError(f"{yol} sayfa yuksekligini asiyor")


def _olasilik_dogrula(deger, yol, *, gerekli=False):
    if deger is None:
        if gerekli:
            raise ValueError(f"{yol} gerekli")
        return
    if (isinstance(deger, bool) or not isinstance(deger, (int, float))
            or not math.isfinite(deger) or not 0 <= deger <= 1):
        raise ValueError(f"{yol} 0..1 veya null olmali")


def _metin_listesi_dogrula(deger, yol):
    if not isinstance(deger, list) or any(not isinstance(v, str)
                                          for v in deger):
        raise ValueError(f"{yol} metin listesi olmali")


def _bolge_turu(deger, *, yasak=False):
    anahtar = _ascii_anahtar(deger)
    es = {
        "figure": "sekil", "shape": "sekil", "table": "tablo",
        "formula": "formul", "text": "metin", "option": "secenek",
        "writing_area": "yazma_alani", "other": "diger",
        "neighbor": "komsu_soru", "neighbour": "komsu_soru",
        "neighbor_content": "komsu_soru", "komsu_icerik": "komsu_soru",
        "header": "baslik", "footer": "altbilgi", "answer": "cevap",
        "solution": "cozum",
    }
    anahtar = es.get(anahtar, anahtar)
    izinli = YASAK_BOLGE_TURLERI if yasak else ZORUNLU_BOLGE_TURLERI
    return anahtar if anahtar in izinli else anahtar


def _parca_turu(deger):
    anahtar = _ascii_anahtar(deger)
    return {
        "question_body": "soru_govdesi", "body": "soru_govdesi",
        "continuation": "devam", "shared_stimulus": "ortak_uyaran",
        "figure": "sekil", "table": "tablo", "formula": "formul",
        "other": "diger",
    }.get(anahtar, anahtar)


def _bolge_dogrula(bolge, yol, genislik, yukseklik, *,
                    yasak=False, parca=False):
    """V2 bolge/parca kisaltmasini veya metadata nesnesini dogrular."""
    if isinstance(bolge, list):
        _kutu_dogrula(bolge, yol, genislik, yukseklik)
        return
    nesne = _nesne(bolge, yol)
    _kutu_dogrula(nesne.get("box"), f"{yol}.box", genislik, yukseklik)
    if "id" in nesne:
        _metin(nesne["id"], f"{yol}.id")
    if "page" in nesne:
        no = nesne["page"]
        if isinstance(no, bool) or not isinstance(no, int) or no < 1:
            raise ValueError(f"{yol}.page pozitif tam sayi olmali")
    if "kind" in nesne:
        tur = (_parca_turu(nesne["kind"]) if parca
               else _bolge_turu(nesne["kind"], yasak=yasak))
        nesne["kind"] = tur
        if parca and tur not in PARCA_TURLERI:
            raise ValueError(f"{yol}.kind gecersiz: {tur!r}")
        if not parca:
            izinli = YASAK_BOLGE_TURLERI if yasak else ZORUNLU_BOLGE_TURLERI
            if tur not in izinli:
                raise ValueError(f"{yol}.kind gecersiz: {tur!r}")


def _bolge_listesi_dogrula(deger, yol, genislik, yukseklik, *,
                            yasak=False, parca=False):
    _liste(deger, yol)
    for i, bolge in enumerate(deger):
        _bolge_dogrula(bolge, f"{yol}[{i}]", genislik, yukseklik,
                        yasak=yasak, parca=parca)


def _nihai_cikti_dogrula(cikti, yol):
    if cikti is None:
        return
    cikti = _nesne(cikti, yol)
    for alan in ("question_count", "png_count", "metadata_count",
                 "pending_review_count", "part_count", "output_count"):
        if alan not in cikti:
            continue
        deger = cikti[alan]
        if isinstance(deger, bool) or not isinstance(deger, int) or deger < 0:
            raise ValueError(f"{yol}.{alan} negatif olmayan tam sayi olmali")
    for alan in ("blocked", "zip_written", "written", "produced"):
        if alan in cikti and not isinstance(cikti[alan], bool):
            raise ValueError(f"{yol}.{alan} boolean olmali")
    if "quality_mode" in cikti:
        kip = _ascii_anahtar(cikti["quality_mode"])
        if kip not in {"strict", "balanced", "legacy"}:
            raise ValueError(f"{yol}.quality_mode gecersiz: {kip!r}")
        cikti["quality_mode"] = kip
    if "metadata" in cikti and not isinstance(cikti["metadata"], dict):
        raise ValueError(f"{yol}.metadata bir nesne olmali")


def _soru_dogrula(soru, yol, genislik, yukseklik, *, tahmin, v2):
    soru = _nesne(soru, yol)
    _metin(soru.get("id"), f"{yol}.id")
    parcalar = soru.get("parts")
    if "box" in soru:
        _kutu_dogrula(soru["box"], f"{yol}.box", genislik, yukseklik)
    elif not (v2 and isinstance(parcalar, list) and parcalar):
        raise ValueError(f"{yol}.box veya dolu parts gerekli")
    if parcalar is not None:
        _bolge_listesi_dogrula(parcalar, f"{yol}.parts", genislik,
                                yukseklik, parca=True)
    soru_turu = kanonik_soru_turu(soru.get("type"))
    soru["type"] = soru_turu
    if soru_turu not in SORU_TURLERI:
        raise ValueError(f"{yol}.type gecersiz: {soru_turu!r}")
    if "number" in soru and not isinstance(soru["number"], (str, int,
                                                               type(None))):
        raise ValueError(f"{yol}.number metin, tam sayi veya null olmali")
    if v2:
        for alan, yasak in (("required_regions", False),
                            ("forbidden_regions", True)):
            if alan in soru:
                _bolge_listesi_dogrula(
                    soru[alan], f"{yol}.{alan}", genislik, yukseklik,
                    yasak=yasak)
        if "shared_stimulus_id" in soru:
            _metin(soru["shared_stimulus_id"],
                   f"{yol}.shared_stimulus_id")
        if "shared_stimulus" in soru:
            uyaran = soru["shared_stimulus"]
            if isinstance(uyaran, str):
                _metin(uyaran, f"{yol}.shared_stimulus")
            else:
                _bolge_dogrula(uyaran, f"{yol}.shared_stimulus",
                                genislik, yukseklik)
        _nihai_cikti_dogrula(soru.get("final_output"),
                             f"{yol}.final_output")
        _nihai_cikti_dogrula(soru.get("output"), f"{yol}.output")
    if tahmin:
        if "confidence" not in soru:
            raise ValueError(f"{yol}.confidence gerekli")
        _olasilik_dogrula(soru.get("confidence"), f"{yol}.confidence")
        if "status" in soru:
            durum = _ascii_anahtar(soru["status"])
            soru["status"] = durum
            if durum not in INCELEME_DURUMLARI:
                raise ValueError(f"{yol}.status gecersiz: {durum!r}")
        for alan in ("evidence", "warnings", "source_methods",
                     "risk_reasons"):
            if alan in soru:
                _metin_listesi_dogrula(soru[alan], f"{yol}.{alan}")


def _veri_setini_dogrula(veri, *, tahmin):
    """Altin/tahmin JSON belgelerinin V1 veya V2 sozlesmesini dogrular.

    JSON Schema dosyasi araclar ve editorler icindir. Bu elle dogrulama katmani,
    ``jsonschema`` paketi kurulu olmayan yerel kurulumlarda da ayni temel
    garantileri verir.
    """
    surumler = TAHMIN_SEMA_SURUMLERI if tahmin else ALTIN_SEMA_SURUMLERI
    surum = veri.get("schema_version")
    if surum not in surumler:
        raise ValueError(
            f"schema_version {sorted(surumler)!r} icinde olmali; "
            f"alinan: {veri.get('schema_version')!r}")
    v2 = surum in {ALTIN_SEMA_SURUMU_V2, TAHMIN_SEMA_SURUMU_V2}
    if not tahmin:
        veri_seti = _nesne(veri.get("dataset"), "dataset")
        _metin(veri_seti.get("id"), "dataset.id")
        if veri_seti.get("kind") not in {"synthetic", "annotated"}:
            raise ValueError("dataset.kind 'synthetic' veya 'annotated' olmali")
        if not isinstance(veri_seti.get("description"), str):
            raise ValueError("dataset.description bir metin olmali")
    belgeler = _liste(veri.get("documents"), "documents")
    belge_kimlikleri = set()
    for di, ham_belge in enumerate(belgeler):
        belge = _nesne(ham_belge, f"documents[{di}]")
        kimlik = _metin(belge.get("id"), f"documents[{di}].id")
        if kimlik in belge_kimlikleri:
            raise ValueError(f"Yinelenen belge kimligi: {kimlik}")
        belge_kimlikleri.add(kimlik)
        _metin(belge.get("source"), f"documents[{di}].source")
        for hash_alani in ("source_hash", "source_sha256"):
            if hash_alani in belge and not isinstance(belge[hash_alani], str):
                raise ValueError(f"documents[{di}].{hash_alani} metin olmali")
        if v2:
            if tahmin and "final_output" not in belge:
                raise ValueError(
                    f"documents[{di}].final_output V2 tahmininde gerekli")
            _nihai_cikti_dogrula(belge.get("final_output"),
                                 f"documents[{di}].final_output")
        sayfalar = _liste(belge.get("pages"), f"documents[{di}].pages")
        sayfa_nolari = set()
        belge_uyaran_kimlikleri = set()
        uyaran_referanslari = []
        for pi, ham_sayfa in enumerate(sayfalar):
            kok = f"documents[{di}].pages[{pi}]"
            sayfa = _nesne(ham_sayfa, kok)
            no = sayfa.get("page")
            if isinstance(no, bool) or not isinstance(no, int) or no < 1:
                raise ValueError(f"{kok}.page pozitif tam sayi olmali")
            if no in sayfa_nolari:
                raise ValueError(f"{kimlik} icinde yinelenen sayfa: {no}")
            sayfa_nolari.add(no)
            rol = kanonik_sayfa_rolu(sayfa.get("role"))
            sayfa["role"] = rol
            roller = TAHMIN_SAYFA_ROLLERI if tahmin else SAYFA_ROLLERI
            if rol not in roller:
                raise ValueError(f"{kok}.role gecersiz: {rol!r}")
            if tahmin:
                _olasilik_dogrula(sayfa.get("role_confidence"),
                                  f"{kok}.role_confidence")
                duzen = sayfa.get("layout_family")
                if duzen is not None and not isinstance(duzen, str):
                    raise ValueError(f"{kok}.layout_family bir metin olmali")
                if v2 and "review_status" in sayfa:
                    durum = _ascii_anahtar(sayfa["review_status"])
                    sayfa["review_status"] = durum
                    if durum not in SAYFA_INCELEME_DURUMLARI:
                        raise ValueError(
                            f"{kok}.review_status gecersiz: {durum!r}")
                elif v2:
                    raise ValueError(f"{kok}.review_status V2 tahmininde gerekli")
                if "risk_reasons" in sayfa:
                    _metin_listesi_dogrula(
                        sayfa["risk_reasons"], f"{kok}.risk_reasons")
            genislik, yukseklik = sayfa.get("width"), sayfa.get("height")
            for deger, ad in ((genislik, "width"), (yukseklik, "height")):
                if (isinstance(deger, bool)
                        or not isinstance(deger, (int, float))
                        or not math.isfinite(deger) or deger <= 0):
                    raise ValueError(f"{kok}.{ad} pozitif sonlu sayi olmali")
            soru_alanlari = ["questions"]
            if tahmin and v2:
                soru_alanlari = ["raw_proposals", "final_cuts"]
                for gerekli_alan in soru_alanlari:
                    if gerekli_alan not in sayfa:
                        raise ValueError(
                            f"{kok}.{gerekli_alan} V2 tahmininde gerekli")
            for soru_alani in soru_alanlari:
                sorular = _liste(sayfa.get(soru_alani, []),
                                  f"{kok}.{soru_alani}")
                soru_kimlikleri = set()
                for qi, soru in enumerate(sorular):
                    qkok = f"{kok}.{soru_alani}[{qi}]"
                    _soru_dogrula(soru, qkok, genislik, yukseklik,
                                  tahmin=tahmin, v2=v2)
                    if v2 and not tahmin and soru.get("shared_stimulus_id"):
                        uyaran_referanslari.append(
                            (soru["shared_stimulus_id"], qkok))
                    soru_id = soru["id"]
                    if soru_id in soru_kimlikleri:
                        raise ValueError(
                            f"{kimlik} sayfa {no} icinde yinelenen "
                            f"{soru_alani}: {soru_id}")
                    soru_kimlikleri.add(soru_id)
            if v2:
                if "required_regions" in sayfa:
                    _bolge_listesi_dogrula(
                        sayfa["required_regions"], f"{kok}.required_regions",
                        genislik, yukseklik)
                if "forbidden_regions" in sayfa:
                    _bolge_listesi_dogrula(
                        sayfa["forbidden_regions"], f"{kok}.forbidden_regions",
                        genislik, yukseklik, yasak=True)
                if "shared_stimuli" in sayfa:
                    uyaranlar = _liste(sayfa["shared_stimuli"],
                                       f"{kok}.shared_stimuli")
                    uyaran_kimlikleri = set()
                    for ui, uyaran in enumerate(uyaranlar):
                        ukok = f"{kok}.shared_stimuli[{ui}]"
                        uyaran = _nesne(uyaran, ukok)
                        uid = _metin(uyaran.get("id"), f"{ukok}.id")
                        if uid in uyaran_kimlikleri:
                            raise ValueError(f"Yinelenen ortak uyaran: {uid}")
                        if uid in belge_uyaran_kimlikleri:
                            raise ValueError(
                                f"Belgede yinelenen ortak uyaran: {uid}")
                        uyaran_kimlikleri.add(uid)
                        belge_uyaran_kimlikleri.add(uid)
                        if "box" in uyaran:
                            _kutu_dogrula(uyaran["box"], f"{ukok}.box",
                                           genislik, yukseklik)
                        elif "parts" in uyaran:
                            _bolge_listesi_dogrula(
                                uyaran["parts"], f"{ukok}.parts", genislik,
                                yukseklik, parca=True)
                        else:
                            raise ValueError(f"{ukok}.box veya parts gerekli")
            if not tahmin:
                ignore = sayfa.get("ignore_regions", [])
                _liste(ignore, f"{kok}.ignore_regions")
                for ii, kutu in enumerate(ignore):
                    _kutu_dogrula(kutu, f"{kok}.ignore_regions[{ii}]",
                                   genislik, yukseklik)
        for uyaran_id, qkok in uyaran_referanslari:
            if uyaran_id not in belge_uyaran_kimlikleri:
                raise ValueError(
                    f"{qkok}.shared_stimulus_id bulunamadi: {uyaran_id}")
    return veri


def altin_veriyi_yukle(yol):
    """Surümlü altin koordinat dosyasini okuyup dogrular."""
    return _veri_setini_dogrula(_json_oku(yol), tahmin=False)


def tahmin_raporunu_yukle(yol):
    """Surümlü tespit raporunu okuyup dogrular."""
    return _veri_setini_dogrula(_json_oku(yol), tahmin=True)


def _atomik_json_yaz(veri, yol):
    """Hedef raporu atomik yazar; kaynak belgeye hicbir zaman dokunmaz."""
    hedef = os.path.abspath(os.fspath(yol))
    klasor = os.path.dirname(hedef)
    os.makedirs(klasor, exist_ok=True)
    gecici_yol = None
    try:
        with tempfile.NamedTemporaryFile(
                "w", encoding="utf-8", dir=klasor, delete=False,
                prefix=f".{os.path.basename(hedef)}.", suffix=".tmp") as dosya:
            gecici_yol = dosya.name
            json.dump(veri, dosya, ensure_ascii=False, indent=2)
            dosya.write("\n")
        os.replace(gecici_yol, hedef)
    finally:
        if gecici_yol and os.path.exists(gecici_yol):
            os.unlink(gecici_yol)
    return hedef


def rapor_yaz(veri, yol, *, tahmin=True):
    """Doğrulanmis altin/tahmin verisini JSON olarak yazar."""
    _veri_setini_dogrula(veri, tahmin=tahmin)
    return _atomik_json_yaz(veri, yol)


def _alan(kutu):
    return max(0.0, kutu[2] - kutu[0]) * max(0.0, kutu[3] - kutu[1])


def _kesisim_alani(a, b):
    return max(0.0, min(a[2], b[2]) - max(a[0], b[0])) * max(
        0.0, min(a[3], b[3]) - max(a[1], b[1]))


def kutu_iou(a, b):
    kesisim = _kesisim_alani(a, b)
    birlesim = _alan(a) + _alan(b) - kesisim
    return kesisim / birlesim if birlesim > 0 else 0.0


def _kutu_eslestir(altin, tahmin, iou_esigi):
    """Esik uzeri IoU kenarlarinda azami sayida bire-bir eslesme bulur.

    Basit en-yuksek-IoU greedy secimi, tek bir guclu eslesmeyle iki gecerli
    eslesmeyi bloke edebilir. Artiran-yol eslemesi once TP sayisini maksimize
    eder; kenar sirasi ayni sonucu yuksek IoU'ya yonlendirir.
    """
    kenarlar = {gi: [] for gi in range(len(altin))}
    ioular = {}
    for gi, g in enumerate(altin):
        for pi, p in enumerate(tahmin):
            iou = kutu_iou(g["box"], p["box"])
            if iou >= iou_esigi:
                kenarlar[gi].append(pi)
                ioular[(gi, pi)] = iou
    for gi in kenarlar:
        kenarlar[gi].sort(key=lambda pi: (-ioular[(gi, pi)], pi))

    tahminden_altina = {}

    def yerlestir(gi, ziyaret):
        for pi in kenarlar[gi]:
            if pi in ziyaret:
                continue
            ziyaret.add(pi)
            onceki = tahminden_altina.get(pi)
            if onceki is None or yerlestir(onceki, ziyaret):
                tahminden_altina[pi] = gi
                return True
        return False

    # Daha az alternatifi olan altin kutular once yerlestirilir; bu yalniz
    # deterministik bag secimini etkiler, azami kardinaliteyi degistirmez.
    for gi in sorted(kenarlar, key=lambda g: (len(kenarlar[g]), g)):
        yerlestir(gi, set())
    return sorted(
        ((gi, pi, ioular[(gi, pi)]) for pi, gi in tahminden_altina.items()),
        key=lambda e: (e[0], e[1]))


def _oran(pay, payda):
    return pay / payda if payda else 0.0


# --- Kesim SINIRI teşhisi -------------------------------------------------
# `final_cuts_strict_iou.f1` kesim sınırının ne kadar bozuk olduğunu tek bir
# sayıyla söyler ama HANGİ kenarın bozulduğunu söylemez: üstten traş mı
# atılıyor, alta mı taşıyor, sağ sütun sınırını mı aşıyor? Aşağıdaki
# biriktirici ZATEN kurulmuş eşleşme çiftlerini kullanır (yeni eşleştirme
# yok, maliyet ~0) ve dört yönün İŞARETLİ farkını toplar. İşaret teşhisin
# ta kendisidir: medyanı sıfırdan uzak bir yön SİSTEMATİK hata, medyanı
# sıfıra yakın ama p95'i büyük bir yön RASTGELE gürültüdür.
KENAR_YONLERI = ("ust", "alt", "sol", "sag")


def _kenar_biriktirici():
    """Her yön için (işaretli pt farkı, sayfa boyutuna oran %) çiftleri."""
    return {yon: [] for yon in KENAR_YONLERI}


def _kenar_govde_parcasi(nesne):
    """Kenar teşhisine girecek TEK parçayı seçer: soru gövdesi.

    Çok parçalı soruda devam parçası başka sayfada, ortak uyaran ise iki
    soruda aynı kutudur; bunların kenarlarını ana kutunun kenarıyla
    kıyaslamak anlamsız sayılar üretir. Altın tarafta `kind` çoğu zaman
    yoktur (tek kutulu soru) -> ilk geçerli parça gövdedir. Hiçbir parça
    gövde sayılamıyorsa (tüm parçalar devam/ortak uyaran) None döner:
    rastgele bir parçayı gövde saymak sessizce çöp sayı üretirdi.
    """
    parcalar = nesne.get("parts") or []
    for parca in parcalar:
        if parca.get("kind") == "soru_govdesi":
            return parca
    for parca in parcalar:
        if parca.get("kind") not in ("devam", "ortak_uyaran"):
            return parca
    return None


def _kenar_farki_ekle(biriktirici, altin_kutu, tahmin_kutu,
                      genislik, yukseklik):
    """Eşleşen (altın, tahmin) çiftinin dört kenar farkını biriktirir.

    İşaret sözleşmesi (PDF puntosu, y aşağı doğru büyür):
      ust > 0 -> tahmin altından daha AŞAĞIDAN başlıyor  = üstten traş
      alt > 0 -> tahmin altından daha AŞAĞIDA bitiyor    = alta taşma
      sol > 0 -> tahmin altından daha SAĞDAN başlıyor    = soldan traş
      sag > 0 -> tahmin altından daha SAĞDA bitiyor      = sağa taşma
    """
    gx0, gy0, gx1, gy1 = altin_kutu
    px0, py0, px1, py1 = tahmin_kutu
    for yon, fark, olcek in (("ust", py0 - gy0, yukseklik),
                             ("alt", py1 - gy1, yukseklik),
                             ("sol", px0 - gx0, genislik),
                             ("sag", px1 - gx1, genislik)):
        biriktirici[yon].append(
            (float(fark), _oran(float(fark), olcek) * 100.0))


def _medyan(degerler):
    """Boş dizide 0.0; çift sayıda elemanda ortadaki ikinin ortalaması."""
    if not degerler:
        return 0.0
    sirali = sorted(degerler)
    orta = len(sirali) // 2
    if len(sirali) % 2:
        return float(sirali[orta])
    return (float(sirali[orta - 1]) + float(sirali[orta])) / 2.0


def _yuzdelik(degerler, oran):
    """Doğrusal aradeğerlemeli yüzdelik (numpy'sız, girdi sıralanmamış)."""
    if not degerler:
        return 0.0
    sirali = sorted(degerler)
    if len(sirali) == 1:
        return float(sirali[0])
    konum = oran * (len(sirali) - 1)
    alt = int(math.floor(konum))
    ust = min(alt + 1, len(sirali) - 1)
    return float(sirali[alt]
                 + (sirali[ust] - sirali[alt]) * (konum - alt))


def _kenar_yon_ozeti(degerler):
    """Tek yönün pt ve sayfa-oranı (%) istatistikleri; işaret korunur.

    `medyan`/`ortalama` İŞARETLİ (sistematik kaymanın yönü), `p95`/
    `maks_mutlak` ise MUTLAK değer üzerinden (kuyruğun büyüklüğü)
    hesaplanır; ikisi bilinçli olarak farklı sorulara cevap verir.
    """
    pt = [fark for fark, _ in degerler]
    yuzde = [oran for _, oran in degerler]
    return {
        "n": len(pt),
        "medyan": _medyan(pt),
        "p95": _yuzdelik([abs(d) for d in pt], 0.95),
        "ortalama": _oran(sum(pt), len(pt)),
        "maks_mutlak": max((abs(d) for d in pt), default=0.0),
        "medyan_yuzde": _medyan(yuzde),
        "p95_yuzde": _yuzdelik([abs(d) for d in yuzde], 0.95),
        "ortalama_yuzde": _oran(sum(yuzde), len(yuzde)),
        "maks_mutlak_yuzde": max((abs(d) for d in yuzde), default=0.0),
    }


def _kenar_hatalari_ozeti(biriktirici):
    ozet = {"n": len(biriktirici["ust"]), "birim": "pt",
            "oran_birimi": "sayfa_yuzdesi"}
    for yon in KENAR_YONLERI:
        ozet[yon] = _kenar_yon_ozeti(biriktirici[yon])
    return ozet


def _guven_kovasi(guven):
    if guven is None:
        return "bilinmiyor"
    if guven < 0.55:
        return "reddedildi"
    if guven < 0.82:
        return "incele"
    return "otomatik"


def _belgeleri_esle(altin_belgeler, tahmin_belgeler):
    """Once kimlik, yoksa tekil kaynak adi uzerinden tahmin belgesi esler."""
    kimlikle = {b["id"]: b for b in tahmin_belgeler}
    kaynakla = {}
    for belge in tahmin_belgeler:
        kaynakla.setdefault(belge["source"], []).append(belge)
    sonuc = []
    for altin in altin_belgeler:
        tahmin = kimlikle.get(altin["id"])
        if tahmin is None and len(kaynakla.get(altin["source"], [])) == 1:
            tahmin = kaynakla[altin["source"]][0]
        sonuc.append((altin, tahmin))
    return sonuc


def _tahmin_kutularini_olcekle(altin_sayfa, tahmin_sayfa):
    """Tahmin koordinatlarini altin sayfanin koordinat uzayina getirir."""
    sx = altin_sayfa["width"] / tahmin_sayfa["width"]
    sy = altin_sayfa["height"] / tahmin_sayfa["height"]
    sonuc = []
    for soru in tahmin_sayfa["questions"]:
        q = dict(soru)
        x0, y0, x1, y1 = soru["box"]
        q["box"] = [x0 * sx, y0 * sy, x1 * sx, y1 * sy]
        sonuc.append(q)
    return sonuc


def _ignore_icinde(soru, ignore_regions):
    x0, y0, x1, y1 = soru["box"]
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    return any(a <= cx <= c and b <= cy <= d
               for a, b, c, d in ignore_regions)


def _dikdortgen_birlesim_alani(kutular):
    """Cakisan eksen hizali kutularin gercek birlesim alanini hesaplar."""
    kutular = [tuple(k) for k in kutular if _alan(k) > 0]
    if not kutular:
        return 0.0
    xs = sorted({k[0] for k in kutular} | {k[2] for k in kutular})
    toplam = 0.0
    for xa, xb in zip(xs, xs[1:]):
        if xb <= xa:
            continue
        araliklar = sorted((k[1], k[3]) for k in kutular
                           if k[0] < xb and k[2] > xa)
        if not araliklar:
            continue
        ya, yb = araliklar[0]
        uzunluk = 0.0
        for a, b in araliklar[1:]:
            if a <= yb:
                yb = max(yb, b)
            else:
                uzunluk += yb - ya
                ya, yb = a, b
        uzunluk += yb - ya
        toplam += (xb - xa) * uzunluk
    return toplam


def _bolge_kutusu(bolge):
    return bolge if isinstance(bolge, list) else bolge["box"]


def _ham_parcalar(nesne, varsayilan_sayfa):
    parcalar = nesne.get("parts")
    if not parcalar:
        parcalar = [{"box": nesne["box"]}]
    sonuc = []
    for parca in parcalar:
        if isinstance(parca, list):
            sonuc.append({"page": varsayilan_sayfa, "box": list(parca)})
        else:
            sonuc.append({
                "page": parca.get("page", varsayilan_sayfa),
                "box": list(parca["box"]),
                "kind": parca.get("kind"),
            })
    return sonuc


def _olcekli_parcalar(nesne, varsayilan_sayfa, kaynak_sayfalar,
                       hedef_sayfalar=None):
    sonuc = []
    for parca in _ham_parcalar(nesne, varsayilan_sayfa):
        no = parca["page"]
        kutu = parca["box"]
        if hedef_sayfalar is not None and no in hedef_sayfalar:
            kaynak = kaynak_sayfalar.get(no)
            hedef = hedef_sayfalar[no]
            if kaynak is not None:
                sx = hedef["width"] / kaynak["width"]
                sy = hedef["height"] / kaynak["height"]
                kutu = [kutu[0] * sx, kutu[1] * sy,
                        kutu[2] * sx, kutu[3] * sy]
        sonuc.append({"page": no, "box": kutu, "kind": parca.get("kind")})
    return sonuc


def _mantiksal_sorular(belge, alan, *, hedef_belge=None):
    kaynak_sayfalar = {s["page"]: s for s in belge.get("pages", [])}
    hedef_sayfalar = ({s["page"]: s for s in hedef_belge.get("pages", [])}
                       if hedef_belge else None)
    uyaranlar = {}
    for sayfa in belge.get("pages", []):
        for uyaran in sayfa.get("shared_stimuli", []):
            uyaranlar[uyaran["id"]] = (
                sayfa["page"], _ham_parcalar(uyaran, sayfa["page"]))
    sonuc = []
    for sayfa in belge.get("pages", []):
        if alan == "final_cuts":
            ham = (sayfa.get("final_cuts") if "final_cuts" in sayfa
                   else sayfa.get("questions", []))
        else:
            ham = sayfa.get(alan, [])
        for soru in ham:
            q = dict(soru)
            q["owner_page"] = sayfa["page"]
            q["parts"] = _olcekli_parcalar(
                soru, sayfa["page"], kaynak_sayfalar, hedef_sayfalar)
            q["required_regions"] = []
            for bolge in soru.get("required_regions", []):
                q["required_regions"].append({
                    "page": (bolge.get("page", sayfa["page"])
                             if isinstance(bolge, dict) else sayfa["page"]),
                    "box": list(_bolge_kutusu(bolge)),
                    "kind": (bolge.get("kind")
                             if isinstance(bolge, dict) else None),
                })
            q["forbidden_regions"] = []
            for bolge in soru.get("forbidden_regions", []):
                q["forbidden_regions"].append({
                    "page": (bolge.get("page", sayfa["page"])
                             if isinstance(bolge, dict) else sayfa["page"]),
                    "box": list(_bolge_kutusu(bolge)),
                    "kind": (bolge.get("kind")
                             if isinstance(bolge, dict) else None),
                })
            uyaran_id = soru.get("shared_stimulus_id")
            if uyaran_id in uyaranlar:
                _, uyaran_parcalari = uyaranlar[uyaran_id]
                for parca in uyaran_parcalari:
                    q["required_regions"].append({
                        "page": parca["page"], "box": list(parca["box"]),
                        "kind": "ortak_uyaran",
                    })
            inline = soru.get("shared_stimulus")
            if isinstance(inline, dict):
                q["required_regions"].append({
                    "page": inline.get("page", sayfa["page"]),
                    "box": list(inline["box"]), "kind": "ortak_uyaran",
                })
            sonuc.append(q)
    return sonuc


def _sayfa_bolgeleri(belge, alan):
    sonuc = []
    for sayfa in belge.get("pages", []):
        for bolge in sayfa.get(alan, []):
            sonuc.append({
                "page": (bolge.get("page", sayfa["page"])
                         if isinstance(bolge, dict) else sayfa["page"]),
                "box": list(_bolge_kutusu(bolge)),
                "kind": bolge.get("kind") if isinstance(bolge, dict) else None,
            })
    return sonuc


def _mantiksal_ignore_icinde(soru, altin_belge):
    ignore = {s["page"]: s.get("ignore_regions", [])
              for s in altin_belge.get("pages", [])}
    if not soru.get("parts"):
        return False
    isaretler = []
    for parca in soru["parts"]:
        x0, y0, x1, y1 = parca["box"]
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        isaretler.append(any(a <= cx <= c and b <= cy <= d
                             for a, b, c, d in ignore.get(parca["page"], [])))
    return bool(isaretler) and all(isaretler)


def _parca_alanlari(parcalar):
    sayfalar = {}
    for parca in parcalar:
        sayfalar.setdefault(parca["page"], []).append(parca["box"])
    return sum(_dikdortgen_birlesim_alani(kutular)
               for kutular in sayfalar.values())


def _parcali_kesisim(a, b):
    kesisimler = {}
    for pa in a["parts"]:
        for pb in b["parts"]:
            if pa["page"] != pb["page"]:
                continue
            ax0, ay0, ax1, ay1 = pa["box"]
            bx0, by0, bx1, by1 = pb["box"]
            kutu = [max(ax0, bx0), max(ay0, by0),
                    min(ax1, bx1), min(ay1, by1)]
            if _alan(kutu) > 0:
                kesisimler.setdefault(pa["page"], []).append(kutu)
    return sum(_dikdortgen_birlesim_alani(kutular)
               for kutular in kesisimler.values())


def _parcali_iou(a, b):
    kesisim = _parcali_kesisim(a, b)
    birlesim = _parca_alanlari(a["parts"]) + _parca_alanlari(b["parts"]) \
        - kesisim
    return _oran(kesisim, birlesim)


def _benzerlik_eslestir(altin, tahmin, esik):
    kenarlar = {gi: [] for gi in range(len(altin))}
    skorlar = {}
    for gi, g in enumerate(altin):
        for pi, p in enumerate(tahmin):
            skor = _parcali_iou(g, p)
            if skor >= esik:
                kenarlar[gi].append(pi)
                skorlar[(gi, pi)] = skor
    for gi in kenarlar:
        kenarlar[gi].sort(key=lambda pi: (-skorlar[(gi, pi)], pi))
    tahminden_altina = {}

    def yerlestir(gi, ziyaret):
        for pi in kenarlar[gi]:
            if pi in ziyaret:
                continue
            ziyaret.add(pi)
            onceki = tahminden_altina.get(pi)
            if onceki is None or yerlestir(onceki, ziyaret):
                tahminden_altina[pi] = gi
                return True
        return False

    for gi in sorted(kenarlar, key=lambda g: (len(kenarlar[g]), g)):
        yerlestir(gi, set())
    return sorted(
        ((gi, pi, skorlar[(gi, pi)]) for pi, gi in tahminden_altina.items()),
        key=lambda e: (e[0], e[1]))


def _parcali_metrikler(altin, tahmin, iou_esigi, bolunme_esigi):
    eslesmeler = _benzerlik_eslestir(altin, tahmin, iou_esigi)
    eslesen_p = {pi for _, pi, _ in eslesmeler}
    ioular = [iou for _, _, iou in eslesmeler]

    def ayirici(nesne):
        # Ortak uyaranin birden cok dogru kesimde yinelenmesi split/merge
        # degildir. Proxy yalniz soruya ozgu govde/devam parcalarini kullanir.
        govde = [p for p in nesne["parts"]
                 if p.get("kind") != "ortak_uyaran"]
        return {**nesne, "parts": govde or nesne["parts"]}

    bolunme = 0
    for g in altin:
        gg = ayirici(g)
        g_alani = _parca_alanlari(gg["parts"])
        adet = sum(_oran(_parcali_kesisim(gg, ayirici(p)), g_alani)
                    >= bolunme_esigi for p in tahmin)
        bolunme += int(adet >= 2)
    birlesme = 0
    for p in tahmin:
        pp = ayirici(p)
        adet = sum(_oran(_parcali_kesisim(ayirici(g), pp),
                         _parca_alanlari(ayirici(g)["parts"]))
                    >= bolunme_esigi
                    for g in altin)
        birlesme += int(adet >= 2)
    tp = len(eslesmeler)
    fp = len(tahmin) - tp
    fn = len(altin) - tp
    kesinlik = _oran(tp, tp + fp)
    geri_cagirma = _oran(tp, tp + fn)
    return ({
        "true_positive": tp,
        "false_positive": fp,
        "false_negative": fn,
        "precision": kesinlik,
        "recall": geri_cagirma,
        "f1": _oran(2 * kesinlik * geri_cagirma,
                    kesinlik + geri_cagirma),
        "mean_matched_iou": _oran(sum(ioular), len(ioular)),
    }, eslesmeler, eslesen_p, bolunme, birlesme)


def _bolge_kapsama_orani(bolge, parcalar):
    kesilen = []
    bx0, by0, bx1, by1 = bolge["box"]
    for parca in parcalar:
        if parca["page"] != bolge["page"]:
            continue
        px0, py0, px1, py1 = parca["box"]
        kutu = [max(bx0, px0), max(by0, py0),
                min(bx1, px1), min(by1, py1)]
        if _alan(kutu) > 0:
            kesilen.append(kutu)
    return _oran(_dikdortgen_birlesim_alani(kesilen), _alan(bolge["box"]))


def _guven_kalibrasyonu(ornekler, kova_sayisi=10):
    kovalar = []
    toplam = len(ornekler)
    ece = mce = 0.0
    for i in range(kova_sayisi):
        alt = i / kova_sayisi
        ust = (i + 1) / kova_sayisi
        kova = [(g, y) for g, y in ornekler
                if alt <= g <= ust and (i == kova_sayisi - 1 or g < ust)]
        ort_guven = _oran(sum(g for g, _ in kova), len(kova))
        dogruluk = _oran(sum(y for _, y in kova), len(kova))
        hata = abs(ort_guven - dogruluk) if kova else 0.0
        ece += _oran(len(kova), toplam) * hata
        mce = max(mce, hata)
        kovalar.append({
            "lower": alt, "upper": ust, "count": len(kova),
            "mean_confidence": ort_guven, "accuracy": dogruluk,
            "calibration_error": hata,
        })
    return {
        "count": toplam, "bin_count": kova_sayisi,
        "expected_calibration_error": ece, "ece": ece,
        "maximum_calibration_error": mce, "bins": kovalar,
    }


def _derin_alt_kume(beklenen, gercek):
    if isinstance(beklenen, dict):
        return isinstance(gercek, dict) and all(
            k in gercek and _derin_alt_kume(v, gercek[k])
            for k, v in beklenen.items())
    return beklenen == gercek


def _rapor_topla(raporlar):
    tp = sum(r["true_positive"] for r in raporlar)
    fp = sum(r["false_positive"] for r in raporlar)
    fn = sum(r["false_negative"] for r in raporlar)
    kesinlik = _oran(tp, tp + fp)
    geri = _oran(tp, tp + fn)
    iou_pay = sum(r["mean_matched_iou"] * r["true_positive"]
                  for r in raporlar)
    return {
        "true_positive": tp, "false_positive": fp, "false_negative": fn,
        "precision": kesinlik, "recall": geri,
        "f1": _oran(2 * kesinlik * geri, kesinlik + geri),
        "mean_matched_iou": _oran(iou_pay, tp),
    }


def _kalite_degerlendir_v2(altin, tahmin, iou_esigi, bolunme_esigi):
    """Mantiksal nihai kesimleri ve ham teklifleri birbirinden ayri olcer."""
    belge_eslesmeleri = _belgeleri_esle(altin["documents"],
                                        tahmin["documents"])
    eslesen_tahminler = {id(p) for _, p in belge_eslesmeleri if p is not None}
    final_raporlar = []
    siki_raporlar = []
    ham_raporlar = []
    belge_sonuclari = []
    toplam_bolunme = toplam_birlesme = 0
    ham_bolunme = ham_birlesme = 0
    tip_toplam = tip_dogru = 0
    guven_ornekleri = []
    guven = {ad: {"count": 0, "true_positive": 0, "false_positive": 0}
             for ad in ("reddedildi", "incele", "otomatik", "bilinmiyor")}
    gerekli_sayisi = gerekli_tam = 0
    gerekli_oran_toplam = gerekli_alan = gerekli_kapsanan_alan = 0.0
    yasak_sayisi = yasak_sizan = 0
    yasak_alan = yasak_sizan_alan = 0.0
    meta = {"matched": 0, "number_expected": 0, "number_correct": 0,
            "part_count_expected": 0, "part_count_correct": 0,
            "metadata_expected": 0, "metadata_correct": 0}
    rol_toplam = rol_dogru = 0
    rol_sayimlari = {rol: {"gold": 0, "predicted": 0, "true_positive": 0}
                     for rol in sorted(SAYFA_ROLLERI)}
    rol_karisiklik = {}
    sayfa_rolune_gore_fp = {rol: 0 for rol in sorted(SAYFA_ROLLERI)}
    dislanan_sayfa = dislanan_fp_sayfa = 0
    altinsiz_tahmin_kutusu = 0
    ignore_edilen_tahmin = 0
    butun_final_kesimler = []
    kenar_biriktirici = _kenar_biriktirici()

    def bolge_say(bolge, parcalar, *, yasak=False):
        nonlocal gerekli_sayisi, gerekli_tam, gerekli_oran_toplam
        nonlocal gerekli_alan, gerekli_kapsanan_alan
        nonlocal yasak_sayisi, yasak_sizan, yasak_alan, yasak_sizan_alan
        oran = _bolge_kapsama_orani(bolge, parcalar)
        alan = _alan(bolge["box"])
        if yasak:
            yasak_sayisi += 1
            yasak_alan += alan
            yasak_sizan_alan += alan * oran
            yasak_sizan += int(oran > 1e-9)
        else:
            gerekli_sayisi += 1
            gerekli_oran_toplam += oran
            gerekli_alan += alan
            gerekli_kapsanan_alan += alan * oran
            gerekli_tam += int(oran >= 0.999)

    for altin_belge, tahmin_belge in belge_eslesmeleri:
        altin_sorular = _mantiksal_sorular(altin_belge, "questions")
        final = (_mantiksal_sorular(
            tahmin_belge, "final_cuts", hedef_belge=altin_belge)
                 if tahmin_belge else [])
        ham = (_mantiksal_sorular(
            tahmin_belge, "raw_proposals", hedef_belge=altin_belge)
               if tahmin_belge else [])
        final_once = len(final)
        final = [p for p in final
                 if not _mantiksal_ignore_icinde(p, altin_belge)]
        ham = [p for p in ham
               if not _mantiksal_ignore_icinde(p, altin_belge)]
        ignore_edilen_tahmin += final_once - len(final)
        # Ham ve nihai ayni adayi temsil edebilir; kamu metriği nihai cikti
        # uzerinden sayilir, hamdaki ek sayi yalniz kendi bolumune yansir.
        butun_final_kesimler.extend(final)
        final_rapor, eslesmeler, eslesen_p, bolunme, birlesme = \
            _parcali_metrikler(altin_sorular, final, iou_esigi,
                               bolunme_esigi)
        ham_rapor, _, _, hbol, hbir = _parcali_metrikler(
            altin_sorular, ham, iou_esigi, bolunme_esigi)
        # SIKI eşik: IoU 0.5'te F1 doygunlaştığı için kesim SINIRI kalitesi
        # (traşlama/taşma) görünmez olur. Aynı eşleştirme 0.75'te tekrarlanır;
        # kutu sınırı iyileştirmelerinin tek gerçek kanıtı budur.
        siki_rapor, _, _, _, _ = _parcali_metrikler(
            altin_sorular, final, SIKI_IOU_ESIGI, bolunme_esigi)
        final_raporlar.append(final_rapor)
        siki_raporlar.append(siki_rapor)
        ham_raporlar.append(ham_rapor)
        toplam_bolunme += bolunme
        toplam_birlesme += birlesme
        ham_bolunme += hbol
        ham_birlesme += hbir

        eslesme_haritasi = {gi: pi for gi, pi, _ in eslesmeler}
        altin_sayfa_boyutu = {s["page"]: (s["width"], s["height"])
                              for s in altin_belge.get("pages", [])}
        for gi, g in enumerate(altin_sorular):
            p = final[eslesme_haritasi[gi]] if gi in eslesme_haritasi else None
            parcalar = p["parts"] if p else []
            for bolge in g.get("required_regions", []):
                bolge_say(bolge, parcalar)
            for bolge in g.get("forbidden_regions", []):
                bolge_say(bolge, parcalar, yasak=True)
            if p is None:
                continue
            meta["matched"] += 1
            # Kenar teşhisi aynı eşleşmeden beslenir; yalnızca soru gövdesi
            # parçaları ve yalnızca AYNI sayfadaki çift karşılaştırılır
            # (farklı sayfadaki devam parçası kenar farkı üretmez).
            altin_govde = _kenar_govde_parcasi(g)
            tahmin_govde = _kenar_govde_parcasi(p)
            # Sayfa boyutu bilinmeyen çift TAMAMEN atlanır: şema parça
            # `page` alanının belgede var olmasını zorlamıyor, boyutu 0
            # varsayıp devam etmek pt farkını kaydedip yüzdesini sessizce
            # 0 yazardı ve yüzde medyanını sıfıra doğru çekerdi.
            if (altin_govde and tahmin_govde
                    and altin_govde["page"] == tahmin_govde["page"]
                    and altin_govde["page"] in altin_sayfa_boyutu):
                gen, yuk = altin_sayfa_boyutu[altin_govde["page"]]
                _kenar_farki_ekle(kenar_biriktirici, altin_govde["box"],
                                  tahmin_govde["box"], gen, yuk)
            if g.get("type") != "bilinmiyor":
                tip_toplam += 1
                tip_dogru += int(g.get("type") == p.get("type"))
            beklenen = g.get("final_output") or {}
            gercek = p.get("final_output") or p.get("output") or {}
            bek_no = beklenen.get("question_number", g.get("number"))
            ger_no = gercek.get("question_number", p.get("number"))
            if bek_no is not None:
                meta["number_expected"] += 1
                meta["number_correct"] += int(str(bek_no) == str(ger_no))
            bek_parca = beklenen.get("part_count")
            if bek_parca is None and g.get("parts"):
                bek_parca = len(g["parts"])
            if bek_parca is not None:
                meta["part_count_expected"] += 1
                meta["part_count_correct"] += int(
                    int(bek_parca) == len(p["parts"]))
            bek_meta = beklenen.get("metadata")
            if bek_meta is not None:
                meta["metadata_expected"] += 1
                meta["metadata_correct"] += int(
                    _derin_alt_kume(bek_meta, gercek.get("metadata", {})))

        for pi, p in enumerate(final):
            guven_degeri = p.get("confidence")
            kova = _guven_kovasi(guven_degeri)
            guven[kova]["count"] += 1
            dogru = int(pi in eslesen_p)
            guven[kova]["true_positive" if dogru else "false_positive"] += 1
            if guven_degeri is not None:
                guven_ornekleri.append((float(guven_degeri), dogru))

        tum_parcalar = [parca for p in final for parca in p["parts"]]
        for bolge in _sayfa_bolgeleri(altin_belge, "required_regions"):
            bolge_say(bolge, tum_parcalar)
        for bolge in _sayfa_bolgeleri(altin_belge, "forbidden_regions"):
            bolge_say(bolge, tum_parcalar, yasak=True)

        tahmin_sayfalar = ({s["page"]: s for s in tahmin_belge["pages"]}
                           if tahmin_belge else {})
        eslesen_owner = {final[pi]["owner_page"] for _, pi, _ in eslesmeler}
        for sayfa in altin_belge["pages"]:
            alt_rol = sayfa["role"]
            tah_sayfa = tahmin_sayfalar.get(sayfa["page"])
            tah_rol = tah_sayfa["role"] if tah_sayfa else "bilinmiyor"
            rol_toplam += 1
            rol_sayimlari[alt_rol]["gold"] += 1
            if tah_rol in rol_sayimlari:
                rol_sayimlari[tah_rol]["predicted"] += 1
            rol_karisiklik.setdefault(alt_rol, {}).setdefault(tah_rol, 0)
            rol_karisiklik[alt_rol][tah_rol] += 1
            if alt_rol == tah_rol:
                rol_dogru += 1
                rol_sayimlari[alt_rol]["true_positive"] += 1
            sayfa_final = [p for p in final if p["owner_page"] == sayfa["page"]]
            sayfa_eslesen = sum(p["owner_page"] == sayfa["page"]
                                for _, pidx, _ in eslesmeler
                                for p in [final[pidx]])
            sayfa_fp = len(sayfa_final) - sayfa_eslesen
            sayfa_rolune_gore_fp[alt_rol] += sayfa_fp
            if alt_rol not in {"soru", "karma"}:
                dislanan_sayfa += 1
                if sayfa_final:
                    dislanan_fp_sayfa += 1

        belge_sonuclari.append({
            "id": altin_belge["id"],
            **final_rapor,
            "raw_proposals": ham_rapor,
        })

    for fazla in tahmin["documents"]:
        if id(fazla) in eslesen_tahminler:
            continue
        final = _mantiksal_sorular(fazla, "final_cuts")
        ham = _mantiksal_sorular(fazla, "raw_proposals")
        butun_final_kesimler.extend(final)
        fr = {"true_positive": 0, "false_positive": len(final),
              "false_negative": 0, "precision": 0.0, "recall": 0.0,
              "f1": 0.0, "mean_matched_iou": 0.0}
        hr = {"true_positive": 0, "false_positive": len(ham),
              "false_negative": 0, "precision": 0.0, "recall": 0.0,
              "f1": 0.0, "mean_matched_iou": 0.0}
        final_raporlar.append(fr)
        ham_raporlar.append(hr)
        altinsiz_tahmin_kutusu += len(final)
        for p in final:
            kova = _guven_kovasi(p.get("confidence"))
            guven[kova]["count"] += 1
            guven[kova]["false_positive"] += 1
            if p.get("confidence") is not None:
                guven_ornekleri.append((float(p["confidence"]), 0))
        belge_sonuclari.append({"id": fazla["id"], "gold_missing": True,
                                **fr, "raw_proposals": hr})

    for sayim in rol_sayimlari.values():
        sayim["precision"] = _oran(sayim["true_positive"],
                                   sayim["predicted"])
        sayim["recall"] = _oran(sayim["true_positive"], sayim["gold"])
    for sayim in guven.values():
        sayim["precision"] = _oran(sayim["true_positive"], sayim["count"])

    final_toplam = _rapor_topla(final_raporlar)
    siki_toplam = _rapor_topla(siki_raporlar)
    ham_toplam = _rapor_topla(ham_raporlar)
    toplam_altin = final_toplam["true_positive"] + final_toplam["false_negative"]
    final_tahmin = final_toplam["true_positive"] + final_toplam["false_positive"]
    ham_altin = ham_toplam["true_positive"] + ham_toplam["false_negative"]
    ham_tahmin = ham_toplam["true_positive"] + ham_toplam["false_positive"]

    bekleyen_sayfalar = bekleyen_adaylar = finalde_bekleyen = 0
    raporlanan_bekleyen = 0
    cikti_kayitlari = []
    kalite_kipleri = []
    belge_kapi_sonuclari = []
    sayilar_tutarli = True
    strict_ihlaller = []
    for belge in tahmin["documents"]:
        cikti = belge.get("final_output") or {}
        cikti_kayitlari.append(cikti)
        kip = _ascii_anahtar(cikti.get(
            "quality_mode", tahmin.get("quality_mode",
            tahmin.get("generator", {}).get("quality_mode", "strict"))))
        kalite_kipleri.append(kip)
        raporlanan = int(cikti.get("pending_review_count", 0))
        raporlanan_bekleyen += raporlanan
        belge_bekleyen_sayfa = belge_bekleyen_aday = belge_final_bekleyen = 0
        for sayfa in belge.get("pages", []):
            hamlar = sayfa.get("raw_proposals", [])
            kesimler = (sayfa.get("final_cuts") if "final_cuts" in sayfa
                        else sayfa.get("questions", []))
            aday_bekliyor = any(a.get("status") == "incele" for a in hamlar)
            final_bekliyor = any(k.get("status") == "incele"
                                 for k in kesimler)
            durum_bekliyor = sayfa.get("review_status", "temiz") in {
                "bekliyor", "incele"}
            belge_bekleyen_sayfa += int(
                durum_bekliyor or aday_bekliyor or final_bekliyor)
            belge_bekleyen_aday += sum(a.get("status") == "incele"
                                       for a in hamlar)
            belge_final_bekleyen += sum(k.get("status") == "incele"
                                        for k in kesimler)
        bekleyen_sayfalar += belge_bekleyen_sayfa
        bekleyen_adaylar += belge_bekleyen_aday
        finalde_bekleyen += belge_final_bekleyen
        adet = len(_mantiksal_sorular(belge, "final_cuts"))
        belge_sayilari_tutarli = all(
            alan not in cikti or cikti[alan] == adet
            for alan in ("question_count", "png_count", "metadata_count"))
        sayilar_tutarli &= belge_sayilari_tutarli
        belge_yazilan = bool(adet) or bool(
            cikti.get("written") or cikti.get("zip_written"))
        belge_bekleyen = max(raporlanan, belge_bekleyen_sayfa)
        belge_bloklandi = (belge_bekleyen == 0 or (
            not belge_yazilan and bool(cikti.get("blocked", False))))
        belge_kapi_sonuclari.append({
            "id": belge["id"], "quality_mode": kip,
            "pending_review_count": belge_bekleyen,
            "pending_review_pages": belge_bekleyen_sayfa,
            "blocked_as_required": belge_bloklandi,
            "counts_consistent": belge_sayilari_tutarli,
        })
        if kip == "strict" and belge_bekleyen and not belge_bloklandi:
            strict_ihlaller.append(
                "bekleyen_incelemeye_ragmen_cikti_yazildi")
        if kip == "strict" and belge_final_bekleyen:
            strict_ihlaller.append("incele_durumlu_kesim_nihai_ciktida")
    bekleyen = max(raporlanan_bekleyen, bekleyen_sayfalar)
    strict = all(k == "strict" for k in kalite_kipleri)
    yazilan = bool(butun_final_kesimler) or any(
        c.get("written") or c.get("zip_written") for c in cikti_kayitlari)
    bekleyen_belgeler = [s for s in belge_kapi_sonuclari
                         if s["pending_review_count"]]
    raporlanan_blok = bool(bekleyen_belgeler) and all(
        s["blocked_as_required"] for s in bekleyen_belgeler)
    beklerken_bloklandi = all(s["blocked_as_required"]
                              for s in belge_kapi_sonuclari)
    if not sayilar_tutarli:
        strict_ihlaller.append("png_soru_metadata_sayilari_tutarsiz")
    strict_ihlaller = list(dict.fromkeys(strict_ihlaller))

    beklenen_cikti_sayilari = {"question_count": 0, "png_count": 0,
                               "metadata_count": 0}
    for belge in altin["documents"]:
        cikti = belge.get("final_output") or {}
        soru_adedi = len(_mantiksal_sorular(belge, "questions"))
        for alan in beklenen_cikti_sayilari:
            beklenen_cikti_sayilari[alan] += int(cikti.get(alan, soru_adedi))
    raporlanan_cikti_sayilari = {"question_count": 0, "png_count": 0,
                                 "metadata_count": 0}
    for belge in tahmin["documents"]:
        cikti = belge.get("final_output") or {}
        kesim_adedi = len(_mantiksal_sorular(belge, "final_cuts"))
        for alan in raporlanan_cikti_sayilari:
            raporlanan_cikti_sayilari[alan] += int(cikti.get(alan,
                                                                  kesim_adedi))
    meta.update({
        "number_accuracy": _oran(meta["number_correct"],
                                 meta["number_expected"]),
        "part_count_accuracy": _oran(meta["part_count_correct"],
                                     meta["part_count_expected"]),
        "metadata_accuracy": _oran(meta["metadata_correct"],
                                   meta["metadata_expected"]),
        "expected_question_count": beklenen_cikti_sayilari["question_count"],
        "actual_question_count": final_tahmin,
        "reported_question_count": raporlanan_cikti_sayilari["question_count"],
        "question_count_matches": (
            beklenen_cikti_sayilari["question_count"] == final_tahmin
            == raporlanan_cikti_sayilari["question_count"]),
        "expected_png_count": beklenen_cikti_sayilari["png_count"],
        "reported_png_count": raporlanan_cikti_sayilari["png_count"],
        "png_count_matches": (beklenen_cikti_sayilari["png_count"]
                              == raporlanan_cikti_sayilari["png_count"]
                              == final_tahmin),
        "expected_metadata_count": beklenen_cikti_sayilari["metadata_count"],
        "reported_metadata_count": raporlanan_cikti_sayilari["metadata_count"],
        "metadata_count_matches": (
            beklenen_cikti_sayilari["metadata_count"]
            == raporlanan_cikti_sayilari["metadata_count"]
            == final_tahmin),
    })
    strict_rapor = {
        "quality_mode": "strict" if strict else "mixed",
        "pending_review_count": bekleyen,
        "reported_pending_review_count": raporlanan_bekleyen,
        "pending_review_pages": bekleyen_sayfalar,
        "pending_review_items": bekleyen_adaylar,
        "review_items_in_final_output": finalde_bekleyen,
        "output_written": yazilan,
        "reported_blocked": raporlanan_blok,
        "blocked_as_required": beklerken_bloklandi,
        "counts_consistent": sayilar_tutarli,
        "violations": strict_ihlaller,
        "passes": not strict_ihlaller,
        "pass": not strict_ihlaller,
        "documents": belge_kapi_sonuclari,
    }
    gerekli_rapor = {
        "count": gerekli_sayisi, "fully_covered": gerekli_tam,
        "missed": gerekli_sayisi - gerekli_tam,
        "mean_coverage": _oran(gerekli_oran_toplam, gerekli_sayisi),
        "area_coverage": _oran(gerekli_kapsanan_alan, gerekli_alan),
    }
    final_kesim_alani = sum(_parca_alanlari(p["parts"])
                             for p in butun_final_kesimler)
    yasak_rapor = {
        "count": yasak_sayisi, "regions_with_leakage": yasak_sizan,
        "clean": yasak_sayisi - yasak_sizan,
        "leakage_rate": _oran(yasak_sizan_alan, yasak_alan),
        "cut_area_leakage_rate": _oran(yasak_sizan_alan, final_kesim_alani),
        "leaked_area": yasak_sizan_alan,
    }
    kalibrasyon_raporu = _guven_kalibrasyonu(guven_ornekleri)

    return {
        "schema_version": KALITE_RAPORU_SURUMU_V2,
        "evaluation_target": "final_cuts",
        "thresholds": {"iou": iou_esigi,
                       "strict_iou": SIKI_IOU_ESIGI,
                       "split_merge_overlap": bolunme_esigi,
                       "required_region_coverage": 0.999,
                       "review": 0.55, "automatic": 0.82,
                       "ece_bins": 10},
        "page_role": {
            "total": rol_toplam, "correct": rol_dogru,
            "accuracy": _oran(rol_dogru, rol_toplam),
            "per_role": rol_sayimlari, "confusion": rol_karisiklik,
        },
        "question_boxes": final_toplam,
        "final_cuts": dict(final_toplam),
        # Kesim sınırı kalitesi: aynı kesimler sıkı IoU eşiğinde.
        "final_cuts_strict_iou": {**siki_toplam,
                                  "iou": SIKI_IOU_ESIGI},
        # Sıkı IoU'nun tek sayısını dört yönlü teşhise çevirir: hangi kenar,
        # ne kadar, hangi işaretle kayıyor.
        "kenar_hatalari": _kenar_hatalari_ozeti(kenar_biriktirici),
        "raw_proposals": {**ham_toplam,
                          "split_count": ham_bolunme,
                          "merge_count": ham_birlesme},
        "question_type": {
            "matched_with_known_gold_type": tip_toplam,
            "correct": tip_dogru, "accuracy": _oran(tip_dogru, tip_toplam),
        },
        "split_merge_proxy": {
            "split_count": toplam_bolunme,
            "merge_count": toplam_birlesme,
            "split_rate": _oran(toplam_bolunme, toplam_altin),
            "merge_rate": _oran(toplam_birlesme, final_tahmin),
        },
        "regions": {"required": gerekli_rapor, "forbidden": yasak_rapor},
        "required_regions": dict(gerekli_rapor),
        "forbidden_regions": dict(yasak_rapor),
        "confidence_calibration": kalibrasyon_raporu,
        "confidence_ece": kalibrasyon_raporu["ece"],
        "confidence_buckets": guven,
        "strict_output": strict_rapor,
        "strict_output_pending_review": dict(strict_rapor),
        "final_output_metadata": meta,
        "false_positives": {
            "total_boxes": final_toplam["false_positive"],
            "by_gold_page_role": sayfa_rolune_gore_fp,
            "excluded_pages": dislanan_sayfa,
            "excluded_pages_with_predictions": dislanan_fp_sayfa,
            "excluded_page_rate": _oran(dislanan_fp_sayfa, dislanan_sayfa),
            "unmatched_page_or_document_boxes": altinsiz_tahmin_kutusu,
            "ignored_region_predictions": ignore_edilen_tahmin,
        },
        "documents": belge_sonuclari,
    }


def kalite_degerlendir(altin, tahmin, *, iou_esigi=0.5,
                       bolunme_ortusme_esigi=0.2):
    """Sayfa rolu ve soru kutularini tekil, deterministik eslesmeyle olcer.

    ``bolunme`` bir altin kutuyu birden cok tahminin; ``birlesme`` ise tek bir
    tahmin kutusunun birden cok altin soruyu anlamli miktarda kaplamasidir.
    Bunlar kesin hata sinifi degil, elle inceleme icin guvenilir proxy'lerdir.
    """
    _veri_setini_dogrula(altin, tahmin=False)
    _veri_setini_dogrula(tahmin, tahmin=True)
    if not 0 < iou_esigi <= 1:
        raise ValueError("iou_esigi 0 ile 1 arasinda olmali")
    if not 0 < bolunme_ortusme_esigi <= 1:
        raise ValueError("bolunme_ortusme_esigi 0 ile 1 arasinda olmali")
    if (altin.get("schema_version") == ALTIN_SEMA_SURUMU_V2
            or tahmin.get("schema_version") == TAHMIN_SEMA_SURUMU_V2):
        return _kalite_degerlendir_v2(
            altin, tahmin, iou_esigi, bolunme_ortusme_esigi)

    rol_toplam = rol_dogru = 0
    rol_sayimlari = {
        rol: {"gold": 0, "predicted": 0, "true_positive": 0}
        for rol in sorted(SAYFA_ROLLERI)
    }
    rol_karisiklik = {}
    tp = fp = fn = 0
    ioular = []
    bolunme = birlesme = 0
    tip_toplam = tip_dogru = 0
    dislanan_sayfa = dislanan_fp_sayfa = 0
    sayfa_rolune_gore_fp = {rol: 0 for rol in sorted(SAYFA_ROLLERI)}
    ignore_edilen_tahmin = 0
    altinsiz_tahmin_kutusu = 0
    kenar_biriktirici = _kenar_biriktirici()
    guven = {
        ad: {"count": 0, "true_positive": 0, "false_positive": 0}
        for ad in ("reddedildi", "incele", "otomatik", "bilinmiyor")
    }
    belge_sonuclari = []

    belge_eslesmeleri = _belgeleri_esle(
        altin["documents"], tahmin["documents"])
    eslesen_tahmin_nesneleri = {
        id(tahmin_belge) for _, tahmin_belge in belge_eslesmeleri
        if tahmin_belge is not None
    }
    for altin_belge, tahmin_belge in belge_eslesmeleri:
        tahmin_sayfalar = ({s["page"]: s for s in tahmin_belge["pages"]}
                           if tahmin_belge else {})
        belge_tp = belge_fp = belge_fn = 0
        for altin_sayfa in altin_belge["pages"]:
            tahmin_sayfa = tahmin_sayfalar.get(altin_sayfa["page"])
            tahmin_rolu = (tahmin_sayfa["role"]
                           if tahmin_sayfa else "bilinmiyor")
            altin_rolu = altin_sayfa["role"]
            rol_toplam += 1
            rol_sayimlari[altin_rolu]["gold"] += 1
            if tahmin_rolu in rol_sayimlari:
                rol_sayimlari[tahmin_rolu]["predicted"] += 1
            rol_karisiklik.setdefault(altin_rolu, {}).setdefault(tahmin_rolu, 0)
            rol_karisiklik[altin_rolu][tahmin_rolu] += 1
            if tahmin_rolu == altin_rolu:
                rol_dogru += 1
                rol_sayimlari[altin_rolu]["true_positive"] += 1

            altin_sorular = altin_sayfa["questions"]
            tahmin_sorular = (_tahmin_kutularini_olcekle(
                altin_sayfa, tahmin_sayfa) if tahmin_sayfa else [])
            ignore_regions = altin_sayfa.get("ignore_regions", [])
            if ignore_regions:
                once = len(tahmin_sorular)
                tahmin_sorular = [q for q in tahmin_sorular
                                   if not _ignore_icinde(q, ignore_regions)]
                ignore_edilen_tahmin += once - len(tahmin_sorular)
            eslesmeler = _kutu_eslestir(
                altin_sorular, tahmin_sorular, iou_esigi)
            eslesen_p = {p for _, p, _ in eslesmeler}
            sayfa_tp = len(eslesmeler)
            sayfa_fp = len(tahmin_sorular) - sayfa_tp
            sayfa_fn = len(altin_sorular) - sayfa_tp
            tp += sayfa_tp
            fp += sayfa_fp
            fn += sayfa_fn
            belge_tp += sayfa_tp
            belge_fp += sayfa_fp
            belge_fn += sayfa_fn
            ioular.extend(iou for _, _, iou in eslesmeler)
            sayfa_rolune_gore_fp[altin_rolu] += sayfa_fp

            if altin_rolu not in {"soru", "karma"}:
                dislanan_sayfa += 1
                if tahmin_sorular:
                    dislanan_fp_sayfa += 1

            for gi, pi, _ in eslesmeler:
                # V1'de kutular zaten tek parçalı ve altın koordinat
                # uzayına ölçeklenmiş; eşleşme yeniden kurulmaz.
                _kenar_farki_ekle(
                    kenar_biriktirici, altin_sorular[gi]["box"],
                    tahmin_sorular[pi]["box"],
                    altin_sayfa["width"], altin_sayfa["height"])
                altin_tip = altin_sorular[gi].get("type", "bilinmiyor")
                tahmin_tip = tahmin_sorular[pi].get("type", "bilinmiyor")
                if altin_tip != "bilinmiyor":
                    tip_toplam += 1
                    tip_dogru += int(altin_tip == tahmin_tip)

            for pi, soru in enumerate(tahmin_sorular):
                kova = _guven_kovasi(soru.get("confidence"))
                guven[kova]["count"] += 1
                if pi in eslesen_p:
                    guven[kova]["true_positive"] += 1
                else:
                    guven[kova]["false_positive"] += 1

            for g in altin_sorular:
                kaplayan = sum(
                    _oran(_kesisim_alani(g["box"], p["box"]), _alan(g["box"]))
                    >= bolunme_ortusme_esigi for p in tahmin_sorular)
                bolunme += int(kaplayan >= 2)
            for p in tahmin_sorular:
                kapsanan = sum(
                    _oran(_kesisim_alani(g["box"], p["box"]), _alan(g["box"]))
                    >= bolunme_ortusme_esigi for g in altin_sorular)
                birlesme += int(kapsanan >= 2)

        # Altinda bulunmayan tahmin sayfalari da yanlis pozitif sayilir.
        altin_sayfa_nolari = {s["page"] for s in altin_belge["pages"]}
        if tahmin_belge:
            for fazla in tahmin_belge["pages"]:
                if fazla["page"] in altin_sayfa_nolari:
                    continue
                fazla_fp = len(fazla["questions"])
                fp += fazla_fp
                belge_fp += fazla_fp
                altinsiz_tahmin_kutusu += fazla_fp
                for soru in fazla["questions"]:
                    kova = _guven_kovasi(soru.get("confidence"))
                    guven[kova]["count"] += 1
                    guven[kova]["false_positive"] += 1
        belge_sonuclari.append({
            "id": altin_belge["id"],
            "true_positive": belge_tp,
            "false_positive": belge_fp,
            "false_negative": belge_fn,
            "precision": _oran(belge_tp, belge_tp + belge_fp),
            "recall": _oran(belge_tp, belge_tp + belge_fn),
        })

    # Altin veri setinde karsiligi olmayan tahmin belgeleri de sessizce
    # kaybolmaz; tum kutulari yanlis pozitif olarak kalite sonucuna girer.
    for fazla_belge in tahmin["documents"]:
        if id(fazla_belge) in eslesen_tahmin_nesneleri:
            continue
        fazla_fp = sum(len(s["questions"]) for s in fazla_belge["pages"])
        fp += fazla_fp
        altinsiz_tahmin_kutusu += fazla_fp
        for sayfa in fazla_belge["pages"]:
            for soru in sayfa["questions"]:
                kova = _guven_kovasi(soru.get("confidence"))
                guven[kova]["count"] += 1
                guven[kova]["false_positive"] += 1
        belge_sonuclari.append({
            "id": fazla_belge["id"],
            "gold_missing": True,
            "true_positive": 0,
            "false_positive": fazla_fp,
            "false_negative": 0,
            "precision": 0.0,
            "recall": 0.0,
        })

    for sayim in rol_sayimlari.values():
        sayim["precision"] = _oran(
            sayim["true_positive"], sayim["predicted"])
        sayim["recall"] = _oran(sayim["true_positive"], sayim["gold"])
    for sayim in guven.values():
        sayim["precision"] = _oran(
            sayim["true_positive"], sayim["count"])

    kesinlik = _oran(tp, tp + fp)
    geri_cagirma = _oran(tp, tp + fn)
    toplam_altin_soru = tp + fn
    return {
        "schema_version": KALITE_RAPORU_SURUMU,
        "thresholds": {
            "iou": iou_esigi,
            "split_merge_overlap": bolunme_ortusme_esigi,
            "review": 0.55,
            "automatic": 0.82,
        },
        "page_role": {
            "total": rol_toplam,
            "correct": rol_dogru,
            "accuracy": _oran(rol_dogru, rol_toplam),
            "per_role": rol_sayimlari,
            "confusion": rol_karisiklik,
        },
        "question_boxes": {
            "true_positive": tp,
            "false_positive": fp,
            "false_negative": fn,
            "precision": kesinlik,
            "recall": geri_cagirma,
            "f1": _oran(2 * kesinlik * geri_cagirma,
                         kesinlik + geri_cagirma),
            "mean_matched_iou": _oran(sum(ioular), len(ioular)),
        },
        # Kesim sınırı teşhisi: eşleşen çiftlerin dört yönlü işaretli farkı.
        "kenar_hatalari": _kenar_hatalari_ozeti(kenar_biriktirici),
        "question_type": {
            "matched_with_known_gold_type": tip_toplam,
            "correct": tip_dogru,
            "accuracy": _oran(tip_dogru, tip_toplam),
        },
        "split_merge_proxy": {
            "split_count": bolunme,
            "merge_count": birlesme,
            "split_rate": _oran(bolunme, toplam_altin_soru),
            "merge_rate": _oran(birlesme, tp + fp),
        },
        "false_positives": {
            "total_boxes": fp,
            "by_gold_page_role": sayfa_rolune_gore_fp,
            "excluded_pages": dislanan_sayfa,
            "excluded_pages_with_predictions": dislanan_fp_sayfa,
            "excluded_page_rate": _oran(dislanan_fp_sayfa, dislanan_sayfa),
            "unmatched_page_or_document_boxes": altinsiz_tahmin_kutusu,
            "ignored_region_predictions": ignore_edilen_tahmin,
        },
        "confidence_buckets": guven,
        "documents": belge_sonuclari,
    }


def _ornek_indeksleri(N, max_sayfa, bas, son):
    """İşlenecek 0-tabanlı sayfa indekslerini seçer.
    - bas verilmişse [bas, son] aralığı (hedefli inceleme).
    - Belge büyükse (N > 2·max_sayfa) BELGE BOYUNCA eşit aralıklı örnekle →
      metrik kapak/yönerge değil soru sayfalarını yakalar.
    - Küçük belgede ilk-N (mevcut davranış, regresyon nötr)."""
    if bas is not None:
        son = son if son is not None else bas + (max_sayfa or 40) - 1
        return list(range(max(0, bas - 1), min(N, son)))
    if max_sayfa and N > 2 * max_sayfa:
        adim = max(1, N // max_sayfa)
        return list(range(0, N, adim))[:max_sayfa]
    if max_sayfa:
        return list(range(min(N, max_sayfa)))
    return list(range(N))


def belge_isle(yol, dpi=300, max_sayfa=None, bas=None, son=None):
    """Belgeyi işleyip (format, [(sayfa, bantlar, kutular)], ornek_no, acik)
    döndürür. ornek_no: işlenen 1-tabanlı sayfa numaraları (örnekleme sonrası).
    acik: iş bitince sk.belge_kapat'a verilecek fitz belgeleri."""
    tum_sayfa, acik = sk.belge_sayfalari([yol], dpi)
    idx = _ornek_indeksleri(len(tum_sayfa), max_sayfa, bas, son)
    sayfalar = [tum_sayfa[i] for i in idx]
    ornek_no = [i + 1 for i in idx]
    sk.toplu_ocr(sayfalar)  # taranmışlarda paralel OCR
    tum = [s.satirlar() for s in sayfalar]
    fmt = sk.belge_formati(sayfalar, tum)
    # Yeni motor varsa ayni ornek sayfalarda V2 profil/rol/guven analizi yap.
    # onbellek=False kritiktir: dogrulama icin orneklenmis kismi, tam belge
    # profiliymis gibi uygulamanin kalici profil onbellegine yazmayiz.
    if hasattr(sk, "belge_analiz_et"):
        try:
            sk.belge_analiz_et(
                sayfalar, fmt=fmt, girdiler=[yol], tum_satirlar=tum,
                onbellek=False)
        except Exception as exc:  # eski metrik yolunu calisir halde tut
            for s in sayfalar:
                s._v2_hata = f"{type(exc).__name__}: {exc}"
    veriler = []
    for s in sayfalar:
        bantlar = sk.sayfa_sutunlari(s)
        meta, _, _ = sk.sorulari_tespit_meta(s, fmt)
        # Motorun TESLİM kümesiyle birebir aynı olmalı (sk.aday_tespit_edildi).
        # Eskiden yalnız devam adayları eleniyordu; reddedilenler metriklere
        # giriyordu — yani count_recall/precision ve kayma sinyalleri hiç
        # çıktıya yazılmayan kutuları sayıyordu.
        kutular = [m.kutu for m in meta if sk.aday_tespit_edildi(m)]
        veriler.append((s, bantlar, kutular, meta))
    return fmt, veriler, ornek_no, acik


def _dosya_sha256(yol):
    ozet = hashlib.sha256()
    with open(yol, "rb") as dosya:
        while True:
            parca = dosya.read(1024 * 1024)
            if not parca:
                break
            ozet.update(parca)
    return ozet.hexdigest()


def _json_listesi(deger):
    if deger is None:
        return []
    if isinstance(deger, str):
        return [deger]
    try:
        return [str(v) for v in deger]
    except TypeError:
        return [str(deger)]


def _analiz_nesnesi(sayfa):
    """V2 motoru sayfaya analiz eklediyse farkli uyumlu adlardan bulur."""
    for ad in ("_v2_sayfa_analizi", "sayfa_analizi", "analiz",
               "_sayfa_analizi"):
        analiz = getattr(sayfa, ad, None)
        if analiz is not None:
            return analiz
    return None


def _analiz_degeri(analiz, *adlar, varsayilan=None):
    if analiz is None:
        return varsayilan
    for ad in adlar:
        if isinstance(analiz, dict) and ad in analiz:
            return analiz[ad]
        if hasattr(analiz, ad):
            return getattr(analiz, ad)
    return varsayilan


def _sayfa_tahmini(sayfa, meta, sayfa_no, fmt):
    gorunen = [m for m in meta if not getattr(m, "devam_aday", False)]
    analiz = _analiz_nesnesi(sayfa)
    rol = kanonik_sayfa_rolu(
        _analiz_degeri(analiz, "sayfa_rolu", "role"))
    if rol not in TAHMIN_SAYFA_ROLLERI:
        aday_roller = [kanonik_sayfa_rolu(
            getattr(m, "sayfa_rolu", None)) for m in gorunen]
        aday_roller = [r for r in aday_roller if r in TAHMIN_SAYFA_ROLLERI]
        rol = max(set(aday_roller), key=aday_roller.count) if aday_roller \
            else "bilinmiyor"
    rol_guveni = _analiz_degeri(
        analiz, "rol_guveni", "role_confidence", varsayilan=None)
    if not isinstance(rol_guveni, (int, float)) or isinstance(rol_guveni, bool):
        rol_guveni = None
    elif not math.isfinite(rol_guveni):
        rol_guveni = None
    else:
        rol_guveni = min(1.0, max(0.0, float(rol_guveni)))

    sorular = []
    for sira, aday in enumerate(gorunen, 1):
        kutu = [round(float(v), 3) for v in aday.kutu]
        soru_turu = kanonik_soru_turu(
            getattr(aday, "soru_turu", "bilinmiyor"))
        if soru_turu not in SORU_TURLERI:
            fmt_turu = kanonik_soru_turu(fmt)
            soru_turu = (fmt_turu if fmt_turu in SORU_TURLERI
                          else "bilinmiyor")
        aday_guveni = getattr(aday, "guven", None)
        if (not isinstance(aday_guveni, (int, float))
                or isinstance(aday_guveni, bool)
                or not math.isfinite(aday_guveni)):
            aday_guveni = None
        else:
            aday_guveni = min(1.0, max(0.0, float(aday_guveni)))
        durum = getattr(aday, "inceleme_durumu", None)
        if durum not in {"otomatik", "incele", "reddedildi", "bilinmiyor"}:
            durum = _guven_kovasi(aday_guveni)
        kararli_id = (getattr(aday, "kararli_kimlik", None)
                      or getattr(aday, "kimlik", None)
                      or f"p{sayfa_no}q{sira}")
        sorular.append({
            "id": str(kararli_id),
            "box": kutu,
            "number": getattr(aday, "numara", None),
            "type": soru_turu,
            "confidence": aday_guveni,
            "status": durum,
            "evidence": _json_listesi(getattr(aday, "kanitlar", ())),
            "warnings": _json_listesi(getattr(aday, "uyarilar", ())),
        })
    return {
        "page": int(sayfa_no),
        "width": round(float(sayfa.genislik), 3),
        "height": round(float(sayfa.yukseklik), 3),
        "role": rol,
        "role_confidence": rol_guveni,
        "layout_family": _analiz_degeri(
            analiz, "duzen_ailesi", "layout_family", varsayilan="bilinmiyor"),
        "analysis_error": getattr(sayfa, "_v2_hata", None),
        "questions": sorular,
    }


def _v2_sayfa_yapisi(v1_sayfa):
    sayfa = dict(v1_sayfa)
    ham = sayfa.pop("questions")
    analiz_hatasi = sayfa.get("analysis_error")
    nedenler = []
    if analiz_hatasi:
        nedenler.append(str(analiz_hatasi))
    if sayfa["role"] in {"soru", "karma"} and not any(
            q.get("status") != "reddedildi" for q in ham):
        nedenler.append("soru_sayfasinda_aday_yok")
    for q in ham:
        nedenler.extend(q.get("warnings") or [])
    nedenler = list(dict.fromkeys(str(n) for n in nedenler if n))
    bekliyor = bool(analiz_hatasi or any(
        q.get("status") == "incele" for q in ham)
        or "soru_sayfasinda_aday_yok" in nedenler)
    sayfa.update({
        "review_status": "bekliyor" if bekliyor else "temiz",
        "risk_reasons": nedenler,
        "raw_proposals": ham,
        "final_cuts": [],
    })
    return sayfa


def _v2_nihai_kesimler(veriler, fmt, ornek_no, yol, kaynak_hash):
    """Gercek ``kirpma_seti`` sonucunu mantiksal parca metadata'sina cevirir."""
    sayfalar = [s for s, _bant, _kutu, _meta in veriler]
    plan, parca_meta, _testler = sk.kirpma_plani_meta(sayfalar, fmt)
    kirpmalar, sorular, uyarilar = sk.kirpma_seti(
        sayfalar, fmt, girdiler=[yol])
    if not (len(plan) == len(parca_meta) == len(kirpmalar) == len(sorular)):
        raise ValueError("kirpma_seti plan/PNG/metadata sayilari tutarsiz")
    sonuc = []
    for sira, (parcalar, pm, img, soru) in enumerate(
            zip(plan, parca_meta, kirpmalar, sorular), 1):
        v2_parcalar = []
        for parca_sira, (yerel_sayfa, kutu) in enumerate(parcalar):
            v2_parcalar.append({
                "page": int(ornek_no[yerel_sayfa]),
                "box": [round(float(v), 3) for v in kutu],
                "kind": ("soru_govdesi" if parca_sira == 0 else "devam"),
            })
        kimlik_ozu = json.dumps(
            [kaynak_hash, v2_parcalar, soru.get("soru_no")],
            ensure_ascii=True, sort_keys=True).encode("utf-8")
        kararli_id = (soru.get("kararli_kimlik") or soru.get("kimlik")
                      or f"cut:{hashlib.sha256(kimlik_ozu).hexdigest()[:20]}")
        guven_degeri = soru.get("kalibre_guven", soru.get("guven"))
        if (not isinstance(guven_degeri, (int, float))
                or isinstance(guven_degeri, bool)
                or not math.isfinite(guven_degeri)):
            guven_degeri = None
        else:
            guven_degeri = max(0.0, min(1.0, float(guven_degeri)))
        durum = _ascii_anahtar(soru.get("inceleme_durumu"))
        if durum not in INCELEME_DURUMLARI:
            durum = _guven_kovasi(guven_degeri)
        soru_turu = kanonik_soru_turu(soru.get("soru_turu"))
        if soru_turu not in SORU_TURLERI:
            soru_turu = "bilinmiyor"
        sonuc.append({
            "id": str(kararli_id),
            "owner_page": int(ornek_no[parcalar[0][0]]),
            "parts": v2_parcalar,
            "number": soru.get("soru_no"),
            "type": soru_turu,
            "confidence": guven_degeri,
            "status": durum,
            "evidence": _json_listesi(soru.get("tespit_kanitlari")),
            "warnings": _json_listesi(soru.get("tespit_uyarilari")),
            "output": {
                "produced": True,
                "question_number": soru.get("soru_no"),
                "part_count": len(v2_parcalar),
                "image_width": int(img.width),
                "image_height": int(img.height),
                "metadata": {
                    "test_no": soru.get("test_no"),
                    "test_sira": soru.get("test_sira"),
                    "source": soru.get("kaynak"),
                    "algorithm_version": soru.get("algoritma_surumu"),
                },
            },
        })
    return sonuc, list(uyarilar)


def _tahmin_raporu_verilerden(yol, fmt, veriler, ornek_no, *, dpi,
                              max_sayfa, belge_kimligi=None,
                              schema_version=TAHMIN_SEMA_SURUMU,
                              quality_mode="strict"):
    if schema_version not in TAHMIN_SEMA_SURUMLERI:
        raise ValueError(f"Desteklenmeyen tahmin semasi: {schema_version}")
    quality_mode = _ascii_anahtar(quality_mode)
    if quality_mode not in {"strict", "balanced", "legacy"}:
        raise ValueError("quality_mode strict, balanced veya legacy olmali")
    kaynak_hash = _dosya_sha256(yol)
    sayfalar = [
        _sayfa_tahmini(s, meta, no, fmt)
        for (s, _bantlar, _kutular, meta), no in zip(veriler, ornek_no)
    ]
    final_output = None
    if schema_version == TAHMIN_SEMA_SURUMU_V2:
        sayfalar = [_v2_sayfa_yapisi(s) for s in sayfalar]
        try:
            final_kesimler, kirpma_uyarilari = _v2_nihai_kesimler(
                veriler, fmt, ornek_no, yol, kaynak_hash)
        except Exception as exc:  # kalite raporu sessizce legacy'ye dusmez
            final_kesimler = []
            kirpma_uyarilari = [f"{type(exc).__name__}: {exc}"]
            if sayfalar:
                sayfalar[0]["review_status"] = "bekliyor"
                sayfalar[0]["risk_reasons"] = list(dict.fromkeys(
                    sayfalar[0]["risk_reasons"] + kirpma_uyarilari))
        # Inceleme kuyrugu aday degil sayfa tabanlidir; ayni sayfadaki birden
        # cok belirsiz aday bekleyen sayisini yapay olarak buyutmez.
        bekleyen = sum(s["review_status"] == "bekliyor" for s in sayfalar)
        bloklu = quality_mode == "strict" and bekleyen > 0
        if not bloklu:
            sayfa_haritasi = {s["page"]: s for s in sayfalar}
            for kesim in final_kesimler:
                owner = kesim.pop("owner_page")
                if owner in sayfa_haritasi:
                    sayfa_haritasi[owner]["final_cuts"].append(kesim)
        gercek_adet = 0 if bloklu else len(final_kesimler)
        final_output = {
            "quality_mode": quality_mode,
            "blocked": bloklu,
            "written": False,
            "zip_written": False,
            "pending_review_count": bekleyen,
            "question_count": gercek_adet,
            "png_count": gercek_adet,
            "metadata_count": gercek_adet,
            "warnings": kirpma_uyarilari,
        }
    rapor = {
        "schema_version": schema_version,
        "generator": {
            "algorithm_version": str(getattr(
                sk, "KALIBRASYON_SURUMU", "legacy")),
            "format": fmt,
            "dpi": dpi,
            "sampled": bool(max_sayfa),
            "sampled_pages": list(ornek_no),
            "quality_mode": quality_mode,
        },
        "documents": [{
            "id": belge_kimligi or f"sha256:{kaynak_hash}",
            "source": os.path.basename(os.fspath(yol)),
            "source_hash": kaynak_hash,
            "source_sha256": kaynak_hash,
            "pages": sayfalar,
        }],
    }
    if final_output is not None:
        rapor["documents"][0]["final_output"] = final_output
    return _veri_setini_dogrula(rapor, tahmin=True)


def tahmin_raporu_olustur(yol, dpi=300, max_sayfa=40, bas=None, son=None,
                          belge_kimligi=None,
                          schema_version=TAHMIN_SEMA_SURUMU,
                          quality_mode="strict"):
    """Belgeyi salt-okunur isleyip surumlu koordinat/guven raporu olusturur."""
    fmt, veriler, ornek_no, acik = belge_isle(
        yol, dpi=dpi, max_sayfa=max_sayfa, bas=bas, son=son)
    try:
        return _tahmin_raporu_verilerden(
            yol, fmt, veriler, ornek_no, dpi=dpi, max_sayfa=max_sayfa,
            belge_kimligi=belge_kimligi, schema_version=schema_version,
            quality_mode=quality_mode)
    finally:
        sk.belge_kapat(acik)


def rapor_ozeti(rapor):
    """Tahmin raporunu kaynak belgeyi acmadan kisa makine-okünur ozetler."""
    _veri_setini_dogrula(rapor, tahmin=True)
    sayfalar = [s for b in rapor["documents"] for s in b["pages"]]
    v2 = rapor["schema_version"] == TAHMIN_SEMA_SURUMU_V2
    sorular = [q for s in sayfalar for q in (
        (s.get("final_cuts") if "final_cuts" in s else s.get("questions", []))
        if v2 else s["questions"])]
    ham = ([q for s in sayfalar for q in s.get("raw_proposals", [])]
           if v2 else sorular)
    kovalar = {ad: 0 for ad in
               ("reddedildi", "incele", "otomatik", "bilinmiyor")}
    roller = {}
    for sayfa in sayfalar:
        roller[sayfa["role"]] = roller.get(sayfa["role"], 0) + 1
    for soru in ham:
        kovalar[_guven_kovasi(soru.get("confidence"))] += 1
    sonuc = {
        "schema_version": ("soru-kesici.prediction-summary/v2" if v2
                           else "soru-kesici.prediction-summary/v1"),
        "document_count": len(rapor["documents"]),
        "page_count": len(sayfalar),
        "question_count": len(sorular),
        "page_roles": roller,
        "confidence_buckets": kovalar,
    }
    if v2:
        sonuc["raw_proposal_count"] = len(ham)
        sonuc["pending_review_count"] = max(
            sum(s.get("review_status") in {"bekliyor", "incele"}
                for s in sayfalar),
            sum(int((b.get("final_output") or {}).get(
                "pending_review_count", 0)) for b in rapor["documents"]))
    return sonuc


def metrikler(yol, dpi=300, max_sayfa=40, bas=None, son=None):
    fmt, veriler, ornek_no, acik = belge_isle(yol, dpi, max_sayfa, bas, son)
    try:
        return _metrikleri_hesapla(fmt, veriler, ornek_no, yol)
    finally:
        sk.belge_kapat(acik)


def _kanitsiz_kutu_say(meta):
    """Sayfadaki TESLİM edilen ama sınır kanıtı taşımayan aday sayısı.

    Payda `toplam_kutu` ile birebir tutmak zorunda olduğu için küme
    `sk.aday_tespit_edildi` ile alınır: reddedilen ya da devam adayı olan
    kanıtsız kutular sayıya girmez, çünkü onlar zaten teslim edilmiyor.
    Ayrı fonksiyon olmasının nedeni bu kural kaymasının testle çivilenmesi.
    """
    return sum(1 for m in meta
               if sk.aday_tespit_edildi(m)
               and not getattr(m, "sinir_kanitlari", ()))


def _metrikleri_hesapla(fmt, veriler, ornek_no, yol):
    G = max(s.genislik for s, _, _, _ in veriler)
    Y = max(s.yukseklik for s, _, _, _ in veriler)
    pay = G * 0.012
    alanlar, kutu_kayit, anomali = [], [], []
    sayfa_num_y = []          # sayfa-başı numara adaylarının y0 listesi (birleşme testi)
    toplam_kutu = sum(len(k) for _, _, k, _ in veriler)
    sayfa_kutu = [len(k) for _, _, k, _ in veriler]
    # Kayma nöbetçisi girdileri: ham aday = dedektörün FİLTRE ÖNCESİ sinyali
    # (numara çapaları). Kutu sayısı düşerken ham aday da düştüyse dedektör
    # gerilemiştir; ham aday sabit kalıp reddedilen artmışsa yalnız filtre
    # sıkılaşmıştır. İkisi farklı hata sınıfıdır ve farklı karar gerektirir.
    sayfa_ham_aday = []
    reddedilen_toplam = incele_toplam = 0
    # KANITSIZ KUTU: teslim edilen ama hiçbir kenarına hangi kuralın karar
    # verdiği kaydedilmemiş kutu. `sinir_kanitlari` yalnızca `_kutu_insa`
    # yolunda dolar; blok-fallback / kurtarma / geri-bağlama yollarından
    # gelen kutular boş kanıtla çıkar. Ölçülen gerçek: korpusun en kötü
    # sayfasında (12meb s186) üretilen 5 kutunun 5'i de kanıtsız -> "kanıtsız
    # kutu" ile "kötü kutu" güçlü ilişkili, üstelik bedava bir sinyal.
    kanitsiz_toplam = 0
    kanitsiz_sayfalar = []
    for i, (s, bantlar, kutular, _meta) in enumerate(veriler):
        satirlar = s.satirlar()
        sayfa_kanitsiz = _kanitsiz_kutu_say(_meta)
        kanitsiz_toplam += sayfa_kanitsiz
        if sayfa_kanitsiz:
            kanitsiz_sayfalar.append(ornek_no[i])
        reddedilen_kutular = {
            tuple(m.kutu) for m in _meta
            if getattr(m, "inceleme_durumu", None) == "reddedildi"
        }
        reddedilen_toplam += len(reddedilen_kutular)
        incele_toplam += sum(
            1 for m in _meta
            if getattr(m, "inceleme_durumu", None) == "incele")
        sayfa_num_y.append(sorted(kutu[1] for _, kutu, _
                                  in sk.numara_adaylari(satirlar)))
        sayfa_ham_aday.append(len(sayfa_num_y[-1]))
        # BOŞ SÜTUN (gerçek eksik): geniş bir bantta hiç kutu YOK ama bantta
        # gerçek çoktan seçmeli soru KANITI var (≥3 farklı şık). HAM numara
        # sayımı yerine şık kullanılır → konu-listesi/alt-madde/tablo numaraları
        # yanlış "eksik-soru" üretmez; yalnız gerçekten kaçan soru sütunu işaretlenir.
        for a, b in bantlar:
            if b - a <= G * 0.14:
                continue
            if any(a <= (k[0] + k[2]) / 2 < b for k in kutular):
                continue
            if sk.bolge_sik_sayisi(satirlar, 0, Y, a, b, pay) >= 3:
                anomali.append({"sayfa": ornek_no[i], "tur": "bos-sutun",
                                "detay": [round(a), round(b)]})
        for k in kutular:
            x0, y0, x1, y1 = k
            alanlar.append((x1 - x0) * (y1 - y0))
            kutu_kayit.append((i, k))
            degen = sum(1 for a, b in bantlar
                        if min(x1, b) - max(x0, a) > (x1 - x0) * 0.20)
            # Çekirdeğin zaten reddettiği ham bir konu/başlık adayı gerçek
            # kesime giremez; onun yatay geometrisi çıktı regresyonu değildir.
            # Kutu ham sayaçta kalır, böylece boş-sütun ve tarihsel snapshot
            # davranışı değişmez.
            if degen >= 2 and tuple(k) not in reddedilen_kutular:
                anomali.append({"sayfa": ornek_no[i], "tur": "sutun-tasma",
                                "detay": [round(x0), round(x1)]})
    # KOMŞU-TUTARSIZLIK: bir sayfa, soru barındırdığı hâlde komşularının çok
    # altında kutu üretiyorsa (ani düşüş) → olası kaçırma. Belge genel yoğunluğu
    # medyanına göre kıyaslanır; tek tük boş/kapak sayfası yanlış-pozitif yapmaz.
    dolu = [n for n in sayfa_kutu if n > 0]
    med_kutu = sorted(dolu)[len(dolu) // 2] if dolu else 0
    if med_kutu >= 3:
        for i, (s, bantlar, kutular, _meta) in enumerate(veriler):
            n = len(kutular)
            if 0 < n < med_kutu * 0.4 \
                    and sk.bolge_sik_sayisi(s.satirlar(), 0, Y, 0, G, pay) >= med_kutu * 2:
                anomali.append({"sayfa": ornek_no[i], "tur": "komsu-dusuk",
                                "detay": [n, med_kutu]})
    if toplam_kutu == 0:
        anomali.insert(0, {"tur": "tespit-basarisiz", "detay": "0 kutu"})
    if alanlar:
        med = sorted(alanlar)[len(alanlar) // 2]
        for i, k in kutu_kayit:
            alan = (k[2] - k[0]) * (k[3] - k[1])
            if alan < med * 0.06:
                anomali.append({"sayfa": ornek_no[i], "tur": "minik",
                                "detay": round(alan / max(med, 1), 3)})
            elif alan > med * 4.5:
                # Büyük kutu TEK BAŞINA anomali değil (grafikli tek soru da büyük
                # olur). Yalnız GERÇEK birleşme sinyali varsa işaretle: kutunun
                # İÇİNDE (kenardan Y·0.02 içeride) ≥2 numara adayı ve bunlar
                # dikeyde ≥Y·0.05 ayrık → iki soru tek kutuda birleşmiş.
                y0, y1 = k[1], k[3]
                ic_num = [y for y in sayfa_num_y[i]
                          if y0 + Y * 0.02 <= y <= y1 - Y * 0.02]
                if len(ic_num) >= 2 and ic_num[-1] - ic_num[0] >= Y * 0.05:
                    anomali.append({"sayfa": ornek_no[i], "tur": "birlesme",
                                    "detay": [round(alan / max(med, 1), 2),
                                              len(ic_num)]})
    # --- bölünmüş soru göstergeleri (YENİ alanlar; eskiler dokunulmaz) ---
    # yarim-soru: bandın SON kutusu beklenen şık kümesinin bir kısmını içerip
    # bant dibine ulaşıyor → soru muhtemelen sonraki sütuna taşmış.
    beklenen = sk.beklenen_sik_kumesi([meta for *_, meta in veriler])
    yarim = []
    for i, (s, bantlar, kutular, meta) in enumerate(veriler):
        satirlar = s.satirlar()
        G2, Y2 = s.genislik, s.yukseklik
        pay2 = G2 * 0.012
        for bi, (ba, bb) in enumerate(bantlar):
            bant = [m for m in meta if m.bant_idx == bi and not m.devam_aday]
            if not bant:
                continue
            son = max(bant, key=lambda m: m.kutu[3])
            ic = sk._bolge_satirlari(satirlar, 0, Y2 * 0.97, ba, bb, pay2)
            bant_alt = max((k[3] for _, k in ic), default=0.0)
            if 1 <= len(son.sik_harfler) < len(beklenen) \
                    and son.kutu[3] >= bant_alt - Y2 * 0.04:
                yarim.append({"sayfa": ornek_no[i], "bant": bi})
    # birlestirilen: SAYFA-İÇİ (sütun sınırı) bölünme birleşmelerini sayar.
    # Örnekleme sayfaları belge boyunca yayıldığından sayfa-ARASI birleşme
    # örneklemede yapaydır → her sayfayı tek başına planlayıp yalnız kendi
    # içindeki birleşmeleri toplarız (gerçek, güvenilir sinyal).
    birlesen = 0
    for s, _, _, _ in veriler:
        for p in sk.kirpma_plani([s], fmt):
            if len(p) > 1:
                birlesen += 1
    return {
        "dosya": os.path.basename(yol),
        "format": fmt,
        "sayfa": len(veriler),
        "ornek_no": ornek_no if len(ornek_no) < 60 else
                    [ornek_no[0], "…", ornek_no[-1]],
        "soru_sayfa": len(dolu),          # kutu>0 olan örnek sayfa sayısı
        "toplam_kutu": toplam_kutu,
        "sayfa_soru": sayfa_kutu,
        "anomali_sayisi": len(anomali),
        "anomaliler": anomali[:24],
        "birlestirilen": birlesen,
        "yarim_soru": yarim[:24],
        # YENİ alan; eskiler dokunulmaz: ML düzen tespiti bu koşuda etkin miydi
        "duzen_model": bool(sk.duzen_model is not None
                            and sk.duzen_model.kullanilabilir()),
        # --- Kayma nöbetçisi alanları (kalite_kosusu._kayma_degerlendir) ---
        # Anomali sayısı bir PROXY'dir ve recall kaybını göremez: bir belgede
        # toplam kutu %37 düşerken anomali 0'da kalabilir. Aşağıdaki alanlar
        # kutu sayısı kaymasını, dedektör gerilemesi (ham aday düşüşü) ile
        # filtre sıkılaşmasından (aday sabit, reddedilen artıyor) ayırt eder.
        "kaynak_sha256": _dosya_sha256(yol),
        "ham_aday": sum(sayfa_ham_aday),
        "sayfa_ham_aday": sayfa_ham_aday,
        "reddedilen_kutu": reddedilen_toplam,
        "incele_kutu": incele_toplam,
        # Sınır kanıtı taşımayan teslim kutuları (en ucuz risk sinyali).
        "kanitsiz_kutu": kanitsiz_toplam,
        "kanitsiz_kutu_orani": _oran(kanitsiz_toplam, toplam_kutu),
        "kanitsiz_sayfalar": kanitsiz_sayfalar[:10],
        "anomali_turleri": dict(sorted(
            collections.Counter(a["tur"] for a in anomali).items())),
    }


def kontakt_sayfasi(yol, cikti, dpi=200, max_sayfa=40, kucuk_en=260, sutun=6,
                    bas=None, son=None):
    """Belgenin tüm kırpmalarını tek bir montaj PNG'sine dizer."""
    fmt, veriler, _, acik = belge_isle(yol, dpi, max_sayfa, bas, son)
    kucukler = []
    try:
        for s, _, kutular, _meta in veriler:
            for k in kutular:
                img = sk.trasla(s.kirp(k))
                oran = kucuk_en / img.width
                kucukler.append(
                    img.resize((kucuk_en, max(1, int(img.height * oran)))))
    finally:
        sk.belge_kapat(acik)
    if not kucukler:
        return None
    satir = (len(kucukler) + sutun - 1) // sutun
    hy = max(im.height for im in kucukler) + 8
    tuval = Image.new("RGB", (sutun * (kucuk_en + 8), satir * hy), "white")
    for idx, im in enumerate(kucukler):
        r, c = divmod(idx, sutun)
        tuval.paste(im, (c * (kucuk_en + 8) + 4, r * hy + 4))
    tuval.save(cikti)
    return cikti


def _arguman_ayristir(argv):
    parser = argparse.ArgumentParser(
        description="Soru kesimlerini olcer, raporlar ve altin veriyle karsilastirir")
    parser.add_argument("yol", nargs="?", help="PDF veya raster kaynak belge")
    parser.add_argument("max_sayfa", nargs="?", type=int, default=40,
                        help="Islenecek en fazla sayfa (varsayilan: 40)")
    parser.add_argument("--kontakt", metavar="PNG",
                        help="Kesimleri kontakt PNG'sine yaz")
    parser.add_argument("--aralik", nargs=2, type=int, metavar=("BAS", "SON"),
                        help="1-tabanli, iki ucu dahil sayfa araligi")
    parser.add_argument("--bas", type=int,
                        help="Bu 1-tabanli sayfadan itibaren isle")
    parser.add_argument("--dpi", type=int,
                        help="Isleme DPI'si (metrik: 300, kontakt: 200)")
    parser.add_argument("--rapor-yaz", "--report-write", dest="rapor_yaz",
                        metavar="JSON", help="Surumlu tahmin raporunu yaz")
    parser.add_argument("--rapor-oku", "--report-read", dest="rapor_oku",
                        metavar="JSON", help="Tahmin raporunu kaynagi acmadan oku")
    parser.add_argument("--altin", "--golden", metavar="JSON",
                        help="V1 altin koordinat/rol verisi")
    parser.add_argument("--belge-kimligi", metavar="ID",
                        help="Tahmin raporundaki belge kimligini sabitle")
    parser.add_argument("--rapor-sema", choices=("v1", "v2"), default="v1",
                        help="Yazilan tahmin semasi (varsayilan: v1)")
    parser.add_argument("--kalite", choices=("strict", "balanced", "legacy"),
                        default="strict",
                        help="V2 nihai cikti kalite kapisi")
    parser.add_argument("--iou-esigi", type=float, default=0.5)
    parser.add_argument("--bolunme-esigi", type=float, default=0.2)
    args = parser.parse_args(argv)
    if args.rapor_oku and args.yol:
        parser.error("--rapor-oku ile kaynak belge birlikte verilemez")
    if not args.rapor_oku and not args.yol:
        parser.error("kaynak belge veya --rapor-oku gerekli")
    if args.aralik and args.bas is not None:
        parser.error("--aralik ve --bas birlikte kullanilamaz")
    if args.max_sayfa is not None and args.max_sayfa < 1:
        parser.error("max_sayfa pozitif olmali")
    if args.dpi is not None and args.dpi < 72:
        parser.error("--dpi en az 72 olmali")
    return args


def main(argv=None):
    args = _arguman_ayristir(sys.argv[1:] if argv is None else argv)
    if args.rapor_oku:
        tahmin = tahmin_raporunu_yukle(args.rapor_oku)
        sonuc = (kalite_degerlendir(
            altin_veriyi_yukle(args.altin), tahmin,
            iou_esigi=args.iou_esigi,
            bolunme_ortusme_esigi=args.bolunme_esigi)
                  if args.altin else rapor_ozeti(tahmin))
        print(json.dumps(sonuc, ensure_ascii=False))
        return sonuc

    bas, son = ((args.aralik[0], args.aralik[1])
                if args.aralik else (args.bas, None))
    isleme_dpi = args.dpi or 300
    tahmin = None
    if args.rapor_yaz or args.altin:
        fmt, veriler, ornek_no, acik = belge_isle(
            args.yol, dpi=isleme_dpi, max_sayfa=args.max_sayfa,
            bas=bas, son=son)
        try:
            m = _metrikleri_hesapla(fmt, veriler, ornek_no, args.yol)
            tahmin = _tahmin_raporu_verilerden(
                args.yol, fmt, veriler, ornek_no, dpi=isleme_dpi,
                max_sayfa=args.max_sayfa,
                belge_kimligi=args.belge_kimligi,
                schema_version=(TAHMIN_SEMA_SURUMU_V2
                                if args.rapor_sema == "v2"
                                else TAHMIN_SEMA_SURUMU_V1),
                quality_mode=args.kalite)
        finally:
            sk.belge_kapat(acik)
    else:
        m = metrikler(args.yol, dpi=isleme_dpi,
                      max_sayfa=args.max_sayfa, bas=bas, son=son)
    if args.kontakt:
        m["kontakt"] = kontakt_sayfasi(
            args.yol, args.kontakt, dpi=args.dpi or 200,
            max_sayfa=args.max_sayfa,
            bas=bas, son=son)
    if args.rapor_yaz:
        m["rapor"] = rapor_yaz(tahmin, args.rapor_yaz)
    if args.altin:
        m["kalite"] = kalite_degerlendir(
            altin_veriyi_yukle(args.altin), tahmin,
            iou_esigi=args.iou_esigi,
            bolunme_ortusme_esigi=args.bolunme_esigi)
    print(json.dumps(m, ensure_ascii=False))
    return m


if __name__ == "__main__":
    main()
