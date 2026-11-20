"""Sıralama, eşleştirme, sayısal ve görsel cevaplar için yapısal puanlama."""

from __future__ import annotations

import ast
import math
import re

from rapidfuzz import fuzz

from ..metin import eslesme_bicimi
from ..modeller import PuanSonucu, Soru, SoruTipi
from .ayarlar import PuanlamaAyar


def soru_turunu_belirle(metin: str) -> SoruTipi:
    norm = eslesme_bicimi(metin)
    kurallar = [
        (SoruTipi.ESLESTIRME, ("eslestir", "eşleştir")),
        (SoruTipi.SIRALAMA, ("sirala", "sırala", "sirasina koy", "sırasına koy")),
        (SoruTipi.COKTAN_SECMELI, ("seceneklerden", "doğru seçene", "hangi sik")),
        (SoruTipi.GRAFIK, ("grafik", "eksen", "egriyi çiz")),
        (SoruTipi.CIZIM, ("sekil çiz", "şekil çiz", "sema çiz", "şema çiz")),
        (SoruTipi.TABLO, ("tabloyu doldur", "tablo olustur")),
        (SoruTipi.DENEY_TASARLAMA, ("deney tasarla", "kontrollu deney")),
        (SoruTipi.ETIK, ("etik", "intihal", "bilimsel dürüst")),
        (SoruTipi.SAYISAL, ("hesapla", "kaçtır", "sonucu bulun")),
        (SoruTipi.FORMUL_ISPAT, ("ispatla", "formulu", "formülü")),
        (SoruTipi.YORUMLAMA, ("yorumlay", "değerlendir", "aciklayarak")),
    ]
    for tip, isaretler in kurallar:
        if any(isaret in norm for isaret in isaretler):
            return tip
    return SoruTipi.ACIK_UCLU


def _lcs_uzunlugu(a: list[str], b: list[str]) -> int:
    onceki = [0] * (len(b) + 1)
    for x in a:
        simdiki = [0]
        for j, y in enumerate(b, start=1):
            simdiki.append(
                onceki[j - 1] + 1
                if fuzz.ratio(x, y) >= 82
                else max(onceki[j], simdiki[j - 1])
            )
        onceki = simdiki
    return onceki[-1]


# Sıralama öğesinin cevap metnindeki konumunu bulurken kabul edilen
# en düşük benzerlik. Tam `find()` OCR'daki tek harf hatasında öğeyi
# tümüyle kaybettiriyordu.
SIRALAMA_KONUM_ESIGI = 84


def _bulanik_konum_skorlu(norm_cevap: str, oge: str) -> tuple[int, float, bool]:
    """(konum, skor, tam_eslesme) — öğe cevapta yoksa konum ``-1``."""
    if not oge:
        return -1, 0.0, False
    tam = norm_cevap.find(oge)
    if tam >= 0:
        return tam, 100.0, True
    # Kayan kelime penceresi: öğe kaç kelimeyse cevapta o uzunlukta pencereler
    # gezilir; en iyi benzerlik eşiği geçerse pencerenin konumu döner.
    oge_kelime_sayisi = max(1, len(oge.split()))
    kelimeler = norm_cevap.split()
    if not kelimeler:
        return -1, 0.0, False
    en_iyi_skor, en_iyi_konum = 0.0, -1
    for i in range(len(kelimeler) - oge_kelime_sayisi + 1):
        pencere = " ".join(kelimeler[i: i + oge_kelime_sayisi])
        skor = fuzz.ratio(oge, pencere)
        if skor > en_iyi_skor:
            en_iyi_skor = skor
            # Pencerenin metindeki gerçek karakter konumu
            en_iyi_konum = len(" ".join(kelimeler[:i])) + (1 if i else 0)
    if en_iyi_skor >= SIRALAMA_KONUM_ESIGI:
        return en_iyi_konum, en_iyi_skor, False
    return -1, en_iyi_skor, False


