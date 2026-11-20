"""Deterministik kalıtım çözücüsü — saf fonksiyonlar, model yok.

`Fraction` kullanımı şart, `float` değil: cevaplar tam kesir olarak
karşılaştırılacak ve float 3/16'yı 0.1875 yapıp "9/48" ile eşleşmesini
engeller. Ayrıca 1/3 gibi devirli kesirler kan grubu ve soyağacı
sorularında gerçekten çıkıyor.

Hiçbir fonksiyon yukarıya istisna sızdırmaz: geçersiz girdide `HesapSonucu`
boş döner ve çağıran mevcut model yoluna düşer. Sessiz yanlış cevap,
cevapsızlıktan zararlıdır.
"""

from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass, field
from fractions import Fraction
from itertools import product

from .tanim import Birey, Caprazlama, Lokus, _alellere_bol


@dataclass(frozen=True)
class HesapSonucu:
    """Çözücünün çıktısı. `deger is None` → hesaplanamadı."""

    deger: Fraction | int | None = None
    dagilim: dict[str, Fraction] = field(default_factory=dict)
    oran: tuple[int, ...] = ()
    adimlar: list[str] = field(default_factory=list)
    kesin: bool = True
    varsayimlar: list[str] = field(default_factory=list)

    def bos_mu(self) -> bool:
        return self.deger is None and not self.dagilim


BOS = HesapSonucu()


# --- gametler ---


def _lokus_gametleri(genotip: str, lokus: Lokus, cinsiyet: str) -> dict[str, Fraction]:
    """Tek lokusun gamet dağılımı."""
    aleller = _alellere_bol(genotip, lokus)
    if not aleller:
        # Y'ye bağlı lokusta dişi hiç alel taşımaz; "yok" tek gamet.
        return {"": Fraction(1)}
    if lokus.konum == "x" and cinsiyet == "erkek":
        # Erkek hemizigot: yarı gametler X (aleli taşır), yarısı Y (taşımaz).
        return {aleller[0]: Fraction(1, 2), "": Fraction(1, 2)}
    if lokus.konum == "y":
        # Y'ye bağlı: erkeğin yarı gameti Y'yi taşır.
        return {aleller[0]: Fraction(1, 2), "": Fraction(1, 2)}
    dagilim: dict[str, Fraction] = defaultdict(Fraction)
    pay = Fraction(1, len(aleller))
    for alel in aleller:
        dagilim[alel] += pay
    return dict(dagilim)


def _cinsiyet_gametleri(birey: Birey) -> dict[str, Fraction]:
    """Cinsiyet kromozomu dağılımı — X'e/Y'ye bağlı lokus yoksa da gerekir."""
    if birey.cinsiyet == "erkek":
        return {"X": Fraction(1, 2), "Y": Fraction(1, 2)}
    if birey.cinsiyet == "disi":
        return {"X": Fraction(1)}
    return {"": Fraction(1)}


