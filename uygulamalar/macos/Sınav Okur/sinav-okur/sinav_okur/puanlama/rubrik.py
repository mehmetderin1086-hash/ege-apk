"""Rubrik tabanlı puanlama: kısa cevap ve açık uçlu sorular için ortak motor.

Her rubrik kalemi cevapta iki katmanla aranır:
1. Sözcüksel: rapidfuzz partial_ratio ile kalemin (ve eş anlamlılarının)
   cevap metni içinde geçip geçmediği.
2. Anlamsal: gömlemci varsa, kalem ile cevabın cümleleri arasındaki en yüksek
   kosinüs benzerliği. Sözcüksel katman kaçırdığında devreye girer
   ("mitokondri enerji üretir" ≈ "hücrenin enerji santralidir").

Kalem bulunursa puanı eklenir; eşiğe yakın kararlar güveni düşürür ve sonuç
insan onayına işaretlenir.
"""

from __future__ import annotations

import re

from rapidfuzz import fuzz

from ..metin import aksansiz, cumleler, eslesme_bicimi
from ..modeller import PuanSonucu, RubrikKalemi, Soru
from .ayarlar import PuanlamaAyar
from .gomme import Gomlemci, kosinus

_KAPSAMA_DURAK = {
    "ama", "bir", "bu", "da", "de", "ile", "ise", "ve", "veya", "olarak",
    "içerisine", "içerisinde", "içine", "içinde",
}
_TURKCE_EKLER = (
    "larının", "lerinin", "lardan", "lerden", "mıştır", "miştir", "muştur",
    "müştür", "ları", "leri", "ların", "lerin", "dır", "dir", "dur", "dür",
    "tır", "tir", "tur", "tür", "dan", "den", "nin", "nın", "nun", "nün",
    "lar", "ler", "ın", "in", "un", "ün", "dı", "di", "du", "dü", "tı",
    "ti", "tu", "tü", "da", "de", "ta", "te",
)
_SIRA_SAYILARI = {
    "1": "birinci",
    "2": "ikinci",
    "3": "üçüncü",
    "4": "dördüncü",
    "5": "beşinci",
    "6": "altıncı",
}


def govde(kelime: str) -> str:
    """Sözcüğü basit Türkçe çekim eklerinden arındırır (kaba gövdeleme)."""
    for ek in _TURKCE_EKLER:
        if kelime.endswith(ek) and len(kelime) - len(ek) >= 3:
            return kelime[: -len(ek)]
    return kelime


# Modül içi eski ad; terim sözlüğü modülü public ``govde``yi kullanır.
_govde = govde


def _ifade_kapsama_skoru(bicim: str, cevap: str) -> float:
    """Kısa eşdeğer ifadelerde Türkçe çekim eklerini tolere et."""
    aranan = [
        _govde(k)
        for k in eslesme_bicimi(bicim).split()
        if len(k) >= 3 and k not in _KAPSAMA_DURAK
    ]
    if not 2 <= len(aranan) <= 8:
        return 0.0
    cevap_kelimeleri = eslesme_bicimi(cevap).split()
    cevap_govdeleri = [
        _govde(k)
        for k in (
            _SIRA_SAYILARI.get(k, k)
            for k in cevap_kelimeleri
        )
        if len(k) >= 3
    ]
    for kok in aranan:
        if not any(
            kok == aday
            or (
                min(len(kok), len(aday)) >= 4
                and fuzz.ratio(kok, aday) >= 88
            )
            for aday in cevap_govdeleri
        ):
            return 0.0
    return 92.0


def _ifade_kapsama_orani(bicim: str, cevap: str) -> tuple[float, int]:
    """Bir rubrik ifadesindeki ayırt edici kavramların ne kadarı cevapta var."""
    aranan = [
        _govde(k)
        for k in eslesme_bicimi(bicim).split()
        if len(k) >= 3 and k not in _KAPSAMA_DURAK
    ]
    aranan = list(dict.fromkeys(aranan))
    cevap_govdeleri = [
        _govde(_SIRA_SAYILARI.get(k, k))
        for k in eslesme_bicimi(cevap).split()
        if len(k) >= 3
    ]
    if len(aranan) < 2 or not cevap_govdeleri:
        return 0.0, 0
    eslesen = sum(
        1
        for kok in aranan
        if any(
            kok == aday
            or (
                min(len(kok), len(aday)) >= 4
                and fuzz.ratio(kok, aday) >= 86
            )
            for aday in cevap_govdeleri
        )
    )
    return eslesen / len(aranan), eslesen


