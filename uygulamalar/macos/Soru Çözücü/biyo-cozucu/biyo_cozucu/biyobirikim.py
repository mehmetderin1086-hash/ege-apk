"""Dar kapsamli toksik madde biyolojik buyutme cozum araci.

Bu modul bir genel ekoloji yorumlayicisi degildir. Yalniz uc (I/II/III)
ifadeli, trofik duzey ile toksik madde birikimini karsilastiran ve sonucu bir
ifade kumesi sikkiyla soran sorularda konusur. Metindeki her halka tek anlamli
degilse ``None`` doner ve mevcut model yolu calismaya devam eder.
"""

from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass


@dataclass(frozen=True)
class BiyobirikimSonucu:
    """Kuralla cozulmus tek bir coktan secmeli sonucun tasiyicisi."""

    cevap: str
    adimlar: tuple[str, ...]
    guven: float
    incele: bool = False
    uyarilar: tuple[str, ...] = ()


@dataclass(frozen=True)
class _IfadeSonucu:
    etiket: str
    ilk: str
    ikinci: str
    yon: str
    dogru: bool
    eksik_fazla: bool = False


# Kullanici istegindeki bilincli, sinirli siralama. ``omurgasiz`` genel
# zoolojik bir trofik duzey degildir; burada yalniz bu soru ailesinin verdigi
# sozlesme uyarinca herbivor basamaginda ele alinir.
_DUZEYLER = {
    "uretici": 0,
    "ototrof": 0,
    "alg": 0,
    "herbivor": 1,
    "omurgasiz": 1,
    "omnivor": 2,
    "karnivor": 3,
}

_ADLAR = {
    "uretici": "üretici",
    "ototrof": "ototrof",
    "alg": "alg",
    "herbivor": "herbivor",
    "omurgasiz": "omurgasız",
    "omnivor": "omnivor",
    "karnivor": "karnivor",
}

_KATEGORILER: tuple[tuple[str, re.Pattern[str]], ...] = (
    ("uretici", re.compile(r"\buretici[a-z]*\b")),
    ("ototrof", re.compile(r"\bototrof[a-z]*\b")),
    # ``alg[a-z]*`` kullanmak "algoritma"yi da kategori sayardi.
    ("alg", re.compile(r"\balg(?:ler[a-z]*|in[a-z]*|e|i|den|de)?\b")),
    ("herbivor", re.compile(r"\b(?:herbivor|otcul)[a-z]*\b")),
    ("omurgasiz", re.compile(r"\bomurgasiz[a-z]*\b")),
    ("omnivor", re.compile(r"\b(?:omnivor|hepcil)[a-z]*\b")),
    ("karnivor", re.compile(r"\b(?:karnivor|etcil)[a-z]*\b")),
)

_IFADE_ISARETI = re.compile(r"(?<!\w)(?P<etiket>III|II|I|1)\s*[.)]\s*", re.I)
_ROMEN = re.compile(r"(?<![a-z0-9])(?:iii|ii|i|1|l)(?![a-z0-9])")


def _ascii(metin: str) -> str:
    """Turkce/OCR metnini regex icin aksansiz, kucuk bicime getir."""
    metin = metin.replace("ı", "i").replace("İ", "I")
    ayrik = unicodedata.normalize("NFKD", metin)
    return "".join(h for h in ayrik if not unicodedata.combining(h)).casefold()


