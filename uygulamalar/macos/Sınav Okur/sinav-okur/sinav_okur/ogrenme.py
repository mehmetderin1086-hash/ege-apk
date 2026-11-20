"""Yalnız açık öğretmen düzeltmelerinden güvenli puan kalibrasyonu."""

from __future__ import annotations

import json
import os
import statistics
import threading
from pathlib import Path

# Aynı süreç içinde (webapp threadpool) eşzamanlı kalibrasyon yazımlarını
# sırayla çalıştırır; .tmp/.onceki/.metrikler dosyalarının yarışmasını önler.
_KALIBRASYON_KILIDI = threading.Lock()


def ogretmen_kalibrasyonu(
    duzeltmeler: list[dict],
    *,
    soru_no: int,
    max_puan: float,
) -> dict:
    farklar = [
        float(x["ogretmen_puani"]) - float(x["otomatik_puan"])
        for x in duzeltmeler
        if int(x["soru_no"]) == int(soru_no)
        and x["ogretmen_puani"] is not None
        and x["otomatik_puan"] is not None
    ]
    if len(farklar) < 5:
        return {
            "uygulanabilir": False,
            "ornek": len(farklar),
            "duzeltme": 0.0,
            "neden": "En az 5 insan düzeltmesi gerekli.",
        }
    medyan = statistics.median(farklar)
    sapmalar = [abs(x - medyan) for x in farklar]
    mad = statistics.median(sapmalar)
    if mad > max(1.0, max_puan * 0.18):
        return {
            "uygulanabilir": False,
            "ornek": len(farklar),
            "duzeltme": 0.0,
            "neden": "Öğretmen düzeltmeleri kendi içinde tutarlı değil.",
        }
    duzeltme = max(-max_puan * 0.10, min(max_puan * 0.10, medyan))
    return {
        "uygulanabilir": True,
        "ornek": len(farklar),
        "duzeltme": round(duzeltme * 2) / 2,
        "neden": "Aynı sorudaki tutarlı, açık öğretmen düzeltmelerinin medyanı.",
    }


def ogrenilmis_kabul_yazimlari(
    duzeltmeler: list[dict],
    *,
    soru_no: int,
    max_puan: float,
    anahtar_yazimlari: list[str],
    asgari_destek: int = 2,
) -> list[dict]:
    """Öğretmenin tam puan verdiği, anahtarda olmayan yazımları çıkarır.

    Bir öğrenci "hücre zarı" yerine "plazma zarı" yazdığında öğretmen tam
    puan veriyorsa bu, anahtarın eksik olduğunun kanıtıdır. Aynı normalize
    yazım ``asgari_destek`` kez tekrar ederse ÖNERİ üretilir — öneri asla
    otomatik puanlamaz, öğretmen onayına düşer.
    """
    from collections import Counter

    from .metin import eslesme_bicimi
    from .puanlama.bosluk import en_iyi_eslesme

    normal_anahtar = {eslesme_bicimi(a) for a in anahtar_yazimlari}
    sayac: Counter = Counter()
    ornek_yazim: dict[str, str] = {}
    puan_farklari: dict[str, list[float]] = {}
    for kayit in duzeltmeler:
        if int(kayit["soru_no"]) != int(soru_no):
            continue
        ogretmen_puani = kayit.get("ogretmen_puani")
        if ogretmen_puani is None or float(ogretmen_puani) < float(max_puan) - 1e-9:
            continue
        yazim = str(kayit.get("duzeltilmis_metin") or kayit.get("ocr_metni") or "")
        norm = eslesme_bicimi(yazim)
        if not norm or norm in normal_anahtar:
            continue
        # Anahtara zaten yakınsa (yalnız yazım farkı) yeni bilgi değildir.
        skor, _e = en_iyi_eslesme(yazim, anahtar_yazimlari)
        if skor >= 88.0:
            continue
        sayac[norm] += 1
        ornek_yazim.setdefault(norm, yazim.strip())
        puan_farklari.setdefault(norm, []).append(
            float(ogretmen_puani) - float(kayit.get("otomatik_puan") or 0.0)
        )
    oneriler = []
    for norm, adet in sayac.items():
        if adet < asgari_destek:
            continue
        farklar = puan_farklari[norm]
        medyan = statistics.median(farklar)
        mad = statistics.median([abs(f - medyan) for f in farklar])
        if mad > max(1.0, float(max_puan) * 0.18):
            continue  # öğretmen bu yazımda kendi içinde tutarsız
        oneriler.append(
            {
                "yazim": ornek_yazim[norm],
                "destek": adet,
                "onay_durumu": "oneri",
            }
        )
    oneriler.sort(key=lambda x: (-x["destek"], x["yazim"]))
    return oneriler