def _kalem_kapsama(kalem: RubrikKalemi, cevap: str) -> tuple[float, int]:
    return max(
        (_ifade_kapsama_orani(bicim, cevap) for bicim in kalem.tum_bicimler()),
        default=(0.0, 0),
        key=lambda x: (x[0], x[1]),
    )


_OLUMSUZ = re.compile(
    r"\b(?:değil|degil|yok|hiçbir|hicbir)\b|"
    r"\b\w+(?:madı|medi|mamış|memiş|maz|mez|madi|mamıs|memis)"
    r"(?:tır|tir|tur|tür|dir|dır|dur|dür)?\b",
    re.IGNORECASE,
)


def _celiski_var(kalem: str, cevap: str) -> bool:
    """Açık olumlu/olumsuz yön tersliğinde benzer kelimelere kısmi puan verme."""
    return bool(_OLUMSUZ.search(kalem)) != bool(_OLUMSUZ.search(cevap))


def _en_ilgili_cumle(kalem: RubrikKalemi, cevap: str) -> str:
    """Kalemin karşılığının arandığı cümle.

    Yön tersliği, cevabın TAMAMINDA aranırsa bulaşır: doğru cevabın yanına
    eklenen doğru bir olumsuz cümle ("Kloroplast hayvan hücresinde bulunmaz")
    bütün olumlu kalemleri çelişki sayıp sıfırlıyordu. Karar, kalemin
    gerçekten karşılandığı cümlede verilmeli.
    """
    parcalar = cumleler(cevap)
    if len(parcalar) <= 1:
        return cevap
    return max(parcalar, key=lambda c: _sozcuksel_skor(kalem, c))


def _bicim_skoru(bicim_norm: str, cevap_norm: str) -> float:
    """Tek bir kalem biçiminin cevap içindeki skoru (0-100).

    Kısa biçimlerde (≤4 harf, tek kelime) ``partial_ratio`` alt-dize eşleşmesi
    yanlış pozitif verir ("su" ↔ "susuz"); bu durumda cevabı kelimelere bölüp
    kelime-bazlı tam/bulanık eşleşme kullanılır. Uzun biçimlerde kısmi eşleşme
    (cevabın bir bölümünde geçme) doğru davranıştır.
    """
    if len(bicim_norm) <= 4 and " " not in bicim_norm:
        return max((fuzz.ratio(bicim_norm, k) for k in cevap_norm.split()), default=0.0)
    return fuzz.partial_ratio(bicim_norm, cevap_norm)


def _sozcuksel_skor(kalem: RubrikKalemi, cevap: str) -> float:
    """Kalemin herhangi bir biçiminin cevap içindeki en iyi eşleşmesi (0-100)."""
    c_norm, c_aksansiz = eslesme_bicimi(cevap), aksansiz(cevap)
    en_iyi = 0.0
    for bicim in kalem.tum_bicimler():
        en_iyi = max(
            en_iyi,
            _bicim_skoru(eslesme_bicimi(bicim), c_norm),
            _bicim_skoru(aksansiz(bicim), c_aksansiz) - 4.0,
            _ifade_kapsama_skoru(bicim, cevap),
        )
    return en_iyi


def _anlamsal_skorlar(
    kalemler: list[RubrikKalemi], cevap: str, gomlemci: Gomlemci
) -> list[float]:
    """Her kalem için cevap cümleleriyle en yüksek kosinüs benzerliği."""
    parcalar = cumleler(cevap)
    if not parcalar:
        parcalar = [cevap]
    if len(cevap.split()) > 3:
        parcalar = [*parcalar, cevap]  # kısa cevaplarda bütün metni de dene

    kalem_metinleri = [k.metin for k in kalemler]
    vek = gomlemci.gom(kalem_metinleri + parcalar)
    kalem_vek, parca_vek = vek[: len(kalemler)], vek[len(kalemler):]
    benzerlik = kosinus(kalem_vek, parca_vek)  # (kalem, parça)
    return benzerlik.max(axis=1).tolist()


