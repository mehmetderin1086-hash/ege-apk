"""Sınavın kendisinin kalitesini ölçen istatistikler.

Mevcut analiz katmanı soru güçlüğünü ve kaba ayırt ediciliği (üst %27 − alt
%27) hesaplıyordu; ama "bu sınav öğrencileri tutarlı biçimde ayırıyor mu"
sorusunu cevaplayan tek sayı (güvenilirlik katsayısı) ve az örneklemde de
çalışan madde-toplam korelasyonu yoktu.

**Az örneklem sözleşmesi:** hiçbir fonksiyon sayı uydurmaz. Yeterli veri
yoksa ``{"deger": None, "neden": "yetersiz_ornek", ...}`` döner; arayüz bunu
"yetersiz örneklem" diye gösterir. Mevcut ``analiz.ayirt_edicilik`` deseniyle
aynıdır — 8 kâğıtlık bir sınavda 0.31'lik bir güvenilirlik katsayısı yazmak,
bilgi değil yanlış güven üretir.
"""

from __future__ import annotations

import statistics

# Cronbach α / KR-20 için gereken asgari kâğıt ve soru sayısı. Altında
# katsayı örneklem gürültüsünden ibarettir.
YETERLI_KAGIT = 10
YETERLI_SORU = 5
# Puanlayıcı uyumu (program ↔ öğretmen) için gereken düzeltme sayısı.
YETERLI_DUZELTME = 20

# Yorum bantları (öğretmene düz Türkçe karşılığıyla gösterilir).
# En alttaki bant -1.0'dan başlar: α negatif olabilir (sorular birbiriyle
# ters ilişkiliyse) ve o durum da adlandırılmalı, aksi hâlde bant araması
# eşleşme bulamaz.
ALFA_BANTLARI = (
    (0.80, "iyi", "Sınav öğrencileri tutarlı biçimde ayırıyor."),
    (0.70, "kabul", "Kabul edilebilir; birkaç soru zayıf olabilir."),
    (0.60, "zayif", "Zayıf: sorular farklı şeyleri ölçüyor olabilir."),
    (-1.0, "guvenilmez", "Güvenilmez: sorular tutarlı bir bütün ölçmüyor."),
)
# Madde-toplam korelasyonu bantları.
RPBIS_IYI = 0.30
RPBIS_SINIRDA = 0.20


def _yetersiz(neden: str, gereken: int, mevcut: int) -> dict:
    return {
        "deger": None,
        "neden": neden,
        "gereken": gereken,
        "mevcut": mevcut,
    }


def puan_matrisi(depo, sinav) -> tuple[dict[int, dict[int, float]], dict[int, float]]:
    """``{kagit_id: {soru_no: puan}}`` ve ``{soru_no: azami_puan}``.

    Öğretmenin kesinleştirdiği puan (``son_puan``) esas alınır; yoksa
    program puanı kullanılır.
    """
    matris: dict[int, dict[int, float]] = {}
    azamiler: dict[int, float] = {s.no: float(s.puan) for s in sinav.sorular}
    for satir in depo.sinav_cevaplari(sinav.kimlik):
        soru_no = int(satir["soru_no"])
        if soru_no not in azamiler:
            continue
        puan = satir["son_puan"]
        if puan is None:
            puan = satir["otomatik_puan"]
        if puan is None:
            continue
        matris.setdefault(int(satir["kagit_id"]), {})[soru_no] = float(puan)
    return matris, azamiler


def _tam_kagitlar(matris: dict, azamiler: dict) -> list[dict[int, float]]:
    """Her sorusu puanlanmış kâğıtlar (eksik veri katsayıyı bozar)."""
    sorular = set(azamiler)
    return [p for p in matris.values() if sorular.issubset(p)]


def cronbach_alfa(matris: dict, azamiler: dict) -> dict:
    """Sınav güvenilirliği (α). İkili puanlarda KR-20 bunun özel hâlidir.

    Rubrikle kısmi puan verildiği için genel formül (α) kullanılır; arayüzde
    tek ad kullanılmalı, "KR-20" ayrı bir sayı gibi sunulmamalıdır.
    """
    kagitlar = _tam_kagitlar(matris, azamiler)
    if len(kagitlar) < YETERLI_KAGIT:
        return _yetersiz("yetersiz_kagit", YETERLI_KAGIT, len(kagitlar))
    if len(azamiler) < YETERLI_SORU:
        return _yetersiz("yetersiz_soru", YETERLI_SORU, len(azamiler))

    soru_nolari = sorted(azamiler)
    madde_varyanslari = []
    for no in soru_nolari:
        degerler = [k[no] for k in kagitlar]
        madde_varyanslari.append(statistics.variance(degerler))
    toplamlar = [sum(k[no] for no in soru_nolari) for k in kagitlar]
    toplam_varyans = statistics.variance(toplamlar)
    if toplam_varyans <= 0:
        # Herkes aynı toplamı almış: ayırt edicilik yok, katsayı tanımsız.
        return _yetersiz("varyans_yok", 1, 0)

    k = len(soru_nolari)
    alfa = (k / (k - 1)) * (1 - sum(madde_varyanslari) / toplam_varyans)
    alfa = max(-1.0, min(1.0, alfa))
    band, yorum = next(
        (ad, metin) for esik, ad, metin in ALFA_BANTLARI if alfa >= esik
    )
    return {
        "deger": round(alfa, 3),
        "band": band,
        "yorum": yorum,
        "kagit": len(kagitlar),
        "soru": k,
    }


