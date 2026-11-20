"""Yığın (çok satırlı) sayısal şıkların ve kesir ifadelerinin okunması.

PDF'ten çıkarılan kesir şıkları iki satıra düşüyor. Soru bankasında ölçüldü:
40 soruda şıkların tamamı yalnız sayıdan oluşan çok satırlı metin ve bunların
35'i `kalitim_hesabi`. Bu şıkların değeri **alt satır / üst satır**:

    "AabbNnRrhh genotipinde tüm genleri çekinik gamet olasılığı" → (1/2)³ = 1/8
    doğru şık C = "8\\n1"                                        → 1/8  ✓
    "SsKk × Sskk, siyah + kısa + dişi" → 3/4 × 1/2 × 1/2 = 3/16
    doğru şık C = "16\\n3"                                       → 3/16 ✓
    "Aa × Aa, art arda iki çocuk hasta" → (1/4)² = 1/16
    doğru şık C = "16\\n1"                                       → 1/16 ✓

Ama aynı yığın biçimi, soru İKİ AYRI DEĞER istediğinde üstten alta okunur:

    "20 tetrat dizilen hücrenin (I) ve yavru hücrelerin (II) kromozom sayısı"
    doğru şık B = "40\\n20"  → I = 40, II = 20  (kesir değil, sıralı liste)

Ayrım kurallaştırılabilir ve bu modülün asıl işi budur. Varsayılan SIRALI:
sıralı bir çifti kesir sanmak, kendinden emin yanlış bir eşleşme üretir;
tersi yalnız eşleşmemeye yol açar ve mevcut metinsel yol devreye girer.

Bu modül `cevap.sik_harfi` tarafından kullanılıyor. Oradaki kusur ölçüldü:
model doğru cevabı "1/8" olarak verdiğinde şık metni "8\\n1" ile eşleşmiyor,
cevap "şıklarla eşleşmiyor" sayılıp güveni 0,3'e kırpılıyordu — yani DOĞRU
cevap, biçim yüzünden yanlış muamelesi görüyordu.
"""

from __future__ import annotations

import re
from fractions import Fraction

_SAYI_SATIRI = re.compile(r"^\s*\d+\s*$")

# Cevap YUVASI işaretleri. Parantezli olması şart: "(I)" ve "(II)" sorunun
# cevabında iki ayrı yuva olduğunu bildirir. Noktalı "I. Aile" ise varlıkları
# sıralar, cevabı bölmez — ölçümde bir soyağacı olasılık sorusu tam bu yüzden
# yanlış sınıflanıyordu ("I. Aile", "II. Aile" geçiyor ama cevap tek kesir).
_YUVA = re.compile(r"\(\s*(?:I{1,3}|IV|V)\s*\)")

# "sırasıyla", "kaç ... ve kaç ..." gibi iki değer isteyen kalıplar.
_SIRALI_IPUCU = re.compile(
    r"sırasıyla|sırayla|kaç[^.?]{0,60}?\bve\b[^.?]{0,20}?kaç|en az[^.?]{0,40}?en çok",
    re.IGNORECASE,
)

# Tek bir olasılık/oran istendiğini bildiren kalıplar.
_KESIR_IPUCU = re.compile(r"olasılı|olasıl|ihtimal|oranı\s+kaç|yüzde\s+kaç", re.IGNORECASE)

# Düz yazılmış kesir: "1/8", "3 / 16".
_DUZ_KESIR = re.compile(r"^\s*(\d+)\s*/\s*(\d+)\s*$")
# Yüzde: "%18,75", "18.75 %".
_YUZDE = re.compile(r"^\s*%\s*(\d+(?:[.,]\d+)?)\s*$|^\s*(\d+(?:[.,]\d+)?)\s*%\s*$")
# Ondalık: "0,25".
_ONDALIK = re.compile(r"^\s*(\d+(?:[.,]\d+)?)\s*$")
# Oran: "3:1", "9 : 3 : 3 : 1".
_ORAN = re.compile(r"^\s*\d+(?:\s*:\s*\d+)+\s*$")


def satirlar(sik: str) -> list[str]:
    """Çok satırlı şık metnini boş olmayan satırlara böler."""
    return [s.strip() for s in (sik or "").splitlines() if s.strip()]


def sayisal_yigin(sik: str) -> tuple[int, ...] | None:
    """Şık tamamen sayısal satırlardan oluşuyorsa satır değerleri, yoksa None."""
    parcalar = satirlar(sik)
    if len(parcalar) < 2 or not all(_SAYI_SATIRI.match(p) for p in parcalar):
        return None
    return tuple(int(p) for p in parcalar)


def yigin_yonu(soru: str, satir_sayisi: int) -> str:
    """Yığın şıkkın "kesir" mi "sirali" mi okunacağı.

    Varsayılan "sirali" — bilinçli olarak. Sıralı bir çifti kesir sanmak
    kendinden emin yanlış eşleşme üretir; tersi yalnız eşleşmemeye yol açar
    ve çağıran mevcut metinsel yola düşer.
    """
    if satir_sayisi != 2:
        # Üç ve daha fazla satır her zaman sıralı liste (X, Y, Z eşleştirmesi).
        return "sirali"
    if _YUVA.search(soru) or _SIRALI_IPUCU.search(soru):
        return "sirali"
    if _KESIR_IPUCU.search(soru):
        return "kesir"
    return "sirali"


