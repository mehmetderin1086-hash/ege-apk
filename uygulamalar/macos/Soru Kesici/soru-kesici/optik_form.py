#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Optik cevap kâğıdı üretici — fitz (PyMuPDF), ana .venv'de çalışır.

Basılabilir PDF ile makine tarafından okunacak şablon JSON'u AYNI yerleşim
döngüsünde üretilir (kapalı döngü): balon merkezleri optik_sema.
baloncuk_merkezleri'nden türetilir, elle ölçüm yoktur. ArUco işaretçileri
vektör olarak bit-bit basılır (optik_sema.ARUCO_BITLER).

QR: .venv-ml kuruluysa optik_isci.py --qr-uret tek atımıyla PNG üretilir;
değilse QR kutusuna okunaklı form kodu metni basılır (şablon geometrisi
değişmez, kimlik ArUco'da zaten yedeklidir).
"""
import datetime
import os
import subprocess
import tempfile

import fitz

import isci_ortam
import optik_sema as osm
import yazi_tipi

PROJE = os.path.dirname(os.path.abspath(__file__))
ISCI_PY = isci_ortam.isci_python()
ISCI_BETIK = os.path.join(PROJE, "optik_isci.py")

SAYFA_GEN, SAYFA_YUK = osm.A4_BOY
KENAR = 20.0
ISARETCI_BOY = 24.0
ISARETCI_IC = 26.0                 # işaretçi merkezinin kenara uzaklığı
KARE_BOY = 8.0                     # köşe kareleri (kontur yedeği görsel çapası)

# Balon grid metrikleri (punto)
CAP = 9.4                          # cevap balon çapı
XAD, YAD = 14.0, 12.4              # cevap grid adımları
ID_CAP, ID_XAD = 8.6, 14.0         # kimlik grid'leri
AD_YAD = 11.2                      # ad-soyad grid satır adımı (29 satır sığsın)
NO_YAD = 12.0

SOL_BLOK_GEN = 172.0               # sayfa 1 kimlik bloğu genişliği
CVP_UST = 104.0                    # cevap alanı üst y (sayfa 1)
CVP_UST_DEVAM = 60.0               # sayfa 2+ üst y
CVP_ALT = 800.0
BOLUM_BASLIK = 16.0                # ders başlığı yüksekliği (satır cinsinden pay)
ETIKET_GEN = 20.0                  # soru numarası şeridi

TALIMAT = ("Kurşun kalemle kodlayınız; balonu taşırmadan doldurunuz. "
           "İptal için işareti tamamen siliniz.")

# Hazır form tipleri — parametrik tasarımcının ön ayarları
ON_AYARLAR = {
    "yazili-20": {"ad": "Yazılı Sınav (20 Soru)", "yanlis_boler": 0,
                  "dersler": [{"ad": "", "soru": 20, "secenek": 4}]},
    "yazili-50": {"ad": "Yazılı Sınav (50 Soru)", "yanlis_boler": 0,
                  "dersler": [{"ad": "", "soru": 50, "secenek": 4}]},
    "yazili-100": {"ad": "Yazılı Sınav (100 Soru)", "yanlis_boler": 0,
                   "dersler": [{"ad": "", "soru": 100, "secenek": 5}]},
    "lgs-sozel": {"ad": "LGS Deneme — Sözel Bölüm", "yanlis_boler": 3,
                  "dersler": [{"ad": "Türkçe", "soru": 20, "secenek": 4},
                              {"ad": "T.C. İnkılap Tarihi", "soru": 10,
                               "secenek": 4},
                              {"ad": "Din Kültürü", "soru": 10, "secenek": 4},
                              {"ad": "İngilizce", "soru": 10, "secenek": 4}]},
    "lgs-sayisal": {"ad": "LGS Deneme — Sayısal Bölüm", "yanlis_boler": 3,
                    "dersler": [{"ad": "Matematik", "soru": 20, "secenek": 4},
                                {"ad": "Fen Bilimleri", "soru": 20,
                                 "secenek": 4}]},
    "tyt": {"ad": "TYT Deneme", "yanlis_boler": 4,
            "dersler": [{"ad": "Türkçe", "soru": 40, "secenek": 5},
                        {"ad": "Sosyal Bilimler", "soru": 20, "secenek": 5},
                        {"ad": "Temel Matematik", "soru": 40, "secenek": 5},
                        {"ad": "Fen Bilimleri", "soru": 20, "secenek": 5}]},
    "ayt": {"ad": "AYT Deneme", "yanlis_boler": 4,
            "dersler": [{"ad": "Türk Dili ve Edebiyatı — Sosyal Bilimler-1",
                         "soru": 40, "secenek": 5},
                        {"ad": "Sosyal Bilimler-2", "soru": 40, "secenek": 5},
                        {"ad": "Matematik", "soru": 40, "secenek": 5},
                        {"ad": "Fen Bilimleri", "soru": 40, "secenek": 5}]},
}

VARSAYILAN = {"ad": "Optik Form", "kurum": "", "ogrenci_no_hane": 5,
              "tc": False, "kitapcik": 2, "ad_soyad": True,
              "yanlis_boler": 0, "dersler": []}


def tanim_hazirla(tanim=None, on_ayar=None):
    """Ön ayar + kullanıcı geçersiz kılmaları → tam form tanımı."""
    sonuc = dict(VARSAYILAN)
    if on_ayar:
        if on_ayar not in ON_AYARLAR:
            raise ValueError(f"bilinmeyen ön ayar: {on_ayar!r} "
                             f"(geçerli: {', '.join(sorted(ON_AYARLAR))})")
        sonuc.update({k: (list(v) if isinstance(v, list) else v)
                      for k, v in ON_AYARLAR[on_ayar].items()})
    for k, v in (tanim or {}).items():
        if v is not None:
            sonuc[k] = v
    return sonuc


def tanim_dogrula(tanim):
    hatalar = []
    dersler = tanim.get("dersler") or []
    if not dersler:
        hatalar.append("en az bir ders/bölüm gerekli")
    adlar = set()
    for d in dersler:
        ad = str(d.get("ad", ""))
        if ad in adlar:
            hatalar.append(f"ders adı tekrarı: {ad!r}")
        adlar.add(ad)
        try:
            soru, secenek = int(d.get("soru", 0)), int(d.get("secenek", 0))
        except (TypeError, ValueError):
            soru = secenek = 0
        if soru < 1 or soru > 200:
            hatalar.append(f"{ad or 'bölüm'}: soru sayısı 1-200 olmalı")
        if secenek < 2 or secenek > 7:
            hatalar.append(f"{ad or 'bölüm'}: seçenek sayısı 2-7 olmalı")
    try:
        kitapcik = int(tanim.get("kitapcik", 1) or 1)
    except (TypeError, ValueError):
        kitapcik = 0
    if not 1 <= kitapcik <= 4:
        hatalar.append("kitapçık sayısı 1-4 olmalı")
    try:
        hane = int(tanim.get("ogrenci_no_hane", 0) or 0)
    except (TypeError, ValueError):
        hane = -1
    if not 0 <= hane <= 10:
        hatalar.append("öğrenci no hanesi 0-10 olmalı")
    if tanim.get("yanlis_boler") not in (0, 3, 4, None):
        hatalar.append("yanlis_boler 0, 3 veya 4 olmalı")
    return hatalar


# ------------------------------------------------------------------- çizimler

def _aruco_ciz(page, isaretci):
    """ArUco işaretçisini vektör olarak basar (1 hücre siyah bordür + 4x4)."""
    cx, cy = isaretci.merkez
    boy = isaretci.boy
    hucre = boy / 6.0
    x0, y0 = cx - boy / 2, cy - boy / 2
    page.draw_rect(fitz.Rect(x0, y0, x0 + boy, y0 + boy),
                   color=None, fill=(0, 0, 0))
    bitler = osm.ARUCO_BITLER[isaretci.id]
    for r in range(4):
        for c in range(4):
            if bitler[r * 4 + c]:
                bx = x0 + (c + 1) * hucre
                by = y0 + (r + 1) * hucre
                page.draw_rect(fitz.Rect(bx, by, bx + hucre, by + hucre),
                               color=None, fill=(1, 1, 1))


def _balon_ciz(page, yzi, x, y, cap, harf):
    page.draw_circle(fitz.Point(x, y), cap / 2, color=(0, 0, 0), width=0.7)
    if harf:
        fs = cap * 0.62
        rect = fitz.Rect(x - cap, y - fs * 0.72, x + cap, y + fs * 0.9)
        yzi.kutu(page, rect, harf, fontsize=fs, color=(0.45, 0.45, 0.45),
                 align=fitz.TEXT_ALIGN_CENTER)


def _grid_ciz(page, yzi, alan):
    """Alan grid'inin balonlarını + sembol harflerini basar."""
    for r, c, x, y in osm.baloncuk_merkezleri(alan):
        _balon_ciz(page, yzi, x, y, alan.hucre.cap,
                   osm.hucre_sembol(alan, r, c))


def _el_yazisi_kutulari(page, kutu, adet):
    x0, y0, x1, y1 = kutu
    adim = (x1 - x0) / adet
    for i in range(adet):
        page.draw_rect(fitz.Rect(x0 + i * adim, y0, x0 + (i + 1) * adim, y1),
                       color=(0.55, 0.55, 0.55), width=0.5)


def _qr_hazirla(icerik):
    """QR PNG bytes | None (işçi/venv yoksa None → metin yedeği)."""
    if not (os.path.isfile(ISCI_PY) and os.path.isfile(ISCI_BETIK)):
        return None
    hedef = None
    try:
        fd, hedef = tempfile.mkstemp(suffix=".png")
        os.close(fd)
        s = subprocess.run([ISCI_PY, ISCI_BETIK, "--qr-uret", icerik, hedef],
                           capture_output=True, timeout=30)
        if s.returncode == 0 and os.path.getsize(hedef) > 0:
            with open(hedef, "rb") as f:
                return f.read()
        return None
    except Exception:  # noqa: BLE001 — QR süs değil ama zorunlu da değil
        return None
    finally:
        if hedef:
            try:
                os.unlink(hedef)
            except OSError:
                pass


# ------------------------------------------------------------------ yerleşim

class _SayfaKurucu:
    """Tek A4 sayfası: işaretçiler + QR basar, şablon kaydını tutar."""

    def __init__(self, doc, yzi, sayfa_no, sinav_id):
        self.page = doc.new_page(width=SAYFA_GEN, height=SAYFA_YUK)
        self.yzi = yzi
        self.kayit = osm.SablonSayfa(sayfa_no=sayfa_no)
        merkezler = {
            "sol_ust": (ISARETCI_IC, ISARETCI_IC),
            "sag_ust": (SAYFA_GEN - ISARETCI_IC, ISARETCI_IC),
            "sag_alt": (SAYFA_GEN - ISARETCI_IC, SAYFA_YUK - ISARETCI_IC),
            "sol_alt": (ISARETCI_IC, SAYFA_YUK - ISARETCI_IC),
        }
        for aid in osm.sayfa_isaretci_idleri(sayfa_no):
            kose = osm.KOSELER[aid % 4]
            im = osm.Isaretci(id=aid, kose=kose, merkez=merkezler[kose],
                              boy=ISARETCI_BOY)
            _aruco_ciz(self.page, im)
            self.kayit.isaretciler.append(im)
        # köşe kareleri: işaretçinin sayfa içine bakan komşusu (kontur/görsel çapa)
        for kose, (cx, cy) in merkezler.items():
            ix = cx + (52 if "sol" in kose else -52)
            kare = {"merkez": [ix, cy], "boy": KARE_BOY}
            self.kayit.kose_kareleri.append(kare)
            page_rect = fitz.Rect(ix - KARE_BOY / 2, cy - KARE_BOY / 2,
                                  ix + KARE_BOY / 2, cy + KARE_BOY / 2)
            self.page.draw_rect(page_rect, color=None, fill=(0, 0, 0))
        # QR sağ üstte
        icerik = osm.qr_icerik(sinav_id, sayfa_no)
        qr_kutu = (SAYFA_GEN - 100.0, 40.0, SAYFA_GEN - 45.0, 95.0)
        self.kayit.qr = {"kutu": list(qr_kutu), "icerik": icerik}
        png = _qr_hazirla(icerik)
        if png:
            self.page.insert_image(fitz.Rect(*qr_kutu), stream=png)
        else:
            self.yzi.kutu(self.page, fitz.Rect(qr_kutu[0] - 30, qr_kutu[1],
                                               qr_kutu[2], qr_kutu[3]),
                          f"Form\n{icerik}", fontsize=6.5,
                          color=(0.3, 0.3, 0.3),
                          align=fitz.TEXT_ALIGN_CENTER)

    def alan_ekle(self, alan):
        self.kayit.alanlar.append(alan)
        _grid_ciz(self.page, self.yzi, alan)
        if alan.el_yazisi_kutusu:
            _el_yazisi_kutulari(self.page, alan.el_yazisi_kutusu, alan.sutun)


def _kimlik_blogu(kurucu, tanim):
    """Sayfa 1 sol sütunu: AD-SOYAD, ÖĞRENCİ NO, TC. Kitapçık üst şeritte."""
    yzi = kurucu.yzi
    page = kurucu.page
    x0 = KENAR + 6
    y = CVP_UST

    def etiket(metin, ey):
        yzi.nokta(page, (x0, ey), metin, fontsize=7.5, color=(0, 0, 0))

    if tanim.get("ad_soyad", True):
        sutun = 10
        etiket("ADI  SOYADI", y + 8)
        el_kutu = (x0, y + 12, x0 + sutun * ID_XAD, y + 24)
        ilk = (x0 + ID_XAD / 2, y + 34)
        alan = osm.Alan(
            tip="harf_grid", ad="ad_soyad", etiket="ADI SOYADI",
            kutu=(x0 - 2, y + 28, x0 + sutun * ID_XAD + 2,
                  y + 34 + 28 * AD_YAD + ID_CAP),
            satir=29, sutun=sutun, semboller=osm.TURK_ALFABE,
            hucre=osm.Hucre(ID_CAP, ilk, ID_XAD, AD_YAD),
            el_yazisi_kutusu=el_kutu)
        kurucu.alan_ekle(alan)
        y = alan.kutu[3] + 10

    hane = int(tanim.get("ogrenci_no_hane", 5) or 0)
    if hane:
        etiket("ÖĞRENCİ NO", y + 8)
        el_kutu = (x0, y + 12, x0 + hane * ID_XAD, y + 24)
        ilk = (x0 + ID_XAD / 2, y + 34)
        alan = osm.Alan(
            tip="rakam_grid", ad="ogrenci_no", etiket="ÖĞRENCİ NO",
            kutu=(x0 - 2, y + 28, x0 + hane * ID_XAD + 2,
                  y + 34 + 9 * NO_YAD + ID_CAP),
            satir=10, sutun=hane, semboller=osm.RAKAMLAR,
            hucre=osm.Hucre(ID_CAP, ilk, ID_XAD, NO_YAD),
            el_yazisi_kutusu=el_kutu)
        kurucu.alan_ekle(alan)
        y = alan.kutu[3] + 10

    if tanim.get("tc"):
        etiket("T.C. KİMLİK NO", y + 8)
        ilk = (x0 + ID_XAD / 2, y + 20)
        alan = osm.Alan(
            tip="rakam_grid", ad="tc_kimlik", etiket="T.C. KİMLİK NO",
            kutu=(x0 - 2, y + 14, x0 + 11 * ID_XAD + 2,
                  y + 20 + 9 * NO_YAD + ID_CAP),
            satir=10, sutun=11, semboller=osm.RAKAMLAR,
            hucre=osm.Hucre(ID_CAP, ilk, ID_XAD, NO_YAD))
        kurucu.alan_ekle(alan)


def _kitapcik_alani(kurucu, kitapcik_turleri):
    """Üst şeritte yatay KİTAPÇIK TÜRÜ alanı."""
    x = 300.0
    y = 76.0
    kurucu.yzi.nokta(kurucu.page, (x, y + 3), "KİTAPÇIK TÜRÜ",
                     fontsize=7.5, color=(0, 0, 0))
    ilk = (x + 66.0, y)
    alan = osm.Alan(
        tip="kitapcik", ad="kitapcik", etiket="KİTAPÇIK TÜRÜ",
        kutu=(x + 58, y - 8, x + 66 + len(kitapcik_turleri) * 18.0, y + 8),
        satir=1, sutun=len(kitapcik_turleri),
        semboller=tuple(kitapcik_turleri),
        hucre=osm.Hucre(CAP, ilk, 18.0, YAD))
    kurucu.alan_ekle(alan)


def _baslik(kurucu, tanim):
    yzi, page = kurucu.yzi, kurucu.page
    yzi.kutu(page, fitz.Rect(60, 36, SAYFA_GEN - 110, 56),
             tanim.get("ad") or "Optik Form", fontsize=12.5,
             align=fitz.TEXT_ALIGN_CENTER)
    if tanim.get("kurum"):
        yzi.kutu(page, fitz.Rect(60, 56, SAYFA_GEN - 110, 70),
                 tanim["kurum"], fontsize=8.5,
                 align=fitz.TEXT_ALIGN_CENTER, color=(0.3, 0.3, 0.3))
    yzi.nokta(page, (KENAR + 4, 96), TALIMAT,
              fontsize=6.5, color=(0.35, 0.35, 0.35))


class _CevapAkisi:
    """Cevap bölümlerini sütunlara/sayfalara akıtır; her kesintisiz parça
    tek Alan (grid) olur."""

    def __init__(self, doc, yzi, sinav_id, tanim, kitapcik_turleri):
        self.doc, self.yzi = doc, yzi
        self.sinav_id, self.tanim = sinav_id, tanim
        self.kitapcik_turleri = kitapcik_turleri
        self.sayfalar = []
        self.secenek_max = max(int(d["secenek"])
                               for d in tanim["dersler"])
        self.sutun_gen = ETIKET_GEN + self.secenek_max * XAD + 8
        self._yeni_sayfa()

    def _yeni_sayfa(self):
        no = len(self.sayfalar) + 1
        if no > osm.AZAMI_SAYFA:
            raise ValueError(f"form {osm.AZAMI_SAYFA} sayfayı aşıyor")
        kurucu = _SayfaKurucu(self.doc, self.yzi, no, self.sinav_id)
        self.sayfalar.append(kurucu)
        if no == 1:
            _baslik(kurucu, self.tanim)
            _kitapcik_alani(kurucu, self.kitapcik_turleri)
            _kimlik_blogu(kurucu, self.tanim)
            self.x_sol = KENAR + SOL_BLOK_GEN + 8
            self.ust = CVP_UST
        else:
            self.x_sol = KENAR + 4
            self.ust = CVP_UST_DEVAM
        self.x_sag = SAYFA_GEN - KENAR - 4
        alan_gen = self.x_sag - self.x_sol
        self.sutun_sayisi = max(1, int(alan_gen // self.sutun_gen))
        self.sutun_no = 0
        self.y = self.ust

    def _sutun_x(self):
        return self.x_sol + self.sutun_no * self.sutun_gen

    def _ilerle(self, gerekli):
        """gerekli yükseklik sığmıyorsa sütun/sayfa atlar."""
        if self.y + gerekli <= CVP_ALT:
            return
        self.sutun_no += 1
        self.y = self.ust
        if self.sutun_no >= self.sutun_sayisi:
            self._yeni_sayfa()

    def ders_bas(self, ders):
        """Bir dersin tüm sorularını akıtır; alan kayıtlarını üretir."""
        ad = str(ders.get("ad", ""))
        soru = int(ders["soru"])
        secenek = int(ders["secenek"])
        harfler = tuple(chr(65 + i) for i in range(secenek))
        sonraki = 1
        while sonraki <= soru:
            baslik_pay = BOLUM_BASLIK if ad else 4
            self._ilerle(baslik_pay + YAD * 2)   # başlık + en az 1 satır
            kurucu = self.sayfalar[-1]
            x = self._sutun_x()
            if ad:
                kurucu.yzi.nokta(kurucu.page, (x, self.y + 8),
                                 _tr_upper(ad)[:30], fontsize=7.0,
                                 color=(0, 0, 0))
                self.y += baslik_pay
            kalan_satir = int((CVP_ALT - self.y - CAP) // YAD)
            adet = min(soru - sonraki + 1, max(1, kalan_satir))
            ilk = (x + ETIKET_GEN + XAD / 2, self.y + YAD / 2 + CAP / 2)
            alan = osm.Alan(
                tip="coktan_secmeli",
                ad=f"{_slug(ad) or 'cevap'}_s{sonraki}",
                kutu=(x, self.y, x + ETIKET_GEN + secenek * XAD + 4,
                      self.y + (adet - 1) * YAD + CAP + YAD / 2),
                satir=adet, sutun=secenek, semboller=harfler,
                hucre=osm.Hucre(CAP, ilk, XAD, YAD),
                ders=ad, soru_baslangic=sonraki, soru_sayisi=adet)
            kurucu.alan_ekle(alan)
            for i in range(adet):
                kurucu.yzi.nokta(
                    kurucu.page,
                    (x + 1, ilk[1] + i * YAD + CAP * 0.32),
                    f"{sonraki + i}.", fontsize=6.8, color=(0, 0, 0))
            self.y = alan.kutu[3] + 6
            sonraki += adet


_TR_BUYUK = str.maketrans("iı", "İI")


def _tr_upper(metin):
    """Türkçe kurallı büyük harf (i→İ, ı→I; str.upper tek başına yanlış)."""
    return str(metin).translate(_TR_BUYUK).upper()


_SLUG_ESLE = str.maketrans("çğıöşüÇĞİÖŞÜ ", "cgiosuCGIOSU_")


def _slug(metin):
    ham = str(metin).translate(_SLUG_ESLE).lower()
    return "".join(c for c in ham if c.isalnum() or c == "_").strip("_")


def form_uret(tanim=None, yol="optik_form.pdf", on_ayar=None, sinav_id=None):
    """Optik form PDF'i + şablon JSON'u üretir.

    Dönüş: {"pdf", "sablon_yolu", "sablon", "sinav_id", "sayfa"}.
    Şablon PDF'in yanına <kok>.sablon.json olarak yazılır.
    """
    tanim = tanim_hazirla(tanim, on_ayar)
    hatalar = tanim_dogrula(tanim)
    if hatalar:
        raise ValueError("form tanımı geçersiz: " + "; ".join(hatalar))
    sinav_id = sinav_id or osm.sinav_id_uret()
    kitapcik_sayisi = int(tanim.get("kitapcik", 1) or 1)
    kitapcik_turleri = tuple(chr(65 + k) for k in range(kitapcik_sayisi))

    doc = fitz.open()
    yzi = _Yazi(yazi_tipi.ttf_yolu())
    akis = _CevapAkisi(doc, yzi, sinav_id, tanim, kitapcik_turleri)
    for ders in tanim["dersler"]:
        akis.ders_bas(ders)

    sablon = osm.Sablon(
        sinav_id=sinav_id,
        ad=tanim.get("ad") or "Optik Form",
        olusturma=datetime.datetime.now().isoformat(timespec="seconds"),
        kitapcik_turleri=kitapcik_turleri,
        puan_kurali={"yanlis_boler": int(tanim.get("yanlis_boler") or 0)},
        sayfalar=[k.kayit for k in akis.sayfalar])
    sorunlar = osm.dogrula(sablon)
    if sorunlar:
        doc.close()
        raise RuntimeError("üretilen şablon tutarsız (hata): "
                           + "; ".join(sorunlar[:4]))

    doc.save(yol, deflate=True)
    sayfa = len(doc)
    doc.close()
    kok, _ = os.path.splitext(yol)
    sablon_yolu = kok + ".sablon.json"
    osm.sablon_yaz(sablon, sablon_yolu)
    return {"pdf": yol, "sablon_yolu": sablon_yolu, "sablon": sablon,
            "sinav_id": sinav_id, "sayfa": sayfa}


class _Yazi:
    """sinav_pdf._Yazi ile aynı felsefe: fontfile her çağrıda, 'helv' yedeği."""

    def __init__(self, fontfile):
        self.ff = fontfile
        self.ad = "tur" if fontfile else "helv"

    def kutu(self, page, rect, metin, **kw):
        try:
            return page.insert_textbox(rect, metin, fontname=self.ad,
                                       fontfile=self.ff, **kw)
        except Exception:  # noqa: BLE001
            return page.insert_textbox(rect, metin, fontname="helv", **kw)

    def nokta(self, page, xy, metin, **kw):
        try:
            return page.insert_text(xy, metin, fontname=self.ad,
                                    fontfile=self.ff, **kw)
        except Exception:  # noqa: BLE001
            return page.insert_text(xy, metin, fontname="helv", **kw)