def gametler(
    birey: Birey,
    caprazlama: Caprazlama,
) -> dict[tuple[str, ...], Fraction]:
    """Bireyin gamet dağılımı: (lokus sırasıyla alel demeti) → olasılık.

    Bağlı lokuslar birlikte taşınır. `krossing_orani` verilmemişse tam
    bağlılık varsayılır (rekombinant yok) ve bu varsayım `sorgula` tarafından
    raporlanır — sessiz varsayım, yanlış cevabın en sık kaynağıdır.
    """
    adlar = [k.ad for k in caprazlama.lokuslar]
    bagli = {ad: grup for grup in caprazlama.bagli_gruplar for ad in grup}

    # Cinsiyet kromozomundaki TÜM lokuslar tek birimdir. Bir sperm ya X ya Y
    # taşır; ikisini bağımsız çekmek "hem X'teki renk körlüğü alelini hem
    # Y'deki kıllı kulak alelini taşıyan gamet" gibi İMKÂNSIZ bir gamet
    # üretir ve olasılığı sessizce yarıya böler.
    eseysel = tuple(
        k.ad for k in caprazlama.lokuslar if k.konum in {"x", "y", "xy_homolog"}
    )

    birimler: list[tuple[str, ...]] = []
    gorulen: set[str] = set()
    if eseysel:
        birimler.append(eseysel)
        gorulen.update(eseysel)
    for ad in adlar:
        if ad in gorulen:
            continue
        grup = bagli.get(ad)
        if grup:
            birim = tuple(a for a in adlar if a in set(grup))
            gorulen.update(birim)
        else:
            birim = (ad,)
            gorulen.add(ad)
        birimler.append(birim)

    birim_dagilimlari: list[list[tuple[dict[str, str], Fraction]]] = []
    for birim in birimler:
        if birim == eseysel:
            birim_dagilimlari.append(_eseysel_gametler(birim, birey, caprazlama))
        else:
            birim_dagilimlari.append(_birim_gametleri(birim, birey, caprazlama))

    sonuc: dict[tuple[str, ...], Fraction] = defaultdict(Fraction)
    for secim in product(*birim_dagilimlari):
        olasilik = Fraction(1)
        birlesik: dict[str, str] = {}
        for atama, pay in secim:
            olasilik *= pay
            birlesik.update(atama)
        anahtar = tuple(birlesik.get(ad, "") for ad in adlar)
        sonuc[anahtar] += olasilik
    return dict(sonuc)


def _eseysel_gametler(
    birim: tuple[str, ...], birey: Birey, caprazlama: Caprazlama
) -> list[tuple[dict[str, str], Fraction]]:
    """Cinsiyet kromozomundaki lokusların ORTAK gamet dağılımı.

    Erkek: yarısı X kromozomu (X'e bağlı alelleri taşır, Y'dekiler boş),
    yarısı Y kromozomu (tersi). Dişi: her zaman X, ve X'e bağlı lokuslarda
    iki alelinden birini eşit olasılıkla verir.
    """
    x_lokuslari = [a for a in birim if (caprazlama.lokus(a) or Lokus("", ())).konum != "y"]
    y_lokuslari = [a for a in birim if (caprazlama.lokus(a) or Lokus("", ())).konum == "y"]

    if birey.cinsiyet == "erkek":
        x_gamet: dict[str, str] = dict.fromkeys(birim, "")
        y_gamet: dict[str, str] = dict.fromkeys(birim, "")
        for ad in x_lokuslari:
            lokus = caprazlama.lokus(ad)
            if lokus is None:
                continue
            aleller = _alellere_bol(birey.genotip.get(ad, ""), lokus)
            # Erkek X'te hemizigot: tek aleli var, X taşıyan gamete o gider.
            x_gamet[ad] = aleller[0] if aleller else ""
        for ad in y_lokuslari:
            lokus = caprazlama.lokus(ad)
            if lokus is None:
                continue
            aleller = _alellere_bol(birey.genotip.get(ad, ""), lokus)
            y_gamet[ad] = aleller[0] if aleller else ""
        return [(x_gamet, Fraction(1, 2)), (y_gamet, Fraction(1, 2))]

    # Dişi: Y lokusları hep boş; X'e bağlı lokuslarda iki alelin biri.
    secenekler: list[tuple[dict[str, str], Fraction]] = [(dict.fromkeys(birim, ""), Fraction(1))]
    for ad in x_lokuslari:
        lokus = caprazlama.lokus(ad)
        if lokus is None:
            continue
        aleller = _alellere_bol(birey.genotip.get(ad, ""), lokus)
        if not aleller:
            continue
        pay = Fraction(1, len(aleller))
        yeni: list[tuple[dict[str, str], Fraction]] = []
        for atama, mevcut in secenekler:
            for alel in aleller:
                kopya = dict(atama)
                kopya[ad] = alel
                yeni.append((kopya, mevcut * pay))
        secenekler = yeni
    return secenekler


