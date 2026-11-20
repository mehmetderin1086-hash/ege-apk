#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Soru Kesici — herhangi bir yayının çoktan seçmeli test sayfalarını
(PDF / JPG / PNG) soru soru kırpıp her soruyu ayrı PNG olarak Arşiv.zip'e
koyar.

Program yükleme sırasında dosyayı ÖN İZLER: metin katmanı var mı yoksa
taranmış mı, kaç sütun, numara formatı nasıl otomatik tespit edilir
(kalibrasyon) ve ayarlar buna göre seçilir. Böylece yayınevi, sayfa
düzeni veya soru biçimi değişse de sorular doğru kesilebilir.

Kullanım:
    python soru_kes.py 1.pdf                  # → yanına Arşiv.zip
    python soru_kes.py test.pdf -o cikti.zip
    python soru_kes.py s1.png s2.jpg -o Arşiv.zip
    python soru_kes.py test.pdf --onizleme    # kesmeden tespiti görselle
    python soru_kes.py test.pdf --dpi 220     # çözünürlük
"""

import argparse
import hashlib
import io
import json
import os
import platform
import re
import subprocess
import unicodedata
import sys
import tempfile
import threading
import zipfile
from collections import Counter
from dataclasses import asdict, dataclass, field
from typing import NamedTuple

import fitz  # PyMuPDF
from PIL import Image, ImageDraw, ImageOps

import veri_yollari

try:                    # görsel projeksiyon için önerilir; yoksa Pillow-yedek
    import numpy as _np
except ImportError:
    _np = None

try:                    # ML düzen tespiti (isteğe bağlı; yoksa/kapalıysa
    import duzen_model  # sezgisel yol aynen çalışır — kurulum: duzen_kur.py)
except Exception:  # noqa: BLE001 — modül eksik/bozuksa uygulama etkilenmez
    duzen_model = None

# Satır başındaki soru numarası: "1.", "12)", "3 ." gibi. Sütun hizası ve
# artan-zincir filtreleri sahte eşleşmeleri (metin içi sayı, romen "I.")
# temizlediğinden desen bilerek geniş tutulur.
# Satır başındaki soru numarası: "1.", "12)", "3 .". Numaranın önünde tek
# bir gürültü jetonu (soru işareti/madde ikonunun OCR'da bıraktığı '0', '•'
# gibi tek karakter + boşluk) toleransı vardır; taranmış testlerde büyüteç
# ikonu numarayı "0 3." biçiminde okutabiliyor. Sütun hizası ve artan-zincir
# filtreleri sahte eşleşmeleri (metin içi sayı, romen "I.") ayrıca temizler.
SORU_NO_DESENI = re.compile(
    r"^\s*(?:(?:soru|question)\s*[-–—.:)]*\s*)?"
    r"(?:\S\s+)?(\d{1,3})\s*(?:[.):]|[-–—]\s*[.)]?)"
    r"(?=\s|$|\d{1,3}\s*(?:puan|points?)\b)", re.I)
# Birleşik OCR satırında (iki sütun köprülenmiş) GİZLİ soru başlangıcı:
# numara + ayraç + BÜYÜK harfle başlayan sözcük (ör. "...yıkıl, 6. Aşağıdak").
# SORU_NO_DESENI'nin aksine satır BAŞINA çapalı DEĞİLDİR — satır ortasında da
# eşleşir; ama devamının büyük harfle başlaması şart koşulduğundan satır-
# ortası meşru sayılar YAKALANMAZ: "6. kromozomda" (küçük harf), "Şekil 6."
# (devamı yok/küçük harf), "1., 3. ve 6. önermeler" (hep küçük harfle devam
# eder). Sol tarafta `(?<!\d)` — çok basamaklı bir sayının SON hanelerini
# yakalayıp "…1923. Türkiye…" gibi bir yıl referansını sahte soru sanmaz.
# Yalnız _aday_bant_araligi'nin gutter-aşan-satır vetosunda kullanılır.
SATIR_ICI_SORU_BASLANGICI = re.compile(
    r"(?<!\d)(\d{1,3})\s*[.):]\s+(?=[A-ZÇĞİÖŞÜ])")
# Birden fazla sorunun kullandığı ortak metin/şekil başlığı: "39-40. soruları
# aşağıdaki parçaya göre cevaplayınız". Bu satır 39. sorunun kendisi değildir;
# gerçek 39 ve 40 çapaları ayrıca gelir. Kesim planı ortak uyaranı her iki
# soruya ayrı parça olarak ekler.
ORTAK_SORU_ARALIGI = re.compile(
    r"^\s*(\d{1,3})\s*(?:[-–—]|ve|ile)\s*(\d{1,3})\s*[.)]?\s*"
    r"sorular[ıi]\b", re.I)
# Soru numarasıyla aynı biçimde başlayan fakat belge üstbilgisi/bölüm başlığı
# olan satırlar. "Soru-4)" açık ön eki her zaman gerçek çapa sayılır; bu filtre
# yalnız çıplak "10. Sınıf", "1. Dönem", "2. Ünite" biçimlerine uygulanır.
NUMARALI_BASLIK_DESENI = re.compile(
    r"^\s*\d{1,3}\s*[.)]\s*(?:s[ıi]n[ıi]f|d[oö]nem|[uü]nite|b[oö]l[uü]m|"
    r"yaz[ıi]l[ıi]|oturum|ders|konu)\b", re.I)
# Deneme kitaplarının bölüm başındaki numaralı kullanım yönergeleri, gerçek
# soru numarasıyla aynı tipografiyi kullanabilir. Bunlar zincire girerse
# örneğin gerçek 1–4 yerine üstbilgideki 1–2 seçilip son sorular kaybolur.
NUMARALI_TALIMAT_DESENI = re.compile(
    r"^\s*\d{1,3}\s*[.)]\s*(?:bu\s+testte\b|"
    r"cevaplar[ıi]n[ıi]z[ıi]\b|"
    r"(?:yks\s+)?deneme(?:ler[ıi])?\b)",
    re.I)
# Çoktan seçmeli şık: satır/parantez başında A–E + nokta/parantez ("A)", "B.").
# ``SIK_DESENI`` metni gövde/şıklara ayıran geriye-uyumlu ayrıştırıcıdır.
# Güven/format kararları ise `_sik_harfleri` kullanır: kitap şekillerindeki
# küçük ``(a) (b) (c)`` panel etiketleri şık değildir. Küçük harfli gerçek
# OCR şıkkı yalnız parantezsiz ``a)`` / ``a.`` biçimindeyse kabul edilir.
SIK_DESENI = re.compile(r"(?:^|[\s(])([A-Ea-e])\s*[.)]")
SIK_GUCLU_DESENI = re.compile(r"(?:^|[\s(])([A-E])\s*[.)]")
SIK_KUCUK_DESENI = re.compile(r"(?:^|\s)([a-e])\s*[.)](?=\s*\S)")


def _sik_harfleri(metin):
    """Bir OCR/metin satırındaki gerçek seçenek işaretlerini döndürür.

    Büyük A–E, satır içinde yan yana yazılmış şıklarda da güvenlidir.
    Küçük a–e satır başında veya soru numarasından sonra ``a)``/``a.``
    biçiminde kabul edilir; ``(a)`` şekil-panel etiketi özellikle dışarıda
    bırakılır.
    """
    sonuc = {h.upper() for h in SIK_GUCLU_DESENI.findall(str(metin))}
    sonuc.update(h.upper() for h in SIK_KUCUK_DESENI.findall(str(metin)))
    return sonuc
# Format sinyalleri (belge türünü otomatik sınıflamak için)
COZUM_DESENI = re.compile(r"^\s*(çözüm|çözümü|cevap|yanıt|çöz)\b\s*[:.]?", re.I)
# Çözüm bölümü çapası: "Soru 1 :", "Çözüm 5", "Cevap 3" — numarası SORU_NO
# gibi nokta/parantezle bitmeyen çözüm-anahtarı girişleri. YALNIZ sayfa
# formatı 'cozumlu' iken kullanılır (çoktan seçmeli korpusa etkisiz).
COZUM_NO_DESENI = re.compile(
    r"^\s*(?:soru|çözüm|cozum|cevap|yanıt)\s*[-–—.:]?\s*(\d{1,3})\b", re.I)
NOKTALI_SATIR = re.compile(r"[.…_·]{6,}")             # yazma/cevap alanı
# İÇİNDEKİLER lider satırı: "... Konu Başlığı ......... 21" (nokta dizisi + sayfa
# no ile biter). Açık uçlu cevap satırından (sona sayfa no gelmez) ayırt eder.
TOC_LIDER = re.compile(r"[.·…]{3,}\s*\d{1,3}\s*$")
ALT_MADDE_DESENI = re.compile(r"^\s*[a-fçğıöşü]\s*[.)]\s+\S")  # "a. b." alt madde
TANIM_MADDE = re.compile(r"^\s*\d{1,3}[.)]\s+.{1,40}:\s*$")    # "1. Duyu Nöronu:"
# Soru gövdesi sinyali. Soru eki (mıdır/midir…) Türkçede AYRI yazılan bir
# sözcüktür → \b ile sınırlanır (yoksa "birimidir", "kaldırılabilir" gibi düz
# metin sözcükleri "…midir" içerdiği için yanlış eşleşir). "olabilir/doğrudur/
# yanlıştır" gibi çok yaygın bildirim sözcükleri çıkarıldı (bilgi paneli/konu
# metni yanlış-pozitifi); gerçek sorular zaten "hangisi/aşağıdaki…" ile eşleşir.
SORU_GOVDE = re.compile(
    r"(\b(?:mıdır|midir|mudur|müdür)\b|\bnedir\b|hangisi|hangileri|aşağıdaki|"
    r"aşağıda|yukarıdaki|yazınız|açıklayınız|belirtiniz|bulunuz|hesaplayınız|"
    r"doldurunuz|tamamlayınız|eşleştiriniz|işaretleyiniz|çiziniz|"
    r"kaçtır|nelerdir|\bneden\b|veriniz|gösteriniz|söyleyiniz)", re.I)
# Bir bloğun yalnız soru bağlamı taşıdığını değil, kendi başına tamamlanmış
# bir soru/yönerge olduğunu gösteren daha dar sinyal. "aşağıdaki şekilde
# gösterilmiştir" gibi şekil girişleri SORU_GOVDE'dir ama tamamlanmış soru
# değildir; görselden sonraki asıl soru cümlesiyle ayrılmamalıdır.
SORU_YONERGE_GUCLU = re.compile(
    r"(\?|"
    r"\b(?:mıdır|midir|mudur|müdür)\b|\bnedir\b|hangisi|hangileri|"
    r"yazınız|açıklayınız|belirtiniz|bulunuz|hesaplayınız|doldurunuz|"
    r"tamamlayınız|eşleştiriniz|işaretleyiniz|çiziniz|kaçtır|nelerdir|"
    r"\bneden\b|veriniz|gösteriniz|söyleyiniz)", re.I)
# Sayfanın altındaki imza/kurum bandı, son sorunun metnine ve kırpmasına
# karışmamalı. Yalnız sayfanın alt bölümünde kullanıldığı için soru metninde
# geçen sıradan "öğretmen" sözcüklerine etkisi yoktur.
ALT_BILGI_DESENI = re.compile(
    r"(?:öğretmen[ıi]|okul\s+müdür[üu]|haz[ıi]rlayan|\bimza\b|"
    r"diğer\s+sayfaya\s+geçiniz|devam\s+ediniz|sayfay[ıi]\s+çeviriniz)",
    re.I)
# Çıkmış soru derlemelerinde her sorunun altındaki kaynak damgası, o sorunun
# kesin semantik sonudur. Ardından gelen ders dipnotu / yeni konu indeksi aynı
# sütunda bulunsa bile kırpmaya dahil edilmemelidir.
SINAV_KAYNAK_DAMGASI = re.compile(
    r"^\s*\*?\s*(?:19|20)\d{2}\s*[-–—]\s*(?:TYT|AYT|YKS)\s*$", re.I)
# --- Test bölümü başlığı --------------------------------------------------
# "TEST 1", "TEST–2", "TEST - 3", "3. TEST", "KAZANIM TESTİ 5",
# "TARAMA TESTİ 3", "DENEME 1", "ÜNİTE 2 TEST 4", numarasız "TEST".
# Türkçe İ/ı, re.I ile eşleşmez → 'test' son eki açık [İIiı] sınıfıyla
# yakalanır. Kısa-satır/büyük-harf ön koşulları test_basliklari'nda.
TEST_KOK = re.compile(r"\bTEST[İIiı]?\b|\bDENEME\b|\bTARAMA\b", re.I)
TEST_NO_SONEK = re.compile(
    r"(?:TEST[İIiı]?|DENEME)[\s\-–—.:)№]*(\d{1,3})\b", re.I)
TEST_NO_ONEK = re.compile(r"(\d{1,3})\s*[.\-–—)]?\s*(?:TEST|DENEME)\b", re.I)
# --- Cevap anahtarı -------------------------------------------------------
CEVAP_BASLIK = re.compile(r"cevap\s*anahtar|yanıt\s*anahtar", re.I)
# Kitap sonundaki açık-uçlu çözüm bölümleri A-E cevap ızgarası taşımaz;
# klasik cevap-anahtarı sezgisi bunları kaçırır. Başlangıç ve bitiş işaretleri
# belge düzeyinde izlenerek devam sayfaları da dışlanır.
MINI_SINAV_DESENI = re.compile(r"\bmini\s+s[ıi]nav\b", re.I)
COZUM_BOLUM_BASLIK = re.compile(
    r"^\s*(?:mini\s+s[ıi]nav\s+)?(?:ç[oö]z[uü]mler[ıi]?|cozumleri?|"
    r"cevaplar[ıi]?|yan[ıi]tlar[ıi]?)\s*$", re.I)
COZUM_BOLUM_BITIS = re.compile(
    r"^\s*(?:ders\s+notlar[ıi]|kaynakça|notlar)\b", re.I)
# "1. A", "1-A", "1) B", "1 A" cevap hücresi. Negatif ileri-bakış Türkçe
# harfleri, rakamı VE şık ayracını dışlar ("1. Aşağıdaki" A'sı ya da
# "A) 5 B) 10" sayısal şık satırındaki "5 B)" cevap sanılmaz).
CEVAP_CIFTI = re.compile(
    r"(?<!\d)(\d{1,3})\s*[).\-–—:]?\s*([A-Ea-e])(?![A-Za-zÇĞİÖŞÜçğıöşü0-9.)])")
GORUNTU_UZANTILARI = {
    ".png", ".jpg", ".jpeg", ".tif", ".tiff", ".bmp", ".webp", ".gif"
}
DOCX_UZANTILARI = {".docx"}
GIRDI_UZANTILARI = GORUNTU_UZANTILARI | {".pdf"} | DOCX_UZANTILARI
COK_KARELI_UZANTILAR = {".tif", ".tiff", ".webp", ".gif"}
BEYAZ_ESIK = 250          # numpy olmayan güvenli traşlama yedeği
KENAR_PAYI_PX = 16        # traşlama sonrası eklenen beyaz çerçeve
ZINCIR_TOLERANS = 2       # zincirde kaç numara atlanmasına izin verilir
OCR_RENDER_DPI = 200      # taranmış/metinsiz PDF'in OCR+düzen render DPI'si;
                          # çıktı kırpması kullanıcının dpi değerinde yapılır
OCR_CACHE_SURUM = 4       # V4: çok-motor hakem imzası anahtara girdi (V3:
                          # güven, alternatifler, numara-önek kutusu)
OCR_CACHE_AKTIF = True    # --ocr-cache-kapat ile kapatılır
OCR_CACHE_DIZIN = os.path.join(veri_yollari.onbellek_koku(), "ocr")
OCR_PARALEL = min(4, os.cpu_count() or 1)  # --ocr-paralel ile değişir (1=seri)
OCR_GIRDI_MAKS = 2200     # görüntü DOSYASI girdilerinde OCR'a giden en uzun
                          # kenar (Vision doğruluğu ~200 DPI'da doyar; kırpma
                          # tam çözünürlükten yapılır). PDF render'ları muaf.

# V3 kalibrasyon/kalite sözleşmesi. Eşikler hem çekirdekte hem web inceleme
# kuyruğunda tek kaynaktan okunur. Algoritma davranışı değiştiğinde sürümü
# artırmak profil ve tespit önbelleklerini kendiliğinden geçersiz kılar.
KALIBRASYON_SURUMU = "3.4"
GUVEN_OTOMATIK = 0.82
GUVEN_INCELE = 0.55
DUZEN_UYUSMAZLIK_RISK_ESIGI = 0.70
KALITE_MODLARI = ("strict", "balanced", "legacy")
VARSAYILAN_KALITE = "strict"
PROFIL_ORNEK_MAKS = 48
PROFIL_CACHE_DIZIN = os.path.join(veri_yollari.onbellek_koku(), "profil-v3")


# ---------------------------------------------------------------- yardımcılar

def _icerik_kutusu(img):
    """Beyaz zemindeki gerçek içeriği, soluk çizgileri kesmeden bulur.

    Sabit ``240`` eşiği açık gri geometriyi yok ediyordu. V3, kenar
    piksellerinden sayfanın gerçek zemin rengini ve JPEG/tarama gürültüsünü
    ölçer. Gürültü tabanının hemen üstündeki renk/parlaklık farkını
    içerik sayar. Belirsizlikte daha geniş kutu döndürmek bilinçli bir
    tercihtir: biraz beyaz alan, kesilmiş şekilden daha güvenlidir.
    """
    if _np is None:
        gri = img.convert("L")
        return gri.point(lambda p: 0 if p >= BEYAZ_ESIK else 255).getbbox()
    rgb = _np.asarray(img.convert("RGB"), dtype=_np.int16)
    if rgb.size == 0:
        return None
    h, w = rgb.shape[:2]
    pay = max(1, min(12, h // 40, w // 40))
    kenarlar = _np.concatenate((rgb[:pay].reshape(-1, 3),
                                rgb[-pay:].reshape(-1, 3),
                                rgb[:, :pay].reshape(-1, 3),
                                rgb[:, -pay:].reshape(-1, 3)))
    zemin = _np.median(kenarlar, axis=0)
    fark = _np.max(_np.abs(rgb - zemin), axis=2)
    kenar_fark = _np.max(_np.abs(kenarlar - zemin), axis=1)
    # JPEG lekesini bastır, fakat 248–252 seviyesindeki soluk çizgiyi koru.
    esik = float(min(18.0, max(3.0, _np.percentile(kenar_fark, 97) + 2.0)))
    maske = fark > esik
    ys, xs = _np.nonzero(maske)
    if not len(xs):
        return None
    # Bir piksellik kenar payı, anti-alias uçlarının traşlanmasını önler.
    return (max(0, int(xs.min()) - 1), max(0, int(ys.min()) - 1),
            min(w, int(xs.max()) + 2), min(h, int(ys.max()) + 2))


def trasla(img, kenar=KENAR_PAYI_PX):
    """Beyaz kenar boşluklarını kırpar, eşit beyaz pay ekler."""
    kutu = _icerik_kutusu(img)
    if kutu:
        img = img.crop(kutu)
    return ImageOps.expand(img, border=kenar, fill="white") if kenar else img


def _trasla_ofset(img, kenar=KENAR_PAYI_PX):
    """trasla + piksel ofseti: orijinal kırpmadaki (X, Y) noktası çıktı
    görüntüsünde (X + ox, Y + oy) konumuna düşer. Yeniden numaralama,
    eski numara bölgesini çıktı pikselinde bulabilsin diye."""
    kutu = _icerik_kutusu(img)
    if kutu:
        img = img.crop(kutu)
        ox, oy = -kutu[0], -kutu[1]
    else:
        ox = oy = 0
    if kenar:
        img = ImageOps.expand(img, border=kenar, fill="white")
        ox, oy = ox + kenar, oy + kenar
    return img, (ox, oy)


def _zincir_segmentli(ham, basliklar, bant_bul, Y, tum_pos=None):
    """Sayfa adaylarını test sınırlarında segmentlere bölüp her segmentte
    en_uzun_zincir çalıştırır; kabul edilen ham-indekslerini döndürür.

    en_uzun_zincir sayfa başına TEK artan zincir seçtiğinden, sayfa ortasında
    yeni test başlarsa (TEST 5'in sonu 8,9,10 + TEST 6'nın başı 1,2,3 aynı
    sayfada) kısa dizinin soruları düşerdi. Sınır kanıtı:
    (a) iki aday arasında TEST başlığı (okuma sırasında), VEYA
    (b) muhafazakâr numara-sıfırlanması: yeni≤2, öncekinden küçük, önceki≥5,
        o ana dek segment ≥3 aday VE (bant değişimi YA DA ≥Y·0.06 dikey
        boşluk). Boşluk koşulu, soru içindeki numaralı ÖNCÜL listesinin
        ("1. madde, 2. madde…" — sıkışık satırlar) sahte sınır üretmesini
        engeller; gerçek test başlangıcında başlık/boşluk zaten vardır.
    Dönüş: ham-indeks listesi | None (sayfada sınır adayı yok). Nihai karar
    çağıranda: iki zincir NİHAİ geçerli kutu sayısıyla yarıştırılır, segmentli
    yalnız daha çok kutu üretirse kullanılır (regresyon güvencesi)."""
    if len(ham) < 2:
        return None
    hpos = sorted((bant_bul(k[0]), k[1]) for _, k, _ in basliklar)
    # Boşluk, FİLTRE ÖNCESİ en yakın üst ham komşuya göre ölçülür: öncül
    # listesinin ilk maddeleri ön-filtrede elense bile sıkışık-satır bağlamı
    # görünür kalır (Palme s26: '1.' elendi, '2.' 14pt üstündeki '1.'e bakar).
    bant_ys = {}
    for sb, y in (tum_pos or [(a[1], a[2][1]) for a in ham]):
        bant_ys.setdefault(sb, []).append(y)
    for v in bant_ys.values():
        v.sort()

    def _bosluk_yeterli(i):
        if ham[i][1] != ham[i - 1][1]:
            return True                     # bant değişimi
        y1 = ham[i][2][1]
        ustler = [y for y in bant_ys.get(ham[i][1], []) if y < y1 - 0.5]
        return not ustler or y1 - ustler[-1] >= Y * 0.06

    sinirlar = []
    seg_bas = 0
    for i in range(1, len(ham)):
        p0 = (ham[i - 1][1], ham[i - 1][2][1])
        p1 = (ham[i][1], ham[i][2][1])
        n0, n1 = ham[i - 1][0], ham[i][0]
        baslik_var = any(p0 < h <= p1 for h in hpos)
        restart = (n1 <= 2 and n1 < n0 and n0 >= 5 and i - seg_bas >= 3
                   and _bosluk_yeterli(i))
        if baslik_var or restart:
            sinirlar.append(i)
            seg_bas = i
    if not sinirlar:
        return None
    parcali = []
    bas = 0
    for son in sinirlar + [len(ham)]:
        alt = en_uzun_zincir([a[0] for a in ham[bas:son]])
        parcali.extend(bas + j for j in alt)
        bas = son
    return parcali


def en_uzun_zincir(numaralar):
    """Okuma sırasındaki numaralardan en uzun 'artan' alt-diziyi (indeksler)
    döndürür. Başlık/sayfa-no gibi tek-tük aykırı numaraları ve romen
    rakamı karışmalarını eler; farklı başlangıç numaralarını (ör. bir test
    7'den başlıyorsa) kabul eder. Her adım kesin artan olmalı, atlama
    ZINCIR_TOLERANS ile sınırlıdır."""
    n = len(numaralar)
    if n == 0:
        return []
    dp = [1] * n
    onceki = [-1] * n
    for i in range(n):
        for j in range(i):
            fark = numaralar[i] - numaralar[j]
            if 0 < fark <= (i - j) + ZINCIR_TOLERANS and dp[j] + 1 > dp[i]:
                dp[i] = dp[j] + 1
                onceki[i] = j
    son = max(range(n), key=lambda k: dp[k])
    zincir = []
    while son != -1:
        zincir.append(son)
        son = onceki[son]
    return zincir[::-1]


def _satir_oncelikli_sirala(ham, yukseklik):
    """Numara adaylarını yaklaşık yatay satırlara gruplayıp soldan sağa sırala.

    Bazı iki sütunlu çalışma kâğıtları sütun-sütun değil, satır-satır
    numaralanır (üstte ``1 | 2``, altta ``3 | 4``). Ana algoritmanın
    sütun-öncelikli sırası bu düzenlerde 1,3,2,4 üretir. Bu yardımcı, hafif
    tarama eğimini ve farklı yazı kutusu yüksekliklerini tolere eden ikinci
    bir okuma sırası üretir; çağıran iki sırayı nihai geçerli kutu sayısıyla
    yarıştırdığı için klasik sütun düzenini değiştirmez.
    """
    if len(ham) < 2:
        return list(ham)
    kutu_yukseklikleri = sorted(max(1.0, a[2][3] - a[2][1]) for a in ham)
    medyan_yuk = kutu_yukseklikleri[len(kutu_yukseklikleri) // 2]
    tolerans = max(yukseklik * 0.012, medyan_yuk * 1.5)
    sirali = sorted(ham, key=lambda a: (a[2][1], a[1], a[2][0]))
    satirlar = []
    for aday in sirali:
        merkez_y = (aday[2][1] + aday[2][3]) / 2
        if not satirlar or abs(merkez_y - satirlar[-1][0]) > tolerans:
            satirlar.append([merkez_y, [aday]])
        else:
            eski_y, uyeler = satirlar[-1]
            uyeler.append(aday)
            satirlar[-1][0] = (eski_y * (len(uyeler) - 1) + merkez_y) / len(uyeler)
    cikti = []
    for _, uyeler in satirlar:
        cikti.extend(sorted(uyeler, key=lambda a: (a[1], a[2][0], a[2][1])))
    return cikti


# ------------------------------------------------------------ Vision OCR
# OCR sonuçları (yol, sayfa, dpi) başına diske önbelleklenir: aynı belge
# tekrar açıldığında (önizle→kes, tekrar çalıştırma) dakikalar süren OCR
# atlanır. Önbellek OCR çıktısının BİREBİR kopyasıdır → sıcak çalıştırma
# soğukla bit-özdeş sonuç verir.


def _ocr_kimlik(yol, sayfa_no, dpi):
    """Önbellek anahtarı: dosya içeriği (boyut+mtime) veya OCR'ı etkileyen
    herhangi bir ayar değişince anahtar da değişir."""
    try:
        st = os.stat(yol)
    except OSError:
        return None
    # OCR modu + hakem motor imzası da anahtara girer: farklı jüri farklı
    # sonuç üretebilir. Hızlı modda imza boş → anahtar sabit (bit-özdeş).
    try:
        import ocr_ensemble
        hakem = f"{ocr_ensemble.mod_al()}|{ocr_ensemble.motor_imzasi()}|" \
                f"h{ocr_ensemble.HAKEM_SURUM}"
    except Exception:  # noqa: BLE001
        hakem = "hizli||h0"
    ham = (f"{os.path.abspath(yol)}|{st.st_size}|{st.st_mtime_ns}|{sayfa_no}|"
           f"{dpi}|{OCR_CACHE_SURUM}|tr-TR,en-US|accurate|{hakem}")
    return hashlib.sha1(ham.encode("utf-8")).hexdigest()


_KAYNAK_KIMLIK_ONBELLEK = {}


def _kaynak_dosya_kimligi(yol):
    """Model önbelleği için yol-bağımsız dosya içerik kimliği üret.

    PDF metin sayfalarının eski model anahtarı yalnız sayfa numarası, boyut ve
    render çözünürlüğünden oluşuyordu. Aynı ölçüdeki iki farklı PDF böylece
    birbirinin soru-modeli bölgelerini okuyabiliyordu. İçerik SHA-256'sı bu
    çapraz-belge sızıntısını engeller; stat anahtarlı küçük süreç önbelleği aynı
    dosyanın yükleme sırasında ikinci kez okunmasını önler.
    """
    try:
        tam = os.path.abspath(yol)
        st = os.stat(tam)
        anahtar = (tam, st.st_ino, st.st_size, st.st_mtime_ns,
                   getattr(st, "st_ctime_ns", 0))
        if anahtar in _KAYNAK_KIMLIK_ONBELLEK:
            return _KAYNAK_KIMLIK_ONBELLEK[anahtar]
        h = hashlib.sha256()
        with open(tam, "rb") as f:
            while True:
                parca = f.read(1024 * 1024)
                if not parca:
                    break
                h.update(parca)
        sonuc = h.hexdigest()
        if len(_KAYNAK_KIMLIK_ONBELLEK) >= 16:
            _KAYNAK_KIMLIK_ONBELLEK.clear()
        _KAYNAK_KIMLIK_ONBELLEK[anahtar] = sonuc
        return sonuc
    except OSError:
        return hashlib.sha256(
            os.path.abspath(str(yol)).encode("utf-8", "replace")).hexdigest()


def _kaynak_ornek_kimligi(yol):
    """Aynı baytlara sahip farklı girdi örneklerini ayıran opak kimlik.

    İçerik kimliği model önbelleğini güvenle paylaşabilir; kullanıcı kararları
    ise dosya örneğine aittir. Mutlak yolu doğrudan karar anahtarına taşımak
    yerine özetleyerek aynı içerikle yüklenen farklı adlı/konumlu belgelerin
    onaylarının birbirine yapışmasını önleriz.
    """
    tam = os.path.abspath(str(yol))
    return hashlib.sha256(tam.encode("utf-8", "replace")).hexdigest()[:24]


def _ocr_cache_oku(kimlik):
    if not (OCR_CACHE_AKTIF and kimlik):
        return None
    try:
        with open(os.path.join(OCR_CACHE_DIZIN, kimlik + ".json"),
                  encoding="utf-8") as f:
            veri = json.load(f)
        # V3 yapılandırılmış satırlar; eski iki-elemanlı kayıtları
        # da okuyabilmek geliştirici/haricî çağrı uyumluluğunu korur.
        if veri and isinstance(veri[0], dict):
            return veri
        return [{"metin": m, "kutu": list(k), "guven": 1.0,
                 "adaylar": [[m, 1.0]], "numara_on_eki_kutu": None,
                 "kaynak": "eski_cache"} for m, k in veri]
    except (OSError, ValueError):
        return None


def _ocr_cache_yaz(kimlik, satirlar):
    if not (OCR_CACHE_AKTIF and kimlik):
        return
    try:
        os.makedirs(OCR_CACHE_DIZIN, exist_ok=True)
        fd, gecici = tempfile.mkstemp(dir=OCR_CACHE_DIZIN, suffix=".tmp")
        veri = []
        for satir in satirlar:
            if isinstance(satir, OCRSatiri):
                veri.append(satir.to_dict())
            elif isinstance(satir, dict):
                veri.append(satir)
            else:
                m, k = satir[:2]
                veri.append({"metin": m, "kutu": list(k), "guven": 1.0,
                             "adaylar": [[m, 1.0]],
                             "numara_on_eki_kutu": None,
                             "kaynak": "legacy"})
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(veri, f, ensure_ascii=False)
        os.replace(gecici, os.path.join(OCR_CACHE_DIZIN, kimlik + ".json"))
    except OSError:  # önbellek yazılamazsa sessizce OCR'suz devam
        pass


# OCR motorları Türkçe diakritikleri sistematik ayrıştırır (OCRTurk,
# arXiv 2602.03693): "DOĞAL"→"DO˘GAL", "BEŞERİ"→"BE¸SERİ", "İ"→"Ì".
# Tablolar YALNIZ meşru metinde geçmeyen işaretleri hedefler; ı/i gibi
# gerçek tanıma belirsizliklerine dokunulmaz.
# Her grup: (işaretler [spacing + combining], {taban harf: birleşik harf}).
_AKSAN_GRUPLARI = [                              # spacing + combining
    ("\u02D8\u0306", {"G": "Ğ", "g": "ğ"}),                      # breve
    ("\u00B8\u0327", {"C": "Ç", "c": "ç", "S": "Ş", "s": "ş"}),  # çengel
    ("\u02D9\u0307", {"I": "İ", "i": "i"}),                      # üst nokta
    ("\u00A8\u0308", {"O": "Ö", "o": "ö", "U": "Ü", "u": "ü"}),  # trema
]

# NFC'nin öncül harfe yapıştırdığı artıklar: "DO"+◌̆+"GAL" NFC'de "DŎGAL"
# olur, birleşen im kaybolur → ancak bileşik-artık deseniyle yakalanır.
# Ă/Ĕ/Ĭ/Ŏ/Ŭ ve Ȩ meşru Türkçe'de yoktur; kural yalnız ardından Türkçe
# digraf tabanı (G/g, S/s, C/c) gelince tetiklenir — çifte muhafazakâr.
_AKSAN_KACAK = [
    (re.compile("([ĂăĔĕĬĭŎŏŬŭ])([Gg])"),
     lambda e: unicodedata.normalize("NFD", e.group(1))[0]
     + ("Ğ" if e.group(2) == "G" else "ğ")),
    (re.compile("([Ȩȩ])([SsCc])"),
     lambda e: unicodedata.normalize("NFD", e.group(1))[0]
     + {"S": "Ş", "s": "ş", "C": "Ç", "c": "ç"}[e.group(2)]),
]

_ONARIM_HARF = "A-Za-zÇĞİÖŞÜçğıöşü"
_AKSAN_ONDE = []   # işaret taban harften ÖNCE (araya tek boşluk olabilir)
_AKSAN_ARA = []    # sözcük içi "harf + boşluk + işaret": boşluk da yutulur
for _isr, _tab in _AKSAN_GRUPLARI:
    _tsinif = "".join(_tab)
    _AKSAN_ONDE.append(
        (re.compile("[" + _isr + "]\\s?([" + _tsinif + "])"), _tab))
    _AKSAN_ARA.append(
        (re.compile("([" + _ONARIM_HARF + "]) [" + _isr + "]\\s?"
                    "([" + _tsinif + "])"), _tab))
del _isr, _tab, _tsinif

# Ì Türkçe'de yoktur; OCR'ın İ yanlış okumasıdır. Yalnız sözcük bağlamında
# (≥2 harf, q/w/x içermeyen) düzeltilir → yabancı jetonlar korunur.
_I_TERS_SOZCUK = re.compile(r"[^\W\d_]*\u00CC[^\W\d_]*")


def _ocr_tr_duzelt(metin):
    """OCR sonrası Türkçe onarım: ayrık/başıboş diakritikleri birleşik harfe
    çevirir (˘G→Ğ, ¸S→Ş, ˙I→İ, ¨O→Ö…) ve Ì→İ (yalnız sözcük bağlamında).

    Muhafazakâr: yalnız meşru metinde bulunmayan işaretler tetikler; ı/i,
    I/l gibi gerçek tanıma belirsizliklerine ve noktalamaya DOKUNMAZ
    (bunları ocr_kiyas.py ölçer, bu katman onarmaz). İdempotenttir.
    _tr_normalize ile karıştırma: o kayıplı arama katlamasıdır, bu kayıpsız
    onarımdır."""
    metin = unicodedata.normalize("NFC", metin)
    for desen, cevir in _AKSAN_KACAK:
        metin = desen.sub(cevir, metin)
    for desen, tab in _AKSAN_ARA:
        metin = desen.sub(lambda e, t=tab: e.group(1) + t[e.group(2)], metin)
    for desen, tab in _AKSAN_ONDE:
        metin = desen.sub(lambda e, t=tab: t[e.group(1)], metin)
    if "\u00CC" in metin:
        def _i_onar(e):
            s = e.group(0)
            if len(s) < 2 or any(k in s for k in "QqWwXx"):
                return s
            return s.replace("\u00CC", "İ")
        metin = _I_TERS_SOZCUK.sub(_i_onar, metin)
    return unicodedata.normalize("NFC", metin)


_PYOBJC_VISION_DURUM = None  # None=denenmedi, True=çalışıyor, False=yedeğe geç


@dataclass(frozen=True)
class OCRSatiri:
    """V3 OCR iç modeli; kesim sınırı değil, çapa kanıtı taşır."""
    metin: str
    kutu: tuple
    guven: float = 1.0
    adaylar: tuple = field(default_factory=tuple)
    numara_on_eki_kutu: object = None
    kaynak: str = "vision"
    yazi_boyutu: object = None
    kalin: object = None

    def to_dict(self):
        return {
            "metin": self.metin, "kutu": list(self.kutu),
            "guven": round(float(self.guven), 6),
            "adaylar": [[str(m), round(float(g), 6)]
                         for m, g in self.adaylar],
            "numara_on_eki_kutu": (list(self.numara_on_eki_kutu)
                                     if self.numara_on_eki_kutu else None),
            "kaynak": self.kaynak, "yazi_boyutu": self.yazi_boyutu,
            "kalin": self.kalin,
        }


def _numara_on_eki_kutusu(metin, kutu):
    """Vision alt-aralık kutusu yoksa numara önek bbox'ını yaklaştır.

    Bu kutu yalnız çapa hizası/ML birleştirme sinyalidir; kırpma sınırı
    olarak kullanılmaz. Karakter oranına eklenen tolerans nokta ve boşluğu
    tamamen kapsar.
    """
    es = SORU_NO_DESENI.match(metin)
    if not es or not metin:
        return None
    x0, y0, x1, y1 = kutu
    oran = min(1.0, max(0.08, (es.end() + 0.75) / max(1, len(metin))))
    return (x0, y0, min(x1, x0 + (x1 - x0) * oran), y1)


def _ocr_satiri_dictten(sonuc, G, Y, duzelt=True, kaynak="vision"):
    metin = str(sonuc.get("metin", "")).strip()
    if duzelt:
        metin = _ocr_tr_duzelt(metin)
    if not metin:
        return None
    bb = sonuc["kutu"]
    # Motor çıktısı normalize; cache/yerel birleştirme piksel uzayında.
    if max(abs(float(v)) for v in bb) <= 1.01:
        kutu = (float(bb[0]) * G, float(bb[1]) * Y,
                float(bb[2]) * G, float(bb[3]) * Y)
    else:
        kutu = tuple(float(v) for v in bb)
    adaylar = []
    for aday in sonuc.get("adaylar") or []:
        try:
            if isinstance(aday, dict):
                am, ag = aday.get("metin", ""), aday.get("guven", 0)
            else:
                am, ag = aday[0], aday[1]
            adaylar.append((_ocr_tr_duzelt(str(am)) if duzelt else str(am),
                            max(0.0, min(1.0, float(ag)))))
        except (TypeError, ValueError, IndexError):
            continue
    guven = max(0.0, min(1.0, float(sonuc.get("guven", 1.0))))
    if not adaylar:
        adaylar = [(metin, guven)]
    onek = sonuc.get("numara_on_eki_kutu")
    if onek and max(abs(float(v)) for v in onek) <= 1.01:
        onek = (float(onek[0]) * G, float(onek[1]) * Y,
                float(onek[2]) * G, float(onek[3]) * Y)
    elif onek:
        onek = tuple(float(v) for v in onek)
    else:
        onek = _numara_on_eki_kutusu(metin, kutu)
    return OCRSatiri(metin, kutu, guven, tuple(adaylar), onek,
                     str(sonuc.get("kaynak") or kaynak))


def vision_satirlar(pil_img, maks_kenar=None, duzelt=True, *, metali=False,
                    dil_duzeltme=True):
    """macOS Vision OCR satırlarını döndürür.

    Varsayılan dönüş eski ``(metin, kutu)`` sözleşmesidir. ``metali``
    açılırsa güven, en iyi üç aday ve kesin/yaklaşık numara-önek
    kutusunu taşıyan :class:`OCRSatiri` listesi döner.

    maks_kenar: verilirse ve görüntü daha büyükse OCR'a küçültülmüş kopya
    gider (hız); Vision kutuları normalize döndürdüğünden koordinatlar yine
    ORİJİNAL piksel uzayında hesaplanır — kırpma kalitesi etkilenmez.

    duzelt=False yalnız ocr_kiyas.py içindir (ham motor çıktısı ölçümü);
    üretim yolları düzeltilmiş metni kullanır."""
    ocr_img = pil_img
    if maks_kenar and max(pil_img.size) > maks_kenar:
        oran = maks_kenar / max(pil_img.size)
        ocr_img = pil_img.resize((max(1, round(pil_img.width * oran)),
                                  max(1, round(pil_img.height * oran))))
    bio = io.BytesIO()
    # compress_level=1: kayıpsız ama ~5× hızlı kodlama (Vision'a giden
    # pikseller özdeş → OCR sonucu değişmez)
    ocr_img.save(bio, "PNG", compress_level=1)
    ham = bio.getvalue()
    global _PYOBJC_VISION_DURUM
    sonuclar = None
    pyobjc_hata = None
    if _PYOBJC_VISION_DURUM is not False:
        try:
            import Vision
            from Foundation import NSData
            data = NSData.dataWithBytes_length_(ham, len(ham))
            handler = Vision.VNImageRequestHandler.alloc().initWithData_options_(
                data, None)
            istek = Vision.VNRecognizeTextRequest.alloc().init()
            istek.setRecognitionLevel_(Vision.VNRequestTextRecognitionLevelAccurate)
            istek.setRecognitionLanguages_(["tr-TR", "en-US"])
            istek.setUsesLanguageCorrection_(bool(dil_duzeltme))
            ok, hata = handler.performRequests_error_([istek], None)
            if ok:
                _PYOBJC_VISION_DURUM = True
                sonuclar = []
                for gozlem in istek.results() or []:
                    adaylar = gozlem.topCandidates_(3)
                    if not adaylar:
                        continue
                    bb = gozlem.boundingBox()
                    aday_json = []
                    for aday in adaylar:
                        try:
                            conf = float(aday.confidence())
                        except TypeError:
                            conf = float(aday.confidence)
                        aday_json.append({"metin": str(aday.string()),
                                          "guven": conf})
                    sonuclar.append({
                        "metin": str(adaylar[0].string()),
                        "guven": aday_json[0]["guven"],
                        "adaylar": aday_json,
                        "kutu": [bb.origin.x,
                                  1 - bb.origin.y - bb.size.height,
                                  bb.origin.x + bb.size.width,
                                  1 - bb.origin.y],
                    })
            else:
                _PYOBJC_VISION_DURUM = False
                pyobjc_hata = f"Vision performRequests false döndü: {hata}"
        except Exception as exc:  # PyObjC yok/uyumsuz → yerel Swift köprüsü
            _PYOBJC_VISION_DURUM = False
            pyobjc_hata = str(exc)

    if sonuclar is None:
        try:
            sonuclar = _vision_swift_calistir(ham, dil_duzeltme=dil_duzeltme)
        except Exception as exc:
            ayrinti = f"; PyObjC: {pyobjc_hata}" if pyobjc_hata else ""
            raise RuntimeError(f"Vision OCR çalıştırılamadı: {exc}{ayrinti}")

    G, Y = pil_img.size
    satirlar = [_ocr_satiri_dictten(s, G, Y, duzelt)
                for s in sonuclar]
    satirlar = [s for s in satirlar if s is not None]
    return satirlar if metali else [(s.metin, s.kutu) for s in satirlar]


def easyocr_satirlar(pil_img, duzelt=True):
    """Windows yedek OCR yolu (Apple Vision yok): easyocr → vision_satirlar
    ile aynı ``OCRSatiri`` listesi sözleşmesi (metali=True karşılığı).

    ocr_ensemble.motor_satirlar zaten PİKSEL uzayında ``[(metin, kutu_px),
    ...]`` döner (ocr_kiyas sözleşmesi); _ocr_satiri_dictten de aynı
    dönüşümü RasterSayfa.satirlar()'ın önbellek-okuma dalında kullanır —
    burada da o yol izlenir, iki ayrı koordinat yorumlayıcısı olmasın diye.

    .venv-ml/ocr işçisi kurulu değilse VEYA işçi ayaktayken easyocr motoru
    fiilen yüklenemediyse RuntimeError fırlatır; çağıran bunu
    vision_satirlar'ın Vision-yok hatasıyla AYNI şekilde yakalayıp sayfayı
    ocr_hata ile boş bırakır (zarif düşüş, regresyon nötr). Bilerek yalnız
    dosya varlığına bakmakla YETİNMEZ: motor_satirlar, işçi çökse/motor
    yüklenemese bile sessizce [] döner (bkz. ocr_ensemble._istek) — bu da
    gerçek bir OCR arızasını "sayfada metin yok" sonucuyla ayırt edilemez
    kılıp boş sonucu cache'e yazdırırdı. El sıkışma (_probe_al) ile motorun
    fiilen aktif olduğu doğrulanır."""
    import ocr_ensemble
    if not (os.path.exists(ocr_ensemble.ISCI_PY)
            and os.path.exists(ocr_ensemble.ISCI_BETIK)):
        raise RuntimeError(
            "easyocr işçisi kurulu değil — .venv-ml/bin/python ocr_kur.py")
    probe = ocr_ensemble._probe_al()
    if not (isinstance(probe, dict) and probe.get("motorlar", {}).get("easyocr")):
        raise RuntimeError(
            "easyocr motoru işçide yüklenemedi — kurulumu doğrulayın "
            "(.venv-ml/bin/python ocr_kur.py)")
    G, Y = pil_img.size
    varsayilan_guven = ocr_ensemble.MOTOR_AGIRLIK.get("easyocr", 0.75)
    satirlar = []
    for metin, kutu in ocr_ensemble.motor_satirlar(pil_img, "easyocr"):
        sonuc = {"metin": metin, "kutu": list(kutu),
                 "guven": varsayilan_guven, "kaynak": "easyocr"}
        satir = _ocr_satiri_dictten(sonuc, G, Y, duzelt, kaynak="easyocr")
        if satir is not None:
            satirlar.append(satir)
    return satirlar


_SWIFT_OCR_KILIT = threading.Lock()


def _vision_swift_binary():
    """Swift Vision yardımcısını kaynak hash'iyle bir kez derleyip döndürür."""
    kaynak = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                          "vision_ocr.swift")
    if not os.path.isfile(kaynak):
        raise RuntimeError("vision_ocr.swift bulunamadı")
    with open(kaynak, "rb") as f:
        ozet = hashlib.sha256(f.read()).hexdigest()[:12]
    kok = os.environ.get("SORU_KESICI_RUNTIME_CACHE") or os.path.join(
        tempfile.gettempdir(), "soru-kesici-runtime")
    os.makedirs(kok, exist_ok=True)
    hedef = os.path.join(kok, f"vision-ocr-{ozet}")
    if os.path.isfile(hedef) and os.access(hedef, os.X_OK):
        return hedef
    with _SWIFT_OCR_KILIT:
        if os.path.isfile(hedef) and os.access(hedef, os.X_OK):
            return hedef
        gecici = hedef + f".{os.getpid()}.tmp"
        modul = os.path.join(kok, "swift-module-cache")
        os.makedirs(modul, exist_ok=True)
        komut = ["xcrun", "swiftc", "-parse-as-library", "-O",
                 "-module-cache-path", modul]
        # Bazı macOS 26 Command Line Tools kurulumlarında varsayılan 26.x SDK
        # ile swiftc yama sürümü uyuşmuyor. Birlikte gelen 15.4 SDK yeni Vision
        # API'sini içerir ve macOS 15+ hedefiyle kararlı derlenir.
        sdk15 = ("/Library/Developer/CommandLineTools/SDKs/"
                 "MacOSX15.4.sdk")
        if os.path.isdir(sdk15):
            komut += ["-sdk", sdk15, "-target",
                      f"{platform.machine()}-apple-macos15.0"]
        komut += [kaynak, "-o", gecici]
        ortam = dict(os.environ)
        ortam["CLANG_MODULE_CACHE_PATH"] = modul
        sonuc = subprocess.run(komut, capture_output=True, text=True,
                               encoding="utf-8", timeout=120, env=ortam)
        if sonuc.returncode != 0:
            try:
                os.unlink(gecici)
            except OSError:
                pass
            raise RuntimeError((sonuc.stderr or sonuc.stdout or
                                "Swift derlemesi başarısız").strip())
        os.replace(gecici, hedef)
        os.chmod(hedef, 0o700)
    return hedef


def _vision_swift_calistir(png_veri, dil_duzeltme=True):
    """PNG baytını yerel Swift/Vision yardımcısıyla OCR'lar."""
    fd, yol = tempfile.mkstemp(prefix="soru_ocr_", suffix=".png")
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(png_veri)
        sonuc = subprocess.run([_vision_swift_binary(), yol,
                                "1" if dil_duzeltme else "0"],
                               capture_output=True, timeout=180)
        if sonuc.returncode != 0:
            hata = sonuc.stderr.decode("utf-8", "replace").strip()
            raise RuntimeError(hata or "Swift Vision OCR başarısız")
        return json.loads(sonuc.stdout.decode("utf-8"))
    finally:
        try:
            os.unlink(yol)
        except OSError:
            pass


# --------------------------------------------------------- Sayfa soyutlaması
# Her Sayfa; kaynağını (metinli PDF / taranmış PDF / görüntü) gizleyerek
# ortak bir arayüz sunar: satirlar(), resim_kutulari(), kirp(), gorsel().

class PdfSayfa:
    """Metin katmanı olan PDF sayfası. Koordinatlar vektörden okunur,
    kırpma yüksek çözünürlükte yeniden render edilir (en yüksek kalite)."""

    raster = False
    belge_no = 0     # kaçıncı girdi dosyasından (belge_sayfalari atar)

    def __init__(self, page, dpi, kimlik=None):
        self.page = page
        self.dpi = dpi
        self.kimlik = kimlik
        self.genislik = page.rect.width
        self.yukseklik = page.rect.height
        self._satir_kesa = None   # satirlar() örnek-içi önbelleği

    def satirlar(self):
        if self._satir_kesa is not None:
            return self._satir_kesa
        cikti = []
        for blok in self.page.get_text("dict")["blocks"]:
            if blok.get("type") != 0:
                continue
            for satir in blok["lines"]:
                dx, _ = satir["dir"]
                if abs(dx) < 0.9:  # dikey/eğik (ayraç yazısı) → ele
                    continue
                metin = "".join(s["text"] for s in satir["spans"]).strip()
                if not metin:
                    continue
                ilk = satir["spans"][0]
                kalin = bool(ilk["flags"] & 16) or "Bold" in ilk.get("font", "")
                cikti.append((metin, tuple(satir["bbox"]), kalin))
        self._satir_kesa = cikti
        return cikti

    def resim_kutulari(self):
        kutular = []
        for gorsel in self.page.get_images(full=True):
            for r in self.page.get_image_rects(gorsel):
                kutular.append((r.x0, r.y0, r.x1, r.y1))
        return kutular

    def kirp(self, kutu):
        olcek = self.dpi / 72
        clip = fitz.Rect(*kutu) & self.page.rect
        pix = self.page.get_pixmap(matrix=fitz.Matrix(olcek, olcek),
                                   clip=clip, alpha=False)
        return Image.frombytes("RGB", (pix.width, pix.height), pix.samples)

    def gorsel(self):
        olcek = self.dpi / 72
        pix = self.page.get_pixmap(matrix=fitz.Matrix(olcek, olcek), alpha=False)
        return Image.frombytes("RGB", (pix.width, pix.height), pix.samples), olcek


# Taranmış sayfa görüntüleri artık TALEP-ÜZERİNE render edilir ve bir LRU ile
# bellekte tutulur; böylece 300 sayfalık taranmış PDF ~6 GB yerine ~onlarca MB
# kullanır. LRU eşzamanlı OCR (toplu_ocr) altında kilitlidir.
_RASTER_LRU = []
_RASTER_LRU_MAKS = 3
_RASTER_KILIT = threading.Lock()


def _raster_kayit(sayfa):
    """Sayfayı LRU'ya ekle; sınır aşılırsa en eskinin görüntüsünü serbest bırak.
    Serbest bırakma yalnız _img_cache'i None yapar; kullanan iş parçacığı yerel
    referansı tuttuğu için render sürerken çökme olmaz."""
    with _RASTER_KILIT:
        try:
            _RASTER_LRU.remove(sayfa)
        except ValueError:
            pass
        _RASTER_LRU.append(sayfa)
        while len(_RASTER_LRU) > _RASTER_LRU_MAKS:
            _RASTER_LRU.pop(0)._img_cache = None


def _raster_lru_temizle():
    with _RASTER_KILIT:
        for s in _RASTER_LRU:
            s._img_cache = None
        _RASTER_LRU.clear()


def _raster_rgb_hazirla(img):
    """Raster girdiyi doğru yöne çevirip beyaz zeminli RGB kopya döndürür.

    PNG/WebP/GIF gibi kaynaklarda saydam pikselleri doğrudan RGB'ye çevirmek
    çoğunlukla siyah zemin üretir; bu hem OCR'ı hem dikey projeksiyonu bozar.
    Önce EXIF yönünü uygula, sonra alfa/transparency bilgisini beyaza kompozit
    et. Dönen görüntü kaynaktan ayrık olduğundan ``Image.open`` güvenle kapanır.
    """
    yonlu = ImageOps.exif_transpose(img)
    saydam = "A" in yonlu.getbands() or "transparency" in yonlu.info
    if saydam:
        rgba = yonlu.convert("RGBA")
        zemin = Image.new("RGB", rgba.size, "white")
        zemin.paste(rgba, mask=rgba.getchannel("A"))
        return zemin
    return yonlu.convert("RGB")


def _raster_kare_ac(yol, kare_no=0):
    """Dosyanın seçili karesini yükleyip bağımsız, normalize RGB görüntü aç."""
    with Image.open(yol) as im:
        if kare_no:
            im.seek(kare_no)
        return _raster_rgb_hazirla(im)


def _raster_yonlu_boyut(img):
    """EXIF yönünü hesaba katan boyut; piksel verisini yüklemeden hesaplanır."""
    try:
        yon = img.getexif().get(274)  # Orientation
    except (AttributeError, KeyError, TypeError, ValueError):
        yon = None
    return img.size[::-1] if yon in (5, 6, 7, 8) else img.size


def _ocr_capa_mi(satir):
    if SORU_NO_DESENI.match(satir.metin):
        return True
    return any(SORU_NO_DESENI.match(m) for m, _ in satir.adaylar)


def _ocr_capa_ikinci_gecis(img, satirlar):
    """Yalnız riskli numara şeritlerini daha yüksek çözünürlükte okur.

    Tam sayfa metin geçişi dil düzeltmeli; sayısal çapa geçişi dil
    düzeltmesizdir. İkinci geçiş adayı ancak gerçek numara öneki olarak
    okunursa birleştirilir; dolayısıyla normal metni yeniden yazmaz ve kesim
    sınırına tek başına karar vermez.

    Yalnız macOS: kırpılan bölgeyi yeniden okumak için doğrudan
    vision_satirlar çağırır (easyocr işçisiyle küçük-kırpım round-trip'i bu
    incelik kazancına değmez). Windows'ta no-op — ana geçiş (easyocr)
    sonucu değişmeden döner.
    """
    if sys.platform != "darwin":
        return satirlar, False
    capalar = [s for s in satirlar if _ocr_capa_mi(s)]
    siklar = {h for s in satirlar for h in _sik_harfleri(s.metin)}
    riskli = [s for s in satirlar
              if s.guven < 0.72 and (any(c.isdigit() for c in s.metin)
                                     or any(any(c.isdigit() for c in a)
                                            for a, _ in s.adaylar))]
    # Kapak/konu sayfalarında gereksiz ağır OCR yok: sıfır çapa ancak
    # A–E kümesi soru sinyali veriyorsa yeniden aranır.
    if not riskli and not (len(capalar) < 2 and len(siklar) >= 3):
        return satirlar, False

    W, H = img.size
    bolgeler = []
    for s in riskli:
        x0, y0, x1, y1 = s.kutu
        padx, pady = W * 0.035, max(12, (y1 - y0) * 2.0)
        bolgeler.append((max(0, x0 - padx), max(0, y0 - pady),
                         min(W, x1 + padx), min(H, y1 + pady)))
    if len(capalar) < 2 and len(siklar) >= 3:
        # 1/2/3 sütun olasılıklarının sol numara şeritleri. Dikey iki
        # parça bellek ve Vision gecikmesini sınırlar.
        for sutun in (1, 2, 3):
            sw = W / sutun
            for si in range(sutun):
                x0, x1 = si * sw, min(W, si * sw + sw * 0.24)
                for yi in range(2):
                    bolgeler.append((x0, yi * H / 2, x1,
                                     (yi + 1) * H / 2))

    # Aynı/neredeyse aynı bölgeyi yeniden OCR'lama.
    tekil = []
    for b in bolgeler:
        if b[2] - b[0] < 8 or b[3] - b[1] < 8:
            continue
        if any(abs(b[0] - q[0]) < 4 and abs(b[1] - q[1]) < 4
               and abs(b[2] - q[2]) < 4 and abs(b[3] - q[3]) < 4
               for q in tekil):
            continue
        tekil.append(b)
    yeni_capalar = []
    for x0, y0, x1, y1 in tekil[:12]:
        kirp = img.crop((round(x0), round(y0), round(x1), round(y1)))
        olcek = min(2.0, 3000 / max(1, max(kirp.size)))
        if olcek > 1.05:
            kirp = kirp.resize((round(kirp.width * olcek),
                                round(kirp.height * olcek)))
        try:
            okunan = vision_satirlar(kirp, metali=True,
                                     dil_duzeltme=False)
        except Exception:  # ana tam sayfa OCR başarılı; retry belgeyi bozmaz
            continue
        for s in okunan:
            if not _ocr_capa_mi(s):
                continue
            k = (x0 + s.kutu[0] / olcek, y0 + s.kutu[1] / olcek,
                 x0 + s.kutu[2] / olcek, y0 + s.kutu[3] / olcek)
            onek = _numara_on_eki_kutusu(s.metin, k)
            yeni_capalar.append(OCRSatiri(
                s.metin, k, s.guven, s.adaylar, onek,
                "vision_capa_ikinci_gecis"))

    birlesik = list(satirlar)
    for yeni in yeni_capalar:
        en_iyi, en_ort = None, 0.0
        for i, eski in enumerate(birlesik):
            ax0, ay0, ax1, ay1 = eski.kutu
            bx0, by0, bx1, by1 = yeni.kutu
            ix, iy = min(ax1, bx1) - max(ax0, bx0), min(ay1, by1) - max(ay0, by0)
            if ix <= 0 or iy <= 0:
                continue
            oran = ix * iy / max(1.0, min((ax1 - ax0) * (ay1 - ay0),
                                          (bx1 - bx0) * (by1 - by0)))
            if oran > en_ort:
                en_iyi, en_ort = i, oran
        if en_iyi is not None and en_ort >= 0.45:
            if yeni.guven > birlesik[en_iyi].guven:
                birlesik[en_iyi] = yeni
        else:
            birlesik.append(yeni)
    birlesik.sort(key=lambda s: (s.kutu[1], s.kutu[0]))
    return birlesik, bool(yeni_capalar)


class RasterSayfa:
    """Taranmış PDF sayfası (talep-üzerine render) ya da JPG/PNG dosyası.
    Koordinatlar Vision OCR'dan gelir. Görüntü dosyaları kaynak pikselden;
    taranmış PDF'ler OCR koordinatı PDF'e geri çevrilip istenen DPI'da doğrudan
    clip-render edilerek kırpılır. Görüntü bellekte KALICI tutulmaz — _img() ile
    üretilip LRU'da tutulur, OCR sonrası bırakılır."""

    raster = True
    belge_no = 0     # kaçıncı girdi dosyasından (belge_sayfalari atar)

    def __init__(self, kimlik=None, ocr_maks_kenar=None, *,
                 page=None, olcek=None, dpi=None, yol=None, kare_no=0,
                 pil_img=None):
        self.kimlik = kimlik  # OCR disk önbelleği anahtarı (yol/sayfa/dpi)
        # OCR girdi sınırı yalnız görüntü DOSYALARI için (PDF render'ları
        # zaten OCR_RENDER_DPI'da, küçültme sonucu değiştirirdi)
        self.ocr_maks_kenar = ocr_maks_kenar
        self._page = page          # taranmış PDF sayfası (fitz) → clip-render
        self._olcek = olcek        # page render ölçeği (OCR_RENDER_DPI/72)
        self.dpi = dpi             # taranmış PDF'nin gerçek çıktı/kırpma DPI'si
        self._yol = yol            # görüntü dosyası yolu (talep-üzerine open)
        self._kare_no = kare_no     # çok kareli TIFF/WebP/GIF içindeki sayfa
        self._img_cache = None
        self._satir_kesa = None
        self._ocr_satir_metalari = None
        self.ocr_ikinci_gecis = False
        self.ocr_hata = None
        self.kirpma_olcegi = 1.0   # layout birimi → çıktı kırpma pikseli
        if page is not None:
            # boyut fitz'in üreteceği pixmap ile birebir (origin-0 sayfada round)
            self.genislik = round(page.rect.width * olcek)
            self.yukseklik = round(page.rect.height * olcek)
            cikti_olcek = (dpi or OCR_RENDER_DPI) / 72
            self.kirpma_olcegi = cikti_olcek / olcek
        elif yol is not None:
            with Image.open(yol) as im:
                if kare_no:
                    im.seek(kare_no)
                self.genislik, self.yukseklik = _raster_yonlu_boyut(im)
        else:                      # doğrudan bellekteki görüntü (yeniden üretilemez)
            self._img_cache = _raster_rgb_hazirla(pil_img)
            self.genislik, self.yukseklik = self._img_cache.size

    def _img(self):
        """Sayfa görüntüsünü döndürür (gerekirse render/open + LRU'ya kaydet)."""
        if self._img_cache is None:
            if self._page is not None:
                m = fitz.Matrix(self._olcek, self._olcek)
                pix = self._page.get_pixmap(matrix=m, alpha=False)
                self._img_cache = Image.frombytes(
                    "RGB", (pix.width, pix.height), pix.samples)
            elif self._yol is not None:
                self._img_cache = _raster_kare_ac(self._yol, self._kare_no)
            _raster_kayit(self)
        return self._img_cache

    def serbest_birak(self):
        # yalnız yeniden üretilebilir kaynaklarda bırak (bellekteki tek görüntü kalır)
        if self._page is not None or self._yol is not None:
            self._img_cache = None

    def satirlar(self):
        if self._satir_kesa is None:
            ham = _ocr_cache_oku(self.kimlik)
            if ham is None:
                img = self._img()
                try:
                    if sys.platform == "darwin":
                        meta = vision_satirlar(
                            img, self.ocr_maks_kenar, metali=True,
                            dil_duzeltme=True)
                    else:   # Windows/Linux: Vision yok → easyocr birincil
                        meta = easyocr_satirlar(img, duzelt=True)
                    meta, ikinci = _ocr_capa_ikinci_gecis(img, meta)
                    self.ocr_ikinci_gecis = ikinci
                    # Çok-motor hakemliği (dengeli/tam modda; hızlıda no-op).
                    # Cache hakemli nihai sonucu saklar → sıcak=soğuk özdeş.
                    try:
                        import ocr_ensemble
                        meta, self.ocr_hakem_kaydi = ocr_ensemble.hakemlik(
                            img, list(meta), duzelt=_ocr_tr_duzelt,
                            kimlik=self.kimlik)
                    except Exception:  # noqa: BLE001 — hakem yerel yolu bozamaz
                        pass
                    ham = [s.to_dict() for s in meta]
                    _ocr_cache_yaz(self.kimlik, ham)
                except Exception as exc:  # tek sayfa hatası diğerlerini düşürmez
                    # belgeyi düşürmesin: o sayfayı boş bırak, önbelleğe YAZMA
                    # (geçici hata olabilir; yeniden denenebilsin).
                    self.ocr_hata = str(exc)
                    ham = []
                finally:
                    self.serbest_birak()   # OCR sonrası görüntüyü tut­ma
            meta = []
            for kayit in ham:
                if isinstance(kayit, OCRSatiri):
                    satir = kayit
                elif isinstance(kayit, dict):
                    satir = _ocr_satiri_dictten(
                        kayit, self.genislik, self.yukseklik,
                        duzelt=False, kaynak="cache")
                else:  # haricî/eskiden monkeypatch'lenen iki-elemanlı yapı
                    m, k = kayit[:2]
                    satir = OCRSatiri(str(m), tuple(k))
                if satir is not None:
                    meta.append(satir)
            self._ocr_satir_metalari = tuple(meta)
            # Konumsal alanları koruyan eski sözleşme: kalın bilgisi OCR'da
            # yok; güven/alternatifler ``ocr_satir_metalari`` ile erişilir.
            self._satir_kesa = [(s.metin, tuple(s.kutu), False) for s in meta]
        return self._satir_kesa

    def ocr_satir_metalari(self):
        """Güven/alternatif/önek kutulu V3 OCR satırlarını döndürür."""
        self.satirlar()
        return self._ocr_satir_metalari or ()

    def resim_kutulari(self):
        return []

    def kirp(self, kutu):
        x0, y0, x1, y1 = kutu
        if self._page is not None:
            # Algılama/OCR uzayı sabit 200 DPI pikseldir. Kutuyu PDF punto
            # uzayına geri çevirip yalnız o bölgeyi kullanıcının istediği DPI'da
            # render et; OCR performansı sabit, arşiv çıktısı yüksek kaliteli olur.
            clip = fitz.Rect(x0 / self._olcek, y0 / self._olcek,
                             x1 / self._olcek, y1 / self._olcek) & self._page.rect
            m = fitz.Matrix((self.dpi or OCR_RENDER_DPI) / 72,
                            (self.dpi or OCR_RENDER_DPI) / 72)
            pix = self._page.get_pixmap(matrix=m, clip=clip, alpha=False)
            return Image.frombytes("RGB", (pix.width, pix.height), pix.samples)
        # Görüntü dosyası: tam çözünürlüklü kaynak kareden piksel kırpması.
        return self._img().crop((int(x0), int(y0), int(x1), int(y1)))

    def gorsel(self):
        return self._img().copy(), 1.0


# --------------------------------------------------------- belge yükleme

def pdf_metin_yeterli(page):
    """Sayfanın işe yarar bir metin katmanı var mı? Taranmış PDF'lerde
    get_text neredeyse boş döner. Ayrıca içeriği RESİM olup metin katmanı
    yalnız birkaç başlıktan ibaret sayfalarda (broşür/afiş) satır sayısı çok
    düşük kalır → OCR'a düşülür."""
    ham = page.get_text("text").strip()
    if len(ham) < 20:
        return False
    gorunur = [c for c in ham if not c.isspace()]
    if not gorunur:
        return False
    kontrol = sum(unicodedata.category(c) in ("Cc", "Cs", "Co")
                  or c == "�" for c in gorunur) / len(gorunur)
    alnum = sum(c.isalnum() for c in gorunur) / len(gorunur)
    if kontrol > 0.015 or alnum < 0.38:
        return False
    d = page.get_text("dict")
    satirlar = [tuple(ln["bbox"]) for b in d["blocks"]
                if b.get("type") == 0 for ln in b["lines"]]
    if len(satirlar) < 12:
        return False

    # Tam sayfa tarama üstündeki gizli OCR katmanı konum olarak bozuksa,
    # metnin varlığına aldanma. Yalnız büyük raster bulunan PDF'lerde
    # ucuz 96-DPI görsel karşılaştırma yapılır; normal vektör PDF hızı aynı.
    alan = max(1.0, page.rect.width * page.rect.height)
    buyuk_gorsel = False
    for im in page.get_images(full=True):
        try:
            if any(r.width * r.height >= alan * 0.55
                   for r in page.get_image_rects(im)):
                buyuk_gorsel = True
                break
        except Exception:  # noqa: BLE001
            continue
    if buyuk_gorsel:
        try:
            olcek = 96 / 72
            pix = page.get_pixmap(matrix=fitz.Matrix(olcek, olcek),
                                  colorspace=fitz.csGRAY, alpha=False)
            img = Image.frombytes("L", (pix.width, pix.height), pix.samples)
            eslesen = toplam = 0
            for k in satirlar[:60]:
                x0 = max(0, int(k[0] * olcek) - 1)
                y0 = max(0, int(k[1] * olcek) - 1)
                x1 = min(img.width, int(k[2] * olcek) + 2)
                y1 = min(img.height, int(k[3] * olcek) + 2)
                if x1 - x0 < 2 or y1 - y0 < 2:
                    continue
                toplam += 1
                parc = img.crop((x0, y0, x1, y1))
                hist = parc.histogram()
                koyu = sum(hist[:225]) / max(1, parc.width * parc.height)
                if koyu >= 0.008:
                    eslesen += 1
            if toplam >= 8 and eslesen / toplam < 0.45:
                return False
        except Exception:  # noqa: BLE001 — görsel test hata verirse metni atma
            pass
    return True


# tam "N." / "N)" numara metni (satırın TAMAMI numara — soru gövdesi metinde yok)
_YALIN_NUMARA = re.compile(r"^(\d{1,3})[.)]$")


def resim_soru_kutulari(page):
    """HİBRİT 'görüntü-soru' sayfası: metin katmanında YALNIZ soru numaraları
    ('1.'..'N.') var, soru GÖVDELERİ sayfaya gömülü GÖRÜNTÜLER (MEB/'Sınav
    Hizmetleri' tipi çıktı, soru-bankası dışa aktarımları). Bu yapıda her soru
    ayrı bir görüntü bloğudur → PDF'in kendi bbox'ları KESİN gerçektir; OCR +
    sütun/numara sezgisine gerek yoktur.

    Döner: okuma sırasında (sütun→yukarı) [(x0,y0,x1,y1)] PDF-punto kutu listesi,
    ya da bu yapı DEĞİLSE None (çağıran normal yola düşer; regresyon nötr).

    Yanlış tetiklenme koruması: ≥2 yalın 'N.' numarası VE her numaranın kendi
    sütununda bir görüntüyle eşleşmesi (numaraların ≥%70'i) gerekir. Tam-sayfa
    tarama (numara yok) ve metin-yerel PDF (numara metne gömülü, yalın değil) bu
    eşiği geçemez."""
    d = page.get_text("dict")
    A = page.rect.width * page.rect.height
    if A <= 0:
        return None
    nums = []
    for b in d["blocks"]:
        if b.get("type") != 0:
            continue
        for ln in b["lines"]:
            t = "".join(s["text"] for s in ln["spans"]).strip()
            m = _YALIN_NUMARA.match(t)
            if m:
                nums.append((int(m.group(1)), tuple(ln["bbox"])))
    if len(nums) < 2:
        return None
    # kayda değer gömülü görüntü blokları (ikon/çizgi/filigran değil)
    imgs = [tuple(b["bbox"]) for b in d["blocks"]
            if b.get("type") == 1
            and (b["bbox"][2] - b["bbox"][0]) * (b["bbox"][3] - b["bbox"][1])
            > A * 0.006]
    if len(imgs) < 2:
        return None
    # her numarayı aynı sütunda (yatay örtüşen) ve hemen hizasında/altındaki bir
    # görüntüyle eşle; her görüntü en çok bir kez kullanılsın
    kullanilan = set()
    kutular = []
    for _, nb in nums:
        nx0, ny0, nx1, ny1 = nb
        en_iyi = None
        for j, im in enumerate(imgs):
            if j in kullanilan:
                continue
            yatay = im[0] <= nx1 + 6 and im[2] >= nx0 - 6
            dikey = im[3] > ny0 - 4 and im[1] < ny1 + 24  # örtüşen ya da altında
            if yatay and dikey and (
                    en_iyi is None
                    or abs(im[1] - ny0) < abs(imgs[en_iyi][1] - ny0)):
                en_iyi = j
        if en_iyi is not None:
            kullanilan.add(en_iyi)
            im = imgs[en_iyi]
            kutu = (min(nb[0], im[0]), min(nb[1], im[1]),
                    max(nb[2], im[2]), max(nb[3], im[3]))
            kutular.append((kutu, nb))       # (soru_kutusu, numara_satır_bbox)
    if len(kutular) < 2 or len(kutular) < len(nums) * 0.7:
        return None
    # okuma sırası: sol-x'leri kümeleyerek sütunları bul, sütun→yukarı sırala
    xs = sorted({round(k[0]) for k, _ in kutular})
    sinir = [(a + b) / 2 for a, b in zip(xs, xs[1:])
             if b - a > page.rect.width * 0.15]

    def kolon(p):
        return sum(1 for s in sinir if p[0][0] >= s)

    kutular.sort(key=lambda p: (kolon(p), p[0][1]))
    return kutular


def ml_kutu_esle(nums, bolgeler, G, Y):
    """ML düzen bölgelerini yalın soru numaralarıyla eşler (saf fonksiyon,
    model gerektirmez → birim test edilebilir). resim_soru_kutulari'nın
    gömülü-görüntü eşlemesinin ML karşılığı: numara sütunları çıkarılır,
    her bölge kendi sütununda üstündeki en yakın numaraya atanır (çapa N ile
    N+1 arasındaki bölgeler N'ye aittir; sonraki çapayı yutamaz).

    nums: [(numara, (x0,y0,x1,y1))], bolgeler: [{"sinif","kutu","guven"}]
    — ikisi de PDF-punto uzayında. Dönüş: resim_soru_kutulari ile AYNI yapı
    [(soru_kutusu, numara_satır_bbox)] ya da None (eşik geçilemedi)."""
    if duzen_model is None or len(nums) < 2:
        return None
    secili = [b for b in bolgeler
              if b.get("sinif") in duzen_model.GOVDE_SINIFLARI
              and b.get("guven", 0) >= 0.35
              and (b["kutu"][2] - b["kutu"][0])
              * (b["kutu"][3] - b["kutu"][1]) > G * Y * 0.006]
    if not secili:
        return None
    # numara sütunları: sol-x kümeleri (resim_soru_kutulari ile aynı kural)
    xs = sorted({round(nb[0]) for _, nb in nums})
    sinir = [(a + b) / 2 for a, b in zip(xs, xs[1:]) if b - a > G * 0.15]

    def kolon(x):
        return sum(1 for s in sinir if x >= s)

    sutunlar = {}
    for num in nums:
        sutunlar.setdefault(kolon(num[1][0]), []).append(num)
    for grup in sutunlar.values():
        grup.sort(key=lambda n: n[1][1])

    birlesim = {}   # id(num kaydı) → [x0,y0,x1,y1]
    for b in secili:
        bx0, by0, bx1, by1 = b["kutu"]
        grup = sutunlar.get(kolon((bx0 + bx1) / 2))
        if not grup:
            continue
        sahip, sonraki_y = None, None
        for i, (_, nb) in enumerate(grup):
            if nb[1] <= by0 + Y * 0.01:
                sahip = grup[i]
                sonraki_y = grup[i + 1][1][1] if i + 1 < len(grup) else None
            else:
                break
        if sahip is None:
            continue
        if sonraki_y is not None:      # bölge sonraki çapayı yutamaz
            by1 = min(by1, sonraki_y - 2)
            if by1 <= by0:
                continue
        k = birlesim.setdefault(id(sahip), list(sahip[1]))
        k[0], k[1] = min(k[0], bx0), min(k[1], by0)
        k[2], k[3] = max(k[2], bx1), max(k[3], by1)

    kutular = [(tuple(birlesim[id(num)]), num[1])
               for grup in sutunlar.values() for num in grup
               if id(num) in birlesim]
    if len(kutular) < 2 or len(kutular) < len(nums) * 0.7:
        return None
    kutular.sort(key=lambda p: (kolon(p[0][0]), p[0][1]))
    return kutular


def _ml_resim_plani(page, yol, sayfa_no):
    """Hibrit sayfa için ML düzen tespitli plan: resim_soru_kutulari eşiği
    geçemediğinde (gömülü görüntü bbox'ları eksik/parçalı) denenir. Yalın
    numara yoksa render bile edilmez → gerçek taranmış sayfalarda maliyet
    sıfır. Her hata → None (çağıran taranmış yola düşer)."""
    if duzen_model is None or not duzen_model.kullanilabilir():
        return None
    try:
        nums = []
        for b in page.get_text("dict")["blocks"]:
            if b.get("type") != 0:
                continue
            for ln in b["lines"]:
                t = "".join(s["text"] for s in ln["spans"]).strip()
                m = _YALIN_NUMARA.match(t)
                if m:
                    nums.append((int(m.group(1)), tuple(ln["bbox"])))
        if len(nums) < 2:
            return None
        olcek = OCR_RENDER_DPI / 72
        pix = page.get_pixmap(matrix=fitz.Matrix(olcek, olcek), alpha=False)
        img = Image.frombytes("RGB", (pix.width, pix.height), pix.samples)
        bolgeler = duzen_model.bolgeler_gorsel(
            img, duzen_model.kimlik(_ocr_kimlik(yol, sayfa_no,
                                                f"duzen-{OCR_RENDER_DPI}")))
        if not bolgeler:
            return None
        punto = [{"sinif": b.get("sinif"), "guven": b.get("guven", 0),
                  "kutu": [v / olcek for v in b["kutu"]]} for b in bolgeler]
        return ml_kutu_esle(nums, punto, page.rect.width, page.rect.height)
    except Exception:  # noqa: BLE001 — sessiz geri düşüş
        return None


def sayfalari_yukle(yol, dpi):
    """Bir girdi dosyasını Sayfa nesnelerine çevirir.
    Dönüş: (sayfalar, doc | None) — doc, açık tutulması gereken fitz belgesi."""
    uzanti = os.path.splitext(yol)[1].lower()
    if uzanti in DOCX_UZANTILARI:
        import docx_girdi
        kayit = docx_girdi.docx_pdf_hazirla(yol)
        sayfalar, doc = sayfalari_yukle(kayit.pdf_yolu, dpi)
        kaynak_meta = kayit.sozluk()
        for sayfa in sayfalar:
            sayfa.kaynak_docx = dict(kaynak_meta)
            sayfa.kaynak_ornegi = _kaynak_ornek_kimligi(yol)
        return sayfalar, doc
    if uzanti in GORUNTU_UZANTILARI:
        with Image.open(yol) as im:
            kare_sayisi = (max(1, int(getattr(im, "n_frames", 1)))
                           if uzanti in COK_KARELI_UZANTILAR else 1)
        sayfalar = []
        for kare_no in range(kare_sayisi):
            kimlik = _ocr_kimlik(
                # Raster normalizasyon sürümü anahtardadır: eski siyah-alpha
                # OCR önbelleği beyaz-kompozit sonuç için yeniden kullanılmasın.
                yol, kare_no, f"orijinal-beyaz-v1-{OCR_GIRDI_MAKS}")
            sayfalar.append(RasterSayfa(
                kimlik, ocr_maks_kenar=OCR_GIRDI_MAKS,
                yol=yol, kare_no=kare_no))
        kaynak_ornegi = _kaynak_ornek_kimligi(yol)
        for sayfa in sayfalar:
            sayfa.kaynak_ornegi = kaynak_ornegi
        return sayfalar, None
    if uzanti != ".pdf":
        raise ValueError(f"desteklenmeyen format: {yol}")

    sayfalar = []
    doc = fitz.open(yol)
    kaynak_kimligi = _kaynak_dosya_kimligi(yol)
    for sayfa_no, page in enumerate(doc):
        sayfa_kimligi = (
            f"pdf-{kaynak_kimligi}-p{sayfa_no}-dpi{float(dpi):g}")
        if pdf_metin_yeterli(page):
            # gerçek metin katmanı var → normal metin yolu (regresyon nötr).
            # Metin-zengin sayfalarda 'N.' etiketleri + figürler hibrit sanılıp
            # kaçırılmasın diye görüntü-soru yolu YALNIZ metinsiz sayfalarda.
            sayfalar.append(PdfSayfa(page, dpi, kimlik=sayfa_kimligi))
            continue
        resim_plani = resim_soru_kutulari(page)
        if resim_plani is None:
            # gömülü-görüntü sezgiseli eşiği geçemedi → (açıksa) ML düzen
            # tespiti dener; o da olmazsa taranmış yol (regresyon nötr)
            resim_plani = _ml_resim_plani(page, yol, sayfa_no)
        if resim_plani is not None:
            # hibrit görüntü-soru sayfası: PDF'in gömülü görüntü bbox'ları =
            # kesin soru kutuları. Vektör kırpma (yüksek DPI) en iyi kalite.
            ps = PdfSayfa(page, dpi, kimlik=sayfa_kimligi)
            ps.resim_kutu_plani = resim_plani
            # Plan elemanını iki alanlı tutarak eski API'yi koru; gerçek
            # basılı numarayı ayrı paralel metadata ile taşı. Önceki
            # ``enumerate(i+1)`` yolu 21–25'i sessizce 1–5'e çeviriyordu.
            numaralar = numara_adaylari(ps.satirlar())
            ps.resim_kutu_numaralari = [next(
                (no for no, nk2, _ in numaralar
                 if max(abs(float(a) - float(b))
                        for a, b in zip(nk, nk2)) <= 1.5), None)
                for _, nk in resim_plani]
            sayfalar.append(ps)
        else:  # taranmış → görüntü TALEP-ÜZERİNE render (bellek için lazy)
            sayfalar.append(RasterSayfa(
                _ocr_kimlik(yol, sayfa_no, OCR_RENDER_DPI),
                page=page, olcek=OCR_RENDER_DPI / 72, dpi=dpi))
    kaynak_ornegi = _kaynak_ornek_kimligi(yol)
    for sayfa in sayfalar:
        sayfa.kaynak_ornegi = kaynak_ornegi
    # doc'u açık tutmalıyız: PdfSayfa.page hâlâ ona bağlı
    return sayfalar, doc


# --------------------------------------------------------- düzen kalibrasyonu

def numara_adaylari(satirlar, cozum=False):
    """(numara, (x0,y0,x1,y1), kalin) — satır başı numara olan satırlar.
    cozum=True: ayrıca 'Soru N :' / 'Çözüm N' çözüm-bölümü çapalarını da
    ekler (çözümlü sayfalarda her çözümü ayrı kesmek için)."""
    ad = []
    for metin, kutu, kalin in satirlar:
        if ORTAK_SORU_ARALIGI.match(metin):
            continue
        if NUMARALI_TALIMAT_DESENI.match(metin):
            continue
        if (not re.match(r"^\s*(?:soru|question)\b", metin, re.I)
                and NUMARALI_BASLIK_DESENI.match(metin)):
            continue
        m = SORU_NO_DESENI.match(metin)
        if not m and cozum:
            m = COZUM_NO_DESENI.match(metin)
        if m:
            ad.append((int(m.group(1)), tuple(kutu), kalin))
    return ad


def _yalin_numara_adaylari(satirlar, adaylar, genislik=None):
    """Ayrı bir satırda duran üst-düzey soru numaralarını döndürür.

    Açık uçlu kitaplarda bir sorunun içinde ``1. ... 2. ...`` önermeleri,
    eşleştirme tabloları ve numaralı cevap çizgileri bulunabilir. Kitabın asıl
    soru numaraları ayrı bir satırda basılmışsa bu çok güçlü ve
    format-bağımsız bir ayrımdır. Yalnız sayfada en az iki böyle çapa varsa
    devreye girmesi, numarası gövdeyle aynı satırda olan normal testleri
    aynen korur.
    """
    yalniz_kutular = set()
    guclu_govde_kutulari = set()
    for metin, kutu, _ in satirlar:
        es = SORU_NO_DESENI.match(metin)
        if not es:
            continue
        kalan = metin[es.end():].strip()
        if not kalan or re.fullmatch(r"\d{1,3}\s*(?:puan|points?)", kalan,
                                     re.I):
            yalniz_kutular.add(tuple(kutu))
        # Bazı yazılılarda üst-düzey soru numarası gövdeyle aynı satırdadır.
        # Ayrı numara satırları bulunan karma sayfada bunları kaybetme; açık
        # ``Soru`` ön eki veya gerçek soru yönergesi güçlü üst-düzey kanıttır.
        elif re.match(r"^\s*(?:soru|question)\b", metin, re.I) \
                or SORU_GOVDE.search(kalan):
            guclu_govde_kutulari.add(tuple(kutu))
    if len(yalniz_kutular) < 2:
        return adaylar
    # Şema/eşleştirme içindeki rakamlar da tek başına bir satırda durabilir.
    # Gerçek soru numarası her sayfa sütununun sol kenarındadır; aynı yarım
    # sayfadaki daha içerlek yalın rakamları ele. Gövdeyle aynı satırdaki güçlü
    # soru adayları aşağıda ayrıca korunur.
    G = genislik or max((k[2] for _, k, _ in satirlar), default=1.0)
    bolumler = []
    for sol, sag in ((0.0, G / 2), (G / 2, G + 1)):
        bolum = [k for k in yalniz_kutular if sol <= k[0] < sag]
        if not bolum:
            continue
        lider_x = min(k[0] for k in bolum)
        bolumler += [k for k in bolum if k[0] <= lider_x + G * 0.025]
    yalniz_kutular = set(bolumler)
    ust_duzey = yalniz_kutular | guclu_govde_kutulari
    return [a for a in adaylar if tuple(a[1]) in ust_duzey]


def _kume_sik_orani(kume, sayfa_satirlari, genislik, yukseklik):
    """Bir sütun kümesindeki numaraların, kaba bölgelerinde şık (A–E) bulunan
    oranı. Gerçek soru sütununda yüksek; 'BİLİM' bilgi kutusu / konu-anlatımı
    sütununda ~0."""
    sikli = 0
    for _, x0, y0, si in kume:
        satirlar = sayfa_satirlari[si]
        if bolge_sik_sayisi(satirlar, y0, y0 + yukseklik * 0.33,
                            x0 - genislik * 0.02, x0 + genislik * 0.33,
                            genislik * 0.01) >= 1:
            sikli += 1
    return sikli / len(kume)


def kalibrasyon(sayfa_satirlari, genislik, yukseklik, sik_zorunlu=False):
    """Belgeden sütun düzenini öğrenir → sıralı sütun-x listesi (her sütunun
    tipik numara sol kenarı).

    Gerçek soru sütunu: numaraları dikey olarak geniş bir alana yayılır ve
    (çoktan seçmeli belgede) bölgelerinde şık içerir. Üst köşe başlığı, üst
    ünite başlığı ve alt bilgi bandı yayılım taşımaz; yan 'bilgi kutusu' /
    konu-anlatımı sütunu şık taşımaz — böyle sahte kümeler elenir."""
    tum = []  # (numara, x0, y0, sayfa_idx)
    for si, satirlar in enumerate(sayfa_satirlari):
        for numara, (x0, y0, x1, y1), _ in numara_adaylari(satirlar):
            tum.append((numara, x0, y0, si))
    if not tum:
        return [0.0]

    tum.sort(key=lambda t: t[1])  # x0'a göre ince kümeleme
    kumeler = [[tum[0]]]
    for t in tum[1:]:
        if t[1] - kumeler[-1][-1][1] <= genislik * 0.055:
            kumeler[-1].append(t)
        else:
            kumeler.append([t])

    def skorla(sik_ele):
        # Skor = (aday sayısı) × (dikey yayılım oranı). sik_ele: çoktan
        # seçmeli belgede bölgesinde çoğunlukla şık olmayan kümeleri ele.
        cikti = []
        for k in kumeler:
            yayilim = (max(t[2] for t in k) - min(t[2] for t in k)) \
                / max(yukseklik, 1)
            if sik_ele and _kume_sik_orani(k, sayfa_satirlari,
                                           genislik, yukseklik) < 0.3:
                continue
            xs = sorted(t[1] for t in k)
            cikti.append((len(k) * yayilim, xs[len(xs) // 2]))
        return cikti

    skorlu = skorla(sik_zorunlu) or skorla(False)  # şık ele hepsini süpürürse
    en_yuksek = max((s for s, _ in skorlu), default=0)
    if en_yuksek <= 0:  # hiç dikey yayılım yok → en kalabalık kümeye düş
        k = max(kumeler, key=len)
        xs = sorted(t[1] for t in k)
        return [xs[len(xs) // 2]]
    # En güçlü sütunun ~%25'inden zayıf kümeleri (gürültü/başlık) ele
    merkezler = sorted(m for s, m in skorlu if s >= en_yuksek * 0.25)

    nihai = [merkezler[0]]  # yakın merkezleri tek sütuna birleştir
    for m in merkezler[1:]:
        if m - nihai[-1] > genislik * 0.055:
            nihai.append(m)
    return nihai


def sutun_indeksi(x0, sutun_xler):
    """Bir x0 konumunu en yakın sütuna atar."""
    return min(range(len(sutun_xler)), key=lambda i: abs(x0 - sutun_xler[i]))


# --------------------------------------------------------- görsel layout
# Sayfanın mürekkep dağılımından sütun sınırlarını NUMARA-BAĞIMSIZ tespit eder.
# Numara kümelemesinden çok daha sağlam: çözümlü/açık-uçlu/karışık düzenlerde
# de sütunlar arası beyaz "vadi"leri bulur; sol+sağ sütun birleşmesini önler.

PROJ_BIN = 1000  # projeksiyon çözünürlüğü (yaklaşık bin sayısı)


def _otsu_esik(gri):
    """Gri PIL görüntüsü için Otsu eşiği (bu değerin ALTI = mürekkep).
    Filigran/açık gürültüyü mürekkep saymamak için [120, 205]'e kısılır."""
    if _np is None:
        return 190
    a = _np.asarray(gri).ravel()
    hist = _np.bincount(a, minlength=256).astype(float)
    p = hist / max(hist.sum(), 1)
    omega = _np.cumsum(p)
    mu = _np.cumsum(p * _np.arange(256))
    mu_t = mu[-1]
    payda = omega * (1.0 - omega)
    payda[payda == 0] = 1e-9
    sigma_b = (mu_t * omega - mu) ** 2 / payda
    return int(min(max(int(_np.argmax(sigma_b)), 120), 205))


def _hareketli_ort(dizi, pencere):
    if pencere <= 1:
        return list(dizi)
    n = len(dizi)
    onek = [0.0]
    for v in dizi:
        onek.append(onek[-1] + v)
    yari = pencere // 2
    cikti = []
    for i in range(n):
        a = max(0, i - yari)
        b = min(n, i + yari + 1)
        cikti.append((onek[b] - onek[a]) / (b - a))
    return cikti


def _yuzdelik(dizi, q):
    if not dizi:
        return 0.0
    s = sorted(dizi)
    return s[min(len(s) - 1, int(q * len(s)))]


def dikey_projeksiyon(sayfa):
    """Sayfanın DİKEY mürekkep profilini LAYOUT-x'e göre döndürür.
    Dönüş: (p, bin_layout) — p[i] = i. bin'de mürekkep kaplama oranı (0..1);
    x_layout = i * bin_layout. Metin sayfasında bbox sözde-projeksiyon (render
    yok); taranmışta piksel projeksiyon (Pillow/numpy, C-hızı)."""
    G, Y = sayfa.genislik, sayfa.yukseklik
    if not sayfa.raster:
        n = PROJ_BIN
        bin_layout = G / n
        p = [0.0] * n
        for _, (x0, y0, x1, y1), _ in sayfa.satirlar():
            i0 = max(0, int(x0 / bin_layout))
            i1 = min(n, int(x1 / bin_layout) + 1)
            for i in range(i0, i1):
                p[i] += (y1 - y0)
        for rx0, ry0, rx1, ry1 in sayfa.resim_kutulari():
            i0 = max(0, int(rx0 / bin_layout))
            i1 = min(n, int(rx1 / bin_layout) + 1)
            for i in range(i0, i1):
                p[i] += (ry1 - ry0)
        p = [min(1.0, v / max(Y, 1)) for v in p]
        return p, bin_layout

    img, olcek = sayfa.gorsel()
    gri = img.convert("L")
    k = max(1, round(gri.width / PROJ_BIN))
    if k > 1:
        gri = gri.reduce(k)
    esik = _otsu_esik(gri)
    if _np is not None:
        p = (_np.asarray(gri) < esik).mean(axis=0).astype(float).tolist()
    else:
        maske = gri.point(lambda v: 255 if v < esik else 0)
        sut = maske.resize((gri.width, 1), Image.BOX)
        p = [v / 255.0 for v in sut.getdata()]
    bin_layout = k / olcek  # 1 küçültülmüş piksel = k piksel = k/olcek layout
    return p, bin_layout


def sutun_bantlari(sayfa):
    """Görsel dikey projeksiyondan sütun bantlarını bulur. Dönüş: LAYOUT
    koordinatında soldan sağa [(x_sol,x_sag)]. Tespit başarısızsa [(0, G)]."""
    G = sayfa.genislik
    p, bin_layout = dikey_projeksiyon(sayfa)
    n = len(p)
    if n < 8:
        return [(0.0, G)]
    ps = _hareketli_ort(p, max(1, int((0.012 if sayfa.raster else 0.006) * n)))
    p90 = _yuzdelik(ps, 0.90)
    if p90 <= 0:
        return [(0.0, G)]
    # İçerik bölgesi (kenar boşluğu / filigran dışta)
    dolu_esik = max(0.03, 0.10 * p90)
    dolu = [v >= dolu_esik for v in ps]
    if not any(dolu):
        return [(0.0, G)]
    sol_i = dolu.index(True)
    sag_i = n - 1 - dolu[::-1].index(True)
    ic_dolu = sorted(ps[i] for i in range(sol_i, sag_i + 1) if ps[i] >= dolu_esik)
    medyan = ic_dolu[len(ic_dolu) // 2] if ic_dolu else p90
    # Gerçek sütun-ARASI vadi: içerik medyanına göre ÇOK sığ (yakın-boş) VE
    # geniş. Sütun-İÇİ şık/ortalama boşlukları medyanın ~yarısı kadar mürekkep
    # taşır (sığ değil) → vadi sayılmaz, sütunlar bölünmez.
    vadi_esik = max(0.02, medyan * 0.35)
    vadi_bin = max(1, int(((0.028 if sayfa.raster else 0.015) * G) / bin_layout))
    sinirlar = [sol_i * bin_layout]
    i = sol_i
    while i <= sag_i:
        if ps[i] < vadi_esik:
            j = i
            while j <= sag_i and ps[j] < vadi_esik:
                j += 1
            if (j - i) >= vadi_bin:
                sinirlar.append(((i + j) / 2) * bin_layout)  # vadi ortası
            i = j
        else:
            i += 1
    sinirlar.append((sag_i + 1) * bin_layout)
    bantlar = [(sinirlar[k], sinirlar[k + 1]) for k in range(len(sinirlar) - 1)]
    return [b for b in bantlar if b[1] - b[0] > G * 0.02] or [(0.0, G)]


def _numara_sutunlari(sayfa):
    """Soru numaralarının x-konumlarından sütun kümelerini (dikey-yayılımlı,
    başlık-elenmiş) döndürür — soldan sağa numara-kümesi listesi."""
    G, Y = sayfa.genislik, sayfa.yukseklik
    num = [(kutu[0], kutu[1]) for _, kutu, _ in numara_adaylari(sayfa.satirlar())]
    kumeler = []
    for x, y in sorted(num):
        if kumeler and x - kumeler[-1][-1][0] <= G * 0.06:
            kumeler[-1].append((x, y))
        else:
            kumeler.append([(x, y)])
    # Gerçek sütun: ≥2 numara VE dikey yayılım (başlık '11. Sınıf' tek-y elenir)
    return [k for k in kumeler if len(k) >= 2
            and max(p[1] for p in k) - min(p[1] for p in k) > Y * 0.12]


def _tek_sorulu_sutun_bantlari(sayfa):
    """Her sütunda yalnız bir soru bulunan sayfalara güvenli yedek.

    Uzun ortak metinli veya tek-soru/sütun düzenlerinde klasik küme ölçütü
    (aynı x'te en az iki numara) doğal olarak oluşmaz. Görsel projeksiyon da
    ortak metin ile sağ soruyu tek kütle sanabilir. Güçlü soru cümlesi taşıyan
    içerik çapalarının sol x'lerini sütun başlangıcı kabul eder; iç sınırı bir
    sonraki çapanın hemen soluna koyar. Böylece numara kutusunun tüm ilk satırı
    kapladığı PDF'lerde bbox merkezi yüzünden sağ soru kesilmez.
    """
    G, Y = sayfa.genislik, sayfa.yukseklik
    guclu = []
    for metin, kutu, _ in sayfa.satirlar():
        if not (Y * 0.08 <= kutu[1] <= Y * 0.92):
            continue
        if ORTAK_SORU_ARALIGI.match(metin):
            continue
        if not SORU_NO_DESENI.match(metin) or not SORU_GOVDE.search(metin):
            continue
        guclu.append((kutu[0], kutu[1]))
    kumeler = []
    for x, y in sorted(guclu):
        if kumeler and x - kumeler[-1][-1][0] <= G * 0.06:
            kumeler[-1].append((x, y))
        else:
            kumeler.append([(x, y)])
    if not (2 <= len(kumeler) <= 4):
        return None
    baslar = [_medyan_x(k) for k in kumeler]
    if any(baslar[i] - baslar[i - 1] < G * 0.16
           for i in range(1, len(baslar))):
        return None
    pay = G * 0.008
    kenarlar = [0.0] + [max(0.0, x - pay) for x in baslar[1:]] + [G]
    return [(kenarlar[i], kenarlar[i + 1])
            for i in range(len(kenarlar) - 1)]


def _medyan_x(kume):
    xs = sorted(p[0] for p in kume)
    return xs[len(xs) // 2]


def _gorsel_numara_rafine(gorsel, gecerli, G):
    """Görsel bantları koru; bir görsel bant İÇİNDE ≥2 numara sütunu varsa
    (görsel gutter sığ kalmış) onları böl. Görsel sınırlar içerik-hassas
    olduğundan meb/ÖSYM gibi net düzenlerde kutular kesin kalır."""
    nihai = []
    for bx0, bx1 in gorsel:
        ic = sorted((k for k in gecerli if bx0 - 1 <= _medyan_x(k) <= bx1 + 1),
                    key=lambda k: min(p[0] for p in k))
        if len(ic) < 2:
            nihai.append((bx0, bx1))
            continue
        kenarlar = [bx0]
        for i in range(1, len(ic)):
            kenarlar.append((max(p[0] for p in ic[i - 1])
                             + min(p[0] for p in ic[i])) / 2)
        kenarlar.append(bx1)
        for i in range(len(kenarlar) - 1):
            nihai.append((kenarlar[i], kenarlar[i + 1]))
    return [b for b in nihai if b[1] - b[0] >= G * 0.055] or [(0.0, G)]


def _raster_gorsel_kume_bantlari(gorsel, gecerli, G):
    """Temiz taramalarda numara kümelerini gerçek görsel bantlara oturt.

    OCR soru numarası sağ sütun ayırıcısının birkaç piksel solunda kalabilir.
    Yalnız x-merkezlerinden sınır üretmek bu durumda iki sütunun ortasını
    keser. Görsel projeksiyonda her numara kümesi ayrı bir banda güvenle
    oturuyorsa o bantları kullan; dekoratif sol şerit gibi numarasız bantları
    çıkar. Eşleme belirsizse ``None`` dönüp eski numara tabanlı yola düşer.
    """
    if len(gorsel) < 2 or len(gecerli) < 2:
        return None
    tol = G * 0.015
    secilen = []
    for kume in sorted(gecerli, key=_medyan_x):
        x = _medyan_x(kume)
        aday = None
        # Bir sonraki görsel bandın hemen solundaki numara o sağ banda aittir.
        for i in range(1, len(gorsel)):
            sinir = gorsel[i][0]
            if sinir - tol <= x <= sinir + tol:
                aday = i
                break
        if aday is None:
            ic = [i for i, (a, b) in enumerate(gorsel) if a <= x <= b]
            if len(ic) == 1:
                aday = ic[0]
        if aday is None or (secilen and aday <= secilen[-1]):
            return None
        secilen.append(aday)
    if len(set(secilen)) != len(gecerli):
        return None
    bantlar = [gorsel[i] for i in secilen]
    return bantlar if all(b - a >= G * 0.055 for a, b in bantlar) else None


def _numara_bant(sayfa, gecerli, G):
    """Numara kümelerinden sütun bantları (görsel kaçırınca yedek). Sınırlar,
    her sütunun METİN İÇERİĞİNİN sağ/sol kenarından (yüzdelik) hesaplanır →
    sol sütun sağ sütun numarasına kadar uzamaz, gerçek gutter'da bölünür.
    Yüzdelik (0.92/0.08) taranmış OCR'ın aykırı-taşan satırlarını dışlar."""
    gecerli = sorted(gecerli, key=lambda k: _medyan_x(k))
    merkez = [_medyan_x(k) for k in gecerli]
    sol_l = [[] for _ in gecerli]
    sag_l = [[] for _ in gecerli]
    for _, (x0, y0, x1, y1), _ in sayfa.satirlar():
        cx = (x0 + x1) / 2
        i = min(range(len(merkez)), key=lambda j: abs(cx - merkez[j]))
        sol_l[i].append(x0)
        sag_l[i].append(x1)

    def yuz(lst, q, yedek):
        if not lst:
            return yedek
        s = sorted(lst)
        return s[min(len(s) - 1, int(q * len(s)))]

    kenarlar = [0.0]
    for i in range(1, len(gecerli)):
        sag_onceki = yuz(sag_l[i - 1], 0.92, merkez[i - 1])
        sol_sonraki = yuz(sol_l[i], 0.08, merkez[i])
        if sag_onceki < sol_sonraki:
            kenarlar.append((sag_onceki + sol_sonraki) / 2)  # gerçek gutter ortası
        else:
            kenarlar.append((merkez[i - 1] + merkez[i]) / 2)  # örtüşme → numara ortası
    kenarlar.append(G)
    return [(kenarlar[i], kenarlar[i + 1]) for i in range(len(kenarlar) - 1)]


def _sayfa_sutunlari_v21(sayfa):
    """Bir sayfanın nihai sütun bantlarını (LAYOUT) döndürür — görsel gutter
    ile numara kümelerinin dikkatli birleşimi.

    METİN sayfasında görsel bbox-projeksiyonu temiz ve içerik-hassas → GÖRSEL
    bantları kullan, bant içi bitişik sütunları numarayla böl (meb/ÖSYM/çözümlü
    kesin). TARANMIŞ sayfada piksel projeksiyonu gürültülü → numara kümelerinin
    METİN İÇERİĞİNDEN türetilen sütunlar daha güvenilir (sağ/karşı sütun kaçmaz).
    Numara zayıf/tek kümeyse görsel gutter'a düşülür."""
    G = sayfa.genislik

    def dis_kenarlari_tamamla(bantlar):
        """Projeksiyonda seyrek kalan soru numarası/şık uçlarını geri kapsa.

        Dikey projeksiyon, sütunun sağındaki yalnız birkaç kısa şık satırını
        içerik dışı sanabilir; numaralar da sol marjda seyrek oldukları için
        ilk bant onların sağından başlayabilir. İç gutter'lara dokunmadan yalnız
        dış kenarları metin yüzdelikleri ve gerçek numara çapalarıyla genişlet.
        """
        if not bantlar:
            return [(0.0, G)]
        try:
            sat = [x for x in sayfa.satirlar()
                   if x[1][1] >= sayfa.yukseklik * 0.04
                   and x[1][3] <= sayfa.yukseklik * 0.96]
        except Exception:  # noqa: BLE001
            return bantlar
        if not sat:
            return bantlar
        sollar = sorted(k[0] for _, k, _ in sat)
        saglar = sorted(k[2] for _, k, _ in sat)
        # %2/%98: tek bir yan filigran veya dikey ayraç tüm bandı açamaz.
        sol_q = sollar[min(len(sollar) - 1, int(len(sollar) * 0.02))]
        sag_q = saglar[min(len(saglar) - 1, int(len(saglar) * 0.98))]
        nums = numara_adaylari(sat)
        if nums:
            sol_q = min(sol_q, min(k[0] for _, k, _ in nums))
            sag_q = max(sag_q, max(k[2] for _, k, _ in nums))
        pay = G * 0.008
        sonuc = list(bantlar)
        sonuc[0] = (max(0.0, min(sonuc[0][0], sol_q - pay)), sonuc[0][1])
        sonuc[-1] = (sonuc[-1][0], min(G, max(sonuc[-1][1], sag_q + pay)))
        return sonuc

    gecerli = _numara_sutunlari(sayfa)
    if len(gecerli) < 2:
        tek = _tek_sorulu_sutun_bantlari(sayfa)
        if tek:
            return dis_kenarlari_tamamla(tek)
        return dis_kenarlari_tamamla(sutun_bantlari(sayfa))
    if sayfa.raster:
        gorsel = sutun_bantlari(sayfa)
        temiz = _raster_gorsel_kume_bantlari(gorsel, gecerli, G)
        if temiz:
            return dis_kenarlari_tamamla(temiz)
        return dis_kenarlari_tamamla(_numara_bant(sayfa, gecerli, G))
    return dis_kenarlari_tamamla(
        _gorsel_numara_rafine(sutun_bantlari(sayfa), gecerli, G))


@dataclass(frozen=True)
class SutunKalibrasyonu:
    """V2.2 sayfa düzeni uzlaşması.

    Tek bir sezgiselin kararını kesin kabul etmek yerine görsel beyaz-boşluk,
    OCR soru çapaları, yatay sayfa bölgeleri ve (varsa) DocLayout-YOLO
    bölgelerini aynı koordinat uzayında birleştirir. ``bantlar`` eski API ile
    uyumludur; kalan alanlar kalite kapısının kararını açıklanabilir yapar.
    """
    bantlar: tuple
    guven: float
    kanitlar: tuple = ()
    uyarilar: tuple = ()
    ayraclar: tuple = ()
    egiklik_derece: float = 0.0
    bolgesel_gecis: bool = False

    def to_dict(self):
        return {
            "bantlar": [[round(float(a), 3), round(float(b), 3)]
                         for a, b in self.bantlar],
            "guven": round(float(self.guven), 3),
            "kanitlar": list(self.kanitlar),
            "uyarilar": list(self.uyarilar),
            "ayraclar": [round(float(x), 3) for x in self.ayraclar],
            "egiklik_derece": round(float(self.egiklik_derece), 3),
            "bolgesel_gecis": bool(self.bolgesel_gecis),
        }


@dataclass(frozen=True)
class DuzenBolgesi:
    """Y aralığına bağlı fiziksel sütun modeli (V3)."""
    y0: float
    y1: float
    bantlar: tuple
    guven: float
    yontem: str = "uzlasma"
    uyarilar: tuple = ()

    def to_dict(self):
        return {
            "y0": round(float(self.y0), 3), "y1": round(float(self.y1), 3),
            "bantlar": [[round(float(a), 3), round(float(b), 3)]
                         for a, b in self.bantlar],
            "guven": round(float(self.guven), 3),
            "yontem": self.yontem, "uyarilar": list(self.uyarilar),
        }


def _bant_ayraclari(bantlar, G):
    """Bant listesini tekilleştirilmiş iç ayraçlara indirger."""
    sonuc = []
    for i in range(len(bantlar) - 1):
        x = (float(bantlar[i][1]) + float(bantlar[i + 1][0])) / 2
        if G * 0.07 <= x <= G * 0.93:
            sonuc.append(x)
    return sonuc


def _projeksiyon_ayraclari_tek(p, bin_layout, G, raster, vadi_orani=0.35,
                               yumusat_orani=None):
    """Tek bir projeksiyondan güvenli iç beyaz-seam merkezlerini çıkarır."""
    n = len(p)
    if n < 16:
        return []
    if yumusat_orani is None:
        yumusat_orani = 0.012 if raster else 0.006
    ps = _hareketli_ort(p, max(1, int(yumusat_orani * n)))
    p90 = _yuzdelik(ps, 0.90)
    if p90 <= 0:
        return []
    dolu_esik = max(0.02, 0.10 * p90)
    dolu = [v >= dolu_esik for v in ps]
    if not any(dolu):
        return []
    sol_i = dolu.index(True)
    sag_i = n - 1 - dolu[::-1].index(True)
    ic = sorted(v for v in ps[sol_i:sag_i + 1] if v >= dolu_esik)
    medyan = ic[len(ic) // 2] if ic else p90
    vadi_esik = max(0.012, medyan * vadi_orani)
    min_gen = max(2, int((0.022 * G) / max(bin_layout, 1e-6)))
    sonuc = []
    i = sol_i + 1
    while i < sag_i:
        if ps[i] < vadi_esik:
            j = i
            while j < sag_i and ps[j] < vadi_esik:
                j += 1
            x = ((i + j) / 2) * bin_layout
            if j - i >= min_gen and G * 0.08 <= x <= G * 0.92:
                sonuc.append(x)
            i = j
        else:
            i += 1
    return sonuc


def _kumele_degerler(degerler, tolerans):
    """[(x, yöntem, ağırlık)] değerlerini yakın x kümelerine ayırır."""
    kumeler = []
    for x, yontem, agirlik in sorted(degerler):
        if kumeler and abs(x - kumeler[-1]["merkez"]) <= tolerans:
            k = kumeler[-1]
        else:
            k = {"degerler": [], "merkez": x}
            kumeler.append(k)
        k["degerler"].append((x, yontem, agirlik))
        toplam = sum(v[2] for v in k["degerler"])
        k["merkez"] = sum(v[0] * v[2] for v in k["degerler"]) / max(toplam, 1e-9)
    return kumeler


def _coklu_projeksiyon_ayraclari(sayfa):
    """Farklı ölçek/eşiklerde kalıcı kalan sütun seam'lerini bulur.

    DocLayout-YOLO'nun global-to-local fikrinin hafif yerel karşılığıdır:
    tek eşik yerine altı farklı görüş oylanır; yalnız en az üçünde yaşayan
    ayraç döner. Bu, tablo hücresi ve kısa şık boşluklarını sütun sanmayı
    belirgin biçimde azaltır.
    """
    G = sayfa.genislik
    try:
        p, bin_layout = dikey_projeksiyon(sayfa)
    except Exception:  # noqa: BLE001 — sentetik/başlıksız sayfa yedeği
        return []
    gorusler = []
    for yumusat in ((0.008, 0.014, 0.022) if sayfa.raster
                    else (0.004, 0.008, 0.014)):
        for oran in (0.28, 0.40):
            gorusler.append(_projeksiyon_ayraclari_tek(
                p, bin_layout, G, sayfa.raster, oran, yumusat))
    ham = [(x, f"p{i}", 1.0) for i, xs in enumerate(gorusler) for x in xs]
    sonuc = []
    for k in _kumele_degerler(ham, G * 0.025):
        gorus = len({v[1] for v in k["degerler"]})
        if gorus >= 3:
            sonuc.append((k["merkez"], gorus / max(1, len(gorusler))))
    return sonuc


def _bolgesel_projeksiyon_ayraclari(sayfa):
    """Üst/orta/alt şeritlerde sütunları ayrı ölçer.

    İki sütundan tam genişliğe geçen sayfalarda seam yalnız bazı şeritlerde
    görünür. İki veya daha çok şeritte aynı kalan seam global kanıt; yalnız
    bir şeritte kalan seam ise güvenli biçimde ``bolgesel_gecis`` işaretidir.
    """
    G, Y = sayfa.genislik, sayfa.yukseklik
    bolgeler = ((Y * 0.08, Y * 0.39), (Y * 0.34, Y * 0.68),
                (Y * 0.63, Y * 0.94))
    profiller = []
    if sayfa.raster:
        try:
            img, olcek = sayfa.gorsel()
            gri = img.convert("L")
            k = max(1, round(gri.width / PROJ_BIN))
            if k > 1:
                gri = gri.reduce(k)
            esik = _otsu_esik(gri)
            for y0, y1 in bolgeler:
                a = max(0, int(y0 * olcek / k))
                b = min(gri.height, int(y1 * olcek / k))
                if b - a < 8:
                    profiller.append(([], k / olcek))
                    continue
                parca = gri.crop((0, a, gri.width, b))
                if _np is not None:
                    p = (_np.asarray(parca) < esik).mean(axis=0).tolist()
                else:
                    mask = parca.point(lambda v: 255 if v < esik else 0)
                    p = [v / 255.0 for v in
                         mask.resize((parca.width, 1), Image.BOX).getdata()]
                profiller.append((p, k / olcek))
        except Exception:  # noqa: BLE001 — bölgesel görüş isteğe bağlıdır
            profiller = []
    else:
        satirlar = sayfa.satirlar()
        n = PROJ_BIN
        bin_layout = G / n
        for y0, y1 in bolgeler:
            p = [0.0] * n
            yuk = max(1.0, y1 - y0)
            for _, (x0, sy0, x1, sy1), _ in satirlar:
                ort = (sy0 + sy1) / 2
                if not y0 <= ort <= y1:
                    continue
                i0 = max(0, int(x0 / bin_layout))
                i1 = min(n, int(x1 / bin_layout) + 1)
                for i in range(i0, i1):
                    p[i] += min(sy1, y1) - max(sy0, y0)
            profiller.append(([min(1.0, v / yuk) for v in p], bin_layout))
    ham = []
    for i, (p, bin_layout) in enumerate(profiller):
        for x in _projeksiyon_ayraclari_tek(
                p, bin_layout, G, sayfa.raster, 0.36,
                0.014 if sayfa.raster else 0.008):
            ham.append((x, f"z{i}", 1.0))
    kararli, tek_bolge = [], False
    for k in _kumele_degerler(ham, G * 0.03):
        adet = len({v[1] for v in k["degerler"]})
        if adet >= 2:
            kararli.append((k["merkez"], adet / 3))
        elif adet == 1:
            tek_bolge = True
    return kararli, tek_bolge


def _egiklik_tahmini(sayfa):
    """Raster sayfada projeksiyon-keskinliğiyle küçük skew açısını ölçer.

    Yalnız analiz için küçültülmüş gri görüntü döndürülerek denenir; kaynak ve
    kırpma koordinatları değiştirilmez. Güçsüz kazanımda 0° kabul edilir.
    """
    if not sayfa.raster or _np is None:
        return 0.0, 1.0
    try:
        img, _ = sayfa.gorsel()
        gri = img.convert("L")
        gri.thumbnail((700, 1000), Image.Resampling.LANCZOS)
        esik = _otsu_esik(gri)

        def puan(aci):
            donuk = gri.rotate(aci, resample=Image.Resampling.BILINEAR,
                               expand=False, fillcolor=255)
            sat = (_np.asarray(donuk) < esik).sum(axis=1).astype(float)
            if len(sat) < 4:
                return 0.0
            # Metin taban çizgileri doğru açıda daha keskin tepe/çukurlar üretir.
            return float(_np.mean(_np.diff(sat) ** 2))

        adaylar = [(aci / 2, puan(aci / 2)) for aci in range(-6, 7)]
        adaylar.sort(key=lambda x: x[1], reverse=True)
        en, ikinci = adaylar[0], adaylar[1]
        kazanc = (en[1] - ikinci[1]) / max(en[1], 1e-9)
        if abs(en[0]) < 0.26 or kazanc < 0.008:
            return 0.0, max(0.55, 1.0 - kazanc)
        return float(en[0]), min(1.0, 0.60 + kazanc * 8)
    except Exception:  # noqa: BLE001
        return 0.0, 0.55


def _bolgesel_gecis_dogrula(sayfa, ayraclar):
    """Bölgesel seam kaybının gerçek tam-genişlik soru geçişi olduğunu kanıtla.

    Sıradan şekil/tablo geçici olarak orta boşluğu doldurabilir. Geçiş rozeti
    için ayrıca ayıracı iki yana geçen bir soru yönergesi/ortak uyaran ve
    ayıracın iki tarafında bağımsız metin akışı aranır.
    """
    if not ayraclar:
        return False
    G, Y = sayfa.genislik, sayfa.yukseklik
    try:
        satirlar = sayfa.satirlar()
    except Exception:  # noqa: BLE001
        return False
    for x in ayraclar:
        capraz = any(
            k[0] <= x - G * 0.055 and k[2] >= x + G * 0.055
            and Y * 0.05 <= (k[1] + k[3]) / 2 <= Y * 0.95
            and (SORU_GOVDE.search(m) or ORTAK_SORU_ARALIGI.match(m))
            for m, k, _ in satirlar)
        sol = any(k[2] <= x + G * 0.02 and k[0] < x - G * 0.10
                  for _, k, _ in satirlar)
        sag = any(k[0] >= x - G * 0.02 and k[2] > x + G * 0.10
                  for _, k, _ in satirlar)
        if capraz and sol and sag:
            return True
    return False


def _soru_modeli_bolgeleri(sayfa):
    """Soru-özel modelin (question_layout_v3) LAYOUT koordinatındaki
    bölgeleri; sayfa nesnesinde önbelleklenir. Model yoksa/başarısızsa []
    (sıfır-etki). Dönüş öğesi: {"sinif", "kutu"(layout), "guven"}."""
    onbellek = getattr(sayfa, "_v3_soru_model_bolgeleri", None)
    if onbellek is not None:
        return onbellek
    bolgeler = []
    if duzen_model is not None and duzen_model.soru_modeli_kullanilabilir():
        try:
            img, olcek = sayfa.gorsel()
            temel = getattr(sayfa, "kimlik", None)
            if temel:
                temel = (f"{temel}|layout={float(sayfa.genislik):.3f}x"
                         f"{float(sayfa.yukseklik):.3f}|"
                         f"render={img.width}x{img.height}")
            ham = duzen_model.soru_bolgeleri_gorsel(
                img, f"soru-{temel}" if temel else None) or []
            ol = max(olcek, 1e-9)
            G = max(1.0, float(sayfa.genislik))
            Y = max(1.0, float(sayfa.yukseklik))
            for b in ham:
                k = b.get("kutu")
                if not k or len(k) < 4:
                    continue
                x0, x1 = sorted((
                    max(0.0, min(G, float(k[0]) / ol)),
                    max(0.0, min(G, float(k[2]) / ol)),
                ))
                y0, y1 = sorted((
                    max(0.0, min(Y, float(k[1]) / ol)),
                    max(0.0, min(Y, float(k[3]) / ol)),
                ))
                if x1 - x0 < 2.0 or y1 - y0 < 2.0:
                    continue
                bolgeler.append({
                    "sinif": b.get("sinif"),
                    "kutu": (x0, y0, x1, y1),
                    "guven": float(b.get("guven", 0.0))})
        except Exception:  # noqa: BLE001 — model görüşü zorunlu değil
            bolgeler = []
    try:
        sayfa._v3_soru_model_bolgeleri = bolgeler
    except Exception:  # noqa: BLE001
        pass
    return bolgeler


def _soru_modeli_sutun_ayraclari(sayfa):
    """Soru-özel modelin question_body/anchor kutularından sütun ayracı
    (DocLayout _ml_sutun_ayraclari ile aynı kümeleme; guven≥0.30)."""
    bolgeler = _soru_modeli_bolgeleri(sayfa)
    if not bolgeler:
        return []
    G, Y = max(1.0, sayfa.genislik), max(1.0, sayfa.yukseklik)
    secili = []
    for b in bolgeler:
        if b["sinif"] not in ("question_body", "question_anchor") \
                or b["guven"] < 0.30:
            continue
        x0, y0, x1, y1 = b["kutu"]
        if G * 0.06 <= x1 - x0 <= G * 0.72 and y1 - y0 >= Y * 0.018:
            secili.append((x0, x1, b["guven"]))
    if len(secili) < 3:
        return []
    kumeler = []
    for bolge in sorted(secili):
        if kumeler and abs(bolge[0] - _yuzdelik(
                [x[0] for x in kumeler[-1]], 0.5)) <= G * 0.055:
            kumeler[-1].append(bolge)
        else:
            kumeler.append([bolge])
    kumeler = [k for k in kumeler if len(k) >= 2]
    if not 2 <= len(kumeler) <= 4:
        return []
    ayraclar = []
    for sol, sag in zip(kumeler, kumeler[1:]):
        sol_sag = _yuzdelik([b[1] for b in sol], 0.75)
        sag_sol = _yuzdelik([b[0] for b in sag], 0.25)
        if sag_sol - sol_sag >= -G * 0.03:
            ayraclar.append((sol_sag + sag_sol) / 2)
    return ayraclar


def _kutu_iou(a, b):
    """İki (x0,y0,x1,y1) kutusunun IoU'su (0..1)."""
    gx = min(a[2], b[2]) - max(a[0], b[0])
    gy = min(a[3], b[3]) - max(a[1], b[1])
    if gx <= 0 or gy <= 0:
        return 0.0
    kesisim = gx * gy
    birlesim = ((a[2] - a[0]) * (a[3] - a[1])
                + (b[2] - b[0]) * (b[3] - b[1]) - kesisim)
    return kesisim / max(1.0, birlesim)


def _kutu_kapsanma_orani(hedef, kapsayan):
    """``hedef`` kutusunun ``kapsayan`` tarafından örtülen yönlü oranı."""
    gx = min(hedef[2], kapsayan[2]) - max(hedef[0], kapsayan[0])
    gy = min(hedef[3], kapsayan[3]) - max(hedef[1], kapsayan[1])
    if gx <= 0 or gy <= 0:
        return 0.0
    hedef_alan = max(
        1.0, (hedef[2] - hedef[0]) * (hedef[3] - hedef[1]))
    return gx * gy / hedef_alan


def _model_bolgeleri_ayrik_mi(bolgeler, G, Y):
    """Model bölgelerinin gerçekten farklı sorulara ait olma kanıtı.

    Global ve yerel model geçişleri tek sorunun gövde/başlık parçalarını ayrı
    ``question_body`` kutuları olarak döndürebilir. Düşük IoU tek başına iki
    soru demek değildir; en az bir eksende örtüşme zayıf ve merkez uzaklığı
    anlamlı olmalıdır.
    """
    for i, a in enumerate(bolgeler):
        ax0, ay0, ax1, ay1 = a["kutu"]
        aw, ah = max(1.0, ax1 - ax0), max(1.0, ay1 - ay0)
        for b in bolgeler[i + 1:]:
            bx0, by0, bx1, by1 = b["kutu"]
            bw, bh = max(1.0, bx1 - bx0), max(1.0, by1 - by0)
            x_ort = max(0.0, min(ax1, bx1) - max(ax0, bx0)) \
                / max(1.0, min(aw, bw))
            y_ort = max(0.0, min(ay1, by1) - max(ay0, by0)) \
                / max(1.0, min(ah, bh))
            merkez_dx = abs((ax0 + ax1) - (bx0 + bx1)) / 2
            merkez_dy = abs((ay0 + ay1) - (by0 + by1)) / 2
            if ((x_ort <= 0.20 and merkez_dx >= G * 0.05)
                    or (y_ort <= 0.20 and merkez_dy >= Y * 0.035)):
                return True
    return False


def _guclu_ayrik_model_govdeleri_mi(bolgeler, G, Y):
    """İki yüksek güvenli, anlamlı boyutlu bağımsız model gövdesi var mı?

    Anchor modeli ikinci soru numarasını kaçırabilir. Bu durumda iki büyük ve
    yüksek güvenli gövdeyi tek otomatik kutuda bırakmak sessiz birleşmedir.
    Ufak başlık/şekil parçaları ise alan ve boyut eşiğini geçemediğinden tek
    uzun soruyu gereksiz yere incelemeye düşürmez.
    """
    guclu = []
    for b in bolgeler:
        x0, y0, x1, y1 = b["kutu"]
        w = max(0.0, x1 - x0)
        h = max(0.0, y1 - y0)
        if (float(b.get("guven", 0.0)) >= 0.72
                and w >= G * 0.16 and h >= Y * 0.07
                and w * h >= G * Y * 0.018):
            guclu.append(b)
    return len(guclu) >= 2 and _model_bolgeleri_ayrik_mi(guclu, G, Y)


def _ml_sutun_ayraclari(sayfa):
    """DocLayout-YOLO gövde bölgelerinin x hizalarından sütun ayracı üretir."""
    if duzen_model is None or not duzen_model.kullanilabilir():
        return []
    try:
        img, olcek = sayfa.gorsel()
        temel = getattr(sayfa, "kimlik", None)
        if not temel and hasattr(sayfa, "page"):
            temel = f"pdf-{getattr(sayfa.page, 'number', 0)}-{sayfa.genislik}"
        bolgeler = duzen_model.bolgeler_gorsel(
            img, duzen_model.kimlik(temel or "")) or []
        G, Y = sayfa.genislik, sayfa.yukseklik
        secili = []
        for b in bolgeler:
            if b.get("sinif") not in duzen_model.GOVDE_SINIFLARI \
                    or b.get("guven", 0) < 0.32:
                continue
            x0, y0, x1, y1 = (float(v) / max(olcek, 1e-9)
                              for v in b["kutu"])
            if G * 0.06 <= x1 - x0 <= G * 0.72 and y1 - y0 >= Y * 0.018:
                secili.append((x0, x1, float(b.get("guven", 0))))
        if len(secili) < 3:
            return []
        kumeler = []
        for bolge in sorted(secili):
            if kumeler and abs(bolge[0] - _yuzdelik(
                    [x[0] for x in kumeler[-1]], 0.5)) <= G * 0.055:
                kumeler[-1].append(bolge)
            else:
                kumeler.append([bolge])
        kumeler = [k for k in kumeler if len(k) >= 2]
        if not 2 <= len(kumeler) <= 4:
            return []
        ayraclar = []
        for sol, sag in zip(kumeler, kumeler[1:]):
            sol_sag = _yuzdelik([b[1] for b in sol], 0.75)
            sag_sol = _yuzdelik([b[0] for b in sag], 0.25)
            if sag_sol - sol_sag >= -G * 0.03:
                ayraclar.append((sol_sag + sag_sol) / 2)
        return ayraclar
    except Exception:  # noqa: BLE001 — model görüşü zorunlu değildir
        return []


# A2*: "saf numara" (yalnız numara x-ortalaması türevi, bağımsız görsel
# kanıtsız) ve "görsel" (beyaz-boşluk/seam tabanlı) yöntem aileleri —
# sayfa_sutun_kalibrasyonu'nun güçlü hesabı ve too-close tercih mantığında
# kullanılır.
_NUMARA_YONTEMLER = frozenset({"v21_geometri", "ocr_capalari"})
_GORSEL_YONTEMLER = frozenset(
    {"coklu_projeksiyon", "bolgesel_seam", "doclayout_yolo", "soru_modeli"})


def sayfa_sutun_kalibrasyonu(sayfa, yenile=False):
    """Sayfa sütunlarını çok-yöntemli uzlaşmayla kalibre eder."""
    if not yenile:
        eski = getattr(sayfa, "_v22_sutun_kalibrasyonu", None)
        if eski is not None:
            # Sertleştirme: ilk koşumda duzen_bolgeleri_uret istisna atmışsa
            # _v22 set olur ama _v3_duzen_bolgeleri hiç yazılmamış kalır —
            # cache-hit yolu bunu asla yeniden denemezdi (o sayfada A1*'in
            # tam-genişlik izni kalıcı kırılırdı). Eksikse burada dene.
            if not getattr(sayfa, "_v3_duzen_bolgeleri", None):
                try:
                    sayfa._v3_duzen_bolgeleri = tuple(
                        b.to_dict() for b in duzen_bolgeleri_uret(sayfa, eski))
                except Exception:  # noqa: BLE001
                    pass
            return eski
    G = max(1.0, float(sayfa.genislik))
    legacy = _sayfa_sutunlari_v21(sayfa)
    legacy_ayrac = _bant_ayraclari(legacy, G)
    coklu = _coklu_projeksiyon_ayraclari(sayfa)
    bolgesel, gecis_adayi = _bolgesel_projeksiyon_ayraclari(sayfa)

    capalar = []
    gecerli = _numara_sutunlari(sayfa)
    numara_yedek_bantlar = None
    if len(gecerli) >= 2:
        numara_yedek_bantlar = _numara_bant(sayfa, gecerli, G)
        capalar = _bant_ayraclari(numara_yedek_bantlar, G)
    else:
        tek = _tek_sorulu_sutun_bantlari(sayfa)
        if tek:
            capalar = _bant_ayraclari(tek, G)
    # A2*: SOY İŞARETİ — `_sayfa_sutunlari_v21` GERÇEKTEN `_numara_bant`
    # yedeğinden mi geldi (taranmışta görsel kümeleme başarısız olup numara
    # x-ortalamasına düşüldü) yoksa görsel projeksiyondan mı? `_numara_bant`
    # bantlarıyla örtüşme, kaynağı `_sayfa_sutunlari_v21`'in kendi
    # dallanmasına dokunmadan (mevcut çağrı yerini/dönüş tipini bozmadan)
    # ortaya çıkarır. Yalnız GERÇEKTEN numara-yedeğinden gelen v21,
    # ocr_capalari ile AYNI kanıt ailesi sayılır (ikisi de numara x-ortalaması
    # türevi, bağımsız değil) — görsel kökenli v21 asla zayıflatılmaz.
    # Sertleştirme: TAM bant tuple'ı (dış kenarlar dahil) yerine yalnız İÇ
    # AYRAÇLAR karşılaştırılır (`legacy_ayrac` vs `capalar`) — `_sayfa_
    # sutunlari_v21` numara-yedeğine düştüğünde bile sonucu
    # `dis_kenarlari_tamamla` ile dış kenarlardan (ilk/son bandın dış ucu)
    # sarmalıyor; bu sarmalama iç ayraçlara DOKUNMAZ ama tam-tuple eşitliğini
    # kırılgan kılar (gerçek numara-yedeği soyu kaçırılabilir).
    v21_numara_soy = bool(
        numara_yedek_bantlar and len(legacy_ayrac) == len(capalar)
        and all(abs(a - b) < 1e-6 for a, b in zip(legacy_ayrac, capalar)))
    gecis = bool(gecis_adayi and _bolgesel_gecis_dogrula(
        sayfa, legacy_ayrac + [a for a, _ in coklu] + capalar))
    # Ağır model yalnız yerel yöntemler anlaşamadığında çalışır. Bu hem
    # gizlilik/yerellik varsayımını hem de yüzlerce sayfalık kitap hızını
    # korur; kesin sayfalar boşuna sinir ağı çıkarımı ödemez.
    ucuz_sayilar = [len(x) for x in (legacy_ayrac,
                                     [a for a, _ in coklu],
                                     [a for a, _ in bolgesel], capalar) if x]
    ucuz_belirsiz = ((ucuz_sayilar and
                      max(ucuz_sayilar) != min(ucuz_sayilar))
                     or (legacy_ayrac and len(ucuz_sayilar) < 2)
                     or (not legacy_ayrac and bool(ucuz_sayilar)))
    ml = _ml_sutun_ayraclari(sayfa) if ucuz_belirsiz else []
    # Soru-özel model (varsa) doğrudan soru gövdesinden sütun görür → genel
    # DocLayout'tan güçlü ama tek başına 'guclu' eşiğini geçemeyecek ağırlık.
    soru_ml = _soru_modeli_sutun_ayraclari(sayfa) if ucuz_belirsiz else []

    ham = []
    ham += [(x, "v21_geometri", 0.36) for x in legacy_ayrac]
    ham += [(x, "coklu_projeksiyon", 0.22 + 0.10 * destek)
            for x, destek in coklu]
    ham += [(x, "bolgesel_seam", 0.18 + 0.08 * destek)
            for x, destek in bolgesel]
    ham += [(x, "ocr_capalari", 0.34) for x in capalar]
    ham += [(x, "doclayout_yolo", 0.24) for x in ml]
    ham += [(x, "soru_modeli", 0.30) for x in soru_ml]
    kumeler = _kumele_degerler(ham, G * 0.032)
    # A2*: v21_geometri+ocr_capalari, YALNIZ v21 gerçekten numara-yedeğinden
    # geldiyse (yukarıdaki v21_numara_soy) aynı kanıt ailesi sayılır — ikisi
    # de aynı numara x-ortalamasından türer, bağımsız iki yöntem değildir.
    # Görsel kökenli v21 bundan ETKİLENMEZ (kendi ailesinde kalır). Modül
    # sabiti _NUMARA_YONTEMLER'in KENDİSİ kullanılır (literal kopya değil) —
    # ileride sabit değişirse ikisi senkron kalır.
    numara_ailesi = _NUMARA_YONTEMLER if v21_numara_soy else frozenset()
    bilgiler = []
    for k in kumeler:
        yontemler = {v[1] for v in k["degerler"]}
        aileler = {"numara_ailesi" if y in numara_ailesi else y
                   for y in yontemler}
        toplam = sum(v[2] for v in k["degerler"])
        bilgiler.append({"x": k["merkez"], "yontemler": yontemler,
                         "destek": min(1.0, toplam),
                         "guclu": len(aileler) >= 2 and toplam >= 0.48,
                         "legacy": "v21_geometri" in yontemler})
    guclu_var = any(b["guclu"] for b in bilgiler)
    # Desteksiz eski sınır, başka konumda iki bağımsız yöntemin güçlü ortak
    # kararı varsa korunmaz. Bu, hatalı eski ayraç + doğru yeni ayracın üç
    # sütun üretmesi yerine sınırı gerçekten düzeltir.
    secilen_bilgi = [b for b in bilgiler
                     if G * 0.12 <= b["x"] <= G * 0.88
                     and (b["guclu"] or (b["legacy"] and not guclu_var))]
    secilen_bilgi.sort(key=lambda b: b["x"])
    # A2*: YEREL KAYIP ÖLÇÜSÜ — birbirine G*0.12 içinde yakın bir "saf numara"
    # (yalnız v21_geometri/ocr_capalari) adayı ile bir "görsel" (coklu_
    # projeksiyon/bolgesel_seam/doclayout_yolo) adayı çakıştığında, yalnız
    # yüksek-destekliyi tutmak yerine normal OCR satırlarını ve soru
    # ilk-satırlarını DAHA AZ bölen konum kazanır (ygslys s16: numara-ortası
    # çok satırı ortadan keserken gerçek gutter kesmez). Tekil bir satırın
    # bölünmesi (OCR-birleşme aykırısı, bkz. A1*) tek başına saymaz.
    try:
        _kb_satirlari = sayfa.satirlar()
    except Exception:  # noqa: BLE001
        _kb_satirlari = []

    def _kb_kopru_supheli_mi(smetin):
        # A1*'in _satir_supheli_kopru_mu ile aynı imza (SATIR_ICI_SORU_
        # BASLANGICI), bağımsız/minimal biçimde tekrarlanır — bu closure
        # sorulari_tespit_meta'da, sayfa_sutun_kalibrasyonu'ndan erişilemez.
        # Öz-numarası DIŞINDA satır-ortası soru-başlangıcı jetonu taşıyan
        # satır köprülü OCR artığıdır (iki sütun birleşmiş); bu tür satırlar
        # "GERÇEK yerel bölme kanıtı" sayılmaz — iki köprülü satır aynı
        # sayfada rastlarsa gerçek görsel gutter'a haksız kayıp yazdırıp
        # saf-numara adayını kazandırabilirdi.
        oz = SORU_NO_DESENI.match(smetin)
        oz_bitis = oz.end() if oz else 0
        return any(es.start() >= oz_bitis
                   for es in SATIR_ICI_SORU_BASLANGICI.finditer(smetin))

    def _yerel_bolme_sayisi(x):
        pay = G * 0.01
        bolunen = sum(1 for smetin, k, _ in _kb_satirlari
                      if k[0] <= x - pay and k[2] >= x + pay
                      and not _kb_kopru_supheli_mi(smetin))
        return bolunen if bolunen >= 2 else 0

    def _tercih_edilen(onceki, aday):
        o_gorsel = bool(onceki["yontemler"] & _GORSEL_YONTEMLER)
        a_gorsel = bool(aday["yontemler"] & _GORSEL_YONTEMLER)
        o_saf_num = bool(onceki["yontemler"]) \
            and onceki["yontemler"] <= _NUMARA_YONTEMLER
        a_saf_num = bool(aday["yontemler"]) \
            and aday["yontemler"] <= _NUMARA_YONTEMLER
        if (o_saf_num and a_gorsel) or (a_saf_num and o_gorsel):
            o_kayip = _yerel_bolme_sayisi(onceki["x"])
            a_kayip = _yerel_bolme_sayisi(aday["x"])
            if o_kayip != a_kayip:
                return onceki if o_kayip < a_kayip else aday
        return onceki if onceki["destek"] >= aday["destek"] else aday

    # Birbirine tehlikeli derecede yakın iki ayraç dar sahte sütun üretmesin;
    # soru sütunu sayılmak için sayfa genişliğinin en az %12'si gerekir.
    temiz = []
    for b in secilen_bilgi:
        if not temiz or b["x"] - temiz[-1]["x"] >= G * 0.12:
            temiz.append(b)
        else:
            temiz[-1] = _tercih_edilen(temiz[-1], b)
    temiz = temiz[:3]
    secilen = [b["x"] for b in temiz]
    destekler = [(b["yontemler"], b["destek"]) for b in temiz]

    if secilen:
        sol = min(a for a, _ in legacy) if legacy else 0.0
        sag = max(b for _, b in legacy) if legacy else G
        kenarlar = [min(0.0, sol)] + secilen + [max(G, sag)]
        bantlar = [(max(0.0, kenarlar[i]), min(G, kenarlar[i + 1]))
                   for i in range(len(kenarlar) - 1)
                   if kenarlar[i + 1] - kenarlar[i] >= G * 0.12]
    else:
        bantlar = legacy or [(0.0, G)]

    yontemler = sorted({v[1] for v in ham})
    if secilen:
        ort_destek = sum(d for _, d in destekler) / max(1, len(destekler))
        uyum = sum(len(y) for y, _ in destekler) / max(1, len(destekler))
        guven = min(0.98, 0.46 + ort_destek * 0.24 + min(3, uyum) * 0.09)
    else:
        # Tüm yöntemlerin ayraç bulmaması da tek-sütun için olumlu uzlaşmadır.
        aykiri = bool(coklu or bolgesel or capalar or ml or soru_ml)
        guven = 0.58 if aykiri else 0.86
    sayilar = [len(x) + 1 for x in (legacy_ayrac, [a for a, _ in coklu],
                                    [a for a, _ in bolgesel], capalar, ml,
                                    soru_ml)
               if x]
    uyarilar = []
    if sayilar and max(sayilar) - min(sayilar) >= 1:
        guven -= 0.12
        uyarilar.append("sutun_yontemleri_uyusmuyor")
    if gecis:
        uyarilar.append("bolgesel_sutun_gecisi")
    egiklik, egik_guven = _egiklik_tahmini(sayfa)
    if abs(egiklik) >= 1.0 and egik_guven >= 0.60:
        guven -= min(0.12, abs(egiklik) * 0.025)
        uyarilar.append("egik_tarama")
    guven = round(max(0.30, min(0.99, guven)), 3)
    if guven < 0.62:
        uyarilar.append("dusuk_sutun_guveni")
    kal = SutunKalibrasyonu(
        bantlar=tuple((float(a), float(b)) for a, b in bantlar),
        guven=guven, kanitlar=tuple(yontemler),
        uyarilar=tuple(dict.fromkeys(uyarilar)), ayraclar=tuple(secilen),
        egiklik_derece=egiklik, bolgesel_gecis=gecis)
    try:
        sayfa._v22_sutun_kalibrasyonu = kal
        sayfa._v3_duzen_bolgeleri = tuple(
            b.to_dict() for b in duzen_bolgeleri_uret(sayfa, kal))
    except Exception:  # noqa: BLE001
        pass
    return kal


def duzen_bolgeleri_uret(sayfa, kalibrasyon=None):
    """Global bantları ``2 sütun → tam genişlik → 2 sütun`` olarak böler.

    Bölgesel geçiş ancak mevcut çoklu-yöntem kalibrasyonu ve ayıracı
    geçen soru/ortak-uyaran satırı birlikte kanıtlarsa kurulur. Yani bir
    tablonun gutter'ı doldurması tek başına tam-genişlik bölgesi yaratmaz.
    """
    kal = kalibrasyon or sayfa_sutun_kalibrasyonu(sayfa)
    G, Y = float(sayfa.genislik), float(sayfa.yukseklik)
    bantlar = tuple(kal.bantlar) or ((0.0, G),)
    if not kal.bolgesel_gecis or len(bantlar) < 2:
        return [DuzenBolgesi(0.0, Y, bantlar, kal.guven)]
    try:
        satirlar = sayfa.satirlar()
    except Exception:  # noqa: BLE001
        return [DuzenBolgesi(0.0, Y, bantlar, min(kal.guven, 0.60),
                            uyarilar=("bolge_satirlari_okunamadi",))]
    ayraclar = kal.ayraclar or tuple(_bant_ayraclari(bantlar, G))
    capraz = []
    for metin, k, _ in satirlar:
        if not (SORU_GOVDE.search(metin) or ORTAK_SORU_ARALIGI.match(metin)):
            continue
        if any(k[0] <= x - G * 0.045 and k[2] >= x + G * 0.045
               for x in ayraclar):
            capraz.append(k)
    if not capraz:
        return [DuzenBolgesi(0.0, Y, bantlar, min(kal.guven, 0.62),
                            uyarilar=("gecis_y_araligi_belirsiz",))]
    num_y = sorted(k[1] for _, k, _ in numara_adaylari(satirlar))
    araliklar = []
    for k in capraz:
        y0 = max(0.0, k[1] - Y * 0.012)
        sonraki = next((y for y in num_y if y > k[3] + Y * 0.025), None)
        y1 = min(Y, sonraki - Y * 0.008 if sonraki is not None
                 else k[3] + Y * 0.18)
        if y1 - y0 >= Y * 0.035:
            araliklar.append((y0, y1))
    if not araliklar:
        return [DuzenBolgesi(0.0, Y, bantlar, min(kal.guven, 0.62),
                            uyarilar=("gecis_y_araligi_belirsiz",))]
    araliklar.sort()
    birlesik = []
    for a, b in araliklar:
        if birlesik and a <= birlesik[-1][1] + Y * 0.02:
            birlesik[-1] = (birlesik[-1][0], max(birlesik[-1][1], b))
        else:
            birlesik.append((a, b))
    sonuc, y = [], 0.0
    for a, b in birlesik:
        if a > y + 1:
            sonuc.append(DuzenBolgesi(y, a, bantlar, kal.guven))
        sonuc.append(DuzenBolgesi(a, b, ((0.0, G),),
                                  min(0.96, kal.guven + 0.03),
                                  "capraz_soru_satiri"))
        y = b
    if y < Y - 1:
        sonuc.append(DuzenBolgesi(y, Y, bantlar, kal.guven))
    return sonuc


def sayfa_sutunlari(sayfa):
    """Geriye uyumlu V2.2 sütun bandı API'si."""
    return list(sayfa_sutun_kalibrasyonu(sayfa).bantlar)


# --------------------------------------------------------- soru tespiti

def bolge_sik_harfleri(satirlar, ust, alt, ban_sol, ban_sag, pay):
    """Bir kırpma bölgesindeki benzersiz şık harfleri (A–E) kümesi."""
    harfler = set()
    for m, (sx0, sy0, sx1, sy1), _ in satirlar:
        if ban_sol - pay <= (sx0 + sx1) / 2 <= ban_sag + pay \
                and sy0 >= ust - pay and sy1 <= alt + pay:
            harfler.update(_sik_harfleri(m))
    return harfler


def bolge_sik_sayisi(satirlar, ust, alt, ban_sol, ban_sag, pay):
    """Bir kırpma bölgesindeki benzersiz şık harfi (A–E) sayısı."""
    return len(bolge_sik_harfleri(satirlar, ust, alt, ban_sol, ban_sag, pay))


def _bolge_satirlari(satirlar, ust, alt, ban_sol, ban_sag, pay):
    return [(m, kutu) for m, kutu, _ in satirlar
            if ban_sol - pay <= (kutu[0] + kutu[2]) / 2 <= ban_sag + pay
            and kutu[1] >= ust - pay and kutu[3] <= alt + pay]


def _slayt_kutusu(sayfa):
    """Slayt/sunum sayfası (yatay, sayfa başına tek soru/cevap): tüm içeriği
    tek kutu olarak döndür. Kenar boşluğu kırpılır, koyu zemin korunur."""
    G, Y = sayfa.genislik, sayfa.yukseklik
    x0 = y0 = 1e9
    x1 = y1 = 0.0
    for _, (a, b, c, d), _ in sayfa.satirlar():
        x0, y0, x1, y1 = min(x0, a), min(y0, b), max(x1, c), max(y1, d)
    for a, b, c, d in sayfa.resim_kutulari():
        x0, y0, x1, y1 = min(x0, a), min(y0, b), max(x1, c), max(y1, d)
    if x1 - x0 < G * 0.1 or y1 - y0 < Y * 0.05:
        return []
    p = G * 0.008
    return [(max(0.0, x0 - p), max(0.0, y0 - p),
             min(G, x1 + p), min(Y, y1 + p))]


def _sayfa_formati(satirlar, belge_fmt):
    """Bir sayfanın kendi formatını belirler (karışık kitaplarda sayfa-başı
    override). Açık uçlu (yazma alanlı) sayfa, belge çoğunlukla çoktan seçmeli
    sayılsa bile 'acik_uclu' işlenir → minik/yanlış parça kesilmez."""
    harfler = set()
    buyuk_harfler = set()
    altmadde_harfleri = set()
    noktali = altmadde = coz = dogru_yanlis = yazma_yonergesi = 0
    coz_capasi = 0
    for m, _, _ in satirlar:
        harfler.update(_sik_harfleri(m))
        buyuk_harfler.update(SIK_GUCLU_DESENI.findall(m))
        if NOKTALI_SATIR.search(m) and not TOC_LIDER.search(m):
            noktali += 1                       # TOC lider satırı yazma alanı değil
        if ALT_MADDE_DESENI.match(m):
            altmadde += 1
            altmadde_harfleri.add(m.strip()[0].lower())
        if COZUM_DESENI.match(m):
            coz += 1
        if COZUM_NO_DESENI.match(m):
            coz_capasi += 1
        if re.search(r"\bdoğru\b", m, re.I) and re.search(r"\byanlış\b", m, re.I):
            dogru_yanlis += 1
        if re.search(
                r"\b(?:yazınız|açıklayınız|belirtiniz|doldurunuz|"
                r"tamamlayınız|eşleştiriniz|çiziniz)\b", m, re.I):
            yazma_yonergesi += 1
    # Tam A–E/C–E seçenek kümesi, soru metninde geçen “belirtiniz” veya
    # şekil panelindeki küçük a/b etiketlerinden daha güçlü bir çoktan
    # seçmeli kanıttır. Önce bunu değerlendir; aksi sıra bazı TYT sayfalarını
    # açık uçlu sanıp son soruyu sayfa altına kadar uzatıyordu.
    # Ama erken dönüş YALNIZ büyük A–E kümesine dayanır: yazılı/çözüm
    # kâğıtlarındaki "a. b. c. d." CEVAP ALT MADDELERİ de küçük harfli şık
    # gibi görünür ve sayfayı yanlışlıkla çoktan seçmeli sayardı — o zaman
    # `blok_gecerli_mi` yazma-alanı kanıtını kabul etmediği için düz metin
    # cevaplar (şıksız, alt maddesiz) tümüyle kaçardı.
    # ÇÖZÜM ÇAPASI en güçlü sinyaldir ve şık kontrolünden ÖNCE gelir: çözüm
    # kitaplarında sayfa "Soru 1 :" başlıklı çözüm bloklarından oluşur ama
    # gövdelerde "Cevap B" / "(A)" gibi ŞIK HARFLERİ de bolca geçtiği için
    # sayfa çoktan seçmeli sanılıyor, çözüm gövdeleri (düz metin) eleniyordu.
    # Ölçüldü: 4 sayfada 40 çözümden 21'i kayboluyordu (recall 1,00 → 0,475).
    if coz_capasi >= 3:
        return "cozumlu"
    if len(buyuk_harfler) >= 3:
        return "coktan_secmeli"
    # Uzun madde dizisi (≥6 harf) ya da Türkçe alfabe harfi ("ç)", "ğ)") bir
    # sorunun alt maddeleri değil, EŞLEŞTİRME/seçenek listesidir; o sayfa açık
    # uçlu sayılırsa son soru sayfa dibine kadar uzayıp birleşme üretir.
    # Not: "f." tek başına sinyal DEĞİLDİR — gerçek cevap alt maddeleri de
    # a'dan f'ye kadar gidebiliyor (yazılı çözüm kâğıtları).
    secenek_listesi = (len(altmadde_harfleri) >= 6
                       or bool(altmadde_harfleri & set("çğıöşü")))
    if (not secenek_listesi
            and (noktali >= 2 or altmadde >= 2 or dogru_yanlis
                 or yazma_yonergesi >= 2)):
        return "acik_uclu"
    # Eşleştirme/seçenek listesi tespit edildiyse ÇOKTAN SEÇMELİ yoluna da
    # düşülmez: o harfler per-soru şık değil, soruların PAYLAŞTIĞI uyarandır.
    # Ölçüldü (12meb s186): a) … o) kutucuklu bir eşleştirme gridi 15 küçük
    # şık harfi üretiyor, sayfa "coktan_secmeli" sanılıyor, böylece hem
    # blok_gecerli_mi her blokta şık kanıtı arıyor (bu sorularda şık yok) hem
    # de zincir çapası devre dışı kalıyordu (fmt != "coktan_secmeli" koşulu).
    # Sonuç: 22 sorunun 3'ü teslim ediliyordu. Bu daraltmayla 11'e çıkıyor.
    if len(harfler) >= 3 and not secenek_listesi:
        return "coktan_secmeli"
    if (noktali >= 2 or altmadde >= 2 or dogru_yanlis
            or yazma_yonergesi >= 2):
        return "acik_uclu"
    if coz >= 1:
        return "cozumlu"
    return belge_fmt


def _x_hiza_kumeleri(adaylar, tolerans):
    """Adayları sol kenarlarına (x0) göre hizalı kümelere ayırır.

    Bir sayfada birden fazla MEŞRU girinti olabilir (üstte tablo, altta
    liste); "en soldaki kazanır" kuralının ikinci kümeyi atmaması için
    gerekli. Aday biçimi: (numara, kutu, ...) — kutu[0] sol kenardır."""
    kumeler = []
    for a in sorted(adaylar, key=lambda a: a[1][0]):
        if kumeler and a[1][0] - kumeler[-1][0][1][0] <= tolerans:
            kumeler[-1].append(a)
        else:
            kumeler.append([a])
    return kumeler


def capa_araligi_p25(kutular):
    """Numara çapaları arasındaki dikey aralıkların 25. YÜZDELİĞİ.

    `min_yuk` eşiğini sayfa yüzdesinden değil sayfanın KENDİ dizgisinden
    türetmek için. Ölçüldü (12meb s186): doğru/yanlış tablosunun satır
    aralığı tam 17,0 pt, sayfa yüzdesi tabanı 0,022 × 779,5 = 17,15 pt —
    yedi soru tesadüfi 0,15 pt farkla eleniyordu.

    Medyan DEĞİL 25. yüzdelik: aynı sayfada sıkı paketli bir liste ile
    seyrek yerleşimli sorular birlikte bulunabiliyor (12meb s186'da 17 pt ile
    45 pt yan yana); medyan sıkı bloğu göremez. Tek bir sapkın küçük aralığın
    eşiği çökertmemesi için de minimum kullanılmaz."""
    ys = sorted(k[1] for k in kutular)
    araliklar = sorted(b - a for a, b in zip(ys, ys[1:]) if b - a > 1.0)
    if len(araliklar) < 3:
        return None
    return araliklar[max(0, (len(araliklar) - 1) // 4)]


def blok_gecerli_mi(satirlar, ust, alt, ban_sol, ban_sag, pay, Y, fmt,
                    kati=False, zincir_capasi=False, capa_araligi=None):
    """Bir bölgeyi gerçek SORU mu yoksa talimat/başlık/konu-maddesi/dekorasyon
    mu olduğunu format-agnostik doğrular. Pozitif kalıp = şık (A-E) VEYA
    soru-gövdesi (…mıdır/hangisi/yazınız…) VEYA yazma alanı (noktalı satır /
    'a. b.' alt madde). Böylece çoktan seçmeli, açık uçlu ve çözümlü sorular
    tek kuralla doğrulanır; konu maddeleri ve minik/boş parçalar elenir.

    kati=True: numara ÇAPASIZ blok-segmentasyon kutuları için daha güçlü kanıt
    ister (tek "A)" satırı gibi parçalar elenir) — şık pozitif yolu ≥2, min
    yükseklik yükseltilir. Soru-gövdesi ve açık-uçlu yazma-alanı yolları aynı.

    zincir_capasi=True: blok, sayfanın DOĞRULANMIŞ artan numara zincirinin
    (≥3 üye) bir üyesidir. Cevap anahtarı / yazılı çözüm kâğıtlarında cevap
    gövdesi düz metindir — ne şık, ne soru kipi, ne yazma alanı taşır — ve
    yukarıdaki üç pozitif yolun hiçbirine uymadığı için tümüyle kaçıyordu
    (ölçüldü: bir çözüm kâğıdında 39 sorudan 12'si). Zincirin kendisi güçlü
    bir kanıttır: numaralar düzenli artıyor ve aynı hizadaysa o bloklar
    sorudur. Yine de yalnız YETERLİ İÇERİK taşıyan ve tanım-maddesi /
    İÇİNDEKİLER lider satırı olmayan bloklar geçer."""
    ic = _bolge_satirlari(satirlar, ust, alt, ban_sol, ban_sag, pay)
    if not ic:
        return False
    metin = " ".join(m for m, _ in ic)
    taban = 0.03 if kati else 0.022
    min_yuk = (0.05 if fmt == "acik_uclu" else taban) * Y
    # Açık uçlu sayfada yüksek min-yükseklik, yazma alanı olmayan minik
    # parçaları elemek içindir; ama doğrulanmış zincirin üyesi olan TEK
    # SATIRLIK cevap ("4. Plasenta") da bu eşiğe takılıp tümüyle kayboluyordu.
    # Zincir kanıtı varken genel tabana düşülür.
    if zincir_capasi and not kati and fmt != "coktan_secmeli":
        min_yuk = taban * Y
        # Sayfanın kendi dizgisi, sayfa yüzdesinden daha iyi bir ölçüdür:
        # doğrulanmış zincirin çapaları arasındaki dar aralık, o sayfada bir
        # sorunun ne kadar kısa olabileceğini doğrudan söyler. %90 pay,
        # çapa aralığından biraz kısa olan son satırı da geçirir.
        if capa_araligi:
            min_yuk = min(min_yuk, capa_araligi * 0.9)
    if alt - ust < min_yuk or len(metin) < 12:
        return False
    # tanım/başlık maddesi ("1. Duyu Nöronu:") — kısa, iki nokta ile biter
    if len(ic) <= 2 and metin.rstrip().endswith(":") \
            and not SORU_GOVDE.search(metin):
        return False
    # Çözümlü sayfa: çözüm gövdesi düz açıklama metnidir (şık/soru-gövdesi
    # içermeyebilir). Blok çözüm çapasıyla (Soru N / Çözüm N) başlıyor ve
    # yeterli içerik taşıyorsa geçerli çözüm sayılır → her çözüm ayrı kesilir.
    # Çapa YALNIZ bölgenin OCR-sıralı ilk satırında aranmaz — bölgeye önceki
    # çözümün "Cevap X" kuyruğu ya da sayfa-no altbilgisi bulaşırsa çapa
    # öne kayar ve meşru çözüm yanlışlıkla düşerdi (cozumler1 s37/41/57/65'te
    # kaybolan kutuların kök nedeni). Gevşek arama ("üst yarıda/ilk 3 satırda
    # herhangi biri") DENENDİ ve yanlış-pozitif üretti: COZUM_NO_DESENI
    # "Soru 5'teki" türü çapraz-referansları da yakaladığından kenar
    # not-şeridi parçaları çözüm sanılıp kutu sayısını 197→266 sıçrattı.
    # Doğru kural teşhis edilen kirliliğe birebir: Y-sıralı satırlardan yalnız
    # bilinen kuyruk kalıpları ("Cevap X" şık harfi, çıplak sayfa numarası)
    # atlanır; çapa, kalan İLK satırda olmak zorundadır.
    if fmt == "cozumlu" and ic and len(re.sub(r"\s", "", metin)) >= 20:
        for m, _ in sorted(ic, key=lambda mk: mk[1][1]):
            if re.match(r"^\s*cevap\s*[-–—.:]?\s*[A-E]\b", m, re.I) \
                    or re.match(r"^\s*\d{1,3}\s*$", m):
                continue
            if COZUM_NO_DESENI.match(m):
                return True
            break
    if len({h for m, _ in ic for h in _sik_harfleri(m)}) \
            >= (2 if kati else 1):
        return True
    if SORU_GOVDE.search(metin):
        return True
    # Yazma alanı (noktalı satır / "a. b." alt madde) YALNIZ açık uçlu sayfada
    # geçerli — çoktan seçmeli/çözümlü/karışık düzende noktalı satır, İÇİNDEKİLER
    # lider noktaları ("... Ortak Özellikleri ........ 5") ya da tablo dolgusu
    # olabilir; şık/soru-gövde yoksa gerçek soru sayılmaz. Ayrıca yazma alanı
    # tek başına yeterli değil (bir sorunun cevap satırı "4. ...." minik kesilir).
    if fmt == "acik_uclu":
        yazma = NOKTALI_SATIR.search(metin) \
            or sum(1 for m, _ in ic if ALT_MADDE_DESENI.match(m)) >= 1
        if yazma and len(re.sub(r"[.…_·\s]", "", metin)) >= 30:
            return True
    # Zincir çapası: son çare. Yukarıdaki içerik-kalıbı yollarının hiçbiri
    # tutmadıysa bile, doğrulanmış numara zincirinin üyesi olan ve yeterli
    # gerçek içerik taşıyan blok sorudur (düz metin cevap gövdesi).
    # ÇOKTAN SEÇMELİ sayfada uygulanmaz: orada gerçek soru zaten şık taşır,
    # gevşetme yalnız yanlış-pozitif üretir (altın veriyle ölçüldü: TYT
    # kalibrasyonunda F1 0,975 → 0,966, fp 41).
    if zincir_capasi and not kati and fmt != "coktan_secmeli":
        govde = re.sub(r"[.…_·\s]", "", metin)
        if len(govde) >= 20 and not TOC_LIDER.search(metin):
            return True
    return False


def _blok_segmentasyon(sayfa, bantlar, satirlar, pay, fmt):
    """Numara olmayan sayfalarda soruları görsel olarak ayırır: her sütun
    şeridinde metin satırlarını y'ye göre dizip, aralarındaki BÜYÜK dikey
    boşlukları (soru ayıracı) bularak blok üretir; blok_gecerli_mi ile doğrular."""
    G, Y = sayfa.genislik, sayfa.yukseklik
    kutular = []
    for ban_sol, ban_sag in bantlar:
        ic = sorted(((sy0, sy1) for _, (sx0, sy0, sx1, sy1), _ in satirlar
                     if ban_sol - pay <= (sx0 + sx1) / 2 <= ban_sag + pay),
                    key=lambda t: t[0])
        if not ic:
            continue
        # ardışık satırlar arası boşluklardan tipik satır-arasını (medyan) bul
        bosluklar = sorted(max(0.0, ic[i][0] - ic[i - 1][1])
                           for i in range(1, len(ic)))
        med = bosluklar[len(bosluklar) // 2] if bosluklar else 0
        esik = max(med * 2.2, Y * 0.02)          # soru ayıracı = büyük boşluk
        gruplar, grup = [], [ic[0]]
        for i in range(1, len(ic)):
            if ic[i][0] - grup[-1][1] > esik:
                gruplar.append(grup)
                grup = [ic[i]]
            else:
                grup.append(ic[i])
        gruplar.append(grup)
        for g in gruplar:
            ust = min(t[0] for t in g) - Y * 0.006
            alt = max(t[1] for t in g) + Y * 0.008
            if blok_gecerli_mi(satirlar, ust, alt, ban_sol, ban_sag, pay, Y,
                               fmt, kati=True):
                kutular.append((ban_sol, ust, ban_sag, alt))
    return kutular


def _blok_arasi_ust_duzey_capa_var_mi(
        onceki_blok, yeni_blok, bant_idx, capalar, raster, G, Y):
    """İki görsel blok arasında güvenilir soru numarası çapası var mı?

    Raster OCR şekil içindeki ``1.`` etiketini de numara adayı yapabilir.
    Sınırı bastırmak için adayın doğrulanmış liste içinde kalmasına ek olarak
    aynı banttaki en soldaki soru-numarası şeridine hizalanmasını şart koşarız.
    Metinli PDF adayları bu noktaya gelmeden zaten hizalama filtresinden geçer.
    """
    bant_capalari = [
        k for _no, bi, k in capalar if bi == bant_idx
    ]
    if not bant_capalari:
        return False
    if raster:
        lider_x = min(k[0] for k in bant_capalari)
        bant_capalari = [
            k for k in bant_capalari
            if abs(k[0] - lider_x) <= G * 0.025
        ]
    return any(
        onceki_blok[3] - Y * 0.01 <= k[1]
        and k[1] <= yeni_blok[1] + Y * 0.03
        for k in bant_capalari
    )


def _sayfa_kaynak_anahtari(sayfa):
    docx = getattr(sayfa, "kaynak_docx", None) or {}
    if docx:
        temel = str(docx.get("kaynak_sha256") or docx.get("kaynak_hash")
                    or docx.get("kaynak") or "docx")
    elif getattr(sayfa, "kimlik", None):
        temel = str(sayfa.kimlik)
    else:
        page = getattr(sayfa, "page", None)
        try:
            temel = page.parent.name
        except Exception:  # noqa: BLE001 — sentetik/kapalı PDF sayfası
            temel = "pdf"
        temel = f"{temel}|{getattr(page, 'number', 0)}"
    # Model/OCR önbelleği içerik kimliğini paylaşabilir; elle verilen sayfa ve
    # kutu kararları ise aynı baytların başka adlı yüklemesine sızmamalıdır.
    return (f"{temel}|ornek={getattr(sayfa, 'kaynak_ornegi', '')}|"
            f"belge={int(getattr(sayfa, 'belge_no', 0))}")


def karar_kimligi(sayfa, kutu, numara=None, tur="soru"):
    """Kaynak + normalize geometriye dayalı, tekrar üretilebilir V3 kimliği."""
    G, Y = max(1.0, float(sayfa.genislik)), max(1.0, float(sayfa.yukseklik))
    norm = [round(float(kutu[0]) / G, 5), round(float(kutu[1]) / Y, 5),
            round(float(kutu[2]) / G, 5), round(float(kutu[3]) / Y, 5)]
    ham = json.dumps([KALIBRASYON_SURUMU, _sayfa_kaynak_anahtari(sayfa),
                      int(getattr(getattr(sayfa, "page", None), "number", 0)),
                      tur, numara, norm], ensure_ascii=False,
                     separators=(",", ":"))
    return "v3_" + hashlib.sha256(ham.encode("utf-8")).hexdigest()[:24]


class SoruKutu(NamedTuple):
    """Bir soru kutusu + birleştirme kararları için meta bilgisi.
    devam_aday=True: sütun başında kalan numarasız 'yetim devam' bölgesi —
    normal çıktıya girmez, yalnız kirpma_plani birleştirmesinde kullanılır."""
    kutu: tuple          # (x0, y0, x1, y1) layout koordinatı
    bant_idx: int        # sayfa_sutunlari bandındaki indeks
    numara: object       # soru numarası (int) | None (numarasız blok)
    devam_aday: bool
    sik_harfler: frozenset   # bölgedeki benzersiz A–E harfleri
    son_metin: str           # bölgedeki en alttaki satır metni
    govde_var: bool          # bölgede soru-gövdesi kalıbı var mı
    # Aşağıdaki alanlar SONRADAN doldurulur (test_bolumleri / tespit);
    # defaultlu son alanlar mevcut 7-konumsal inşaları bozmaz.
    test_no: object = None       # yerel test numarası (kitapta yazan) | None
    test_sira: object = None     # belge-geneli benzersiz test sırası | None
    numara_kutu: object = None   # numara satırının layout bbox'ı | None
    soru_turu: str = "bilinmiyor"
    sayfa_rolu: str = "soru"
    guven: float = 1.0
    kanitlar: tuple = ()
    uyarilar: tuple = ()
    inceleme_durumu: str = "otomatik"  # otomatik | incele | reddedildi
    karar_kimligi: str = ""
    kalibre_guven: object = None
    onay_durumu: str = "otomatik"      # otomatik | bekliyor | onaylandi | reddedildi
    kaynak_yontemler: tuple = ()
    risk_nedenleri: tuple = ()
    duzen_bolgeleri: tuple = ()
    # Kutunun her kenarına HANGİ kuralın karar verdiği. Kesim sınırı
    # hatalarının teşhisi bunsuz yapılamıyordu: alt sınır dört kaynağın
    # (sonraki numara / blok sınırı / TEST başlığı / son metin satırı)
    # sessiz min() yarışıyla belirleniyor ve kazanan hiçbir yere yazılmıyordu.
    # Biçim: (("alt", "sonraki_numara", 812.4), ("ust", "numara_kutu", 401.0))
    sinir_kanitlari: tuple = ()

    def to_dict(self):
        """Web/rapor katmanı için kararlı ve yalnız JSON türleri içeren görünüm."""
        return {
            "kutu": [round(float(v), 3) for v in self.kutu],
            "bant_idx": self.bant_idx,
            "numara": self.numara,
            "devam_aday": self.devam_aday,
            "sik_harfler": sorted(self.sik_harfler),
            "soru_turu": self.soru_turu,
            "sayfa_rolu": self.sayfa_rolu,
            "guven": round(float(self.guven), 3),
            "kanitlar": list(self.kanitlar),
            "uyarilar": list(self.uyarilar),
            "inceleme_durumu": self.inceleme_durumu,
            "karar_kimligi": self.karar_kimligi,
            "kalibre_guven": round(float(
                self.guven if self.kalibre_guven is None
                else self.kalibre_guven), 3),
            "onay_durumu": self.onay_durumu,
            "kaynak_yontemler": list(self.kaynak_yontemler),
            "risk_nedenleri": list(self.risk_nedenleri),
            "duzen_bolgeleri": list(self.duzen_bolgeleri),
            "sinir_kanitlari": [
                [str(k[0]), str(k[1])] + [round(float(v), 3) for v in k[2:]]
                for k in self.sinir_kanitlari],
        }


@dataclass
class SayfaAnalizi:
    """V3'ün sayfa-başı kalibrasyon, risk ve aday sonucu."""
    sayfa_no: int
    sayfa_rolu: str
    rol_guveni: float
    duzen_ailesi: str
    soru_turu: str
    adaylar: tuple = field(default_factory=tuple)
    uyarilar: tuple = field(default_factory=tuple)
    raster: bool = False
    duzen_guveni: float = 1.0
    sutun_kanitlari: tuple = field(default_factory=tuple)
    egiklik_derece: float = 0.0
    karar_kimligi: str = ""
    onay_durumu: str = "otomatik"
    risk_nedenleri: tuple = field(default_factory=tuple)
    duzen_bolgeleri: tuple = field(default_factory=tuple)
    pipeline_hatalari: tuple = field(default_factory=tuple)
    inceleme_gerekli: bool = False

    def to_dict(self):
        return {
            "sayfa_no": self.sayfa_no,
            "sayfa_rolu": self.sayfa_rolu,
            "rol_guveni": round(float(self.rol_guveni), 3),
            "duzen_ailesi": self.duzen_ailesi,
            "soru_turu": self.soru_turu,
            "adaylar": [a.to_dict() if hasattr(a, "to_dict") else a
                         for a in self.adaylar],
            "uyarilar": list(self.uyarilar),
            "raster": bool(self.raster),
            "duzen_guveni": round(float(self.duzen_guveni), 3),
            "sutun_kanitlari": list(self.sutun_kanitlari),
            "egiklik_derece": round(float(self.egiklik_derece), 3),
            "karar_kimligi": self.karar_kimligi,
            "onay_durumu": self.onay_durumu,
            "risk_nedenleri": list(self.risk_nedenleri),
            "duzen_bolgeleri": list(self.duzen_bolgeleri),
            "pipeline_hatalari": list(self.pipeline_hatalari),
            "inceleme_gerekli": bool(self.inceleme_gerekli),
        }


@dataclass
class BelgeProfili:
    """Belgenin temsilî sayfalarından öğrenilen sürümlü V2 profili."""
    kaynak_hash: str
    format: str
    sayfa_sayisi: int
    raster_orani: float
    yon_dagilimi: dict
    rol_dagilimi: dict
    tur_dagilimi: dict
    sutun_aileleri: list
    numara_x_oranlari: list
    tekrar_satirlari: list
    sayfa_rolleri: list
    duzen_guveni: float = 1.0
    kalibrasyon_yontemleri: list = field(default_factory=list)
    egiklik_dagilimi: dict = field(default_factory=dict)
    algoritma_surumu: str = KALIBRASYON_SURUMU
    guven_esikleri: dict = field(default_factory=lambda: {
        "otomatik": GUVEN_OTOMATIK, "incele": GUVEN_INCELE})

    def to_dict(self):
        d = asdict(self)
        d["raster_orani"] = round(float(self.raster_orani), 4)
        return d

    @classmethod
    def from_dict(cls, veri):
        alanlar = {f.name for f in cls.__dataclass_fields__.values()}
        return cls(**{k: v for k, v in dict(veri).items() if k in alanlar})


def _bolge_bilgi(satirlar, kutu, pay):
    """(sik_harfler, son_metin, govde_var) — kutu bölgesinin birleştirme
    kararlarında kullanılan özeti."""
    ic = _bolge_satirlari(satirlar, kutu[1], kutu[3], kutu[0], kutu[2], pay)
    if not ic:
        return frozenset(), "", False
    harfler = frozenset(h for m, _ in ic for h in _sik_harfleri(m))
    metin = " ".join(m for m, _ in ic)
    son = max(ic, key=lambda t: t[1][3])[0]
    return harfler, son, bool(SORU_GOVDE.search(metin))


def _profil_norm(metin):
    """Tekrarlanan üst/altbilgi karşılaştırması için hafif, yerel normalizasyon."""
    metin = unicodedata.normalize("NFKD", str(metin).casefold())
    metin = "".join(c for c in metin if not unicodedata.combining(c))
    metin = re.sub(r"\d+", "#", metin)
    return re.sub(r"[^a-zçğıöşü#]+", " ", metin).strip()


def _sayfa_sinyalleri(satirlar):
    metinler = [m.strip() for m, _, _ in satirlar if m.strip()]
    birlesik = " ".join(metinler)
    numaralar = numara_adaylari(satirlar)
    siklar = {h for m in metinler for h in _sik_harfleri(m)}
    govde_sayisi = sum(bool(SORU_GOVDE.search(m)) for m in metinler)
    yazma_sayisi = sum(bool(NOKTALI_SATIR.search(m)
                             and not TOC_LIDER.search(m)) for m in metinler)
    toc_sayisi = sum(bool(TOC_LIDER.search(m)) for m in metinler)
    cozum_sayisi = sum(bool(COZUM_DESENI.match(m)
                             or COZUM_BOLUM_BASLIK.match(m)) for m in metinler)
    paragraf = sum(len(m) >= 70 for m in metinler)
    return {
        "metinler": metinler, "birlesik": birlesik,
        "numara": len(numaralar), "siklar": siklar,
        "govde": govde_sayisi, "yazma": yazma_sayisi,
        "toc": toc_sayisi, "cozum": cozum_sayisi,
        "paragraf": paragraf,
    }


def _sayfa_rolu_belirle(satirlar, sayfa_no=None, toplam=None):
    """Bir sayfayı içerik rolüne ayırır; ``(rol, güven, kanıtlar)`` döndürür.

    Bu katman soru kutusu üretmez. Bu nedenle konu anlatımındaki sıralı
    maddeleri soru sanma hatasını tespit motorundan önce durdurabilir.
    """
    s = _sayfa_sinyalleri(satirlar)
    metinler, birlesik = s["metinler"], s["birlesik"]
    kucuk = _profil_norm(birlesik)
    kanit = []
    try:
        cevap = _cevap_sayfasi_mi(satirlar)
    except Exception:  # işlev modül yüklenirken henüz çağrılmaz; savunma
        cevap = False
    if cevap:
        return "cevap_anahtari", 0.99, ("cevap_izgarasi",)
    icindekiler_basligi = any(
        re.fullmatch(
            r"\s*(?:içindekiler|icindekiler|contents)\s*[:\-–—]?\s*",
            metin, re.I)
        for metin in metinler
    )
    if icindekiler_basligi or s["toc"] >= 3:
        return "içindekiler", min(0.99, 0.80 + s["toc"] * 0.04), \
            ("icindekiler_liderleri",)

    soru_puani = 0.0
    if s["numara"] >= 1:
        soru_puani += min(0.28, 0.12 + s["numara"] * 0.04)
        kanit.append("numarali_capalar")
    if len(s["siklar"]) >= 3:
        soru_puani += 0.42
        kanit.append("sik_kumesi")
    if s["govde"]:
        soru_puani += min(0.30, 0.14 + s["govde"] * 0.05)
        kanit.append("soru_yonergesi")
    if s["yazma"]:
        soru_puani += min(0.20, 0.10 + s["yazma"] * 0.03)
        kanit.append("cevap_alani")
    if test_basliklari(satirlar):
        soru_puani += 0.12
        kanit.append("test_basligi")

    # Çözüm başlığı/yoğunluğu güçlü ve yeni soru kanıtı zayıfsa tüm sayfa
    # çözüm rolündedir. Soru metnini de tekrar basan çözümlü sayfa ``karma``
    # kalır; aday düzeyindeki çözüm filtresi yalnız çözüm bloklarını bastırır.
    if s["cozum"] >= 1 and soru_puani < 0.65:
        return "çözüm", min(0.97, 0.78 + s["cozum"] * 0.06), \
            ("cozum_basligi",)
    cevap_basligi = any(
        CEVAP_BASLIK.search(metin.strip()) and len(metin.strip()) <= 40
        for metin in metinler
    )
    if cevap_basligi and soru_puani < 0.58:
        return "cevap_anahtari", 0.90, ("cevap_basligi",)

    if soru_puani < 0.58 and re.search(
            r"\bkonu\s+anlat[ıi]m[ıi]\b|\bders\s+notlar[ıi]\b",
            birlesik, re.I):
        return "konu", 0.96, ("konu_basligi",)

    ilk_sayfa = sayfa_no is not None and sayfa_no <= 2
    kapak_sozcugu = bool(re.search(
        r"\b(?:kitab[ıi]|soru bankas[ıi]|yay[ıi]nlar[ıi]|isbn|copyright|"
        r"ö[ğg]renci\s+ad[ıi])\b", birlesik, re.I))
    if soru_puani < 0.35 and (ilk_sayfa or kapak_sozcugu) \
            and len(metinler) <= 22:
        return "kapak", 0.82 if kapak_sozcugu else 0.70, ("kapak_duzeni",)

    if soru_puani >= 0.58:
        if s["paragraf"] >= 5 and soru_puani < 0.86:
            return "karma", min(0.94, 0.68 + soru_puani * 0.25), tuple(kanit)
        return "soru", min(0.99, 0.66 + soru_puani * 0.30), tuple(kanit)
    if not metinler:
        return "konu", 0.58, ("metin_yok",)
    # Düz anlatım/tanım maddeleri: soru kipi ve şık kümesi yoktur.
    konu_guveni = 0.72 + min(0.22, s["paragraf"] * 0.025)
    if "ders not" in kucuk or "konu anlat" in kucuk:
        konu_guveni = max(konu_guveni, 0.94)
    return "konu", konu_guveni, ("soru_kaniti_zayif",)


# Ders kitaplarında ETKİNLİK sayfası: numaralı maddeler soru değil, uygulama
# ADIMLARIDIR ("4-6 kişilik gruplar oluşturunuz", "adrese giriniz",
# "arkadaşlarınızla paylaşınız"). Bunlar da düzgün artan bir zincir kurar ve
# zincir kanıtı onları soru sanırdı: ölçüldü, 9pdf s69'da ("11. Etkinlik")
# altın 0 soru derken motor 6 kutu teslim ediyordu, altısı da zincir kanıtlı.
# "Yönerge" TEK BAŞINA ayırt edici DEĞİL — gerçek soru sayfaları da
# "Yönerge: Aşağıdaki soruları..." ile başlıyor (9pdf s89, s113). Ayırt eden
# işaret etkinlik/performans görevi başlığıdır.
ETKINLIK_BASLIGI = re.compile(
    r"^\s*(?:\d{1,2}\s*[.)]\s*)?(?:etkinlik\b|performans\s+görev|"
    r"uygulama\s+basamak)", re.I)


def _etkinlik_sayfasi_mi(satirlar):
    return any(ETKINLIK_BASLIGI.match(m) for m, _k, *_ in satirlar)


def _guclu_zincir_uyeleri(meta, G, asgari=5):
    """Sayfanın doğrulanmış artan numara zincirinin üye numaraları.

    İki şart birlikte aranır:
      * zincir en az `asgari` üyeli (tek tük aykırı numara zincir sayılmaz),
      * üyeler aynı sol hizada (±G*0,025) — şekil içi "1. Tur, 2. Tur"
        etiketleri ya da sayfa numarası bu şartı sağlayamaz.

    Boş küme döner (yani hiçbir şey değişmez) zincir zayıfsa. `meta` okuma
    sırasındadır; `en_uzun_zincir` bu sıradaki en uzun artan alt-diziyi verir.

    Dönüş NUMARA DEĞERİ değil KUTU KİMLİĞİ kümesidir: aynı numara bir sayfada
    birden çok kez üretilebiliyor (bölünme hatası) ve numaraya göre eşleşme
    mükerrer kutuya da kanıt yazardı — ölçüldü, 9pdf s113'te numaralar
    [1,2,2,3,3,4,5,6] gelip precision düşüyordu. Zincir her numarayı bir kez
    içerir; kanıt yalnız zincirin GERÇEK üyesine yazılmalıdır."""
    adaylar = [m for m in meta if not m.devam_aday and m.numara is not None]
    if len(adaylar) < asgari:
        return frozenset()
    idx = en_uzun_zincir([m.numara for m in adaylar])
    if len(idx) < asgari:
        return frozenset()
    uyeler = [adaylar[i] for i in idx]
    sol = sorted(m.kutu[0] for m in uyeler)
    referans = sol[len(sol) // 2]          # medyan sol kenar
    hizali = [m for m in uyeler if abs(m.kutu[0] - referans) <= G * 0.025]
    if len(hizali) < asgari:
        return frozenset()
    return frozenset(tuple(m.kutu) for m in hizali)


def _soru_turu_belirle(satirlar, kutu, pay, fmt):
    ic = _bolge_satirlari(satirlar, kutu[1], kutu[3],
                          kutu[0], kutu[2], pay)
    metinler = [m for m, _ in ic]
    metin = " ".join(metinler)
    harfler = {h for m in metinler for h in _sik_harfleri(m)}
    if re.search(r"eşleştir|eslestir", metin, re.I):
        return "eşleştirme"
    if len(harfler) >= 3:
        return "çoktan_seçmeli"
    if re.search(r"do[ğg]ru\s*[-/]?\s*yanl[ıi]ş|\bD\s*[/|]\s*Y\b",
                 metin, re.I):
        return "doğru_yanlış"
    yazma = any(NOKTALI_SATIR.search(m) and not TOC_LIDER.search(m)
                for m in metinler)
    if re.search(r"yaz[ıi]n[ıi]z|aç[ıi]klay[ıi]n[ıi]z|çiziniz|gösteriniz|"
                 r"doldurunuz|belirtiniz|neden", metin, re.I):
        return "açık_uçlu"
    if yazma or re.search(r"\bnedir\b|kaçt[ıi]r|bulunuz|tamamlay[ıi]n[ıi]z",
                          metin, re.I):
        return "kısa_cevap"
    return {
        "coktan_secmeli": "çoktan_seçmeli",
        "acik_uclu": "açık_uçlu",
    }.get(fmt, "karma")


def _adaylari_zenginlestir(sayfa, satirlar, meta, fmt, sayfa_rolu=None,
                           tekrar_satirlari=()):
    """Adayları soru türü, kanıt, uyarı ve güven puanıyla zenginleştirir."""
    G, Y = max(1.0, sayfa.genislik), max(1.0, sayfa.yukseklik)
    pay = G * 0.012
    rol, _, _ = _sayfa_rolu_belirle(satirlar) if sayfa_rolu is None \
        else (sayfa_rolu, 1.0, ())
    duzen = getattr(sayfa, "_v22_sutun_kalibrasyonu", None)
    tam_genislik_bolgeleri = tuple(
        b for b in (getattr(sayfa, "_v3_duzen_bolgeleri", ()) or ())
        if b.get("yontem") == "capraz_soru_satiri"
        and len(b.get("bantlar") or ()) == 1)
    tekrar = set(tekrar_satirlari or ())
    # Soru-özel model bölgeleri (varsa) aday kanıtı/birleşme koruması için.
    sm_bolgeler = _soru_modeli_bolgeleri(sayfa)
    sm_body = [b for b in sm_bolgeler if b["sinif"] == "question_body"
               and b["guven"] >= 0.30]
    sm_anchor = [b for b in sm_bolgeler if b["sinif"] == "question_anchor"]
    sm_cozum = [b for b in sm_bolgeler
                if b["sinif"] == "solution_or_answer" and b["guven"] >= 0.40]
    sm_kullanildi = False
    # Sayfanın DOĞRULANMIŞ artan numara zincirinin üyeleri. "Doğrulanmış" =
    # en az 5 üye VE üyeler aynı sol hizada (±G*0.025). Bu iki şart birlikte,
    # şekil içi "1. Tur, 2. Tur" etiketlerinin veya sayfa numarasının zincir
    # sanılmasını engeller. Aşağıda hem güven kanıtı hem de "aşırı küçük"
    # cezasının vetosu olarak kullanılır.
    guclu_zincir_uyeleri = (
        frozenset() if _etkinlik_sayfasi_mi(satirlar)
        else _guclu_zincir_uyeleri(meta, G))
    cikti = []
    for m in meta:
        if m.devam_aday:
            cikti.append(m._replace(
                soru_turu="devam", sayfa_rolu=rol, guven=0.60,
                kanitlar=("numarasiz_devam",), uyarilar=("devam_adayi",),
                inceleme_durumu="incele"))
            continue
        ic = _bolge_satirlari(satirlar, m.kutu[1], m.kutu[3],
                              m.kutu[0], m.kutu[2], pay)
        metinler = [t for t, _ in ic]
        metin = " ".join(metinler)
        harfler = {h for t in metinler for h in _sik_harfleri(t)}
        govde = bool(SORU_GOVDE.search(metin))
        yazma = any(NOKTALI_SATIR.search(t) and not TOC_LIDER.search(t)
                    for t in metinler)
        metin_uz = len(re.sub(r"\W+", "", metin, flags=re.UNICODE))
        w = max(0.0, m.kutu[2] - m.kutu[0]) / G
        h = max(0.0, m.kutu[3] - m.kutu[1]) / Y
        alan = w * h
        ic_numaralar = [(no, nk) for no, nk, _ in numara_adaylari(satirlar)
                        if m.kutu[0] - pay <= (nk[0] + nk[2]) / 2
                        <= m.kutu[2] + pay
                        and m.kutu[1] - pay <= (nk[1] + nk[3]) / 2
                        <= m.kutu[3] + pay]
        if ic_numaralar:
            # Şekil etiketleri ("1.", "2.") ve metin içindeki "2. üründe"
            # gibi alt numaralar gerçek soru çapalarından daha içeridedir.
            # Birleşme korumasında yalnız adayın soru numarasıyla aynı sol
            # hizada kalan üst-düzey çapaları say. İki gerçek birleşmiş soru
            # aynı sütun soluna hizalandığından güvenlik koruması devam eder.
            referans_x = (m.numara_kutu[0]
                          if m.numara_kutu is not None
                          else min(nk[0] for _no, nk in ic_numaralar))
            ic_numaralar = [
                (no, nk) for no, nk in ic_numaralar
                if abs(nk[0] - referans_x) <= G * 0.025
            ]
        ic_numara = [no for no, _ in ic_numaralar]
        puan = 0.20
        kanitlar, uyarilar = [], []
        if m.numara is not None:
            puan += 0.24; kanitlar.append("soru_numarasi")
        if govde:
            puan += 0.20; kanitlar.append("soru_yonergesi")
        if len(harfler) >= 4:
            puan += 0.28; kanitlar.append("tam_sik_kumesi")
        elif len(harfler) >= 2:
            puan += 0.15; kanitlar.append("sik_kumesi")
        if yazma:
            puan += 0.15; kanitlar.append("cevap_alani")
        if metin_uz >= 30:
            puan += 0.08; kanitlar.append("yeterli_metin")
        if 0.10 <= w <= 0.90 and 0.035 <= h <= 0.70:
            puan += 0.08; kanitlar.append("uygun_geometri")
        # Zincir üyeliği BAĞIMSIZ ve güçlü bir kanıttır: bir numara sayfanın
        # doğrulanmış artan zincirinin üyesiyse ve kardeşleriyle aynı sol
        # hizadaysa, blok tek başına zayıf görünse bile (tek satır, şık yok,
        # soru kipi yok) sorudur — 20 kardeşi onu doğrular.
        # Ölçüldü (12meb s186): doğru-yanlış tablosunun 21-25 numaralı
        # satırları ve 32 numaralı soru HİÇBİR UYARI TAŞIMADAN 0,520 ile
        # GUVEN_INCELE'nin (0,55) 0,03 altında kalıp tümüyle reddediliyordu.
        if tuple(m.kutu) in guclu_zincir_uyeleri:
            puan += 0.15; kanitlar.append("zincir_uyeligi")
        if getattr(sayfa, "resim_kutu_plani", None):
            puan = max(puan, 0.88); kanitlar.append("gomulu_soru_gorseli")

        # V2.2: aday güveni yalnız metne değil, onu sınırlayan sütun
        # geometrisinin yöntemler-arası uzlaşmasına da bağlıdır. Yüksek
        # uzlaşma küçük bir doğrulama kanıtıdır; düşük uzlaşma hiçbir adayı
        # kullanıcı görmeden otomatik bankaya geçiremez.
        if duzen is not None:
            if duzen.guven >= 0.82:
                puan += 0.04
                kanitlar.append("sutun_uzlasmasi")
            elif duzen.guven < 0.55:
                puan -= 0.16
                uyarilar.append("dusuk_duzen_guveni")
            elif duzen.guven < 0.70:
                puan -= 0.07
                uyarilar.append("sutun_uzlasmazligi")
            if abs(duzen.egiklik_derece) >= 1.0:
                uyarilar.append("egik_kaynak")
            if duzen.bolgesel_gecis:
                kanitlar.append("bolgesel_duzen_modeli")

        # Soru-özel model kanıtı (varsa). Güvenlik değişmezi: model kanıtı
        # tek başına ne 0.55 ne 0.82 eşiğini geçirebilir (taban 0.20 + en
        # çok 0.16); Gemini yedeğiyle aynı "yerel doğrulama şart" felsefesi.
        if sm_body:
            en_iyi = max(sm_body, key=lambda b: _kutu_iou(m.kutu, b["kutu"]))
            iou = _kutu_iou(m.kutu, en_iyi["kutu"])
            if iou >= 0.55:
                puan += min(0.12, 0.06 + en_iyi["guven"] * 0.12)
                kanitlar.append("soru_modeli_dogruladi")
                sm_kullanildi = True
            elif iou >= 0.30:
                uyarilar.append("soru_modeli_sinir_uyusmazligi")
                sm_kullanildi = True
            # Anchor merkezi adayın üst %35'ine düşüyorsa numara başı kanıtı.
            ust_sinir = m.kutu[1] + (m.kutu[3] - m.kutu[1]) * 0.35
            for a in sm_anchor:
                acx = (a["kutu"][0] + a["kutu"][2]) / 2
                acy = (a["kutu"][1] + a["kutu"][3]) / 2
                if (m.kutu[0] - pay <= acx <= m.kutu[2] + pay
                        and m.kutu[1] - pay <= acy <= ust_sinir):
                    puan += 0.04
                    kanitlar.append("soru_modeli_capasi")
                    sm_kullanildi = True
                    break
            # Birleşme koruması: aday ≥2 ayrık body'yi her birinin ≥%60'ıyla
            # kapsıyorsa iki soru tek kutuda birleşmiş olabilir → otomatiğe
            # geçemez (banka birleşik kutu kabul etmesin).
            kapsanan = []
            for b in sm_body:
                bx0, by0, bx1, by1 = b["kutu"]
                galan = max(0.0, min(m.kutu[2], bx1) - max(m.kutu[0], bx0)) \
                    * max(0.0, min(m.kutu[3], by1) - max(m.kutu[1], by0))
                balan = max(1.0, (bx1 - bx0) * (by1 - by0))
                if b["guven"] >= 0.50 and galan / balan >= 0.60:
                    kapsanan.append(b)
            kapsanan_capalar = []
            # Model, şekil içindeki numaralı açıklama satırlarını da anchor
            # sanabilir. Gerçek soru başlangıçları aynı sütun soluna hizalıdır;
            # birleşme kanıtında yalnız güvenilir yerel numarayla hizalı model
            # anchor'larını kullan.
            anchor_referans_x = (
                m.numara_kutu[0] if m.numara_kutu is not None
                else m.kutu[0])
            for a in sm_anchor:
                acx = (a["kutu"][0] + a["kutu"][2]) / 2
                acy = (a["kutu"][1] + a["kutu"][3]) / 2
                if (m.kutu[0] - pay <= acx <= m.kutu[2] + pay
                        and m.kutu[1] - pay <= acy <= m.kutu[3] + pay
                        and abs(a["kutu"][0] - anchor_referans_x)
                        <= G * 0.02):
                    kapsanan_capalar.append(a)
            # Body modeli, tek ve uzun bir sorunun "şekil üstü / şekil altı"
            # parçalarını sıklıkla iki gövde gibi döndürür. Normal durumda iki
            # ayrık anchor bunu doğrular. Ancak anchor modeli ikinci numarayı
            # kaçırmış olsa bile iki yüksek güvenli ve anlamlı boyutlu ayrık
            # body tek otomatik kutuda kalamaz: strict kapı incelemeye alır.
            if (len(kapsanan) >= 2
                    and _model_bolgeleri_ayrik_mi(kapsanan, G, Y)
                    and (_model_bolgeleri_ayrik_mi(
                            kapsanan_capalar, G, Y)
                         or _guclu_ayrik_model_govdeleri_mi(
                            kapsanan, G, Y))):
                puan = min(puan, GUVEN_OTOMATIK - 0.01)
                uyarilar.append("soru_modeli_birlesme_riski")
                sm_kullanildi = True
        # Çözüm bölgesi cezası (çözümlü olmayan belgede çözüm bölgesine düşen
        # aday muhtemelen soru değil).
        if sm_cozum and fmt != "cozumlu":
            for b in sm_cozum:
                bx0, by0, bx1, by1 = b["kutu"]
                galan = max(0.0, min(m.kutu[2], bx1) - max(m.kutu[0], bx0)) \
                    * max(0.0, min(m.kutu[3], by1) - max(m.kutu[1], by0))
                malan = max(1.0, (m.kutu[2] - m.kutu[0])
                            * (m.kutu[3] - m.kutu[1]))
                if galan / malan >= 0.50:
                    puan -= 0.10
                    uyarilar.append("soru_modeli_cozum_bolgesi")
                    sm_kullanildi = True
                    break

        # Birleşme koruması (ML'siz): kutu içinde dikeyde ayrık ≥2 numara
        # çapası varsa iki soru tek kutuda birleşmiş olabilir → otomatiğe
        # geçemez. (dogrula.py 'birlesme' anomalisinin tespit-tarafı karşılığı.)
        if len(ic_numaralar) >= 2:
            yler = sorted((nk[1] + nk[3]) / 2 for _, nk in ic_numaralar)
            if any(yler[i + 1] - yler[i] >= Y * 0.05
                   for i in range(len(yler) - 1)):
                puan = min(puan, GUVEN_OTOMATIK - 0.01)
                uyarilar.append("coklu_numara_icerik")

        # Yatay birleşme koruması: bir aday birden çok bağımsız sütunun
        # anlamlı kısmını kaplıyorsa, yalnız yerelleştirilmiş gerçek
        # tam-genişlik bölgesinde otomatik kabul edilebilir. Tespit
        # katmanındaki hard-clamp'in son savunmasıdır; profil hizası ya da
        # ikinci görüş bu fiziksel riski sonradan otomatiğe yükseltemez.
        if duzen is not None and len(duzen.bantlar) >= 2:
            kutu_gen = max(1.0, m.kutu[2] - m.kutu[0])
            kaplanan_bant = sum(
                min(m.kutu[2], b) - max(m.kutu[0], a) > kutu_gen * 0.20
                for a, b in duzen.bantlar)
            # Tam-genişlik kararı sorunun BAŞLADIĞI yerde verilir. Büyük bir
            # şekil/tablo adayın altını, kalibrasyonun tahmini geçiş
            # aralığından aşağı uzatabilir; kutu merkezini kullanmak böyle
            # meşru soruyu yanlış riskli yapardı. Numara çapası varsa onun
            # merkezi, yoksa kutunun üst %8 noktası güvenli referanstır.
            referans_y = ((m.numara_kutu[1] + m.numara_kutu[3]) / 2
                          if m.numara_kutu is not None
                          else m.kutu[1] + (m.kutu[3] - m.kutu[1]) * 0.08)
            dogrulanmis_capraz = any(
                float(b["y0"]) <= referans_y <= float(b["y1"])
                for b in tam_genislik_bolgeleri)
            if kaplanan_bant >= 2 and not dogrulanmis_capraz:
                puan = min(puan, 0.78)
                uyarilar.append("sutun_tasma_riski")

        if w >= 0.88 and h >= 0.76:
            puan -= 0.38; uyarilar.append("tam_sayfaya_yakin")
        elif h >= 0.82 and (len(ic_numara) != 1
                            or not (govde and len(harfler) >= 3)):
            puan -= 0.25; uyarilar.append("tam_sutuna_yakin")
        # "Aşırı küçük" eşiği de sayfa yüzdesidir ve yoğun dizgide yanılır:
        # 12meb s186'da 19 pt'lik meşru sorular h=0,0244 ile 0,025 eşiğinin
        # hemen altında kalıp −0,45 yiyordu. Zincirin doğrulanmış üyesi olan
        # bir kutu, kardeşleriyle aynı boyuttaysa dekorasyon değildir; ceza
        # yalnız GENİŞLİK yönünde (gerçekten şerit gibi) uygulanır.
        if w < 0.08 or (h < 0.025
                        and tuple(m.kutu) not in guclu_zincir_uyeleri):
            puan -= 0.45; uyarilar.append("asiri_kucuk")
        if metin_uz < 12 and not getattr(sayfa, "resim_kutu_plani", None):
            puan -= 0.30; uyarilar.append("metin_kaniti_yok")
        if metinler and tekrar:
            tekrar_sayi = sum(_profil_norm(t) in tekrar for t in metinler)
            if tekrar_sayi / max(1, len(metinler)) >= 0.60:
                puan -= 0.35; uyarilar.append("tekrarlanan_kenar_bandi")
        cozum_blok = bool(metinler and COZUM_DESENI.match(metinler[0]))
        if cozum_blok and not govde and len(harfler) < 3:
            puan = min(puan, 0.30); uyarilar.append("yalniz_cozum")
        # "Soru dışı sayfa" cezası BELGENİN AMACINA GÖRELİDİR. Çözüm
        # kitabında çözüm sayfası aykırı bir sayfa değil, İÇERİK sayfasıdır;
        # kesilmek istenen birim tam da çözüm bloğudur. Bu ayrım olmadan
        # cozumler1'de mükemmel kanıtlı kutular (soru_numarasi + yeterli_metin
        # + uygun_geometri + belge_numara_hizasi) 0,225 güvenle reddediliyor
        # ve sayfa tümüyle boş kalıyordu; ölçüldü: s41'de 11 kutunun 11'i
        # kayboluyor, count_recall 0,625 → düzeltmeyle 0,900.
        aykiri_roller = {"kapak", "içindekiler", "çözüm", "cevap_anahtari"}
        if fmt == "cozumlu":
            aykiri_roller.discard("çözüm")
        if rol in aykiri_roller:
            puan = min(puan, 0.20); uyarilar.append("soru_disinda_sayfa")
        elif rol == "konu":
            # Güçlü, bağımsız soru kanıtı konu sayfasındaki alıştırmayı
            # kurtarabilir; sıradan numaralı paragraf ise otomatik reddedilir.
            # DENENDİ VE GERİ ALINDI (2026-07-25): zincir üyeliğini üçüncü bir
            # kurtarma yolu yapmak 9pdf s89'daki "Kontrol Noktası" bulmacasını
            # kurtarmadı (iki soru grubunun sol hizası 15,2 pt ayrık, tolerans
            # 14,25 pt) ama 12meb'e +12, 9pdf'e +8 ALTINSIZ sayfa kutusu ekledi.
            # Ölçülebilir faydası olmayan, ölçülemeyen kutu üreten değişiklik
            # kabul edilmez — projenin dokümante edilmiş kuralı budur.
            # Sıfır sayfa sorunu için bkz. kalite/sifir_sayfa_teshisi.md.
            tavan = 0.70 if (govde and (len(harfler) >= 3 or yazma)) else 0.35
            puan = min(puan, tavan)
            uyarilar.append("konu_sayfasinda_aday")
        if duzen is not None and duzen.guven < 0.55:
            # İçerik kanıtı çok güçlü olsa bile sınır geometrisi güvensizse
            # komşu sorunun içeri girip girmediği otomatik doğrulanamaz.
            puan = min(puan, GUVEN_OTOMATIK - 0.01)
        puan = round(max(0.0, min(0.99, puan)), 3)
        durum = ("otomatik" if puan >= GUVEN_OTOMATIK else
                 "incele" if puan >= GUVEN_INCELE else "reddedildi")
        cikti.append(m._replace(
            soru_turu=_soru_turu_belirle(satirlar, m.kutu, pay, fmt),
            sayfa_rolu=rol, guven=puan, kanitlar=tuple(dict.fromkeys(kanitlar)),
            uyarilar=tuple(dict.fromkeys(uyarilar)), inceleme_durumu=durum))

    # Yüksek örtüşme iki alternatifin aynı soruyu temsil ettiğini gösterir;
    # ikisini de otomatik bankaya göndermek yerine incelemeye indir.
    for i in range(len(cikti)):
        if cikti[i].devam_aday:
            continue
        if any(j != i and not cikti[j].devam_aday
               and _ortusme_orani(cikti[i].kutu, cikti[j].kutu) >= 0.35
               for j in range(len(cikti))):
            yeni = min(cikti[i].guven, 0.78)
            uy = tuple(dict.fromkeys(cikti[i].uyarilar + ("aday_cakismasi",)))
            cikti[i] = cikti[i]._replace(
                guven=yeni, uyarilar=uy,
                inceleme_durumu=("incele" if yeni >= GUVEN_INCELE
                                  else "reddedildi"))
    # Kararlı kimlik ve karar alanları tek noktada doldurulur. Böylece
    # örtüşme gibi sonradan güveni düşüren adımlar onay durumuyla çelişmez.
    duzen_bolgeleri = tuple(getattr(sayfa, "_v3_duzen_bolgeleri", ()) or ())
    yontem_taban = ["vision_ocr" if sayfa.raster else "pdf_text"]
    if getattr(sayfa, "resim_kutu_plani", None):
        yontem_taban.append("embedded_image")
    if duzen is not None:
        yontem_taban.extend(str(x) for x in duzen.kanitlar)
    if sm_kullanildi:
        yontem_taban.append("question_specific_model")
    sonuc = []
    for m in cikti:
        onay = {"otomatik": "otomatik", "incele": "bekliyor",
                "reddedildi": "reddedildi"}.get(
                    m.inceleme_durumu, "bekliyor")
        risk = list(m.uyarilar)
        if m.inceleme_durumu == "incele":
            risk.append("kalite_esigi_altinda")
        elif m.inceleme_durumu == "reddedildi":
            risk.append("aday_reddedildi")
        sonuc.append(m._replace(
            karar_kimligi=(m.karar_kimligi or
                            karar_kimligi(sayfa, m.kutu, m.numara)),
            kalibre_guven=(m.guven if m.kalibre_guven is None
                            else m.kalibre_guven),
            onay_durumu=onay,
            kaynak_yontemler=tuple(dict.fromkeys(
                tuple(m.kaynak_yontemler) + tuple(yontem_taban))),
            risk_nedenleri=tuple(dict.fromkeys(
                tuple(m.risk_nedenleri) + tuple(risk))),
            duzen_bolgeleri=(m.duzen_bolgeleri or duzen_bolgeleri)))
    return sonuc


_BASLIK_SOZCUK = re.compile(r"[A-Za-zÇĞİÖŞÜçğıöşü]+")


def test_basliklari(satirlar):
    """Sayfadaki TEST bölümü başlıklarını bulur.
    Dönüş: [(test_no|None, kutu, metin)] okuma-sırası bağımsız (çağıran
    bant/y'ye göre konumlandırır).

    Başlık kabul koşulları (yanlış-pozitif eleme):
    - TEST/DENEME/TARAMA kökü var; satır kısa (≤28 karakter);
    - soru-gövdesi kalıbı yok ("... test edilir mi?" cümlesi elenmez ama
      SORU_GOVDE'siz kısa düz metin için ek koruma ↓);
    - tüm sözcükler büyük harfle başlıyor ("TEST 5", "Kazanım Testi 3"
      geçer; "test edebilir" düz metni elenir);
    - cevap anahtarı başlığı değil (o sayfalar ayrıca ele alınır)."""
    bulunan = []
    for metin, kutu, _ in satirlar:
        m = metin.strip()
        if len(m) > 28 or not TEST_KOK.search(m):
            continue
        if SORU_GOVDE.search(m) or CEVAP_BASLIK.search(m):
            continue
        sozcukler = _BASLIK_SOZCUK.findall(m)
        if not sozcukler or any(s[0].islower() for s in sozcukler):
            continue
        no = None
        es = TEST_NO_SONEK.search(m) or TEST_NO_ONEK.search(m)
        if es:
            no = int(es.group(1))
        bulunan.append((no, tuple(kutu), m))
    return bulunan


def _devam_adaylari(sayfa, satirlar, bantlar, meta, pay, fmt):
    """Sütun başı 'yetim devam' bölgeleri: bandın İLK kabul edilen kutusunun
    ÜSTÜNDE kalan, numarasız satır grubu. Bugün sessizce atılan bu bölge,
    kirpma_plani'nda önceki sütunun yarım kalan sorusuyla birleştirilebilir.

    Korumalar (yanlış-pozitif önleme): bölgede numara satırı olmamalı;
    çoktan seçmelide en az bir şık satırı olmalı (sayfa başlığı / ünite
    bandı asla 'C) …' içermez); yükseklik bandın içeriğinin %60'ını
    aşmamalı; ≥12 karakter metin olmalı."""
    if fmt in ("slayt", "konu_anlatimi"):
        return []
    G, Y = sayfa.genislik, sayfa.yukseklik
    adaylar = []
    for bi, (ba, bb) in enumerate(bantlar):
        bant_meta = [m for m in meta if m.bant_idx == bi]
        if not bant_meta:
            continue
        ilk_ust = min(m.kutu[1] for m in bant_meta)
        if ilk_ust <= Y * 0.03:            # kutu zaten sayfanın tepesinde
            continue
        ic = _bolge_satirlari(satirlar, 0, ilk_ust - Y * 0.005,
                              ba, bb, pay)
        if not ic:
            continue
        if any(SORU_NO_DESENI.match(m) for m, _ in ic):
            continue                       # numaralı satır → normal bölge
        harfler = frozenset(h for m, _ in ic for h in _sik_harfleri(m))
        metin = " ".join(m for m, _ in ic)
        if len(metin) < 12:
            continue
        if fmt == "coktan_secmeli" and not harfler:
            continue                       # başlık/banner sınıfı elenir
        y0 = min(k[1] for _, k in ic)
        y1 = max(k[3] for _, k in ic)
        bant_ic = _bolge_satirlari(satirlar, 0, Y * 0.97, ba, bb, pay)
        bant_yuk = (max(k[3] for _, k in bant_ic)
                    - min(k[1] for _, k in bant_ic)) if bant_ic else 0
        if not (Y * 0.02 <= y1 - y0 <= 0.6 * max(bant_yuk, 1)):
            continue
        if sayfa.raster:
            sol, sag = ba, bb              # şekil bbox'ı yok → tam şerit
        else:
            sol = max(min(k[0] for _, k in ic) - 4, ba)
            sag = min(max(k[2] for _, k in ic) + 4, bb)
        kutu = (sol, max(0.0, y0 - Y * 0.006), sag, min(Y, y1 + Y * 0.008))
        son = max(ic, key=lambda t: t[1][3])[0]
        adaylar.append(SoruKutu(kutu, bi, None, True, harfler, son,
                                bool(SORU_GOVDE.search(metin))))
    return adaylar


def _ml_sekil_kutulari(sayfa):
    """RasterSayfa için ML şekil bölgeleri [(x0,y0,x1,y1)] — layout
    koordinatları render pikselleriyle 1:1 olduğundan ölçek gerekmez.
    Kapalı/kurulu değil/hata → [] (sezgisel yol aynen çalışır)."""
    if duzen_model is None or not duzen_model.kullanilabilir():
        return []
    try:
        bolgeler = duzen_model.bolgeler_gorsel(
            sayfa.gorsel()[0], duzen_model.kimlik(sayfa.kimlik or ""))
        return [tuple(b["kutu"]) for b in (bolgeler or [])
                if b.get("sinif") in duzen_model.SEKIL_SINIFLARI
                and b.get("guven", 0) >= 0.35]
    except Exception:  # noqa: BLE001
        return []


def _pdf_metin_kutularini_sikilastir(sayfa, meta, satirlar, fmt):
    """Metinli PDF'de soru kutusunu son gerçek içerik satırında kapatır.

    Genel tespit yolu güvenli tarafta kalıp sütunun altına kadar uzayabilir.
    Vektör metin katmanında ise son satır koordinatı kesindir. Çoktan seçmeli
    soruda şeklin altında seçenek metni bulunduğundan bu sınır şekli de kapsar;
    yalnız metnin hemen altında biten gömülü görsel ayrıca korunur. Raster ve
    açık-uçlu belgelerin geniş güvenlik davranışı değişmez.
    """
    if getattr(sayfa, "raster", True) or fmt != "coktan_secmeli":
        return meta
    G, Y = sayfa.genislik, sayfa.yukseklik
    pay = G * 0.012
    gorseller = sayfa.resim_kutulari()
    sonuc = []
    for aday in meta:
        if aday.devam_aday or aday.numara is None:
            sonuc.append(aday)
            continue
        x0, y0, x1, y1 = aday.kutu
        ic = []
        for metin, kutu, _kalin in satirlar:
            sx0, sy0, sx1, sy1 = kutu
            merkez_x = (sx0 + sx1) / 2
            if not (x0 - pay <= merkez_x <= x1 + pay
                    and sy0 >= y0 - Y * 0.004
                    and sy1 <= y1 + Y * 0.002):
                continue
            if sy0 >= Y * 0.82 and ALT_BILGI_DESENI.search(metin):
                continue
            # Alt köşedeki tekrar eden test adı/sayfa numarası içerik değildir.
            if sy0 >= Y * 0.90 and (
                    TEST_KOK.search(metin)
                    or re.fullmatch(r"\s*\d{1,4}\s*", metin)):
                continue
            ic.append((metin, kutu))
        if not ic:
            sonuc.append(aday)
            continue
        # "2025-TYT" gibi tam satır kaynak damgası soru sonunu kesin olarak
        # bildirir. Aynı sütunda damgadan sonra başlayan dipnotu veya yeni
        # konu listesini (örn. "Mantık" + madde dizisi) uzun sorunun parçası
        # sanıp tam sütuna kadar uzatma.
        damga_sonlari = [
            k[3] for metin, k in ic if SINAV_KAYNAK_DAMGASI.match(metin)
        ]
        if damga_sonlari:
            damga_sonu = min(damga_sonlari)
            ic = [(metin, k) for metin, k in ic
                  if k[1] <= damga_sonu + Y * 0.004]
        son = max(k[3] for _m, k in ic)
        # Son metinle temas eden gerçek görseli koru. Metinden çok aşağıdaki
        # dekoratif/arka-plan nesneleri sınırı tekrar sayfa altına taşıyamaz.
        for rx0, ry0, rx1, ry1 in gorseller:
            merkez_x = (rx0 + rx1) / 2
            if (x0 - pay <= merkez_x <= x1 + pay
                    and ry0 <= son + Y * 0.08
                    and ry1 > son):
                son = ry1
        yeni_alt = min(y1, max(
            y0 + Y * 0.03, son + max(3.0, Y * 0.005)))
        if yeni_alt >= y1 - 1.0:
            sonuc.append(aday)
            continue
        yeni_kutu = (x0, y0, x1, yeni_alt)
        harfler, son_metin, govde = _bolge_bilgi(
            satirlar, yeni_kutu, pay)
        sonuc.append(aday._replace(
            kutu=yeni_kutu, sik_harfler=harfler,
            son_metin=son_metin, govde_var=govde))
    return sonuc


def sorulari_tespit_meta(sayfa, fmt="karisik"):
    """Bir sayfadaki soruları meta bilgisiyle bulur.
    Dönüş: (meta, bantlar, sayfa_fmt) — meta: SoruKutu listesi (okuma
    sırasında; devam_aday=True öğeler normal çıktıya girmez), bantlar:
    görsel sütun bantları, sayfa_fmt: sayfa-başı formatı (override sonrası).

    fmt: belge formatı (belge_formati/kalibre_et sonucu). Doğrulama belgenin
    formatına göre yapılır; blok_gecerli_mi bölgesinde geçerli soru kalıbı
    (şık / soru-gövdesi / yazma alanı) olmayan adayları (talimat, başlık,
    konu maddesi, minik parça) format-agnostik eler."""
    onbellek = getattr(sayfa, "_v2_meta_onbellek", None)
    if isinstance(onbellek, dict) and fmt in onbellek:
        return onbellek[fmt]
    satirlar = sayfa.satirlar()
    G, Y = sayfa.genislik, sayfa.yukseklik
    if fmt == "slayt":                      # yatay sunum: sayfa = tek kutu
        meta = [SoruKutu(k, 0, None, False, frozenset(), "", False)
                for k in _slayt_kutusu(sayfa)]
        return _adaylari_zenginlestir(sayfa, satirlar, meta, fmt), \
            [(0.0, G)], fmt
    # HİBRİT görüntü-soru sayfası (sayfalari_yukle önceden çıkardı): her kutu
    # PDF'in gömülü görüntü bloğundan kesin gelir → OCR/sütun/numara sezgisini
    # tümüyle atla, kutuları okuma sırasında olduğu gibi kullan.
    plani = getattr(sayfa, "resim_kutu_plani", None)
    if plani:
        pay = G * 0.012
        asil_numaralar = getattr(sayfa, "resim_kutu_numaralari", ())
        meta = [SoruKutu(
                    k, 0,
                    (asil_numaralar[i] if i < len(asil_numaralar)
                     and asil_numaralar[i] is not None else i + 1),
                    False, *_bolge_bilgi(satirlar, k, pay),
                    numara_kutu=nk)
                for i, (k, nk) in enumerate(plani)]
        return _adaylari_zenginlestir(
            sayfa, satirlar, meta, "coktan_secmeli", sayfa_rolu="soru"), \
            [(0.0, G)], "coktan_secmeli"
    fmt = _sayfa_formati(satirlar, fmt)  # karışık kitaplarda sayfa-başı override
    cozumlu = fmt == "cozumlu"

    # Sütunlar GÖRSEL projeksiyondan (sayfa-başına) → çözümlü/karışık
    # düzenlerde sol+sağ birleşmesi imkânsız (hard-clamp aşağıda).
    bantlar = sayfa_sutunlari(sayfa)
    pay = G * 0.012

    def _bant_idx(x0):
        # Taranmış sayfalarda sağ sütunun numara glifi ayırıcının birkaç
        # piksel soluna taşabilir. Görsel bant güvenilirken bu dar toleransı
        # sağ banda ver; aksi halde yalnız "4." kutusu sol soruya bağlanır.
        if sayfa.raster:
            tol = G * 0.015
            for i in range(len(bantlar) - 1):
                sinir = bantlar[i][1]
                if sinir - tol <= x0 < sinir:
                    return i + 1
        for i, (a, b) in enumerate(bantlar):
            if a - G * 0.02 <= x0 < b:
                return i
        return min(range(len(bantlar)), key=lambda i: abs(x0 - bantlar[i][0]))

    # A1*: doğrulanmış tam-genişlik geçişleri (bkz. duzen_bolgeleri_uret,
    # yontem="capraz_soru_satiri") — sayfa-düzeyi bolgesel_gecis boolean'ı
    # DEĞİL, adayın y-aralığının bu bölgelerle örtüşmesi kontrol edilir.
    _tam_genislik_bolgeler = tuple(
        (b["y0"], b["y1"])
        for b in (getattr(sayfa, "_v3_duzen_bolgeleri", ()) or ())
        if b.get("yontem") == "capraz_soru_satiri")
    _ayrac_sinirlari = tuple(bantlar[i][1] for i in range(len(bantlar) - 1))

    def _satir_supheli_kopru_mu(smetin, k):
        # Bu satırın KENDİSİ bir bant sınırını geçiyor VE satır-ortasında
        # (öz-numarası değil) karşı tarafa düşen bir soru-başlangıcı jetonu
        # taşıyor mu — yani _karsi_bantta_soru_baslangici'nin vetolayacağı
        # türden köprülü bir OCR satırı mı. Tanık aramasında böyle satırlar
        # birbirine tanıklık edemesin diye kullanılır (iki şüpheli satır
        # birbirini doğrulayamaz).
        x0, y0, x1, y1 = k
        if _bant_idx(x0) == _bant_idx(x1):
            return False
        oz = SORU_NO_DESENI.match(smetin)
        oz_bitis = oz.end() if oz else 0
        for es in SATIR_ICI_SORU_BASLANGICI.finditer(smetin):
            if es.start() < oz_bitis:
                continue
            oran = es.start() / max(1, len(smetin))
            tahmini_x = x0 + (x1 - x0) * oran
            if _bant_idx(tahmini_x) != _bant_idx(x0):
                return True
        return False

    def _bagimsiz_tam_genislik_kaniti(by0, by1, haric):
        # duzen_bolgeleri_uret'in "capraz_soru_satiri" kararı (SORU_GOVDE/
        # ORTAK_SORU_ARALIGI + gutter'ı gerçekten aşan bbox) TEK bir köprülü
        # OCR satırından türeyebilir — o satır tam da vetolamaya çalıştığımız
        # şüpheli satırsa (aydin s31: "...yıkıl, 6. Aşağıdakilerden..." hem
        # 'capraz' sayılıyor hem gizli-soru-başlangıcı taşıyor) bölge kanıtı
        # DÖNGÜSEL ve güvenilmezdir. Şüpheli satır HARİÇ, aynı bölgede
        # BAŞKA bir tanık satır (gerçek çok-satırlı PUAN/tam-genişlik
        # başlığı gibi) var mı diye bakılır. Kimlik bbox TAM eşitliği yerine
        # yüksek-örtüşme (IoU>=0.9) ile belirlenir — OCR hakem/ikinci-geçiş
        # konsensüsü aynı satırı ε-farklı koordinatlarla iki kez üretebilir;
        # tam eşitlik böyle bir yinelemeyi yakalayamaz ve şüpheli satır
        # neredeyse-ikizini bağımsız tanık sanabilir. Ayrıca tanık ADAYI
        # kendisi de şüpheli bir köprü satırıysa (iki köprülü satır birbirine
        # tanıklık edemez) geçerli kanıt SAYILMAZ.
        for smetin, k, _ in satirlar:
            if _kutu_iou(k, haric) >= 0.9:
                continue
            if k[3] <= by0 or k[1] >= by1:
                continue
            if not (SORU_GOVDE.search(smetin) or ORTAK_SORU_ARALIGI.match(smetin)):
                continue
            if not any(k[0] <= x - G * 0.045 and k[2] >= x + G * 0.045
                       for x in _ayrac_sinirlari):
                continue
            if _satir_supheli_kopru_mu(smetin, k):
                continue
            return True
        return False

    def _tam_genislik_gecis_dogrulandi(sy0, sy1, haric, smetin=None):
        """Yeni bir sütuna geçiş için yerel, fiziksel kanıt ister.

        Normal bir çapraz soru satırı, doğrulanmış ``capraz_soru_satiri``
        bölgesiyle örtüşüyorsa kendi başına kanıttır. Satır OCR'ın iki sütunu
        yanlışlıkla birleştirdiğini gösteriyorsa ise döngüsel öz-kanıt kabul
        edilmez; aynı bölgede bağımsız ikinci bir tanık gerekir.
        """
        for by0, by1 in _tam_genislik_bolgeler:
            if not (sy0 < by1 and sy1 > by0):
                continue
            if smetin is not None and not _satir_supheli_kopru_mu(
                    smetin, haric):
                return True
            if _bagimsiz_tam_genislik_kaniti(by0, by1, haric):
                return True
        return False

    def _karsi_bantta_soru_baslangici(smetin, sx0, sx1, kaplanan):
        # Satır içinde (satırın KENDİ numarası değil — o zaten SORU_NO_DESENI
        # guard'ından geçer) numara+ayraç+büyük-harf jetonu var mı; varsa
        # karakter oranından kaba x konumu kestirilip (bkz. _numara_on_eki_
        # kutusu ile aynı yöntem) henüz kaplanmamış bir banda düşüp
        # düşmediğine bakılır. Öz-numara "konum 0" ile DEĞİL, SORU_NO_DESENI'nin
        # kendi eşleşme sınırıyla karşılaştırılır — "• 6. Aşağıdaki" gibi tek
        # gürültü-karakterli öneki olan satırlarda öz-numara konum 0'da
        # olmadığından salt "==0" kontrolü satırın kendi başlığını yanlışlıkla
        # gizli-jeton sanıp öz-veto üretebilirdi.
        oz = SORU_NO_DESENI.match(smetin)
        oz_bitis = oz.end() if oz else 0
        for es in SATIR_ICI_SORU_BASLANGICI.finditer(smetin):
            if es.start() < oz_bitis:
                continue
            oran = es.start() / max(1, len(smetin))
            tahmini_x = sx0 + (sx1 - sx0) * oran
            # Asimetri düzeltmesi: yalnız jetonun kendi banda düşüp düşmediğine
            # değil, satırın SOL BAŞLANGICININ da kaplanan bantta olup
            # olmadığına bakılır — satır yabancı (henüz kaplanmamış) bir
            # bantta BAŞLIYORSA, bu satırın başı zaten başka bir sorunun
            # kuyruğudur; jetonun kendisi tesadüfen kaplanan banda düşse bile
            # satır bu adayın meşru devamı sayılmaz.
            if (_bant_idx(tahmini_x) not in kaplanan
                    or _bant_idx(sx0) not in kaplanan):
                return True
        return False

    # Sayfanın üstü iki sütun, altı tam genişlik olabilir. Bir soru başlığı
    # gutter üzerinde aynı yatay satırda devam ediyorsa (ör. solda
    # "6. Aşağıda...", sağda "şekli ... doldurunuz") yalnız O SORU için
    # bağlı sütunları tek bölge say. Uzak, yan yana iki ayrı başlık birleşmez.
    aday_bant_onbellek = {}

    def _aday_bant_araligi(kutu, ilk_bant=None):
        # ilk_bant ANAHTARA DAHİLDİR: aynı kutu bir kez dıştan atanmış bantla,
        # bir kez merkezden türetilen bantla sorulabiliyor. İkisi çeliştiğinde
        # (dar/kaymış kutu) anahtarsız önbellek ilk çağrının sonucunu sessizce
        # ikinciye de döndürüyordu.
        anahtar = (tuple(kutu), ilk_bant)
        if anahtar in aday_bant_onbellek:
            return aday_bant_onbellek[anahtar]
        ilk_bant = (_bant_idx((kutu[0] + kutu[2]) / 2)
                     if ilk_bant is None else ilk_bant)
        kaplanan = {ilk_bant}
        sol, sag = kutu[0], kutu[2]
        ky = (kutu[1] + kutu[3]) / 2
        # OCR aynı başlığı birkaç yatay parçaya ayırabilir; iki kısa geçiş
        # zincirlenmiş parçaları da yakalar.
        for _ in range(2):
            degisti = False
            for smetin, (sx0, sy0, sx1, sy1), _ in satirlar:
                sy = (sy0 + sy1) / 2
                ayni_satir = abs(sy - ky) <= max(Y * 0.006,
                                                (kutu[3] - kutu[1]) * 0.7)
                yatay_bagli = sx0 <= sag + G * 0.018 \
                    and sx1 >= sol - G * 0.018
                if not (ayni_satir and yatay_bagli):
                    continue
                # Aynı y'de karşı sütunda başlayan BAŞKA soru, mevcut başlığın
                # devamı değildir. Önceki kod iki uzun başlık satırı gutter'a
                # yaklaştığında bunları zincirleyip iki sütunu tek tam-sayfa
                # kutusuna dönüştürüyordu (23|24, 25|26 gibi).
                baska_numara = SORU_NO_DESENI.match(smetin)
                if baska_numara and tuple((sx0, sy0, sx1, sy1)) != tuple(kutu):
                    continue
                # A1*: satırın KENDİSİ bir bant sınırını geçiyorsa (aynı OCR
                # satırında iki sütun köprülenmiş olabilir) ve satır-ortası
                # (satır başı değil, üstteki guard onu zaten eler) bir
                # "numara + büyük harfle başlayan sözcük" jetonu henüz
                # kaplanmamış bir banda geometrik düşüyorsa, doğrulanmış bir
                # tam-genişlik geçişi yoksa bu satırı genişletme için
                # KULLANMA (aydin ~22 taşma: "...yıkıl, 6. Aşağıdak" gibi
                # köprülenmiş satırlar birleşik OCR satırını kırar).
                if (_bant_idx(sx0) != _bant_idx(sx1)
                        and _karsi_bantta_soru_baslangici(
                            smetin, sx0, sx1, kaplanan)
                        and not _tam_genislik_gecis_dogrulandi(
                            sy0, sy1, (sx0, sy0, sx1, sy1), smetin)):
                    continue
                yeni_bant = _bant_idx((sx0 + sx1) / 2)
                # Temel güvenlik değişmezi: bağımsız sütunlar yalnız aynı
                # y-hizasında ve birbirine yakın satırlar diye birleşemez.
                # Yeni bir banda geçiş ancak V3'ün yerelleştirdiği gerçek
                # tam-genişlik bölgesinde mümkündür. Bu kural, OCR'ın yan
                # yana iki soruyu ayrı satırlara bölüp aynı y'de döndürdüğü
                # durumda da çalışır; satır-içi numara kalıbına bağımlı
                # değildir.
                if yeni_bant not in kaplanan \
                        and not _tam_genislik_gecis_dogrulandi(
                            sy0, sy1, (sx0, sy0, sx1, sy1), smetin):
                    continue
                if yeni_bant not in kaplanan or sx0 < sol or sx1 > sag:
                    kaplanan.add(yeni_bant)
                    sol, sag = min(sol, sx0), max(sag, sx1)
                    degisti = True
            if not degisti:
                break
        sonuc = (min(kaplanan), max(kaplanan))
        aday_bant_onbellek[anahtar] = sonuc
        return sonuc

    # Adaylar: numara satırları, ait oldukları banda atanır. Hizalama filtresi
    # YOK — sütun sınırları zaten numara kümelerinden türediği için numara
    # bandın herhangi bir yerinde olabilir (özellikle 3+ sütunda ORTA sütun
    # numarası bandın ortasında kalır). Sahteler y-yayılım + blok_gecerli_mi +
    # artan-zincir ile elenir.
    def _meta(kutu, numara, devam=False, numara_kutu=None, kanit=(),
              bant_idx=None):
        # Kırpma kutusu, son sözcüğü kesmemek için sütun ayıracının birkaç
        # punto dışına genişleyebilir. Okuma sırası sütunu bu genişletilmiş
        # x0'dan yeniden türetilirse sağ sütun yanlışlıkla sola taşınır ve
        # numara sıfırlaması sahte bir yeni test açar. Adayın özgün sütununu
        # bilen çağıran onu açıkça korur; diğer kurtarma yolları eski
        # geometri-tabanlı davranışta kalır.
        bi = _bant_idx(kutu[0]) if bant_idx is None else int(bant_idx)
        return SoruKutu(kutu, bi, numara, devam,
                        *_bolge_bilgi(satirlar, kutu, pay),
                        numara_kutu=numara_kutu,
                        sinir_kanitlari=tuple(kanit))

    basliklar = test_basliklari(satirlar)   # TEST bölüm başlıkları (varsa)

    # Çözümlü sayfada 'Soru N :' / 'Çözüm N' çözüm çapaları da kesim noktası
    # olur → her çözüm ayrı kesilir (yoksa sayfa 1-2 dev bloğa iner).
    tum_num = numara_adaylari(satirlar, cozum=cozumlu)  # + alt sınır için
    ust_duzey_numara_kutulari = set()
    if fmt == "acik_uclu":
        # Ayrı satırdaki soru numaraları varsa gövde içindeki numaralı önerme,
        # eşleştirme tablosu ve cevap çizgilerini çapa sayma. Aynı temiz
        # çapalar sütun geometrisini de düzeltir: tablonun iç boşlukları sahte
        # dar sütun üretse bile soru gövdesi gerçek sol/sağ banda yayılır.
        temiz_num = _yalin_numara_adaylari(satirlar, tum_num, G)
        if temiz_num != tum_num:
            ust_duzey_numara_kutulari = {tuple(a[1]) for a in temiz_num}
        tum_num = temiz_num
        temiz_kumeler = []
        for _, kutu, _ in sorted(tum_num, key=lambda a: a[1][0]):
            x, y = kutu[0], kutu[1]
            if temiz_kumeler and x - temiz_kumeler[-1][-1][0] <= G * 0.06:
                temiz_kumeler[-1].append((x, y))
            else:
                temiz_kumeler.append([(x, y)])
        temiz_kumeler = [k for k in temiz_kumeler if len(k) >= 2
                         and max(p[1] for p in k) - min(p[1] for p in k)
                         > Y * 0.12]
        if len(temiz_kumeler) >= 2:
            # Numara x'i sütunun MERKEZİ değil sol başlangıcıdır. Bu yüzden
            # iki numara x'inin orta noktası gerçek sınır değildir (ör. 50 ve
            # 330 için 190, soru gövdesini ortadan keser). Her yeni sütun,
            # kendi üst-düzey numarasının hemen solunda başlar.
            merkezler = [_medyan_x(k) for k in temiz_kumeler]
            kenarlar = [0.0]
            for x in merkezler[1:]:
                kenarlar.append(max(kenarlar[-1] + G * 0.06,
                                    x - G * 0.004))
            kenarlar.append(G)
            bantlar = [(kenarlar[i], kenarlar[i + 1])
                       for i in range(len(kenarlar) - 1)]
            aday_bant_onbellek.clear()

    if not sayfa.raster and len(tum_num) >= 2:
        # Metinli PDF'de gerçek soru numaraları her sütunda ortak bir sol
        # hizaya sahiptir. Şekil/tablo içindeki "1. Tur, 2. Tur..." gibi
        # numaralar daha içeridedir; bunlar alt sınır adayı kalırsa gerçek
        # soruyu şeklin ortasında keser. Her banttaki en soldaki kararlı
        # kümeyi koru. Tek adaylı/esnek sayfalarda eski davranış sürer.
        # en_uzun_zincir İNDEKS döndürür; verilen listeye göre çözülmeli.
        _sayilar = [n for n, _s, _k in tum_num if n is not None]
        zincir_numaralari = {_sayilar[i] for i in en_uzun_zincir(_sayilar)}
        hizali = []
        for bi, (ba, bb) in enumerate(bantlar):
            bant_adaylari = [
                a for a in tum_num
                if bi == _bant_idx((a[1][0] + a[1][2]) / 2)
            ]
            if not bant_adaylari:
                continue
            lider_x = min(a[1][0] for a in bant_adaylari)
            kume = [
                a for a in bant_adaylari
                if a[1][0] <= lider_x + G * 0.025
            ]
            # "En soldaki küme kazanır" kuralı MEŞRU bir soru grubunu da
            # atabiliyor: bir sayfada iki soru bloğu farklı girintide
            # dizilebilir. Ölçüldü (12meb s186): üstteki 7 satırlık
            # doğru-yanlış tablosu x0=78,7'de, alttaki 15 boşluk-doldurma
            # sorusu x0=47,2'de; tolerans G×0,025=13,8 olduğu için üst blok
            # tümüyle eleniyor ve sonra tek dev numarasız kutuya yutuluyordu.
            # İkinci bir küme ancak KENDİ İÇİNDE hizalıysa (≥3 üye) ve
            # üyeleri sayfanın doğrulanmış artan zincirine katılıyorsa
            # korunur — şekil içi "1. Tur, 2. Tur" etiketleri bu iki şartı
            # birden sağlayamaz, filtrenin asıl amacı korunmuş olur.
            kalan = [a for a in bant_adaylari if a not in kume]
            for grup in _x_hiza_kumeleri(kalan, G * 0.025):
                if len(grup) < 3:
                    continue
                zincir_uye = sum(1 for a in grup if a[0] in zincir_numaralari)
                if zincir_uye >= 3:
                    kume.extend(grup)
            hizali.extend(kume or bant_adaylari)
        if len(hizali) >= 2:
            tum_num = hizali

    # Numara satırı bbox'ı çoğu PDF'de yalnız "24." değil tüm ilk soru
    # satırını kapsar. Sağ sütunun x0'ı gutter'ın birkaç punto soluna taşabilir;
    # x0 ile atamak onu yanlışlıkla sol banda koyar. Satır merkezi doğru sütun
    # kanıtıdır ve gerçek tam-genişlik başlık aşağıdaki bağlama adımında yine
    # gerekli bantlara genişletilir.
    ham = [(numara, _bant_idx((kutu[0] + kutu[2]) / 2), kutu)
           for numara, kutu, _ in tum_num]
    if not ham:
        # Numara yok (ör. başlıkla ayrılan sorular) → her sütunda büyük dikey
        # boşluklarla blok segmentasyonu.
        meta = [_meta(k, None) for k in
                _blok_segmentasyon(sayfa, bantlar, satirlar, pay, fmt)]
        meta += _devam_adaylari(sayfa, satirlar, bantlar, meta, pay, fmt)
        meta = _pdf_metin_kutularini_sikilastir(
            sayfa, meta, satirlar, fmt)
        return _adaylari_zenginlestir(sayfa, satirlar, meta, fmt), \
            bantlar, fmt

    ham.sort(key=lambda a: (a[1], a[2][1]))  # okuma sırası: sütun → yukarı
    tum_pos = [(a[1], a[2][1]) for a in ham]  # filtre ÖNCESİ konumlar

    # Zincir seçiminden ÖNCE, kaba bölgesinde geçerli-soru kalıbı olmayan
    # adayları ele (sayfa başı numaralı TALİMATLAR, konu başlıkları, tanım
    # maddeleri). Böylece artan-zincir gerçek soruları seçer.
    # Sayfada doğrulanmış artan numara zinciri (≥3 üye) varsa, o zincirin
    # üyeleri için içerik-kalıbı kanıtı gevşetilir: cevap anahtarı / yazılı
    # çözüm kâğıtlarında gövde düz metindir (şık yok, soru kipi yok, yazma
    # alanı yok) ve bu adaylar zincir seçimine hiç ulaşamadan burada
    # eleniyordu. Talimat/başlık/tanım-maddesi korumaları `blok_gecerli_mi`
    # içinde zincir kanıtından ÖNCE çalıştığı için yerinde kalır.
    _zincir_num = [n for n, _s, _k in ham if n is not None]
    guclu_zincir_sayfa = len(en_uzun_zincir(_zincir_num)) >= 3
    # min_yuk eşiğini bu sayfanın kendi çapa dizgisinden türetmek için
    # (bkz. capa_araligi_p25); yalnız zincir kanıtı varken kullanılır.
    _capa_araligi = capa_araligi_p25(
        [k for n, _s, k in ham if n is not None]) if guclu_zincir_sayfa else None
    filtreli = []
    for numara, s, kutu in ham:
        a, b = bantlar[s]
        alt_kaba = Y * 0.97
        for n2, s2, k2 in ham:
            if s2 == s and k2[1] > kutu[1] + 1:
                alt_kaba = min(alt_kaba, k2[1])
        if (blok_gecerli_mi(satirlar, kutu[1], alt_kaba,
                            a, b, pay, Y, fmt,
                            capa_araligi=_capa_araligi,
                            zincir_capasi=(numara is not None
                                           and guclu_zincir_sayfa))
                or tuple(kutu) in ust_duzey_numara_kutulari):
            filtreli.append((numara, s, kutu))
    if filtreli:
        ham = filtreli

    alt_sinir = Y * 0.955  # alt bilgi bandı / sayfa-no bölgesini dışla
    altbilgi_yleri = [k[1] for m, k, _ in satirlar
                      if k[1] >= Y * 0.82 and ALT_BILGI_DESENI.search(m)]
    icerik_alt_sinir = (min(alt_sinir, min(altbilgi_yleri) - Y * 0.008)
                        if altbilgi_yleri else alt_sinir)
    resimler = sayfa.resim_kutulari()
    ml_sekiller = _ml_sekil_kutulari(sayfa) if sayfa.raster else []

    # Renkli/ikon içindeki soru numarası OCR'da kaybolabilir. Görsel boşluk
    # segmentasyonunda art arda iki bağımsız, seçenekli blok bulunuyorsa ikinci
    # bloğun başlangıcını güvenli ek sınır say. Önceki blok seçenek taşımıyorsa
    # bu genellikle şekil ile aynı sorunun gövdesi arasındaki doğal boşluktur;
    # o durumda bölme yapmayız.
    blok_sinirlar = {i: [] for i in range(len(bantlar))}
    tum_blok_adaylar = []
    blok_ek_adaylar = []
    for bi, band in enumerate(bantlar):
        bloklar = _blok_segmentasyon(sayfa, [band], satirlar, pay, fmt)
        tum_blok_adaylar.extend((bi, blok) for blok in bloklar)
        for onceki_blok, yeni_blok in zip(bloklar, bloklar[1:]):
            # Görseli büyük bir dikey boşluk oluşturan sorularda ilk metin
            # parçası katı blok doğrulamasını geçmeyebilir. Bu durumda akış,
            # önceki sorunun seçenekli bloğu ile görselden sonraki "Buna
            # göre..." parçasını iki bağımsız soru sanıyordu. Aradaki gerçek
            # soru numarası zaten okunmuşsa yeni blok bir ek soru sınırı
            # değildir; numara çapalı kutunun şekil üzerinden devam etmesine
            # izin ver. Koruma yalnız içerikçe kabul edilen ``ham`` çapalarını
            # ve rasterda üst-düzey soru-numarası x hizasını kullanır; şekil
            # içindeki girintili "1." etiketi sınırı bastıramaz.
            arada_bilinen_soru = _blok_arasi_ust_duzey_capa_var_mi(
                onceki_blok, yeni_blok, bi, ham, sayfa.raster, G, Y
            )
            if arada_bilinen_soru:
                continue
            onceki_harf, _, _ = _bolge_bilgi(
                satirlar, onceki_blok, pay)
            onceki_metin = " ".join(
                m for m, _ in _bolge_satirlari(
                    satirlar, onceki_blok[1], onceki_blok[3],
                    band[0], band[1], pay))
            onceki_tamam = bool(SORU_YONERGE_GUCLU.search(onceki_metin))
            yeni_harf, _, yeni_govde = _bolge_bilgi(
                satirlar, yeni_blok, pay)
            bosluk = yeni_blok[1] - onceki_blok[3]
            # Şekil üzerindeki A/B/C etiketleri tek başına "önceki soru
            # tamamlandı" kanıtı değildir. Önceki blokta gerçek soru
            # yönergesi de bulunmalı; aksi halde harita/şema ile alttaki
            # soru cümlesi yanlışlıkla iki ayrı soruya bölünür.
            if len(onceki_harf) >= 3 and onceki_tamam \
                    and (len(yeni_harf) >= 3 or yeni_govde) \
                    and bosluk >= Y * 0.012:
                blok_sinirlar[bi].append(yeni_blok[1])
                blok_ek_adaylar.append((bi, yeni_blok))

    def _kutulari_kur(kabul):
        """Kabul edilen numara adaylarından sayfanın nihai meta listesini
        kurar (kutu sınırları + doğrulama + boş-sütun kurtarma + tekilleştirme
        + devam adayları). Zincir karşılaştırması için yeniden çalıştırılabilir."""
        meta = _kutu_insa(kabul)
        # Açık uçlu sayfalarda renkli numarası okunmayan bağımsız bir blok,
        # aynı sütundaki sonraki numaralı soru yüzünden "boş sütun" kurtarma
        # yoluna giremez. Var olan adaylarla örtüşmeyen güçlü bloğu koru.
        if fmt == "acik_uclu":
            for bi, blok in tum_blok_adaylar:
                _, _, govde = _bolge_bilgi(satirlar, blok, pay)
                if govde and not any(
                        _ortusme_orani(blok, m.kutu) >= 0.18
                        for m in meta if not m.devam_aday):
                    sonraki = [m.kutu[1] for m in meta
                               if not m.devam_aday
                               and _bant_idx((m.kutu[0] + m.kutu[2]) / 2) == bi
                               and m.kutu[1] > blok[1] + Y * 0.04]
                    alt = ((min(sonraki) - Y * 0.008) if sonraki
                           else icerik_alt_sinir)
                    genis = (blok[0], blok[1], blok[2], max(blok[3], alt))
                    meta.append(_meta(genis, None))
        # Ek sınır bir birleşmeyi durdurduysa ve yeni bloğun kendi numarası
        # OCR'da yoksa onu numarasız fakat kanıtlı soru olarak ekle.
        for bi, blok in blok_ek_adaylar:
            # Renkli bölüm başlığı, hemen altındaki okunmuş soru numarasıyla
            # birlikte tek bir görsel blok oluşturabilir. Blok başlangıcı
            # numaralı adaydan birkaç satır yukarıda olsa da bu yeni bir soru
            # değildir. %3,5 eşiği gerçek belgelerde başlık yüksekliğinin
            # hemen altında kalıyordu (örn. 31 pt / 780 pt); %5 aynı sorunun
            # başlık payını kapsar, bağımsız iki soru bu kadar yakın başlayıp
            # zaten üst üste binemeyeceği için güvenlidir.
            yakin_baslangic = any(
                abs(m.kutu[1] - blok[1]) <= Y * 0.05
                and _bant_idx((m.kutu[0] + m.kutu[2]) / 2) == bi
                for m in meta if not m.devam_aday)
            if not yakin_baslangic:
                meta.append(_meta(blok, None))
        # Numara zinciri bir sütunu HİÇ kutulamadıysa (taranmışta OCR o sütunun
        # numaralarını kaçırmış; ya da numaralar konu-listesi maddesi olup
        # elenmiş) o sütunu görsel blok boşluklarından kurtar. KURTARMA KOŞULU:
        # sütunda gerçek çoktan seçmeli kanıt (≥3 farklı şık) ya da açık uçlu
        # format olmalı (yan bilgi paneli / İÇİNDEKİLER kurtarmaya girmez).
        uretilen = {_bant_idx(m.kutu[0]) for m in meta}
        # Tam-genişlik soru birden fazla bandı zaten kapsıyorsa sağ/sol bandı
        # "boş" sanıp blok-segmentasyonla sahte ek sorular üretme.
        for m in meta:
            for i, (ba, bb) in enumerate(bantlar):
                yatay = min(m.kutu[2], bb) - max(m.kutu[0], ba)
                if yatay >= (bb - ba) * 0.45:
                    uretilen.add(i)
        eklendi = False
        for i, (ba, bb) in enumerate(bantlar):
            if i in uretilen:
                continue
            if fmt == "acik_uclu" \
                    or bolge_sik_sayisi(satirlar, 0, Y, ba, bb, pay) >= 3:
                yeni = _blok_segmentasyon(sayfa, [(ba, bb)], satirlar, pay, fmt)
                meta += [_meta(k, None) for k in yeni]
                eklendi = eklendi or bool(yeni)
        if eklendi:
            meta.sort(key=lambda m: (_bant_idx(m.kutu[0]), m.kutu[1]))
        # Örtüşen iki alternatifte "daima büyük kutu" komşu soruyu
        # yutabiliyordu. Numara çapası + gövde + şık kanıtını önceleyen
        # puanla; yalnız eşit kanıtta güvenli geniş kutuyu koru.
        puanlar = [
            (3.0 if m.numara is not None else 0.0)
            + (1.5 if m.numara_kutu is not None else 0.0)
            + (1.2 if m.govde_var else 0.0)
            + min(1.5, len(m.sik_harfler) * 0.3)
            for m in meta]
        maske = _tekrarsiz_maske([m.kutu for m in meta], puanlar=puanlar)
        meta = [m for m, tut in zip(meta, maske) if tut]
        meta += _devam_adaylari(sayfa, satirlar, bantlar, meta, pay, fmt)
        return meta

    def _kutu_insa(kabul):
        meta = []
        # Zincir kanıtı: bu aday kümesi ≥3 numaralı üye taşıyorsa, numaralar
        # düzenli bir soru dizisidir (talimat/konu maddesi değil). Tek/iki
        # numaralı sayfada bu kanıt kullanılmaz.
        guclu_zincir = sum(1 for n, _, _ in kabul if n is not None) >= 3
        for numara, s, kutu in kabul:
            bant_bas, bant_son = _aday_bant_araligi(kutu, s)
            ban_sol, ban_sag = bantlar[bant_bas][0], bantlar[bant_son][1]
            if sayfa.raster:
                # OCR numara kutusu, projeksiyondan bulunan sütun sınırının
                # birkaç piksel dışında kalabilir. Hard-clamp baştaki "S"yi
                # kesmesin; yalnız çapanın kendi kutusu kadar kontrollü açıl.
                ban_sol = max(0.0, min(ban_sol, kutu[0] - G * 0.008))
                ban_sag = min(G, max(ban_sag, kutu[2] + G * 0.008))
            # Üst pay, sayfa yüzdesi DEĞİL numara kutusunun kendi
            # yüksekliğinden türetilir. Sabit Y×0,012 (779 pt sayfada 9,35 pt)
            # 11 pt'lik bir numara satırının yarısı kadar fazla yer alıyordu:
            # kenar_hatalari ölçümü üst kenarda sistematik −5,36 pt medyan
            # (tahmin altından yukarıda başlıyor) gösterdi. min() ile pay
            # bugünkü değerini ASLA aşamaz — değişim yalnız daraltma yönünde.
            numara_yuk = max(1.0, kutu[3] - kutu[1])
            ust = kutu[1] - min(Y * 0.012, numara_yuk * 0.45)
            # alt sınır: aynı bantta bir sonraki NUMARA ADAYI'na kadar (kabul
            # edilmese bile) — arada elenen bir soru varsa kutu onu yutmaz
            # (birleşik/dev kutu koruması). Yoksa son metin satırına kadar.
            alt_num = None
            alt_kural = None       # alt sınırı hangi kaynağın kazandığı
            for n2, k2, _ in tum_num:
                k2_bas, k2_son = _aday_bant_araligi(k2)
                bantlar_ortusuyor = not (k2_son < bant_bas
                                         or k2_bas > bant_son)
                if k2[1] > kutu[1] + Y * 0.015 and bantlar_ortusuyor:
                    # Puan başlığından kısa süre sonra gövdede numaranın
                    # yeniden yazılması ("Soru-5 ..." + "5. Aşağıda...")
                    # yeni soru değildir. Uzak tekrarlar yeni test olabilir.
                    if n2 == numara and k2[1] - kutu[1] <= Y * 0.12:
                        continue
                    if alt_num is None or k2[1] < alt_num:
                        alt_num, alt_kural = k2[1], "sonraki_numara"
            for bi in range(bant_bas, bant_son + 1):
                for sinir_y in blok_sinirlar.get(bi, ()):
                    if sinir_y > kutu[1] + Y * 0.04:
                        if alt_num is None or sinir_y < alt_num:
                            alt_num, alt_kural = sinir_y, "blok_sinir"
            # Aynı bantta aşağıda TEST başlığı varsa kutu ona taşmasın. Eşik
            # bilerek geniş (Y·0.05): çözümlü kaynaklarda tek satırlık çözümün
            # ("9. E") hemen altındaki 'Test - N' işareti kutuyu minik bırakıp
            # öldürmesin — yakın başlıkta eski davranış korunur.
            for _, hk, _ in basliklar:
                if hk[1] > kutu[1] + Y * 0.05 and _bant_idx(hk[0]) == s:
                    if alt_num is None or hk[1] < alt_num:
                        alt_num, alt_kural = hk[1], "test_basligi"
            if alt_num is not None:
                alt = alt_num - Y * 0.008
            else:
                alt_kural = "son_metin"
                alt = ust
                for _, (sx0, sy0, sx1, sy1), _ in satirlar:
                    if ban_sol - pay <= (sx0 + sx1) / 2 <= ban_sag + pay \
                            and sy0 >= ust and sy1 < icerik_alt_sinir:
                        alt = max(alt, sy1)
                alt += Y * 0.01
                # ML şekil koruması (yalnız alt-çapasız dal → iki soruyu
                # birleştiremez): son metin satırının altına taşan şekil
                # (OCR'ın göremediği grafik/tablo) kutuya dahil edilir.
                for mx0, my0, mx1, my1 in ml_sekiller:
                    if ban_sol <= (mx0 + mx1) / 2 <= ban_sag \
                            and my0 < alt and my1 > alt:
                        alt = max(alt, my1 + Y * 0.004)
                        alt_kural = "ml_sekil"
                # Metin katmanlı PDF'de son soru bir grafik/tabloyla bitiyorsa
                # gömülü görüntü kutusu, son OCR/metin satırının altında
                # kalabilir. Yakın veya metinle örtüşen aynı-sütun görselini
                # yalnız alt çapası olmayan son soruda aşağı doğru kapsa.
                for rx0, ry0, rx1, ry1 in resimler:
                    merkez_x = (rx0 + rx1) / 2
                    if ban_sol <= merkez_x <= ban_sag \
                            and ry1 > alt and ry1 > ry0 \
                            and ry0 >= ust - Y * 0.01 \
                            and ry0 <= alt + Y * 0.025:
                        alt = max(alt, min(icerik_alt_sinir,
                                           ry1 + Y * 0.004))
                        alt_kural = "gomulu_gorsel"
                if fmt == "acik_uclu":
                    ic_metin = " ".join(m for m, _ in _bolge_satirlari(
                        satirlar, ust, alt, ban_sol, ban_sag, pay))
                    if re.search(
                            r"\b(?:yazınız|açıklayınız|belirtiniz|"
                            r"doldurunuz|tamamlayınız|çiziniz)\b",
                            ic_metin, re.I):
                        # Rasterda noktalı cevap çizgileri OCR metni değildir;
                        # son sorunun yazma alanını alt bilgi bandına kadar tut.
                        alt = icerik_alt_sinir
                        alt_kural = "yazma_alani"
                if alt > icerik_alt_sinir:
                    alt, alt_kural = icerik_alt_sinir, "icerik_alt_sinir"
            if alt > Y:
                alt, alt_kural = Y, "sayfa_alti"

            if sayfa.raster:
                # şekil bbox'ı yok → tam sütun şeridi (traşlama fazlayı alır)
                sol, sag = ban_sol, ban_sag
                yan_kural = "bant_seridi"
            else:
                # Görsel sütun ayıracı, metin kutularının gerçek sağ/sol
                # kenarı değildir. Dar bir emniyet payı olmadan ayıracın
                # birkaç punto dışına taşan son sözcük (örn. "bulunur?")
                # kesiliyordu. Yalnız merkezi hâlâ özgün bantta olan satır ve
                # görseller aşağıda birleştirildiğinden bu pay komşu sütunun
                # içeriğini kutuya çekmez.
                yatay_emniyet = G * 0.04
                fizik_sol = max(0.0, ban_sol - yatay_emniyet)
                fizik_sag = min(G, ban_sag + yatay_emniyet)
                yan_kural = "metin_birlesimi"
                # metin birleşimi + o dikey aralığı ≥%50 kesen gömülü resimler
                sol, sag = kutu[0], kutu[2]
                for _, (sx0, sy0, sx1, sy1), _ in satirlar:
                    if ban_sol - pay <= (sx0 + sx1) / 2 <= ban_sag + pay \
                            and sy0 < alt and sy1 > ust:
                        sol, sag = min(sol, sx0), max(sag, sx1)
                for rx0, ry0, rx1, ry1 in resimler:
                    dikey = min(ry1, alt) - max(ry0, ust)
                    if ry1 > ry0 and dikey / (ry1 - ry0) < 0.5:
                        continue
                    if ban_sol <= (rx0 + rx1) / 2 <= ban_sag:
                        sol, sag = min(sol, rx0), max(sag, rx1)
                sol = max(sol - 4, fizik_sol)
                sag = min(sag + 4, fizik_sag)

            # HARD-CLAMP: rasterda tam sütun bandı; metinli PDF'de yalnız
            # yukarıda kendi-merkeziyle seçilmiş içeriğe tanınan dar pay.
            if sayfa.raster:
                fizik_sol, fizik_sag = ban_sol, ban_sag
            clamp_sol, clamp_sag = sol < fizik_sol, sag > fizik_sag
            sol, sag = max(sol, fizik_sol), min(sag, fizik_sag)
            sinir_kanit = [("ust", "numara_kutu", ust),
                           ("alt", alt_kural or "bilinmiyor", alt),
                           ("sol", "bant_clamp" if clamp_sol else yan_kural,
                            sol),
                           ("sag", "bant_clamp" if clamp_sag else yan_kural,
                            sag)]

            # Dejenere kutuları (ör. bant negatif genişlik verirse) ele
            if sag - sol < 8 or alt - ust < 8:
                continue
            # Format-agnostik geçerlilik: talimat/konu-maddesi/minik parça ele.
            # zincir_capasi: bu aday, sayfanın doğrulanmış artan numara
            # zincirinin üyesi (≥3 numaralı üye) — cevap/çözüm kâğıtlarındaki
            # düz metin gövdeler bu kanıtla kurtarılır.
            if not blok_gecerli_mi(satirlar, ust, alt, ban_sol, ban_sag,
                                   pay, Y, fmt,
                                   capa_araligi=_capa_araligi,
                                   zincir_capasi=(numara is not None
                                                  and guclu_zincir)):
                # Ayrı satır + sütun sol kenarıyla doğrulanmış açık-uçlu soru
                # bazen soru-kipi taşımaz ("işaretini koyunuz" OCR'da kayıp,
                # yalnız tablo/önermeler kalmış olabilir). Güçlü çapa ve
                # yeterli gövde varsa bu soruyu sırf sözcük kalıbı yüzünden atma.
                ic = _bolge_satirlari(satirlar, ust, alt,
                                      ban_sol, ban_sag, pay)
                metin_uzunlugu = len(re.sub(
                    r"[.…_·\s]", "", " ".join(m for m, _ in ic)))
                guclu_acik = (fmt == "acik_uclu"
                              and tuple(kutu) in ust_duzey_numara_kutulari
                              and alt - ust >= Y * 0.05
                              and metin_uzunlugu >= 30)
                if not guclu_acik:
                    continue
            meta.append(_meta((sol, ust, sag, alt), numara,
                              numara_kutu=kutu, kanit=sinir_kanit,
                              bant_idx=s))

        return meta

    # Birincil davranış sütun-önceliklidir. Buna test-sınırı segmentli ve
    # satır-öncelikli iki aday eklenir; yalnız DAHA ÇOK nihai geçerli soru
    # üreten alternatif kazanır. Beraberlikte sütun sırası korunur.
    duz = en_uzun_zincir([a[0] for a in ham])
    aday_zincirler = [[ham[i] for i in duz]]
    parcali = _zincir_segmentli(ham, basliklar, _bant_idx, Y, tum_pos)
    if parcali is not None and parcali != duz:
        aday_zincirler.append([ham[i] for i in parcali])
    satir_ham = _satir_oncelikli_sirala(ham, Y)
    if satir_ham != ham:
        satir_zincir = en_uzun_zincir([a[0] for a in satir_ham])
        aday_zincirler.append([satir_ham[i] for i in satir_zincir])

    def _aday_skor(meta):
        gorunen = [m for m in meta if not m.devam_aday]
        # Numara adayları varken, daha çok numaralı gerçek kutu üreten sıra
        # blok-fallback'in ürettiği çok sayıdaki numarasız parçadan üstündür.
        # Eşit numaralı sayıda toplam kutu, tam eşitlikte eski sıra kazanır.
        #
        # İlk iki anahtar SAYIYI optimize eder ve dokunulmadı → bugünkü hiçbir
        # karar değişmez. Sonraki anahtarlar yalnız gerçek BERABERLİĞİ çözer:
        # eskiden beraberlikte keyfi biçimde ilk aday kazanıyordu, artık daha
        # az bant taşan ve daha az örtüşen (yani daha temiz) sıra kazanır.
        tasan = 0
        for m in gorunen:
            bas, son = _aday_bant_araligi(m.kutu)
            tasan += int(son > bas)
        ortusen = 0
        for i, a in enumerate(gorunen):
            for b in gorunen[i + 1:]:
                if _kutu_iou(a.kutu, b.kutu) > 0.25:
                    ortusen += 1
        return (sum(m.numara is not None for m in gorunen), len(gorunen),
                -tasan, -ortusen)

    en_iyi = _kutulari_kur(aday_zincirler[0])
    en_iyi_skor = _aday_skor(en_iyi)
    for kabul in aday_zincirler[1:]:
        meta_aday = _kutulari_kur(kabul)
        aday_skor = _aday_skor(meta_aday)
        if aday_skor > en_iyi_skor:
            en_iyi, en_iyi_skor = meta_aday, aday_skor

    # Şekilli bir soruda numara ile gövde arasında büyük boşluk varsa görsel
    # blok yolu yalnız alt metni numarasız aday olarak çıkarabilir. Aynı
    # sütunun gerçek sol kenarında, hemen üstte kalan ve başka bir adaya
    # bağlanmamış PDF/OCR numara çapası varsa ikisini tekrar birleştir.
    kullanilan_capalar = {
        tuple(m.numara_kutu) for m in en_iyi if m.numara_kutu is not None
    }
    geri_bagli = []
    for m in en_iyi:
        if m.devam_aday or m.numara is not None:
            geri_bagli.append(m)
            continue
        bi = _bant_idx((m.kutu[0] + m.kutu[2]) / 2)
        ba, bb = bantlar[bi]
        adaylar = []
        for no, nk, _kalin in tum_num:
            if tuple(nk) in kullanilan_capalar:
                continue
            if _bant_idx((nk[0] + nk[2]) / 2) != bi:
                continue
            if nk[0] > ba + G * 0.025:
                continue
            bosluk = m.kutu[1] - nk[1]
            if not 0 <= bosluk <= Y * 0.18:
                continue
            genis = (min(m.kutu[0], nk[0] - G * 0.008),
                     nk[1] - Y * 0.012, m.kutu[2], m.kutu[3])
            if blok_gecerli_mi(
                    satirlar, genis[1], genis[3], ba, bb, pay, Y, fmt):
                adaylar.append((bosluk, no, nk, genis))
        if adaylar:
            _bosluk, no, nk, genis = min(adaylar, key=lambda a: a[0])
            kullanilan_capalar.add(tuple(nk))
            geri_bagli.append(_meta(genis, no, numara_kutu=nk))
        else:
            geri_bagli.append(m)
    en_iyi = geri_bagli

    en_iyi = _pdf_metin_kutularini_sikilastir(
        sayfa, en_iyi, satirlar, fmt)
    return _adaylari_zenginlestir(sayfa, satirlar, en_iyi, fmt), \
        bantlar, fmt


def aday_tespit_edildi(m):
    """Bir aday metası TESPİT çıktısına giriyor mu — tek doğruluk kaynağı.

    Devam adayları (önceki sayfanın taşması, ayrı soru değil) ve reddedilenler
    dışarıdadır. Ölçüm tarafı (dogrula/altin_sayim) ile motor AYNI kümeye
    bakmak zorundadır: aksi halde count_recall/precision ve kayma sinyalleri
    hiç teslim edilmeyen kutuları sayar. `_aday_ciktiya_girer` bunun bir
    adım ilerisidir (kalite kipine göre otomatik/onaylı alt kümesi)."""
    return not m.devam_aday and m.inceleme_durumu != "reddedildi"


def aday_otomatik_teslim(m):
    """Aday, insan incelemesi olmadan teslim edilebilir mi.

    `aday_tespit_edildi`'nin sıkı alt kümesi: "sıfır hata" hedefi bu kovaya
    tanımlıdır (otomatik teslim edilen her kesim kusursuz olmalı), `incele`
    kovası ise ayrı klasöre gerekçesiyle yazılır."""
    return aday_tespit_edildi(m) and _aday_ciktiya_girer(m, "balanced")


def sorulari_tespit(sayfa, fmt="karisik"):
    """Bir sayfadaki soruları bulur; her soru için kırpma kutusunu (PDF/
    piksel koordinatında) döndürür. sorulari_tespit_meta'nın kutu-listesi
    görünümü (devam adayları hariç) — çıktı meta öncesiyle birebir aynıdır."""
    meta, _, _ = sorulari_tespit_meta(sayfa, fmt)
    return [m.kutu for m in meta if aday_tespit_edildi(m)]


def _ortusme_orani(a, b):
    """İki kutunun kesişim alanının, KÜÇÜK olanın alanına oranı (0..1)."""
    gx = min(a[2], b[2]) - max(a[0], b[0])
    gy = min(a[3], b[3]) - max(a[1], b[1])
    if gx <= 0 or gy <= 0:
        return 0.0
    kesisim = gx * gy
    ka = (a[2] - a[0]) * (a[3] - a[1])
    kb = (b[2] - b[0]) * (b[3] - b[1])
    return kesisim / max(1.0, min(ka, kb))


def _tekrarsiz_maske(kutular, esik=0.85, puanlar=None):
    """Yüksek örtüşen kutuları teke indiren tutma-maskesi (aynı numaranın iki
    kez çapalanması ya da blok/numara yollarının çakışması → zip'te tekrarlı
    PNG olmaz). ``puanlar`` verilirse daha güçlü numara/içerik kanıtı
    korunur; eşit kanıtta geniş kutu güvenli pay nedeniyle tercih edilir.
    GİRİŞ SIRASI değişmez. Eski çağrılarda büyük-kutu davranışı korunur."""
    if len(kutular) < 2:
        return [True] * len(kutular)
    alan = [(k[2] - k[0]) * (k[3] - k[1]) for k in kutular]
    puanlar = list(puanlar) if puanlar is not None else [0.0] * len(kutular)
    if len(puanlar) != len(kutular):
        raise ValueError("puanlar ile kutular aynı uzunlukta olmalı")
    at = [False] * len(kutular)
    for i in range(len(kutular)):
        if at[i]:
            continue
        for j in range(len(kutular)):
            if i == j or at[j]:
                continue
            if _ortusme_orani(kutular[i], kutular[j]) >= esik:
                if puanlar[i] < puanlar[j] \
                        or (puanlar[i] == puanlar[j] and alan[i] < alan[j]):
                    at[i] = True
                    break
                at[j] = True
    return [not a for a in at]


# --------------------------------------------------------- işleme + önizleme

def belge_sayfalari(girdiler, dpi):
    """Tüm girdileri sırayla Sayfa nesnelerine açar. Açık PDF doc'larını da
    döndürür (yaşam süresi için)."""
    sayfalar = []
    acik = []
    for belge_no, yol in enumerate(girdiler):
        if not os.path.exists(yol):
            # sys.exit değil: GUI/web iş parçacıkları Exception yakalar,
            # SystemExit yakalamaz (arayüz asılı kalırdı)
            raise FileNotFoundError(f"dosya bulunamadı: {yol}")
        s, doc = sayfalari_yukle(yol, dpi)
        for sayfa in s:
            sayfa.belge_no = belge_no  # birleştirme belge sınırını aşmasın
        sayfalar.extend(s)
        if doc is not None:
            acik.append(doc)
    return sayfalar, acik


def belge_formatini_belirle(tum_satirlar):
    """Belgenin baskın soru formatını döndürür: 'coktan_secmeli' | 'acik_uclu'
    | 'cozumlu' | 'konu_anlatimi' | 'karisik'. Sayfa-başı sinyallerin (şık
    yoğunluğu, çözüm başlığı, yazma alanı/alt-madde, tanım maddesi) belge-düzeyi
    oranlarına göre öncelikli karar ağacı. Doğrulama kuralı formata göre seçilir."""
    n = max(1, len(tum_satirlar))
    sik_s = coz_s = yaz_s = tanim_s = 0
    for satirlar in tum_satirlar:
        harfler = set()
        coz = noktali = altmadde = tanim = 0
        num = False
        for m, _, _ in satirlar:
            harfler.update(_sik_harfleri(m))
            if COZUM_DESENI.match(m):
                coz += 1
            if NOKTALI_SATIR.search(m):
                noktali += 1
            if ALT_MADDE_DESENI.match(m):
                altmadde += 1
            if TANIM_MADDE.match(m):
                tanim += 1
            if SORU_NO_DESENI.match(m):
                num = True
        if len(harfler) >= 3:
            sik_s += 1
        if num and coz >= 1:
            coz_s += 1
        if noktali >= 2 or altmadde >= 2:
            yaz_s += 1
        if tanim >= 3 and len(harfler) < 2 and noktali == 0:
            tanim_s += 1
    # 'cozumlu' kararı ARTIK çoktan seçmeli kanıtına bakmadan verilmiyor.
    # COZUM_DESENI satır başındaki "çözüm/cevap/yanıt/çöz" ile eşleşir; her
    # sorunun altına "Cevap: A" basan bir soru bankası da sayfalarının
    # çoğunda bu deseni tetikler ve eski sıralamada belge yanlışlıkla
    # 'cozumlu' sayılırdı. Yanlış pozitifin etkisi geniştir: sayfa vetosunda
    # çözüm rolü bağışıklık kazanır, aday puanlamasında çözüm cezası kalkar,
    # COZUM_NO_DESENI ek çapa üretir. Bu yüzden şık kanıtı KENDİ eşiğini
    # geçip çözüm kanıtından güçlüyse belge çoktan seçmeli sayılır.
    # Ölçüldü (A korpusu): gerçek çözüm kitabı cozumler1 coz=0,784 sik=0,341;
    # diğer dokuz belgenin tamamı coz<=0,019 — karar aralığı geniş, bu ek
    # koşul mevcut sınıflandırmaların hiçbirini değiştirmez.
    # Beraberlik çoktan seçmeliye gider: her sayfada HEM tam şık kümesi HEM
    # cevap satırı varsa bu, çözümün baskın olduğu bir kitap değil, cevaplı
    # bir soru bankasıdır (gerçek çözüm kitabı beş şıkkı yeniden basmaz).
    if coz_s / n >= 0.30 and (sik_s / n < 0.40 or coz_s > sik_s):
        return "cozumlu"
    if sik_s / n >= 0.40:            # mevcut eşik → çoktan seçmeli regresyonu güvenli
        return "coktan_secmeli"
    if yaz_s / n >= 0.30:
        return "acik_uclu"
    if tanim_s / n >= 0.50:
        return "konu_anlatimi"
    return "karisik"


def belge_formati(sayfalar, tum_satirlar):
    """Sayfa boyutunu da dikkate alan format tespiti. Sayfalar çoğunlukla
    yatay (16:9 slayt) ve numara çok azsa 'slayt'; aksi hâlde metin desenlerine
    dayalı belge_formatini_belirle."""
    if sayfalar:
        yatay = sum(1 for s in sayfalar if s.genislik > s.yukseklik * 1.3)
        num_top = sum(len(numara_adaylari(sat)) for sat in tum_satirlar)
        if yatay >= len(sayfalar) * 0.7 and num_top < len(sayfalar) * 2:
            return "slayt"
    return belge_formatini_belirle(tum_satirlar)


def kalibre_et(sayfalar, tum_satirlar):
    """Format + sütun kalibrasyonu. Dönüş: (fmt, sutun_xler)."""
    G = max(s.genislik for s in sayfalar)
    Y = max(s.yukseklik for s in sayfalar)
    fmt = belge_formati(sayfalar, tum_satirlar)
    return fmt, kalibrasyon(tum_satirlar, G, Y, fmt == "coktan_secmeli")


def _ornek_indeksler(adet, maks=PROFIL_ORNEK_MAKS):
    """Belgenin baş/orta/sonunu kapsayan deterministik eşit örnekleme."""
    if adet <= maks:
        return list(range(adet))
    return sorted({round(i * (adet - 1) / (maks - 1)) for i in range(maks)})


def _kaynak_hashi(girdiler, sayfalar=None):
    """İçeriğe bağlı SHA-256. Yol değişse de aynı belge aynı profili kullanır."""
    h = hashlib.sha256()
    kullanildi = False
    for yol in girdiler or []:
        try:
            h.update(b"\0DOSYA\0")
            with open(yol, "rb") as f:
                while True:
                    parca = f.read(1024 * 1024)
                    if not parca:
                        break
                    h.update(parca)
            kullanildi = True
        except OSError:
            h.update(os.path.basename(str(yol)).encode("utf-8", "replace"))
    if not kullanildi:
        # Sentetik/test sayfaları ve kaynağı bulunamayan oturumlar için içerik
        # parmak izi. Tüm metni kullanmak küçük; görüntü piksellerini okumaz.
        for s in sayfalar or []:
            h.update(f"{s.genislik:.3f}x{s.yukseklik:.3f}|{int(s.raster)}"
                     .encode("ascii"))
            try:
                for m, k, _ in s.satirlar():
                    h.update(_profil_norm(m).encode("utf-8"))
                    h.update(f"@{k[0]:.1f},{k[1]:.1f}".encode("ascii"))
            except Exception:  # noqa: BLE001
                pass
    return h.hexdigest()


def _profil_cache_oku(kaynak_hash, sayfa_sayisi):
    yol = os.path.join(PROFIL_CACHE_DIZIN, kaynak_hash + ".json")
    try:
        with open(yol, encoding="utf-8") as f:
            veri = json.load(f)
        if veri.get("algoritma_surumu") != KALIBRASYON_SURUMU \
                or veri.get("sayfa_sayisi") != sayfa_sayisi:
            return None
        return BelgeProfili.from_dict(veri)
    except (OSError, ValueError, TypeError):
        return None


def _profil_cache_yaz(profil):
    try:
        os.makedirs(PROFIL_CACHE_DIZIN, exist_ok=True)
        fd, gecici = tempfile.mkstemp(dir=PROFIL_CACHE_DIZIN, suffix=".tmp")
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(profil.to_dict(), f, ensure_ascii=False, indent=2)
        os.replace(gecici, os.path.join(PROFIL_CACHE_DIZIN,
                                        profil.kaynak_hash + ".json"))
    except OSError:
        try:
            os.unlink(gecici)
        except (OSError, UnboundLocalError):
            pass


def _tekrar_satirlari_bul(sayfalar, indeksler):
    """Temsilî sayfalarda yinelenen üst/alt/yan bant metinlerini öğrenir."""
    gorulme = Counter()
    uygun_sayfa = 0
    for i in indeksler:
        s = sayfalar[i]
        sayfadakiler = set()
        try:
            for metin, (x0, y0, x1, y1), _ in s.satirlar():
                kenar = (y1 <= s.yukseklik * 0.14
                         or y0 >= s.yukseklik * 0.86
                         or x1 <= s.genislik * 0.08
                         or x0 >= s.genislik * 0.92)
                norm = _profil_norm(metin)
                if kenar and len(norm) >= 4:
                    sayfadakiler.add(norm)
            uygun_sayfa += 1
        except Exception:  # noqa: BLE001
            continue
        gorulme.update(sayfadakiler)
    esik = max(3, int(uygun_sayfa * 0.28 + 0.999))
    return sorted(m for m, adet in gorulme.items() if adet >= esik)


def belge_profili_uret(sayfalar, fmt=None, girdiler=None,
                       tum_satirlar=None, onbellek=True):
    """Belgenin tamamına yayılmış örneklerden :class:`BelgeProfili` üretir."""
    if not sayfalar:
        raise ValueError("profil için en az bir sayfa gerekir")
    tum = tum_satirlar or [s.satirlar() for s in sayfalar]
    fmt = fmt or belge_formati(sayfalar, tum)
    kaynak_hash = _kaynak_hashi(girdiler, sayfalar)
    if onbellek:
        eski = _profil_cache_oku(kaynak_hash, len(sayfalar))
        if eski is not None:
            return eski

    indeksler = _ornek_indeksler(len(sayfalar))
    roller = []
    for i, satirlar in enumerate(tum):
        rol, guven, kanit = _sayfa_rolu_belirle(
            satirlar, sayfa_no=i + 1, toplam=len(sayfalar))
        roller.append({"sayfa_no": i + 1, "rol": rol,
                       "guven": round(guven, 3), "kanitlar": list(kanit)})

    tekrar = _tekrar_satirlari_bul(sayfalar, indeksler)
    aile_say = Counter()
    aile_bant = {}
    x_say = Counter()
    tur_say = Counter()
    duzen_guvenleri = []
    yontem_say = Counter()
    egiklik_say = Counter()
    for i in indeksler:
        s = sayfalar[i]
        if roller[i]["rol"] not in ("soru", "karma"):
            continue
        try:
            kal = sayfa_sutun_kalibrasyonu(s)
            bantlar = list(kal.bantlar)
            duzen_guvenleri.append(kal.guven)
            yontem_say.update(kal.kanitlar)
            aci = abs(kal.egiklik_derece)
            egiklik_say["duz" if aci < 0.5 else
                         "hafif" if aci < 1.5 else "egik"] += 1
        except Exception:  # noqa: BLE001
            bantlar = [(0.0, s.genislik)]
        norm_bant = tuple((round(a / max(1, s.genislik), 2),
                           round(b / max(1, s.genislik), 2))
                          for a, b in bantlar)
        anahtar = f"{len(norm_bant)}_sutun:" + ",".join(
            f"{a:.2f}-{b:.2f}" for a, b in norm_bant)
        aile_say[anahtar] += 1
        aile_bant[anahtar] = norm_bant
        for _, k, _ in numara_adaylari(tum[i]):
            oran = max(0.0, min(1.0, k[0] / max(1, s.genislik)))
            x_say[round(round(oran / 0.02) * 0.02, 2)] += 1
        tur = _soru_turu_belirle(tum[i], (0, 0, s.genislik, s.yukseklik),
                                  s.genislik * 0.012, fmt)
        tur_say[tur] += 1

    aileler = [{"ad": k.split(":", 1)[0],
                "bantlar": [list(x) for x in aile_bant[k]], "sayfa": adet}
               for k, adet in aile_say.most_common()]
    x_esik = max(2, int(len(indeksler) * 0.04 + 0.999))
    numara_x = [x for x, adet in sorted(x_say.items()) if adet >= x_esik]
    yon = Counter("yatay" if s.genislik > s.yukseklik * 1.15 else "dikey"
                  for s in sayfalar)
    rol_say = Counter(r["rol"] for r in roller)
    profil = BelgeProfili(
        kaynak_hash=kaynak_hash, format=fmt, sayfa_sayisi=len(sayfalar),
        raster_orani=sum(bool(s.raster) for s in sayfalar) / len(sayfalar),
        yon_dagilimi=dict(yon), rol_dagilimi=dict(rol_say),
        tur_dagilimi=dict(tur_say), sutun_aileleri=aileler,
        numara_x_oranlari=numara_x, tekrar_satirlari=tekrar,
        sayfa_rolleri=roller,
        duzen_guveni=(round(sum(duzen_guvenleri) / len(duzen_guvenleri), 3)
                       if duzen_guvenleri else 0.60),
        kalibrasyon_yontemleri=[k for k, _ in yontem_say.most_common()],
        egiklik_dagilimi=dict(egiklik_say))
    if onbellek:
        _profil_cache_yaz(profil)
    return profil


def _duzen_ailesi_adi(bantlar, adaylar):
    gorunen = [m for m in adaylar if not m.devam_aday]
    capraz = any(sum(min(m.kutu[2], b) - max(m.kutu[0], a) > (b - a) * 0.25
                     for a, b in bantlar) >= 2 for m in gorunen)
    if capraz and len(bantlar) > 1:
        return f"{len(bantlar)}_sutun_tam_genislik_gecisli"
    return f"{max(1, len(bantlar))}_sutun"


def _sutun_uyarisi_sayfa_riskleri(duzen):
    """Sütun uyarılarını strict sayfa riskine ölçülü biçimde dönüştür.

    Yöntem sayılarının farklı çıkması güven puanını zaten düşürür. Nihai
    uzlaşma yine güçlü ise aynı uyarıyı ikinci kez koşulsuz sert engel yapmak,
    yüzlerce temiz sayfayı inceleme kuyruğuna taşıyordu.
    """
    if duzen is None:
        return ()
    uyarilar = set(duzen.uyarilar or ())
    riskler = []
    if ("sutun_yontemleri_uyusmuyor" in uyarilar
            and float(duzen.guven) < DUZEN_UYUSMAZLIK_RISK_ESIGI):
        riskler.append("sutun_yontemleri_uyusmuyor")
    if "bolgesel_sutun_gecisi" in uyarilar:
        riskler.append("bolgesel_sutun_gecisi")
    return tuple(riskler)


def _profil_duzen_onculu(sayfa, profil, mevcut):
    """Belirsiz sayfaya belgenin baskın düzen kümesini öncül olarak verir."""
    if mevcut is None or mevcut.guven >= 0.62 or not profil.sutun_aileleri:
        return None
    baskin = profil.sutun_aileleri[0]
    if int(baskin.get("sayfa", 0)) < min(3, max(1, profil.sayfa_sayisi)):
        return None
    try:
        bantlar = tuple((float(a) * sayfa.genislik,
                         float(b) * sayfa.genislik)
                        for a, b in baskin["bantlar"])
    except (KeyError, TypeError, ValueError):
        return None
    if not bantlar or any(b <= a for a, b in bantlar):
        return None
    # Öncül kesin gerçek değildir; güveni otomatik kabul eşiğinin
    # altında tutup adayların yeniden kurulmasına yardım eder.
    return SutunKalibrasyonu(
        bantlar=bantlar,
        guven=min(0.78, max(0.62, float(profil.duzen_guveni))),
        kanitlar=tuple(dict.fromkeys(
            tuple(mevcut.kanitlar) + ("belge_duzen_profili",))),
        uyarilar=tuple(dict.fromkeys(
            tuple(mevcut.uyarilar) + ("belge_onculu_kullanildi",))),
        ayraclar=tuple(_bant_ayraclari(bantlar, sayfa.genislik)),
        egiklik_derece=mevcut.egiklik_derece,
        bolgesel_gecis=mevcut.bolgesel_gecis)


def _profil_aday_onculu(meta, sayfa, profil):
    """Tipik numara hizasını aday güvenine sınırlı kanıt olarak besler."""
    tipik = [float(x) for x in (profil.numara_x_oranlari or [])]
    if not tipik:
        return meta
    G = max(1.0, float(sayfa.genislik))
    sert_geometri_riskleri = {
        "sutun_tasma_riski", "coklu_numara_icerik",
        "soru_modeli_birlesme_riski", "tam_sayfaya_yakin",
        "tam_sutuna_yakin", "asiri_kucuk",
    }
    sonuc = []
    for m in meta:
        if m.devam_aday or m.numara_kutu is None:
            sonuc.append(m)
            continue
        if sert_geometri_riskleri.intersection(m.uyarilar):
            sonuc.append(m)
            continue
        x = float(m.numara_kutu[0]) / G
        yakin = min(abs(x - p) for p in tipik)
        if yakin <= 0.045:
            guven = min(0.99, m.guven + 0.025)
            kanit = tuple(dict.fromkeys(m.kanitlar +
                                        ("belge_numara_hizasi",)))
            uyari = m.uyarilar
        elif yakin >= 0.12 and m.guven < 0.90:
            guven = max(0.0, m.guven - 0.08)
            kanit = m.kanitlar
            uyari = tuple(dict.fromkeys(m.uyarilar +
                                        ("aykiri_numara_hizasi",)))
        else:
            sonuc.append(m)
            continue
        durum = ("otomatik" if guven >= GUVEN_OTOMATIK else
                 "incele" if guven >= GUVEN_INCELE else "reddedildi")
        sonuc.append(m._replace(
            guven=round(guven, 3), kalibre_guven=round(guven, 3),
            kanitlar=kanit, uyarilar=uyari, inceleme_durumu=durum,
            onay_durumu={"otomatik": "otomatik", "incele": "bekliyor",
                          "reddedildi": "reddedildi"}[durum],
            risk_nedenleri=tuple(dict.fromkeys(
                m.risk_nedenleri + tuple(uyari)))))
    return sonuc


def _gemini_yedegi_uygula(sayfa, satirlar, meta, bantlar, fmt, yerel_rol):
    """Düşük güvenli adaylara isteğe bağlı Vision ikinci görüşü uygular.

    Gemini tek başına kutu oluşturamaz: öneri mevcut yerel adayla en az %35
    örtüşmeli veya yerel bir soru-numarası + blok geçerlilik testini geçmelidir.
    """
    if meta and all(m.devam_aday or m.inceleme_durumu == "otomatik"
                    for m in meta):
        return meta, yerel_rol
    try:
        import gemini_vision
        if not gemini_vision.aktif_mi():
            return meta, yerel_rol
        img, _ = sayfa.gorsel()
        sonuc = gemini_vision.sayfa_analiz_et(
            img, [m for m in meta if not m.devam_aday],
            layout_boyut=(sayfa.genislik, sayfa.yukseklik))
    except Exception:  # noqa: BLE001 — bulut yedeği yerel yolu bozamaz
        return meta, yerel_rol
    if not sonuc:
        return meta, yerel_rol
    rol = {"cevap_anahtarı": "cevap_anahtari"}.get(
        sonuc.get("sayfa_rolu"), sonuc.get("sayfa_rolu")) or yerel_rol
    G, Y = sayfa.genislik, sayfa.yukseklik
    ai_kutular = []
    for a in sonuc.get("sorular") or []:
        try:
            k = (max(0.0, min(G, float(a["x0"]) * G / 1000)),
                 max(0.0, min(Y, float(a["y0"]) * Y / 1000)),
                 max(0.0, min(G, float(a["x1"]) * G / 1000)),
                 max(0.0, min(Y, float(a["y1"]) * Y / 1000)))
            if k[2] - k[0] >= G * 0.06 and k[3] - k[1] >= Y * 0.025:
                ai_kutular.append((k, max(0.0, min(1.0, float(a["guven"]))),
                                   str(a.get("soru_turu") or "karma")))
        except (KeyError, TypeError, ValueError):
            continue

    cikti = list(meta)
    eslesen_ai = set()
    for i, m in enumerate(cikti):
        if m.devam_aday:
            continue
        adaylar = [(j, _ortusme_orani(m.kutu, k), conf, tur)
                   for j, (k, conf, tur) in enumerate(ai_kutular)]
        if adaylar:
            j, ort, ai_guven, ai_tur = max(adaylar, key=lambda x: x[1])
        else:
            ort = 0
        if ort >= 0.35:
            eslesen_ai.add(j)
            yeni = min(0.94, max(m.guven, 0.72 + ai_guven * 0.22))
            kanit = tuple(dict.fromkeys(m.kanitlar + ("gemini_dogruladi",)))
            uyari = tuple(u for u in m.uyarilar
                          if u not in ("metin_kaniti_yok", "aday_cakismasi"))
            # Bulut yalnız ikinci görüştür: yerelde inceleme/reddetme
            # gereken adayı tek başına otomatik kabul edemez.
            durum = ("otomatik" if m.inceleme_durumu == "otomatik"
                     else "incele")
            cikti[i] = m._replace(
                guven=round(yeni, 3), soru_turu=ai_tur or m.soru_turu,
                kanitlar=kanit, uyarilar=uyari,
                inceleme_durumu=durum, kalibre_guven=round(yeni, 3),
                onay_durumu=("otomatik" if durum == "otomatik"
                              else "bekliyor"),
                kaynak_yontemler=tuple(dict.fromkeys(
                    m.kaynak_yontemler + ("cloud_second_opinion",))),
                risk_nedenleri=tuple(dict.fromkeys(
                    m.risk_nedenleri + (("bulut_tek_basina_onaylayamaz",)
                                        if durum != "otomatik" else ()))))
        elif rol in ("kapak", "içindekiler", "konu", "çözüm",
                     "cevap_anahtari") and m.guven < 0.90:
            uyari = tuple(dict.fromkeys(m.uyarilar +
                                        ("gemini_soru_disinda",)))
            cikti[i] = m._replace(guven=min(m.guven, 0.50), uyarilar=uyari,
                                  kalibre_guven=min(m.guven, 0.50),
                                  inceleme_durumu="reddedildi",
                                  onay_durumu="reddedildi",
                                  kaynak_yontemler=tuple(dict.fromkeys(
                                      m.kaynak_yontemler +
                                      ("cloud_second_opinion",))))

    # AI'nin bulduğu fakat yerel kutunun kaçırdığı öneri, ancak yerel numara
    # çapası kutunun içinde ve klasik blok doğrulaması olumluysa eklenebilir.
    numaralar = numara_adaylari(satirlar, cozum=(fmt == "cozumlu"))
    pay = G * 0.012
    for j, (k, ai_guven, ai_tur) in enumerate(ai_kutular):
        if j in eslesen_ai:
            continue
        nk = next(((no, kutu) for no, kutu, _ in numaralar
                   if k[0] - pay <= (kutu[0] + kutu[2]) / 2 <= k[2] + pay
                   and k[1] - pay <= (kutu[1] + kutu[3]) / 2 <= k[3] + pay),
                  None)
        if nk is None:
            continue
        no, num_kutu = nk
        bi = next((z for z, (a, b) in enumerate(bantlar)
                   if a - pay <= (num_kutu[0] + num_kutu[2]) / 2 <= b + pay), 0)
        ba, bb = bantlar[bi]
        kk = (max(ba, k[0]), k[1], min(bb, k[2]), k[3])
        if kk[2] - kk[0] < 8 or not blok_gecerli_mi(
                satirlar, kk[1], kk[3], ba, bb, pay, Y, fmt):
            continue
        yeni = SoruKutu(kk, bi, no, False,
                         *_bolge_bilgi(satirlar, kk, pay),
                         numara_kutu=num_kutu)
        yeni = _adaylari_zenginlestir(
            sayfa, satirlar, [yeni], fmt, sayfa_rolu="soru")[0]
        guven = min(0.91, max(yeni.guven, 0.70 + ai_guven * 0.22))
        yeni = yeni._replace(
            soru_turu=ai_tur or yeni.soru_turu, guven=round(guven, 3),
            kalibre_guven=round(guven, 3),
            kanitlar=tuple(dict.fromkeys(
                yeni.kanitlar + ("gemini_dogruladi", "yerel_numara_capasi"))),
            inceleme_durumu="incele", onay_durumu="bekliyor",
            kaynak_yontemler=tuple(dict.fromkeys(
                yeni.kaynak_yontemler + ("cloud_second_opinion",))),
            risk_nedenleri=tuple(dict.fromkeys(
                yeni.risk_nedenleri + ("bulut_tek_basina_onaylayamaz",))))
        cikti.append(yeni)
    return cikti, rol


def _soru_modeli_yedegi_uygula(sayfa, satirlar, meta, bantlar, fmt):
    """Yerel soru modelinin bulduğu ama tespitin kaçırdığı soruları kurtarır
    (bos-sutun hata sınıfının ana ilacı). Gemini yedeğiyle aynı güvenlik
    felsefesi: model tek başına kutu ekleyemez — yalnız yerel numara çapası
    kutunun içindeyse VE blok_gecerli_mi olumluysa, o da 'incele' olarak.
    Dönüş: genişletilmiş meta. Model yoksa değişmeden döner."""
    sm_body = [b for b in _soru_modeli_bolgeleri(sayfa)
               if b["sinif"] == "question_body" and b["guven"] >= 0.50]
    if not sm_body:
        return meta
    G, Y = max(1.0, sayfa.genislik), max(1.0, sayfa.yukseklik)
    pay = G * 0.012
    numaralar = numara_adaylari(satirlar, cozum=(fmt == "cozumlu"))
    mevcut = [m.kutu for m in meta if not m.devam_aday]
    cikti = list(meta)
    for b in sm_body:
        k = b["kutu"]
        if any(_kutu_iou(k, mk) >= 0.20
               or _kutu_kapsanma_orani(k, mk) >= 0.70 for mk in mevcut):
            continue
        nk = next(((no, kutu) for no, kutu, _ in numaralar
                   if k[0] - pay <= (kutu[0] + kutu[2]) / 2 <= k[2] + pay
                   and k[1] - pay <= (kutu[1] + kutu[3]) / 2 <= k[3] + pay),
                  None)
        if nk is None:
            continue
        no, num_kutu = nk
        bi = next((z for z, (a, bb) in enumerate(bantlar)
                   if a - pay <= (num_kutu[0] + num_kutu[2]) / 2 <= bb + pay),
                  0)
        ba, bb = bantlar[bi]
        kk = (max(ba, k[0]), k[1], min(bb, k[2]), k[3])
        # Model kutusu yanlış sütuna düşüp gutter'da ince bir şerit olarak
        # clamp edildiyse bu bir soru önerisi değildir. Gemini yoluyla aynı
        # asgari fiziksel genişliği uygula; aksi halde güveni 0 olan 20–30 px
        # şeritler inceleme kuyruğunu ve anomali sayısını kirletiyordu.
        if kk[2] - kk[0] < max(8.0, G * 0.06) or not blok_gecerli_mi(
                satirlar, kk[1], kk[3], ba, bb, pay, Y, fmt):
            continue
        yeni = SoruKutu(kk, bi, no, False,
                        *_bolge_bilgi(satirlar, kk, pay),
                        numara_kutu=num_kutu)
        yeni = _adaylari_zenginlestir(
            sayfa, satirlar, [yeni], fmt, sayfa_rolu="soru")[0]
        yeni = yeni._replace(
            inceleme_durumu="incele", onay_durumu="bekliyor",
            kanitlar=tuple(dict.fromkeys(
                yeni.kanitlar + ("soru_modeli_onerisi",
                                 "yerel_numara_capasi"))),
            kaynak_yontemler=tuple(dict.fromkeys(
                yeni.kaynak_yontemler + ("question_specific_model",))),
            risk_nedenleri=tuple(dict.fromkeys(
                yeni.risk_nedenleri + ("soru_modeli_kurtardi",))))
        cikti.append(yeni)
        mevcut.append(kk)
    return cikti


def belge_analiz_et(sayfalar, fmt=None, girdiler=None, tum_satirlar=None,
                    onbellek=True):
    """V2 iki aşamalı analiz: belge profili + güven puanlı sayfa adayları.

    Dönüş ``(BelgeProfili, [SayfaAnalizi, ...])``. Sonuçlar sayfa nesnesine
    de bağlanır; eski ``sorulari_tespit_meta`` çağrıları aynı adayları tekrar
    hesaplamaz.
    """
    if sayfalar and all(hasattr(s, "_v2_sayfa_analizi") for s in sayfalar):
        p = getattr(sayfalar[0], "_v2_belge_profili", None)
        if p is not None and (fmt is None or p.format == fmt):
            return p, [s._v2_sayfa_analizi for s in sayfalar]
    tum = tum_satirlar or [s.satirlar() for s in sayfalar]
    profil = belge_profili_uret(sayfalar, fmt, girdiler, tum, onbellek)
    analizler = []
    for i, (s, satirlar) in enumerate(zip(sayfalar, tum)):
        rol_bilgi = profil.sayfa_rolleri[i]
        meta, bantlar, sayfa_fmt = sorulari_tespit_meta(s, profil.format)
        mevcut_duzen = getattr(s, "_v22_sutun_kalibrasyonu", None)
        profil_onculu = _profil_duzen_onculu(s, profil, mevcut_duzen)
        if profil_onculu is not None:
            s._v22_sutun_kalibrasyonu = profil_onculu
            s._v3_duzen_bolgeleri = tuple(
                b.to_dict() for b in duzen_bolgeleri_uret(s, profil_onculu))
            if isinstance(getattr(s, "_v2_meta_onbellek", None), dict):
                s._v2_meta_onbellek.pop(profil.format, None)
            meta, bantlar, sayfa_fmt = sorulari_tespit_meta(s, profil.format)
        meta = _adaylari_zenginlestir(
            s, satirlar, meta, sayfa_fmt, sayfa_rolu=rol_bilgi["rol"],
            tekrar_satirlari=profil.tekrar_satirlari)
        meta = _profil_aday_onculu(meta, s, profil)
        # Yerel soru modeli kaçan soruları önce kurtarır (bulut çağrısı çoğu
        # kez gereksizleşir); sonra Gemini yedeği (varsa) devreye girer.
        meta = _soru_modeli_yedegi_uygula(s, satirlar, meta, bantlar,
                                          sayfa_fmt)
        meta, nihai_rol = _gemini_yedegi_uygula(
            s, satirlar, meta, bantlar, sayfa_fmt, rol_bilgi["rol"])
        gorunen = [m for m in meta if not m.devam_aday]
        turler = Counter(m.soru_turu for m in gorunen
                         if m.inceleme_durumu != "reddedildi")
        sayfa_turu = turler.most_common(1)[0][0] if turler else "bilinmiyor"
        uyari = []
        risk = []
        pipeline_hatalari = []
        sinyaller = _sayfa_sinyalleri(satirlar)
        soru_sinyali = bool(
            sinyaller["numara"] and (sinyaller["govde"]
                                      or len(sinyaller["siklar"]) >= 2
                                      or sinyaller["yazma"]))
        kabul_edilebilir = [m for m in gorunen
                            if m.inceleme_durumu != "reddedildi"]
        if nihai_rol in ("soru", "karma") and not kabul_edilebilir:
            uyari.append("soru_sayfasinda_aday_yok")
            risk.append("adaysiz_soru_sayfasi")
        elif soru_sinyali and not kabul_edilebilir:
            risk.append("soru_sinyali_var_aday_yok")
        if any(m.inceleme_durumu == "reddedildi" for m in gorunen):
            uyari.append("reddedilen_aday_var")
        if any(m.inceleme_durumu == "incele" for m in gorunen):
            uyari.append("inceleme_gerekli")
            risk.append("dusuk_aday_guveni")
        duzen = getattr(s, "_v22_sutun_kalibrasyonu", None)
        if duzen is not None:
            uyari.extend(duzen.uyarilar)
            if duzen.guven < 0.62:
                risk.append("dusuk_duzen_guveni")
            if abs(duzen.egiklik_derece) >= 1.0:
                risk.append("egik_kaynak")
        if float(rol_bilgi["guven"]) < 0.60:
            risk.append("dusuk_sayfa_rolu_guveni")
        ocr_hata = getattr(s, "ocr_hata", None)
        if ocr_hata:
            pipeline_hatalari.append(f"ocr:{ocr_hata}")
            risk.append("ocr_hatasi")
        aile = _duzen_ailesi_adi(bantlar, meta)
        bilinen_aileler = {str(a.get("ad")) for a in profil.sutun_aileleri}
        if profil.sutun_aileleri and aile.split("_tam_", 1)[0] \
                not in bilinen_aileler:
            risk.append("yeni_duzen")
        risk.extend(_sutun_uyarisi_sayfa_riskleri(duzen))
        risk = list(dict.fromkeys(risk))
        inceleme = bool(risk or pipeline_hatalari)
        bolgeler = tuple(getattr(s, "_v3_duzen_bolgeleri", ()) or ())
        analiz = SayfaAnalizi(
            sayfa_no=i + 1, sayfa_rolu=nihai_rol,
            rol_guveni=rol_bilgi["guven"],
            duzen_ailesi=aile,
            soru_turu=sayfa_turu, adaylar=tuple(meta),
            uyarilar=tuple(dict.fromkeys(uyari)), raster=bool(s.raster),
            duzen_guveni=(duzen.guven if duzen is not None else 0.60),
            sutun_kanitlari=(duzen.kanitlar if duzen is not None else ()),
            egiklik_derece=(duzen.egiklik_derece
                             if duzen is not None else 0.0),
            karar_kimligi=karar_kimligi(
                s, (0.0, 0.0, s.genislik, s.yukseklik), i + 1, "sayfa"),
            onay_durumu=("bekliyor" if inceleme else "otomatik"),
            risk_nedenleri=tuple(risk), duzen_bolgeleri=bolgeler,
            pipeline_hatalari=tuple(pipeline_hatalari),
            inceleme_gerekli=inceleme)
        s._v2_belge_profili = profil
        s._v2_sayfa_analizi = analiz
        s._v2_meta_onbellek = {profil.format: (meta, bantlar, sayfa_fmt)}
        analizler.append(analiz)
    return profil, analizler


def toplu_ocr(sayfalar, is_sayisi=None, tamamlandi=None):
    """Taranmış sayfaların OCR sonuçlarını paralel doldurur (satirlar()
    nesne-içi önbelleğine). PyObjC, Objective-C çağrılarında GIL'i bırakır ve
    her vision_satirlar çağrısı kendi handler'ını kurar → iş parçacıkları
    güvenli, gerçek eşzamanlı. Dönüş: paralel işlenen sayfa listesi.

    tamamlandi(i, n): her sayfa bitince ÇAĞIRAN iş parçacığında çalışır."""
    rasterlar = [s for s in sayfalar
                 if s.raster and s._satir_kesa is None]
    n = OCR_PARALEL if is_sayisi is None else is_sayisi
    if len(rasterlar) < 2 or n < 2:
        return []
    from concurrent.futures import ThreadPoolExecutor, as_completed
    with ThreadPoolExecutor(max_workers=min(n, len(rasterlar))) as havuz:
        isler = [havuz.submit(s.satirlar) for s in rasterlar]
        for i, gelecek in enumerate(as_completed(isler), 1):
            gelecek.result()  # işçideki hatayı yüzeye çıkar
            if tamamlandi:
                tamamlandi(i, len(rasterlar))
    return rasterlar


def belge_hazirla(yollar, dpi=300, ilerleme=None):
    """Yükle + OCR + kalibre — tüm ön yüzlerin ortak açılış adımı.
    Dönüş: (sayfalar, acik, fmt, sutun_xler).
    ilerleme(i, n): sayfa-başı okuma geri çağrısı (GUI ilerleme çubuğu)."""
    sayfalar, acik = belge_sayfalari(yollar, dpi)
    if not sayfalar:
        raise ValueError("işlenecek sayfa yok")
    n = len(sayfalar)
    sayac = [0]

    def _adim(*_):
        sayac[0] += 1
        if ilerleme:
            ilerleme(sayac[0], n)

    # Taranmış sayfalar paralel OCR'lanır (her biten ilerleme sayar); kalan
    # sayfalar (metin katmanı / paralel kapalıysa raster) sırayla okunur.
    paralel = {id(s) for s in toplu_ocr(sayfalar, tamamlandi=_adim)}
    tum = []
    for s in sayfalar:
        tum.append(s.satirlar())
        if id(s) not in paralel:
            _adim()
    rasterlar = [s for s in sayfalar if s.raster]
    hatalilar = [(i + 1, s.ocr_hata) for i, s in enumerate(sayfalar)
                 if s.raster and s.ocr_hata]
    if rasterlar and len(hatalilar) == len(rasterlar):
        # OCR altyapısı tamamen kullanılamıyorsa sessizce boş belge üretmek,
        # kullanıcıya yanlışlıkla "soru yok" dedirtiyordu. Açık belgeleri de
        # burada kapat; çağıran dönüş değerlerini henüz alamadığı için kapatamaz.
        ayrinti = str(hatalilar[0][1]).strip().replace("\n", " ")[:300]
        belge_kapat(acik)
        raise RuntimeError(
            f"OCR başlatılamadı; {len(rasterlar)} taranmış/görüntü sayfası "
            f"okunamadı. Ayrıntı: {ayrinti}")
    fmt, sutunlar = kalibre_et(sayfalar, tum)
    # V3 profil/aday analizi eski dört öğeli dönüş sözleşmesini değiştirmez.
    # Hata kaydedilir: legacy uyumluluk yoluna devam edebilir, strict kapı
    # bu sayfaları asla "%100 güvenli" saymaz ve nihai çıktıyı durdurur.
    try:
        belge_analiz_et(sayfalar, fmt, yollar, tum_satirlar=tum)
    except Exception as exc:  # noqa: BLE001 — geriye uyumlu güvenli dönüş
        for s in sayfalar:
            s._v2_hata = f"{type(exc).__name__}: {exc}"
            s._v3_hata = s._v2_hata
    return sayfalar, acik, fmt, sutunlar


def ocr_hatalari(sayfalar):
    """Kısmen okunamayan raster sayfaları ``[(sayfa_no, neden), ...]`` döndür."""
    return [(i + 1, s.ocr_hata) for i, s in enumerate(sayfalar)
            if getattr(s, "raster", False) and getattr(s, "ocr_hata", None)]


# ------------------------------------------------- bölünmüş soru birleştirme
# Bir soru sütun/sayfa sonunda ikiye bölündüğünde ikinci parça numarasız
# kalır ve bugüne dek ya atılır ya ayrı parça olurdu. kirpma_plani, yüksek
# kesinlikli ŞIK-DEVAMI kanıtıyla (önceki kutuda A,B var - eksik; yetimde
# tam eksik son ek C,D,E var) iki parçayı tek çıktıda birleştirir.

_CUMLE_SONU = re.compile(r"[.!?:;…]['\")\]]?\s*$")


def _yarim_metin(metin):
    """Metin cümle ortasında mı bitiyor? (nokta/soru/iki nokta vb. yok)"""
    return bool(metin) and not _CUMLE_SONU.search(metin)


def beklenen_sik_kumesi(sayfa_metalari):
    """Belgenin tipik şık kümesi ({A..D} ya da {A..E}): ≥3 harf içeren
    kutuların harf-sayısı MOD'u. Yanlış tahmin yalnız birleştirmeyi bastırır
    (güvenli taraf)."""
    boyutlar = [len(m.sik_harfler) for meta in sayfa_metalari for m in meta
                if not m.devam_aday and len(m.sik_harfler) >= 3]
    if not boyutlar:
        return frozenset("ABCDE")
    tipik = max(set(boyutlar), key=boyutlar.count)
    return frozenset("ABCDE"[:max(3, min(5, tipik))])


# ------------------------------------------------- test bölümleri (dikiş)

def _kosucu_bantsiz_basliklar(sayfalar):
    """Sayfa-başı TEST başlıkları; koşucu köşe bantları elenmiş.
    Koşucu bant = numarasız başlık sayfanın üst şeridinde (dekor) YA DA aynı
    metin ~aynı konumda ≥3 sayfada yineleniyor (PRF köşe 'TEST' bandı)."""
    ham = []
    tekrar = {}
    for s in sayfalar:
        try:
            bl = test_basliklari(s.satirlar())
        except Exception:  # noqa: BLE001 — OCR hatası başlıksız devam
            bl = []
        ham.append(bl)
        for no, k, m in bl:
            if no is None:
                anahtar = (m, round(k[0] / 10), round(k[1] / 10))
                tekrar[anahtar] = tekrar.get(anahtar, 0) + 1
    temiz = []
    for i, s in enumerate(sayfalar):
        Y = s.yukseklik
        kalan = []
        for no, k, m in ham[i]:
            if no is None:
                anahtar = (m, round(k[0] / 10), round(k[1] / 10))
                if k[1] < Y * 0.12 or tekrar.get(anahtar, 0) >= 3:
                    continue
            kalan.append((no, k, m))
        temiz.append(kalan)
    return temiz


def test_bolumleri(sayfalar, sayfa_meta, atla=None):
    """Belge-düzeyi test dikişi: kutulara test_no (kitapta yazan yerel numara)
    ve test_sira (belge-geneli benzersiz 1..N) doldurur.

    sayfa_meta: sorulari_tespit_meta çıktıları [(meta, bantlar, sfmt) | None]
    (None = elle düzenlenen sayfa; kutuları atlanır, başlıkları okunur).
    atla: başlıkları da yok sayılacak sayfa indeksleri (cevap anahtarı
    sayfalarındaki 'TEST 1 / TEST 2' sütun başlıkları dikişi şaşırtmasın).
    Dönüş: (sayfa_meta2, testler) — testler: [{test_sira, test_no, baslik,
    sayfa_bas, sayfa_son, soru_bas, soru_son, adet}].

    Yöntem: sayfalar okuma sırasında yürünür; TEST başlığı 'beklemede yeni
    test' açar — test gerçekte İLK numara-sıfırlanan kutuda başlar (başlık
    sayfa altında 'sonraki sayfada başlıyor' habercisi olabilir). Bekleme,
    başlığın sayfasından sonraki sayfanın sonuna kadar sürer; sıfırlanma
    gelmezse ilk kutuda başlar. Başlıksız muhafazakâr sıfırlanma (yeni≤2,
    öncekinden küçük, önceki≥4) da yeni test sayılır. Aynı numaralı yinelenen
    başlık (devam sayfası koşucusu) yeni test AÇMAZ. Hiç sınır yoksa belge
    tek örtük test kabul edilir ve alanlar None kalır (geriye uyum)."""
    basliklar = _kosucu_bantsiz_basliklar(sayfalar)
    for i in (atla or ()):
        basliklar[i] = []

    # --- 1. geçiş: okuma sırası yürüyüşü → segment atamaları
    seg = 0
    seg_bilgi = {0: {"no": None, "baslik": None}}
    atama = {}          # (sayfa_idx, meta_idx) → seg
    bekleyen = None     # {"no", "metin", "sayfa"}
    son_no = None
    for i, s in enumerate(sayfalar):
        sm = sayfa_meta[i]
        meta = sm[0] if sm else []
        olaylar = [((mt.bant_idx, mt.kutu[1], 1), "kutu", j)
                   for j, mt in enumerate(meta)]
        if basliklar[i]:
            G = s.genislik
            bantlar = sm[1] if sm else [(0.0, G)]

            def _b_idx(x0):
                for bi, (a, b) in enumerate(bantlar):
                    if a - G * 0.02 <= x0 < b:
                        return bi
                return min(range(len(bantlar)),
                           key=lambda bi: abs(x0 - bantlar[bi][0]))

            for no, k, m in basliklar[i]:
                # Sayfa-düzeyi başlık (üst bölgede ortalanmış ya da birden çok
                # bantı kaplayan) TÜM sayfa içeriğinden önce gelir; sütun-içi
                # başlık (PRF 'TEST - 3') kendi bandının akışında kalır.
                merkez = (k[0] + k[2]) / 2
                genis = sum(1 for a, b in bantlar if k[0] < b and k[2] > a) > 1
                ortali = abs(merkez - G / 2) < G * 0.12
                # Sayfanın en üst kenarındaki sağ/sol hizalı koşucu başlık da
                # bütün sayfaya aittir. Onu bulunduğu sütunun olay sırasına
                # bırakırsak soldaki ilk sorular başlıktan önce işlenir; test
                # kimliği bir sonraki teste kadar kayar. Daha aşağıdaki gerçek
                # sütun-içi başlıkların davranışı korunur.
                ust_kosucu = k[1] < s.yukseklik * 0.08
                if k[1] < s.yukseklik * 0.3 and \
                        (ortali or genis or ust_kosucu):
                    konum = (-1, k[1], 0)
                else:
                    konum = (_b_idx(merkez), k[1], 0)
                olaylar.append((konum, "baslik", (no, m)))
        olaylar.sort(key=lambda o: o[0])
        for _, tur, veri in olaylar:
            if tur == "baslik":
                no, m = veri
                if no is not None and bekleyen is None \
                        and seg_bilgi[seg]["no"] == no:
                    continue        # aynı testin devam-sayfası koşucusu
                bekleyen = {"no": no, "metin": m, "sayfa": i}
                continue
            mt = meta[veri]
            n = mt.numara
            if not mt.devam_aday:
                if bekleyen is not None:
                    sifir = n is not None and (
                        n <= 2 or (son_no is not None and n < son_no))
                    zorla = i > bekleyen["sayfa"] + 1
                    if sifir or zorla or son_no is None:
                        seg += 1
                        seg_bilgi[seg] = {"no": bekleyen["no"],
                                          "baslik": bekleyen["metin"]}
                        bekleyen = None
                        son_no = None
                elif n is not None and son_no is not None \
                        and n <= 2 and n < son_no and son_no >= 4:
                    seg += 1
                    seg_bilgi[seg] = {"no": None, "baslik": None}
                    son_no = None
            atama[(i, veri)] = seg
            if n is not None and not mt.devam_aday:
                son_no = n

    # --- 2. geçiş: segment → (test_sira, test_no) etiketleme
    dolu_segler = sorted({v for v in atama.values()})
    baslikli = any(b["baslik"] is not None or b["no"] is not None
                   for b in seg_bilgi.values())
    if len(dolu_segler) <= 1 and not baslikli:
        return sayfa_meta, []       # tek örtük test → dokunma (geriye uyum)
    seg_ata = {}
    sira = 0
    yerel_onceki = None
    for sg in dolu_segler:
        bilgi = seg_bilgi[sg]
        sira += 1
        no = bilgi["no"]
        if no is None:
            if sg == 0 and baslikli:
                no = None           # başlık öncesi ön-madde içeriği
            else:
                no = (yerel_onceki + 1) if isinstance(yerel_onceki, int) else 1
        seg_ata[sg] = (sira, no, bilgi["baslik"])
        if no is not None:
            yerel_onceki = no

    # --- meta'ları doldur + özet
    testler = {}
    sayfa_meta2 = []
    for i, sm in enumerate(sayfa_meta):
        if sm is None:
            sayfa_meta2.append(None)
            continue
        meta, bantlar, sfmt = sm
        yeni = []
        for j, mt in enumerate(meta):
            sg = atama.get((i, j))
            if sg in seg_ata:
                t_sira, t_no, baslik = seg_ata[sg]
                mt = mt._replace(test_no=t_no, test_sira=t_sira)
                if not mt.devam_aday:
                    oz = testler.setdefault(t_sira, {
                        "test_sira": t_sira, "test_no": t_no,
                        "baslik": baslik, "sayfa_bas": i + 1,
                        "sayfa_son": i + 1, "soru_bas": None,
                        "soru_son": None, "adet": 0})
                    oz["sayfa_son"] = i + 1
                    oz["adet"] += 1
                    if mt.numara is not None:
                        oz["soru_bas"] = (mt.numara if oz["soru_bas"] is None
                                          else min(oz["soru_bas"], mt.numara))
                        oz["soru_son"] = (mt.numara if oz["soru_son"] is None
                                          else max(oz["soru_son"], mt.numara))
            yeni.append(mt)
        sayfa_meta2.append((yeni, bantlar, sfmt))
    return sayfa_meta2, [testler[k] for k in sorted(testler)]


# ------------------------------------------------- seçim söz dizimi

_SECIM_TEST = re.compile(r"^(?:test|t)\s*(\d+)?(?:\s*#\s*(\d+))?"
                         r"\s*(?::\s*(.*))?$")
_SECIM_SAYFA = re.compile(r"^(?:sayfa|s)\s*(\d+)(?:\s*:\s*(.*))?$")
_SECIM_ARALIK = re.compile(r"^(\d+)(?:\s*-\s*(\d+))?$")


def _araliklari_coz(metin, baglam):
    """'2-10, 15' → [(2,10), (15,15)]. Hatalıda Türkçe ValueError."""
    aralik = []
    for parca in metin.split(","):
        parca = parca.strip()
        if not parca:
            continue
        m = _SECIM_ARALIK.match(parca)
        if not m:
            raise ValueError(f"anlaşılmayan aralık: '{parca}' ({baglam}). "
                             "Örnek biçim: 2-10 ya da tek soru için 7")
        bas = int(m.group(1))
        son = int(m.group(2)) if m.group(2) else bas
        if son < bas:
            bas, son = son, bas
        aralik.append((bas, son))
    if not aralik:
        raise ValueError(f"boş aralık ({baglam})")
    return aralik


def secim_ayristir(metin):
    """Seçim belirtimini kurallara ayrıştırır. Söz dizimi (';' ya da satır
    sonu ile ayrılır; büyük/küçük harf serbest):
      test 5: 2-10   → 5. testin 2-10. soruları  (kısa: t5:2-10,15)
      t5             → 5. testin tamamı
      t5#2:1-4       → yerel no 5, belge-geneli 2. test (yinelenen 'TEST 5')
      #3 / t#3       → belge-geneli 3. test (yerel numarasız seçim)
      sayfa 12: 3-5  → 12. sayfadaki 3-5 numaralı sorular (kısa: s12:3)
      s12            → 12. sayfanın tamamı
      27-40 / 27     → çıktı sırasına göre (test bilgisinden bağımsız)
    Dönüş: [{"tur","no","sira","aralik"}] — aralik: [(bas,son)] | None (tümü).
    Hatalı söz diziminde Türkçe ValueError."""
    kurallar = []
    for parca in re.split(r"[;\n]+", metin):
        parca = parca.strip().lower().replace("İ", "i")
        if not parca:
            continue
        m = _SECIM_TEST.match(parca)
        if m and (m.group(1) or m.group(2)):
            kurallar.append({
                "tur": "test",
                "no": int(m.group(1)) if m.group(1) else None,
                "sira": int(m.group(2)) if m.group(2) else None,
                "aralik": (_araliklari_coz(m.group(3), f"kural '{parca}'")
                           if m.group(3) and m.group(3).strip() else None)})
            continue
        if parca.startswith("#") and _SECIM_ARALIK.match(parca[1:].strip()):
            g = _SECIM_ARALIK.match(parca[1:].strip())
            kurallar.append({"tur": "test", "no": None,
                             "sira": int(g.group(1)), "aralik": None})
            continue
        m = _SECIM_SAYFA.match(parca)
        if m:
            kurallar.append({
                "tur": "sayfa", "no": int(m.group(1)), "sira": None,
                "aralik": (_araliklari_coz(m.group(2), f"kural '{parca}'")
                           if m.group(2) and m.group(2).strip() else None)})
            continue
        if _SECIM_ARALIK.match(parca) or "," in parca:
            kurallar.append({"tur": "global", "no": None, "sira": None,
                             "aralik": _araliklari_coz(parca,
                                                       f"kural '{parca}'")})
            continue
        raise ValueError(
            f"anlaşılmayan seçim kuralı: '{parca}'. Örnekler: "
            "\"test 5: 2-10\", \"t3\", \"s12: 3-5\", \"27-40\"")
    if not kurallar:
        raise ValueError("boş seçim belirtimi")
    return kurallar


def _aralikta(no, aralik):
    return aralik is None or any(b <= no <= s for b, s in aralik)


def secim_uygula(parca_meta, kurallar, testler):
    """Seçim kurallarını plan-parça metadata'sına uygular.
    parca_meta[j]: {"test_no","test_sira","soru_no","sayfa",...} (plan sırası).
    Dönüş: (indeksler:set, uyarilar:[str]). Var olmayan test/sayfa/soru için
    kullanıcıya yol gösteren Türkçe uyarı üretir."""
    secilen = set()
    uyarilar = []

    def _test_ozeti_metni():
        if not testler:
            return "Belgede test bölümü tespit edilmedi."
        satirlar = []
        for t in testler:
            ad = (f"test {t['test_no']}" if t["test_no"] is not None
                  else "test ?")
            soru = (f"soru {t['soru_bas']}-{t['soru_son']}"
                    if t["soru_bas"] is not None else "numarasız")
            satirlar.append(f"#{t['test_sira']} {ad} ({soru}, {t['adet']} soru)")
        return "Mevcut testler: " + "; ".join(satirlar)

    for k in kurallar:
        onceki = len(secilen)
        if k["tur"] == "test":
            hedefler = [t for t in testler
                        if (k["no"] is None or t["test_no"] == k["no"])
                        and (k["sira"] is None or t["test_sira"] == k["sira"])]
            if not hedefler:
                ad = (f"test {k['no']}" if k["no"] is not None
                      else f"#{k['sira']}")
                uyarilar.append(f"{ad} bulunamadı. {_test_ozeti_metni()}")
                continue
            if len(hedefler) > 1 and k["sira"] is None:
                uyarilar.append(
                    f"test {k['no']} belgede {len(hedefler)} kez geçiyor "
                    f"(sıra: {', '.join(str(t['test_sira']) for t in hedefler)})"
                    f" — tümü seçildi. Tek birini seçmek için "
                    f"t{k['no']}#{hedefler[0]['test_sira']} yazın.")
            siralar = {t["test_sira"] for t in hedefler}
            atlanari = 0
            for j, pm in enumerate(parca_meta):
                if pm["test_sira"] not in siralar:
                    continue
                if pm["soru_no"] is None:
                    if k["aralik"] is None:
                        secilen.add(j)
                    else:
                        atlanari += 1
                elif _aralikta(pm["soru_no"], k["aralik"]):
                    secilen.add(j)
            if atlanari:
                uyarilar.append(
                    f"{atlanari} numarasız soru, aralık kuralıyla "
                    "eşlenemediği için atlandı (tüm testi 't<no>' ile seçin).")
        elif k["tur"] == "sayfa":
            sayfada = [(j, pm) for j, pm in enumerate(parca_meta)
                       if pm["sayfa"] == k["no"]]
            if not sayfada:
                uyarilar.append(f"sayfa {k['no']} üzerinde soru bulunamadı.")
                continue
            numarali = any(pm["soru_no"] is not None for _, pm in sayfada)
            for sirano, (j, pm) in enumerate(sayfada, 1):
                no = pm["soru_no"] if numarali else sirano
                if no is not None and _aralikta(no, k["aralik"]):
                    secilen.add(j)
        else:  # global çıktı sırası (1-tabanlı)
            for j in range(len(parca_meta)):
                if _aralikta(j + 1, k["aralik"]):
                    secilen.add(j)
        if len(secilen) == onceki and k["tur"] != "test":
            uyarilar.append(f"kural hiç soru seçmedi: {k}")
    return secilen, uyarilar


def soru_kimlikleri(parca_meta):
    """parca_meta listesine benzersiz string kimlik ata (web tıkla-seç,
    etiketleme ve seçim için ortak). Kimlik: 'p{sayfa}s{no}' (numaralı) /
    'p{sayfa}_{kutu}' (numarasız); çakışmada '_2' eki. Dönüş: kimlik listesi
    (parca_meta ile paralel).

    Çapa yalnız SAYFA ve SORU NUMARASIDIR — ikisi de kitapta basılıdır ve
    tespit sonucuna göre kaymaz. Test numaraları bilinçli olarak dışarıda:
    ``test_sira`` belge-geneli sıradır, ``test_no`` da bölüm dikişine bağlıdır;
    belgenin BAŞKA bir yerinde bir sayfanın kesim hattına girip girmemesi
    ikisini de kaydırır ve ilgisiz soruların kimliğini bozar. Etiketler ve
    elle cevap düzeltmeleri bu kimliğe bağlı olduğu için bu kabul edilemez.

    Ölçüldü (cozumler1, sayfa vetosu amaç duyarlı yapılmadan önce/sonra,
    101 ortak kesim): ``t{test_sira}s{no}`` → 73 kimlik kaydı,
    ``p{sayfa}t{test_no}s{no}`` → 15, ``p{sayfa}s{no}`` → 0 (benzersizlik
    korunarak). Aynı sayfada aynı numara iki kez görünürse '_2' eki ayırır."""
    def _temel(pm):
        if pm.get("soru_no") is not None:
            return f"p{pm.get('sayfa')}s{pm['soru_no']}"
        si, ki = (next((p for p in pm["parcalar_idx"] if p[1] is not None),
                       pm["parcalar_idx"][0]) if pm.get("parcalar_idx")
                  else (pm.get("sayfa", 1) - 1, 0))
        return f"p{si}_{ki}"

    gorulen, kimlikler = {}, []
    for pm in parca_meta:
        k = _temel(pm)
        if k in gorulen:
            gorulen[k] += 1
            k = f"{k}_{gorulen[k]}"
        else:
            gorulen[k] = 1
        kimlikler.append(k)
    return kimlikler


def _tr_normalize(metin):
    """Türkçe-güvenli normalizasyon: küçült + aksan katla (arama/etiket
    eşleşmesi için). 'İ'→'i', 'I'→'i', 'Ş'→'s' vb. Önce NFC birleştirme:
    macOS'ta 'ö' bazen ayrık (o + birleşen ¨) gelir; NFC olmadan katlama kaçar."""
    metin = unicodedata.normalize("NFC", metin)
    metin = metin.replace("İ", "i").replace("I", "ı")
    metin = metin.lower()
    cevir = str.maketrans("çğıöşü", "cgiosu")
    return metin.translate(cevir)


def konu_sozlugu_oku(yol):
    """konular.csv oku → [(konu, [anahtar_kelime_normal, ...])].
    Biçim: her satır 'Konu Adı;anahtar1,anahtar2,...' (# ile yorum, ; ayraç).
    Dosya yoksa boş liste (etiketleme sessizce atlanır)."""
    sozluk = []
    try:
        with open(yol, encoding="utf-8") as f:
            for satir in f:
                satir = satir.strip()
                if not satir or satir.startswith("#") or ";" not in satir:
                    continue
                konu, kelimeler = satir.split(";", 1)
                anahtarlar = [_tr_normalize(k.strip())
                              for k in kelimeler.split(",") if k.strip()]
                if konu.strip() and anahtarlar:
                    sozluk.append((konu.strip(), anahtarlar))
    except OSError:
        return []
    return sozluk


def konu_etiketle(metin, sozluk, en_fazla=3):
    """Soru metnini konu sözlüğüyle skorlar. Dönüş: (en_iyi_konu|None,
    [aday_konu, ...]). Kelime-sınırlı eşleşme sayısına göre; berabere en çok
    anahtarı eşleşen kazanır. Skor 0 → None."""
    if not sozluk or not metin:
        return None, []
    norm = _tr_normalize(metin)
    skorlar = []
    for konu, anahtarlar in sozluk:
        skor = sum(1 for a in anahtarlar
                   if re.search(r"\b" + re.escape(a) + r"\b", norm))
        if skor:
            skorlar.append((skor, konu))
    skorlar.sort(reverse=True)
    adaylar = [k for _, k in skorlar[:en_fazla]]
    return (adaylar[0] if adaylar else None), adaylar


def soru_metni_ayristir(satir_metinleri):
    """Kutu satır metinlerinden gövde + şıkları (A–E) ayırır.
    Dönüş: {"metin", "govde", "siklar": {"A": "...", ...}}.
    Şık işaretleri SIK_DESENI ile taranır; harfler A'dan sırayla ilerlemeli
    (metin içi '(a)' gürültüsü sahte bölme yapmaz). Şık bulunamazsa
    (açık uçlu / OCR eksik) siklar boş, tüm metin gövdede kalır."""
    metin = " ".join(m.strip() for m in satir_metinleri if m.strip())
    # numara önekini gövdeden ayıkla ("12. " → "")
    metin = re.sub(r"^\s*\d{1,3}[.)]\s*", "", metin)
    bolmeler = []          # (konum, harf)
    beklenen = 0           # 'A' + beklenen
    for e in SIK_DESENI.finditer(metin):
        harf = e.group(1).upper()
        if ord(harf) - 65 == beklenen:      # sıradaki şık
            bolmeler.append((e.start(1) - (0 if e.start(1) == e.start()
                                           else 1), harf))
            beklenen += 1
        elif harf == "A" and beklenen == 0:
            bolmeler.append((e.start(1), harf))
            beklenen = 1
    if not bolmeler:
        return {"metin": metin, "govde": metin, "siklar": {}}
    govde = metin[:bolmeler[0][0]].strip()
    siklar = {}
    for j, (poz, harf) in enumerate(bolmeler):
        son = bolmeler[j + 1][0] if j + 1 < len(bolmeler) else len(metin)
        icerik = metin[poz:son].strip()
        icerik = re.sub(r"^[A-Ea-e]\s*[.)]\s*", "", icerik).strip()
        siklar[harf] = icerik
    return {"metin": metin, "govde": govde, "siklar": siklar}


def soru_metni_ocr(kirpma):
    """Bir soru KIRPMASININ (PIL) metnini OCR ile çıkarıp gövde+şık olarak
    ayrıştırır (macOS: Vision, diğer platformlar: easyocr). Metin
    metadata'da boş kaldığında (görüntü-gömülü kaynak: numarası text,
    gövdesi resim olan sayfalar) bankada arama/konu için kullanılır.
    Dönüş: soru_metni_ayristir çıktısı ({"metin","govde","siklar"})."""
    if sys.platform == "darwin":
        satirlar = vision_satirlar(kirpma)
    else:
        satirlar = [(s.metin, s.kutu) for s in easyocr_satirlar(kirpma)]
    metinler = [m for m, _ in sorted(satirlar, key=lambda t: t[1][1])]
    return soru_metni_ayristir(metinler)


# ------------------------------------------------- cevap anahtarı çıkarma

def _cevap_cesitliligi(satirlar):
    """(çift_sayısı, ızgara_satır, benzersiz_harf, baskın_oran). Baskın_oran:
    en sık harfin tüm çiftlere oranı — 'D, Y' (Doğru/Yanlış) çözüm sayfaları
    tek harfte toplanır, gerçek A–E cevap anahtarı dağılır."""
    ciftler = izgara = 0
    from collections import Counter
    say = Counter()
    for m, _, _ in satirlar:
        # Cebirsel seçenek satırları ("A) a + 2b + 3c + 4d") içindeki
        # katsayı-harf çiftleri CEVAP_CIFTI biçimine tesadüfen uyar. Bunlar
        # cevap anahtarı hücresi değil, gerçek sorunun seçenekleridir. Ancak
        # kitapçık etiketli anahtar satırları da "A) 1-B 2-C ..." başlar;
        # birden çok açık ayraçlı numara-harf çifti taşıyan satırı koru.
        secenek_basli = re.match(r"^\s*[A-E]\s*[).:]\s+", m, re.I)
        ayracli_cift = re.findall(
            r"(?<!\d)\d{1,3}\s*[).\-–—:]\s*[A-Ea-e]"
            r"(?![A-Za-zÇĞİÖŞÜçğıöşü0-9.)])", m)
        if secenek_basli and len(ayracli_cift) < 2:
            continue
        bulunan = CEVAP_CIFTI.findall(m)
        ciftler += len(bulunan)
        if len(bulunan) >= 2:
            izgara += 1
        for _, h in bulunan:
            say[h.upper()] += 1
    baskin = max(say.values()) / max(1, ciftler) if say else 1.0
    return ciftler, izgara, len(say), baskin


def _cevap_sayfasi_mi(satirlar):
    """Sayfa bir CEVAP ANAHTARI sayfası mı? 'CEVAP ANAHTARI' başlığı + yeterli
    çift YA DA başlıksız yoğun numara-harf ızgarası arar. Yanlış-pozitif
    koruması: gerçek cevap anahtarında şıklar A–E'ye dağılır → ≥3 benzersiz
    harf ve baskın harf oranı ≤%70. Böylece 'D, Y' (Doğru/Yanlış) çözüm
    sayfaları ve tek tük 'Cevap: E' soru sayfaları elenir."""
    baslik = any(CEVAP_BASLIK.search(m) for m, _, _ in satirlar)
    ciftler, izgara, benzersiz, baskin = _cevap_cesitliligi(satirlar)
    if benzersiz < 3 or baskin > 0.70:
        return False
    if baslik and ciftler >= 8:
        return True
    # Bazı metin-katmanlı PDF'ler cevap tablosunun her hücresini ayrı bir
    # satır olarak verir ("1. D", "2. E", ...). Böyle bir sayfada yüzlerce
    # gerçek çift olsa bile ``izgara`` sıfır kalır. En az bir TEST/DENEME
    # başlığı bu tek-hücreli düzen için güçlü ve belgeye özgü ek kanıttır;
    # sıradan soru sayfalarındaki sayısal şıkları gevşetmez.
    testli_tek_hucre = ciftler >= 12 and bool(test_basliklari(satirlar))
    return ciftler >= 12 and (izgara >= 3 or testli_tek_hucre)


def _belge_sayfa_rolleri(sayfalar, kalite="legacy", *, fmt):
    """Belge için ``(dışlanacak, soru_sayfaları|None)`` kümelerini üret.

    ``dışlanacak`` klasik cevap anahtarlarına ek olarak "Mini Sınav
    Çözümleri" gibi bir başlıkla başlayan devamlı çözüm bölümünü kapsar.
    Belge genelinde en az üç TEST/Mini Sınav işareti varsa kitap
    yapılandırılmış kabul edilir; bu durumda konu anlatımı/ders notu sayfaları
    ancak güçlü soru kanıtı taşıyorsa tutulur. Küçük veya başlıksız belgelerde
    ``soru_sayfaları=None`` döner ve eski format-agnostik davranış korunur.

    ``fmt``: belgenin amacı (bkz. ``belge_formati``) — ZORUNLU. Sayfa vetosu
    amaca GÖRELİDİR: çözüm kitabında çözüm sayfası aykırı değil, kesilmek
    istenen içeriktir (aday puanlamasındaki aynı ayrım için bkz.
    ``aykiri_roller``). Amaç üç ayrı veto kolunu birden etkiler: çözüm bölümü
    başlığı, rol vetosu ve legacy beyaz listesi — biri atlanırsa sayfa yine
    aday üretmeden ölür. ``fmt=None`` "amaç bilinmiyor" demektir ve eski
    davranışı korur; parametre keyword-only ve zorunludur ki yeni bir çağıran
    onu atlayıp sessizce sessiz-kayıp hatasını geri getiremesin.
    """
    cozum_kitabi = fmt == "cozumlu"
    tum_satirlar = []
    for s in sayfalar:
        try:
            tum_satirlar.append(s.satirlar())
        except Exception:  # noqa: BLE001 — OCR hatalı sayfayı burada sınıflama
            tum_satirlar.append([])

    disla = set()
    cozum_bolumu = False
    mini_isaretleri = set()
    test_isaretleri = set()
    for i, satirlar in enumerate(tum_satirlar):
        metinler = [m.strip() for m, _, _ in satirlar if m.strip()]
        # Çözüm bölümü başlığı da amaca GÖRELİDİR: soru kitabının arkasındaki
        # "ÇÖZÜMLER" eki dışlanır, ama çözüm kitabında aynı başlık içeriğin
        # başlangıcıdır. Bu kol atlanmazsa rol vetosunu düzeltmek yetmez —
        # başlıklı bir çözüm kitabında sayfalar yine aday üretmeden ölür.
        # Gerçek cevap anahtarı sayfaları burada değil, aşağıdaki
        # `_cevap_sayfasi_mi` ile yakalanır; o koruma her belgede açıktır.
        if not cozum_kitabi:
            if any(COZUM_BOLUM_BASLIK.match(m) for m in metinler):
                cozum_bolumu = True
            bitis = any(COZUM_BOLUM_BITIS.match(m) for m in metinler)
            if cozum_bolumu and not bitis:
                disla.add(i)
            if bitis:
                cozum_bolumu = False
        if _cevap_sayfasi_mi(satirlar):
            disla.add(i)
        birlesik = " ".join(metinler)
        if MINI_SINAV_DESENI.search(birlesik) and i not in disla:
            mini_isaretleri.add(i)
        if test_basliklari(satirlar):
            test_isaretleri.add(i)

    # V2 sayfa rolü, yalnız "TEST" başlığı taşıyan yapılandırılmış kitaplara
    # bağlı değildir. Başlıksız deneme, açık uçlu yazılı ve konu+alıştırma
    # karışık kitaplarında da soru sayfalarını seçer; yüksek güvenli kapak,
    # içindekiler, çözüm ve konu sayfaları kesim hattına hiç girmez.
    rol_bilgileri = [_sayfa_rolu_belirle(sat, i + 1, len(tum_satirlar))
                     for i, sat in enumerate(tum_satirlar)]
    # Sayfa vetosu, aday puanlamasıyla AYNI amaç istisnasını uygulamalıdır:
    # çözüm kitabında çözüm sayfası aykırı değil, içerik sayfasıdır. Veto
    # burada çalıştığı için sayfa `sorulari_tespit_meta`'ya hiç girmiyordu;
    # aday üretilmediğinden kesim ne çıktı ne de İncele kovasına düşüyor,
    # yani "İncele tam tümleyendir" güvencesi kırılıyordu. Ölçüldü: cozumler1
    # s39-47'de tespit 87 kutu bulurken teslim 21'de kalıyordu (66 sessiz
    # kayıp); istisna eklenince teslim 87'ye çıkıp tespitle birebir örtüştü.
    veto_rolleri = {"kapak", "içindekiler", "çözüm", "cevap_anahtari"}
    icerik_rolleri = {"soru", "karma"}
    if cozum_kitabi:
        veto_rolleri.discard("çözüm")
        # Beyaz liste de amaca uymalı. Aksi hâlde legacy'de düzeltme ETKİSİZ
        # kalır: 'çözüm' sayfası `disla`dan çıkar ama içerik rolleri kümesine
        # giremediği için pozitif liste onu yine eler ve sayfa aday üretmeden
        # ölür. Ölçüldü: yalnız rol vetosu düzeltilince legacy'de cozumler1
        # s39-44 ve s46 hâlâ sıfır kesim veriyordu.
        icerik_rolleri.add("çözüm")
    for i, (rol, guven, _) in enumerate(rol_bilgileri):
        if guven >= 0.72 and rol in veto_rolleri:
            disla.add(i)
    v2_soru = {i for i, (rol, guven, _) in enumerate(rol_bilgileri)
               if i not in disla and rol in icerik_rolleri
               and guven >= 0.64}
    # V3 strict/balanced: pozitif whitelist kullanıp kalan sayfaları sessizce
    # atmak yasak. Yalnız yüksek güvenli kesin soru-dışı roller dışlanır;
    # belirsiz/adaysız sayfa kalite kapısına kadar yaşar. Legacy eski
    # davranışı tam korur.
    if kalite in ("strict", "balanced"):
        return disla, None
    if v2_soru:
        return disla, v2_soru

    yapili = len(mini_isaretleri | test_isaretleri) >= 3
    if not yapili:
        return disla, None

    soru_sayfalari = set()
    for i, satirlar in enumerate(tum_satirlar):
        if i in disla:
            continue
        metinler = [m for m, _, _ in satirlar]
        num_say = len(numara_adaylari(satirlar))
        siklar = {h for m in metinler for h in _sik_harfleri(m)}
        govde = any(SORU_GOVDE.search(m) for m in metinler)
        yazma = any(NOKTALI_SATIR.search(m) and not TOC_LIDER.search(m)
                    for m in metinler)
        testli = i in test_isaretleri
        minili = i in mini_isaretleri
        mini_devam = i > 0 and (i - 1) in mini_isaretleri

        # Normal test sayfası/başlangıcı; TOC'deki "TEST" satırı ancak gerçek
        # şık veya soru gövdesi de varsa geçebilir.
        test_kaniti = testli and num_say >= 1 \
            and (len(siklar) >= 3 or govde)
        # Açık uçlu Mini Sınav ve hemen sonraki devam sayfası.
        mini_kaniti = (minili or mini_devam) and num_say >= 1 \
            and (govde or yazma or len(siklar) >= 2)
        # Başlığı görüntü olarak basılmış ya da OCR'ın kaçırdığı çoktan
        # seçmeli sayfa: birden çok numara + A-E kümesi güçlü bağımsız kanıt.
        yogun_coktan_secmeli = num_say >= 2 and len(siklar) >= 4
        if test_kaniti or mini_kaniti or yogun_coktan_secmeli:
            soru_sayfalari.add(i)
    return disla, soru_sayfalari


def cevap_anahtari_bul(sayfalar):
    """Cevap anahtarı sayfalarını / 'CEVAP ANAHTARI' başlıklı alt bölgeleri
    tarar. Dönüş: okuma sırasında [{"test_no": int|None, "cevaplar":
    {soru_no: 'A'..'E'}}] blokları. Best-effort: anahtar yoksa boş liste."""
    bloklar = []
    for s in sayfalar:
        try:
            satirlar = s.satirlar()
        except Exception:  # noqa: BLE001 — OCR hatası anahtarı atla
            continue
        if _cevap_sayfasi_mi(satirlar):
            bolge = satirlar
        else:
            bas_y = min((k[1] for m, k, _ in satirlar
                         if CEVAP_BASLIK.search(m)), default=None)
            if bas_y is None:
                continue
            bolge = [(m, k, b) for m, k, b in satirlar if k[1] >= bas_y - 1]
        basliklar = [(no, k) for no, k, _ in test_basliklari(bolge)
                     if no is not None]

        def _yakin_test(k):
            cx = (k[0] + k[2]) / 2
            en_iyi = None
            en_kucuk = None
            for no, hk in basliklar:
                if k[1] < hk[1] - 2:
                    continue        # başlığın üstündeki satır ona ait değil
                d = abs(cx - (hk[0] + hk[2]) / 2) + (k[1] - hk[1]) * 0.25
                if en_kucuk is None or d < en_kucuk:
                    en_iyi, en_kucuk = no, d
            return en_iyi

        sayfa_blok = {}     # test_no|None → {soru: harf}
        for m, k, _ in bolge:
            for no_s, harf in CEVAP_CIFTI.findall(m):
                sayfa_blok.setdefault(_yakin_test(k), {})[int(no_s)] = \
                    harf.upper()
        # blokları başlık okuma sırasında (sütun x → y) yay
        gorulen = set()
        for no, hk in sorted(basliklar, key=lambda t: (round(t[1][0] / 40),
                                                       t[1][1])):
            if no in sayfa_blok and no not in gorulen:
                bloklar.append({"test_no": no, "cevaplar": sayfa_blok[no]})
                gorulen.add(no)
        if None in sayfa_blok:
            bloklar.append({"test_no": None, "cevaplar": sayfa_blok[None]})
    return bloklar


def cevaplari_esle(testler, bloklar):
    """Belgenin test sırası ile anahtar bloklarını hizalar (yinelenen yerel
    test numaraları — Palme ünite-başı 'TEST 1' — sırayla eşlenir).
    Dönüş: {(test_sira|None, soru_no): 'A'..'E'}."""
    esleme = {}
    kalan = list(bloklar)
    for t in testler:
        sec = next((b for b in kalan if b["test_no"] == t["test_no"]), None)
        if sec is None:
            continue
        kalan.remove(sec)
        for no, harf in sec["cevaplar"].items():
            esleme[(t["test_sira"], no)] = harf
    for b in kalan:
        if b["test_no"] is None:
            for no, harf in b["cevaplar"].items():
                esleme.setdefault((None, no), harf)
    return esleme


def _birlesme_uygun(onceki, yetim, beklenen, agresif):
    """Önceki kutunun yarım sorusu ile yetim bölge birleştirilebilir mi?
    Varsayılan kural yüksek kesinlikli ŞIK ayrışmasıdır; örtüşen harf
    (her ikisinde de 'A' gibi) = yetim aslında numarası kaçmış YENİ soru →
    birleştirme reddedilir (bugünkü davranış korunur)."""
    if yetim.numara is not None:
        return False
    o, y = onceki.sik_harfler, yetim.sik_harfler
    sirali = sorted(beklenen)
    if o and y and not (o & y):
        k = len(o)
        # önceki = beklenenin ÖN EKİ (ör. {A,B}), yetim ⊇ kalan SON EK
        if k < len(sirali) and o == set(sirali[:k]) and set(sirali[k:]) <= y:
            return True
    if not o and y and beklenen <= y and _yarim_metin(onceki.son_metin):
        return True   # gövde bölünmüş, şıkların TÜMÜ karşı sütunda
    if agresif and not y and not yetim.govde_var \
            and _yarim_metin(onceki.son_metin):
        return True   # şık kanıtı yok — yalnız --birlestirme-agresif ile
    return False


def _ortak_uyaran_haritasi(sayfa, satirlar, bantlar):
    """Ortak parça/şekli kullanan soru numaralarını ek kırpma kutusuna bağlar.

    Dönüş ``{soru_no: kutu}``. Ortak bölgenin altı, başlığın bulunduğu bantta
    aralığın ilk gerçek soru çapasıyla sınırlanır. Böylece komşu soru ortak
    metne karışmaz; farklı sütundaki her soru aynı uyaranı güvenle paylaşır.
    """
    G, Y = sayfa.genislik, sayfa.yukseklik
    numaralar = numara_adaylari(satirlar)
    sonuc = {}
    for metin, hk, _ in satirlar:
        es = ORTAK_SORU_ARALIGI.match(metin)
        if not es:
            continue
        bas, son = int(es.group(1)), int(es.group(2))
        if son < bas or son - bas > 20:
            continue
        # Başlık hangi bantla en fazla yatay örtüşüyorsa ortak metin oradadır.
        bi = max(range(len(bantlar)), key=lambda z:
                 max(0.0, min(hk[2], bantlar[z][1])
                     - max(hk[0], bantlar[z][0])))
        ba, bb = bantlar[bi]
        alt_capalar = []
        for no, nk, _ in numaralar:
            cx = (nk[0] + nk[2]) / 2
            if bas <= no <= son and ba - G * 0.02 <= cx <= bb + G * 0.02 \
                    and nk[1] > hk[3] + Y * 0.025:
                alt_capalar.append(nk[1])
        if not alt_capalar:
            continue
        y0 = max(0.0, hk[1] - Y * 0.008)
        y1 = min(alt_capalar) - Y * 0.008
        if y1 - y0 < Y * 0.05:
            continue
        # Metin/görsel taşmasını aynı bant içinde kapsa; PDF'de bbox kesin,
        # rasterda tam bant kırpılıp beyaz kenarlar sonradan traşlanır.
        if sayfa.raster:
            x0, x1 = ba, bb
        else:
            ic = _bolge_satirlari(satirlar, y0, y1, ba, bb, G * 0.012)
            x0 = max(ba, min((k[0] for _, k in ic), default=ba) - 4)
            x1 = min(bb, max((k[2] for _, k in ic), default=bb) + 4)
            for rx0, ry0, rx1, ry1 in sayfa.resim_kutulari():
                if ry0 < y1 and ry1 > y0 and ba <= (rx0 + rx1) / 2 <= bb:
                    x0, x1 = max(ba, min(x0, rx0)), min(bb, max(x1, rx1))
        kutu = (x0, y0, x1, y1)
        for no in range(bas, son + 1):
            sonuc[no] = kutu
    return sonuc


def _aday_ciktiya_girer(m, kalite):
    if m.inceleme_durumu == "reddedildi":
        return False
    if kalite == "legacy":
        return True
    # Balanced güvenli alt kümeyi yazabilir; strict ayrıca belge düzeyinde
    # bekleyen tek riskte tüm çıktıyı durdurur.
    return (m.inceleme_durumu == "otomatik"
            or m.onay_durumu == "onaylandi")


def _kova_secici(kalite, kova):
    """Hangi adayların bu koşumda kesileceğini belirleyen yüklem.

    kova="cikti"  → bugünkü davranış birebir (otomatik/onaylı alt küme).
    kova="incele" → TAM TÜMLEYENİ: tespit edilmiş ama otomatik teslim
                    edilemeyen adaylar. Bunlar eskiden strict/balanced kipte
                    SESSİZCE düşüyordu; "sıfır hata" hedefi otomatik kovanın
                    kusursuz olmasını ister ama emin olunamayan kesimin
                    KAYBOLMASINI değil — ayrı bir klasöre gerekçesiyle yazılır.
    """
    if kova == "cikti":
        return lambda m: _aday_ciktiya_girer(m, kalite)
    if kova == "incele":
        return lambda m: (aday_tespit_edildi(m)
                          and not _aday_ciktiya_girer(m, kalite))
    raise ValueError(f"bilinmeyen kova: {kova}")


def aday_inceleme_gerekcesi(m):
    """Bir adayın neden otomatik teslim edilemediğinin okunabilir gerekçesi.

    Ölçüldü: `incele` kutularının en büyük grubu (28/49) HİÇBİR uyarı
    taşımıyor — güven 0,55-0,82 arasında kaldığı için düşüyorlar ama nedeni
    hiçbir yere yazılmıyordu. İncele klasörüne gerekçesiz dosya koymak
    kullanıcıyı sayfayı baştan incelemeye zorlar."""
    gerekce = list(m.uyarilar or ())
    if not gerekce:
        eksik = []
        if not m.kanitlar or "sik_kumesi" not in (m.kanitlar or ()) \
                and "tam_sik_kumesi" not in (m.kanitlar or ()):
            eksik.append("şık kümesi yok")
        if "soru_yonergesi" not in (m.kanitlar or ()):
            eksik.append("soru kipi yok")
        if "uygun_geometri" not in (m.kanitlar or ()):
            eksik.append("geometri belirsiz")
        gerekce.append("kanit_yetersiz: " + ", ".join(eksik or ["güven düşük"]))
    return tuple(gerekce)


def kirpma_plani_meta(sayfalar, fmt, birlestir=True, agresif=False,
                      kutu_atama=None, cevap_disla=False, kalite="legacy",
                      kova="cikti", rapor=None):
    """Belge düzeyinde kırpma planı + parça-metadata + test dikişi.
    Dönüş: (plan, parca_meta, testler)
    - plan: her çıktı PNG'si için [(sayfa_idx, kutu), ...] parça listesi —
      1 parça normal soru, 2 parça sütun/sayfa sonunda bölünüp birleşen soru.
    - parca_meta[j] (plan[j] ile paralel): {"test_no","test_sira","soru_no",
      "sayfa" (1-tabanlı), "belge_no", "parcalar_idx": [(si, ki|None), ...],
      "numara_kutu"} — ki: sayfanın görünür kutu listesindeki (sorulari_tespit
      sırası / kutu_atama sırası) indeks; birleştirilen devam parçası None.
    - testler: test_bolumleri özeti.

    rapor: verilirse doldurulan sözlük. `dislanan_sayfalar` anahtarı, soru
    üretmeden KASITLI olarak atlanan sayfaların indekslerini taşır (cevap
    anahtarı, çözüm bölümü, soru dışı sayfa). Bu bilgi eskiden yalnız
    fonksiyonun içinde kalıyordu; dışarıdan bakan biri "bu sayfada soru
    bulunamadı" ile "bu sayfa bilerek dışlandı" arasındaki farkı göremiyordu.

    kutu_atama: {sayfa_idx: [kutu, ...]} — kullanıcı eliyle düzenlenmiş
    sayfalar; bu sayfalarda tespit ve birleştirme atlanır (web kutu editörü).
    cevap_disla=True: cevap anahtarı sayfaları soru üretmez (çöp kutu yok).
    birlestir=False: bölünmüş-soru birleştirmesi kapalı (tek parçalar)."""
    sayfa_meta = []
    cevap_sayfalari = set()
    if kalite not in KALITE_MODLARI:
        raise ValueError(f"bilinmeyen kalite modu: {kalite}")
    _secili = _kova_secici(kalite, kova)
    dislanacak, soru_sayfalari = (
        _belge_sayfa_rolleri(sayfalar, kalite, fmt=fmt)
        if cevap_disla else (set(), None))
    for i, s in enumerate(sayfalar):
        if kutu_atama and i in kutu_atama:
            sayfa_meta.append(None)
            continue
        if cevap_disla:
            if i in dislanacak \
                    or (soru_sayfalari is not None and i not in soru_sayfalari):
                cevap_sayfalari.add(i)
                sayfa_meta.append(([], [(0.0, s.genislik)], fmt))
                continue
            try:
                anahtar_mi = _cevap_sayfasi_mi(s.satirlar())
            except Exception:  # noqa: BLE001 — OCR hatası normal akışa düşer
                anahtar_mi = False
            if anahtar_mi:
                cevap_sayfalari.add(i)
                sayfa_meta.append(([], [(0.0, s.genislik)], fmt))
                continue
        sayfa_meta.append(sorulari_tespit_meta(s, fmt))
    sayfa_meta, testler = test_bolumleri(sayfalar, sayfa_meta,
                                         atla=cevap_sayfalari)
    if rapor is not None:
        rapor["dislanan_sayfalar"] = sorted(cevap_sayfalari)

    beklenen = beklenen_sik_kumesi(
        [sm[0] for sm in sayfa_meta if sm is not None])
    plan = []
    parca_meta = []
    onceki = None   # (plan_idx, SoruKutu, sayfa_idx, sayfa_fmt, dibe_ulasti)

    def _kutu_metni(satirlar, kutu, pay):
        """Kutu bölgesindeki satır metinleri (okuma sırasında) — arama,
        etiketleme ve gövde/şık ayrıştırma için sorular.json'a taşınır."""
        ic = _bolge_satirlari(satirlar, kutu[1], kutu[3], kutu[0], kutu[2],
                              pay)
        return [m for m, _ in sorted(ic, key=lambda t: t[1][1])]

    def _v2_alanlari(m):
        return {
            "soru_turu": m.soru_turu, "sayfa_rolu": m.sayfa_rolu,
            "guven": m.guven, "kanitlar": list(m.kanitlar),
            "uyarilar": list(m.uyarilar),
            "inceleme_durumu": m.inceleme_durumu,
            "karar_kimligi": m.karar_kimligi,
            "kalibre_guven": (m.guven if m.kalibre_guven is None
                                else m.kalibre_guven),
            "onay_durumu": m.onay_durumu,
            "kaynak_yontemler": list(m.kaynak_yontemler),
            "risk_nedenleri": list(m.risk_nedenleri),
            "duzen_bolgeleri": list(m.duzen_bolgeleri),
            "algoritma_surumu": KALIBRASYON_SURUMU,
            # İncele kovasına düşen her kesim NEDENİYLE birlikte yazılır;
            # gerekçesiz bir "İncele/" klasörü kullanıcıyı sayfayı baştan
            # incelemeye zorlar (ölçüldü: incele kutularının 28/49'u hiçbir
            # uyarı taşımıyordu).
            "inceleme_gerekcesi": list(aday_inceleme_gerekcesi(m)),
        }

    for i, s in enumerate(sayfalar):
        if sayfa_meta[i] is None:
            try:
                sat_i = s.satirlar()
            except Exception:  # noqa: BLE001 — OCR hatası: metinsiz devam
                sat_i = []
            pay_i = s.genislik * 0.012
            for ki, kutu in enumerate(kutu_atama[i]):
                plan.append([(i, kutu)])
                parca_meta.append({
                    "test_no": None, "test_sira": None, "soru_no": None,
                    "sayfa": i + 1, "belge_no": s.belge_no,
                    "parcalar_idx": [(i, ki)], "numara_kutu": None,
                    "metin": _kutu_metni(sat_i, kutu, pay_i),
                    "soru_turu": "elle_belirlendi", "sayfa_rolu": "soru",
                    "guven": 1.0, "kanitlar": ["elle_duzenlendi"],
                    "uyarilar": [], "inceleme_durumu": "otomatik",
                    "algoritma_surumu": KALIBRASYON_SURUMU})
            onceki = None   # elle düzenlenen sayfa sınırında birleştirme yok
            continue
        meta, bantlar, sfmt = sayfa_meta[i]
        satirlar = s.satirlar()
        G, Y = s.genislik, s.yukseklik
        pay = G * 0.012
        gorunur_butun = [m for m in meta if not m.devam_aday]
        ki_map = {id(m): k for k, m in enumerate(gorunur_butun)}
        gorunur_tum = [m for m in gorunur_butun if _secili(m)]

        def _bant_alt(bi):
            ic = _bolge_satirlari(satirlar, 0, Y * 0.97,
                                  bantlar[bi][0], bantlar[bi][1], pay)
            return max((k[3] for _, k in ic), default=0.0)

        # Tespit motoru satır-öncelikli ya da karma tam-genişlik düzeni
        # seçtiyse meta sırası bantlar arasında geri döner (0,1,0,1 veya
        # 0,1,0). Aşağıdaki klasik bant döngüsü bunu tekrar 0,0,1,1 yapardı.
        # Böyle sayfalarda doğrulanmış meta sırasını doğrudan koru; kutular
        # zaten bütün olduğundan sütun-sonu yetim birleştirmesi uygulanmaz.
        bant_dizisi = [m.bant_idx for m in gorunur_tum]
        satir_oncelikli = any(a > b for a, b in
                              zip(bant_dizisi, bant_dizisi[1:]))
        if satir_oncelikli:
            for m in gorunur_tum:
                plan.append([(i, m.kutu)])
                parca_meta.append({
                    "test_no": m.test_no, "test_sira": m.test_sira,
                    "soru_no": m.numara, "sayfa": i + 1,
                    "belge_no": s.belge_no,
                    "parcalar_idx": [(i, ki_map[id(m)])],
                    "numara_kutu": m.numara_kutu,
                    "metin": _kutu_metni(satirlar, m.kutu, pay),
                    **_v2_alanlari(m)})
            if gorunur_tum:
                son = gorunur_tum[-1]
                dibe = son.kutu[3] >= _bant_alt(son.bant_idx) - Y * 0.04
                onceki = (len(plan) - 1, son, i, sfmt, dibe)
            else:
                onceki = None
            continue

        # bant sırasına göre yürü (meta zaten okuma sırasında)
        for bi in range(len(bantlar)):
            gorunur = [m for m in meta
                       if m.bant_idx == bi and not m.devam_aday
                       and _secili(m)]
            devam = next((m for m in meta
                          if m.bant_idx == bi and m.devam_aday), None)
            atla = None   # birleşme yüzünden ayrı basılmayacak kutu

            if birlestir and onceki is not None and sfmt == onceki[3] \
                    and s.belge_no == sayfalar[onceki[2]].belge_no \
                    and onceki[4]:
                # 1) açık devam adayı (bugün atılan bölge)
                if devam is not None \
                        and _birlesme_uygun(onceki[1], devam, beklenen,
                                            agresif):
                    plan[onceki[0]].append((i, devam.kutu))
                    parca_meta[onceki[0]]["parcalar_idx"].append((i, None))
                    parca_meta[onceki[0]]["metin"] += _kutu_metni(
                        satirlar, devam.kutu, pay)
                # 2) bandın İLK kutusu numarasız blok (segmentasyon
                #    kurtarması): şık son-eki eşleşirse öncekine katılır
                elif gorunur and gorunur[0].numara is None \
                        and not gorunur[0].govde_var \
                        and _birlesme_uygun(onceki[1], gorunur[0],
                                            beklenen, False):
                    plan[onceki[0]].append((i, gorunur[0].kutu))
                    parca_meta[onceki[0]]["parcalar_idx"].append(
                        (i, ki_map[id(gorunur[0])]))
                    parca_meta[onceki[0]]["metin"] += _kutu_metni(
                        satirlar, gorunur[0].kutu, pay)
                    atla = gorunur[0]

            for m in gorunur:
                if m is atla:
                    continue
                plan.append([(i, m.kutu)])
                parca_meta.append({
                    "test_no": m.test_no, "test_sira": m.test_sira,
                    "soru_no": m.numara, "sayfa": i + 1,
                    "belge_no": s.belge_no,
                    "parcalar_idx": [(i, ki_map[id(m)])],
                    "numara_kutu": m.numara_kutu,
                    "metin": _kutu_metni(satirlar, m.kutu, pay),
                    **_v2_alanlari(m)})

            kalan = [m for m in gorunur if m is not atla]
            if kalan:
                son = kalan[-1]
                dibe = son.kutu[3] >= _bant_alt(bi) - Y * 0.04
                onceki = (len(plan) - 1, son, i, sfmt, dibe)
            elif gorunur:
                onceki = None   # bandın tek kutusu birleşti → zincir kesilir
            # bant tamamen boşsa 'onceki' korunur (boş yan bant okuma
            # sırasını bozmasın)

    # "39-40. soruları aşağıdaki parçaya göre..." gibi ortak uyaranları her
    # ilgili sorunun başına ayrı parça olarak ekle. Bu, aynı uyaranı paylaşan
    # farklı sütun sorularında ya uyaranın kaybolmasını ya da iki sorunun tek
    # tam-sayfa kutusuna birleşmesini önler.
    ortak_onbellek = {}
    for j, (parcalar, pm) in enumerate(zip(plan, parca_meta)):
        no = pm.get("soru_no")
        si = pm.get("sayfa", 1) - 1
        if no is None or not (0 <= si < len(sayfalar)) \
                or sayfa_meta[si] is None:
            continue
        if si not in ortak_onbellek:
            _, bantlar, _ = sayfa_meta[si]
            ortak_onbellek[si] = _ortak_uyaran_haritasi(
                sayfalar[si], sayfalar[si].satirlar(), bantlar)
        ortak = ortak_onbellek[si].get(no)
        if ortak is None or any(_ortusme_orani(ortak, k) >= 0.85
                                for psi, k in parcalar if psi == si):
            continue
        plan[j] = [(si, ortak)] + parcalar
        pm["parcalar_idx"] = [(si, None)] + pm["parcalar_idx"]
        pm["numara_parca_idx"] = 1
        pay = sayfalar[si].genislik * 0.012
        pm["metin"] = _kutu_metni(
            sayfalar[si].satirlar(), ortak, pay) + (pm.get("metin") or [])
        pm.setdefault("kanitlar", []).append("ortak_uyaran")

    return plan, parca_meta, testler


def kirpma_plani(sayfalar, fmt, birlestir=True, agresif=False,
                 kutu_atama=None, kalite="legacy"):
    """kirpma_plani_meta'nın yalnız-plan görünümü (geriye uyum: dogrula.py
    ve eski çağıranlar). Dönüş yapısı değişmedi."""
    return kirpma_plani_meta(sayfalar, fmt, birlestir, agresif,
                             kutu_atama, kalite=kalite)[0]


def dikey_birlestir(parcalar, bosluk_px=14):
    """Traşlanmış parçaları piksel ölçeğini bozmadan alt alta diker.

    Önceki sürüm her parçayı en geniş kırpmaya büyütüyordu. Kırpma genişliği
    DPI değil içerik genişliğidir; dar bir devam/çözüm parçasını geniş soruya
    uydurmak fontu ve şekli büyütüp koordinatları bozuyordu. PDF ve taranmış
    PDF sayfaları zaten istenen ortak çıktı DPI'ında render edilir. Bu yüzden
    doğru davranış parçaları yeniden örneklemeden, geniş olanı tuval ölçüsü
    kabul edip sola hizalamaktır.
    """
    if not parcalar:
        raise ValueError("birleştirilecek parça yok")
    hedef = max(p.width for p in parcalar)
    Y = sum(p.height for p in parcalar) + bosluk_px * (len(parcalar) - 1)
    tuval = Image.new("RGB", (hedef, Y), "white")
    y = 0
    for p in parcalar:
        tuval.paste(p, (0, y))
        y += p.height + bosluk_px
    return tuval


def cevap_bandi_ekle(img, cevap):
    """Kesilmiş soru görüntüsünün altına 'Cevap: X' bandı diker. Bant
    TRAŞLAMADAN SONRA eklenmelidir (trasla beyaz bandı kenar boşluğu sanıp
    kesmesin); numara_px üst bölgede olduğundan koordinatları etkilenmez."""
    import yazi_tipi
    w = img.width
    bant = max(26, min(64, round(w * 0.055)))
    tuval = Image.new("RGB", (w, img.height + bant), "white")
    tuval.paste(img, (0, 0))
    ciz = ImageDraw.Draw(tuval)
    ciz.line([(0, img.height), (w, img.height)], fill=(200, 200, 200))
    metin = f"Cevap: {cevap}"
    font = yazi_tipi.pil_font(max(11, round(bant * 0.55)))
    try:
        mx0, my0, mx1, my1 = ciz.textbbox((0, 0), metin, font=font)
        mw, mh = mx1 - mx0, my1 - my0
    except (AttributeError, TypeError):   # çok eski Pillow yedeği
        mw, mh = ciz.textsize(metin, font=font)
        mx0 = my0 = 0
    ciz.text((w - mw - max(8, bant // 3) - mx0,
              img.height + (bant - mh) // 2 - my0),
             metin, fill=(10, 125, 40), font=font)
    return tuval


def _cozum_ayraci(genislik):
    """'Çözüm' etiketli ince gri ayraç şeridi (iliştirme dikişinde)."""
    import yazi_tipi
    h = 22
    serit = Image.new("RGB", (genislik, h), (245, 245, 245))
    ciz = ImageDraw.Draw(serit)
    ciz.line([(0, 0), (genislik, 0)], fill=(200, 200, 200))
    ciz.text((8, 4), "Çözüm", fill=(120, 120, 120),
             font=yazi_tipi.pil_font(12))
    return serit


def cozumleri_ilistir(kirpmalar, sorular):
    """Çözüm-bölümü kayıtlarını (sayfa_rolu=='çözüm') aynı numaralı sorunun
    altına diker. Eşleşen çözüm listeden düşer; eşleşmeyen aynen kalır.
    Anahtar kademeli denenir: (kaynak, test_sira, soru_no) →
    (kaynak, None, soru_no) → yalnız soru_no (belgede benzersizse).
    Çakışmada (birden çok aday soru) iliştirme YAPILMAZ — yanlış çözüm
    yapıştırmaktansa ayrı bırakmak yeğdir. Girdi listeleri değiştirilir;
    dönüş: (kirpmalar, sorular, uyarilar)."""
    uyarilar = []
    soru_idx = {}
    for i, so in enumerate(sorular):
        if so.get("sayfa_rolu") == "çözüm" or so.get("soru_no") is None:
            continue
        for anahtar in ((so.get("kaynak"), so.get("test_sira"), so["soru_no"]),
                        (so.get("kaynak"), None, so["soru_no"]),
                        (None, None, so["soru_no"])):
            soru_idx.setdefault(anahtar, []).append(i)
    tuketilen = set()
    for j, co in enumerate(sorular):
        if co.get("sayfa_rolu") != "çözüm" or co.get("soru_no") is None:
            continue
        hedefler = None
        for anahtar in ((co.get("kaynak"), co.get("test_sira"), co["soru_no"]),
                        (co.get("kaynak"), None, co["soru_no"]),
                        (None, None, co["soru_no"])):
            adaylar = soru_idx.get(anahtar)
            if adaylar:
                hedefler = adaylar
                break
        if not hedefler:
            uyarilar.append(f"Çözüm {co['soru_no']}: eşleşen soru "
                            "bulunamadı, ayrı bırakıldı.")
            continue
        if len(set(hedefler)) > 1:
            uyarilar.append(f"Çözüm {co['soru_no']}: aynı numarada birden "
                            "çok soru var, iliştirilmedi.")
            continue
        i = hedefler[0]
        if i in tuketilen or sorular[i].get("cozum_ilistirildi"):
            uyarilar.append(f"Çözüm {co['soru_no']}: soruya zaten çözüm "
                            "iliştirilmiş, atlandı.")
            continue
        soru_img = kirpmalar[i]
        kirpmalar[i] = dikey_birlestir(
            [soru_img, _cozum_ayraci(soru_img.width), kirpmalar[j]],
            bosluk_px=6)
        sorular[i]["cozum_ilistirildi"] = True
        tuketilen.add(j)
    if tuketilen:
        kirpmalar[:] = [im for j, im in enumerate(kirpmalar)
                        if j not in tuketilen]
        sorular[:] = [so for j, so in enumerate(sorular)
                      if j not in tuketilen]
    return kirpmalar, sorular, uyarilar


def kirpmalari_uret(sayfalar, fmt, birlestir=True, agresif=False,
                    kutu_atama=None):
    """Tüm sayfalardaki soruları kırpıp traşlanmış PIL listesi döndürür.
    Bölünmüş sorular (bkz. kirpma_plani) dikey dikişle tek PNG olur."""
    plan = kirpma_plani(sayfalar, fmt, birlestir, agresif, kutu_atama)
    kirpmalar = []
    sayfa_sayilari = [0] * len(sayfalar)
    for parcalar in plan:
        if len(parcalar) == 1:
            si, kutu = parcalar[0]
            kirpmalar.append(trasla(sayfalar[si].kirp(kutu)))
        else:
            imgler = [trasla(sayfalar[si].kirp(kutu), kenar=0)
                      for si, kutu in parcalar]
            kirpmalar.append(trasla(dikey_birlestir(imgler)))
        sayfa_sayilari[parcalar[0][0]] += 1
    return kirpmalar, sayfa_sayilari


def _numara_soz_kutusu(sayfa, numara, satir_kutu):
    """Soru numarası JETONUNUN ('12.') layout bbox'ı. Metin sayfasında kelime
    kutularından kesin; taranmışta satır yüksekliğinden kestirim (satır bbox'ı
    tüm satırı kapsar — yalnız baştaki numara payı alınır)."""
    if not sayfa.raster:
        try:
            for x0, y0, x1, y1, soz, *_ in sayfa.page.get_text("words"):
                if (abs(y0 - satir_kutu[1]) < 6
                        and x0 < satir_kutu[0]
                        + (satir_kutu[2] - satir_kutu[0]) * 0.5
                        and re.fullmatch(r"\d{1,3}[.)]?", soz)
                        and int(re.match(r"\d+", soz).group()) == numara):
                    return (x0, y0, x1, y1)
        except Exception:  # noqa: BLE001 — kelime çıkarımı yoksa kestirime düş
            pass
    x0, y0, x1, y1 = satir_kutu
    h = max(1.0, y1 - y0)
    genis = h * (0.62 * len(str(numara)) + 0.7)
    # TAVAN: numara satır başındaki küçük bir jetondur — beyazlatma genişliği
    # satır genişliğinin ~%30'unu geçmesin. Anormal-yüksek OCR satır bbox'ında
    # (h büyük) ~2h'lik beyaz dikdörtgen soru gövdesini silmesin.
    genis = min(genis, (x1 - x0) * 0.30)
    return (x0, y0, min(x1, x0 + genis), y1)


def kirpma_seti(sayfalar, fmt, girdiler=None, birlestir=True, agresif=False,
                kutu_atama=None, secim=None, secim_kutular=None,
                cevaplar=None, numara_temizle=False, ilerleme=None,
                cevap_disla=True, rastgele=None, tohum=None,
                konu_sozluk=None, etiketler=None, kalite="legacy",
                cevap_bandi=False, cevap_duzeltmeler=None, kova="cikti"):
    """Zengin kesim API'si: kes + seç + metadata. CLI, web ve GUI'nin ortak
    yolu. Dönüş: (kirpmalar, sorular, uyarilar)
    - kirpmalar: PIL listesi (bölünmüş sorular dikişli).
    - sorular[j]: {"dosya" (zip_yaz doldurur), "test_no", "test_sira",
      "soru_no", "sayfa", "kaynak", "cevap", "numara_px"}.
    - secim: secim_ayristir kuralları (CLI/metin yolu).
      secim_kutular: {(sayfa_idx, kutu_idx), ...} — web tıkla-seç yolu; plan
      öğesi, parçalarından herhangi biri kümede ise dahil edilir.
      İkisi de None → tüm sorular.
    - cevaplar: cevap_anahtari_bul çıktısı → 'cevap' alanı doldurulur.
    - cevap_duzeltmeler: {_kimlik: 'A'..'E'|''} elle düzeltme — anahtar
      eşlemesini ezer ('' = cevabı sil). cevap_bandi=True: bulunan cevap
      görüntünün altına bant olarak basılır (yalnız zip/kes yolunda kullan;
      banka dedup'ı ve sınav PDF'i bantsız görüntü ister).
    - numara_temizle=True: eski soru numarası kirpmada beyazlatılır ve yeri
      numara_px (çıktı pikseli, (x0,y0,x1,y1)) olarak raporlanır — sınav
      PDF'inde yeniden numaralama için.
    - rastgele=N: (seçim uygulandıktan sonra) her testten dengeli N soru
      rastgele örneklenir (test yoksa toplamdan N) — 'havuzdan her boyut
      eşit temsille rastgele çekme'. tohum: tekrarlanabilirlik (None=rasgele).
    - ilerleme(i, n): her kirpma sonrası çağrılır."""
    plan_raporu = {}
    plan, parca_meta, testler = kirpma_plani_meta(
        sayfalar, fmt, birlestir, agresif, kutu_atama,
        cevap_disla=cevap_disla, kalite=kalite, kova=kova, rapor=plan_raporu)
    for pm, kml in zip(parca_meta, soru_kimlikleri(parca_meta)):
        pm["_kimlik"] = kml       # etiket eşleme + kararlı kimlik
    uyarilar = []
    tut = None
    if secim:
        tut, uyarilar = secim_uygula(parca_meta, secim, testler)
    elif secim_kutular is not None:
        kume = {tuple(t) for t in secim_kutular}
        tut = {j for j, pm in enumerate(parca_meta)
               if any(ki is not None and (si, ki) in kume
                      for si, ki in pm["parcalar_idx"])}
    if rastgele:
        import random
        rnd = random.Random(tohum)
        evren = sorted(tut) if tut is not None else list(range(len(parca_meta)))
        gruplar = {}
        for j in evren:
            gruplar.setdefault(parca_meta[j]["test_sira"], []).append(j)
        tut = set()
        for anahtar in sorted(gruplar, key=lambda a: (a is None, a or 0)):
            grup = gruplar[anahtar]
            tut.update(rnd.sample(grup, min(rastgele, len(grup))))
    if tut is not None:
        secili = sorted(tut)
        plan = [plan[j] for j in secili]
        parca_meta = [parca_meta[j] for j in secili]
    esleme = cevaplari_esle(testler, cevaplar) if cevaplar else {}

    kirpmalar = []
    sorular = []
    for j, parcalar in enumerate(plan):
        pm = parca_meta[j]
        numara_px = None
        # numara bölgesinin KIRPMA pikselindeki yeri. Ortak uyaranlı soruda
        # numara ikinci parçada olabilir; klasik bölünmüş soruda ilk parçadır.
        nk_px = None
        si0, kutu0 = parcalar[0]
        s0 = sayfalar[si0]
        numara_parca_idx = min(pm.get("numara_parca_idx", 0),
                               len(parcalar) - 1)
        sin, kutun = parcalar[numara_parca_idx]
        sn = sayfalar[sin]
        olcekn = (sn.kirpma_olcegi if sn.raster else sn.dpi / 72)
        if numara_temizle and pm["soru_no"] is not None \
                and pm["numara_kutu"] is not None:
            nk = _numara_soz_kutusu(sn, pm["soru_no"], pm["numara_kutu"])
            nk_px = ((nk[0] - kutun[0]) * olcekn,
                     (nk[1] - kutun[1]) * olcekn,
                     (nk[2] - kutun[0]) * olcekn,
                     (nk[3] - kutun[1]) * olcekn)
        if len(parcalar) == 1:
            img, (ox, oy) = _trasla_ofset(s0.kirp(kutu0))
            if nk_px is not None:
                numara_px = (nk_px[0] + ox, nk_px[1] + oy,
                             nk_px[2] + ox, nk_px[3] + oy)
        else:
            imgler, ofsetler = [], []
            for si, kutu in parcalar:
                parca_img, parca_ofset = _trasla_ofset(
                    sayfalar[si].kirp(kutu), kenar=0)
                imgler.append(parca_img)
                ofsetler.append(parca_ofset)
            img, (ox2, oy2) = _trasla_ofset(dikey_birlestir(imgler))
            if nk_px is not None:
                ox, oy = ofsetler[numara_parca_idx]
                once_y = sum(p.height for p in imgler[:numara_parca_idx])
                once_y += 14 * numara_parca_idx
                numara_px = (nk_px[0] + ox + ox2,
                             nk_px[1] + oy + once_y + oy2,
                             nk_px[2] + ox + ox2,
                             nk_px[3] + oy + once_y + oy2)
        if numara_px is not None:
            pad = 3
            x0 = max(0, int(numara_px[0]) - pad)
            y0 = max(0, int(numara_px[1]) - pad)
            x1 = min(img.width, int(numara_px[2]) + pad)
            y1 = min(img.height, int(numara_px[3]) + pad)
            if x1 > x0 and y1 > y0:
                ImageDraw.Draw(img).rectangle([x0, y0, x1, y1], fill="white")
                numara_px = (x0, y0, x1, y1)
            else:
                numara_px = None
        cevap = esleme.get((pm["test_sira"], pm["soru_no"]))
        if cevap is None and pm["soru_no"] is not None:
            cevap = esleme.get((None, pm["soru_no"]))
        if cevap_duzeltmeler and pm.get("_kimlik") in cevap_duzeltmeler:
            cevap = cevap_duzeltmeler[pm["_kimlik"]] or None
        if cevap_bandi and cevap:
            img = cevap_bandi_ekle(img, cevap)
        kirpmalar.append(img)
        ayrisik = soru_metni_ayristir(pm.get("metin") or [])
        profil = getattr(s0, "_v2_belge_profili", None)
        kayit = {
            "dosya": None,
            "test_no": pm["test_no"], "test_sira": pm["test_sira"],
            "soru_no": pm["soru_no"], "sayfa": pm["sayfa"],
            "kaynak": (os.path.basename(girdiler[pm["belge_no"]])
                       if girdiler else None),
            "cevap": cevap,
            "metin": ayrisik["metin"], "govde": ayrisik["govde"],
            "siklar": ayrisik["siklar"],
            "kaynak_kutu": (list(next(
                (p for p in pm["parcalar_idx"] if p[1] is not None),
                pm["parcalar_idx"][0])) if pm.get("parcalar_idx") else None),
            "numara_px": ([int(v) for v in numara_px]
                          if numara_px is not None else None),
            "inceleme_gerekcesi": pm.get("inceleme_gerekcesi") or [],
            "kaynak_hash": (profil.kaynak_hash if profil else None),
            "algoritma_surumu": pm.get("algoritma_surumu",
                                        KALIBRASYON_SURUMU),
            "soru_turu": pm.get("soru_turu", "bilinmiyor"),
            "sayfa_rolu": pm.get("sayfa_rolu", "soru"),
            "guven": pm.get("guven", 1.0),
            "inceleme_durumu": pm.get("inceleme_durumu", "otomatik"),
            "tespit_kanitlari": pm.get("kanitlar") or [],
            "tespit_uyarilari": pm.get("uyarilar") or []}
        if konu_sozluk:
            konu, adaylar = konu_etiketle(ayrisik["metin"], konu_sozluk)
            kayit["konu"] = konu
            kayit["konu_adaylari"] = adaylar
        if etiketler:      # web'den elle girilen etiketler (kimlik anahtarlı)
            kml = pm.get("_kimlik")
            if kml and kml in etiketler:
                kayit.setdefault("etiketler", {}).update(etiketler[kml])
        sorular.append(kayit)
        if ilerleme:
            ilerleme(j + 1, len(plan))
    dislanan = plan_raporu.get("dislanan_sayfalar") or []
    if dislanan:
        # Görünür üçüncü sonuç: "bu sayfada soru bulunamadı" ile "bu sayfa
        # bilerek dışlandı" dışarıdan ayırt edilemiyordu. Sayfa numaraları
        # 1 tabanlı verilir; kullanıcı PDF'te o sayfaya bakacak.
        uyarilar.append(
            "dislanan_sayfa:%d:%s"
            % (len(dislanan), ",".join(str(i + 1) for i in dislanan[:20])))
    return kirpmalar, sorular, uyarilar


def _etiket_metni(so):
    """Bir sorunun konu + elle etiketlerini tek okunur dizeye toplar."""
    parcalar = []
    if so.get("konu"):
        parcalar.append(so["konu"])
    for k, v in (so.get("etiketler") or {}).items():
        parcalar.append(f"{k}: {v}" if v else k)
    return " · ".join(parcalar)


def disa_aktar(sorular, tur, kirpmalar=None):
    """Soru bankasını (kirpma_seti 'sorular' listesi) dışa aktarır.
    tur: 'csv' | 'md' | 'html'. HTML için kirpmalar verilirse görüntüler
    base64 data-URI olarak gömülür (tek dosya, paylaşılabilir). Dönüş:
    (metin_str, uzanti)."""
    if tur == "csv":
        import csv, io as _io
        tampon = _io.StringIO()
        tampon.write("﻿")            # Excel UTF-8 BOM (Türkçe güvenli)
        yaz = csv.writer(tampon)
        yaz.writerow(["Sıra", "Test", "Soru No", "Sayfa", "Kaynak", "Cevap",
                      "Konu/Etiket", "Metin"])
        for i, so in enumerate(sorular, 1):
            yaz.writerow([i, so.get("test_no") or "", so.get("soru_no") or "",
                          so.get("sayfa") or "", so.get("kaynak") or "",
                          so.get("cevap") or "", _etiket_metni(so),
                          (so.get("metin") or "")[:500]])
        return tampon.getvalue(), "csv"
    if tur == "md":
        satirlar = ["| # | Test | Soru | Sayfa | Cevap | Konu/Etiket | Metin |",
                    "|---|------|------|-------|-------|-------------|-------|"]
        for i, so in enumerate(sorular, 1):
            m = (so.get("metin") or "").replace("|", "\\|")[:160]
            satirlar.append(
                f"| {i} | {so.get('test_no') or ''} | {so.get('soru_no') or ''} "
                f"| {so.get('sayfa') or ''} | {so.get('cevap') or ''} "
                f"| {_etiket_metni(so)} | {m} |")
        return "\n".join(satirlar) + "\n", "md"
    if tur == "html":
        import base64
        parcalar = ["<!doctype html><html lang='tr'><head><meta charset='utf-8'>",
                    "<title>Soru Bankası</title><style>",
                    "body{font:15px/1.5 -apple-system,sans-serif;max-width:900px;"
                    "margin:24px auto;padding:0 16px;color:#1a1a1a}",
                    ".s{border:1px solid #ddd;border-radius:10px;padding:14px;"
                    "margin:14px 0}.b{color:#666;font-size:13px;margin-bottom:8px}",
                    ".b b{color:#111}img{max-width:100%;border-radius:6px}",
                    ".c{color:#0a7d28;font-weight:600}</style></head><body>",
                    f"<h1>Soru Bankası ({len(sorular)} soru)</h1>"]
        for i, so in enumerate(sorular):
            et = _etiket_metni(so)
            bilgi = []
            if so.get("test_no"):
                bilgi.append(f"Test {so['test_no']}")
            if so.get("soru_no"):
                bilgi.append(f"Soru {so['soru_no']}")
            if so.get("sayfa"):
                bilgi.append(f"s.{so['sayfa']}")
            cev = (f" · <span class='c'>Cevap: {so['cevap']}</span>"
                   if so.get("cevap") else "")
            parcalar.append(f"<div class='s'><div class='b'><b>{i + 1}.</b> "
                            f"{' · '.join(bilgi)}{cev}"
                            + (f" · {et}" if et else "") + "</div>")
            if kirpmalar and i < len(kirpmalar):
                import io as _io
                bio = _io.BytesIO()
                kirpmalar[i].save(bio, "PNG")
                b64 = base64.b64encode(bio.getvalue()).decode()
                parcalar.append(f"<img src='data:image/png;base64,{b64}'>")
            elif so.get("metin"):
                parcalar.append(f"<div>{so['metin']}</div>")
            parcalar.append("</div>")
        parcalar.append("</body></html>")
        return "\n".join(parcalar), "html"
    raise ValueError(f"bilinmeyen dışa aktarma türü: {tur}")


def test_ozeti(sayfalar, fmt, kutu_atama=None, cevaplar=None,
               birlestir=True, agresif=False, kalite="legacy"):
    """Belgenin test/soru yapısı — web arayüzünün ve --liste'nin tek gerçek
    kaynağı. Dönüş: (testler, parca_meta) — parca_meta girişlerine 'cevap'
    alanı eklenmiş hâlde, plan (kesim) sırasında."""
    _, parca_meta, testler = kirpma_plani_meta(
        sayfalar, fmt, birlestir, agresif, kutu_atama, cevap_disla=True,
        kalite=kalite)
    esleme = cevaplari_esle(testler, cevaplar) if cevaplar else {}
    for pm in parca_meta:
        cevap = esleme.get((pm["test_sira"], pm["soru_no"]))
        if cevap is None and pm["soru_no"] is not None:
            cevap = esleme.get((None, pm["soru_no"]))
        pm["cevap"] = cevap
    return testler, parca_meta


KUTU_RENK = (220, 30, 30)  # önizleme kutu çizgisi


def kutulari_ciz(gorsel, kutular, olcek=1.0, kalinlik=4, renk=KUTU_RENK):
    """Kutuları (layout koordinatında) numaralandırıp görselin üzerine çizer."""
    ciz = ImageDraw.Draw(gorsel)
    for j, (x0, y0, x1, y1) in enumerate(kutular, 1):
        r = [x0 * olcek, y0 * olcek, x1 * olcek, y1 * olcek]
        ciz.rectangle(r, outline=renk, width=kalinlik)
        ciz.text((r[0] + 6, r[1] + 4), str(j), fill=renk)
    return gorsel


def onizleme_gorseli(sayfa, kutular, kalinlik=4):
    """sayfa.gorsel() + kutulari_ciz kısayolu → kutulu PIL görüntü."""
    gorsel, olcek = sayfa.gorsel()
    return kutulari_ciz(gorsel, kutular, olcek, kalinlik)


@dataclass(frozen=True)
class KaliteKapisiSonucu:
    kalite: str
    izin: bool
    bekleyen_sayfalar: tuple = ()
    pipeline_hatalari: tuple = ()

    def to_dict(self):
        return {"kalite": self.kalite, "izin": bool(self.izin),
                "bekleyen_sayfalar": list(self.bekleyen_sayfalar),
                "pipeline_hatalari": list(self.pipeline_hatalari),
                "algoritma_surumu": KALIBRASYON_SURUMU}


def kalite_kapisi(sayfalar, fmt=None, girdiler=None, kalite="strict",
                  sayfa_kararlari=None):
    """Belirsiz hiçbir sayfayı strict çıktıya sessizce geçirmez."""
    if kalite not in KALITE_MODLARI:
        raise ValueError(f"bilinmeyen kalite modu: {kalite}")
    kararlar = sayfa_kararlari or {}
    pipeline = []
    try:
        profil, analizler = belge_analiz_et(sayfalar, fmt, girdiler)
    except Exception as exc:  # V3 hatası legacy kutuyu güvenli yapmaz
        profil, analizler = None, []
        pipeline.append({"tur": "v3_analiz_hatasi",
                         "ayrinti": f"{type(exc).__name__}: {exc}"})
    for i, s in enumerate(sayfalar):
        hata = getattr(s, "_v3_hata", None) or getattr(s, "_v2_hata", None)
        if hata:
            pipeline.append({"sayfa": i + 1, "tur": "v3_analiz_hatasi",
                             "ayrinti": str(hata)})
    bekleyen = []
    for i, analiz in enumerate(analizler):
        karar = kararlar.get(i, kararlar.get(str(i), ""))
        if karar in ("onayli", "onaylandi", "soru_yok", "dogru"):
            continue
        aday_bekleyen = [a.karar_kimligi for a in analiz.adaylar
                         if not a.devam_aday
                         and a.onay_durumu == "bekliyor"]
        if analiz.inceleme_gerekli or aday_bekleyen:
            bekleyen.append({
                "sayfa": i + 1, "karar_kimligi": analiz.karar_kimligi,
                "risk_nedenleri": list(dict.fromkeys(
                    analiz.risk_nedenleri
                    + (("bekleyen_aday",) if aday_bekleyen else ()))),
                "bekleyen_adaylar": aday_bekleyen,
                "pipeline_hatalari": list(analiz.pipeline_hatalari),
            })
    izin = kalite != "strict" or not (bekleyen or pipeline)
    sonuc = KaliteKapisiSonucu(kalite, izin, tuple(bekleyen), tuple(pipeline))
    return sonuc, profil, analizler


def _inceleme_bindirmesi(sayfa, analiz):
    gorsel, olcek = sayfa.gorsel()
    ciz = ImageDraw.Draw(gorsel)
    renkler = {"otomatik": (20, 155, 70), "incele": (235, 145, 20),
               "reddedildi": (205, 35, 45)}
    for aday in analiz.adaylar:
        if aday.devam_aday:
            continue
        x0, y0, x1, y1 = (float(v) * olcek for v in aday.kutu)
        renk = renkler.get(aday.inceleme_durumu, (235, 145, 20))
        ciz.rectangle((x0, y0, x1, y1), outline=renk, width=4)
        etiket = f"{aday.numara or '?'}  {aday.guven:.2f}"
        ciz.rectangle((x0, y0, x0 + max(62, len(etiket) * 8), y0 + 20),
                      fill=renk)
        ciz.text((x0 + 4, y0 + 3), etiket, fill="white")
    risk = ", ".join(analiz.risk_nedenleri) or "risk yok"
    ciz.rectangle((0, 0, min(gorsel.width, max(240, len(risk) * 7)), 28),
                  fill=(35, 39, 47))
    ciz.text((8, 7), f"Sayfa {analiz.sayfa_no}: {risk}", fill="white")
    return gorsel


def inceleme_paketi_uret(sayfalar, fmt, klasor, girdiler=None,
                         kalite="strict", kapi_sonucu=None,
                         profil=None, analizler=None):
    """Sayfa tabanlı JSON + tam sayfa bindirmeleri üretir; ZIP üretmez."""
    if analizler is None or kapi_sonucu is None:
        kapi_sonucu, profil, analizler = kalite_kapisi(
            sayfalar, fmt, girdiler, kalite)
    os.makedirs(klasor, exist_ok=True)
    bekleyen = {int(x["sayfa"]) for x in kapi_sonucu.bekleyen_sayfalar}
    gorseller = []
    for i in sorted(bekleyen):
        if not (1 <= i <= len(sayfalar)):
            continue
        yol = os.path.join(klasor, f"inceleme_sayfa{i:04d}.png")
        _inceleme_bindirmesi(sayfalar[i - 1], analizler[i - 1]).save(yol)
        gorseller.append(os.path.basename(yol))
    veri = {"schema_version": "3.0", "quality_gate": kapi_sonucu.to_dict(),
            "profile": profil.to_dict() if profil is not None else None,
            "pages": [a.to_dict() for a in analizler],
            "overlay_images": gorseller}
    yol = os.path.join(klasor, "inceleme.json")
    with open(yol, "w", encoding="utf-8") as f:
        json.dump(veri, f, ensure_ascii=False, indent=2)
    return yol, [os.path.join(klasor, ad) for ad in gorseller]


def onizleme_uret(sayfalar, fmt, klasor, en_fazla=4, mod="ornek"):
    """Tespit edilen soru kutularını sayfaların üzerine çizip PNG kaydeder.
    Kesme yapmadan ayarların doğruluğunu görsel denetlemek için."""
    os.makedirs(klasor, exist_ok=True)
    uretilen = []
    try:
        _, _, analizler = kalite_kapisi(sayfalar, fmt, kalite="balanced")
    except Exception:  # noqa: BLE001 — legacy önizleme yedeği
        analizler = []
    if mod == "tum":
        indeksler = list(range(len(sayfalar)))
    elif mod == "riskli" and analizler:
        indeksler = [i for i, a in enumerate(analizler)
                     if a.inceleme_gerekli]
    else:
        indeksler = list(range(min(en_fazla, len(sayfalar))))
    for i in indeksler:
        sayfa = sayfalar[i]
        gorsel = onizleme_gorseli(sayfa, sorulari_tespit(sayfa, fmt),
                                  kalinlik=3)
        yol = os.path.join(klasor, f"onizleme_sayfa{i + 1}.png")
        gorsel.save(yol)
        uretilen.append(yol)
    return uretilen


INCELE_KLASORU = "İncele"


def inceleme_seti(sayfalar, fmt, **kw):
    """`kirpma_seti`'nin İNCELE kovası: tespit edilmiş ama otomatik teslim
    edilemeyen kesimler.

    Bunlar strict/balanced kipte eskiden SESSİZCE düşüyordu. "Sıfır hata"
    hedefi otomatik kovanın kusursuz olmasını ister; emin olunamayan kesimin
    kaybolmasını değil. Ayrı klasöre gerekçesiyle yazılır, sessiz kayıp
    sıfırlanır."""
    kw.pop("kova", None)
    return kirpma_seti(sayfalar, fmt, kova="incele", **kw)


# Yalnız bu fonksiyonun ürettiği adlar. Temizlik bilerek bu kalıba
# bağlı: `-o` kullanıcının kendi klasörüne işaret ederse yabancı hiçbir
# dosyaya dokunulmasın diye klasör kökten silinmiyor.
_KOVA_DOSYA_KALIBI = re.compile(
    r"^(?:soru_\d+|test\d+_soru\d+|incele_\d+)(?:_\d+)?\.png$")


def _klasor_kovasini_temizle(kok):
    """Önceki koşumun kırpımlarını ve künyesini siler; başkasına dokunmaz."""
    if not os.path.isdir(kok):
        return
    for dizin in (kok, os.path.join(kok, INCELE_KLASORU)):
        if not os.path.isdir(dizin):
            continue
        for ad in os.listdir(dizin):
            if ad == "sorular.json" or _KOVA_DOSYA_KALIBI.match(ad):
                try:
                    os.remove(os.path.join(dizin, ad))
                except OSError:
                    # Silinemeyen tek dosya koşumu düşürmemeli; üzerine
                    # yazma zaten devam edecek.
                    pass


def zip_yaz(kirpmalar, cikti_yolu, klasor=False, sorular=None,
            incele=None, incele_sorular=None):
    """Kırpmaları zip'e (istenirse yanına klasör olarak da) yazar; adet
    döndürür.

    sorular=None → bugünkü davranış birebir: soru_NN.png sıralı adlar.
    sorular verilirse (kirpma_seti çıktısı) akıllı adlandırma yapılır —
    test tespit edildiyse test05_soru02.png, yoksa soru_NNN.png — ve arşive
    soru bilgilerini içeren sorular.json eklenir. Ad çakışmasında _2 eki
    (sessiz üzerine yazma olmaz); sorular[j]['dosya'] doldurulur.

    incele/incele_sorular verilirse (bkz. `inceleme_seti`) bu kesimler
    `İncele/` alt klasörüne + `İncele/sorular.json` olarak yazılır. Ana
    çıktı BİREBİR aynı kalır — incele kovası ana klasöre karışmaz."""
    hane = max(2, len(str(len(kirpmalar))))

    def _ad(i):
        if sorular is None:
            return f"soru_{i:0{hane}d}.png"
        so = sorular[i - 1]
        if so["test_no"] is not None and so["soru_no"] is not None:
            return f"test{so['test_no']:02d}_soru{so['soru_no']:02d}.png"
        return f"soru_{i:0{hane}d}.png"

    adlar = []
    kullanilan = set()
    for i in range(1, len(kirpmalar) + 1):
        ad = _ad(i)
        if ad in kullanilan:
            kok, uz = os.path.splitext(ad)
            k = 2
            while f"{kok}_{k}{uz}" in kullanilan:
                k += 1
            ad = f"{kok}_{k}{uz}"
        kullanilan.add(ad)
        adlar.append(ad)
        if sorular is not None:
            sorular[i - 1]["dosya"] = ad

    meta_json = (json.dumps(sorular, ensure_ascii=False, indent=1)
                 if sorular is not None else None)

    # İncele kovası: ana çıktıdan bağımsız adlandırılır, ana klasöre karışmaz.
    inc_adlar = []
    inc_json = None
    if incele:
        inc_hane = max(2, len(str(len(incele))))
        for i in range(1, len(incele) + 1):
            ad = f"incele_{i:0{inc_hane}d}.png"
            inc_adlar.append(ad)
            if incele_sorular is not None:
                incele_sorular[i - 1]["dosya"] = f"{INCELE_KLASORU}/{ad}"
        if incele_sorular is not None:
            inc_json = json.dumps(incele_sorular, ensure_ascii=False, indent=1)

    # Hedef klasör yoksa ZipFile yakalanmamış FileNotFoundError ile patlıyordu
    # ve bu, OCR/tespit BİTTİKTEN sonra oluyordu: dakikalarca süren koşum
    # yazma anında çöp oluyordu. Klasörü burada açmak koşumu kurtarır.
    hedef_klasor = os.path.dirname(os.path.abspath(cikti_yolu))
    if hedef_klasor:
        os.makedirs(hedef_klasor, exist_ok=True)
    with zipfile.ZipFile(cikti_yolu, "w", zipfile.ZIP_DEFLATED) as zf:
        for ad, img in zip(adlar, kirpmalar):
            tampon = io.BytesIO()
            img.save(tampon, format="PNG")
            zf.writestr(ad, tampon.getvalue())
        if meta_json is not None:
            zf.writestr("sorular.json", meta_json)
        for ad, img in zip(inc_adlar, incele or ()):
            tampon = io.BytesIO()
            img.save(tampon, format="PNG")
            zf.writestr(f"{INCELE_KLASORU}/{ad}", tampon.getvalue())
        if inc_json is not None:
            zf.writestr(f"{INCELE_KLASORU}/sorular.json", inc_json)
    if klasor:
        kl = os.path.splitext(cikti_yolu)[0]
        # Klasör kovası ZIP gibi sıfırdan yazılmalı. Üstüne yazmak, ikinci
        # koşumda daha AZ soru çıkarsa eski `soru_NN.png`leri yerinde
        # bırakıyordu: `sorular.json` yenilendiği için künye ile klasör
        # içeriği ayrışıyor ve klasörü okuyan akışa (soru bankası, Soru
        # Çözücü) önceki koşumun kesimleri karışıyordu.
        _klasor_kovasini_temizle(kl)
        os.makedirs(kl, exist_ok=True)
        for ad, img in zip(adlar, kirpmalar):
            img.save(os.path.join(kl, ad))
        if meta_json is not None:
            with open(os.path.join(kl, "sorular.json"), "w",
                      encoding="utf-8") as f:
                f.write(meta_json)
        if inc_adlar:
            ikl = os.path.join(kl, INCELE_KLASORU)
            os.makedirs(ikl, exist_ok=True)
            for ad, img in zip(inc_adlar, incele):
                img.save(os.path.join(ikl, ad))
            if inc_json is not None:
                with open(os.path.join(ikl, "sorular.json"), "w",
                          encoding="utf-8") as f:
                    f.write(inc_json)
    return len(kirpmalar)


def belge_kapat(acik):
    """belge_sayfalari/belge_hazirla'nın açtığı fitz belgelerini kapatır.
    Kapattıktan sonra bu belgelere ait PdfSayfa/RasterSayfa'lar kullanılamaz."""
    _raster_lru_temizle()   # kapanan sayfalara ait render önbelleklerini bırak
    for doc in acik or []:
        try:
            doc.close()
        except Exception:  # noqa: BLE001 — kapanmış/bozuk doc önemsiz
            pass


# ------------------------------------------------------------------------ ana

def belgeyi_isle(girdiler, cikti, dpi, klasor, onizleme, birlestir=True,
                 agresif=False, secim=None, liste=False,
                 sinav_pdf_yolu=None, sinav_baslik=None, sinav_ayar=None,
                 kalite=VARSAYILAN_KALITE):
    """Bir çıktı için verilen girdileri yükle → tespit → kes → zip.
    Toplu modda her belge için ayrı çağrılır. Kesilen soru adedini döndürür.

    secim: secim_ayristir kuralları — yalnız seçilen sorular kesilir.
    liste=True: kesmeden test yapısını yazıp çıkar.
    sinav_pdf_yolu: kesilen sorulardan A4 sınav kağıdı PDF'i de üretilir."""
    try:
        sayfalar, acik, fmt, sutun_xler = belge_hazirla(girdiler, dpi)
    except (FileNotFoundError, ValueError, RuntimeError) as e:
        print(f"  HATA: {e}")
        return 0
    try:
        raster_say = sum(1 for s in sayfalar if s.raster)
        mod = ("taranmış/görüntü (OCR)" if raster_say == len(sayfalar)
               else "metin katmanı" if raster_say == 0 else "karışık")
        print(f"  Tespit: {len(sayfalar)} sayfa · {len(sutun_xler)} sütun · "
              f"{mod} · {fmt}")
        ocr_sorunlari = ocr_hatalari(sayfalar)
        if ocr_sorunlari:
            sayfa_liste = ", ".join(str(i) for i, _ in ocr_sorunlari[:8])
            ek = "…" if len(ocr_sorunlari) > 8 else ""
            print(f"  UYARI: {len(ocr_sorunlari)} sayfada OCR tamamlanamadı "
                  f"(sayfa {sayfa_liste}{ek}); diğer sayfalar işlendi.")

        if onizleme:
            klasor_yolu = os.path.splitext(cikti)[0] + "_onizleme"
            onizleme_modu = onizleme if isinstance(onizleme, str) else "ornek"
            for y in onizleme_uret(sayfalar, fmt, klasor_yolu,
                                   mod=onizleme_modu):
                print(f"  önizleme: {y}")
            print("Ön izleme hazır. Kutular doğruysa --onizleme olmadan "
                  "çalıştırın.")
            return 0

        cevaplar = cevap_anahtari_bul(sayfalar)
        if liste:
            testler, parca_meta = test_ozeti(sayfalar, fmt, cevaplar=cevaplar,
                                             birlestir=birlestir,
                                             agresif=agresif,
                                             kalite=kalite)
            test_ozeti_yaz(testler, parca_meta)
            return 0

        kapi, profil, analizler = kalite_kapisi(
            sayfalar, fmt, girdiler, kalite=kalite)
        if kalite == "strict" and not kapi.izin:
            klasor_yolu = os.path.splitext(cikti)[0] + "_inceleme"
            json_yolu, gorseller = inceleme_paketi_uret(
                sayfalar, fmt, klasor_yolu, girdiler, kalite,
                kapi_sonucu=kapi, profil=profil, analizler=analizler)
            print(f"  KATI KALİTE: {len(kapi.bekleyen_sayfalar)} sayfa "
                  f"inceleme bekliyor; nihai ZIP/sınav/banka yazılmadı.")
            print(f"  inceleme JSON: {json_yolu}")
            if gorseller:
                print(f"  bindirmeli sayfa: {len(gorseller)}")
            return 0
        if kalite == "balanced" and kapi.bekleyen_sayfalar:
            print(f"  UYARI: {len(kapi.bekleyen_sayfalar)} riskli sayfa "
                  "dışlandı; yalnız otomatik/onaylı sorular yazılacak.")

        kirpmalar, sorular, uyarilar = kirpma_seti(
            sayfalar, fmt, girdiler=girdiler, birlestir=birlestir,
            agresif=agresif, secim=secim, cevaplar=cevaplar,
            numara_temizle=bool(sinav_pdf_yolu),
            rastgele=sinav_ayar.get("rastgele") if sinav_ayar else None,
            tohum=sinav_ayar.get("tohum") if sinav_ayar else None,
            konu_sozluk=sinav_ayar.get("konu_sozluk") if sinav_ayar else None,
            kalite=kalite)
        for u in uyarilar:
            if u.startswith("dislanan_sayfa:"):
                # Uyarı değil, bilgi: bu sayfalar bilerek atlandı.
                _, adet, sayfalar_str = u.split(":", 2)
                print(f"  kasıtlı dışlanan sayfa: {adet}"
                      + (f" (s{sayfalar_str})" if sayfalar_str else "")
                      + " — cevap anahtarı/çözüm/soru dışı")
            else:
                print(f"  UYARI: {u}")
        if not kirpmalar:
            if secim:
                print("  Seçime uyan soru bulunamadı — mevcut testleri "
                      "görmek için --liste ile çalıştırın.")
            else:
                print("  Hiç soru bulunamadı — dosyada numaralı sorular "
                      "var mı?")
            return 0
        testli = sum(1 for so in sorular if so["test_sira"] is not None)
        cevapli = sum(1 for so in sorular if so["cevap"])
        ek = ""
        if testli:
            ek += f" · {len({so['test_sira'] for so in sorular if so['test_sira']})} test"
        if cevapli:
            ek += f" · {cevapli} cevap eşlendi"
        print(f"  {len(kirpmalar)} soru kesildi{ek}")

        if sinav_pdf_yolu:
            import sinav_pdf
            ayarlar = dict(sinav_ayar or {})
            ayarlar.setdefault("baslik", sinav_baslik or os.path.splitext(
                os.path.basename(girdiler[0]))[0])
            sonuc = sinav_pdf.sinav_pdf_uret(kirpmalar, sorular, ayarlar,
                                             sinav_pdf_yolu)
            if sonuc["kitapcik"] > 1:
                print(f"✓ {sonuc['kitapcik']} kitapçık ({sonuc['sayfa']} "
                      f"sayfa): {', '.join(os.path.basename(y) for y in sonuc['yollar'])}")
            else:
                print(f"✓ Sınav kağıdı: {sinav_pdf_yolu} "
                      f"({sonuc['sayfa']} sayfa)")
            if ayarlar.get("optik_form"):
                try:
                    import optik_koprusu
                    okok, _ = os.path.splitext(sinav_pdf_yolu)
                    optik = optik_koprusu.sinavdan_optik(
                        sorular, ayarlar, okok + "_optik.pdf")
                    print(f"✓ Optik cevap kâğıdı: {optik['pdf']} — "
                          f"kimlik {optik['sinav_id']}, "
                          f"{optik['anahtarli_soru']} cevap anahtarı, "
                          f"{optik['kazanimli_soru']} kazanım eşlendi")
                    for u in optik["uyarilar"]:
                        print(f"  UYARI: {u}")
                    print("  taramalar: python3 optik.py oku --sinav "
                          f"{optik['sinav_id']} <fotoğraf/pdf…>")
                except Exception as e:  # noqa: BLE001 — sınav üretimi bozulmaz
                    print(f"  UYARI: optik form üretilemedi: {e}")

        # Çözüm iliştirme + cevap bandı yalnız ZIP kopyasına uygulanır —
        # sınav PDF'i ve dışa aktarmalar bantsız/iliştirmesiz görüntüyle
        # çalışır (cevap orada metadata'dır).
        zip_kirpmalar, zip_sorular = kirpmalar, sorular
        if (sinav_ayar or {}).get("cozum_ilistir"):
            zip_kirpmalar, zip_sorular, cu = cozumleri_ilistir(
                list(kirpmalar), [dict(so) for so in sorular])
            ilistirilen = sum(1 for so in zip_sorular
                              if so.get("cozum_ilistirildi"))
            print(f"  Çözüm iliştirme: {ilistirilen} soruya çözüm eklendi")
            for u in cu[:8]:
                print(f"  UYARI: {u}")
        if (sinav_ayar or {}).get("cevap_bandi"):
            zip_kirpmalar = [cevap_bandi_ekle(im, so["cevap"])
                             if so.get("cevap") else im
                             for im, so in zip(zip_kirpmalar, zip_sorular)]
            print(f"  Cevap bandı: {cevapli} soruya basıldı")
        # İncele kovası: strict/balanced kipte otomatik teslim edilemeyen
        # kesimler eskiden SESSİZCE düşüyordu. Artık gerekçesiyle birlikte
        # `İncele/` altına yazılıyorlar — ana çıktı birebir aynı kalır.
        inc_kirpma, inc_soru = [], []
        if kalite != "legacy":
            try:
                inc_kirpma, inc_soru, _iu = inceleme_seti(
                    sayfalar, fmt, girdiler=girdiler, birlestir=birlestir,
                    agresif=agresif, secim=secim, cevaplar=cevaplar,
                    kalite=kalite)
            except Exception as e:  # noqa: BLE001 — ana çıktı riske girmesin
                print(f"  UYARI: İncele kovası üretilemedi: {e}")
        zip_yaz(zip_kirpmalar, cikti, klasor, sorular=zip_sorular,
                incele=inc_kirpma, incele_sorular=inc_soru)
        if klasor:
            print(f"  PNG klasörü: {os.path.splitext(cikti)[0]}")
        print(f"✓ {len(kirpmalar)} soru → {cikti}")
        if inc_kirpma:
            print(f"  {len(inc_kirpma)} kesim İncele/ klasörüne yazıldı "
                  f"(otomatik teslim edilemedi; gerekçeler "
                  f"İncele/sorular.json içinde)")

        for tur in (sinav_ayar or {}).get("disa") or []:
            tur = tur.strip().lower()
            if tur not in ("csv", "md", "html", "docx", "pdf-metin"):
                print(f"  UYARI: bilinmeyen dışa aktarma türü: {tur}")
                continue
            try:
                if tur in ("docx", "pdf-metin"):
                    import belge_disa
                    uz = "docx" if tur == "docx" else "pdf"
                    dyol = os.path.splitext(cikti)[0] + f"_soru.{uz}"
                    (belge_disa.docx_uret if tur == "docx"
                     else belge_disa.pdf_metin_uret)(sorular, kirpmalar, dyol)
                else:
                    metin, uz = disa_aktar(
                        sorular, tur,
                        kirpmalar=kirpmalar if tur == "html" else None)
                    dyol = os.path.splitext(cikti)[0] + f"_soru_bankasi.{uz}"
                    with open(dyol, "w", encoding="utf-8") as f:
                        f.write(metin)
                print(f"✓ Dışa aktarıldı ({tur}): {dyol}")
            except (ValueError, OSError, RuntimeError) as e:
                print(f"  HATA (dışa aktarma {tur}): {e}")
        return len(kirpmalar)
    finally:
        belge_kapat(acik)


def test_ozeti_yaz(testler, parca_meta):
    """--liste çıktısı: tespit edilen test yapısını insan-okur biçimde basar."""
    toplam = len(parca_meta)
    if not testler:
        print(f"  Test bölümü tespit edilmedi; {toplam} soru tek liste "
              "hâlinde. Seçim için sayfa (s12:3) ya da sıra (27-40) "
              "kullanılabilir.")
        return
    print(f"  {len(testler)} test · {toplam} soru:")
    for t in testler:
        ad = (f"test {t['test_no']}" if t["test_no"] is not None
              else "(numarasız bölüm)")
        soru = (f"soru {t['soru_bas']}-{t['soru_son']}"
                if t["soru_bas"] is not None else "numarasız")
        baslik = f" — \"{t['baslik']}\"" if t.get("baslik") else ""
        print(f"   #{t['test_sira']:>2} {ad:<10} sayfa "
              f"{t['sayfa_bas']}-{t['sayfa_son']:<4} {soru:<14} "
              f"{t['adet']} soru{baslik}")
    ornek = next((t for t in testler if t["test_no"] is not None), None)
    if ornek:
        print(f"  Örnek seçim: --sec \"test {ornek['test_no']}: "
              f"{ornek['soru_bas']}-{min(ornek['soru_bas'] + 3, ornek['soru_son'])}\"")


def main():
    p = argparse.ArgumentParser(
        description="PDF, DOCX ve yaygın görsel testleri soru soru "
                    "kırpıp Arşiv.zip'e koyar.")
    p.add_argument("girdiler", nargs="+",
                   help="PDF / DOCX / PNG / JPG / TIFF / BMP / WebP / GIF")
    p.add_argument("-o", "--cikti", default=None,
                   help="Çıktı zip yolu (varsayılan: ilk girdinin yanına "
                        "Arşiv.zip). --coklu ile: çıktı KLASÖRÜ")
    p.add_argument("--dpi", type=int, default=300,
                   help="Kırpma çözünürlüğü (varsayılan: 300)")
    p.add_argument("--klasor", action="store_true",
                   help="Zip'in yanına PNG'leri klasör olarak da çıkar")
    p.add_argument("--coklu", action="store_true",
                   help="Her girdiyi AYRI arşive işle (<girdi>_Arşiv.zip); "
                        "-o çıktı klasörü olur (eski kısayol).")
    p.add_argument("--girdi-grubu", choices=["tek-belge", "ayri"],
                   default="tek-belge",
                   help="Girdileri ardışık tek belge veya ayrı belgeler "
                        "olarak profille (varsayılan: tek-belge)")
    p.add_argument("--kalite", choices=KALITE_MODLARI,
                   default=VARSAYILAN_KALITE,
                   help="strict: bekleyen riskte hiç çıktı yazma; balanced: "
                        "yalnız güvenli alt küme; legacy: eski davranış")
    p.add_argument("--onizleme", nargs="?", const="riskli", default=None,
                   choices=["riskli", "ornek", "tum"],
                   help="Kesmeden bindirme üret: riskli | ornek | tum "
                        "(değersiz kullanım: riskli)")
    p.add_argument("--ocr-modu", choices=["hizli", "dengeli", "tam"],
                   default=None,
                   help="çok-motor OCR hakemliği: hizli (yalnız Vision), "
                        "dengeli (şüpheli satırlarda 5-motor), tam (tüm sayfa)")
    p.add_argument("--ocr-cache-kapat", action="store_true",
                   help="OCR disk önbelleğini devre dışı bırak")
    p.add_argument("--ocr-paralel", type=int, default=None, metavar="N",
                   help="Taranmış sayfa OCR'ında iş parçacığı sayısı "
                        "(varsayılan: min(4, çekirdek); 1 = seri)")
    p.add_argument("--duzen-model", choices=["acik", "kapali"], default=None,
                   help="ML düzen tespitini bu çalıştırma için zorla aç/"
                        "kapat (varsayılan: ~/.soru_kesici.json içindeki "
                        "duzen_model_aktif; kurulum: python3 duzen_kur.py)")
    p.add_argument("--birlestirme", choices=["acik", "kapali"],
                   default="acik",
                   help="Sütun/sayfa sonunda bölünen soruları şık-devamı "
                        "kanıtıyla birleştir (varsayılan: acik)")
    p.add_argument("--birlestirme-agresif", action="store_true",
                   help="Şık kanıtı olmadan, yalnız cümle-ortası sinyaliyle "
                        "de birleştir (açık uçlu/karışık için; riskli)")
    p.add_argument("--sec", default=None, metavar="SPEC",
                   help='Yalnız seçilen soruları kes. Örnekler: '
                        '"test 5: 2-10; test 3: 10-15" · "t5" (tüm test) · '
                        '"t1#9" (yinelenen test adında 9. bölüm) · '
                        '"s12: 3-5" (sayfa) · "27-40" (çıktı sırası). '
                        'Mevcut testleri görmek için --liste')
    p.add_argument("--liste", action="store_true",
                   help="Kesmeden testleri ve soru aralıklarını listele "
                        "(neyi seçebileceğini gör)")
    p.add_argument("--sinav-pdf", default=None, metavar="ÇIKTI.pdf",
                   help="Kesilen sorulardan yazdırılabilir A4 sınav kağıdı "
                        "PDF'i de üret (--sec ile birlikte kullanışlı)")
    p.add_argument("--optik-form", action="store_true",
                   help="--sinav-pdf ile: eşleşen optik cevap kâğıdı da "
                        "üret; kitapçık anahtarları ve konu/kazanım "
                        "eşlemesi optik veritabanına otomatik yazılır "
                        "(taramalar: python3 optik.py oku / web 🔘 Optik)")
    p.add_argument("--baslik", default=None,
                   help="--sinav-pdf başlığı (varsayılan: girdi dosya adı)")
    p.add_argument("--kurum", default=None,
                   help="--sinav-pdf üst bilgisine kurum/okul adı")
    p.add_argument("--kitapcik", type=int, default=1, metavar="N",
                   help="N kitapçık (A/B/C/D): soru sırası karıştırılmış "
                        "ayrı PDF'ler + her birine cevap anahtarı (kopya "
                        "önleme). Varsayılan 1")
    p.add_argument("--puan", type=float, default=None, metavar="TOPLAM",
                   help="Sınav toplam puanı; soru başına eşit dağıtılıp "
                        "numaraların yanına yazılır")
    p.add_argument("--rastgele", type=int, default=None, metavar="N",
                   help="Her testten rastgele N soru örnekle (havuzdan "
                        "dengeli seçim). --sec ile birlikte kullanılabilir")
    p.add_argument("--tohum", type=int, default=None, metavar="N",
                   help="--rastgele/--kitapcik için tekrarlanabilirlik tohumu")
    p.add_argument("--cevap-bandi", action="store_true",
                   help="cevap anahtarından bulunan cevabı kesilen soru "
                        "görselinin altına bant olarak bas (yalnız ZIP; "
                        "sınav PDF'i bantsız kalır)")
    p.add_argument("--cozum-ilistir", action="store_true",
                   help="çözümlü kaynakta çözümü aynı numaralı sorunun "
                        "altına iliştir (eşleşen çözüm ayrı kesilmez)")
    p.add_argument("--disa", default=None, metavar="TÜR",
                   help="Soruları dışa aktar: csv | md | html | docx | "
                        "pdf-metin (virgülle birden çok). docx/pdf-metin: "
                        "şekilsiz soru editlenebilir metin, şekilli soru şekli "
                        "korunur (OCR). Zip'in yanına yazılır")
    p.add_argument("--konu-csv", default=None, metavar="YOL",
                   help="Otomatik konu etiketleme sözlüğü (konular.csv); "
                        "verilirse sorular.json'a 'konu' alanı eklenir")
    args = p.parse_args()

    secim = None
    if args.sec:
        try:
            secim = secim_ayristir(args.sec)
        except ValueError as e:
            print(f"HATA (--sec): {e}")
            sys.exit(2)

    global OCR_CACHE_AKTIF, OCR_PARALEL
    if args.ocr_modu:
        try:
            import ocr_ensemble
            ocr_ensemble.MOD_ZORLA = args.ocr_modu
        except Exception:  # noqa: BLE001
            pass
    if args.ocr_cache_kapat:
        OCR_CACHE_AKTIF = False
    if args.ocr_paralel:
        OCR_PARALEL = max(1, args.ocr_paralel)
    if args.duzen_model and duzen_model is not None:
        duzen_model.AKTIF_ZORLA = args.duzen_model == "acik"
    birlestir = args.birlestirme == "acik"
    konu_sozluk = None
    if args.konu_csv:
        konu_sozluk = konu_sozlugu_oku(args.konu_csv)
        if not konu_sozluk:
            print(f"UYARI: konu sözlüğü boş/okunamadı: {args.konu_csv}")
    sinav_ayar = {"kurum": args.kurum, "kitapcik": args.kitapcik,
                  "toplam_puan": args.puan, "rastgele": args.rastgele,
                  "tohum": args.tohum,
                  "disa": args.disa.split(",") if args.disa else None,
                  "konu_sozluk": konu_sozluk,
                  "cevap_bandi": args.cevap_bandi,
                  "cozum_ilistir": args.cozum_ilistir,
                  "optik_form": args.optik_form}

    print("Dosyalar yükleniyor ve ön izleniyor…")
    ayri_girdi = args.coklu or args.girdi_grubu == "ayri"
    if ayri_girdi:
        # Her girdi kendi arşivine (belge-başına kalibrasyon = daha doğru)
        klasor_cikti = args.cikti or os.path.dirname(
            os.path.abspath(args.girdiler[0]))
        os.makedirs(klasor_cikti, exist_ok=True)
        toplam = 0
        for yol in args.girdiler:
            ad = os.path.splitext(os.path.basename(yol))[0]
            hedef = os.path.join(klasor_cikti, f"{ad}_Arşiv.zip")
            print(f"\n[{os.path.basename(yol)}]")
            sinav_yolu = None
            if args.sinav_pdf:
                sinav_yolu = os.path.join(klasor_cikti, f"{ad}_Sınav.pdf")
            toplam += belgeyi_isle([yol], hedef, args.dpi, args.klasor,
                                   args.onizleme, birlestir,
                                   args.birlestirme_agresif, secim,
                                   args.liste, sinav_yolu, args.baslik,
                                   sinav_ayar, args.kalite)
        if not args.onizleme and not args.liste:
            print(f"\n✓ Toplam {toplam} soru · {len(args.girdiler)} arşiv")
        return

    cikti = args.cikti or os.path.join(
        os.path.dirname(os.path.abspath(args.girdiler[0])), "Arşiv.zip")
    adet = belgeyi_isle(args.girdiler, cikti, args.dpi, args.klasor,
                        args.onizleme, birlestir, args.birlestirme_agresif,
                        secim, args.liste, args.sinav_pdf, args.baslik,
                        sinav_ayar, args.kalite)
    if adet == 0 and not args.onizleme and not args.liste:
        sys.exit(1)


if __name__ == "__main__":
    main()
