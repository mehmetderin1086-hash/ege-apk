"""Deterministik kalıtım çözücüsü testleri — model gerekmez, tümü çevrimdışı.

Vakaların bir bölümü test dilimindeki GERÇEK sorulardan alındı ve beklenen
değer elle hesaplanıp doğrulandı; bunlar `[dilim]` ile işaretli. Çözücü saf
fonksiyon olduğu için doğruluğu modelden bağımsız sınanabilir — kalıtım
türündeki %18'lik doğruluğun sebebi bilgi değil aritmetikti, ve aritmetiğin
doğruluğu burada kanıtlanır.
"""

from __future__ import annotations

from fractions import Fraction as F

import pytest

from biyo_cozucu.kalitim.punnett import (
    caprazla,
    fenotip,
    fenotipe_indir,
    gametler,
    sorgula,
)
from biyo_cozucu.kalitim.tanim import Birey, Caprazlama, Istek, Lokus


def lok(harf: str, **kw) -> Lokus:
    return Lokus(ad=harf, aleller=(harf.upper(), harf.lower()), **kw)


KAN = Lokus(
    ad="kan", aleller=("A", "B", "0"), baskinlik="kan_grubu",
    ustunluk=(("A", "B"), ("0",)),
)
RK = Lokus(ad="rk", aleller=("XR", "Xr"), konum="x")
KK = Lokus(ad="kk", aleller=("H",), konum="y")


def caprazlama(lokuslar, ebeveynler, istek, **kw) -> Caprazlama:
    return Caprazlama(
        lokuslar=tuple(lokuslar), ebeveynler=tuple(ebeveynler), istek=istek, **kw
    )


# --- monohibrit ---


@pytest.mark.parametrize(
    "anne, baba, hedef, beklenen",
    [
        ("AA", "AA", "baskin", F(1)),
        ("AA", "aa", "baskin", F(1)),
        ("Aa", "Aa", "cekinik", F(1, 4)),
        ("Aa", "Aa", "baskin", F(3, 4)),
        ("Aa", "aa", "cekinik", F(1, 2)),
        ("aa", "aa", "cekinik", F(1)),
        ("aa", "aa", "baskin", F(0)),
        ("Aa", "Aa", "heterozigot", F(1, 2)),
        ("Aa", "Aa", "homozigot", F(1, 2)),
    ],
)
def test_monohibrit_olasilik(anne, baba, hedef, beklenen):
    c = caprazlama(
        [lok("a")],
        [Birey(genotip={"a": anne}), Birey(genotip={"a": baba})],
        Istek(tur="olasilik", hedef={"a": hedef}),
    )
    assert sorgula(c).deger == beklenen


def test_monohibrit_fenotip_orani():
    c = caprazlama(
        [lok("a")],
        [Birey(genotip={"a": "Aa"}), Birey(genotip={"a": "Aa"})],
        Istek(tur="fenotip_orani"),
    )
    assert sorgula(c).oran == (3, 1)


def test_monohibrit_genotip_orani():
    c = caprazlama(
        [lok("a")],
        [Birey(genotip={"a": "Aa"}), Birey(genotip={"a": "Aa"})],
        Istek(tur="genotip_orani"),
    )
    assert sorgula(c).oran == (2, 1, 1)


# --- eksik / eş baskınlık ---


def test_eksik_baskinlik_uc_fenotip():
    kirmizi = Lokus(ad="c", aleller=("C", "c"), baskinlik="eksik")
    c = caprazlama(
        [kirmizi],
        [Birey(genotip={"c": "Cc"}), Birey(genotip={"c": "Cc"})],
        Istek(tur="cesit_sayisi", hedef={"neyin": "fenotip"}),
    )
    assert sorgula(c).deger == 3


def test_eksik_baskinlikta_oran_1_2_1():
    kirmizi = Lokus(ad="c", aleller=("C", "c"), baskinlik="eksik")
    c = caprazlama(
        [kirmizi],
        [Birey(genotip={"c": "Cc"}), Birey(genotip={"c": "Cc"})],
        Istek(tur="fenotip_orani"),
    )
    assert sorgula(c).oran == (2, 1, 1)