def siralama_puanla(cevap: str, soru: Soru) -> PuanSonucu:
    beklenen = soru.anahtar.siralama or soru.anahtar.dogru_cevaplar
    if not cevap.strip() or not beklenen:
        return PuanSonucu(
            0.0, soru.puan, 0.0 if beklenen else 1.0,
            ["Sıralama cevabı veya yapısal anahtar eksik."],
            incele=not bool(beklenen),
        )
    norm_cevap = eslesme_bicimi(cevap)
    # Her konum yalnız BİR öğeye verilir. Aksi halde birbirine benzeyen
    # anahtar öğeleri ("Profaz I" / "Profaz II") aynı pencereye kilitlenir,
    # öğrencinin hiç yazmadığı öğe "bulundu" sayılır ve hem puan şişer hem
    # eksik cevap inceleme kuyruğuna düşmez.
    adaylar: list[tuple[float, int, str, bool]] = []  # (-skor, konum, oge, tam)
    for oge in beklenen:
        oge_norm = eslesme_bicimi(oge)
        konum, skor, tam = _bulanik_konum_skorlu(norm_cevap, oge_norm)
        if konum >= 0:
            adaylar.append((-skor, konum, oge_norm, tam))
    adaylar.sort()
    alinan_konumlar: set[int] = set()
    alinan_ogeler: set[str] = set()
    secilen: list[tuple[int, str, bool]] = []
    for _negskor, konum, oge_norm, tam in adaylar:
        if konum in alinan_konumlar or oge_norm in alinan_ogeler:
            continue
        alinan_konumlar.add(konum)
        alinan_ogeler.add(oge_norm)
        secilen.append((konum, oge_norm, tam))
    secilen.sort(key=lambda x: x[0])
    bulunan = [(k, o) for k, o, _t in secilen]
    ogrenci = [x[1] for x in bulunan]
    tam_eslesen = sum(1 for _k, _o, t in secilen if t)
    dogru = [eslesme_bicimi(x) for x in beklenen]
    lcs = _lcs_uzunlugu(dogru, ogrenci)
    oran = lcs / len(dogru)
    puan = round(soru.puan * oran * 2) / 2
    aciklama = (
        f"{lcs}/{len(dogru)} öğe doğru göreli sırada; "
        f"{puan:g}/{soru.puan:g} puan."
    )
    # Kesinlik ölçütü TAM eşleşmedir: bulanık eşleşmeyle kurtarılan öğeler
    # kutuyu otomatik kesinleştirmemeli, öğretmen görsele bakmalı.
    kesin = len(ogrenci) == len(dogru) and tam_eslesen == len(dogru)
    return PuanSonucu(
        puan,
        soru.puan,
        0.9 if kesin else 0.62,
        [aciklama],
        incele=not kesin,
        risk=0.15 if kesin else 0.45,
        kararlar=[
            {
                "tur": "siralama",
                "beklenen": beklenen,
                "bulunan": ogrenci,
                "dogru_sira_ogesi": lcs,
                "puan": puan,
            }
        ],
        aciklama=aciklama,
        puanlama_guveni=0.9 if kesin else 0.62,
    )


# Ayraçlı biçim: "1 - c", "A: mitokondri", "2 = b", "3 → d", "I ile II".
# Sol ve sağ öğe çok sözcüklü olabilir ("hücre zarı - A"); ayraç
# çevresinde en az bir boşluk ya da noktalama aranır.
_ESLESTIRME = re.compile(
    r"(?P<sol>[^\n,;=:→)]+?)\s*(?:[-–—:=→)]|\bile\b)\s*"
    r"(?P<sag>[^\n,;=:→)-]+)",
    re.IGNORECASE,
)
# Ayraçsız bitişik biçim: "1c", "2a" (öğrenciler sık böyle yazıyor).
_ESLESTIRME_BITISIK = re.compile(r"\b(?P<sol>\d{1,2})\s*(?P<sag>[A-Za-z])\b")
# Hizalı sütun biçimi: satır başına tek çift, aralarında yalnız boşluk.
_ESLESTIRME_SUTUN = re.compile(
    r"^\s*(?P<sol>\S+(?:\s\S+)*?)\s{2,}"
    r"(?P<sag>\S+(?:\s\S+)*)\s*$"
)