def _birim_gametleri(
    birim: tuple[str, ...], birey: Birey, caprazlama: Caprazlama
) -> list[tuple[dict[str, str], Fraction]]:
    """Bir bağımsız birimin (tek lokus ya da bağlantı grubu) gamet dağılımı."""
    if len(birim) == 1:
        ad = birim[0]
        lokus = caprazlama.lokus(ad)
        if lokus is None:
            return [({ad: ""}, Fraction(1))]
        dagilim = _lokus_gametleri(birey.genotip.get(ad, ""), lokus, birey.cinsiyet)
        return [({ad: alel}, pay) for alel, pay in dagilim.items()]

    # Bağlantı grubu: ebeveynin iki kromozomu birlikte taşınır. Faz bilgisi
    # (hangi alel hangi kromozomda) genotip yazımının sırasından okunur:
    # ilk aleller bir kromozom, ikinciler diğeri.
    kromozom_a: dict[str, str] = {}
    kromozom_b: dict[str, str] = {}
    for ad in birim:
        lokus = caprazlama.lokus(ad)
        if lokus is None:
            return [(dict.fromkeys(birim, ""), Fraction(1))]
        aleller = _alellere_bol(birey.genotip.get(ad, ""), lokus)
        if len(aleller) != 2:
            return [(dict.fromkeys(birim, ""), Fraction(1))]
        kromozom_a[ad] = aleller[0]
        kromozom_b[ad] = aleller[1]

    krossing = caprazlama.krossing_orani
    if not krossing:
        return [(kromozom_a, Fraction(1, 2)), (kromozom_b, Fraction(1, 2))]

    # Rekombinantlar: krossing oranı toplam rekombinant payıdır.
    ebeveyn_payi = (1 - krossing) / 2
    rekombinant_payi = krossing / 2
    rek_a = dict(kromozom_a)
    rek_b = dict(kromozom_b)
    son = birim[-1]
    rek_a[son], rek_b[son] = kromozom_b[son], kromozom_a[son]
    return [
        (kromozom_a, ebeveyn_payi),
        (kromozom_b, ebeveyn_payi),
        (rek_a, rekombinant_payi),
        (rek_b, rekombinant_payi),
    ]


# --- çaprazlama ---


def _genotipi_duzenle(aleller: tuple[str, str], lokus: Lokus) -> str:
    """İki aleli kanonik sırada birleştirir (baskın önce)."""
    sira = {a: i for i, a in enumerate(lokus.aleller)}
    return "".join(sorted((a for a in aleller if a), key=lambda a: sira.get(a, 99)))


def caprazla(caprazlama: Caprazlama) -> dict[tuple[str, ...], Fraction]:
    """İki ebeveynin döl genotip dağılımı: (lokus sırasıyla genotip) → olasılık."""
    if len(caprazlama.ebeveynler) != 2:
        return {}
    anne, baba = caprazlama.ebeveynler
    adlar = [k.ad for k in caprazlama.lokuslar]
    a_gametleri = gametler(anne, caprazlama)
    b_gametleri = gametler(baba, caprazlama)
    if not a_gametleri or not b_gametleri:
        return {}

    sonuc: dict[tuple[str, ...], Fraction] = defaultdict(Fraction)
    for a_gamet, a_pay in a_gametleri.items():
        for b_gamet, b_pay in b_gametleri.items():
            genotipler = []
            for i, ad in enumerate(adlar):
                lokus = caprazlama.lokus(ad)
                if lokus is None:
                    genotipler.append("")
                    continue
                genotipler.append(_genotipi_duzenle((a_gamet[i], b_gamet[i]), lokus))
            sonuc[tuple(genotipler)] += a_pay * b_pay
    return dict(sonuc)


# --- fenotip ---