def _karar_guveni(skor: float, esik: float, band: float) -> float:
    """Eşikten uzaklık → karar güveni (eşiğin tam üstü/altı kararsız sayılır)."""
    return min(1.0, abs(skor - esik) / band) if band > 0 else 1.0


# Rubrik yolundan puanlanan soru tipleri: gömlemcisiz güven tavanı bunların
# hepsine uygulanır. Yalnız açık uçluya uygulamak tutarsızdı — kısa cevap,
# yorumlama, deney tasarlama ve etik de aynı sözcüksel kanıta dayanıyor.
RUBRIK_TIPLERI = frozenset(
    {"acik_uclu", "kisa_cevap", "yorumlama", "deney_tasarlama", "etik"}
)


def _anlamsal_tam_puan_verilir(
    soz: float, anl: float, ayar: PuanlamaAyar
) -> bool:
    """Anlamsal benzerlik TEK BAŞINA tam puan verebilir mi?

    Varsayılan "kurtarma" rolünde hayır: ölçümde eşdeğer ve farklı cevapların
    benzerlik dağılımları örtüşüyor, yani yüksek benzerlik "aynı şeyi söylüyor"
    demek değil. "tam" rolünde bile iki koruma vardır: yüksek eşik ve asgari
    sözcüksel destek (cevap kalemle hiç kelime paylaşmıyorsa benzerlik
    yanıltıcıdır).
    """
    if str(ayar.anlamsal_rol).casefold() != "tam":
        return False
    if anl < max(ayar.rubrik_anlamsal_esik, ayar.rubrik_anlamsal_tam_esik):
        return False
    return soz >= ayar.rubrik_sozcuksel_esik - ayar.anlamsal_tam_sozcuksel_pay


def _kismi_guven(
    soz: float, anl: float | None, kapsama: float, ayar: PuanlamaAyar
) -> float:
    """Kısmi puan kararının güveni: sabit değil, kanıtın gücüne bağlı.

    Eskiden her kısmi puan sabit 0.55 alıyordu; kavramın çoğunu yazan cevapla
    tek kelime tutturana aynı kararsızlık atanıyordu.
    """
    anl_orani = 0.0
    if anl is not None:
        anl_orani = max(
            0.0,
            min(
                1.0,
                (anl - ayar.rubrik_kismi_anlamsal_esik)
                / max(
                    0.01,
                    ayar.rubrik_anlamsal_esik - ayar.rubrik_kismi_anlamsal_esik,
                ),
            ),
        )
    soz_orani = max(
        0.0,
        min(
            1.0,
            (soz - ayar.rubrik_kismi_sozcuksel_esik)
            / max(
                1.0,
                ayar.rubrik_sozcuksel_esik - ayar.rubrik_kismi_sozcuksel_esik,
            ),
        ),
    )
    deger = 0.40 + 0.35 * kapsama + 0.15 * anl_orani + 0.10 * soz_orani
    return max(0.35, min(0.85, deger))


def _birlesik_guven(kararlar: list[dict], guvenler: list[float]) -> float:
    """Kalem güvenlerini puan ağırlıklı birleştirir.

    ``min`` almak, çok kalemli bir rubrikte tek kararsız küçük kalemin bütün
    cevabı inceleme kuyruğuna atmasına yol açıyordu. En düşük güven yine
    ağırlık taşır (%30), ama tek başına belirleyici değildir.
    """
    if not guvenler:
        return 1.0
    agirliklar = [
        max(0.0, float(k.get("max_puan", 0.0)))
        for k in kararlar[: len(guvenler)]
    ]
    toplam_agirlik = sum(agirliklar)
    if toplam_agirlik <= 0:
        return min(guvenler)
    agirlikli = (
        sum(g * a for g, a in zip(guvenler, agirliklar)) / toplam_agirlik
    )
    return 0.7 * agirlikli + 0.3 * min(guvenler)


