#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Belge dışa aktarma — soruları Word (.docx) ve metin-öncelikli PDF'e çevirir.

Ana ilke: METİN, sorunun metadata'sından (govde/siklar — metin-katmanlı PDF'te
birebir, taranmışta Vision OCR) gelir; görselden YALNIZ şekil/grafik pikselleri
kesilir. Böylece şekilsiz soru tam editlenebilir metin olur; şekilli soruda metin
editlenebilir kalırken şekil orijinal görüntü olarak korunur.

Metin metadata'da yoksa (görüntü-gömülü kaynak) tüm kırpma tek görüntü olarak
gömülür (sadık yedek). Şekil bölgeleri kırpmanın KENDİ piksel uzayında tespit
edilir → hem metin-katmanı hem taranmış hem de banka (kaynak sayfa yok) için
tek, sağlam yol.

Word için python-docx gerekir (tembel import + nazik hata). PDF için ek bağımlılık
yok (fitz/PyMuPDF; Türkçe font + cevap anahtarı sinav_pdf'ten paylaşılır).
"""

import io
import sys

import numpy as np
from PIL import Image

from soru_kes import trasla, _otsu_esik, vision_satirlar, easyocr_satirlar

try:
    import docx
    from docx.shared import Inches, Pt, RGBColor
    from docx.enum.text import WD_ALIGN_PARAGRAPH
except ModuleNotFoundError:      # python-docx kurulu değil
    docx = None

MUREKKEP_ESIK = 0.030            # bir satırı "dolu" sayan mürekkep oranı
SEKIL_MIN_YUK = 0.055           # şekil bandı min yüksekliği (kırpma yüksekliği oranı)
METIN_KAPSAMA_ESIK = 0.40       # OCR bu orandan az satırı kaplarsa → tüm kırpma şekil
CIKTI_DPI = 300                 # kırpma piksel→fiziksel inç dönüşümü (yaklaşık)


# --------------------------------------------------------- şekil ayırma

def yatay_projeksiyon(pil_img):
    """Görüntünün YATAY mürekkep profili: p[y] = y satırındaki mürekkep oranı
    (0..1). dikey_projeksiyon'un (soru_kes.py) Y-ekseni (axis=1) ikizi.
    Dönüş: (p:list[float], k:int) — k: küçültme faktörü (1 küçük satır = k px)."""
    gri = pil_img.convert("L")
    k = max(1, round(gri.height / 1400))
    if k > 1:
        gri = gri.reduce(k)
    esik = _otsu_esik(gri)
    p = (np.asarray(gri) < esik).mean(axis=1).astype(float).tolist()
    return p, k


def sekil_bolgeleri(kirpma, ocr=None):
    """Bir soru kırpmasında (PIL) ŞEKİL/grafik bantlarını METİN bandından ayırır.
    Dönüş: [(x0,y0,x1,y1)] — kırpmanın KENDİ piksel uzayında, üstten alta.
    Boş liste → şekilsiz (ya da tüm kırpma metin). ocr: (metin,bbox) satırları;
    None ise macOS'ta vision_satirlar(kirpma), diğer platformlarda
    easyocr_satirlar(kirpma) ile üretilir."""
    G, Y = kirpma.width, kirpma.height
    if ocr is None:
        try:
            if sys.platform == "darwin":
                ocr = vision_satirlar(kirpma)
            else:
                ocr = [(s.metin, s.kutu) for s in easyocr_satirlar(kirpma)]
        except Exception:  # noqa: BLE001 — OCR hatası bir soruyu export'tan
            # düşürmesin: tüm kırpmayı tek şekil olarak koru (görsel yedek).
            bb = trasla(kirpma).getbbox() or (0, 0, G, Y)
            return [tuple(int(v) for v in bb)]
    p, k = yatay_projeksiyon(kirpma)     # küçültülmüş satır profili
    n = len(p)
    if not n:
        return []
    # metin kapsama maskesi: OCR satırlarının kapladığı (küçültülmüş) satırlar
    metin = [False] * n
    tol = int(Y * 0.012 / k) + 1
    for _m, (x0, y0, x1, y1) in ocr:
        i0 = max(0, int(y0 / k) - tol)
        i1 = min(n, int(y1 / k) + tol + 1)
        for i in range(i0, i1):
            metin[i] = True
    # metin kapsaması çok düşük ama mürekkep yüksekse → tüm kırpma tek şekil
    dolu = [i for i in range(n) if p[i] > MUREKKEP_ESIK]
    if dolu:
        kaplanan = sum(1 for i in dolu if metin[i]) / len(dolu)
        if kaplanan < METIN_KAPSAMA_ESIK:
            return [tuple(int(v) for v in trasla(kirpma).getbbox() or (0, 0, G, Y))]
    # şekil satırı: mürekkepli VE metin kaplamıyor → bantla
    sekil = [p[i] > MUREKKEP_ESIK and not metin[i] for i in range(n)]
    bantlar = []
    i = 0
    min_h = max(int(Y * SEKIL_MIN_YUK / k), 4)
    while i < n:
        if sekil[i]:
            j = i
            while j < n and sekil[j]:
                j += 1
            if (j - i) >= min_h and sum(p[i:j]) / (j - i) > MUREKKEP_ESIK:
                bantlar.append((i * k, j * k))
            i = j
        else:
            i += 1
    # her bandı gerçek içeriğe traşla (x + y daralt)
    sonuc = []
    for by0, by1 in bantlar:
        parca = kirpma.crop((0, max(0, by0 - 2), G, min(Y, by1 + 2)))
        bb = trasla(parca, kenar=0).getbbox()
        if bb is None:
            kutu = (0, by0, G, by1)
        else:
            # trasla ofsetini bilemeyiz; x'i parçanın kendi bbox'ından al
            ham = parca.getbbox() or (0, 0, G, by1 - by0)
            kutu = (ham[0], max(0, by0 - 2) + ham[1],
                    ham[2], max(0, by0 - 2) + ham[3])
        if kutu[2] - kutu[0] > G * 0.04 and kutu[3] - kutu[1] > 6:
            sonuc.append(tuple(int(v) for v in kutu))
    return sonuc


def _metin_var(soru):
    govde = (soru.get("govde") or soru.get("metin") or "").strip()
    return len(govde) >= 8 or len(soru.get("siklar") or {}) >= 2


def soru_akisi(soru, kirpma, ocr=None):
    """Soruyu editlenebilir metin + şekil görsel segmentlerine çevirir.
    Dönüş: {"sekilli":bool, "segmentler":[{"tur":"metin","icerik":str} |
    {"tur":"sekil","gorsel":PIL.Image}]}. Metin YALNIZ metadata'dan, görsel
    yalnız şekil bantlarından."""
    if not _metin_var(soru):
        # metin metadata'da yok (görüntü-gömülü) → tüm kırpmayı sadık koru
        return {"sekilli": True,
                "segmentler": [{"tur": "sekil", "gorsel": trasla(kirpma)}]}
    govde = (soru.get("govde") or soru.get("metin") or "").strip()
    siklar = soru.get("siklar") or {}
    sik_metin = "\n".join(f"{h}) {siklar[h]}" for h in sorted(siklar)
                          if siklar[h])
    bantlar = sekil_bolgeleri(kirpma, ocr=ocr)
    seg = []
    if govde:
        seg.append({"tur": "metin", "icerik": govde})
    for b in bantlar:
        seg.append({"tur": "sekil", "gorsel": trasla(kirpma.crop(b), kenar=6)})
    if len(siklar) >= 2 and sik_metin:
        seg.append({"tur": "metin", "icerik": sik_metin})
    if not seg:                      # ne metin ne bant → tüm kırpma
        return {"sekilli": True,
                "segmentler": [{"tur": "sekil", "gorsel": trasla(kirpma)}]}
    return {"sekilli": bool(bantlar), "segmentler": seg}


# --------------------------------------------------------- Word (.docx)

def _docx_gerekli():
    if docx is None:
        raise RuntimeError(
            "Word (.docx) çıktısı için 'python-docx' gerekli. Kurulum:\n"
            "  .venv/bin/pip install python-docx")


def _png_akis(img):
    bio = io.BytesIO()
    img.convert("RGB").save(bio, "PNG")
    bio.seek(0)
    return bio


def docx_uret(sorular, kirpmalar, yol, ayarlar=None, sayfalar=None):
    """Soruları editlenebilir Word belgesine yazar. Şekilsiz soru = tam
    editlenebilir metin; şekilli soru = editlenebilir gövde + gömülü şekil.
    Dönüş: {"yol","adet","sekilli","sekilsiz"}."""
    _docx_gerekli()
    ayarlar = ayarlar or {}
    doc = docx.Document()
    st = doc.styles["Normal"]
    st.font.name = "Calibri"          # Türkçe glifleri destekler (helv sorunu yok)
    st.font.size = Pt(11)
    ic_gen = (doc.sections[0].page_width - doc.sections[0].left_margin
              - doc.sections[0].right_margin)
    ic_inch = ic_gen / 914400.0       # EMU → inç

    if ayarlar.get("kurum"):
        pk = doc.add_paragraph(ayarlar["kurum"])
        pk.alignment = WD_ALIGN_PARAGRAPH.CENTER
        pk.runs[0].font.size = Pt(10.5); pk.runs[0].font.color.rgb = RGBColor(0x55, 0x55, 0x55)
    if ayarlar.get("baslik"):
        h = doc.add_heading(ayarlar["baslik"], level=1)
        h.alignment = WD_ALIGN_PARAGRAPH.CENTER

    sekilli = sekilsiz = 0
    for j, soru in enumerate(sorular):
        img = kirpmalar[j]
        akis = soru_akisi(soru, img)
        if akis["sekilli"]:
            sekilli += 1
        else:
            sekilsiz += 1
        no = (j + 1) if ayarlar.get("yeniden_numarala", True) \
            else (soru.get("soru_no") or j + 1)
        ilk = True
        for seg in akis["segmentler"]:
            if seg["tur"] == "metin":
                p = doc.add_paragraph()
                if ilk:
                    r = p.add_run(f"{no}. ")
                    r.bold = True
                p.add_run(seg["icerik"])
                ilk = False
            else:
                if ilk:
                    pn = doc.add_paragraph()
                    pn.add_run(f"{no}.").bold = True
                    ilk = False
                g = seg["gorsel"]
                gen = min(ic_inch, g.width / CIKTI_DPI)
                doc.add_picture(_png_akis(g), width=Inches(gen))
        doc.add_paragraph()           # sorular arası boşluk

    if ayarlar.get("cevap_anahtari"):
        _docx_cevap_anahtari(doc, sorular, ayarlar)

    doc.save(yol)
    return {"yol": yol, "adet": len(sorular),
            "sekilli": sekilli, "sekilsiz": sekilsiz}


def _docx_cevap_anahtari(doc, sorular, ayarlar):
    cevaplar = [(i + 1 if ayarlar.get("yeniden_numarala", True)
                 else (sorular[i].get("soru_no") or i + 1),
                 sorular[i].get("cevap"))
                for i in range(len(sorular)) if sorular[i].get("cevap")]
    if not cevaplar:
        return
    doc.add_page_break()
    h = doc.add_heading("Cevap Anahtarı", level=1)
    h.alignment = WD_ALIGN_PARAGRAPH.CENTER
    sut = 6
    satir = (len(cevaplar) + sut - 1) // sut
    tab = doc.add_table(rows=satir, cols=sut)
    tab.style = "Table Grid"
    for k, (no, harf) in enumerate(cevaplar):
        r, c = divmod(k, sut)
        tab.cell(r, c).text = f"{no}. {harf}"


# --------------------------------------------------------- metin-öncelikli PDF

def _sar(font, metin, fs, gen):
    """Metni gen genişliğine kelime-kelime sararak satır listesi döndürür."""
    satirlar = []
    for ham in metin.split("\n"):
        if not ham.strip():
            satirlar.append("")
            continue
        sozler = ham.split(" ")
        cur = ""
        for s in sozler:
            dene = (cur + " " + s).strip()
            if font.text_length(dene, fontsize=fs) <= gen or not cur:
                cur = dene
            else:
                satirlar.append(cur); cur = s
        if cur:
            satirlar.append(cur)
    return satirlar


def pdf_metin_uret(sorular, kirpmalar, yol, ayarlar=None, sayfalar=None):
    """Metin-öncelikli sınav PDF'i: şekilsiz soru VEKTÖR metin, şekilli soru
    metin + gömülü görüntü. sinav_pdf'in tümüyle-görüntü akışından farklı;
    Türkçe font ilkellerini ondan alır. Dönüş: {"sayfa","yol","yollar"}."""
    import fitz
    import sinav_pdf as sp
    ayarlar = ayarlar or {}
    A4 = sp.A4
    KEN = sp.KENAR
    ic_x0, ic_x1 = KEN, A4.width - KEN
    gen = ic_x1 - ic_x0
    alt_y = A4.height - KEN - sp.ALT_BANT
    ff = sp._font_bul()
    yzi = sp._Yazi(ff)
    font = fitz.Font(fontfile=ff) if ff else fitz.Font("helv")
    fs, lh = 11, 15.0

    doc = fitz.open()
    page = doc.new_page(width=A4.width, height=A4.height)
    y = [KEN]

    def yeni_sayfa():
        nonlocal page
        page = doc.new_page(width=A4.width, height=A4.height)
        y[0] = KEN

    # başlık
    yb = KEN
    if ayarlar.get("kurum"):
        yzi.kutu(page, fitz.Rect(KEN, yb, ic_x1, yb + 16), ayarlar["kurum"],
                 fontsize=10.5, align=fitz.TEXT_ALIGN_CENTER, color=(.3, .3, .3))
        yb += 16
    if ayarlar.get("baslik"):
        yzi.kutu(page, fitz.Rect(KEN, yb, ic_x1, yb + 26), ayarlar["baslik"],
                 fontsize=16, align=fitz.TEXT_ALIGN_CENTER)
        yb += 30
    y[0] = yb + 6

    def metin_bas(txt, kalin_no=None):
        satir = _sar(font, txt, fs, gen)
        gerek = len(satir) * lh
        if y[0] + gerek > alt_y:
            yeni_sayfa()
        yzi.kutu(page, fitz.Rect(ic_x0, y[0], ic_x1, y[0] + gerek + 4),
                 txt, fontsize=fs, align=fitz.TEXT_ALIGN_LEFT)
        y[0] += gerek + 4

    def gorsel_bas(img):
        olcek = min(gen / img.width, (alt_y - KEN) / img.height)
        w, h = img.width * olcek, img.height * olcek
        if y[0] + h > alt_y:
            yeni_sayfa()
        bio = io.BytesIO(); img.convert("RGB").save(bio, "PNG")
        page.insert_image(fitz.Rect(ic_x0, y[0], ic_x0 + w, y[0] + h),
                          stream=bio.getvalue())
        y[0] += h + 6

    for j, soru in enumerate(sorular):
        no = (j + 1) if ayarlar.get("yeniden_numarala", True) \
            else (soru.get("soru_no") or j + 1)
        akis = soru_akisi(soru, kirpmalar[j])
        ilk = True
        for seg in akis["segmentler"]:
            if seg["tur"] == "metin":
                metin_bas((f"{no}. " if ilk else "") + seg["icerik"])
            else:
                if ilk:
                    metin_bas(f"{no}.")
                gorsel_bas(seg["gorsel"])
            ilk = False
        y[0] += sp.SORU_ARA

    if ayarlar.get("cevap_anahtari"):
        sp._cevap_anahtari_sayfasi(doc, sorular,
                                   ayarlar.get("yeniden_numarala", True), yzi)

    n = len(doc)
    for i, pg in enumerate(doc, 1):
        yzi.kutu(pg, fitz.Rect(KEN, A4.height - KEN + 2, ic_x1,
                               A4.height - 8), f"Sayfa {i} / {n}", fontsize=9,
                 align=fitz.TEXT_ALIGN_CENTER, color=(.4, .4, .4))
    doc.save(yol, deflate=True)
    doc.close()
    return {"sayfa": n, "yol": yol, "yollar": [yol]}