def fenotip(genotip: str, lokus: Lokus) -> str:
    """Genotipin fenotip etiketi."""
    if lokus.fenotipler and genotip in lokus.fenotipler:
        return lokus.fenotipler[genotip]
    aleller = _alellere_bol(genotip, lokus)
    if not aleller:
        return "yok"

    if lokus.baskinlik in {"eksik", "es"}:
        # Heterozigotun kendi fenotipi var.
        return _genotipi_duzenle(tuple(aleller[:2]), lokus) if len(aleller) >= 2 else aleller[0]

    if lokus.baskinlik in {"coklu_alel", "kan_grubu"} and lokus.ustunluk:
        # Üstünlük kademelerinde en üstteki kademede bulunan alel(ler) fenotipi
        # belirler. Aynı kademede iki farklı alel varsa ikisi de görünür
        # (AB kan grubu).
        for kademe in lokus.ustunluk:
            gorunen = sorted({a for a in aleller if a in set(kademe)})
            if gorunen:
                return "".join(gorunen)
        return "".join(sorted(set(aleller)))

    # Tam baskınlık: baskın alelden biri varsa baskın fenotip.
    for alel in lokus.aleller:
        if alel in aleller:
            return alel
    return aleller[0]


def fenotipe_indir(
    dagilim: dict[tuple[str, ...], Fraction], caprazlama: Caprazlama
) -> dict[tuple[str, ...], Fraction]:
    """Genotip dağılımını fenotip dağılımına indirger."""
    adlar = [k.ad for k in caprazlama.lokuslar]
    sonuc: dict[tuple[str, ...], Fraction] = defaultdict(Fraction)
    for genotipler, pay in dagilim.items():
        etiketler = []
        for i, ad in enumerate(adlar):
            lokus = caprazlama.lokus(ad)
            etiketler.append(fenotip(genotipler[i], lokus) if lokus else "")
        sonuc[tuple(etiketler)] += pay
    return dict(sonuc)


# --- hedef eşleşmesi ---


def _hedefe_uyuyor(
    anahtar: tuple[str, ...], hedef: dict, caprazlama: Caprazlama, fenotip_mi: bool
) -> bool:
    """Bir genotip/fenotip demeti hedef tanımına uyuyor mu.

    Hedef biçimleri (lokus adı → beklenen):
      {"A": "cekinik"} · {"A": "baskin"} · {"A": "Aa"} · {"kan": "AB"}
    Ayrıca `{"cinsiyet": "erkek"}` desteklenir.
    """
    adlar = [k.ad for k in caprazlama.lokuslar]
    for anahtar_adi, beklenen in hedef.items():
        if anahtar_adi == "cinsiyet":
            continue  # cinsiyet ayrı ele alınıyor
        if anahtar_adi not in adlar:
            return False
        lokus = caprazlama.lokus(anahtar_adi)
        if lokus is None:
            return False
        deger = anahtar[adlar.index(anahtar_adi)]
        if not _deger_uyuyor(deger, str(beklenen), lokus, fenotip_mi):
            return False
    return True


def _deger_uyuyor(deger: str, beklenen: str, lokus: Lokus, fenotip_mi: bool) -> bool:
    beklenen = beklenen.strip()
    if beklenen in {"baskin", "baskın"}:
        gozlenen = deger if fenotip_mi else fenotip(deger, lokus)
        return gozlenen == lokus.baskin_alel()
    if beklenen in {"cekinik", "çekinik"}:
        gozlenen = deger if fenotip_mi else fenotip(deger, lokus)
        return gozlenen == lokus.cekinik_alel()
    if beklenen in {"heterozigot", "homozigot"}:
        # Zigotluk bir GENOTİP özelliğidir; fenotip etiketinde aranamaz.
        # Tam baskınlıkta fenotip "A" tek alel gibi görünür ve "homozigot"
        # sayılırdı — AA ile Aa'yı ayırt edemediği için cevap 3/4+1/4 = 1
        # çıkıyordu. False dönmek, çağıranın genotip düzeyine düşmesini sağlar.
        if fenotip_mi:
            return False
        aleller = _alellere_bol(deger, lokus)
        return (len(set(aleller)) > 1) if beklenen == "heterozigot" else (
            len(set(aleller)) == 1
        )
    if fenotip_mi:
        return deger == beklenen or fenotip(beklenen, lokus) == deger
    return deger == _genotipi_duzenle(tuple(_alellere_bol(beklenen, lokus)[:2]), lokus)


