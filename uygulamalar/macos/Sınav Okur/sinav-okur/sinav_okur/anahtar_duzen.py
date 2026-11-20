"""Cevap anahtarı kurma ve düzenleme: form girdisi → ``CevapAnahtari``.

Bu mantık daha önce webapp'in "yazılıyı tanıt" akışına gömülüydü; anahtar
düzenleyici de aynı dönüşüme ihtiyaç duyduğu için buraya taşındı. İki giriş
noktası vardır:

* ``formdan_anahtar_uret`` — öğretmenin elle yazdığı satırlardan anahtar kurar.
* ``rag_anahtarini_kur`` — yerel RAG'ın ürettiği yapısal cevaptan anahtar kurar
  (üretilen anahtar ``taslak`` durumundadır; öğretmen onaylamadan otomatik
  puanlama kesinleşmez).

Ayrıca ``anahtar_etkisini_onizle`` bir anahtar değişikliğinin mevcut kâğıtlara
etkisini **depoya hiçbir şey yazmadan** hesaplar.
"""

from __future__ import annotations

import re

from .modeller import CevapAnahtari, RubrikKalemi, Sinav, SoruTipi
from .yeniden_puanlama import metni_puanla, referans_pasajlari_getir

# Anahtar satırları: satır sonu veya noktalı virgülle ayrılır.
_SATIR_AYRACI = re.compile(r"[\n;]+")
# Eşleştirme satırı: "A = 1", "A: 1", "A -> 1", "A → 1"
_ESLESTIRME_AYRACI = re.compile(r"\s*(?:=|:|->|→)\s*")

DOGRUDAN_TIPLER = {SoruTipi.BOSLUK_DOLDURMA, SoruTipi.COKTAN_SECMELI}
YAPISAL_TIPLER = {
    SoruTipi.BOSLUK_DOLDURMA,
    SoruTipi.COKTAN_SECMELI,
    SoruTipi.SIRALAMA,
    SoruTipi.ESLESTIRME,
    SoruTipi.SAYISAL,
    SoruTipi.FORMUL_ISPAT,
}


def anahtar_satirlari(ham: str) -> list[str]:
    """Serbest metin anahtar girdisini satırlara böler."""
    return [x.strip() for x in _SATIR_AYRACI.split(ham or "") if x.strip()]


def eslestirmeleri_coz(satirlar: list[str]) -> dict[str, str]:
    """"A = 1" biçimli satırlardan eşleştirme sözlüğü kurar."""
    eslestirmeler: dict[str, str] = {}
    for satir in satirlar:
        parcalar = _ESLESTIRME_AYRACI.split(satir, maxsplit=1)
        if len(parcalar) == 2 and parcalar[0].strip() and parcalar[1].strip():
            eslestirmeler[parcalar[0].strip()] = parcalar[1].strip()
    return eslestirmeler


def rubrik_kur(
    satirlar: list[str],
    puan: float,
    *,
    esanlamlilar: list[list[str]] | None = None,
    kategoriler: list[str] | None = None,
    celiskiler: list[list[str]] | None = None,
) -> list[RubrikKalemi]:
    """Satırları eşit puanlı rubrik kalemlerine böler (artık son kaleme gider)."""
    if not satirlar:
        return []
    parca = puan / len(satirlar)
    kalemler = []
    for i, metin in enumerate(satirlar):
        kalem_puani = (
            puan - parca * (len(satirlar) - 1) if i == len(satirlar) - 1 else parca
        )
        kalemler.append(
            RubrikKalemi(
                metin=metin,
                puan=kalem_puani,
                esanlamlilar=(
                    esanlamlilar[i]
                    if esanlamlilar and i < len(esanlamlilar)
                    else []
                ),
                kategori=(
                    kategoriler[i]
                    if kategoriler and i < len(kategoriler)
                    else "kavram"
                ),
                celiskiler=(
                    celiskiler[i] if celiskiler and i < len(celiskiler) else []
                ),
            )
        )
    return kalemler