# Sol öğenin anahtardaki karşılığına hizalanması için asgari benzerlik.
ESLESTIRME_SOL_ESIGI = 80


def eslestirme_cozumle(cevap: str, sol_anahtarlar: list[str]) -> dict[str, str]:
    """Öğrenci cevabından (sol → sağ) eşleştirme çiftlerini çıkarır.

    Üç yazım biçimini de tanır (ayraçlı, bitişik, hizalı sütun); ardından
    sol öğeleri anahtardaki sol kümeye bulanık hizalar. Her sol öğe yalnız
    bir kez eşlenir (en iyi skor kazanır). Sağ öğenin tekrarı ENGELLENMEZ:
    öğrenci aynı seçeneği iki soruya yazmışsa bu onun hatasıdır ve iki
    eşleştirme de kendi başına değerlendirilmelidir.
    """
    ham_ciftler: list[tuple[str, str]] = []
    for satir in cevap.splitlines():
        sutun = _ESLESTIRME_SUTUN.match(satir)
        if sutun:
            ham_ciftler.append((sutun.group("sol"), sutun.group("sag")))
            continue
        ham_ciftler.extend(
            (e.group("sol"), e.group("sag")) for e in _ESLESTIRME.finditer(satir)
        )
        ham_ciftler.extend(
            (e.group("sol"), e.group("sag"))
            for e in _ESLESTIRME_BITISIK.finditer(satir)
        )
    if not ham_ciftler:
        return {}

    normal_anahtarlar = [eslesme_bicimi(k) for k in sol_anahtarlar]
    # (skor, anahtar_sol, sag) üçlüleri; en iyi eşleşmeden başlayarak yerleştir.
    adaylar: list[tuple[float, str, str]] = []
    for sol, sag in ham_ciftler:
        sol_norm, sag_norm = eslesme_bicimi(sol), eslesme_bicimi(sag)
        if not sol_norm or not sag_norm:
            continue
        if not normal_anahtarlar:
            adaylar.append((100.0, sol_norm, sag_norm))
            continue
        for anahtar in normal_anahtarlar:
            skor = float(fuzz.ratio(sol_norm, anahtar))
            if skor >= ESLESTIRME_SOL_ESIGI:
                adaylar.append((skor, anahtar, sag_norm))
    adaylar.sort(key=lambda x: -x[0])
    sonuc: dict[str, str] = {}
    for _skor, sol, sag in adaylar:
        if sol in sonuc:
            continue
        sonuc[sol] = sag
    return sonuc


def eslestirme_puanla(cevap: str, soru: Soru) -> PuanSonucu:
    beklenen = {
        eslesme_bicimi(k): eslesme_bicimi(v)
        for k, v in soru.anahtar.eslestirmeler.items()
    }
    bulunan = eslestirme_cozumle(cevap, list(soru.anahtar.eslestirmeler.keys()))
    if not beklenen:
        return PuanSonucu(
            0.0, soru.puan, 0.0,
            ["Eşleştirme anahtarı yapısal olarak tanımlanmamış."],
            incele=True,
        )
    dogru = 0
    kararlar = []
    for sol, sag in beklenen.items():
        ogrenci = bulunan.get(sol, "")
        uydu = bool(ogrenci and fuzz.ratio(sag, ogrenci) >= 84)
        dogru += int(uydu)
        kararlar.append(
            {"tur": "eslestirme", "sol": sol, "beklenen": sag,
             "bulunan": ogrenci, "dogru": uydu}
        )
    puan = round(soru.puan * dogru / len(beklenen) * 2) / 2
    aciklama = f"{dogru}/{len(beklenen)} eşleştirme doğru."
    guven = 0.92 if len(bulunan) == len(beklenen) else 0.58
    return PuanSonucu(
        puan, soru.puan, guven, [aciklama],
        incele=len(bulunan) != len(beklenen),
        risk=1.0 - guven,
        kararlar=kararlar,
        aciklama=aciklama,
        puanlama_guveni=guven,
    )