def _sozcuksel_kanit_guclu(kararlar: list[dict], ayar: PuanlamaAyar) -> bool:
    """Her kalem net sözcüksel eşleşmeyle tam puan aldı mı?

    Böyle bir cevapta "sözcüksel tek başına zayıf kanıt" savı geçerli
    değildir; anlamsal katman yokluğu için güven tavanı uygulanmaz.
    """
    if not kararlar:
        return False
    return all(
        k.get("karar") == "tam"
        and float(k.get("sozcuksel", 0.0))
        >= ayar.rubrik_sozcuksel_esik + ayar.sozcuksel_band
        for k in kararlar
    )


def _kararsiz_puan_payi(
    kararlar: list[dict],
    guvenler: list[float],
    soru_puani: float,
    esik: float,
) -> float:
    """Güveni eşiğin altında kalan kalemlerin soru puanındaki payı."""
    if soru_puani <= 0:
        return 0.0
    riskli = sum(
        max(0.0, float(k.get("max_puan", 0.0)))
        for k, g in zip(kararlar, guvenler)
        if g < esik
    )
    return min(1.0, riskli / soru_puani)


def _kitap_ortusmesi(
    cevap: str, referans_pasajlari: list[str], gomlemci: Gomlemci
) -> float:
    """Öğrenci cevabı ile sorunun ders kitabı pasajları arasındaki en yüksek benzerlik."""
    parcalar = cumleler(cevap) or [cevap]
    vek = gomlemci.gom(referans_pasajlari + parcalar)
    pas_vek, cev_vek = vek[: len(referans_pasajlari)], vek[len(referans_pasajlari):]
    return float(kosinus(cev_vek, pas_vek).max())