def formdan_anahtar_uret(
    tip: SoruTipi, puan: float, satirlar: list[str]
) -> tuple[SoruTipi, CevapAnahtari]:
    """Öğretmenin yazdığı satırlardan anahtar kurar.

    Öğretmenin kendi yazdığı anahtar doğrudan ``onayli`` sayılır. Eşleştirme
    tipinde ayrıştırılabilir çift bulunamazsa tip kısa cevaba düşürülür —
    yanlış yapısal kesinlik üretilmez.
    """
    if tip in DOGRUDAN_TIPLER:
        return tip, CevapAnahtari(dogru_cevaplar=satirlar, onay_durumu="onayli")
    if tip == SoruTipi.SIRALAMA:
        return tip, CevapAnahtari(siralama=satirlar, onay_durumu="onayli")
    if tip == SoruTipi.ESLESTIRME:
        eslestirmeler = eslestirmeleri_coz(satirlar)
        if eslestirmeler:
            return tip, CevapAnahtari(
                eslestirmeler=eslestirmeler, onay_durumu="onayli"
            )
        tip = SoruTipi.KISA_CEVAP  # çift çıkarılamadı → rubrikle puanla
    if tip in {SoruTipi.SAYISAL, SoruTipi.FORMUL_ISPAT}:
        return tip, CevapAnahtari(
            dogru_cevaplar=satirlar, onay_durumu="onayli"
        )
    return tip, CevapAnahtari(
        rubrik=rubrik_kur(satirlar, puan),
        ornek_cevap="\n".join(satirlar),
        uretim_yontemi="Öğretmen",
        onay_durumu="onayli",
    )


def rag_anahtarini_kur(
    tip: SoruTipi, puan: float, rag_cevabi
) -> tuple[SoruTipi, CevapAnahtari]:
    """Yerel RAG cevabından taslak anahtar kurar (öğretmen onayı bekler)."""
    satirlar = list(rag_cevabi.rubrik)
    kanitlar = [{"kaynak": x} for x in rag_cevabi.kaynaklar]
    if tip in DOGRUDAN_TIPLER:
        return tip, CevapAnahtari(
            dogru_cevaplar=satirlar,
            onay_durumu="taslak",
            kaynak_kanitlari=kanitlar,
        )
    if tip == SoruTipi.SIRALAMA:
        return tip, CevapAnahtari(
            siralama=satirlar, onay_durumu="taslak", kaynak_kanitlari=kanitlar
        )
    if tip == SoruTipi.ESLESTIRME:
        eslestirmeler = eslestirmeleri_coz(satirlar)
        if eslestirmeler:
            return tip, CevapAnahtari(
                eslestirmeler=eslestirmeler, onay_durumu="taslak"
            )
        tip = SoruTipi.KISA_CEVAP
    if tip in {SoruTipi.SAYISAL, SoruTipi.FORMUL_ISPAT}:
        return tip, CevapAnahtari(
            dogru_cevaplar=[
                rag_cevabi.cevap,
                *(rag_cevabi.kabul_edilen_alternatifler or []),
            ],
            yontem_adimlari=rag_cevabi.yontem_adimlari or [],
            birimler=rag_cevabi.birimler or [],
            onay_durumu="taslak",
            kaynak_kanitlari=kanitlar,
        )
    return tip, CevapAnahtari(
        rubrik=rubrik_kur(
            satirlar,
            puan,
            esanlamlilar=rag_cevabi.rubrik_es_anlamlilari,
            kategoriler=rag_cevabi.rubrik_kategorileri,
            celiskiler=rag_cevabi.rubrik_celiskileri,
        ),
        ornek_cevap=rag_cevabi.cevap,
        kaynaklar=rag_cevabi.kaynaklar,
        uretim_yontemi=rag_cevabi.uretim_yontemi,
        otomatik_uretildi=True,
        otomatik_puanlama=rag_cevabi.puanlanabilir,
        uyari=rag_cevabi.uyari,
        kabul_edilen_alternatifler=rag_cevabi.kabul_edilen_alternatifler or [],
        yaygin_hatalar=rag_cevabi.yaygin_hatalar or [],
        yasak_celiskiler=rag_cevabi.yasak_celiskiler or [],
        yontem_adimlari=rag_cevabi.yontem_adimlari or [],
        birimler=rag_cevabi.birimler or [],
        onay_durumu="taslak",
        kaynak_kanitlari=kanitlar,
    )


