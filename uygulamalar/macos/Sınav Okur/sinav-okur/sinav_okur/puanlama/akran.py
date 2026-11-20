"""Akran uzlaşması: benzer cevaplara benzer puan ilkesini geri besleme.

``analiz.py`` benzer cevap–farklı puan çiftlerini zaten raporluyordu ama
puanlama kararına hiç dönmüyordu. Bu modül soru bazında cevapları kümeler
ve öğretmenin **elle dokunduğu** kutuları çapa alır: çapa medyanından
belirgin sapan otomatik puanlar incelemeye işaretlenir.

**Puan asla otomatik değiştirilmez.** Yalnız `incele=True` + `kararlar_json`
içinde bir öneri bırakılır; böylece güvenlik kapısı sözleşmesi ve denetim
izi korunur.
"""

from __future__ import annotations

import statistics

from rapidfuzz import fuzz

from ..metin import eslesme_bicimi

# Küme eşiği analiz.py ile aynı: öğretmenin gördüğü uyarı ile buradaki
# küme örtüşsün.
KUME_ESIGI = 88
GOMME_ESIGI = 0.82
ASGARI_UZUNLUK = 8


def _elle_dokunuldu(satir, duzeltilen_kutular: set[int] | None = None) -> bool:
    """Öğretmen bu kutuya müdahale etmiş mi?

    ``duzeltilmis_metin`` dolu olması TEK BAŞINA yeterli değildir: program
    yeniden puanlarken de o alanı yazıyor. Gerçek kanıt ya
    ``duzeltme_ogrenimi`` kaydı ya da otomatik puandan sapan bir son puandır.
    """
    if duzeltilen_kutular and int(satir["id"]) in duzeltilen_kutular:
        return True
    otomatik = satir["otomatik_puan"]
    son = satir["son_puan"]
    if otomatik is None or son is None:
        return False
    return abs(float(son) - float(otomatik)) > 1e-6


def akran_kumeleri(cevaplar: list, gomlemci=None) -> list[list]:
    """Cevapları yazım (ve varsa anlam) benzerliğine göre kümeler.

    Birleşik-bul yerine doğrudan küme temsilcisiyle karşılaştırma kullanılır;
    tek soruda cevap sayısı sınıf mevcudu kadar olduğundan yeterlidir.
    """
    kumeler: list[list] = []
    temsilciler: list[str] = []
    vektorler: dict[int, object] = {}
    if gomlemci is not None:
        try:
            metinler = [
                eslesme_bicimi(
                    str(c["duzeltilmis_metin"] or c["taninan_metin"] or "")
                )
                for c in cevaplar
            ]
            gomuler = gomlemci.gom(metinler)
            vektorler = {i: gomuler[i] for i in range(len(cevaplar))}
        except Exception:
            vektorler = {}

    for i, cevap in enumerate(cevaplar):
        metin = eslesme_bicimi(
            str(cevap["duzeltilmis_metin"] or cevap["taninan_metin"] or "")
        )
        yerlesti = False
        if metin and len(metin) >= ASGARI_UZUNLUK:
            for k, temsilci in enumerate(temsilciler):
                if not temsilci:
                    continue
                benzer = fuzz.token_set_ratio(metin, temsilci) >= KUME_ESIGI
                if not benzer and vektorler:
                    from .gomme import kosinus

                    ilk_indeks = kumeler[k][0]["_indeks"]
                    try:
                        benzer = (
                            float(
                                kosinus(
                                    vektorler[i].reshape(1, -1),
                                    vektorler[ilk_indeks].reshape(1, -1),
                                ).max()
                            )
                            >= GOMME_ESIGI
                        )
                    except Exception:
                        benzer = False
                if benzer:
                    kumeler[k].append({"satir": cevap, "_indeks": i})
                    yerlesti = True
                    break
        if not yerlesti:
            kumeler.append([{"satir": cevap, "_indeks": i}])
            # Kısa metin temsilci OLAMAZ: `token_set_ratio` alt kümede 100
            # döndürdüğü için "ATP" temsilcisi "ATP hücrede mitokondride
            # üretilir" cevabını da kendi kümesine çeker ve öğretmene yanlış
            # bir tutarsızlık uyarısı gösterilir.
            temsilciler.append(metin if len(metin) >= ASGARI_UZUNLUK else "")
    return [[u["satir"] for u in kume] for kume in kumeler]


def akran_uzlasmasini_degerlendir(
    depo, sinav, soru_no: int | None = None, gomlemci=None, uygula: bool = False
) -> dict:
    """Kümeleri çapa puanına göre denetler; sapan kutulara öneri bırakır.

    ``uygula=False`` ise yalnız rapor üretilir (kuru çalıştırma).
    """
    satirlar: dict[int, list] = {}
    for satir in depo.sinav_cevaplari(sinav.kimlik):
        satirlar.setdefault(int(satir["soru_no"]), []).append(satir)
    # Gerçek öğretmen düzeltmeleri çapa kaynağıdır.
    duzeltilen = {
        int(d["kutu_id"]) for d in depo.duzeltme_ornekleri(sinav.kimlik)
    }

    isaretlenen: list[dict] = []
    incelenen_kume = 0
    for soru in sinav.sorular:
        if soru_no is not None and soru.no != soru_no:
            continue
        soru_satirlari = satirlar.get(soru.no, [])
        if len(soru_satirlari) < 2:
            continue
        for kume in akran_kumeleri(soru_satirlari, gomlemci):
            if len(kume) < 2:
                continue
            capalar = [k for k in kume if _elle_dokunuldu(k, duzeltilen)]
            if not capalar:
                continue  # öğretmen kararı yoksa kıyaslanacak doğru yok
            incelenen_kume += 1
            capa_puanlari = [float(k["son_puan"] or 0) for k in capalar]
            medyan = statistics.median(capa_puanlari)
            mad = statistics.median([abs(p - medyan) for p in capa_puanlari])
            if mad > max(1.0, float(soru.puan) * 0.18):
                continue  # çapaların kendisi tutarsız; öneri üretme
            esik = max(2.0, float(soru.puan) * 0.20)
            for kutu in kume:
                if _elle_dokunuldu(kutu, duzeltilen):
                    continue
                sapma = abs(float(kutu["son_puan"] or 0) - medyan)
                if sapma < esik:
                    continue
                oneri = {
                    "tur": "akran_uzlasmasi",
                    "soru_no": soru.no,
                    "kutu_id": kutu["id"],
                    "kagit_id": kutu["kagit_id"],
                    "mevcut_puan": float(kutu["son_puan"] or 0),
                    "onerilen_puan": round(medyan * 2) / 2,
                    "kume_boyu": len(kume),
                    "capa_sayisi": len(capalar),
                }
                isaretlenen.append(oneri)
                if uygula:
                    # Puan DEĞİŞTİRİLMEZ; yalnız inceleme işareti konur.
                    depo.kutu_guncelle(
                        kutu_id=kutu["id"],
                        incele=True,
                        neden=(
                            "Akran uzlaşması: benzer cevaplara öğretmen "
                            f"{oneri['onerilen_puan']:g} puan vermişti"
                        ),
                        aktor="program",
                    )
    return {
        "isaretlenen": isaretlenen,
        "kume_sayisi": incelenen_kume,
        "uygulandi": bool(uygula),
    }
