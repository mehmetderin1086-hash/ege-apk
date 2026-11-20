"""Soruyu yapılandırılmış `Caprazlama` tanımına çevirir (tek model çağrısı).

Model burada ÇÖZMÜYOR: yalnız "anne Aa, baba Aa, çekinik çocuk olasılığı
soruluyor" bilgisini çıkarıyor. Bu bir dil işi ve 4B modelin yapabildiği
şey; hesabın kendisi (Punnett, olasılık çarpımı) yapamadığı şeydi ve saf
Python'a devredildi.

Çıkarım BAŞARISIZ OLABİLİR ve bu normaldir — `None` döndüğünde çağıran
mevcut model yoluna düşer. Uydurulmuş bir tanımla yapılan hesap, kendinden
emin yanlış bir cevap üretir ve bu cevapsızlıktan zararlıdır; bu yüzden
şema denetimi (`Caprazlama.dogrula`) sert tutuldu.
"""

from __future__ import annotations

import json
from fractions import Fraction
from typing import Any

from ..motor.temel import MotorHatasi, json_ayikla
from .tanim import BASKINLIK, ISTEK_TURLERI, KONUM, Birey, Caprazlama, Istek, Lokus

CIKARIM_ISTEMI = (
    "Aşağıdaki biyoloji sorusunu ÇÖZME. Yalnız sorudaki kalıtım kurgusunu "
    "yapılandırılmış JSON olarak çıkar. Sorudan okuyamadığın bir alanı "
    "UYDURMA; bilmiyorsan null ya da boş bırak.\n"
    "\n"
    "Alanlar:\n"
    "- lokuslar: her karakter için {ad, aleller (baskın önce), baskinlik, konum}\n"
    "  baskinlik: tam | eksik | es | coklu_alel | kan_grubu\n"
    "  konum: otozom | x | y | xy_homolog\n"
    "- ebeveynler: {etiket, genotip {lokus: \"Aa\"}, cinsiyet: disi|erkek|\"\"}\n"
    "  X'e bağlı lokusta ERKEK tek alel taşır (\"XR\"), dişi iki (\"XRXr\").\n"
    "- bagli_gruplar: aynı kromozomdaki lokus adları, ör. [[\"a\",\"d\"]]\n"
    "- krossing_orani: \"1/5\" gibi ya da null\n"
    "- istek: {tur, hedef, cocuk_sirasi, sinir, kosul}\n"
    "  tur: olasilik | fenotip_orani | genotip_orani | cesit_sayisi |\n"
    "       gamet_cesidi | gamet_olasiligi | kromozom_sayisi | kontrol_caprazi\n"
    "  hedef: {lokus: \"baskin\"|\"cekinik\"|\"heterozigot\"|\"homozigot\"|genotip}\n"
    "         cesit_sayisi'nde {\"neyin\": \"fenotip\"|\"genotip\"}\n"
    "  cocuk_sirasi: sıralı olaylar, ör. [{\"a\":\"cekinik\"},{\"a\":\"baskin\"}]\n"
    "  sinir: en_az | en_cok (gamet çeşidi sorularında)\n"
    "  kosul: DAĞILIMI DARALTAN koşul. Ayrım kritik:\n"
    "    \"ERKEK çocukların X olma olasılığı\"  → kosul {\"cinsiyet\":\"erkek\"}\n"
    "    \"X olan ERKEK çocuk olma olasılığı\"  → hedef {\"cinsiyet\":\"erkek\"}\n"
    "\n"
    "Yalnız geçerli JSON döndür, öncesinde/sonrasında açıklama yazma."
)


def _kesir_oku(deger: Any) -> Fraction | None:
    if deger is None:
        return None
    try:
        if isinstance(deger, (int, float)):
            return Fraction(deger).limit_denominator(1000)
        metin = str(deger).strip()
        if not metin:
            return None
        if "/" in metin:
            pay, payda = metin.split("/", 1)
            return Fraction(int(pay.strip()), int(payda.strip()))
        return Fraction(metin).limit_denominator(1000)
    except (ValueError, ZeroDivisionError, TypeError):
        return None


def _dize(deger: Any) -> str:
    return str(deger).strip() if isinstance(deger, (str, int, float)) else ""


def _sozluk(deger: Any) -> dict:
    return {str(a): deger[a] for a in deger} if isinstance(deger, dict) else {}