def test_tam_baskinlikta_fenotip_cesidi_iki():
    c = caprazlama(
        [lok("a")],
        [Birey(genotip={"a": "Aa"}), Birey(genotip={"a": "Aa"})],
        Istek(tur="cesit_sayisi", hedef={"neyin": "fenotip"}),
    )
    assert sorgula(c).deger == 2


# --- kan grubu (çok alelli) ---


def test_kan_grubu_fenotipleri():
    assert fenotip("A0", KAN) == "A"
    assert fenotip("AB", KAN) == "AB"
    assert fenotip("00", KAN) == "0"
    assert fenotip("BB", KAN) == "B"


def test_kan_grubu_b0_capraz_cesit_sayilari():
    """[dilim] B kan grubundaki anne ve babanın çocukları: 3 genotip, 2 fenotip."""
    ebeveynler = [Birey(genotip={"kan": "B0"}), Birey(genotip={"kan": "B0"})]
    genotip = sorgula(
        caprazlama([KAN], ebeveynler, Istek(tur="cesit_sayisi", hedef={"neyin": "genotip"}))
    )
    fenotip_sonucu = sorgula(
        caprazlama([KAN], ebeveynler, Istek(tur="cesit_sayisi", hedef={"neyin": "fenotip"}))
    )
    assert (genotip.deger, fenotip_sonucu.deger) == (3, 2)


def test_kan_grubu_ab_x_00_dort_fenotip_degil_iki():
    """AB × 00 → yalnız A0 ve B0 çıkar: 2 fenotip."""
    c = caprazlama(
        [KAN],
        [Birey(genotip={"kan": "AB"}), Birey(genotip={"kan": "00"})],
        Istek(tur="cesit_sayisi", hedef={"neyin": "fenotip"}),
    )
    assert sorgula(c).deger == 2


def test_kan_grubu_a0_x_b0_dort_fenotip():
    c = caprazlama(
        [KAN],
        [Birey(genotip={"kan": "A0"}), Birey(genotip={"kan": "B0"})],
        Istek(tur="cesit_sayisi", hedef={"neyin": "fenotip"}),
    )
    assert sorgula(c).deger == 4


# --- di / trihibrit ---


def test_dihibrit_9_3_3_1():
    c = caprazlama(
        [lok("a"), lok("b")],
        [Birey(genotip={"a": "Aa", "b": "Bb"}), Birey(genotip={"a": "Aa", "b": "Bb"})],
        Istek(tur="fenotip_orani"),
    )
    assert sorgula(c).oran == (9, 3, 3, 1)


def test_dihibrit_cift_cekinik_olasiligi():
    c = caprazlama(
        [lok("a"), lok("b")],
        [Birey(genotip={"a": "Aa", "b": "Bb"}), Birey(genotip={"a": "Aa", "b": "Bb"})],
        Istek(tur="olasilik", hedef={"a": "cekinik", "b": "cekinik"}),
    )
    assert sorgula(c).deger == F(1, 16)


def test_fare_dihibrit_gercek_soru():
    """[dilim benzeri] SsKk × Sskk → siyah(3/4) × kısa(1/2) = 3/8."""
    c = caprazlama(
        [lok("s"), lok("k")],
        [Birey(genotip={"s": "Ss", "k": "Kk"}), Birey(genotip={"s": "Ss", "k": "kk"})],
        Istek(tur="olasilik", hedef={"s": "baskin", "k": "baskin"}),
    )
    assert sorgula(c).deger == F(3, 8)


# --- gametler ---


def test_gamet_cesidi_2_ussu():
    birey = Birey(genotip={"a": "Aa", "b": "Bb", "c": "Cc"})
    c = caprazlama([lok("a"), lok("b"), lok("c")], [birey], Istek(tur="gamet_cesidi"))
    assert sorgula(c).deger == 8


def test_gamet_cesidi_homozigot_tek():
    birey = Birey(genotip={"a": "AA", "b": "bb"})
    c = caprazlama([lok("a"), lok("b")], [birey], Istek(tur="gamet_cesidi"))
    assert sorgula(c).deger == 1