def _eseysel_lokus_var(caprazlama: Caprazlama) -> bool:
    return any(k.konum in {"x", "y", "xy_homolog"} for k in caprazlama.lokuslar)


def _cinsiyet_payi(hedef: dict, caprazlama: Caprazlama) -> Fraction:
    """Birleşik olasılıkta cinsiyet çarpanı.

    Eşeysel lokus VARSA çarpan uygulanmaz: cinsiyet zaten dağılımın içinde
    (babadan Y alan çocuk X'e bağlı lokusta hemizigot görünür) ve ayrıca 1/2
    ile çarpmak cevabı yarıya indirir — çift sayım. Yalnız tamamen otozomal
    bir çaprazlamada "erkek çocuk" bağımsız bir 1/2'dir.
    """
    cinsiyet = str(hedef.get("cinsiyet") or "").strip()
    if cinsiyet not in {"erkek", "disi", "dişi"}:
        return Fraction(1)
    return Fraction(1) if _eseysel_lokus_var(caprazlama) else Fraction(1, 2)


def _cinsiyet_uyuyor(anahtar: tuple[str, ...], caprazlama: Caprazlama, beklenen: str) -> bool:
    """Döl demetinden cinsiyeti okur.

    X'e bağlı bir lokus varsa cinsiyet dolaylı olarak orada kodludur: babadan
    Y gelen çocuk o lokusta TEK alel taşır (hemizigot), X gelen iki alel
    taşır. Y'ye bağlı lokusta ise alel taşımak erkek olmak demektir.
    """
    beklenen = "disi" if beklenen in {"disi", "dişi"} else beklenen
    adlar = [k.ad for k in caprazlama.lokuslar]
    for lokus in caprazlama.lokuslar:
        deger = anahtar[adlar.index(lokus.ad)]
        if lokus.konum == "x":
            erkek = len(_alellere_bol(deger, lokus)) <= 1
            return erkek if beklenen == "erkek" else not erkek
        if lokus.konum == "y":
            erkek = bool(_alellere_bol(deger, lokus))
            return erkek if beklenen == "erkek" else not erkek
    return False


def _kosulla_daralt(
    genotip_dagilimi: dict[tuple[str, ...], Fraction],
    fenotip_dagilimi: dict[tuple[str, ...], Fraction],
    kosul: dict,
    caprazlama: Caprazlama,
) -> tuple[dict, dict, Fraction]:
    """Koşula uyan alt kümeyi seçip 1'e normalleştirir."""
    cinsiyet = str(kosul.get("cinsiyet") or "").strip()

    def _sec(dagilim: dict[tuple[str, ...], Fraction], fenotip_mi: bool) -> dict:
        secili = {}
        for anahtar, pay in dagilim.items():
            if cinsiyet and not _cinsiyet_uyuyor(anahtar, caprazlama, cinsiyet):
                continue
            digerleri = {k: v for k, v in kosul.items() if k != "cinsiyet"}
            if digerleri and not _hedefe_uyuyor(anahtar, digerleri, caprazlama, fenotip_mi):
                continue
            secili[anahtar] = pay
        return secili

    secili_genotip = _sec(genotip_dagilimi, False)
    secili_fenotip = _sec(fenotip_dagilimi, True)
    pay = sum(secili_genotip.values(), Fraction(0))
    if pay == 0:
        return {}, {}, Fraction(0)
    return (
        {a: p / pay for a, p in secili_genotip.items()},
        {a: p / pay for a, p in secili_fenotip.items()},
        pay,
    )