def anahtar_etkisini_onizle(
    depo,
    mevcut: Sinav,
    yeni: Sinav,
    gomlemci=None,
    *,
    referans_indeks_dizini=None,
) -> dict:
    """Yeni anahtarın mevcut kâğıtlara etkisini hesaplar; DEPOYA YAZMAZ.

    Her kutunun geçerli metni yeni anahtarla kuru puanlanır ve mevcut puanla
    karşılaştırılır. Öğretmen "uygula" demeden hiçbir şey değişmez.

    ``referans_indeks_dizini`` uygulama yolundaki (``kutuyu_yeniden_puanla``)
    ile aynı verilmelidir: kitap RAG pasajları puanlamaya giriyorsa önizleme
    de onlarla hesaplamalı, yoksa öğretmen gördüğünden farklı bir sonuç uygulanır.
    """
    sorular = {s.no: s for s in yeni.sorular}
    # Uygulama yolu onaylı kabul yazımlarını kullanıyor; önizleme de aynı
    # girdiyi almazsa öğretmen kararını yanlış bilgiyle verir.
    kabuller: dict[int, list[str]] = {
        no: [
            k["yazim"]
            for k in depo.ogrenilmis_kabuller(
                mevcut.kimlik, no, onay_durumu="onayli"
            )
        ]
        for no in sorular
    }
    soru_ozetleri: dict[int, dict] = {}
    ornekler: list[dict] = []
    pasaj_onbellegi: dict[int, list[str]] = {}
    for satir in depo.sinav_cevaplari(mevcut.kimlik):
        no = int(satir["soru_no"])
        if no not in sorular:
            continue
        if no not in pasaj_onbellegi:
            pasaj_onbellegi[no] = referans_pasajlari_getir(
                referans_indeks_dizini, sorular[no].metin
            )
        metin = str(
            satir["duzeltilmis_metin"]
            if satir["duzeltilmis_metin"] is not None
            else satir["taninan_metin"] or ""
        )
        yeni_sonuc = metni_puanla(
            yeni,
            no,
            metin,
            ogrenilmis_kabuller=kabuller.get(no),
            gomlemci=gomlemci,
            referans_pasajlari=pasaj_onbellegi[no],
        )
        eski_puan = float(satir["son_puan"] or 0.0)
        delta = yeni_sonuc.puan - eski_puan
        ozet = soru_ozetleri.setdefault(
            no,
            {
                "soru_no": no,
                "etkilenen_kagit": 0,
                "yukselen": 0,
                "dusen": 0,
                "toplam_delta": 0.0,
            },
        )
        if abs(delta) > 1e-9:
            ozet["etkilenen_kagit"] += 1
            ozet["toplam_delta"] += delta
            if delta > 0:
                ozet["yukselen"] += 1
            else:
                ozet["dusen"] += 1
            ornekler.append(
                {
                    "soru_no": no,
                    "kagit_id": satir["kagit_id"],
                    "kutu_id": satir["id"],
                    "metin": metin[:160],
                    "eski_puan": round(eski_puan, 2),
                    "yeni_puan": round(yeni_sonuc.puan, 2),
                    "delta": round(delta, 2),
                }
            )
    for ozet in soru_ozetleri.values():
        ozet["ortalama_delta"] = (
            round(ozet["toplam_delta"] / ozet["etkilenen_kagit"], 2)
            if ozet["etkilenen_kagit"]
            else 0.0
        )
        ozet["toplam_delta"] = round(ozet["toplam_delta"], 2)
    ornekler.sort(key=lambda x: -abs(x["delta"]))
    return {
        "sorular": [soru_ozetleri[no] for no in sorted(soru_ozetleri)],
        "ornekler": ornekler[:10],
        "toplam_etkilenen": sum(
            o["etkilenen_kagit"] for o in soru_ozetleri.values()
        ),
    }