def rubrik_puanla(
    cevap_metni: str,
    soru: Soru,
    gomlemci: Gomlemci | None = None,
    ayar: PuanlamaAyar | None = None,
    referans_pasajlari: list[str] | None = None,
) -> PuanSonucu:
    ayar = (ayar or PuanlamaAyar()).profil(
        soru.esneklik or soru.anahtar.esneklik
    )
    if not cevap_metni.strip():
        return PuanSonucu(0.0, soru.puan, 1.0, ["Cevap boş"], incele=False)

    kalemler = soru.anahtar.rubrik
    anlamsal: list[float] | None = None
    if gomlemci is not None:
        try:
            anlamsal = _anlamsal_skorlar(kalemler, cevap_metni, gomlemci)
        except Exception:  # gömme başarısız olursa sözcüksel katmanla devam
            anlamsal = None

    toplam, detaylar, guvenler, kararlar = 0.0, [], [], []
    zorunlu_eksik = False
    for i, kalem in enumerate(kalemler):
        soz = _sozcuksel_skor(kalem, cevap_metni)
        kapsama, eslesen_kavram = _kalem_kapsama(kalem, cevap_metni)
        anl = anlamsal[i] if anlamsal is not None else None
        acik_celiskiler = [
            ifade
            for ifade in kalem.celiskiler
            if _bicim_skoru(
                eslesme_bicimi(ifade), eslesme_bicimi(cevap_metni)
            ) >= 86
        ]
        # Yön tersliği kalemin karşılandığı cümlede aranır; kalem.celiskiler
        # ise cevabın tamamında (açık çelişki nerede geçerse geçsin gerçektir).
        ilgili_cumle = _en_ilgili_cumle(kalem, cevap_metni)
        celiski = _celiski_var(kalem.metin, ilgili_cumle) or bool(acik_celiskiler)
        verilen = 0.0
        karar = "yok"

        if not celiski and soz >= ayar.rubrik_sozcuksel_esik:
            toplam += kalem.puan
            verilen = kalem.puan
            karar = "tam"
            guvenler.append(_karar_guveni(soz, ayar.rubrik_sozcuksel_esik, ayar.sozcuksel_band))
            detaylar.append(f"✓ '{kalem.metin}' ({kalem.puan:g}p) — sözcüksel {soz:.0f}")
        elif (
            not celiski
            and anl is not None
            and _anlamsal_tam_puan_verilir(soz, anl, ayar)
        ):
            toplam += kalem.puan
            verilen = kalem.puan
            karar = "tam"
            guvenler.append(_karar_guveni(anl, ayar.rubrik_anlamsal_esik, ayar.anlamsal_band))
            detaylar.append(f"✓ '{kalem.metin}' ({kalem.puan:g}p) — anlamsal {anl:.2f}")
        elif (
            not celiski
            and (
                (
                    soz >= ayar.rubrik_kismi_sozcuksel_esik
                    and kapsama >= ayar.rubrik_kismi_kapsama_esigi
                    and eslesen_kavram >= 2
                )
                or (
                    soz >= ayar.rubrik_sozcuksel_esik - 12
                    and eslesen_kavram >= 1
                )
                or (
                    anl is not None
                    and anl >= ayar.rubrik_kismi_anlamsal_esik
                    and (soz >= 45 or eslesen_kavram >= 1)
                )
            )
        ):
            anl_oran = (
                (anl - ayar.rubrik_kismi_anlamsal_esik)
                / max(0.01, ayar.rubrik_anlamsal_esik - ayar.rubrik_kismi_anlamsal_esik)
                if anl is not None else 0.0
            )
            kismi_oran = min(
                ayar.rubrik_azami_kismi_oran,
                max(
                    0.25,
                    kapsama,
                    0.25 + 0.5 * max(
                        0.0,
                        (soz - ayar.rubrik_kismi_sozcuksel_esik)
                        / max(
                            1.0,
                            ayar.rubrik_sozcuksel_esik
                            - ayar.rubrik_kismi_sozcuksel_esik,
                        ),
                    ),
                    0.35 + 0.45 * anl_oran,
                ),
            )
            kismi_puan = round(kalem.puan * kismi_oran * 2) / 2
            kismi_puan = min(kalem.puan, max(0.5, kismi_puan))
            toplam += kismi_puan
            verilen = kismi_puan
            karar = "kismi"
            guvenler.append(_kismi_guven(soz, anl, kapsama, ayar))
            ek = f", anlamsal {anl:.2f}" if anl is not None else ""
            detaylar.append(
                f"≈ '{kalem.metin}' ({kismi_puan:g}/{kalem.puan:g}p) — "
                f"doğru mantık/yöntem izi; kavram kapsamı %{kapsama * 100:.0f}, "
                f"sözcüksel {soz:.0f}{ek}"
            )
        else:
            # RET güvenli ancak İKİ katman da eşikten net uzaksa (kabul için
            # katmanlardan birinin eşiği aşması yeterdi) → en yakın sınıra olan
            # mesafe kadar güvenli: min. Aksi halde sınırdaki parafraz sessizce
            # 0 alır, incele bayrağı kalkmaz.
            if anl is not None:
                ret_guveni = min(
                    _karar_guveni(soz, ayar.rubrik_sozcuksel_esik, ayar.sozcuksel_band),
                    _karar_guveni(anl, ayar.rubrik_anlamsal_esik, ayar.anlamsal_band),
                )
            else:
                ret_guveni = _karar_guveni(soz, ayar.rubrik_sozcuksel_esik, ayar.sozcuksel_band)
            guvenler.append(ret_guveni)
            ek = f", anlamsal {anl:.2f}" if anl is not None else ""
            detaylar.append(f"✗ '{kalem.metin}' (0/{kalem.puan:g}p) — sözcüksel {soz:.0f}{ek}")
            if kalem.zorunlu:
                zorunlu_eksik = True
        kararlar.append(
            {
                "tur": "rubrik",
                "olcut": kalem.metin,
                "kategori": kalem.kategori,
                "zorunlu": kalem.zorunlu,
                "karar": "celiski" if celiski else karar,
                "puan": verilen,
                "max_puan": kalem.puan,
                "sozcuksel": round(float(soz), 3),
                "anlamsal": round(float(anl), 4) if anl is not None else None,
                "kapsama": round(float(kapsama), 4),
                "celiskiler": acik_celiskiler,
            }
        )

    puan = min(toplam, soru.puan)
    guven = _birlesik_guven(kararlar, guvenler)
    if (
        anlamsal is None
        and soru.tip.value in RUBRIK_TIPLERI
        and not _sozcuksel_kanit_guclu(kararlar, ayar)
    ):
        # Anlamsal katman yoksa sözcüksel kanıt tek başına zayıftır; güvene
        # tavan konur. İki sınır: (1) tavan inceleme eşiğinin ÜSTÜNDE olmalı,
        # yoksa bu tiplerin her cevabı tam doğru olsa bile kuyruğa düşer
        # (ölçüldü: eski tavan 0.6 < eşik 0.65). (2) Kalemlerin hepsi net
        # eşleşmişse kanıt zaten zayıf değildir; tavan uygulanmaz, aksi hâlde
        # tam doğru kısa cevaplar güvenlik kapısından da geçemez.
        guven = min(guven, ayar.gomlemcisiz_rubrik_tavani)
    # Asıl sinyal güvenin kendisi değil, RİSK ALTINDAKİ PUAN PAYI: 9 puanlık
    # kesin kalemin yanındaki 1 puanlık kararsız kalem öğretmeni çağırmamalı,
    # ama puanın çoğu kararsızsa çağırmalı.
    kararsiz_pay = _kararsiz_puan_payi(
        kararlar, guvenler, soru.puan, ayar.incele_guven_esigi
    )
    incele = (
        guven < ayar.incele_guven_esigi
        or kararsiz_pay >= ayar.kararsiz_puan_payi_esigi
    )
    genel_celiskiler = [
        ifade
        for ifade in soru.anahtar.yasak_celiskiler
        if _bicim_skoru(
            eslesme_bicimi(ifade), eslesme_bicimi(cevap_metni)
        ) >= 86
    ]
    if genel_celiskiler:
        incele = True
        guven = min(guven, 0.45)
        detaylar.append(
            "⚠ Cevapta anahtarla çelişen ifade bulundu: "
            + ", ".join(genel_celiskiler[:3])
        )
    if zorunlu_eksik:
        incele = True
        detaylar.append(
            "↳ Zorunlu bir ölçüt eksik; diğer doğru ölçütlerin puanı korundu."
        )

    # Referanslı tespit: cevap ders kitabıyla güçlü örtüşüyor ama rubrik puanı
    # düşük kaldıysa, öğretmen doğrulasın diye insan onayına işaretle (haksız
    # sıfırı engeller). Kitaptaki en ilgili pasaj kanıt olarak eklenir.
    if referans_pasajlari and gomlemci is not None:
        try:
            ortusme = _kitap_ortusmesi(cevap_metni, referans_pasajlari, gomlemci)
            detaylar.append(f"📖 Kitap örtüşmesi: {ortusme:.2f}")
            if ortusme >= ayar.rubrik_anlamsal_esik and puan < 0.5 * soru.puan:
                incele = True
                guven = min(guven, 0.55)
                detaylar.append("↳ Cevap ders kitabıyla örtüşüyor; rubrik kaçırmış olabilir — incele")
        except Exception:
            pass

    kazanilan = [
        k for k in kararlar if float(k.get("puan", 0)) > 0
    ]
    eksik = [
        k for k in kararlar if float(k.get("puan", 0)) == 0
    ]
    aciklama = (
        f"{len(kazanilan)}/{len(kararlar)} rubrik ölçütünden puan alındı; "
        f"sonuç {puan:g}/{soru.puan:g}."
    )
    if eksik:
        aciklama += " Eksik: " + "; ".join(
            str(k["olcut"]) for k in eksik[:3]
        )
    return PuanSonucu(
        puan,
        soru.puan,
        guven,
        detaylar,
        incele=incele,
        risk=max(0.0, min(1.0, 1.0 - guven)),
        kararlar=kararlar,
        aciklama=aciklama,
        puanlama_guveni=guven,
    )
