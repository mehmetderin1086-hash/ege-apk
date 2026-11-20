"""Basit soyağacı uyumluluk soruları için güvenli görsel köprü.

Görsel dil modeli burada soruyu ÇÖZMEZ. Yalnız çekirdek ailedeki
çocuğun cinsiyet/hastalık durumunu ve ebeveynlerin durumunu okur. Standart
okul genetiği kuralları saf Python ile uygulanır. Okuma veya şık eşlemesi
tek anlamlı değilse katman sessizce çekilir; mevcut model yolu devam eder.

Bu dar kapsam bilinçli: bir soyağacının tamamını serbest metinle çözdürüp
yüksek güven vermek, görseldeki tek bir sembol yanlış okunduğunda kendinden
emin yanlış cevap üretiyordu.
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from fractions import Fraction

from ..metin import sadelestir


@dataclass(frozen=True)
class CekirdekAile:
    """Görselden okunması gereken asgari, doğrulanabilir aile yapısı."""

    cocuk_cinsiyet: str
    cocuk_hasta: bool
    anne_hasta: bool
    baba_hasta: bool


@dataclass(frozen=True)
class SoyagaciSonucu:
    """Saf kural motorunun tek anlamlı olarak bağladığı şık."""

    cevap: str
    adimlar: tuple[str, ...]


@dataclass(frozen=True)
class SoyagaciBireyi:
    kimlik: str
    cinsiyet: str
    durum: str
    ebeveynler: tuple[str, ...] = ()
    hedef: bool = False


_TURKCE_ASCII = str.maketrans(
    {"ç": "c", "ğ": "g", "ı": "i", "ö": "o", "ş": "s", "ü": "u"}
)


def _ascii(metin: str) -> str:
    return sadelestir(metin).translate(_TURKCE_ASCII)


def uyumluluk_sorusu_mu(
    soru: str, secenekler: dict[str, str] | None = None
) -> bool:
    """Yalnız desteklenen "hangi kalıtımlar olabilir" tipini kabul et."""
    metin = _ascii(soru)
    if "soyagac" not in metin or "dogru olabilir" not in metin:
        return False
    if not secenekler or len(secenekler) < 2:
        return False
    return len(_ifade_modlari(soru)) >= 2


def aile_okuma_mesajlari() -> list[dict[str, str]]:
    """VLM'ye verilen kısa ve çözümden bağımsız görsel okuma istemi.

    Uzun sistem istemi, RAG örnekleri ve soru şıkları kasıtlı olarak yoktur.
    Modelin görevi yalnız gözlemdir; kalıtım sonucunu Python çıkarır.
    """
    return [
        {
            "role": "user",
            "content": (
                "Görseldeki soyağacını oku. En alttaki çocuğun cinsiyetini "
                "ve hasta/sağlıklı durumunu, hemen üstündeki anne ile babanın "
                "hasta/sağlıklı durumlarını yaz. Sembol açıklamasını aile "
                "bireyi sanma. Bir alan görünmüyorsa BELİRSİZ yaz. Yalnız kısa "
                "bir Türkçe cümle yaz."
            ),
        }
    ]


def olasilik_sorusu_mu(soru: str, secenekler: dict[str, str] | None = None) -> bool:
    metin = _ascii(soru)
    return bool(
        secenekler
        and "soyagac" in metin
        and "olasil" in metin
        and ("x kromozom" in metin or "renk kor" in metin)
    )


def graf_okuma_mesajlari() -> list[dict[str, str]]:
    """Tam soyağacını cevap/şık görmeden yapılandırılmış olarak okut."""
    return [
        {
            "role": "user",
            "content": (
                "Görseldeki soyağacını yalnız gözlem olarak JSON'a çevir; "
                "soruyu çözme ve olasılık hesaplama. Her bireye G1-1 gibi "
                "benzersiz kimlik ver. Sembol açıklamasını birey sanma. "
                "Elmas ve yanında ? olan bireyi hedef=true işaretle. Yalnız "
                "şu kök nesneyi döndür: "
                '{"bireyler":[{"kimlik":"G1-1","cinsiyet":"erkek|disi|bilinmiyor",'
                '"durum":"hasta|saglikli|bilinmiyor","ebeveynler":["..."],'
                '"hedef":false}]} Görmediğin bağı uydurma.'
            ),
        }
    ]


def grafi_ayikla(ham: str) -> list[SoyagaciBireyi]:
    govde = (ham or "").strip()
    govde = re.sub(r"^```(?:json)?\s*|\s*```$", "", govde, flags=re.I | re.M).strip()
    try:
        veri = json.loads(govde)
    except json.JSONDecodeError:
        nesne_bas, nesne_son = govde.find("{"), govde.rfind("}")
        liste_bas, liste_son = govde.find("["), govde.rfind("]")
        adaylar = []
        if nesne_bas >= 0 and nesne_son > nesne_bas:
            adaylar.append(govde[nesne_bas : nesne_son + 1])
        if liste_bas >= 0 and liste_son > liste_bas:
            adaylar.append(govde[liste_bas : liste_son + 1])
        veri = None
        for aday in adaylar:
            try:
                veri = json.loads(aday)
                break
            except json.JSONDecodeError:
                continue
        if veri is None:
            return []
    satirlar = veri.get("bireyler") if isinstance(veri, dict) else veri
    if not isinstance(satirlar, list):
        return []
    sonuc: list[SoyagaciBireyi] = []
    for satir in satirlar:
        if not isinstance(satir, dict):
            continue
        kimlik = str(satir.get("kimlik") or satir.get("id") or "").strip()
        cinsiyet = _ascii(str(satir.get("cinsiyet") or satir.get("gender") or ""))
        durum = _ascii(str(satir.get("durum") or satir.get("status") or ""))
        ceviri_cinsiyet = {"male": "erkek", "female": "disi", "unknown": "bilinmiyor"}
        ceviri_durum = {"affected": "hasta", "unaffected": "saglikli", "unknown": "bilinmiyor"}
        cinsiyet = ceviri_cinsiyet.get(cinsiyet, cinsiyet)
        durum = ceviri_durum.get(durum, durum)
        ebeveynler = satir.get("ebeveynler") or satir.get("parents") or []
        if not kimlik or cinsiyet not in {"erkek", "disi", "bilinmiyor"}:
            continue
        if durum not in {"hasta", "saglikli", "bilinmiyor"}:
            continue
        sonuc.append(
            SoyagaciBireyi(
                kimlik=kimlik,
                cinsiyet=cinsiyet,
                durum=durum,
                ebeveynler=tuple(str(x) for x in ebeveynler if str(x)),
                hedef=bool(satir.get("hedef") or satir.get("target")),
            )
        )
    kimlikler = {b.kimlik for b in sonuc}
    if len(kimlikler) != len(sonuc) or not any(b.hedef for b in sonuc):
        return []
    return sonuc


def _mutant_aktarim_olasiliklari(bireyler: list[SoyagaciBireyi]) -> dict[str, Fraction]:
    """Dişilerin mutant X aktarma olasılığını gözlenen soyağacından çıkar."""
    birey = {b.kimlik: b for b in bireyler}
    aktarim: dict[str, Fraction] = {}
    for b in bireyler:
        if b.cinsiyet != "disi":
            continue
        if b.durum == "hasta":
            aktarim[b.kimlik] = Fraction(1)

    # Hasta erkek mutant X'i anneden alır; sağlıklı anne zorunlu taşıyıcıdır.
    for cocuk in bireyler:
        if cocuk.cinsiyet != "erkek" or cocuk.durum != "hasta":
            continue
        anneler = [birey[p] for p in cocuk.ebeveynler if p in birey and birey[p].cinsiyet == "disi"]
        for anne in anneler:
            if anne.durum == "saglikli":
                aktarim[anne.kimlik] = Fraction(1, 2)

    # Bilinen ebeveynlerden sağlıklı kızın taşıyıcılık olasılığını ilerlet.
    for _ in range(len(bireyler) + 1):
        degisti = False
        for kiz in bireyler:
            if kiz.cinsiyet != "disi" or kiz.durum != "saglikli" or len(kiz.ebeveynler) != 2:
                continue
            anne = next(
                (birey[p] for p in kiz.ebeveynler if p in birey and birey[p].cinsiyet == "disi"),
                None,
            )
            baba = next(
                (birey[p] for p in kiz.ebeveynler if p in birey and birey[p].cinsiyet == "erkek"),
                None,
            )
            if anne is None or baba is None:
                continue
            anne_x = aktarim.get(anne.kimlik)
            if anne_x is None:
                continue
            baba_x = Fraction(1) if baba.durum == "hasta" else Fraction(0)
            # Sağlıklı olduğu gözlenen kız iki mutant X alamaz. Koşullu
            # taşıyıcılık P(tek mutant)/P(sağlıklı).
            tek = baba_x * (1 - anne_x) + (1 - baba_x) * anne_x
            saglikli = 1 - baba_x * anne_x
            if saglikli <= 0:
                continue
            # `aktarim` taşıyıcılık değil, gametin mutant olasılığıdır;
            # taşıyıcı kız mutant aleli gametlerinin yarısına verir.
            yeni = tek / saglikli / 2
            if aktarim.get(kiz.kimlik) != yeni:
                aktarim[kiz.kimlik] = yeni
                degisti = True
        if not degisti:
            break
    return aktarim


def x_cekinik_olasilik_coz(
    soru: str,
    secenekler: dict[str, str],
    bireyler: list[SoyagaciBireyi],
) -> SoyagaciSonucu | None:
    if not olasilik_sorusu_mu(soru, secenekler):
        return None
    hedefler = [b for b in bireyler if b.hedef and len(b.ebeveynler) == 2]
    if len(hedefler) != 1:
        return None
    hedef = hedefler[0]
    harita = {b.kimlik: b for b in bireyler}
    anne = next(
        (harita[p] for p in hedef.ebeveynler if p in harita and harita[p].cinsiyet == "disi"),
        None,
    )
    baba = next(
        (harita[p] for p in hedef.ebeveynler if p in harita and harita[p].cinsiyet == "erkek"),
        None,
    )
    if anne is None or baba is None:
        return None
    aktarim = _mutant_aktarim_olasiliklari(bireyler)
    anne_x = aktarim.get(anne.kimlik)
    if anne_x is None:
        return None
    baba_x = Fraction(1) if baba.durum == "hasta" else Fraction(0)
    erkek_hasta = anne_x
    kiz_hasta = anne_x * baba_x
    olasilik = (erkek_hasta + kiz_hasta) / 2

    eslesen: list[str] = []
    for harf, metin in secenekler.items():
        kesir = re.search(r"\b(\d+)\s*/\s*(\d+)\b", metin)
        deger = None
        if kesir:
            deger = Fraction(int(kesir.group(1)), int(kesir.group(2)))
        elif metin.strip().isdigit():
            deger = Fraction(int(metin.strip()))
        if deger == olasilik:
            eslesen.append(harf.upper())
    if len(eslesen) != 1:
        return None
    return SoyagaciSonucu(
        eslesen[0],
        (
            f"Görsel grafında hedef bireyin annesi {anne.kimlik}, babası {baba.kimlik} olarak okundu.",
            f"Annenin mutant X aktarma olasılığı {anne_x}, babanın mutant X aktarması {baba_x} olarak hesaplandı.",
            f"Cinsiyet bilinmediği için hasta erkek ve hasta kız olasılıklarının ortalaması {olasilik} olur.",
            f"{olasilik} değerini veren seçenek {eslesen[0]} olduğundan cevap {eslesen[0]}'dir.",
        ),
    )


def aileyi_ayikla(ham: str) -> CekirdekAile | None:
    """Kısa VLM gözlemini katı bir çekirdek aile kaydına çevir."""
    metin = _ascii(ham)
    if not metin or "belirsiz" in metin:
        return None

    # Tercih edilen etiketli biçimi de kabul et; model kimi sürümlerde kısa
    # cümle yerine kendiliğinden bu düzeni kullanıyor.
    cocuk = re.search(
        r"cocuk\s*=\s*(disi|erkek)\s*[,;/ -]+\s*(hasta|saglikli)", metin
    )
    anne = re.search(r"anne\s*=\s*(hasta|saglikli)", metin)
    baba = re.search(r"baba\s*=\s*(hasta|saglikli)", metin)
    if cocuk and anne and baba:
        return CekirdekAile(
            cocuk_cinsiyet=cocuk.group(1),
            cocuk_hasta=cocuk.group(2) == "hasta",
            anne_hasta=anne.group(1) == "hasta",
            baba_hasta=baba.group(1) == "hasta",
        )

    # Bazı Qwen3-VL sürümleri kısa cümle yerine üç etiketli satır
    # döndürür: "En alttaki çocuk: Hasta dişi / anne: Sağlıklı ...".
    # Noktalama `sadelestir` ile kalktığı için iki nokta isteğe bağlıdır.
    satir_cocuk = re.search(
        r"(?:en\s+alttaki\s+)?cocuk\s+(hasta|saglikli)\s+(disi|erkek)", metin
    )
    satir_anne = re.search(r"anne\s+(hasta|saglikli)(?:\s+disi)?", metin)
    satir_baba = re.search(r"baba\s+(hasta|saglikli)(?:\s+erkek)?", metin)
    if satir_cocuk and satir_anne and satir_baba:
        return CekirdekAile(
            cocuk_cinsiyet=satir_cocuk.group(2),
            cocuk_hasta=satir_cocuk.group(1) == "hasta",
            anne_hasta=satir_anne.group(1) == "hasta",
            baba_hasta=satir_baba.group(1) == "hasta",
        )

    # Canlı Qwen3-VL çıktısı: "En alttaki çocuk bir hasta dişi ...
    # anne ve babanın her ikisi de sağlıklıdır". Çocuk cümlesini
    # ebeveyn cümlesinden ayırarak "hasta" sözcüğünün yanlış bireye
    # bağlanmasını engelle.
    cocuk_parcasi = metin.split("anne", 1)[0].split("baba", 1)[0]
    cinsiyet = ""
    if re.search(r"(?:hasta|saglikli)\s+(?:bir\s+)?disi", cocuk_parcasi):
        cinsiyet = "disi"
    elif re.search(r"(?:hasta|saglikli)\s+(?:bir\s+)?erkek", cocuk_parcasi):
        cinsiyet = "erkek"
    if not cinsiyet:
        return None
    if "hasta" in cocuk_parcasi and "saglikli" not in cocuk_parcasi:
        cocuk_hasta = True
    elif "saglikli" in cocuk_parcasi and "hasta" not in cocuk_parcasi:
        cocuk_hasta = False
    else:
        return None

    ikisi_saglikli = bool(
        re.search(
            r"anne\s+(?:ve|ile)\s+baba\w*\s+(?:her\s+ikisi\s+de\s+)?saglikli",
            metin,
        )
        or re.search(r"anne\s+ve\s+baba\w*\s+her\s+ikisi\s+de\s+saglikli", metin)
    )
    ikisi_hasta = bool(
        re.search(
            r"anne\s+(?:ve|ile)\s+baba\w*\s+(?:her\s+ikisi\s+de\s+)?hasta",
            metin,
        )
    )
    if ikisi_saglikli == ikisi_hasta:
        return None
    return CekirdekAile(
        cocuk_cinsiyet=cinsiyet,
        cocuk_hasta=cocuk_hasta,
        anne_hasta=ikisi_hasta,
        baba_hasta=ikisi_hasta,
    )


def _ifade_modlari(soru: str) -> list[str]:
    """Desteklenen kalıtım ifadelerini soru içindeki sıralarıyla bul."""
    metin = _ascii(soru)
    desenler = {
        "otozomal_cekinik": r"otozomal\s+cekinik",
        "otozomal_baskin": r"otozomal\s+baskin",
        "x_cekinik": r"(?:x\s+kromozom\w*|x\s*e\s*bagli).*?cekinik",
    }
    bulunan: list[tuple[int, str]] = []
    for mod, desen in desenler.items():
        eslesme = re.search(desen, metin)
        if eslesme:
            bulunan.append((eslesme.start(), mod))
    return [mod for _konum, mod in sorted(bulunan)]


def _uyumlu_modlar(aile: CekirdekAile) -> set[str]:
    """Klasik tam penetrans/yeni mutasyon yok varsayımıyla uyumlu modlar."""
    if not aile.cocuk_hasta:
        # Bu dar katman yalnız hasta çocuk üzerinden kesin eleme yapıyor.
        return set()

    uyumlu = {"otozomal_cekinik"}
    # Hasta çocuk + iki sağlıklı ebeveyn, otozomal baskınla bağdaşmaz.
    if aile.anne_hasta or aile.baba_hasta:
        uyumlu.add("otozomal_baskin")

    # X'e bağlı çekinik hasta kız mutant X'i babadan da almak zorundadır.
    # Hasta erkek çocukta ise anne sağlıklı taşıyıcı olabilir.
    if aile.cocuk_cinsiyet == "erkek" or aile.baba_hasta:
        uyumlu.add("x_cekinik")
    return uyumlu


def _romen_kumesi(metin: str) -> frozenset[int] | None:
    sade = _ascii(metin).upper()
    jetonlar = re.findall(r"\b(?:IV|III|II|I|LI|L|[1-4])\b", sade)
    if not jetonlar:
        return None
    donusum = {
        "I": 1,
        "L": 1,   # OCR: büyük I yerine küçük l
        "1": 1,
        "II": 2,
        "LI": 2,  # OCR: "lI"
        "2": 2,
        "III": 3,
        "3": 3,
        "IV": 4,
        "4": 4,
    }
    return frozenset(donusum[j] for j in jetonlar)


def uyumluluk_coz(
    soru: str,
    secenekler: dict[str, str],
    aile: CekirdekAile,
) -> SoyagaciSonucu | None:
    """Okunan aileyi desteklenen ifadelere uygula ve tek şıkka bağla."""
    if not uyumluluk_sorusu_mu(soru, secenekler):
        return None
    modlar = _ifade_modlari(soru)
    uyumlu = _uyumlu_modlar(aile)
    if not uyumlu:
        return None
    dogru = frozenset(i for i, mod in enumerate(modlar, 1) if mod in uyumlu)
    eslesen = [
        harf.upper()
        for harf, metin in secenekler.items()
        if _romen_kumesi(metin) == dogru
    ]
    if len(eslesen) != 1:
        return None

    durum = "hasta" if aile.cocuk_hasta else "sağlıklı"
    cinsiyet = "kız" if aile.cocuk_cinsiyet == "disi" else "erkek"
    anne = "hasta" if aile.anne_hasta else "sağlıklı"
    baba = "hasta" if aile.baba_hasta else "sağlıklı"
    adimlar = [
        f"Görselde {anne} anne ve {baba} babanın {durum} {cinsiyet} çocuğu var.",
        "Sağlıklı iki ebeveynden hasta çocuk, otozomal çekinik "
        "kalıtımla bağdaşabilir; otozomal baskınla bağdaşmaz."
        if not aile.anne_hasta and not aile.baba_hasta
        else "Hasta bir ebeveyn bulunduğu için otozomal baskın kalıtım "
        "yalnız bu çekirdek aile verisiyle elenemez.",
    ]
    if aile.cocuk_cinsiyet == "disi":
        adimlar.append(
            "X'e bağlı çekinik hasta kız için babanın da hasta olması "
            f"gerekir; baba {baba} olduğu için bu olasılık "
            + ("elenmez." if aile.baba_hasta else "elenir.")
        )
    else:
        adimlar.append(
            "X'e bağlı çekinik hasta erkek, sağlıklı taşıyıcı bir "
            "anneden doğabileceği için yalnız bu veriyle elenemez."
        )
    adimlar.append(
        "Uyumlu ifadeler "
        + ", ".join(("I", "II", "III", "IV")[i - 1] for i in sorted(dogru))
        + f" olduğundan cevap {eslesen[0]} şıkkıdır."
    )
    return SoyagaciSonucu(eslesen[0], tuple(adimlar))