def puani_kalibre_et(puan: float, max_puan: float, kalibrasyon: dict) -> float:
    if not kalibrasyon.get("uygulanabilir"):
        return float(puan)
    return round(
        max(0.0, min(float(max_puan), float(puan) + float(kalibrasyon["duzeltme"])))
        * 2
    ) / 2


def ocr_kalibrasyon_kumesi(ornekler: list[dict]) -> tuple[list[float], list[int]]:
    """(ham_guven, etiket) çiftleri üretir; etiket = normalize metinler eşit mi."""
    from .metin import eslesme_bicimi

    ham: list[float] = []
    etiket: list[int] = []
    for ornek in ornekler:
        ham.append(float(ornek["ham_guven"]))
        dogru = eslesme_bicimi(ornek["taninan"]) == eslesme_bicimi(ornek["ogretmen"])
        etiket.append(int(dogru))
    return ham, etiket


def ocr_kalibrasyonunu_guncelle(
    depo,
    cikti_yolu: str | Path,
    *,
    sinav_kimlik: str | None = None,
    asgari_ornek: int = 200,
    asgari_sinif: int = 30,
    yalniz_duzeltmeler: bool = False,
    kuru: bool = False,
) -> dict:
    """Öğretmen düzeltmelerinden OCR güven kalibrasyonu eğitir.

    Yeni eğri yalnız kilitli ölçüt (Brier) mevcut/varsayılan eğriden iyiyse
    atomik olarak yazılır; eskisi ``.onceki.json``'a yedeklenir, metrikler yan
    dosyaya kaydedilir. ``kuru=True`` ise yalnız değerlendirir, yazmaz.
    """
    from .htr.kalibrasyon import (
        DILIM_BILINMIYOR,
        KosulluGuvenKalibrasyonu,
        dilim_anahtari,
    )

    ornekler = depo.kalibrasyon_ornekleri(sinav_kimlik)
    if yalniz_duzeltmeler:
        ornekler = [o for o in ornekler if o["kaynak"] == "duzeltme"]
    ham, etiket = ocr_kalibrasyon_kumesi(ornekler)
    # Dilim sütunları olmayan eski satırlar "bilinmiyor" dilimine gider;
    # KosulluGuvenKalibrasyonu bu dilime eğri eğitmez, genel eğriye bırakır.
    dilimler = [
        (
            dilim_anahtari(
                o.get("bagimsiz_motor_sayisi", 0), o.get("girdi_kalitesi", 0.0)
            )
            if o.get("dilim_bilinir", True)
            else DILIM_BILINMIYOR
        )
        for o in ornekler
    ]
    kaynak_sayimi = {
        "duzeltme": sum(1 for o in ornekler if o["kaynak"] == "duzeltme"),
        "onay": sum(1 for o in ornekler if o["kaynak"] == "onay"),
    }
    dogru_sayi = int(sum(etiket))
    yanlis_sayi = len(etiket) - dogru_sayi

    if len(ornekler) < asgari_ornek:
        return {
            "uygulandi": False,
            "ornek": len(ornekler),
            "neden": (
                f"Yetersiz örnek: {len(ornekler)}/{asgari_ornek}. "
                "Daha fazla öğretmen düzeltmesi/onayı gerekli."
            ),
            "kaynak_sayimi": kaynak_sayimi,
        }
    if dogru_sayi < asgari_sinif or yanlis_sayi < asgari_sinif:
        return {
            "uygulandi": False,
            "ornek": len(ornekler),
            "dogru": dogru_sayi,
            "yanlis": yanlis_sayi,
            "neden": (
                f"Sınıf dengesi yetersiz (doğru={dogru_sayi}, yanlış={yanlis_sayi}); "
                f"her sınıftan en az {asgari_sinif} örnek gerekli."
            ),
            "kaynak_sayimi": kaynak_sayimi,
        }

    cikti_yolu = Path(cikti_yolu)
    eski = (
        KosulluGuvenKalibrasyonu.yukle(cikti_yolu)
        if cikti_yolu.exists()
        else KosulluGuvenKalibrasyonu()
    )

    # Katmanlı train/validation ayrımı: kabul kararı held-out küme üzerinde
    # verilir (örnek-içi Brier yanıltıcıdır; aday kendi eğitim verisine daima
    # daha iyi uyar). Kabul edilirse dağıtılan eğri TÜM veriyle yeniden eğitilir.
    import random

    rng = random.Random(0)
    poz = [i for i, e in enumerate(etiket) if e == 1]
    neg = [i for i, e in enumerate(etiket) if e == 0]
    rng.shuffle(poz)
    rng.shuffle(neg)

    def _bol(idxler: list[int]) -> tuple[list[int], list[int]]:
        kesim = max(1, round(len(idxler) * 0.2))
        return idxler[kesim:], idxler[:kesim]  # (egitim, dogrulama)

    poz_egt, poz_dog = _bol(poz)
    neg_egt, neg_dog = _bol(neg)
    egt_idx, dog_idx = poz_egt + neg_egt, poz_dog + neg_dog
    ham_egt = [ham[i] for i in egt_idx]
    etiket_egt = [etiket[i] for i in egt_idx]
    dilim_egt = [dilimler[i] for i in egt_idx]
    ham_dog = [ham[i] for i in dog_idx]
    etiket_dog = [etiket[i] for i in dog_idx]
    dilim_dog = [dilimler[i] for i in dog_idx]

    aday = KosulluGuvenKalibrasyonu().egit_dilimli(ham_egt, etiket_egt, dilim_egt)
    # Kabul kararı tek noktadan: dilim seçimi dahil TOPLAM held-out Brier.
    aday_dog = aday.metrikler(ham_dog, etiket_dog, dilim_dog)
    eski_dog = eski.metrikler(ham_dog, etiket_dog, dilim_dog)
    iyilesme = aday_dog["brier"] < eski_dog["brier"]

    # Dağıtılacak eğri: kabul edilirse tüm veriyle yeniden eğitilir.
    yeni = KosulluGuvenKalibrasyonu().egit_dilimli(ham, etiket, dilimler)
    yeni_metrik = yeni.metrikler(ham, etiket, dilimler)

    sonuc = {
        "uygulandi": False,
        "ornek": len(ornekler),
        "dogru": dogru_sayi,
        "yanlis": yanlis_sayi,
        "kaynak_sayimi": kaynak_sayimi,
        "ece": yeni_metrik["ece"],
        "brier": yeni_metrik["brier"],
        "dogrulama_brier": aday_dog["brier"],
        "onceki_dogrulama_brier": eski_dog["brier"],
        "dilimler": {ad: e.ornek_sayisi for ad, e in yeni.dilimler.items()},
    }
    if not iyilesme:
        sonuc["neden"] = (
            f"Doğrulama Brier'i ({aday_dog['brier']}) mevcut eğriden "
            f"({eski_dog['brier']}) iyi değil; uygulanmadı."
        )
        return sonuc
    if kuru:
        sonuc["neden"] = "Kuru çalıştırma: eğri iyileşiyor ama yazılmadı."
        return sonuc

    with _KALIBRASYON_KILIDI:
        cikti_yolu.parent.mkdir(parents=True, exist_ok=True)
        if cikti_yolu.exists():
            onceki_yolu = cikti_yolu.with_suffix(".onceki.json")
            onceki_yolu.write_text(
                cikti_yolu.read_text(encoding="utf-8"), encoding="utf-8"
            )
        # Süreçler-arası (CLI + webapp) çakışmayı önlemek için pid'li geçici ad;
        # os.replace atomik olduğundan hedef dosya her an tutarlı kalır.
        gecici = cikti_yolu.with_suffix(f".{os.getpid()}.tmp")
        yeni.kaydet(gecici)
        os.replace(gecici, cikti_yolu)
        sonuc["uygulandi"] = True
        sonuc["cikti"] = str(cikti_yolu)
        sonuc["neden"] = "Kalibrasyon güncellendi (Brier iyileşti)."
        # Metrik sidecar'ı nihai sonucu (uygulandi=True dahil) yansıtsın.
        cikti_yolu.with_suffix(".metrikler.json").write_text(
            json.dumps(sonuc, ensure_ascii=False, indent=2), encoding="utf-8"
        )
    return sonuc

