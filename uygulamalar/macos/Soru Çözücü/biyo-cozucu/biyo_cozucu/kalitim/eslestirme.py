"""Hesap sonucunu verilen şıklardan birine bağlar — ya da hiç konuşmaz.

Bu modül çözücünün güvenlik valfi. Deterministik hesap doğru olsa bile
sorunun sorduğu şey başka olabilir (birim farkı, "kaç çeşit" yerine
"olasılık", yığın kesrin ters okunması). Serbest cevap üretmek yerine
sonucu ŞIKLARA çözmek bu riski kesiyor: sonuç tek bir şıkka oturmuyorsa
çözücü çekiliyor ve mevcut model yolu çalışıyor.

Kendinden emin yanlış cevap, cevapsızlıktan zararlıdır — kalıtım türünün
kalibrasyon çarpanı 0,442'ye inmiş olmasının sebebi de tam buydu: model
yanılırken de "eminim" diyordu.
"""

from __future__ import annotations

from fractions import Fraction

from .. import kesir
from ..cevap import sik_harfi
from .punnett import HesapSonucu

# Tam eşleşme güveni. 0,95 — 1,0 değil: çıkarım katmanı yanılabilir ve
# hesabın doğruluğu sorunun doğru okunduğunu garanti etmez.
TAM_GUVEN = 0.95
# Yalnız ters okunuşla eşleşen yığın kesir. Şıkka bağlanıyor ama incelemeye
# düşecek kadar düşük güvenle.
TERS_GUVEN = 0.60


def _sonuc_degerleri(sonuc: HesapSonucu) -> list[Fraction | tuple[int, ...] | int]:
    """Sonucun şıkla karşılaştırılabilir biçimleri."""
    degerler: list[Fraction | tuple[int, ...] | int] = []
    if sonuc.oran:
        degerler.append(sonuc.oran)
    if sonuc.deger is not None:
        degerler.append(sonuc.deger)
        if isinstance(sonuc.deger, int) and not isinstance(sonuc.deger, bool):
            # Sayım cevabı ("3 çeşit") kesir olarak da yazılmış olabilir.
            degerler.append(Fraction(sonuc.deger))
    return degerler


def _esdeger(a: object, b: object) -> bool:
    if kesir.esdeger(a, b):
        return True
    # Tam sayı ile Fraction karşılaştırması (`cesit_sayisi` sonuçları).
    if isinstance(a, int) and isinstance(b, Fraction):
        return Fraction(a) == b
    if isinstance(a, Fraction) and isinstance(b, int):
        return a == Fraction(b)
    if isinstance(a, int) and isinstance(b, int):
        return a == b
    return False


def sonuca_uyan_sik(
    sonuc: HesapSonucu,
    secenekler: dict[str, str],
    *,
    soru: str = "",
) -> tuple[str, float, list[str]]:
    """(şık harfi, güven, uyarılar). Harf boşsa çağıran mevcut yola dönmeli.

    Sıra:
      1. Şıkları sayısal olarak oku (yığın kesir yönü `soru`dan kestirilir).
      2. Tam eşleşme TEK bir şıkta ise → o şık, yüksek güven.
      3. Yalnız TERS okunuşla eşleşiyorsa → o şık, düşük güven + uyarı.
      4. Sayısal okunamıyorsa metinsel eşleşmeye düş (`sik_harfi`).
      5. Çok eşleşme ya da hiç eşleşme → boş; çözücü çekilir.
    """
    if sonuc.bos_mu() or not secenekler:
        return "", 0.0, []

    degerler = _sonuc_degerleri(sonuc)
    if not degerler:
        return "", 0.0, []

    uyarilar: list[str] = list(sonuc.varsayimlar)

    okunan = {h.upper(): kesir.oku(m, soru=soru) for h, m in secenekler.items()}
    eslesen = [
        h for h, deger in okunan.items()
        if deger is not None and any(_esdeger(d, deger) for d in degerler)
    ]
    if len(eslesen) == 1:
        guven = TAM_GUVEN
        if sonuc.varsayimlar:
            # Varsayım yapılmışsa (ör. tam bağlılık) sonuç kesin değil.
            guven = 0.70
        return eslesen[0], guven, uyarilar
    if len(eslesen) > 1:
        uyarilar.append(
            f"Hesap sonucu birden çok şıkla eşleşti ({', '.join(sorted(eslesen))}); "
            "deterministik çözüm kullanılmadı."
        )
        return "", 0.0, uyarilar

    # Ters okunuş: yığın kesir yönü yanlış kestirilmiş olabilir.
    ters = _ters_eslesme(degerler, secenekler, soru)
    if ters:
        uyarilar.append(
            "Şık kesir yönü belirsiz (PDF'ten iki satıra düşmüş); sonuç ters "
            "okunuşla eşleşti ve düşük güvenle işaretlendi."
        )
        return ters, TERS_GUVEN, uyarilar

    # Sayısal yol tutmadıysa metinsel eşleşme (genotip cevapları: "mmss").
    for deger in degerler:
        metin = _metne_cevir(deger)
        if not metin:
            continue
        harf = sik_harfi(metin, secenekler, soru=soru)
        if harf:
            return harf, TAM_GUVEN if not sonuc.varsayimlar else 0.70, uyarilar

    # Kontrol çaprazı gibi sonuçlarda değer `dagilim` anahtarında duruyor.
    for anahtar in sonuc.dagilim:
        harf = sik_harfi(anahtar, secenekler, soru=soru)
        if harf:
            return harf, TAM_GUVEN, uyarilar

    return "", 0.0, uyarilar


def _ters_eslesme(
    degerler: list, secenekler: dict[str, str], soru: str
) -> str:
    """Yığın kesri ters yönde okuyarak eşleşme arar; tek eşleşme varsa harfi."""
    adaylar: list[str] = []
    for harf, metin in secenekler.items():
        yigin = kesir.sayisal_yigin(metin)
        if not yigin or len(yigin) != 2:
            continue
        ust, alt = yigin
        if ust == 0:
            continue
        ters = Fraction(ust, alt) if alt else None
        if ters is None:
            continue
        if any(_esdeger(d, ters) for d in degerler):
            adaylar.append(harf.upper())
    return adaylar[0] if len(adaylar) == 1 else ""


def _metne_cevir(deger: object) -> str:
    if isinstance(deger, Fraction):
        return f"{deger.numerator}/{deger.denominator}"
    if isinstance(deger, tuple):
        return ":".join(str(s) for s in deger)
    if isinstance(deger, int):
        return str(deger)
    return ""