# --- ana sorgu ---


def sorgula(caprazlama: Caprazlama) -> HesapSonucu:
    """Tanımı çözer. Hesaplanamıyorsa boş `HesapSonucu` döner."""
    if caprazlama.dogrula():
        return BOS
    tur = caprazlama.istek.tur
    try:
        if tur == "kromozom_sayisi":
            return _kromozom_sayisi(caprazlama)
        if tur == "kontrol_caprazi":
            return _kontrol_caprazi(caprazlama)
        if tur in {"gamet_cesidi", "gamet_olasiligi"}:
            return _gamet_sorgusu(caprazlama)
        return _dol_sorgusu(caprazlama)
    except (ValueError, ZeroDivisionError, KeyError, IndexError, TypeError):
        # Çözücü asla yukarıya patlamaz: hesaplanamayan soru, model yoluna
        # düşmeli; istisna tüm çözüm akışını düşürürdü.
        return BOS


def _varsayimlar(caprazlama: Caprazlama) -> list[str]:
    notlar: list[str] = []
    if caprazlama.bagli_gruplar and caprazlama.krossing_orani is None:
        notlar.append("Krossing over oranı verilmedi; tam bağlılık varsayıldı.")
    return notlar


def _dol_sorgusu(caprazlama: Caprazlama) -> HesapSonucu:
    genotip_dagilimi = caprazla(caprazlama)
    if not genotip_dagilimi:
        return BOS
    istek = caprazlama.istek
    varsayimlar = _varsayimlar(caprazlama)
    adlar = [k.ad for k in caprazlama.lokuslar]

    if istek.tur == "cesit_sayisi":
        neyin = str(istek.hedef.get("neyin") or "fenotip")
        kume = (
            fenotipe_indir(genotip_dagilimi, caprazlama)
            if neyin.startswith("fenotip")
            else genotip_dagilimi
        )
        sayi = sum(1 for pay in kume.values() if pay > 0)
        return HesapSonucu(
            deger=sayi,
            dagilim={"/".join(a): p for a, p in kume.items()},
            adimlar=[
                f"Döl dağılımı {len(genotip_dagilimi)} genotip sınıfı veriyor.",
                f"{neyin} çeşidi: {sayi}.",
            ],
            varsayimlar=varsayimlar,
        )

    if istek.tur in {"fenotip_orani", "genotip_orani"}:
        kume = (
            fenotipe_indir(genotip_dagilimi, caprazlama)
            if istek.tur == "fenotip_orani"
            else genotip_dagilimi
        )
        paylar = [p for p in kume.values() if p > 0]
        if not paylar:
            return BOS
        payda = 1
        for p in paylar:
            payda = payda * p.denominator // _gcd(payda, p.denominator)
        oran = tuple(sorted((int(p * payda) for p in paylar), reverse=True))
        return HesapSonucu(
            deger=None,
            dagilim={"/".join(a): p for a, p in kume.items()},
            oran=_sadelestir(oran),
            adimlar=[f"{istek.tur.replace('_', ' ')}: {':'.join(str(o) for o in oran)}"],
            varsayimlar=varsayimlar,
        )

    # olasilik (varsayılan)
    hedefler = list(istek.cocuk_sirasi) or [istek.hedef]
    if not any(hedefler):
        return BOS
    fenotip_dagilimi = fenotipe_indir(genotip_dagilimi, caprazlama)
    adimlar: list[str] = []

    # KOŞUL önce uygulanır: dağılımı daraltıp yeniden normalleştirir.
    # "Erkek çocukların renk körü olma olasılığı" sorusunda payda tüm çocuklar
    # değil YALNIZ erkek çocuklardır; çarpan uygulamak (birleşik olasılık)
    # cevabı yarıya indirirdi.
    if istek.kosul:
        genotip_dagilimi, fenotip_dagilimi, kosul_payi = _kosulla_daralt(
            genotip_dagilimi, fenotip_dagilimi, istek.kosul, caprazlama
        )
        if kosul_payi == 0:
            return BOS
        etiket = ", ".join(f"{k}={v}" for k, v in istek.kosul.items())
        adimlar.append(
            f"Koşul ({etiket}): dağılım bu alt kümeye daraltıldı "
            f"(payı {kosul_payi.numerator}/{kosul_payi.denominator})."
        )

    toplam = Fraction(1)
    for sira, hedef in enumerate(hedefler, 1):
        # Eşeysel lokus varsa cinsiyet dağılımda kodlu; hedefteki cinsiyet bir
        # SÜZGEÇ olur, çarpan değil (bkz. `_cinsiyet_payi`).
        cinsiyet_suzgeci = (
            str(hedef.get("cinsiyet") or "").strip()
            if _eseysel_lokus_var(caprazlama)
            else ""
        )

        def _uygun(anahtar, fenotip_mi, _hedef=hedef, _suzgec=cinsiyet_suzgeci):
            if _suzgec and not _cinsiyet_uyuyor(anahtar, caprazlama, _suzgec):
                return False
            return _hedefe_uyuyor(anahtar, _hedef, caprazlama, fenotip_mi)

        pay = sum(
            (p for a, p in fenotip_dagilimi.items() if _uygun(a, True)),
            Fraction(0),
        )
        if pay == 0:
            # Fenotipte bulunamadıysa genotip düzeyinde ara (ör. "Aa" hedefi).
            pay = sum(
                (p for a, p in genotip_dagilimi.items() if _uygun(a, False)),
                Fraction(0),
            )
        pay *= _cinsiyet_payi(hedef, caprazlama)
        etiket = ", ".join(f"{k}={v}" for k, v in hedef.items()) or "hedef"
        adimlar.append(
            f"{sira}. olay ({etiket}) olasılığı: {pay.numerator}/{pay.denominator}."
        )
        toplam *= pay
    if len(hedefler) > 1:
        adimlar.append(
            f"Olaylar bağımsız olduğu için olasılıklar çarpılır: "
            f"{toplam.numerator}/{toplam.denominator}."
        )
    return HesapSonucu(
        deger=toplam,
        dagilim={"/".join(a): p for a, p in fenotip_dagilimi.items()},
        adimlar=[f"Lokuslar: {', '.join(adlar)}.", *adimlar],
        varsayimlar=varsayimlar,
    )