def madde_toplam_korelasyonu(matris: dict, azamiler: dict) -> dict[int, dict]:
    """Her soru için DÜZELTİLMİŞ madde-toplam korelasyonu (r_pbis).

    "Düzeltilmiş": sorunun kendi puanı toplamdan çıkarılır, yoksa her soru
    kendisiyle korelasyon gösterip yapay olarak yüksek çıkar.

    Negatif değer güçlü bir sinyaldir: soruyu bilenler sınavın genelinde
    daha KÖTÜ; çoğunlukla anahtar hatalıdır.
    """
    kagitlar = _tam_kagitlar(matris, azamiler)
    sonuc: dict[int, dict] = {}
    for no in sorted(azamiler):
        if len(kagitlar) < YETERLI_KAGIT:
            sonuc[no] = _yetersiz("yetersiz_kagit", YETERLI_KAGIT, len(kagitlar))
            continue
        madde = [k[no] for k in kagitlar]
        kalan = [sum(v for s, v in k.items() if s != no) for k in kagitlar]
        if statistics.variance(madde) <= 0 or statistics.variance(kalan) <= 0:
            sonuc[no] = _yetersiz("varyans_yok", 1, 0)
            continue
        r = statistics.correlation(madde, kalan)
        band = (
            "iyi" if r >= RPBIS_IYI
            else "sinirda" if r >= RPBIS_SINIRDA
            else "zayif" if r >= 0
            else "anahtar_supheli"
        )
        sonuc[no] = {"deger": round(r, 3), "band": band}
    return sonuc


def puan_dagilimi(matris: dict, azamiler: dict) -> dict:
    """Toplam puanların merkezî eğilimi ve yayılımı."""
    kagitlar = _tam_kagitlar(matris, azamiler)
    if not kagitlar:
        return _yetersiz("kagit_yok", 1, 0)
    toplamlar = [sum(k.values()) for k in kagitlar]
    azami = sum(azamiler.values())
    sonuc = {
        "ornek": len(toplamlar),
        "ortalama": round(statistics.mean(toplamlar), 2),
        "medyan": round(statistics.median(toplamlar), 2),
        "en_dusuk": round(min(toplamlar), 2),
        "en_yuksek": round(max(toplamlar), 2),
        "azami": round(azami, 2),
    }
    sonuc["standart_sapma"] = (
        round(statistics.stdev(toplamlar), 2) if len(toplamlar) > 1 else None
    )
    return sonuc


def puanlayici_uyumu(duzeltmeler: list[dict], azamiler: dict) -> dict:
    """Program puanı ile öğretmenin verdiği puan ne kadar örtüşüyor?

    ``duzeltme_ogrenimi`` kayıtları zaten birikiyor; bu, veri gelmeden
    hesaplanabilen tek doğruluk ölçüsüdür.
    """
    ciftler = [
        (float(d["otomatik_puan"]), float(d["son_puan"]))
        for d in duzeltmeler
        if d.get("otomatik_puan") is not None and d.get("son_puan") is not None
    ]
    if len(ciftler) < YETERLI_DUZELTME:
        return _yetersiz("yetersiz_duzeltme", YETERLI_DUZELTME, len(ciftler))
    farklar = [ogretmen - program for program, ogretmen in ciftler]
    mutlak = [abs(f) for f in farklar]
    return {
        "ornek": len(ciftler),
        "mae": round(statistics.mean(mutlak), 3),
        # Sistematik sapma: program tutarlı biçimde cömert mi, cimri mi?
        "sistematik_sapma": round(statistics.mean(farklar), 3),
        "tam_uyum_orani": round(
            sum(1 for f in mutlak if f < 0.01) / len(mutlak), 4
        ),
        "iki_puan_icinde": round(
            sum(1 for f in mutlak if f <= 2) / len(mutlak), 4
        ),
    }


def sinav_psikometrisi(depo, sinav, duzeltmeler: list[dict] | None = None) -> dict:
    """Tüm psikometrik ölçüleri tek çağrıda toplar."""
    matris, azamiler = puan_matrisi(depo, sinav)
    return {
        "guvenilirlik": cronbach_alfa(matris, azamiler),
        "madde_korelasyonu": madde_toplam_korelasyonu(matris, azamiler),
        "dagilim": puan_dagilimi(matris, azamiler),
        "puanlayici_uyumu": puanlayici_uyumu(duzeltmeler or [], azamiler),
    }