def test_gamet_cesidi_en_az_en_cok():
    """[dilim] ABR/abr hücresi: en az 2 (tam bağlı), en çok 8 (bağımsız)."""
    birey = Birey(genotip={"a": "Aa", "b": "Bb", "r": "Rr"})
    lokuslar = [lok("a"), lok("b"), lok("r")]
    en_az = sorgula(caprazlama(lokuslar, [birey], Istek(tur="gamet_cesidi", sinir="en_az")))
    en_cok = sorgula(caprazlama(lokuslar, [birey], Istek(tur="gamet_cesidi", sinir="en_cok")))
    assert (en_az.deger, en_cok.deger) == (2, 8)


def test_gamet_olasiligi_gercek_soru():
    """[dilim] AaBbMmDD → aBmD gameti: (1/2)³ × 1 = 1/8."""
    c = caprazlama(
        [lok("a"), lok("b"), lok("m"), lok("d")],
        [Birey(genotip={"a": "Aa", "b": "Bb", "m": "Mm", "d": "DD"})],
        Istek(tur="gamet_olasiligi", hedef={"a": "a", "b": "B", "m": "m", "d": "D"}),
    )
    assert sorgula(c).deger == F(1, 8)


def test_gamet_olasiligi_imkansiz_sifir():
    c = caprazlama(
        [lok("a")],
        [Birey(genotip={"a": "AA"})],
        Istek(tur="gamet_olasiligi", hedef={"a": "a"}),
    )
    assert sorgula(c).deger == 0


# --- bağlı genler ---


def test_bagli_genler_iki_gamet():
    birey = Birey(genotip={"a": "Aa", "b": "Bb"})
    c = Caprazlama(
        lokuslar=(lok("a"), lok("b")),
        ebeveynler=(birey,),
        bagli_gruplar=(("a", "b"),),
        istek=Istek(tur="gamet_cesidi"),
    )
    assert sorgula(c).deger == 2


def test_bagli_genler_krossing_ile_dort_gamet():
    birey = Birey(genotip={"a": "Aa", "b": "Bb"})
    c = Caprazlama(
        lokuslar=(lok("a"), lok("b")),
        ebeveynler=(birey,),
        bagli_gruplar=(("a", "b"),),
        krossing_orani=F(1, 5),
        istek=Istek(tur="gamet_cesidi"),
    )
    assert sorgula(c).deger == 4


def test_bagli_gen_varsayimi_raporlanir():
    """Krossing oranı verilmediğinde tam bağlılık VARSAYILDIĞI yazılmalı."""
    c = Caprazlama(
        lokuslar=(lok("a"), lok("b")),
        ebeveynler=(Birey(genotip={"a": "Aa", "b": "Bb"}),),
        bagli_gruplar=(("a", "b"),),
        istek=Istek(tur="gamet_cesidi"),
    )
    assert any("tam bağlılık" in v for v in sorgula(c).varsayimlar)


# --- eşeye bağlı kalıtım ---


def test_eseysel_lokuslar_ayni_gamette_olamaz():
    """Bir sperm ya X ya Y taşır — ikisini bağımsız çekmek İMKÂNSIZ gamet üretir."""
    baba = Birey(genotip={"rk": "XR", "kk": "H"}, cinsiyet="erkek")
    c = caprazlama([RK, KK], [baba], Istek(tur="gamet_cesidi"))
    dagilim = gametler(baba, c)
    # X taşıyan gamette Y aleli, Y taşıyanda X aleli olmamalı.
    for (x_alel, y_alel), pay in dagilim.items():
        assert not (x_alel and y_alel), f"imkânsız gamet: {x_alel}+{y_alel}"
        assert pay == F(1, 2)


def test_tasiyici_anne_erkek_cocuk_renk_koru():
    c = caprazlama(
        [RK],
        [
            Birey(genotip={"rk": "XRXr"}, cinsiyet="disi"),
            Birey(genotip={"rk": "XR"}, cinsiyet="erkek"),
        ],
        Istek(tur="olasilik", hedef={"rk": "cekinik"}, kosul={"cinsiyet": "erkek"}),
    )
    assert sorgula(c).deger == F(1, 2)