_SAYI = re.compile(r"[-+]?(?:\d+(?:[.,]\d+)?|[.,]\d+)")


def _sayilar(metin: str) -> list[float]:
    sonuc = []
    for ham in _SAYI.findall(metin):
        try:
            sonuc.append(float(ham.replace(",", ".")))
        except ValueError:
            continue
    return sonuc


# Öğrencinin nihai sonucu işaretlediği ifadeler.
_SONUC_ISARETI = re.compile(
    r"(?:sonuç|sonuc|cevap|bulunur|buldum|bulduk|toplam|=)\s*:?\s*",
    re.IGNORECASE,
)
# "1/2" gibi kesirli anahtarlar: _sayilar bunu [1.0, 2.0] diye böler.
_KESIR = re.compile(r"(?<![\d.,])(\d+(?:[.,]\d+)?)\s*/\s*(\d+(?:[.,]\d+)?)")


def _degerleri_coz(metin: str) -> list[float]:
    """Metindeki sayıları çözer; kesirli yazımı tek değer sayar.

    ``_sayilar`` "1/2"yi [1.0, 2.0] diye böler; kesir önce çözülmezse yarım
    değeri anlatan cevap ve anahtar hiç eşleşmez.
    """
    metin = str(metin)
    kesirler = [
        float(pay.replace(",", ".")) / float(payda.replace(",", "."))
        for pay, payda in _KESIR.findall(metin)
        if float(payda.replace(",", ".")) != 0
    ]
    if kesirler:
        return kesirler
    return _sayilar(metin)


def _beklenen_degerler(anahtar) -> list[float]:
    """Anahtardaki her kabul edilen değeri ayrı hedef olarak çıkarır.

    Eskiden yalnız ilk sayı hedef alınıyordu; ``kabul_edilen_alternatifler``
    toplanıp atılıyordu.
    """
    return [
        deger
        for metin in [
            *anahtar.dogru_cevaplar,
            *anahtar.kabul_edilen_alternatifler,
        ]
        for deger in _degerleri_coz(metin)
    ]


def _nihai_sayilar(metin: str) -> list[float]:
    """Cevabın NİHAİ sonucu sayılabilecek sayıları döndürür.

    Ölçüldü: cevabın herhangi bir yerindeki sayıyı hedefle karşılaştırmak,
    "Önce 0.5 ile çarptım, sonuç 12 mol buldum" gibi yanlış bir cevaba
    otomatik tam puan veriyordu — inceleme bayrağı bile kalkmadan.
    """
    eslesmeler = list(_SONUC_ISARETI.finditer(metin))
    if eslesmeler:
        kuyruk = _degerleri_coz(metin[eslesmeler[-1].end():])
        if kuyruk:
            return kuyruk
    tum = _degerleri_coz(metin)
    return tum[-1:] if tum else []


