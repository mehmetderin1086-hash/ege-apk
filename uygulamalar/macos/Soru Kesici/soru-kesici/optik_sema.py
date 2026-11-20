#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Optik form şablon şeması — yalnız stdlib, Python 3.9 uyumlu.

Kapalı döngünün tek doğruluk kaynağı: optik_form.py (üretici) ve
optik_isci.py (okuyucu) balon konumlarını AYNI fonksiyondan
(baloncuk_merkezleri) türetir; balon merkezleri şablona yazılmaz.
Koordinatlar PDF punto uzayındadır (A4: 595.276 × 841.890, sol-üst köşe
orijin, y aşağı artar) — fitz sayfa uzayıyla birebir.

Sayfa kimliği ArUco işaretçi kimliklerinde yedeklidir: sayfa p (1 tabanlı)
→ ID'ler {4(p−1) … 4(p−1)+3}, köşe = id % 4. QR yalnız sınav kimliği +
sayfa numarası taşır: "SKO1|<sinav_id>|<sayfa_no>".
"""
import json
import math
import os
import tempfile
import uuid
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple

SEMA_SURUMU = "soru-kesici.optik-sablon/v1"
QR_ONEK = "SKO1"

A4_BOY = (595.276, 841.89)

# 29 harfli Türk alfabesi — AD-SOYAD grid satır sembolleri
TURK_ALFABE = ("A", "B", "C", "Ç", "D", "E", "F", "G", "Ğ", "H", "I", "İ",
               "J", "K", "L", "M", "N", "O", "Ö", "P", "R", "S", "Ş", "T",
               "U", "Ü", "V", "Y", "Z")
RAKAMLAR = tuple(str(i) for i in range(10))

ALAN_TIPLERI = ("coktan_secmeli", "dogru_yanlis", "harf_grid",
                "rakam_grid", "kitapcik")

# İşaretçi köşe adları; ArUco id % 4 bu sıraya eşlenir.
KOSELER = ("sol_ust", "sag_ust", "sag_alt", "sol_alt")

# DICT_4X4_50 ilk 48 işaretin 4x4 bit desenleri (satır satır; 1 = beyaz).
# .venv-ml cv2.aruco.generateImageMarker'dan bir defalık çıkarıldı; üretici
# bunları vektör olarak basar, test_optik_sema_v1 bütünlüğü kilitler.
ARUCO_BITLER = {
    0: (1, 0, 1, 1, 0, 1, 0, 1, 0, 0, 1, 1, 0, 0, 1, 0),
    1: (0, 0, 0, 0, 1, 1, 1, 1, 1, 0, 0, 1, 1, 0, 1, 0),
    2: (0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 0, 1, 1, 0, 1),
    3: (1, 0, 0, 1, 1, 0, 0, 1, 0, 1, 0, 0, 0, 1, 1, 0),
    4: (0, 1, 0, 1, 0, 1, 0, 0, 1, 0, 0, 1, 1, 1, 1, 0),
    5: (0, 1, 1, 1, 1, 0, 0, 1, 1, 1, 0, 0, 1, 1, 0, 1),
    6: (1, 0, 0, 1, 1, 1, 1, 0, 0, 0, 1, 0, 1, 1, 1, 0),
    7: (1, 1, 0, 0, 0, 1, 0, 0, 1, 1, 1, 1, 0, 0, 1, 0),
    8: (1, 1, 1, 1, 1, 1, 1, 0, 1, 1, 0, 1, 1, 0, 1, 0),
    9: (1, 1, 0, 0, 1, 1, 1, 1, 0, 1, 0, 1, 0, 1, 1, 0),
    10: (1, 1, 1, 1, 1, 0, 0, 1, 1, 0, 0, 1, 0, 0, 0, 1),
    11: (0, 0, 0, 1, 0, 0, 0, 1, 1, 0, 1, 0, 0, 1, 1, 1),
    12: (0, 0, 0, 0, 1, 1, 1, 0, 1, 0, 1, 1, 0, 1, 1, 1),
    13: (0, 0, 1, 0, 1, 0, 1, 0, 0, 0, 0, 0, 1, 1, 1, 1),
    14: (0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 1, 1, 0, 0, 0, 1),
    15: (0, 0, 1, 0, 0, 1, 1, 0, 0, 0, 1, 1, 1, 1, 1, 0),
    16: (0, 1, 0, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 0, 1),
    17: (0, 1, 1, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0),
    18: (0, 1, 1, 0, 1, 1, 0, 0, 0, 1, 0, 1, 1, 1, 1, 0),
    19: (0, 1, 1, 1, 0, 1, 1, 0, 1, 0, 1, 0, 1, 1, 1, 1),
    20: (1, 0, 0, 0, 0, 1, 1, 0, 1, 0, 0, 0, 1, 0, 1, 1),
    21: (1, 0, 1, 1, 0, 0, 0, 0, 0, 0, 1, 0, 1, 0, 1, 1),
    22: (1, 1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 1, 0, 1, 0, 1),
    23: (1, 1, 0, 1, 1, 1, 0, 1, 1, 0, 0, 0, 0, 0, 1, 0),
    24: (1, 1, 1, 1, 1, 1, 1, 0, 0, 1, 0, 0, 0, 1, 1, 1),
    25: (1, 0, 0, 1, 0, 1, 0, 0, 0, 1, 1, 1, 0, 0, 0, 1),
    26: (1, 0, 1, 0, 1, 1, 0, 0, 1, 1, 1, 0, 0, 1, 0, 0),
    27: (1, 0, 1, 0, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 0),
    28: (0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 0, 1, 1),
    29: (0, 0, 1, 1, 0, 1, 0, 0, 0, 1, 1, 0, 1, 1, 1, 1),
    30: (0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 1, 0, 1),
    31: (0, 1, 0, 1, 0, 1, 1, 1, 1, 0, 1, 1, 0, 0, 1, 0),
    32: (1, 0, 0, 1, 1, 1, 1, 0, 1, 1, 0, 0, 1, 1, 1, 1),
    33: (1, 1, 1, 1, 0, 0, 0, 0, 1, 1, 0, 0, 1, 0, 1, 1),
    34: (0, 0, 0, 0, 1, 0, 0, 0, 1, 0, 1, 0, 1, 1, 1, 0),
    35: (0, 0, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 1, 0, 0, 1),
    36: (0, 0, 0, 1, 1, 0, 0, 0, 0, 1, 1, 1, 0, 1, 0, 1),
    37: (0, 0, 0, 0, 0, 1, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1),
    38: (0, 0, 0, 0, 1, 1, 0, 1, 1, 1, 1, 1, 0, 1, 1, 0),
    39: (0, 0, 0, 1, 1, 1, 0, 0, 0, 1, 0, 1, 1, 0, 1, 0),
    40: (0, 0, 0, 1, 0, 1, 1, 1, 0, 0, 0, 1, 1, 0, 0, 0),
    41: (0, 0, 1, 0, 1, 0, 1, 0, 0, 0, 1, 0, 1, 0, 0, 0),
    42: (0, 0, 1, 1, 0, 0, 1, 0, 1, 0, 0, 0, 1, 1, 0, 0),
    43: (0, 0, 1, 1, 1, 0, 0, 0, 1, 0, 1, 1, 0, 0, 1, 0),
    44: (0, 0, 1, 0, 0, 1, 0, 0, 1, 1, 1, 0, 1, 0, 0, 0),
    45: (0, 0, 1, 0, 1, 1, 1, 0, 1, 1, 1, 0, 1, 0, 1, 1),
    46: (0, 0, 1, 0, 1, 1, 0, 1, 0, 0, 1, 1, 1, 1, 1, 1),
    47: (0, 1, 0, 0, 1, 0, 1, 1, 0, 1, 1, 0, 0, 1, 0, 0),
}
ARUCO_SOZLUK = "DICT_4X4_50"
AZAMI_SAYFA = len(ARUCO_BITLER) // 4      # 12 sayfa


def sinav_id_uret():
    return uuid.uuid4().hex[:8]


def sayfa_isaretci_idleri(sayfa_no):
    """1 tabanlı sayfa → köşe sırasına göre 4 ArUco kimliği."""
    if not 1 <= sayfa_no <= AZAMI_SAYFA:
        raise ValueError(f"sayfa_no 1..{AZAMI_SAYFA} olmalı: {sayfa_no}")
    taban = 4 * (sayfa_no - 1)
    return [taban + k for k in range(4)]


def isaretci_sayfasi(aruco_id):
    """ArUco kimliği → (sayfa_no, köşe adı) | None."""
    if not isinstance(aruco_id, int) or aruco_id < 0 \
            or aruco_id >= 4 * AZAMI_SAYFA:
        return None
    return aruco_id // 4 + 1, KOSELER[aruco_id % 4]


def qr_icerik(sinav_id, sayfa_no):
    return f"{QR_ONEK}|{sinav_id}|{sayfa_no}"


def qr_coz(metin):
    """QR içeriği → {"sinav_id", "sayfa_no"} | None."""
    try:
        parcalar = str(metin).strip().split("|")
        if len(parcalar) != 3 or parcalar[0] != QR_ONEK:
            return None
        sayfa = int(parcalar[2])
        if not parcalar[1] or sayfa < 1:
            return None
        return {"sinav_id": parcalar[1], "sayfa_no": sayfa}
    except (ValueError, AttributeError):
        return None


@dataclass
class Hucre:
    """Balon grid geometrisi: çap ve adımlar punto."""
    cap: float
    ilk_merkez: Tuple[float, float]
    x_adim: float
    y_adim: float


@dataclass
class Alan:
    """Tek düzgün balon grid'i.

    Satır/sütun semantiği tipe göre:
      coktan_secmeli/dogru_yanlis: satır = soru (soru_baslangic + r),
        sütun = secenek (semboller[c]).
      harf_grid/rakam_grid: satır = sembol (semboller[r]),
        sütun = karakter konumu.
      kitapcik: tek satır, sütun = kitapçık harfi (semboller[c]).
    """
    tip: str
    ad: str
    kutu: Tuple[float, float, float, float]
    satir: int
    sutun: int
    semboller: Tuple[str, ...]
    hucre: Hucre
    etiket: str = ""
    ders: str = ""
    soru_baslangic: int = 0
    soru_sayisi: int = 0
    el_yazisi_kutusu: Optional[Tuple[float, float, float, float]] = None


@dataclass
class Isaretci:
    id: int
    kose: str
    merkez: Tuple[float, float]
    boy: float


@dataclass
class SablonSayfa:
    sayfa_no: int
    isaretciler: List[Isaretci] = field(default_factory=list)
    kose_kareleri: List[Dict] = field(default_factory=list)
    qr: Optional[Dict] = None            # {"kutu": [...], "icerik": "..."}
    alanlar: List[Alan] = field(default_factory=list)


@dataclass
class Sablon:
    sinav_id: str
    ad: str
    olusturma: str = ""
    sayfa_boyu: Tuple[float, float] = A4_BOY
    kitapcik_turleri: Tuple[str, ...] = ("A",)
    puan_kurali: Dict = field(default_factory=dict)   # {"yanlis_boler": 4|3|0}
    sayfalar: List[SablonSayfa] = field(default_factory=list)

    def alan_bul(self, ad):
        for sayfa in self.sayfalar:
            for alan in sayfa.alanlar:
                if alan.ad == ad:
                    return alan
        return None

    def cevap_alanlari(self):
        """Soru cevap alanları sayfa + soru_baslangic sırasıyla."""
        alanlar = []
        for sayfa in self.sayfalar:
            for alan in sayfa.alanlar:
                if alan.tip in ("coktan_secmeli", "dogru_yanlis"):
                    alanlar.append((sayfa.sayfa_no, alan))
        alanlar.sort(key=lambda c: (c[0], c[1].soru_baslangic))
        return alanlar

    def soru_sayisi(self):
        return sum(a.soru_sayisi for _, a in self.cevap_alanlari())

    def dersler(self):
        """Görülme sırasıyla benzersiz ders adları."""
        sira = []
        for _, alan in self.cevap_alanlari():
            if alan.ders and alan.ders not in sira:
                sira.append(alan.ders)
        return sira


def baloncuk_merkezleri(alan):
    """Alan grid'inin balon merkezleri: [(satir, sutun, x, y)].

    Üretici (optik_form) ve okuyucu (optik_isci) AYNI listeyi kullanır —
    kapalı döngünün tek doğruluk kaynağı budur.
    """
    x0, y0 = alan.hucre.ilk_merkez
    return [(r, c, x0 + c * alan.hucre.x_adim, y0 + r * alan.hucre.y_adim)
            for r in range(alan.satir) for c in range(alan.sutun)]


def hucre_sembol(alan, r, c):
    """Grid hücresinin temsil ettiği sembol (tip semantiğine göre)."""
    if alan.tip in ("coktan_secmeli", "dogru_yanlis", "kitapcik"):
        return alan.semboller[c]
    return alan.semboller[r]


# ---------------------------------------------------------------- serileştirme

def _hucre_dict(h):
    return {"cap": h.cap, "ilk_merkez": list(h.ilk_merkez),
            "x_adim": h.x_adim, "y_adim": h.y_adim}


def _alan_dict(a):
    d = {"tip": a.tip, "ad": a.ad, "kutu": list(a.kutu), "satir": a.satir,
         "sutun": a.sutun, "semboller": list(a.semboller),
         "hucre": _hucre_dict(a.hucre)}
    if a.etiket:
        d["etiket"] = a.etiket
    if a.ders:
        d["ders"] = a.ders
    if a.soru_sayisi:
        d["soru_baslangic"] = a.soru_baslangic
        d["soru_sayisi"] = a.soru_sayisi
    if a.el_yazisi_kutusu:
        d["el_yazisi_kutusu"] = list(a.el_yazisi_kutusu)
    return d


def sablon_dict(s):
    return {
        "surum": SEMA_SURUMU,
        "sinav_id": s.sinav_id,
        "ad": s.ad,
        "olusturma": s.olusturma,
        "sayfa_boyu": list(s.sayfa_boyu),
        "kitapcik_turleri": list(s.kitapcik_turleri),
        "puan_kurali": dict(s.puan_kurali),
        "sayfalar": [{
            "sayfa_no": sf.sayfa_no,
            "isaretciler": [{"id": i.id, "kose": i.kose,
                             "merkez": list(i.merkez), "boy": i.boy}
                            for i in sf.isaretciler],
            "kose_kareleri": list(sf.kose_kareleri),
            "qr": sf.qr,
            "alanlar": [_alan_dict(a) for a in sf.alanlar],
        } for sf in s.sayfalar],
    }


def _hucre_kur(d):
    return Hucre(cap=float(d["cap"]),
                 ilk_merkez=(float(d["ilk_merkez"][0]),
                             float(d["ilk_merkez"][1])),
                 x_adim=float(d["x_adim"]), y_adim=float(d["y_adim"]))


def _alan_kur(d):
    return Alan(tip=d["tip"], ad=d["ad"],
                kutu=tuple(float(v) for v in d["kutu"]),
                satir=int(d["satir"]), sutun=int(d["sutun"]),
                semboller=tuple(str(v) for v in d["semboller"]),
                hucre=_hucre_kur(d["hucre"]),
                etiket=d.get("etiket", ""),
                ders=d.get("ders", ""),
                soru_baslangic=int(d.get("soru_baslangic", 0) or 0),
                soru_sayisi=int(d.get("soru_sayisi", 0) or 0),
                el_yazisi_kutusu=(tuple(float(v)
                                        for v in d["el_yazisi_kutusu"])
                                  if d.get("el_yazisi_kutusu") else None))


def sablon_kur(d):
    """dict → Sablon; sürüm uyumsuzluğunda ValueError."""
    if d.get("surum") != SEMA_SURUMU:
        raise ValueError(f"şablon sürümü uyumsuz: {d.get('surum')!r}")
    return Sablon(
        sinav_id=str(d["sinav_id"]),
        ad=str(d.get("ad", "")),
        olusturma=str(d.get("olusturma", "")),
        sayfa_boyu=tuple(float(v) for v in d.get("sayfa_boyu", A4_BOY)),
        kitapcik_turleri=tuple(str(v) for v in
                               d.get("kitapcik_turleri", ("A",))),
        puan_kurali=dict(d.get("puan_kurali") or {}),
        sayfalar=[SablonSayfa(
            sayfa_no=int(sf["sayfa_no"]),
            isaretciler=[Isaretci(id=int(i["id"]), kose=str(i["kose"]),
                                  merkez=(float(i["merkez"][0]),
                                          float(i["merkez"][1])),
                                  boy=float(i["boy"]))
                         for i in sf.get("isaretciler", [])],
            kose_kareleri=list(sf.get("kose_kareleri", [])),
            qr=sf.get("qr"),
            alanlar=[_alan_kur(a) for a in sf.get("alanlar", [])],
        ) for sf in d.get("sayfalar", [])],
    )


def sablon_yaz(s, yol):
    """Şablonu atomik yazar (tmp + os.replace)."""
    veri = sablon_dict(s)
    dizin = os.path.dirname(os.path.abspath(yol)) or "."
    fd, gecici = tempfile.mkstemp(dir=dizin, suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(veri, f, ensure_ascii=False, indent=1)
        os.replace(gecici, yol)
    except BaseException:
        try:
            os.unlink(gecici)
        except OSError:
            pass
        raise


def sablon_oku(yol):
    with open(yol, encoding="utf-8") as f:
        return sablon_kur(json.load(f))


# ------------------------------------------------------------------ doğrulama

def _kutu_gecerli(kutu, sayfa_boyu):
    x0, y0, x1, y1 = kutu
    return (all(math.isfinite(v) for v in kutu) and x0 < x1 and y0 < y1
            and x0 >= 0 and y0 >= 0
            and x1 <= sayfa_boyu[0] + 0.5 and y1 <= sayfa_boyu[1] + 0.5)


def dogrula(s):
    """Şablon tutarlılık denetimi → hata mesajları listesi (boş = geçerli)."""
    hatalar = []
    if not s.sinav_id:
        hatalar.append("sinav_id boş")
    if not s.sayfalar:
        hatalar.append("şablonda sayfa yok")
    if not s.kitapcik_turleri:
        hatalar.append("kitapcik_turleri boş")
    gorulen_soru = set()
    gorulen_ad = set()
    for sf in s.sayfalar:
        on_ek = f"sayfa {sf.sayfa_no}: "
        beklenen = set(sayfa_isaretci_idleri(sf.sayfa_no)) \
            if 1 <= sf.sayfa_no <= AZAMI_SAYFA else set()
        bulunan = {i.id for i in sf.isaretciler}
        if bulunan != beklenen:
            hatalar.append(on_ek + f"işaretçi kimlikleri {sorted(bulunan)} "
                                   f"≠ beklenen {sorted(beklenen)}")
        for i in sf.isaretciler:
            beklenen_kose = KOSELER[i.id % 4]
            if i.kose != beklenen_kose:
                hatalar.append(on_ek + f"işaretçi {i.id} köşesi {i.kose!r} "
                                       f"≠ {beklenen_kose!r}")
        if sf.qr:
            icerik = qr_coz(sf.qr.get("icerik", ""))
            if not icerik or icerik["sinav_id"] != s.sinav_id \
                    or icerik["sayfa_no"] != sf.sayfa_no:
                hatalar.append(on_ek + "qr içeriği şablonla uyumsuz")
        for a in sf.alanlar:
            aon = on_ek + f"alan {a.ad!r}: "
            if a.tip not in ALAN_TIPLERI:
                hatalar.append(aon + f"bilinmeyen tip {a.tip!r}")
                continue
            if a.ad in gorulen_ad:
                hatalar.append(aon + "ad tekrarı")
            gorulen_ad.add(a.ad)
            if a.satir < 1 or a.sutun < 1:
                hatalar.append(aon + "satır/sütun sayısı geçersiz")
                continue
            if not _kutu_gecerli(a.kutu, s.sayfa_boyu):
                hatalar.append(aon + "kutu sayfa dışında/geçersiz")
            if a.tip in ("coktan_secmeli", "dogru_yanlis", "kitapcik"):
                if len(a.semboller) != a.sutun:
                    hatalar.append(aon + "sembol sayısı ≠ sütun sayısı")
            elif len(a.semboller) != a.satir:
                hatalar.append(aon + "sembol sayısı ≠ satır sayısı")
            if a.tip in ("coktan_secmeli", "dogru_yanlis"):
                if a.soru_sayisi != a.satir:
                    hatalar.append(aon + "soru_sayisi ≠ satır sayısı")
                if a.soru_baslangic < 1:
                    hatalar.append(aon + "soru_baslangic < 1")
                sorular = range(a.soru_baslangic,
                                a.soru_baslangic + a.soru_sayisi)
                anahtar = a.ders or ""
                for no in sorular:
                    if (anahtar, no) in gorulen_soru:
                        hatalar.append(aon + f"soru {no} tekrarı ({anahtar})")
                    gorulen_soru.add((anahtar, no))
            if a.hucre.cap <= 0:
                hatalar.append(aon + "balon çapı geçersiz")
            # balonlar kutu içinde mi? (yarıçap payıyla)
            yari = a.hucre.cap / 2 + 0.5
            for r, c, x, y in baloncuk_merkezleri(a):
                if not (a.kutu[0] - yari <= x <= a.kutu[2] + yari
                        and a.kutu[1] - yari <= y <= a.kutu[3] + yari):
                    hatalar.append(aon + f"balon ({r},{c}) kutu dışında")
                    break
    return hatalar