def _ifadeleri_ayir(soru: str) -> list[tuple[str, str]] | None:
    """Yalniz sirali I/II/III yapisini ayir; baska numaralamayi reddet."""
    eslesmeler = list(_IFADE_ISARETI.finditer(soru))
    etiketler = ["I" if e.group("etiket").upper() in {"I", "1"} else e.group("etiket").upper()
                 for e in eslesmeler]
    baslangiclar = [
        sira
        for sira in range(len(etiketler) - 2)
        if etiketler[sira:sira + 3] == ["I", "II", "III"]
    ]
    if len(baslangiclar) != 1:
        return None
    baslangic = baslangiclar[0]
    secilen = eslesmeler[baslangic:baslangic + 3]
    parcalar: list[tuple[str, str]] = []
    for sira, (etiket, eslesme) in enumerate(zip(("I", "II", "III"), secilen, strict=True)):
        bitis = secilen[sira + 1].start() if sira < 2 else len(soru)
        parca = soru[eslesme.end():bitis].strip()
        if etiket == "III":
            parca = re.split(
                r"\b(?:yorumlarindan|ifadelerinden|yargilarindan)\b",
                _ascii(parca),
                maxsplit=1,
            )[0].strip()
        if not parca:
            return None
        parcalar.append((etiket, parca))
    return parcalar


def _kategorileri_bul(ifade: str) -> list[tuple[int, int, str]]:
    bulunan: list[tuple[int, int, str]] = []
    for ad, desen in _KATEGORILER:
        bulunan.extend((m.start(), m.end(), ad) for m in desen.finditer(ifade))
    return sorted(bulunan)


def _ifadeyi_coz(etiket: str, ifade: str) -> _IfadeSonucu | None:
    sade = _ascii(ifade)
    if "birik" not in sade or "beklen" not in sade:
        return None
    # Olumsuzluk veya esitlik, yalniz buyuk/kucuk siralamasinin anlamini
    # degistirir. Bu arac bunlari yorumlamaya calismaz.
    if re.search(r"\b(?:degil|beklenmez|esit|ayni)\b", sade):
        return None

    kategoriler = _kategorileri_bul(sade)
    if len(kategoriler) != 2:
        return None
    ilk, ikinci = kategoriler
    daha = list(re.finditer(r"\bdaha\b", sade))
    if len(daha) != 1 or daha[0].start() <= ikinci[1]:
        return None

    karsilastirma = sade[daha[0].start():]
    buyuk = bool(re.match(r"daha\s+(?:fazla|cok|yuksek)\b", karsilastirma))
    kucuk = bool(re.match(r"daha\s+(?:az|dusuk)\b", karsilastirma))
    # Soru Kesici OCR'sinin gercek Q2 metninde satir sonundaki "fazla"
    # kirpilmis ve "daha olmasi beklenir" kalmistir. Bu yapida "az" ya da
    # baska bir sifat yoksa Turkcedeki eliptik "daha [fazla]" tek yonludur;
    # yine de veri kaybi oldugu icin sonuc zorunlu incelemeye cikar.
    eksik_fazla = bool(re.match(r"daha\s+olmasi\s+beklen", karsilastirma))
    if sum((buyuk, kucuk, eksik_fazla)) != 1:
        return None
    yon = "<" if kucuk else ">"
    ilk_ad, ikinci_ad = ilk[2], ikinci[2]
    ilk_duzey, ikinci_duzey = _DUZEYLER[ilk_ad], _DUZEYLER[ikinci_ad]
    dogru = ilk_duzey < ikinci_duzey if yon == "<" else ilk_duzey > ikinci_duzey
    return _IfadeSonucu(
        etiket=etiket,
        ilk=ilk_ad,
        ikinci=ikinci_ad,
        yon=yon,
        dogru=dogru,
        eksik_fazla=eksik_fazla,
    )


def _sik_kumesi(metin: str) -> frozenset[str] | None:
    sade = _ascii(metin).strip()
    yalniz = bool(re.search(r"\b(?:yalniz|sadece)\b", sade))
    bulunan: list[str] = []
    for eslesme in _ROMEN.finditer(sade):
        deger = eslesme.group(0)
        bulunan.append("I" if deger in {"i", "1", "l"} else deger.upper())
    if not bulunan or len(set(bulunan)) != len(bulunan):
        return None
    if yalniz and len(bulunan) != 1:
        return None

    kalan = _ROMEN.sub(" ", sade)
    kalan = re.sub(r"\b(?:yalniz|sadece|ve|ile)\b", " ", kalan)
    kalan = re.sub(r"[\s,;+/&()\-]+", "", kalan)
    if kalan:
        return None
    return frozenset(bulunan)