def sayisal_puanla(
    cevap: str,
    soru: Soru,
    rubrik_sonucu: PuanSonucu | None = None,
) -> PuanSonucu:
    beklenenler = _beklenen_degerler(soru.anahtar)
    nihai = _nihai_sayilar(cevap)
    tum_bulunan = _degerleri_coz(cevap)
    if not beklenenler:
        sonuc = rubrik_sonucu or PuanSonucu(
            0.0, soru.puan, 0.0,
            ["Sayısal sonuç anahtarda bulunamadı."], incele=True
        )
        sonuc.incele = True
        sonuc.guven = min(sonuc.guven, 0.45)
        return sonuc
    hedef = beklenenler[0]

    def _tolerans(deger: float) -> float:
        return soru.anahtar.sayisal_tolerans or max(1e-9, abs(deger) * 0.005)

    def _uyan(sayilar: list[float]) -> float | None:
        for beklenen in beklenenler:
            tol = _tolerans(beklenen)
            if any(math.isclose(x, beklenen, abs_tol=tol) for x in sayilar):
                return beklenen
        return None

    uyan_nihai = _uyan(nihai)
    esit = uyan_nihai is not None
    if esit:
        hedef = uyan_nihai
    # Doğru değer yalnız ara işlemde geçiyorsa bu, sonucu doğru bulmak
    # değildir; yöntem payı verilir ve öğretmene gösterilir.
    ara_islemde = not esit and _uyan(tum_bulunan) is not None
    birim_var = not soru.anahtar.birimler or any(
        eslesme_bicimi(birim) in eslesme_bicimi(cevap)
        for birim in soru.anahtar.birimler
    )
    if esit:
        sonuc_payi = 0.8 if soru.anahtar.yontem_adimlari else 1.0
        puan = soru.puan * sonuc_payi
        if soru.anahtar.birimler and not birim_var:
            puan *= 0.9
        if rubrik_sonucu is not None:
            puan = max(puan, min(soru.puan, rubrik_sonucu.puan + puan))
        puan = round(min(soru.puan, puan) * 2) / 2
        guven = 0.96 if birim_var else 0.78
        aciklama = (
            f"Sayısal sonuç {hedef:g} tolerans içinde doğru"
            + ("; birim doğru." if birim_var else "; birim eksik/yanlış.")
        )
    else:
        puan = rubrik_sonucu.puan if rubrik_sonucu is not None else 0.0
        guven = min(0.72, rubrik_sonucu.guven) if rubrik_sonucu else 0.72
        if ara_islemde:
            guven = min(guven, 0.5)
            aciklama = (
                f"Doğru değer ({hedef:g}) yalnız ara işlemde geçiyor, nihai "
                f"sonuç farklı; yöntem payı {puan:g} puan — öğretmen incelesin."
            )
        else:
            aciklama = (
                "Nihai sayısal sonuç doğru değil; yalnız doğrulanmış yöntem ve ara "
                f"adımlardan {puan:g} puan verildi."
            )
    return PuanSonucu(
        puan,
        soru.puan,
        guven,
        [*(rubrik_sonucu.detaylar if rubrik_sonucu else []), aciklama],
        incele=(not esit) or (not birim_var),
        risk=1.0 - guven,
        kararlar=[
            {
                "tur": "sayisal_sonuc",
                "beklenen": hedef,
                "beklenen_hepsi": beklenenler,
                "tolerans": _tolerans(hedef),
                "bulunan": tum_bulunan,
                "nihai": nihai,
                "dogru": esit,
                "ara_islemde": ara_islemde,
                "birim_dogru": birim_var,
                "puan": puan,
            }
        ],
        aciklama=aciklama,
        puanlama_guveni=guven,
    )


_IZINLI_AST = (
    ast.Expression,
    ast.BinOp,
    ast.UnaryOp,
    ast.Add,
    ast.Sub,
    ast.Mult,
    ast.Div,
    ast.Pow,
    ast.USub,
    ast.UAdd,
    ast.Name,
    ast.Load,
    ast.Constant,
)


def _guvenli_ifade(metin: str) -> ast.Expression | None:
    ifade = metin.strip().replace("^", "**").replace(",", ".")
    ifade = re.sub(r"(?<=\d)(?=[a-zA-Z])", "*", ifade)
    try:
        agac = ast.parse(ifade, mode="eval")
    except SyntaxError:
        return None
    if any(not isinstance(dugum, _IZINLI_AST) for dugum in ast.walk(agac)):
        return None
    return agac