def yigindan_kesir(yigin: tuple[int, ...]) -> Fraction | None:
    """İki satırlı sayısal yığını kesre çevirir: (payda, pay) → pay/payda.

    Olasılık 1'i aşıyorsa `None` döner. Bu bir VETO: değer 1'den büyükse
    şık bir olasılık olamaz, demek ki yığın sıralı okunmalıydı. Kural
    yanılabilir olduğu için bu ucuz denetim, yanlış sınıflandırmanın en
    zararlı yarısını (kesir sanılan sıralı çift) kesiyor.
    """
    if len(yigin) != 2:
        return None
    payda, pay = yigin
    if payda == 0:
        return None
    deger = Fraction(pay, payda)
    if deger > 1:
        return None
    return deger


def kesir_oku(metin: str) -> Fraction | None:
    """Tek satırlık kesir/yüzde/ondalık ifadeyi `Fraction`'a çevirir."""
    ham = (metin or "").strip()
    if not ham:
        return None
    duz = _DUZ_KESIR.match(ham)
    if duz:
        payda = int(duz.group(2))
        return Fraction(int(duz.group(1)), payda) if payda else None
    yuzde = _YUZDE.match(ham)
    if yuzde:
        sayi = (yuzde.group(1) or yuzde.group(2)).replace(",", ".")
        return Fraction(sayi) / 100
    ondalik = _ONDALIK.match(ham)
    if ondalik and ("," in ham or "." in ham):
        # Yalın tam sayı burada kesir sayılmaz: "16" bir olasılık değil,
        # bir sayım cevabıdır ve kesir karşılaştırmasına girmemeli.
        return Fraction(ondalik.group(1).replace(",", "."))
    return None


def oran_oku(metin: str) -> tuple[int, ...] | None:
    """"9:3:3:1" gibi oran ifadesini sadeleştirilmiş demete çevirir."""
    ham = (metin or "").strip()
    if not _ORAN.match(ham):
        return None
    sayilar = tuple(int(p) for p in re.split(r"\s*:\s*", ham))
    return sadelestir_oran(sayilar)


def sadelestir_oran(sayilar: tuple[int, ...]) -> tuple[int, ...]:
    """Oranı en büyük ortak bölenine böler: (6,2) → (3,1)."""
    from math import gcd

    bolen = 0
    for s in sayilar:
        bolen = gcd(bolen, s)
    if bolen <= 1:
        return sayilar
    return tuple(s // bolen for s in sayilar)


def oku(sik: str, *, soru: str = "") -> Fraction | tuple[int, ...] | None:
    """Şık metnini karşılaştırılabilir bir değere çevirir.

    Dönüş: kesir için `Fraction`, sıralı/oran için `tuple[int, ...]`,
    okunamıyorsa `None`. `soru` yığın yönünü belirlemek için gerekiyor.
    """
    yigin = sayisal_yigin(sik)
    if yigin is not None:
        if yigin_yonu(soru, len(yigin)) == "kesir":
            kesir = yigindan_kesir(yigin)
            if kesir is not None:
                return kesir
        return yigin
    tek = (sik or "").strip()
    kesir = kesir_oku(tek)
    if kesir is not None:
        return kesir
    # Olasılığın kesinlik uçları yalın tam sayı olarak yazılıyor: soru bankasında
    # iki soruda doğru cevap "1" (renk körü anne × kıllı kulaklı baba → oğulların
    # TAMAMI) ve "0" (dazlak olmayan babadan kız çocuğa D aleli geçemez). Yalın
    # tam sayıyı kesir saymak genelde yanlış olurdu ("16" bir sayım cevabıdır),
    # bu yüzden yalnız olasılık soruluyorken ve yalnız 0/1 için geçerli.
    if tek in {"0", "1"} and _KESIR_IPUCU.search(soru or ""):
        return Fraction(int(tek))
    return oran_oku(tek)


def esdeger(a: object, b: object) -> bool:
    """İki okunmuş değerin özde aynı olup olmadığı.

    Kesir ile oran karşılaştırılmaz (1/2 ile 1:2 aynı şey değildir); demetler
    sadeleştirilmiş hâlleriyle karşılaştırılır.
    """
    if a is None or b is None:
        return False
    if isinstance(a, Fraction) and isinstance(b, Fraction):
        return a == b
    if isinstance(a, tuple) and isinstance(b, tuple):
        return sadelestir_oran(a) == sadelestir_oran(b)
    return False


def normalize(sik: str, *, soru: str = "") -> str:
    """Şıkkı okunabilir tek satıra indirger — günlük ve uyarı metinleri için."""
    deger = oku(sik, soru=soru)
    if isinstance(deger, Fraction):
        return f"{deger.numerator}/{deger.denominator}"
    if isinstance(deger, tuple):
        return ", ".join(str(s) for s in deger)
    return " ".join((sik or "").split())