def _sikki_bul(secenekler: dict[str, str], hedef: frozenset[str]) -> str | None:
    if len(secenekler) < 3 or not hedef:
        return None
    kumeler: dict[str, frozenset[str]] = {}
    for ham_harf, metin in secenekler.items():
        harf = str(ham_harf).strip().upper()
        if not re.fullmatch(r"[A-E]", harf) or harf in kumeler:
            return None
        kume = _sik_kumesi(str(metin))
        if kume is None:
            return None
        kumeler[harf] = kume
    # Ayni ifade kumesinin iki harfe baglanmasi, "tek bir harf" sozlesmesini
    # bozar; hedef eslesse bile arac susar.
    if len(set(kumeler.values())) != len(kumeler):
        return None
    eslesen = [harf for harf, kume in kumeler.items() if kume == hedef]
    return eslesen[0] if len(eslesen) == 1 else None


def coz(soru: str, secenekler: dict[str, str] | None) -> BiyobirikimSonucu | None:
    """Desteklenen toksik birikim sorusunu coz; emin degilse ``None`` don."""
    if not soru or not secenekler:
        return None
    sade = _ascii(soru)
    if "toksik" not in sade or "birik" not in sade or "hangileri" not in sade:
        return None
    yapilamaz = bool(re.search(r"\byapilama(?:z|yan)\b", sade))
    yapilabilir = bool(re.search(r"\byapilabil(?:ir|en)\b", sade))
    if yapilamaz == yapilabilir:
        return None

    parcalar = _ifadeleri_ayir(soru)
    if parcalar is None:
        return None
    sonuclar = [_ifadeyi_coz(etiket, ifade) for etiket, ifade in parcalar]
    if any(sonuc is None for sonuc in sonuclar):
        return None
    kesin = [sonuc for sonuc in sonuclar if sonuc is not None]
    hedef = frozenset(
        sonuc.etiket
        for sonuc in kesin
        if sonuc.dogru is yapilabilir
    )
    cevap = _sikki_bul(secenekler, hedef)
    if cevap is None:
        return None

    adimlar = [
        "Toksik madde birikimi için sınırlı trofik sıra kullanıldı: "
        "üretici/ototrof/alg < herbivor/omurgasız < omnivor < karnivor."
    ]
    for sonuc in kesin:
        yorum = "yapılabilir" if sonuc.dogru else "yapılamaz"
        adimlar.append(
            f"{sonuc.etiket}: {_ADLAR[sonuc.ilk]} {sonuc.yon} "
            f"{_ADLAR[sonuc.ikinci]} karşılaştırması {yorum}."
        )
    kume = " ve ".join(sonuc.etiket for sonuc in kesin if sonuc.etiket in hedef)
    adimlar.append(
        f"Sorulan ifade kümesi {kume}; seçeneklerde bu küme {cevap} şıkkıdır."
    )

    eksik_fazla = any(sonuc.eksik_fazla for sonuc in kesin)
    uyarilar: tuple[str, ...] = ()
    if eksik_fazla:
        uyarilar = (
            "Bir ifadede 'daha fazla' sözündeki 'fazla' OCR/kırpım metninde "
            "yoktu; 'daha olması beklenir' eliptik büyüklük karşılaştırması "
            "olarak okundu. Kırpım insan tarafından doğrulanmalıdır.",
        )
    return BiyobirikimSonucu(
        cevap=cevap,
        adimlar=tuple(adimlar),
        guven=0.72 if eksik_fazla else 0.95,
        incele=eksik_fazla,
        uyarilar=uyarilar,
    )