def _gamet_sorgusu(caprazlama: Caprazlama) -> HesapSonucu:
    if not caprazlama.ebeveynler:
        return BOS
    birey = caprazlama.ebeveynler[0]
    istek = caprazlama.istek
    varsayimlar = _varsayimlar(caprazlama)

    if istek.tur == "gamet_olasiligi":
        dagilim = gametler(birey, caprazlama)
        adlar = [k.ad for k in caprazlama.lokuslar]
        hedef = istek.hedef
        pay = Fraction(0)
        for anahtar, olasilik in dagilim.items():
            uyuyor = True
            for ad, beklenen in hedef.items():
                if ad not in adlar:
                    uyuyor = False
                    break
                if anahtar[adlar.index(ad)] != str(beklenen):
                    uyuyor = False
                    break
            if uyuyor:
                pay += olasilik
        return HesapSonucu(
            deger=pay,
            dagilim={"".join(a): p for a, p in dagilim.items()},
            adimlar=[
                f"Birey {len(dagilim)} çeşit gamet üretebilir.",
                f"İstenen gametin olasılığı: {pay.numerator}/{pay.denominator}.",
            ],
            varsayimlar=varsayimlar,
        )

    # gamet_cesidi: "en az" tam bağlılık, "en cok" bağımsızlık varsayar.
    sinir = (istek.sinir or "").strip()
    heterozigot_sayisi = 0
    for lokus in caprazlama.lokuslar:
        aleller = _alellere_bol(birey.genotip.get(lokus.ad, ""), lokus)
        if len(set(aleller)) > 1:
            heterozigot_sayisi += 1
    if sinir == "en_az":
        # Tüm heterozigot lokuslar tek kromozomda bağlı → 2 çeşit gamet.
        sayi = 2 if heterozigot_sayisi else 1
        gerekce = "Tüm genler bağlı olsaydı krossing over olmadan 2 çeşit gamet oluşur."
    elif sinir == "en_cok":
        sayi = 2**heterozigot_sayisi if heterozigot_sayisi else 1
        gerekce = (
            f"{heterozigot_sayisi} heterozigot lokus bağımsız olsaydı "
            f"2^{heterozigot_sayisi} = {sayi} çeşit gamet oluşur."
        )
    else:
        dagilim = gametler(birey, caprazlama)
        sayi = sum(1 for p in dagilim.values() if p > 0)
        gerekce = f"Gamet çeşidi: {sayi}."
    return HesapSonucu(
        deger=sayi,
        adimlar=[f"Heterozigot lokus sayısı: {heterozigot_sayisi}.", gerekce],
        varsayimlar=varsayimlar,
    )