def tanimi_kur(veri: dict[str, Any]) -> Caprazlama | None:
    """Ham JSON sözlüğünü `Caprazlama`ya çevirir; şema tutmuyorsa None."""
    if not isinstance(veri, dict):
        return None

    lokuslar: list[Lokus] = []
    for ham in veri.get("lokuslar") or []:
        if not isinstance(ham, dict):
            continue
        ad = _dize(ham.get("ad"))
        aleller = tuple(
            _dize(a) for a in (ham.get("aleller") or []) if _dize(a)
        )
        if not ad or len(aleller) < 1:
            continue
        baskinlik = _dize(ham.get("baskinlik")) or "tam"
        konum = _dize(ham.get("konum")) or "otozom"
        if baskinlik not in BASKINLIK or konum not in KONUM:
            return None
        ustunluk_ham = ham.get("ustunluk") or ()
        ustunluk: tuple[tuple[str, ...], ...] = ()
        if isinstance(ustunluk_ham, list) and ustunluk_ham:
            kademeler = []
            for kademe in ustunluk_ham:
                if isinstance(kademe, list):
                    kademeler.append(tuple(_dize(a) for a in kademe if _dize(a)))
                elif _dize(kademe):
                    kademeler.append((_dize(kademe),))
            ustunluk = tuple(k for k in kademeler if k)
        # Kan grubu için üstünlük verilmediyse standart kademeleri koy: modelin
        # bunu her seferinde doğru yazmasını beklemek gereksiz bir kırılganlık.
        if baskinlik == "kan_grubu" and not ustunluk and set(aleller) >= {"A", "B", "0"}:
            ustunluk = (("A", "B"), ("0",))
        lokuslar.append(
            Lokus(ad=ad, aleller=aleller, baskinlik=baskinlik, konum=konum,
                  ustunluk=ustunluk)
        )
    if not lokuslar:
        return None

    ebeveynler: list[Birey] = []
    for ham in veri.get("ebeveynler") or []:
        if not isinstance(ham, dict):
            continue
        genotip = {
            str(a): _dize(d) for a, d in _sozluk(ham.get("genotip")).items() if _dize(d)
        }
        cinsiyet = _dize(ham.get("cinsiyet"))
        cinsiyet = {"dişi": "disi", "kadın": "disi", "erkek": "erkek"}.get(
            cinsiyet, cinsiyet
        )
        if cinsiyet not in {"disi", "erkek", ""}:
            cinsiyet = ""
        ebeveynler.append(
            Birey(etiket=_dize(ham.get("etiket")), genotip=genotip, cinsiyet=cinsiyet)
        )
    if not ebeveynler:
        return None

    bagli: list[tuple[str, ...]] = []
    for grup in veri.get("bagli_gruplar") or []:
        if isinstance(grup, list):
            adlar = tuple(_dize(a) for a in grup if _dize(a))
            if len(adlar) >= 2:
                bagli.append(adlar)

    ham_istek = _sozluk(veri.get("istek"))
    tur = _dize(ham_istek.get("tur")) or "olasilik"
    if tur not in ISTEK_TURLERI:
        return None
    cocuk_sirasi = tuple(
        _sozluk(o) for o in (ham_istek.get("cocuk_sirasi") or []) if isinstance(o, dict)
    )
    istek = Istek(
        tur=tur,
        hedef=_sozluk(ham_istek.get("hedef")),
        cocuk_sirasi=cocuk_sirasi,
        sinir=_dize(ham_istek.get("sinir")),
        kosul=_sozluk(ham_istek.get("kosul")),
    )

    caprazlama = Caprazlama(
        lokuslar=tuple(lokuslar),
        ebeveynler=tuple(ebeveynler),
        bagli_gruplar=tuple(bagli),
        krossing_orani=_kesir_oku(veri.get("krossing_orani")),
        istek=istek,
    )
    if caprazlama.dogrula():
        return None
    return caprazlama


def caprazlama_cikar(
    motor,
    soru: str,
    secenekler: dict[str, str] | None = None,
    *,
    azami_token: int = 400,
) -> Caprazlama | None:
    """Modelden yapılandırılmış tanımı ister. Hiçbir durumda istisna sızdırmaz."""
    if motor is None or not soru.strip():
        return None
    govde = soru.strip()
    if secenekler:
        # Şıklar isteme GİRİYOR: cevabın birimi (oran mı, olasılık mı, sayım
        # mı) çoğu soruda yalnız şıklardan anlaşılıyor.
        govde += "\n" + "\n".join(
            f"{h}) {m}" for h, m in sorted(secenekler.items())
        )
    mesajlar = [
        {"role": "system", "content": CIKARIM_ISTEMI},
        {"role": "user", "content": govde},
    ]
    try:
        ham = motor.uret(mesajlar, sicaklik=0.0, azami_token=azami_token)
    except MotorHatasi:
        return None
    try:
        veri = json_ayikla(ham)
    except (ValueError, json.JSONDecodeError):
        return None
    try:
        return tanimi_kur(veri)
    except (ValueError, TypeError, KeyError, IndexError):
        return None
