#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Sınav kağıdı üretici — kirpma_seti çıktısı (soru PNG'leri + metadata) alıp
yazdırılabilir A4 sınav PDF'i dizer. fitz (PyMuPDF) ile vektör metin + gömülü
görüntü; başka bağımlılık yok.

Yerleşim: soru sırası KORUNUR (sınavda sıra değişmez). Sütun genişliğine
sığan sorular 2 sütuna akıtılır; geniş (grafikli/tam-sayfa) sorular tüm sayfa
genişliğini kaplayıp bandı kırar. Yeniden numaralama: kaynak kırpmadaki eski
numara kirpma_seti tarafından beyazlatılmışsa (numara_px) yerine 1..N vektör
rakam basılır.
"""

import os

import fitz

A4 = fitz.paper_rect("a4")            # 595 × 842 pt
KENAR = 36
ARA = 18                              # sütun arası
SORU_ARA = 14                         # sorular arası dikey boşluk
ALT_BANT = 26                         # "Sayfa X / Y" için ayrılan alt şerit
BASLIK_YUK = 74                       # ilk sayfa başlık + alan satırı yüksekliği
SPAN_ESIK = 1.45                      # medyan genişliğin bu katından genişi = span

# Türkçe glifler için sistem TrueType zinciri (base-14 "helv" ş/ğ/İ içermez).
# Ortak liste yazi_tipi modülünde — PIL tarafı (cevap bandı) da aynını kullanır.
import yazi_tipi

_FONT_ADAYLARI = yazi_tipi.TTF_ADAYLARI


def _medyan(dizi):
    d = sorted(dizi)
    return d[len(d) // 2] if d else 0.0


class _Yerlesim:
    """A4 sayfalarına band+sütun akışıyla görüntü yerleştirir. Numaralar
    yerleştirmeden sonra ikinci geçişte basılır (font yüklemesi orada)."""

    def __init__(self, doc, sutun, ic_x0, ic_x1, ust_y, alt_y):
        self.doc = doc
        self.sutun = sutun
        self.ic_x0, self.ic_x1 = ic_x0, ic_x1
        self.ust_y, self.alt_y = ust_y, alt_y
        self.sutun_gen = ((ic_x1 - ic_x0) - ARA * (sutun - 1)) / sutun
        self.page = None
        self.yerlestirmeler = []       # (page_index, rect, png, no, numara_px)
        self._yeni_sayfa(ilk=True)

    def _yeni_sayfa(self, ilk=False):
        self.page = self.doc.new_page(width=A4.width, height=A4.height)
        self.pno = len(self.doc) - 1
        bas = self.ust_y if ilk else KENAR
        self.sut_y = [bas] * self.sutun     # her sütunun mevcut y'si
        self.kol = 0

    def _sig(self, y, h):
        return y + h <= self.alt_y

    def yerlestir(self, png, w, h, no, numara_px, span):
        if span:
            self._span(png, w, h, no, numara_px)
        else:
            self._sutun(png, w, h, no, numara_px)

    def _sutun(self, png, w, h, no, numara_px):
        olcek = self.sutun_gen / w
        yh = h * olcek
        # Sığacak ilk sütunu (soldan sağa) seç; hiçbiri sığmazsa yeni sayfa.
        # Tek soru bir sütundan uzunsa ek küçültmeyle sığdır (nadir).
        if yh > self.alt_y - KENAR:
            olcek = (self.alt_y - KENAR) / h
            yh = self.alt_y - KENAR
        yer_var = next((k for k in range(self.sutun)
                        if self._sig(self.sut_y[k], yh)), None)
        if yer_var is None:
            self._yeni_sayfa()
            yer_var = 0
        self.kol = yer_var
        x0 = self.ic_x0 + self.kol * (self.sutun_gen + ARA)
        y0 = self.sut_y[self.kol]
        self._koy(png, x0, y0, self.sutun_gen, yh, no, numara_px, olcek)
        self.sut_y[self.kol] += yh + SORU_ARA

    def _span(self, png, w, h, no, numara_px):
        tam_gen = self.ic_x1 - self.ic_x0
        olcek = min(tam_gen / w, (self.alt_y - KENAR) / h)
        yh = h * olcek
        xw = w * olcek
        taban = max(self.sut_y)
        if not self._sig(taban, yh):
            self._yeni_sayfa()
            taban = max(self.sut_y)
        self._koy(png, self.ic_x0, taban, xw, yh, no, numara_px, olcek)
        yeni = taban + yh + SORU_ARA
        self.sut_y = [yeni] * self.sutun     # band kırıldı: sütunları hizala
        self.kol = 0

    def _koy(self, png, x0, y0, w, h, no, numara_px, olcek):
        rect = fitz.Rect(x0, y0, x0 + w, y0 + h)
        self.page.insert_image(rect, stream=png)
        self.yerlestirmeler.append((self.pno, rect, no, numara_px, olcek))


def _font_bul():
    """Türkçe destekli sistem TrueType yolu | None (→ 'helv' yedeği)."""
    return yazi_tipi.ttf_yolu()


class _Yazi:
    """fontfile'ı her çağrıda geçen metin yardımcısı — font sayfa-özel kaynak
    olduğundan (her yeni sayfada yeniden gömülmeli) bu en sağlam yol. Font
    yoksa 'helv'e düşer (Türkçe glifler bozulabilir; loglanmaz)."""

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


def _grup_ici_karistir(meta, tohum, kitapcik_idx):
    """Soru sırasını KİTAPÇIK için permüte eder. Test/bölüm grupları kendi
    içinde karışır, grup sırası korunur — konu bütünlüğü bozulmadan kopya
    zorlaşır (testinvite 'sistematik rastgeleleştirme' mantığı). Kitapçık 0
    (A) orijinal sırayı korur (kaynak referansı)."""
    n = len(meta)
    if kitapcik_idx == 0:
        return list(range(n))
    import random
    rnd = random.Random((tohum or 0) * 100 + kitapcik_idx)
    gruplar, sira = {}, []
    for j in range(n):
        ts = meta[j].get("test_sira")
        if ts not in gruplar:
            gruplar[ts] = []
            sira.append(ts)
        gruplar[ts].append(j)
    sonuc = []
    for ts in sira:
        g = gruplar[ts][:]
        rnd.shuffle(g)
        sonuc.extend(g)
    return sonuc


def sinav_pdf_uret(kirpmalar, meta, ayarlar, yol):
    """Kesilen soru PNG'lerinden A4 sınav PDF('ler)i üretir.
    ayarlar: {baslik, kurum, ad_soyad, tarih, sinif, no, sutun,
    yeniden_numarala, cevap_anahtari, toplam_puan, kitapcik, tohum}.
    kitapcik>1: A/B/C/D kitapçıkları (<yol>_A.pdf …), her biri soru sırası
    farklı + kendi cevap anahtarı. Dönüş: {"sayfa", "yollar", "kitapcik"}."""
    kitapcik = max(1, int(ayarlar.get("kitapcik", 1) or 1))
    if kitapcik == 1:
        n = _tek_pdf(kirpmalar, meta, ayarlar, yol, None,
                     list(range(len(kirpmalar))))
        return {"sayfa": n, "yollar": [yol], "kitapcik": 1}
    kok, uz = os.path.splitext(yol)
    tohum = ayarlar.get("tohum")
    toplam, yollar = 0, []
    for k in range(kitapcik):
        harf = chr(65 + k)
        sira = _grup_ici_karistir(meta, tohum, k)
        kyol = f"{kok}_{harf}{uz}"
        toplam += _tek_pdf(kirpmalar, meta, ayarlar, kyol, harf, sira)
        yollar.append(kyol)
    return {"sayfa": toplam, "yollar": yollar, "kitapcik": kitapcik}


def _puan_metni(puan):
    if puan is None:
        return ""
    p = round(puan, 1)
    return f" ({int(p) if p == int(p) else p}p)"


def _tek_pdf(kirpmalar, meta, ayarlar, yol, kitapcik_harf, sira):
    """Tek bir sınav kitapçığı üretir. sira: kirpmalar/meta'nın kullanılacak
    indeks sırası (kitapçık permütasyonu). Dönüş: sayfa sayısı."""
    import io

    baslik = ayarlar.get("baslik") or "Sınav"
    kurum = ayarlar.get("kurum") or ""
    # sutun 1..4 aralığına sıkıştır: negatif/0/çok büyük değer sutun_gen'i
    # negatife düşürüp bozuk yerleşim/fitz hatası yapardı.
    try:
        sutun = max(1, min(4, int(ayarlar.get("sutun", 2)) or 2))
    except (TypeError, ValueError):
        sutun = 2
    yeniden = ayarlar.get("yeniden_numarala", True)
    toplam_puan = ayarlar.get("toplam_puan")
    alanlar = [ad for ad, ac in (("Adı Soyadı", ayarlar.get("ad_soyad", True)),
                                 ("Sınıf", ayarlar.get("sinif", True)),
                                 ("No", ayarlar.get("no", False)),
                                 ("Tarih", ayarlar.get("tarih", True))) if ac]
    # sira'ya göre yeniden diz
    kirp = [kirpmalar[j] for j in sira]
    met = [meta[j] for j in sira]
    n_soru = len(kirp)
    soru_puani = (toplam_puan / n_soru) if (toplam_puan and n_soru) else None

    pngler = []
    for img in kirp:
        bio = io.BytesIO()
        img.save(bio, "PNG")
        pngler.append((bio.getvalue(), img.width, img.height))
    med_w = _medyan([w for _, w, _ in pngler]) or 1
    span_orani = sum(1 for _, w, _ in pngler if w > med_w * SPAN_ESIK) \
        / max(1, len(pngler))
    if span_orani > 0.5:
        sutun = 1

    # başlık bloğu yüksekliğini içeriğe göre hesapla (dinamik)
    puan_satiri = bool(toplam_puan)
    ust_bosluk = 0
    if baslik or alanlar or kurum:
        ust_bosluk = ((17 if kurum else 0) + (30 if baslik else 0)
                      + (15 if puan_satiri else 0) + (22 if alanlar else 0)
                      + 12)
    doc = fitz.open()
    yer = _Yerlesim(doc, sutun, KENAR, A4.width - KENAR, KENAR + ust_bosluk,
                    A4.height - KENAR - ALT_BANT)
    for i, (png, w, h) in enumerate(pngler):
        span = (sutun == 1) or (w > med_w * SPAN_ESIK)
        no = (i + 1) if yeniden else (met[i].get("soru_no") or (i + 1))
        yer.yerlestir(png, w, h, no, met[i].get("numara_px"), span)

    yzi = _Yazi(_font_bul())
    ilk = doc[0]
    yb = KENAR
    if kurum:
        yzi.kutu(ilk, fitz.Rect(KENAR, yb, A4.width - KENAR, yb + 17), kurum,
                 fontsize=10.5, align=fitz.TEXT_ALIGN_CENTER,
                 color=(0.3, 0.3, 0.3))
        yb += 17
    if baslik:
        bmetin = baslik + (f"  —  Kitapçık {kitapcik_harf}"
                           if kitapcik_harf else "")
        yzi.kutu(ilk, fitz.Rect(KENAR, yb, A4.width - KENAR, yb + 28), bmetin,
                 fontsize=16, align=fitz.TEXT_ALIGN_CENTER)
        yb += 30
    # puan/soru sayısı: başlık altında ORTALI ince satır (çakışma yok)
    if puan_satiri:
        tp = int(toplam_puan) if toplam_puan == int(toplam_puan) else toplam_puan
        parca = [f"Toplam {tp} puan"]
        if soru_puani:
            parca.append(f"her soru {_puan_metni(soru_puani).strip(' ()')}")
        parca.append(f"{n_soru} soru")
        yzi.kutu(ilk, fitz.Rect(KENAR, yb, A4.width - KENAR, yb + 15),
                 " · ".join(parca), fontsize=9.5,
                 align=fitz.TEXT_ALIGN_CENTER, color=(0.3, 0.3, 0.3))
        yb += 15
    if alanlar:
        satir = "     ".join(f"{a}: {'.' * (18 if a == 'Adı Soyadı' else 8)}"
                             for a in alanlar)
        yzi.kutu(ilk, fitz.Rect(KENAR, yb, A4.width - KENAR, yb + 22), satir,
                 fontsize=10.5)
    if baslik or alanlar or kurum:
        y = KENAR + ust_bosluk - 8
        ilk.draw_line(fitz.Point(KENAR, y), fitz.Point(A4.width - KENAR, y),
                      color=(0.6, 0.6, 0.6), width=0.6)

    if yeniden:
        for pno, rect, no, numara_px, olcek in yer.yerlestirmeler:
            page = doc[pno]
            etiket = f"{no}."   # puan başlıkta (eşit dağıtım) — soru üstünde değil
            if numara_px is not None:
                nx0, ny0, nx1, ny1 = numara_px
                px = rect.x0 + nx0 * olcek
                py = rect.y0 + ny1 * olcek - (ny1 - ny0) * olcek * 0.15
                fs = max(8, min(14, (ny1 - ny0) * olcek * 0.85))
                yzi.nokta(page, (px, py), etiket, fontsize=fs, color=(0, 0, 0))
            else:
                yzi.nokta(page, (rect.x0 + 2, rect.y0 + 12), etiket,
                          fontsize=11, color=(0.1, 0.1, 0.1))

    if ayarlar.get("cevap_anahtari"):
        _cevap_anahtari_sayfasi(doc, met, yeniden, yzi, kitapcik_harf)

    n = len(doc)
    alt = f"Sayfa {{i}} / {n}"
    for i, page in enumerate(doc, 1):
        yzi.kutu(page, fitz.Rect(KENAR, A4.height - KENAR + 2,
                                 A4.width - KENAR, A4.height - 8),
                 alt.replace("{i}", str(i)), fontsize=9,
                 align=fitz.TEXT_ALIGN_CENTER, color=(0.4, 0.4, 0.4))

    doc.save(yol, deflate=True)
    doc.close()
    return n


def _cevap_anahtari_sayfasi(doc, meta, yeniden, yzi, kitapcik_harf=None):
    """Son sayfaya 'Cevap Anahtarı' ızgarası ekler (yeni numaralarla).
    Kitapçık modunda başlığa kitapçık harfi eklenir (her kitapçık farklı)."""
    cevaplar = [(i + 1 if yeniden else (meta[i].get("soru_no") or i + 1),
                 meta[i].get("cevap"))
                for i in range(len(meta)) if meta[i].get("cevap")]
    if not cevaplar:
        return
    page = doc.new_page(width=A4.width, height=A4.height)
    bas = "Cevap Anahtarı" + (f" — Kitapçık {kitapcik_harf}"
                             if kitapcik_harf else "")
    yzi.kutu(page, fitz.Rect(KENAR, KENAR, A4.width - KENAR, KENAR + 28),
             bas, fontsize=15, align=fitz.TEXT_ALIGN_CENTER)
    sut = 6
    huc_w = (A4.width - 2 * KENAR) / sut
    y = KENAR + 44
    for k, (no, harf) in enumerate(cevaplar):
        c = k % sut
        yzi.nokta(page, (KENAR + c * huc_w + 4, y), f"{no}. {harf}",
                  fontsize=11)
        if c == sut - 1:
            y += 20