def test_kosullu_ile_birlesik_farkli():
    """"ERKEK çocukların X olma olasılığı" ile "X erkek çocuk olma olasılığı" AYRI.

    Ayrım yapılmazsa cevap yarıya iner ya da iki katına çıkar ve şık
    listesinde genelde her iki değer de bulunduğu için kendinden emin yanlış
    cevap üretir.
    """
    ebeveynler = [
        Birey(genotip={"rk": "XRXr"}, cinsiyet="disi"),
        Birey(genotip={"rk": "XR"}, cinsiyet="erkek"),
    ]
    kosullu = sorgula(caprazlama([RK], ebeveynler,
        Istek(tur="olasilik", hedef={"rk": "cekinik"}, kosul={"cinsiyet": "erkek"})))
    birlesik = sorgula(caprazlama([RK], ebeveynler,
        Istek(tur="olasilik", hedef={"rk": "cekinik", "cinsiyet": "erkek"})))
    assert kosullu.deger == F(1, 2)
    assert birlesik.deger == F(1, 4)


def test_renk_koru_anne_killi_kulakli_baba():
    """[dilim] Erkek çocuklar anneden Xr, babadan Y(H) alır → olasılık 1."""
    c = caprazlama(
        [RK, KK],
        [
            Birey(genotip={"rk": "XrXr"}, cinsiyet="disi"),
            Birey(genotip={"rk": "XR", "kk": "H"}, cinsiyet="erkek"),
        ],
        Istek(tur="olasilik", hedef={"rk": "cekinik", "kk": "H"},
              kosul={"cinsiyet": "erkek"}),
    )
    assert sorgula(c).deger == 1


def test_otozomalde_cinsiyet_carpani_uygulanir():
    """Eşeysel lokus YOKSA "erkek çocuk" bağımsız bir 1/2'dir."""
    c = caprazlama(
        [lok("a")],
        [Birey(genotip={"a": "Aa"}), Birey(genotip={"a": "Aa"})],
        Istek(tur="olasilik", hedef={"a": "cekinik", "cinsiyet": "erkek"}),
    )
    assert sorgula(c).deger == F(1, 8)


def test_kiz_cocuk_renk_koru_olabilir():
    c = caprazlama(
        [RK],
        [
            Birey(genotip={"rk": "XRXr"}, cinsiyet="disi"),
            Birey(genotip={"rk": "Xr"}, cinsiyet="erkek"),
        ],
        Istek(tur="olasilik", hedef={"rk": "cekinik"}, kosul={"cinsiyet": "disi"}),
    )
    assert sorgula(c).deger == F(1, 2)


# --- sıralı çocuk ---


def test_sirali_cocuk_carpimsal():
    """[dilim] Aa × Aa: 1. çocuk çekinik (1/4), 2. baskın (3/4) → 3/16."""
    c = caprazlama(
        [lok("a")],
        [Birey(genotip={"a": "Aa"}), Birey(genotip={"a": "Aa"})],
        Istek(tur="olasilik", cocuk_sirasi=({"a": "cekinik"}, {"a": "baskin"})),
    )
    assert sorgula(c).deger == F(3, 16)


def test_art_arda_iki_hasta_cocuk():
    c = caprazlama(
        [lok("a")],
        [Birey(genotip={"a": "Aa"}), Birey(genotip={"a": "Aa"})],
        Istek(tur="olasilik", cocuk_sirasi=({"a": "cekinik"}, {"a": "cekinik"})),
    )
    assert sorgula(c).deger == F(1, 16)


# --- kromozom sayısı ---


def test_kromozom_sayisi_bagli_genlerle():
    """[dilim] AABbCcddEeXRxr, A ve d bağlı → 5 çift → 10 kromozom."""
    c = Caprazlama(
        lokuslar=(lok("a"), lok("b"), lok("c"), lok("d"), lok("e"), RK),
        ebeveynler=(
            Birey(genotip={"a": "AA", "b": "Bb", "c": "Cc", "d": "dd",
                           "e": "Ee", "rk": "XRXr"}),
        ),
        bagli_gruplar=(("a", "d"),),
        istek=Istek(tur="kromozom_sayisi"),
    )
    assert sorgula(c).deger == 10


