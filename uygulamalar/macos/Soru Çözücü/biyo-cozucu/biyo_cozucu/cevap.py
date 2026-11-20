"""Cevap metninin kanonikleştirilmesi ve karşılaştırılması.

Bu üç fonksiyon `cozucu.py` içindeydi ve oradan yeniden dışa veriliyor.
Buraya taşınmalarının sebebi bağımlılık yönü: kalıtım çözücüsü (hesap
sonucunu şıkka bağlar) ve kanıt kalite kapısı (çözümün vardığı harf ile
kayıtlı cevabın çelişip çelişmediğine bakar) bu fonksiyonlara muhtaç,
ama `hafiza`/`kalitim` → `cozucu` importu döngü yaratıyor.
"""

from __future__ import annotations

import re

from . import kesir
from .metin import sadelestir

# Cevabın başındaki şık işareti: "E) ...", "b. ...".
_SIK_ONEKI = re.compile(r"^\s*([A-EÇĞİÖŞÜa-eçğıöşü])\s*[).]")


def tek_harf(metin: str) -> str:
    """Metindeki SON tek-harf sözcüğü: "c", "c şıkkı", "cevap c" → "c".

    Son olması önemli: "Cevap: B" gibi bir dizede ilk karakteri almak "C"
    verirdi. Bu fonksiyon hem cevap karşılaştırmasında hem şık
    kanonikleştirmesinde kullanılıyor — ikisi ayrışırsa biri diğerinin
    ürettiği cevabı tanımaz.
    """
    # `sadelestir` noktalamayı atar: "b) Krebs" → "b krebs". `esitle` kullanmak
    # "b)" jetonunu iki karakter bırakıp tek-harf saymamasına yol açıyordu.
    parcalar = [p for p in sadelestir(metin).split() if len(p) == 1 and p.isalpha()]
    return parcalar[-1] if parcalar else ""


def sik_harfi(ham: str, secenekler: dict[str, str], *, soru: str = "") -> str:
    """Modelin verdiği cevabı geçerli bir şık harfine çevirir; olmazsa "".

    Dört yol sırayla denenir: cevabın kendisi bir şık harfiyse; içindeki son
    tek-harf sözcük bir şıksa ("Cevap: B"); cevap metni bir şıkkın METNİYLE
    eşleşiyorsa ("Yalnız III" → C); son olarak cevap SAYISAL bir değerse
    ("1/8") şıkların sayısal okumasıyla eşleşiyorsa. Hiçbiri tutmazsa boş
    döner ve çağıran bunu uyarıya çevirir.

    Eskiden burada `ham.strip(".)").upper()[:1]` vardı: ilk karakteri şık
    harfi sayıyordu. "Cevap: B" → "C", "Doğru cevap E seçeneğidir" → "D"
    olarak SESSİZCE kaydediliyordu — harf A-E aralığında olduğu için geçerli
    şık sanılıyor, uyarı da güven düşüşü de olmuyordu.

    Sayısal yol ÖLÇÜLMÜŞ bir hatayı kapatıyor: kesir şıkları PDF'ten iki
    satıra düşüyor ("8\\n1" = 1/8, bkz. `kesir`). Model doğru cevabı "1/8"
    diye verdiğinde metinsel eşleşme tutmuyor, cevap "şıklarla eşleşmiyor"
    sayılıyor ve güveni 0,3'e kırpılıyordu — yani DOĞRU cevap, yalnız biçim
    yüzünden yanlış muamelesi görüyordu. Soru bankasında böyle 40 soru var,
    35'i `kalitim_hesabi`.
    """
    if not ham:
        return ""
    gecerli = {h.upper(): h for h in secenekler}
    dogrudan = ham.strip(".) ").upper()
    if len(dogrudan) == 1 and dogrudan in gecerli:
        return dogrudan
    # Baştaki "E) ..." / "b. ..." kalıbı, son-tek-harf kuralından ÖNCE gelmeli:
    # "E) I, II ve III" cevabında son tek harf romen rakamı "I"dır.
    bas = _SIK_ONEKI.match(ham)
    if bas and bas.group(1).upper() in gecerli:
        return bas.group(1).upper()
    harf = tek_harf(ham).upper()
    if harf in gecerli:
        return harf
    aday = sadelestir(ham)
    if aday:
        for h, metin in secenekler.items():
            if sadelestir(metin) == aday:
                return h.upper()
    return _sayisal_sik(ham, secenekler, soru=soru)


def _sayisal_sik(ham: str, secenekler: dict[str, str], *, soru: str = "") -> str:
    """Sayısal cevabı ("1/8", "3:1") şıkların sayısal okumasıyla eşler.

    Eşleşme TEK bir şıkta olmalı. Birden çok şık aynı değere okunuyorsa
    (yığın yönü yanlış kestirilmiş olabilir) boş döner: kendinden emin
    yanlış bir eşleşme, eşleşmemekten daha zararlıdır.
    """
    aranan = kesir.oku(ham, soru=soru)
    if aranan is None:
        return ""
    bulunan = [
        h.upper()
        for h, metin in secenekler.items()
        if kesir.esdeger(kesir.oku(metin, soru=soru), aranan)
    ]
    return bulunan[0] if len(bulunan) == 1 else ""


def cevap_eslesiyor(uretilen: str, beklenen: str, *, soru: str = "") -> bool:
    """İki cevabın özde aynı olup olmadığı (şık harfi veya kısa ifade).

    Sayısal karşılaştırma metinsel eşleşmeden SONRA denenir: "1/8" ile
    "0,125" metinsel olarak farklı ama aynı cevaptır. Ölçümde bu, doğru
    üretilmiş bir cevabın yalnız yazım biçimi yüzünden yanlış sayılmasını
    önlüyor.
    """
    u, b = sadelestir(uretilen), sadelestir(beklenen)
    if not u or not b:
        return False
    if u == b:
        return True
    uh, bh = tek_harf(uretilen), tek_harf(beklenen)
    if uh and uh == bh:
        return True
    ud, bd = kesir.oku(uretilen, soru=soru), kesir.oku(beklenen, soru=soru)
    return kesir.esdeger(ud, bd)