def ifadeler_esdeger(a: str, b: str) -> bool:
    """Basit cebirsel ifadeleri birkaç güvenli örnek noktada karşılaştır."""
    agac_a, agac_b = _guvenli_ifade(a), _guvenli_ifade(b)
    if agac_a is None or agac_b is None:
        return False
    adlar = {
        n.id
        for agac in (agac_a, agac_b)
        for n in ast.walk(agac)
        if isinstance(n, ast.Name)
    }
    for deger in (-3.0, -1.25, 0.5, 2.0, 4.5):
        ortam = {ad: deger + i * 0.37 for i, ad in enumerate(sorted(adlar))}
        try:
            va = float(eval(compile(agac_a, "<ifade>", "eval"), {"__builtins__": {}}, ortam))
            vb = float(eval(compile(agac_b, "<ifade>", "eval"), {"__builtins__": {}}, ortam))
        except (ArithmeticError, ValueError, TypeError):
            continue
        if not math.isclose(va, vb, rel_tol=1e-7, abs_tol=1e-7):
            return False
    return True


def formul_puanla(
    cevap: str,
    soru: Soru,
    rubrik_sonucu: PuanSonucu | None = None,
) -> PuanSonucu:
    beklenenler = [
        *soru.anahtar.dogru_cevaplar,
        *soru.anahtar.kabul_edilen_alternatifler,
    ]
    adaylar = [
        x.strip()
        for x in re.split(r"[\n;=]", cevap)
        if any(isaret in x for isaret in ("+", "-", "*", "/", "^"))
    ]
    esdeger = any(
        ifadeler_esdeger(aday, beklenen)
        for aday in adaylar
        for beklenen in beklenenler
    )
    if not esdeger and _sayilar(cevap) and any(_sayilar(x) for x in beklenenler):
        return sayisal_puanla(cevap, soru, rubrik_sonucu)
    yontem_puani = rubrik_sonucu.puan if rubrik_sonucu else 0.0
    sonuc_puani = soru.puan * (0.7 if soru.anahtar.yontem_adimlari else 1.0)
    puan = min(soru.puan, yontem_puani + (sonuc_puani if esdeger else 0.0))
    puan = round(puan * 2) / 2
    guven = 0.9 if esdeger else (rubrik_sonucu.guven if rubrik_sonucu else 0.6)
    aciklama = (
        "Cebirsel ifade anahtarla eşdeğer."
        if esdeger
        else "Nihai formül eşdeğer değil; yalnız doğru yöntem/ispat adımları puanlandı."
    )
    return PuanSonucu(
        puan,
        soru.puan,
        guven,
        [*(rubrik_sonucu.detaylar if rubrik_sonucu else []), aciklama],
        incele=not esdeger,
        risk=1.0 - guven,
        kararlar=[
            {
                "tur": "formul",
                "beklenen": beklenenler,
                "adaylar": adaylar,
                "esdeger": esdeger,
                "puan": puan,
            }
        ],
        aciklama=aciklama,
        puanlama_guveni=guven,
    )


def gorsel_cevap_kapisi(sonuc: PuanSonucu, tip: SoruTipi) -> PuanSonucu:
    """Grafik/çizim/tablo için metin rubriğini korur, görsel doğrulamayı zorunlu yapar."""
    sonuc.incele = True
    sonuc.guven = min(sonuc.guven, 0.55)
    sonuc.puanlama_guveni = min(sonuc.puanlama_guveni, 0.55)
    sonuc.risk = max(sonuc.risk, 0.55)
    sonuc.detaylar.append(
        f"{tip.value.replace('_', ' ').title()} cevabında yerleşim, ok ve eksenler "
        "görsel olarak öğretmen tarafından doğrulanmalıdır."
    )
    return sonuc