def test_kromozom_sayisi_bagsiz():
    c = caprazlama(
        [lok("a"), lok("b")],
        [Birey(genotip={"a": "Aa", "b": "Bb"})],
        Istek(tur="kromozom_sayisi"),
    )
    assert sorgula(c).deger == 4


# --- kontrol çaprazı ---


def test_kontrol_caprazi_homozigot_cekinik():
    """[dilim] Mor çiçekli + sarı tohumlu bezelyenin kontrol çaprazı → mmss."""
    c = caprazlama(
        [lok("m"), lok("s")],
        [Birey(genotip={"m": "Mm", "s": "Ss"})],
        Istek(tur="kontrol_caprazi"),
    )
    assert list(sorgula(c).dagilim) == ["mmss"]


# --- geçersiz girdi: sessizce çekil ---


@pytest.mark.parametrize(
    "bozuk",
    [
        Caprazlama(),  # tamamen boş
        Caprazlama(  # tanımsız lokus
            lokuslar=(Lokus(ad="a", aleller=("A", "a")),),
            ebeveynler=(Birey(genotip={"yok": "Aa"}),),
            istek=Istek(tur="olasilik", hedef={"a": "cekinik"}),
        ),
        Caprazlama(  # tanımsız alel
            lokuslar=(Lokus(ad="a", aleller=("A", "a")),),
            ebeveynler=(Birey(genotip={"a": "Zz"}), Birey(genotip={"a": "Aa"})),
            istek=Istek(tur="olasilik", hedef={"a": "cekinik"}),
        ),
        Caprazlama(  # bilinmeyen istek türü
            lokuslar=(Lokus(ad="a", aleller=("A", "a")),),
            ebeveynler=(Birey(genotip={"a": "Aa"}), Birey(genotip={"a": "Aa"})),
            istek=Istek(tur="uydurma"),
        ),
        Caprazlama(  # bilinmeyen baskınlık
            lokuslar=(Lokus(ad="a", aleller=("A", "a"), baskinlik="sihirli"),),
            ebeveynler=(Birey(genotip={"a": "Aa"}), Birey(genotip={"a": "Aa"})),
            istek=Istek(tur="olasilik", hedef={"a": "cekinik"}),
        ),
    ],
)
def test_gecersiz_tanim_bos_doner(bozuk):
    """Çözücü ASLA istisna sızdırmaz; hesaplanamayan soru model yoluna döner."""
    assert sorgula(bozuk).bos_mu()


def test_erkek_x_lokusunda_diploit_yazim_hata():
    c = Caprazlama(
        lokuslar=(RK,),
        ebeveynler=(Birey(genotip={"rk": "XRXr"}, cinsiyet="erkek"),),
        istek=Istek(tur="gamet_cesidi"),
    )
    assert any("tek alel" in h for h in c.dogrula())


def test_tek_ebeveynle_caprazlama_bos():
    c = caprazlama(
        [lok("a")], [Birey(genotip={"a": "Aa"})], Istek(tur="olasilik", hedef={"a": "cekinik"})
    )
    assert sorgula(c).bos_mu()


# --- dağılım bütünlüğü ---


def test_dagilim_toplami_bir():
    c = caprazlama(
        [lok("a"), lok("b")],
        [Birey(genotip={"a": "Aa", "b": "Bb"}), Birey(genotip={"a": "Aa", "b": "Bb"})],
        Istek(tur="fenotip_orani"),
    )
    assert sum(caprazla(c).values()) == 1
    assert sum(fenotipe_indir(caprazla(c), c).values()) == 1


def test_gamet_dagilimi_toplami_bir():
    birey = Birey(genotip={"a": "Aa", "b": "Bb"})
    c = caprazlama([lok("a"), lok("b")], [birey], Istek(tur="gamet_cesidi"))
    assert sum(gametler(birey, c).values()) == 1