def _kromozom_sayisi(caprazlama: Caprazlama) -> HesapSonucu:
    """Genotipten diploit kromozom sayısı.

    Her BAĞIMSIZ lokus ayrı bir homolog çift demektir; bağlı lokuslar aynı
    çifti paylaşır. Cinsiyet kromozomu ayrı sayılmaz — X'e bağlı bir lokus
    zaten kendi çiftini temsil eder.
    """
    bagli = {ad: i for i, grup in enumerate(caprazlama.bagli_gruplar) for ad in grup}
    birimler: set[str] = set()
    for lokus in caprazlama.lokuslar:
        grup = bagli.get(lokus.ad)
        birimler.add(f"grup{grup}" if grup is not None else lokus.ad)
    if not birimler:
        return BOS
    return HesapSonucu(
        deger=len(birimler) * 2,
        adimlar=[
            f"Bağımsız kromozom çifti sayısı: {len(birimler)} "
            f"(bağlı genler aynı çifti paylaşır).",
            f"Diploit kromozom sayısı: {len(birimler)} × 2 = {len(birimler) * 2}.",
        ],
        varsayimlar=_varsayimlar(caprazlama),
    )


def _kontrol_caprazi(caprazlama: Caprazlama) -> HesapSonucu:
    """Kontrol (test) çaprazı için gereken eş: tüm lokuslarda homozigot çekinik."""
    if not caprazlama.lokuslar:
        return BOS
    genotip = "".join(
        lokus.cekinik_alel() * 2 for lokus in caprazlama.lokuslar
    )
    return HesapSonucu(
        deger=None,
        dagilim={genotip: Fraction(1)},
        adimlar=[
            "Kontrol çaprazında baskın fenotipli birey, HOMOZİGOT ÇEKİNİK "
            "bireyle çaprazlanır: çekinik eş gamete kendi çekinik alelini "
            "verdiği için döl fenotipi doğrudan bilinmeyen genotipi gösterir.",
            f"Gereken genotip: {genotip}.",
        ],
        varsayimlar=_varsayimlar(caprazlama),
    )


# --- yardımcılar ---


def _gcd(a: int, b: int) -> int:
    from math import gcd

    return gcd(a, b)


def _sadelestir(sayilar: tuple[int, ...]) -> tuple[int, ...]:
    bolen = 0
    for s in sayilar:
        bolen = _gcd(bolen, s)
    return tuple(s // bolen for s in sayilar) if bolen > 1 else sayilar
