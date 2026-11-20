#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Metin katmanlı, iki sütunlu sınav PDF'lerinden bağımsız golden-v2 üretir.

Bu araç Soru Kesici'nin tespit kutularını kullanmaz. Soru başlangıçlarını
PDF'nin yerleşik kelime koordinatlarından bulur; böylece üretilen veri motorun
kendi cevabını kopyalayan bir sözde etiket olmaz. Çıktı yine insan denetimine
yardımcı temas sayfalarıyla birlikte üretilir.

Kitap ailesine özgü geometri ve desenler ``kalite/altin_profil/profiller.json``
dosyasındaki profillerden okunur (``--profil``). Profil verilmezse modülün
kendi varsayılan profili (MEBİ TYT denemesi) kullanılır; bu, bayrak
eklenmeden önceki davranışın birebir aynısıdır.
"""

import argparse
import collections
import datetime
import hashlib
import json
import os
import re
import sys
import unicodedata

import fitz


SEMA_SURUMU = "soru-kesici.golden/v2"
SUTUNLAR = (
    {"ad": "sol", "x0": 31.0, "x1": 275.0, "capa": 36.0},
    {"ad": "sag", "x0": 282.0, "x1": 527.0, "capa": 287.7},
)
KONULAR = (
    ("turkce", "turkce testi", 40),
    ("sosyal", "sosyal bilimler testi", 25),
    ("matematik", "temel matematik testi", 40),
    ("fen", "fen bilimleri testi", 20),
)
ARALIK_DESENI = re.compile(
    r"(?<!\d)(\d{1,2})\s*[-–]\s*(\d{1,2})\.\s*sorular")
DENEME_DESENI = re.compile(r"(?<!\d)([1-8])\.\s*deneme")
NUMARA_DESENI = re.compile(r"(\d{1,2})\.")

# Varsayılan profilin ölçüldüğü sayfa: MEBİ TYT denemesinin gerçek
# ``page.rect`` yüksekliği. Kenar payları buna bölünerek orana çevrildiği için
# aynı yükseklikteki bir sayfada mutlak sınırlar (68 / 730 / 733) birebir geri
# gelir; farklı boyutlu bir kitapta ise sayfayla birlikte ölçeklenir.
VARSAYILAN_SAYFA_YUKSEKLIGI = 779.5280151367188
VARSAYILAN_KENAR_PAYLARI = {
    "capa_ust": 68.0 / VARSAYILAN_SAYFA_YUKSEKLIGI,
    "capa_alt": 730.0 / VARSAYILAN_SAYFA_YUKSEKLIGI,
    "govde_alt": 733.0 / VARSAYILAN_SAYFA_YUKSEKLIGI,
}
PROFIL_DOSYASI = os.path.join(
    os.path.dirname(os.path.abspath(__file__)),
    "kalite", "altin_profil", "profiller.json")
# Çapa türetmede mod kümelemesinin yarıçapı ve bir kümenin çapa sayılması için
# gereken asgari kelime sayısı.
TURETME_YARICAPI = 6.0
TURETME_ASGARI_ADET = 12
# Şıklar tek satırda yan yana da dizilebiliyor ("A) 660   B) 740 ..."), bu
# yüzden işaret satır başında aranmaz; parantez öncesi harf/rakam olmaması
# metin içindeki rastgele "A)" benzeri dizilimleri eler.
SECENEK_DESENI = re.compile(r"(?:^|[\s\t])([A-E])\s*\)")

# Bölge üretimi ayarları. Şekil kümelemesi karesel olduğu için aday sayısı
# sınırlanır; kapak/dizgi sayfalarında binlerce vektör parçası bulunabiliyor.
FIGUR_KUME_BOSLUGU = 6.0
FIGUR_ASGARI_KENAR = 20.0
FIGUR_ASGARI_KAPSAMA = 0.9
FIGUR_AZAMI_ADAY = 400
# Komşu soru satırının gövdeye bakan kenarından kırpılan pay. Altın gövde ile
# komşu satır arasında zaten 4 pt boşluk var; bu pay yuvarlama/raster
# oynamasının "sızıntı" sayılmasını engeller, gerçek sızıntıyı gizlemez.
BOLGE_KOMSU_PAYI = 2.0
SATIR_BANDI = 4.0
GEREKLI_BOLGE_TURLERI = {
    "sekil", "tablo", "formul", "metin", "secenek", "yazma_alani", "diger",
}
YASAK_BOLGE_TURLERI = {
    "komsu_soru", "baslik", "altbilgi", "cevap", "cozum", "diger",
}


class Profil:
    """Bir kitap ailesinin dizgi varsayımlarını taşır.

    Motor sabitleri (sütun çapaları, bölüm başlıkları, kenar payları) tek bir
    kitaba gömülü kaldığı sürece üretici o kitabın dışına çıkamaz. Profil bu
    varsayımları veriye çevirir; ``altin_uret`` yalnızca profilin söylediğini
    uygular.

    ``bolum_kipi``:

    * ``konu`` — bölüm, sayfadaki konu başlığı + deneme numarasından okunur ve
      beklenen soru adetleri dayatılabilir (MEBİ TYT denemesi).
    * ``dizi`` — bölüm, numara dizisinin kendisinden türetilir: numara bir
      önceki numaranın altına düştüğünde yeni bölüm başlar. Beklenen adet
      bilgisi olmayan kitaplar için tek dayanak zincirin kendisidir.
    """

    def __init__(self, ad, *, sutunlar=None, capa_hizasi="x0",
                 capa_toleransi=6.0, numara_azami_hane=2,
                 kenar_paylari=None, bolum_kipi="konu", konular=(),
                 deneme_deseni=None, aralik_deseni=None,
                 atlanacak_sayfa_deseni=None, sutun_turetme=None,
                 sayfa_rect=None, aciklama=""):
        if bolum_kipi not in ("konu", "dizi"):
            raise ValueError(f"{ad}: bilinmeyen bolum_kipi {bolum_kipi!r}")
        if capa_hizasi not in ("x0", "x1"):
            raise ValueError(f"{ad}: bilinmeyen capa_hizasi {capa_hizasi!r}")
        if not 1 <= int(numara_azami_hane) <= 3:
            raise ValueError(f"{ad}: numara_azami_hane 1-3 olmalı")
        self.ad = ad
        self.aciklama = aciklama
        self.sutunlar = tuple(dict(s) for s in sutunlar) if sutunlar else None
        self.capa_hizasi = capa_hizasi
        self.capa_toleransi = float(capa_toleransi)
        self.numara_azami_hane = int(numara_azami_hane)
        self.numara_deseni = re.compile(
            r"(\d{1,%d})\." % self.numara_azami_hane)
        self.kenar_paylari = dict(kenar_paylari or VARSAYILAN_KENAR_PAYLARI)
        eksik = {"capa_ust", "capa_alt", "govde_alt"} - set(self.kenar_paylari)
        if eksik:
            raise ValueError(f"{ad}: kenar payı eksik: {sorted(eksik)}")
        self.bolum_kipi = bolum_kipi
        self.konular = tuple(
            (k[0], k[1], (None if len(k) < 3 or k[2] is None else int(k[2])))
            for k in (konular or ())
        )
        self.deneme_deseni = (
            re.compile(deneme_deseni) if isinstance(deneme_deseni, str)
            else deneme_deseni)
        self.aralik_deseni = (
            re.compile(aralik_deseni) if isinstance(aralik_deseni, str)
            else aralik_deseni)
        self.atlanacak_sayfa_deseni = (
            re.compile(atlanacak_sayfa_deseni)
            if isinstance(atlanacak_sayfa_deseni, str)
            else atlanacak_sayfa_deseni)
        self.sutun_turetme = dict(sutun_turetme or {})
        self.sayfa_rect = tuple(sayfa_rect) if sayfa_rect else None
        if bolum_kipi == "konu" and (not self.konular
                                     or self.deneme_deseni is None):
            raise ValueError(f"{ad}: konu kipi konular+deneme_deseni ister")

    @property
    def beklenen_adetler(self):
        """Her konu için beklenen soru adedi biliniyorsa True."""
        return bool(self.konular) and all(
            adet is not None for _ad, _baslik, adet in self.konular)

    def y_sinirlari(self, page):
        """Sayfa yüksekliğine oranlı (çapa üst, çapa alt, gövde alt)."""
        yukseklik = float(page.rect.height)
        return (
            self.kenar_paylari["capa_ust"] * yukseklik,
            self.kenar_paylari["capa_alt"] * yukseklik,
            self.kenar_paylari["govde_alt"] * yukseklik,
        )

    def capa_konumu(self, x0, x1):
        """Çapa hizasına göre numaranın karşılaştırılacak kenarı."""
        return float(x0) if self.capa_hizasi == "x0" else float(x1)

    def sutunlarla(self, sutunlar):
        """Aynı profilin, çapaları türetilmiş kopyasını verir."""
        yeni = Profil.__new__(Profil)
        yeni.__dict__.update(self.__dict__)
        yeni.sutunlar = tuple(dict(s) for s in sutunlar)
        return yeni


VARSAYILAN_PROFIL = Profil(
    "mebi-tyt-deneme",
    sutunlar=SUTUNLAR,
    capa_hizasi="x0",
    capa_toleransi=6.0,
    numara_azami_hane=2,
    kenar_paylari=VARSAYILAN_KENAR_PAYLARI,
    bolum_kipi="konu",
    konular=KONULAR,
    deneme_deseni=DENEME_DESENI,
    aralik_deseni=ARALIK_DESENI,
    aciklama="MEBİ TYT denemesi (tyt-1); bayraksız varsayılan davranış",
)


def profilleri_yukle(yol=None):
    """Profil dosyasını okur; {ad: Profil} döndürür."""
    yol = yol or PROFIL_DOSYASI
    with open(yol, encoding="utf-8") as kaynak:
        veri = json.load(kaynak)
    profiller = {}
    for ad, ayar in (veri.get("profiller") or {}).items():
        temiz = {k: v for k, v in ayar.items() if not k.startswith("_")}
        profiller[ad] = Profil(ad, **temiz)
    return profiller


def profil_coz(ad, yol=None):
    """``--profil`` değerini Profil nesnesine çevirir."""
    if not ad:
        return VARSAYILAN_PROFIL
    profiller = profilleri_yukle(yol)
    if ad not in profiller:
        raise ValueError(
            f"bilinmeyen profil {ad!r}; tanımlı: {sorted(profiller)}")
    return profiller[ad]


def _ascii(deger):
    """Türkçe I/İ/ı dâhil metni karşılaştırma için kararlılaştırır."""
    metin = str(deger).casefold().replace("ı", "i")
    return "".join(
        c for c in unicodedata.normalize("NFKD", metin)
        if not unicodedata.combining(c)
    )


def _sha256(yol):
    ozet = hashlib.sha256()
    with open(yol, "rb") as kaynak:
        while True:
            parca = kaynak.read(1024 * 1024)
            if not parca:
                break
            ozet.update(parca)
    return ozet.hexdigest()


def _aralik(deger, *, alt, ust, ad):
    """'N', 'N-M' ya da virgüllü karışık listeyi sayfa listesine çevirir.

    Bitişik olmayan liste gerekiyor çünkü ölçüm tarafı büyük belgelerde
    sayfaları BELGE BOYUNCA eşit aralıklı örnekliyor; altın veri o örneklemin
    dışındaki sayfaları kapsarsa ölçüm altınla hizalanmaz ve F1 anlamsız
    biçimde çöker.
    """
    if deger is None:
        return list(range(alt, ust + 1))
    sonuc = []
    for parca in str(deger).split(","):
        m = re.fullmatch(r"\s*(\d+)\s*(?:-\s*(\d+)\s*)?", parca)
        if not m:
            raise ValueError(
                f"{ad}: 'N', 'N-M' ya da virgüllü liste bekleniyor")
        bas = int(m.group(1))
        son = int(m.group(2) or bas)
        if not alt <= bas <= son <= ust:
            raise ValueError(f"{ad}: {alt}-{ust} aralığında olmalı")
        sonuc.extend(range(bas, son + 1))
    return sorted(dict.fromkeys(sonuc))


def _konu_ve_deneme(page, profil=None):
    profil = profil or VARSAYILAN_PROFIL
    metin = _ascii(" ".join(page.get_text("text").split()))
    if _cevap_anahtari_sayfasi(metin, profil):
        return None
    konu = next(
        (ad for ad, baslik, _ in profil.konular if baslik in metin), None)
    deneme = (profil.deneme_deseni.search(metin)
              if profil.deneme_deseni else None)
    if konu is None or deneme is None:
        return None
    return int(deneme.group(1)), konu


def _cevap_anahtari_sayfasi(normalize_metin, profil=None):
    """Soru içinde geçen “cevap anahtarı” sözünü sayfa rolü sanmaz."""
    profil = profil or VARSAYILAN_PROFIL
    konu_basligi_sayisi = sum(
        baslik in normalize_metin for _ad, baslik, _adet in profil.konular)
    return (
        "cevap anahtari" in normalize_metin
        and konu_basligi_sayisi >= 3
    )


def _sutun_no(x0, x1=None, profil=None):
    profil = profil or VARSAYILAN_PROFIL
    sutunlar = profil.sutunlar
    konum = profil.capa_konumu(x0, x0 if x1 is None else x1)
    yakin = min(
        range(len(sutunlar)),
        key=lambda i: abs(konum - sutunlar[i]["capa"]))
    fark = abs(konum - sutunlar[yakin]["capa"])
    return yakin if fark <= profil.capa_toleransi else None


def _sayfa_atlanir(page, profil):
    """Yönerge/açıklama sayfalarını çapa taramasının dışında tutar.

    ``AÇIKLAMA`` sayfasındaki madde numaraları da sütun bandına yakın basılır;
    elenmezlerse zincir kipinde altı tane hayalet soru üretirler.
    """
    if profil.atlanacak_sayfa_deseni is None:
        return False
    metin = _ascii(" ".join(page.get_text("text").split()))
    return profil.atlanacak_sayfa_deseni.search(metin) is not None


def _fiziksel_capalar(page, sayfa_no, bolum, profil=None):
    """Gerçek soru numarası olabilecek PDF kelimelerini döndürür."""
    profil = profil or VARSAYILAN_PROFIL
    deneme, konu = bolum
    capa_ust, capa_alt, _govde_alt = profil.y_sinirlari(page)
    sonuc = []
    for x0, y0, x1, y1, metin, *_ in page.get_text("words"):
        eslesme = profil.numara_deseni.fullmatch(metin.strip())
        sutun = _sutun_no(x0, x1, profil)
        if (eslesme is None or sutun is None
                or not capa_ust <= float(y0) <= capa_alt):
            continue
        sonuc.append({
            "deneme": deneme,
            "konu": konu,
            "numara": int(eslesme.group(1)),
            "page": sayfa_no,
            "column": sutun,
            "word_box": [float(x0), float(y0), float(x1), float(y1)],
        })
    return sonuc


def _okuma_sirasi(capa):
    """İki sütunlu dizgide okuma sırası: sayfa → sütun → dikey konum."""
    return (capa["page"], capa["column"], capa["word_box"][1])


def _bolumlere_ayir(capalar):
    """Numara dizisinden bölüm sınırlarını çıkarır (zincir kipi).

    Beklenen adet bilgisi olmayan kitapta bölümü söyleyecek tek kanıt numara
    dizisidir: numara bir öncekinin altına düştüğünde yeni test başlamıştır.

    Numaranın aynen tekrarı iki ayrı şey olabilir: (a) sayfa devrinde aynı
    numaranın iki kez basıldığı bilinen dizgi durumu — o zaman aynı bölümde
    kalır ve kararı ``_capalari_sec`` verir; (b) ölçüm sayfaları seyrek
    örneklendiğinde iki ayrı testin aynı numarası. İkisini ayıran şey sayfa
    mesafesidir: gerçek tekrar aynı ya da komşu sayfadadır. Ayrım yapılmazsa
    (b) durumunda gerçek bir soru "yinelenen baskı" sanılıp düşürülür.
    """
    sirali = sorted(capalar, key=_okuma_sirasi)
    bolum = 0
    son = None
    onceki_sayfa = None
    for capa in sirali:
        numara = capa["numara"]
        komsu_sayfa = (onceki_sayfa is not None
                       and capa["page"] - onceki_sayfa <= 1)
        if son is None or numara < son or (numara == son and not komsu_sayfa):
            bolum += 1
        son = numara
        onceki_sayfa = capa["page"]
        capa["deneme"] = bolum
        capa["konu"] = ""
    return sirali


def _capalari_sec(capalar, denemeler, profil=None, *, serbest=False,
                  rapor=None):
    """Her mantıksal soruya tek başlangıç seçer.

    Ardışık sayfalarda aynı numaranın ikinci kez tam basıldığı dizgi durumu
    için üstte başlayan sonraki kopya esas alınır; ilk baskı ignore_regions
    ile kalite hesabından çıkarılır.

    Katı kipte (varsayılan) beklenen adet listesi dayatılır ve her sapma hata
    verir. ``serbest`` kipinde adet dayatılmaz: yalnızca bulunan çapalar
    zincire göre değerlendirilir, çözülemeyen tekrarlar ``rapor`` sözlüğüne
    yazılır ve çağıran bunu insana gösterir.
    """
    profil = profil or VARSAYILAN_PROFIL
    gruplar = collections.defaultdict(list)
    for capa in capalar:
        if profil.bolum_kipi == "konu" and capa["deneme"] not in denemeler:
            continue
        gruplar[(capa["deneme"], capa["konu"], capa["numara"])].append(capa)

    zorunlu = (
        not serbest
        and profil.bolum_kipi == "konu"
        and profil.beklenen_adetler
    )
    if zorunlu:
        anahtarlar = [
            (deneme, konu, numara)
            for deneme in denemeler
            for konu, _baslik, adet in profil.konular
            for numara in range(1, adet + 1)
        ]
    else:
        anahtarlar = sorted(gruplar)

    secilen = []
    yinelenen = []
    cozulmeyen = []
    for anahtar in anahtarlar:
        deneme, konu, numara = anahtar
        adaylar = sorted(
            gruplar.get(anahtar, []),
            key=lambda c: (c["page"], c["word_box"][1]))
        if len(adaylar) == 1:
            secilen.append(adaylar[0])
            continue
        if len(adaylar) == 2:
            onceki, sonraki = adaylar
            if (sonraki["page"] == onceki["page"] + 1
                    and onceki["word_box"][1] > 250
                    and sonraki["word_box"][1] < 150):
                secilen.append(sonraki)
                yinelenen.append(onceki)
                continue
        konumlar = [
            (a["page"], round(a["word_box"][0], 1),
             round(a["word_box"][1], 1))
            for a in adaylar
        ]
        if zorunlu:
            raise ValueError(
                f"{deneme}. deneme {konu} soru {numara}: "
                f"tek bağımsız çapa bekleniyordu, bulunan={konumlar}")
        cozulmeyen.append({
            "bolum": deneme, "konu": konu, "numara": numara,
            "konumlar": konumlar,
        })
        secilen.append(adaylar[0])
        yinelenen.extend(adaylar[1:])
    if rapor is not None:
        rapor["cozulmeyen"] = cozulmeyen
        rapor["zincir"] = _zinciri_denetle(secilen)
    return secilen, yinelenen


def _zinciri_denetle(secilen):
    """Bölüm başına numara zincirinin sürekliliğini raporlar.

    Adet dayatmayan kipte doğruluğun tek ölçüsü budur: bir bölümün numaraları
    1'den başlayıp bir bir artmalıdır. Eksik ya da baştan kaçık zincir
    üreticinin bir çapayı kaçırdığını (ya da uydurduğunu) söyler; kararı
    insana bırakmak için hata yerine özet döndürülür.
    """
    bolumler = collections.defaultdict(list)
    for capa in secilen:
        bolumler[(capa["deneme"], capa["konu"])].append(capa)
    ozet = []
    for anahtar in sorted(bolumler):
        grup = sorted(bolumler[anahtar], key=_okuma_sirasi)
        numaralar = [c["numara"] for c in grup]
        beklenen = set(range(min(numaralar), max(numaralar) + 1))
        ozet.append({
            "bolum": anahtar[0],
            "konu": anahtar[1],
            "adet": len(grup),
            "ilk": min(numaralar),
            "son": max(numaralar),
            "sayfalar": [grup[0]["page"], grup[-1]["page"]],
            "eksik": sorted(beklenen - set(numaralar)),
            "birden_baslamiyor": min(numaralar) != 1,
        })
    return ozet


def _capalari_turet(doc, sayfalar, profil):
    """Sütun çapalarını numara kelimelerinin konum histogramından türetir.

    Profil geometriyi vermediğinde tek dayanak belgenin kendisidir: numara
    gibi görünen kelimelerin kenar konumları ±``TURETME_YARICAPI`` içinde
    kümelenir, yeterince kalabalık kümeler sütun çapası sayılır. Türetilen
    değerler ``stderr``e basılır; insan doğrulamadan altın yayınlanmamalıdır.
    """
    ayar = profil.sutun_turetme
    yaricap = float(ayar.get("yaricap", TURETME_YARICAPI))
    asgari = int(ayar.get("asgari_adet", TURETME_ASGARI_ADET))
    sol_payi = float(ayar.get("sol_payi", 5.0))
    genislik = float(ayar.get("genislik", 244.0))
    sayac = collections.Counter()
    for sayfa_no in sayfalar:
        page = doc[sayfa_no - 1]
        if _sayfa_atlanir(page, profil):
            continue
        capa_ust, capa_alt, _govde_alt = profil.y_sinirlari(page)
        for x0, y0, x1, _y1, metin, *_ in page.get_text("words"):
            if profil.numara_deseni.fullmatch(metin.strip()) is None:
                continue
            if not capa_ust <= float(y0) <= capa_alt:
                continue
            sayac[round(profil.capa_konumu(x0, x1), 1)] += 1

    kumeler = []
    for konum, adet in sorted(sayac.items(), key=lambda p: -p[1]):
        if any(abs(konum - k["capa"]) <= yaricap for k in kumeler):
            for kume in kumeler:
                if abs(konum - kume["capa"]) <= yaricap:
                    kume["adet"] += adet
                    break
            continue
        kumeler.append({"capa": konum, "adet": adet})
    secili = sorted(
        (k for k in kumeler if k["adet"] >= asgari),
        key=lambda k: k["capa"])
    if len(secili) < 2:
        raise ValueError(
            "sütun çapası türetilemedi; histogram="
            f"{[(k['capa'], k['adet']) for k in kumeler[:6]]}")
    adlar = ("sol", "sag", "uc", "dort")
    # Sola hizalı dizgide çapa numaranın sol kenarıdır; sağa hizalıda sağ
    # kenarıdır, o yüzden sütunun sol sınırı numara genişliği kadar geriden
    # başlar.
    numara_genisligi = float(ayar.get("numara_genisligi", 13.0))
    sutunlar = []
    for i, kume in enumerate(secili):
        capa = kume["capa"]
        taban = (capa if profil.capa_hizasi == "x0"
                 else capa - numara_genisligi) - sol_payi
        sutunlar.append({
            "ad": adlar[i] if i < len(adlar) else f"s{i}",
            "x0": round(taban, 3),
            "x1": round(taban + genislik, 3),
            "capa": capa,
        })
    print(
        "türetilen sütun çapaları: "
        + ", ".join(f"{s['ad']}={s['capa']} (x0={s['x0']}, x1={s['x1']}, "
                    f"adet={k['adet']})"
                    for s, k in zip(sutunlar, secili)),
        file=sys.stderr)
    return sutunlar


def _sonraki_capa(capa, sayfa_capalari):
    ayni = sorted(
        (a for a in sayfa_capalari
         if a["column"] == capa["column"]
         and a["word_box"][1] > capa["word_box"][1] + 1.0),
        key=lambda a: a["word_box"][1])
    return ayni[0] if ayni else None


def _normal_kutu(kutu):
    """Ters çevrilmiş çizim kutusunu (x0<=x1, y0<=y1) hâline getirir."""
    x0, y0, x1, y1 = (float(kutu[0]), float(kutu[1]),
                      float(kutu[2]), float(kutu[3]))
    return (min(x0, x1), min(y0, y1), max(x0, x1), max(y0, y1))


def _kutu_anahtari(kutu):
    return tuple(round(float(deger), 1) for deger in kutu)


def _alan(kutu):
    return max(0.0, kutu[2] - kutu[0]) * max(0.0, kutu[3] - kutu[1])


def _birlesim(kutular):
    kutular = list(kutular)
    return (
        min(k[0] for k in kutular), min(k[1] for k in kutular),
        max(k[2] for k in kutular), max(k[3] for k in kutular),
    )


def _kesisim(a, b):
    kutu = (max(a[0], b[0]), max(a[1], b[1]),
            min(a[2], b[2]), min(a[3], b[3]))
    return kutu if kutu[0] < kutu[2] and kutu[1] < kutu[3] else None


def _birlesim_alani(kutular):
    """Çakışan kutuların gerçek birleşim alanını (çift saymadan) verir.

    Denetimde tek tek parçalarla kesişim almak yetmez: bir gerekli bölge iki
    parçaya bölünmüş olabilir, o zaman hiçbir parça bölgeyi tek başına
    kapsamaz ama birleşimleri kapsar. Ölçüm tarafı (``dogrula``) kapsamayı
    zaten birleşim üzerinden hesaplıyor; denetim başka bir tanım kullanırsa
    üretici ile ölçüm sessizce ayrışır.
    """
    kutular = [k for k in kutular if _alan(k) > 0.0]
    if not kutular:
        return 0.0
    xler = sorted({k[0] for k in kutular} | {k[2] for k in kutular})
    toplam = 0.0
    for xa, xb in zip(xler, xler[1:]):
        if xb <= xa:
            continue
        araliklar = sorted(
            (k[1], k[3]) for k in kutular if k[0] < xb and k[2] > xa)
        if not araliklar:
            continue
        yukseklik = 0.0
        ust, alt = araliklar[0]
        for bas, son in araliklar[1:]:
            if bas > alt:
                yukseklik += alt - ust
                ust, alt = bas, son
            else:
                alt = max(alt, son)
        yukseklik += alt - ust
        toplam += (xb - xa) * yukseklik
    return toplam


def _degiyor(a, b, bosluk):
    """İki kutu ``bosluk`` kadar yaklaşmışsa aynı şeklin parçasıdır."""
    return (a[0] - bosluk <= b[2] and b[0] - bosluk <= a[2]
            and a[1] - bosluk <= b[3] and b[1] - bosluk <= a[3])


def _gorsel_gurultu(kutu):
    """Sütun ayracı ve sayfa çizgisi gibi dizgi süslerini eler.

    ``_govde_kutusu`` ile bölge üretimi aynı kararı vermek zorunda; filtre iki
    yerde ayrı yazılırsa gövde sınırı ile şekil bölgesi birbirinden kayar.
    """
    genislik = abs(kutu[2] - kutu[0])
    yukseklik = abs(kutu[3] - kutu[1])
    ayirac = genislik < 2.5 and yukseklik > 180
    sayfa_cizgisi = genislik > 420 and yukseklik < 4
    return ayirac or sayfa_cizgisi


def _dekor_kutulari(sayfa_gorselleri):
    """Sayfadan sayfaya tekrarlayan dizgi dekorasyonlarının kutularını bulur.

    Bu korpusta ``get_drawings`` her sayfada aynı koordinatlarda yüzlerce
    görünmez InDesign süsü döndürüyor; bunlar elenmezse hemen her soruya
    sahte bir "şekil" bölgesi eklenir ve şekil kırpma ölçütü anlamsızlaşır.
    Az sayfalı çağrılarda tekrar sayımı güvenilir olmadığı için filtre kapalı
    kalır: o durumda şekil adayları yalnızca boyut/kapsama süzgecinden geçer.
    """
    sayfa_adedi = len(sayfa_gorselleri)
    if sayfa_adedi < 10:
        return set()
    sayac = collections.Counter()
    for kutular in sayfa_gorselleri.values():
        sayac.update({_kutu_anahtari(_normal_kutu(
            (k.x0, k.y0, k.x1, k.y1))) for k in kutular})
    esik = max(5, 0.2 * sayfa_adedi)
    return {anahtar for anahtar, adet in sayac.items() if adet >= esik}


def _kumele(kutular, bosluk=FIGUR_KUME_BOSLUGU):
    """Birbirine değen vektör parçalarını tek şekil kutusunda toplar."""
    kalan = list(kutular)
    kumeler = []
    while kalan:
        aktif = kalan.pop()
        buyudu = True
        while buyudu:
            buyudu = False
            for i in range(len(kalan) - 1, -1, -1):
                if _degiyor(aktif, kalan[i], bosluk):
                    aktif = _birlesim((aktif, kalan.pop(i)))
                    buyudu = True
        kumeler.append(aktif)
    return kumeler


def _figur_kumeleri(gorseller, dekor):
    """Sayfadaki şekil/tablo adaylarını birleşik kutular olarak verir."""
    adaylar = []
    for kutu in gorseller:
        normal = _normal_kutu((kutu.x0, kutu.y0, kutu.x1, kutu.y1))
        if _gorsel_gurultu(normal) or _kutu_anahtari(normal) in dekor:
            continue
        adaylar.append(normal)
    if len(adaylar) > FIGUR_AZAMI_ADAY:
        return []
    return _kumele(adaylar)


def _filigran_kelimesi_mi(x0, y0, x1, y1, page, sutun):
    """Bir kelime kutusu gövde metni değil FİLİGRAN mı?

    ÖSYM kitapçıklarında sayfayı çapraz kesen dev bir "ÖSYM ... Bu dokümanın
    telif hakları..." damgası var. Döndürülmüş olduğu için her glifin bbox'ı
    devasa oluyor; ölçüldü (yks_tyt_2026 s3): tek bir 'Y' harfinin kutusu
    189×189 pt ve merkezi sol sütuna düşüyor. `_govde_kutusu` bunu içerik
    sanıp soru kutusunu 46 pt aşağı uzatıyordu — altın bozuluyor, motor
    haksız yere cezalandırılıyordu (F1@0,75 0,48).

    İki ölçüt: normal bir dizgi satırı sayfa yüksekliğinin %5'ini aşmaz ve
    tek bir kelime sütun genişliğini geçmez."""
    return ((y1 - y0) > page.rect.height * 0.05
            or (x1 - x0) > (sutun["x1"] - sutun["x0"]))


def _metin_satirlari(page):
    """Sayfadaki metin satırlarını kutu + düz metin olarak döndürür."""
    sonuc = []
    for blok in page.get_text("dict")["blocks"]:
        if blok.get("type") != 0:
            continue
        for satir in blok.get("lines", []):
            metin = "".join(
                parca.get("text", "") for parca in satir.get("spans", []))
            # Yalnız sekme/boşluk taşıyan dizgi satırları içerik değildir.
            if not metin.strip():
                continue
            sonuc.append({"box": _normal_kutu(satir["bbox"]), "metin": metin})
    return sonuc


def _sutunda(kutu, sutun):
    orta = (kutu[0] + kutu[2]) / 2
    return sutun["x0"] <= orta <= sutun["x1"]


def _gorsel_kutular(page):
    sonuc = []
    try:
        for bilgi in page.get_image_info():
            kutu = bilgi.get("bbox")
            if kutu:
                sonuc.append(fitz.Rect(kutu))
    except Exception:
        pass
    try:
        for cizim in page.get_drawings():
            kutu = cizim.get("rect")
            if kutu:
                sonuc.append(fitz.Rect(kutu))
    except Exception:
        pass
    return sonuc


def _govde_kutusu(page, capa, sayfa_capalari, gorsel_kutular, profil=None):
    """Çapadan sonraki gerçek içerik sonuna kadar sıkı soru gövdesi kutusu."""
    profil = profil or VARSAYILAN_PROFIL
    sutun = profil.sutunlar[capa["column"]]
    _capa_ust, _capa_alt, govde_alt = profil.y_sinirlari(page)
    ust = max(0.0, capa["word_box"][1] - 4.0)
    sonraki = _sonraki_capa(capa, sayfa_capalari)
    alt_sinir = min(
        govde_alt,
        (sonraki["word_box"][1] - 4.0) if sonraki else govde_alt)
    sonlar = [capa["word_box"][3]]

    for x0, y0, x1, y1, _metin, *_ in page.get_text("words"):
        if _filigran_kelimesi_mi(float(x0), float(y0), float(x1), float(y1),
                                 page, sutun):
            continue
        cx = (float(x0) + float(x1)) / 2
        cy = (float(y0) + float(y1)) / 2
        if (sutun["x0"] <= cx <= sutun["x1"]
                and ust <= cy <= alt_sinir):
            sonlar.append(float(y1))

    # Çoktan seçmeli bu korpusta her şeklin altında seçenek metni bulunuyor;
    # dolayısıyla son metin satırı, şekli de kapsayan doğru alt sınırdır.
    # PDF'nin görünmeyen InDesign dekorasyonları ``get_drawings`` içinde
    # soru içeriği gibi dönebildiği için görseller yalnızca metinsiz bir
    # soruda yedek sınır olarak kullanılabilir.
    if len(sonlar) == 1:
        for kutu in gorsel_kutular:
            cx = (kutu.x0 + kutu.x1) / 2
            cy = (kutu.y0 + kutu.y1) / 2
            if (_gorsel_gurultu((kutu.x0, kutu.y0, kutu.x1, kutu.y1))
                    or not sutun["x0"] <= cx <= sutun["x1"]
                    or not ust <= cy <= alt_sinir):
                continue
            sonlar.append(float(min(kutu.y1, alt_sinir)))

    alt = min(alt_sinir, max(max(sonlar) + 4.0, capa["word_box"][3] + 8.0))
    return [
        round(sutun["x0"], 3), round(ust, 3),
        round(sutun["x1"], 3), round(alt, 3),
    ]


def _onceki_capa(capa, sayfa_capalari):
    ayni = sorted(
        (a for a in sayfa_capalari
         if a["column"] == capa["column"]
         and a["word_box"][1] < capa["word_box"][1] - 1.0),
        key=lambda a: a["word_box"][1])
    return ayni[-1] if ayni else None


def _capa_ilk_satiri(satirlar, capa, sutun):
    """Çapanın kendi ilk metin satırının (numara + gövde) birleşik kutusu."""
    ust = capa["word_box"][1]
    bant = [
        s["box"] for s in satirlar
        if _sutunda(s["box"], sutun)
        and ust - 2.0 <= s["box"][1] <= ust + SATIR_BANDI
    ]
    return _birlesim(bant) if bant else None


def _onceki_son_satir(satirlar, onceki, tavan, sutun):
    """Önceki sorunun, bu sorunun hemen üstünde biten son metin satırı."""
    adaylar = [
        s["box"] for s in satirlar
        if _sutunda(s["box"], sutun)
        and s["box"][1] >= onceki["word_box"][1] - 2.0
        and s["box"][3] <= tavan
    ]
    if not adaylar:
        return None
    dip = max(kutu[3] for kutu in adaylar)
    return _birlesim([k for k in adaylar if k[3] >= dip - SATIR_BANDI])


def _bolgeleri_uret(sayfa_no, capa, govde, satirlar, sayfa_capalari,
                    figur_kumeleri, kesim_kutulari=None, profil=None):
    """Bir soru için kesim kalitesini ölçen gerekli/yasak bölgeleri üretir.

    Kutu IoU'su, kesimin hangi *içeriği* kaçırdığını söylemez: alt kenardan
    traşlanan şık bloğu ya da kırpılan şekil, IoU'da birkaç puanlık kayıp
    olarak görünüp gözden kaçar. Gerekli bölgeler "bu alan kesimin içinde
    tamamen kalmalı", yasak bölgeler "bu alan kesime asla girmemeli"
    diyerek aynı hatayı ikili ve yorumlanabilir biçimde ölçer.

    Üretilen her gerekli bölge altın gövdenin içine kırpılır, her yasak bölge
    sorunun bu sayfadaki *tüm* parçalarıyla (ortak uyaran dâhil) kesişiyorsa
    atılır; böylece altın kesimin kendisi her zaman tam puan alır ve bölgeler
    kutuyla çelişmez.
    """
    profil = profil or VARSAYILAN_PROFIL
    kesim_kutulari = list(kesim_kutulari or (govde,))
    sutun = profil.sutunlar[capa["column"]]
    icerik = [
        s for s in satirlar
        if _sutunda(s["box"], sutun)
        and govde[1] <= (s["box"][1] + s["box"][3]) / 2 <= govde[3]
    ]
    gerekli = []
    yasak = []

    # 1) İlk metin satırı: üst kenarın soru numarasının altından başlamasını
    # (baş traşlaması) doğrudan yakalar.
    if icerik:
        ust = min(s["box"][1] for s in icerik)
        bant = [s["box"] for s in icerik if s["box"][1] <= ust + SATIR_BANDI]
        gerekli.append(("metin", _birlesim(bant)))

    # 2) Şık bloğu: ilk şık işaretinden gövde sonuna kadar. Alt kenar
    # traşlandığında en sık kaybedilen içerik budur.
    isaretli = []
    harfler = set()
    for satir in icerik:
        bulunan = SECENEK_DESENI.findall(satir["metin"])
        if bulunan:
            isaretli.append(satir)
            harfler.update(bulunan)
    if "A" in harfler and len(harfler) >= 3:
        bas = min(s["box"][1] for s in isaretli)
        blok = [s["box"] for s in icerik if s["box"][1] >= bas - 1.0]
        gerekli.append(("secenek", _birlesim(blok)))

    # 3) Şekil/tablo: gövdeye düşen vektör kümeleri.
    for kume in figur_kumeleri:
        if (kume[2] - kume[0] < FIGUR_ASGARI_KENAR
                or kume[3] - kume[1] < FIGUR_ASGARI_KENAR):
            continue
        kirpik = _kesisim(kume, govde)
        # Kümenin ezici çoğunluğu gövde dışındaysa şekil bu soruya ait
        # değildir; komşunun şeklini bu soruya zorunlu kılmayız.
        if (kirpik is None
                or _alan(kirpik) < FIGUR_ASGARI_KAPSAMA * _alan(kume)):
            continue
        gerekli.append(("sekil", kirpik))

    # 4) Komşu soru satırları: aşağıdan ve yukarıdan sızmayı ölçer. Yan
    # sütunun satırları eklenmez; gövde zaten sütun bandına kısıtlı olduğu
    # için oraya taşma olmuyor, eklenirse ölçüm gürültüye boğulur.
    sonraki = _sonraki_capa(capa, sayfa_capalari)
    if sonraki is not None:
        kutu = _capa_ilk_satiri(satirlar, sonraki, sutun)
        if kutu is not None:
            yasak.append(("komsu_soru", (
                kutu[0], kutu[1] + BOLGE_KOMSU_PAYI, kutu[2], kutu[3])))
    onceki = _onceki_capa(capa, sayfa_capalari)
    if onceki is not None:
        kutu = _onceki_son_satir(satirlar, onceki, govde[1], sutun)
        if kutu is not None:
            yasak.append(("komsu_soru", (
                kutu[0], kutu[1], kutu[2], kutu[3] - BOLGE_KOMSU_PAYI)))

    # Gerekli bölge gövdenin dışına taşarsa kusursuz bir kesim bile onu
    # kapsayamaz; satır kutularının yarım puntoluk taşmaları kırpılır.
    gerekli_kirpik = [
        (tur, _kesisim(kutu, govde)) for tur, kutu in gerekli
    ]
    return (
        [_bolge_nesnesi(sayfa_no, tur, kutu)
         for tur, kutu in gerekli_kirpik if kutu is not None],
        [_bolge_nesnesi(sayfa_no, tur, kutu) for tur, kutu in yasak
         if _alan(kutu) > 0.0
         and all(_kesisim(kutu, k) is None for k in kesim_kutulari)],
    )


def _bolge_nesnesi(sayfa_no, tur, kutu):
    return {
        "page": sayfa_no,
        "box": [round(float(deger), 3) for deger in kutu],
        "kind": tur,
    }


def _sayfa_rolu(page, profil=None, bolum_var=None):
    profil = profil or VARSAYILAN_PROFIL
    metin = _ascii(" ".join(page.get_text("text").split()))
    if _cevap_anahtari_sayfasi(metin, profil):
        return "cevap_anahtari"
    if (_konu_ve_deneme(page, profil) if bolum_var is None else bolum_var):
        return "soru"
    if "icindekiler" in metin:
        return "icindekiler"
    if not metin.strip():
        return "kapak"
    if "adayın dikkatine" in metin or "adayin dikkatine" in metin \
            or "aciklama" in metin:
        return "konu"
    return "kapak"


def _soru_kimligi(deneme, konu, numara):
    """Bölüm kipinden bağımsız, çakışmayan soru kimliği."""
    if konu:
        return f"d{deneme}-{konu}-q{numara}"
    return f"b{deneme}-q{numara}"


def _uyaran_kimligi(deneme, konu, bas, son, sayfa_no):
    onek = f"d{deneme}-{konu}" if konu else f"b{deneme}"
    return f"{onek}-stim-{bas}-{son}-p{sayfa_no}"


def _ortak_uyaranlari_bul(doc, sayfalar, secilen_haritasi, profil=None,
                          sayfa_bolumleri=None):
    """Ortak paragraf/yönerge kutularını ve soru bağlarını üretir."""
    profil = profil or VARSAYILAN_PROFIL
    uyaranlar = collections.defaultdict(list)
    soru_uyarani = {}
    if profil.aralik_deseni is None:
        return uyaranlar, soru_uyarani
    for sayfa_no in sayfalar:
        page = doc[sayfa_no - 1]
        bolum = (_konu_ve_deneme(page, profil) if sayfa_bolumleri is None
                 else sayfa_bolumleri.get(sayfa_no))
        if bolum is None:
            continue
        deneme, konu = bolum
        secili = [
            c for (d, k, _n), c in secilen_haritasi.items()
            if d == deneme and k == konu
        ]
        for blok in page.get_text("blocks"):
            x0, y0, x1, y1, metin, *_ = blok
            eslesme = profil.aralik_deseni.search(_ascii(metin))
            if eslesme is None:
                continue
            bas, son = (int(eslesme.group(1)), int(eslesme.group(2)))
            sutun_no = 0 if (x0 + x1) / 2 < page.rect.width / 2 else 1
            sutun = profil.sutunlar[sutun_no]
            kimlik = _uyaran_kimligi(deneme, konu, bas, son, sayfa_no)
            if "asagidaki parcaya gore" in _ascii(metin):
                ayni_sayfa = sorted(
                    (c for c in secili
                     if c["page"] == sayfa_no
                     and c["column"] == sutun_no
                     and bas <= c["numara"] <= son
                     and c["word_box"][1] > y1),
                    key=lambda c: c["word_box"][1])
                alt = (ayni_sayfa[0]["word_box"][1] - 4.0
                       if ayni_sayfa else y1 + 4.0)
                kutu = [
                    sutun["x0"], max(0.0, y0 - 4.0),
                    sutun["x1"], min(float(page.rect.height), alt),
                ]
            else:
                kutu = [
                    max(sutun["x0"], x0 - 4.0), max(0.0, y0 - 4.0),
                    min(sutun["x1"], x1 + 4.0),
                    min(float(page.rect.height), y1 + 4.0),
                ]
            soru_kimlikleri = []
            for numara in range(bas, son + 1):
                anahtar = (deneme, konu, numara)
                if anahtar not in secilen_haritasi:
                    continue
                soru_id = _soru_kimligi(deneme, konu, numara)
                soru_kimlikleri.append(soru_id)
                soru_uyarani[anahtar] = kimlik
            if soru_kimlikleri:
                uyaranlar[sayfa_no].append({
                    "id": kimlik,
                    "box": [round(float(v), 3) for v in kutu],
                    "question_ids": soru_kimlikleri,
                })
    return uyaranlar, soru_uyarani


def altin_uret(pdf_yolu, *, dataset_id, split, denemeler, sayfalar,
               profil=None, serbest=False, rapor=None):
    profil = profil or VARSAYILAN_PROFIL
    rapor = {} if rapor is None else rapor
    doc = fitz.open(pdf_yolu)
    try:
        if profil.sutunlar is None:
            profil = profil.sutunlarla(
                _capalari_turet(doc, sayfalar, profil))
        fiziksel = []
        sayfa_fiziksel = collections.defaultdict(list)
        sayfa_bolumleri = {}
        for sayfa_no in sayfalar:
            page = doc[sayfa_no - 1]
            if profil.bolum_kipi == "konu":
                bolum = _konu_ve_deneme(page, profil)
                if bolum is None or bolum[0] not in denemeler:
                    continue
            else:
                # Zincir kipinde bölüm henüz bilinmiyor; çapalar toplandıktan
                # sonra numara dizisinden türetilir.
                if _sayfa_atlanir(page, profil):
                    continue
                bolum = (0, "")
            bulunan = _fiziksel_capalar(page, sayfa_no, bolum, profil)
            fiziksel.extend(bulunan)
            sayfa_fiziksel[sayfa_no].extend(bulunan)

        if profil.bolum_kipi != "konu":
            _bolumlere_ayir(fiziksel)

        secilen, yinelenen = _capalari_sec(
            fiziksel, denemeler, profil, serbest=serbest, rapor=rapor)
        secilen_haritasi = {
            (c["deneme"], c["konu"], c["numara"]): c for c in secilen
        }
        for capa in secilen:
            sayfa_bolumleri.setdefault(
                capa["page"], (capa["deneme"], capa["konu"]))
        uyaranlar, soru_uyarani = _ortak_uyaranlari_bul(
            doc, sayfalar, secilen_haritasi, profil,
            None if profil.bolum_kipi == "konu" else sayfa_bolumleri)
        uyaran_haritasi = {
            uyaran["id"]: (sayfa_no, uyaran["box"])
            for sayfa_no, sayfa_uyaranlari in uyaranlar.items()
            for uyaran in sayfa_uyaranlari
        }

        # Dekorasyon süzgeci belge geneli bir istatistik olduğu için görseller
        # önce toplanır; ``_govde_kutusu`` yine süzülmemiş listeyi alır ki
        # kutu koordinatları bölge eklemesinden etkilenmesin.
        sayfa_gorselleri = {
            sayfa_no: _gorsel_kutular(doc[sayfa_no - 1])
            for sayfa_no in sayfalar
        }
        dekor = _dekor_kutulari(sayfa_gorselleri)

        soru_sayfalari = collections.defaultdict(list)
        ignore = collections.defaultdict(list)
        for sayfa_no in sayfalar:
            page = doc[sayfa_no - 1]
            gorseller = sayfa_gorselleri[sayfa_no]
            fiziksel_sayfa = sayfa_fiziksel.get(sayfa_no, [])
            satirlar = figurler = None
            for capa in (c for c in secilen if c["page"] == sayfa_no):
                govde = _govde_kutusu(
                    page, capa, fiziksel_sayfa, gorseller, profil)
                if satirlar is None:
                    satirlar = _metin_satirlari(page)
                    figurler = _figur_kumeleri(gorseller, dekor)
                anahtar = (capa["deneme"], capa["konu"], capa["numara"])
                soru = {
                    "id": _soru_kimligi(*anahtar),
                    "number": capa["numara"],
                    "box": govde,
                    "type": "coktan_secmeli",
                    "final_output": {
                        "question_number": capa["numara"],
                        "part_count": 1,
                    },
                }
                if anahtar in soru_uyarani:
                    uyaran_id = soru_uyarani[anahtar]
                    uyaran_sayfasi, uyaran_kutusu = uyaran_haritasi[uyaran_id]
                    soru.pop("box")
                    soru["parts"] = [
                        {
                            "page": uyaran_sayfasi,
                            "box": uyaran_kutusu,
                            "kind": "ortak_uyaran",
                        },
                        {
                            "page": sayfa_no,
                            "box": govde,
                            "kind": "soru_govdesi",
                        },
                    ]
                    soru["shared_stimulus_id"] = uyaran_id
                    soru["final_output"]["part_count"] = 2
                kesim_kutulari = [
                    parca["box"] for parca in soru.get("parts", ())
                    if parca["page"] == sayfa_no
                ] or [govde]
                gerekli, yasak = _bolgeleri_uret(
                    sayfa_no, capa, govde, satirlar, fiziksel_sayfa, figurler,
                    kesim_kutulari, profil)
                if gerekli:
                    soru["required_regions"] = gerekli
                if yasak:
                    soru["forbidden_regions"] = yasak
                soru_sayfalari[sayfa_no].append(soru)
            for capa in (c for c in yinelenen if c["page"] == sayfa_no):
                ignore[sayfa_no].append(_govde_kutusu(
                    page, capa, fiziksel_sayfa, gorseller, profil))

        sayfa_nesneleri = []
        for sayfa_no in sayfalar:
            page = doc[sayfa_no - 1]

            def _sirala(soru):
                kutu = soru.get("box")
                if kutu is None:
                    kutu = next(
                        parca["box"] for parca in reversed(soru["parts"])
                        if parca["page"] == sayfa_no)
                return kutu[0] >= page.rect.width / 2, kutu[1]

            sayfa_sorulari = sorted(
                soru_sayfalari.get(sayfa_no, []),
                key=_sirala)
            rol = _sayfa_rolu(
                page, profil,
                None if profil.bolum_kipi == "konu"
                else bool(sayfa_sorulari))
            # Deneme kapaklarında konu adları ve "N. DENEME" birlikte
            # geçebilir; fiziksel soru çapası yoksa bunlar soru sayfası değil.
            if rol == "soru" and not sayfa_sorulari:
                rol = "konu"
            nesne = {
                "page": sayfa_no,
                "width": round(float(page.rect.width), 3),
                "height": round(float(page.rect.height), 3),
                "role": rol,
                "questions": sayfa_sorulari,
            }
            if uyaranlar.get(sayfa_no):
                nesne["shared_stimuli"] = uyaranlar[sayfa_no]
            if ignore.get(sayfa_no):
                nesne["ignore_regions"] = ignore[sayfa_no]
            sayfa_nesneleri.append(nesne)

        kaynak_hash = _sha256(pdf_yolu)
        soru_adedi = sum(len(s["questions"]) for s in sayfa_nesneleri)
        altin = {
            "schema_version": SEMA_SURUMU,
            "dataset": {
                "id": dataset_id,
                "kind": "annotated",
                "description": (
                    "PDF metin/geometri katmanından bağımsız çıkarılmış, "
                    f"{datetime.date.today().isoformat()} tarihinde görsel "
                    "denetim için temas sayfaları üretilmiş TYT altın verisi"
                ),
                "split": split,
            },
            "documents": [{
                "id": f"sha256:{kaynak_hash}",
                "source": os.path.basename(pdf_yolu),
                "source_sha256": kaynak_hash,
                "final_output": {
                    "question_count": soru_adedi,
                    "png_count": soru_adedi,
                    "metadata_count": soru_adedi,
                },
                "pages": sayfa_nesneleri,
            }],
        }
        deneme_konu = collections.Counter(
            (c["deneme"], c["konu"]) for c in secilen)
        bolge_sayaci = collections.Counter(
            (alan, bolge["kind"])
            for sayfa in sayfa_nesneleri
            for soru in sayfa["questions"]
            for alan in ("required_regions", "forbidden_regions")
            for bolge in soru.get(alan, [])
        )
        denetim = {
            "schema_version": "soru-kesici.golden-audit/v1",
            "dataset": dataset_id,
            "source_sha256": kaynak_hash,
            "page_count": len(sayfa_nesneleri),
            "question_count": soru_adedi,
            "shared_stimulus_count": sum(
                len(v) for v in uyaranlar.values()),
            "ignored_duplicate_count": len(yinelenen),
            "region_counts": {
                f"{alan}.{tur}": adet
                for (alan, tur), adet in sorted(bolge_sayaci.items())
            },
            "counts": (
                {
                    f"d{d}-{k}": deneme_konu[(d, k)]
                    for d in denemeler for k, _b, _a in profil.konular
                }
                if profil.bolum_kipi == "konu" else
                {
                    f"b{d}": adet
                    for (d, _k), adet in sorted(deneme_konu.items())
                }
            ),
            "profile": profil.ad,
            "free_mode": bool(serbest),
            "duplicate_locations": [
                {
                    "deneme": c["deneme"], "konu": c["konu"],
                    "number": c["numara"], "page": c["page"],
                }
                for c in yinelenen
            ],
        }
        if serbest or profil.bolum_kipi != "konu":
            denetim["chain"] = rapor.get("zincir", [])
            denetim["unresolved_duplicates"] = rapor.get("cozulmeyen", [])
        return altin, denetim
    finally:
        doc.close()


def _renkli_onizleme(pdf_yolu, altin, hedef, *, sutun_sayisi=4):
    """Tüm sayfaları kapsayan kutulu temas sayfaları üretir."""
    from PIL import Image, ImageDraw, ImageFont

    os.makedirs(hedef, exist_ok=True)
    doc = fitz.open(pdf_yolu)
    try:
        sayfalar = altin["documents"][0]["pages"]
        kucuk_w, kucuk_h = 280, 395
        satir_sayisi = 3
        kenar = 18
        hucre_w, hucre_h = kucuk_w + kenar * 2, kucuk_h + 42
        sayfa_basina = sutun_sayisi * satir_sayisi
        font = ImageFont.load_default()
        yollar = []
        for bas in range(0, len(sayfalar), sayfa_basina):
            grup = sayfalar[bas:bas + sayfa_basina]
            temas = Image.new(
                "RGB", (hucre_w * sutun_sayisi,
                        hucre_h * satir_sayisi), "white")
            ciz = ImageDraw.Draw(temas)
            for i, bilgi in enumerate(grup):
                page = doc[bilgi["page"] - 1]
                olcek = kucuk_w / page.rect.width
                pix = page.get_pixmap(
                    matrix=fitz.Matrix(olcek, olcek), alpha=False)
                goruntu = Image.frombytes(
                    "RGB", (pix.width, pix.height), pix.samples)
                goruntu.thumbnail((kucuk_w, kucuk_h))
                gciz = ImageDraw.Draw(goruntu)

                def kutu_ciz(kutu, renk, etiket):
                    oran_x = goruntu.width / page.rect.width
                    oran_y = goruntu.height / page.rect.height
                    xy = [
                        kutu[0] * oran_x, kutu[1] * oran_y,
                        kutu[2] * oran_x, kutu[3] * oran_y,
                    ]
                    gciz.rectangle(xy, outline=renk, width=2)
                    gciz.text(
                        (xy[0] + 2, xy[1] + 1), etiket,
                        fill=renk, font=font, stroke_width=1,
                        stroke_fill="white")

                for soru in bilgi["questions"]:
                    parcalar = soru.get("parts")
                    if parcalar:
                        for parca in parcalar:
                            if parca["page"] != bilgi["page"]:
                                continue
                            renk = (
                                "#0068d9"
                                if parca.get("kind") == "ortak_uyaran"
                                else "#00a040"
                            )
                            etiket = (
                                "U"
                                if parca.get("kind") == "ortak_uyaran"
                                else str(soru["number"])
                            )
                            kutu_ciz(parca["box"], renk, etiket)
                    else:
                        kutu_ciz(
                            soru["box"], "#00a040", str(soru["number"]))
                    # Bölgeler kesim kalitesinin asıl ölçüsü; insan denetimi
                    # kutuyla birlikte bunları da görebilmeli.
                    for bolge in soru.get("required_regions", []):
                        if bolge["page"] == bilgi["page"]:
                            kutu_ciz(bolge["box"], "#e08000", "")
                    for bolge in soru.get("forbidden_regions", []):
                        if bolge["page"] == bilgi["page"]:
                            kutu_ciz(bolge["box"], "#a000c0", "X")
                for uyaran in bilgi.get("shared_stimuli", []):
                    kutu_ciz(uyaran["box"], "#0068d9", "U")
                for kutu in bilgi.get("ignore_regions", []):
                    kutu_ciz(kutu, "#d02030", "IGNORE")

                x = (i % sutun_sayisi) * hucre_w + kenar
                y = (i // sutun_sayisi) * hucre_h + 28
                temas.paste(goruntu, (x, y))
                ciz.text(
                    (x, 7 + (i // sutun_sayisi) * hucre_h),
                    (f"s.{bilgi['page']} rol={bilgi['role']} "
                     f"soru={len(bilgi['questions'])}"),
                    fill="black", font=font)
            yol = os.path.join(
                hedef, f"temas_{bas // sayfa_basina + 1:03d}.png")
            temas.save(yol, optimize=True)
            yollar.append(yol)
        return yollar
    finally:
        doc.close()


def _kutu_denetle(kutu, yol, genislik, yukseklik):
    if not isinstance(kutu, list) or len(kutu) != 4:
        raise ValueError(f"{yol}: dört elemanlı kutu bekleniyor")
    x0, y0, x1, y1 = kutu
    if not (0 <= x0 < x1 <= genislik and 0 <= y0 < y1 <= yukseklik):
        raise ValueError(f"{yol}: sayfa sınırları dışında ya da boş: {kutu}")


def _ciktiyi_denetle(altin):
    """Üretilen altın belgesinin şema ve geometri tutarlılığını doğrular.

    Ölçüm modülü ``dogrula`` burada bilerek çağrılmaz: o modül motoru
    (``soru_kes``) import ediyor. Üretici motora bağlanırsa altın veri
    sözde etikete dönüşür ve ölçüm motorun kendi hatasına kör kalır. Bu
    yüzden garanti bağımsız olarak burada verilir; ``dogrula`` şeması ise
    ölçüm anında dosyayı yüklerken zaten uygulanıyor.
    """
    if altin.get("schema_version") != SEMA_SURUMU:
        raise ValueError("schema_version beklenen sürümde değil")
    for belge in altin["documents"]:
        kimlikler = set()
        uyaran_kimlikleri = {
            uyaran["id"] for sayfa in belge["pages"]
            for uyaran in sayfa.get("shared_stimuli", [])
        }
        # Parça başka sayfada olabilir ve o sayfanın boyutu farklı olabilir;
        # kutuyu bulunduğu sayfanın değil, ait olduğu sayfanın sınırlarıyla
        # denetlemek gerekir.
        sayfa_boyutlari = {
            sayfa["page"]: (sayfa["width"], sayfa["height"])
            for sayfa in belge["pages"]
        }
        for sayfa in belge["pages"]:
            genislik, yukseklik = sayfa["width"], sayfa["height"]
            kok = f"sayfa {sayfa['page']}"
            for kutu in sayfa.get("ignore_regions", []):
                _kutu_denetle(kutu, f"{kok}.ignore_regions", genislik,
                              yukseklik)
            for uyaran in sayfa.get("shared_stimuli", []):
                _kutu_denetle(uyaran["box"], f"{kok}.{uyaran['id']}",
                              genislik, yukseklik)
            for soru in sayfa["questions"]:
                yol = f"{kok}.{soru['id']}"
                if soru["id"] in kimlikler:
                    raise ValueError(f"Yinelenen soru kimliği: {soru['id']}")
                kimlikler.add(soru["id"])
                parcalar = soru.get("parts") or [
                    {"page": sayfa["page"], "box": soru["box"]}]
                for parca in parcalar:
                    parca_sayfa = parca.get("page", sayfa["page"])
                    if parca_sayfa not in sayfa_boyutlari:
                        raise ValueError(
                            f"{yol}.parts: belgede olmayan sayfa "
                            f"{parca_sayfa}")
                    parca_gen, parca_yuk = sayfa_boyutlari[parca_sayfa]
                    _kutu_denetle(parca["box"], f"{yol}.parts", parca_gen,
                                  parca_yuk)
                uyaran_id = soru.get("shared_stimulus_id")
                if (uyaran_id is not None
                        and uyaran_id not in uyaran_kimlikleri):
                    raise ValueError(f"{yol}: ortak uyaran bulunamadı")
                kendi = [p["box"] for p in parcalar
                         if p.get("page", sayfa["page"]) == sayfa["page"]]
                _bolgeleri_denetle(soru, yol, kendi, sayfa)


def _bolgeleri_denetle(soru, yol, kendi_kutular, sayfa):
    """Gerekli bölge gövdenin içinde, yasak bölge dışında olmalı."""
    for alan, turler in (("required_regions", GEREKLI_BOLGE_TURLERI),
                         ("forbidden_regions", YASAK_BOLGE_TURLERI)):
        for bolge in soru.get(alan, []):
            _kutu_denetle(bolge["box"], f"{yol}.{alan}",
                          sayfa["width"], sayfa["height"])
            if bolge["kind"] not in turler:
                raise ValueError(f"{yol}.{alan}: geçersiz tür {bolge['kind']}")
            if bolge.get("page") != sayfa["page"]:
                raise ValueError(f"{yol}.{alan}: sayfa numarası tutarsız")
            ortusme = _birlesim_alani(
                [_kesisim(bolge["box"], kutu) or (0.0, 0.0, 0.0, 0.0)
                 for kutu in kendi_kutular])
            if alan == "required_regions":
                if ortusme < _alan(bolge["box"]) - 1e-6:
                    raise ValueError(
                        f"{yol}.{alan}: gerekli bölge gövdenin dışına taşıyor")
            elif ortusme > 0.0:
                raise ValueError(
                    f"{yol}.{alan}: yasak bölge gövdeyle kesişiyor")


def _yaz_json(veri, yol):
    os.makedirs(os.path.dirname(os.path.abspath(yol)), exist_ok=True)
    with open(yol, "w", encoding="utf-8") as hedef:
        json.dump(veri, hedef, ensure_ascii=False, indent=1)
        hedef.write("\n")


def _serbest_ozeti(denetim):
    """Serbest kipte zincirin nerede tutmadığını ``stderr``e yazar."""
    satirlar = []
    for bilgi in denetim.get("chain", []):
        if not bilgi["eksik"] and not bilgi["birden_baslamiyor"]:
            continue
        neden = []
        if bilgi["birden_baslamiyor"]:
            neden.append(f"zincir {bilgi['ilk']} ile başlıyor")
        if bilgi["eksik"]:
            # Seyrek sayfa örneklemesinde boşluk beklenen bir şey; tam liste
            # denetim JSON'unda duruyor, burada okunabilirlik önemli.
            gosterilen = bilgi["eksik"][:8]
            kuyruk = ("…" if len(bilgi["eksik"]) > len(gosterilen) else "")
            neden.append(
                f"eksik {len(bilgi['eksik'])} numara {gosterilen}{kuyruk}")
        satirlar.append(
            f"  bölüm b{bilgi['bolum']} (s.{bilgi['sayfalar'][0]}-"
            f"{bilgi['sayfalar'][1]}, {bilgi['adet']} soru): "
            + "; ".join(neden))
    for bilgi in denetim.get("unresolved_duplicates", []):
        satirlar.append(
            f"  bölüm b{bilgi['bolum']} soru {bilgi['numara']}: "
            f"çözülemeyen tekrar {bilgi['konumlar']} — ilki alındı, "
            "kalanı ignore_regions")
    if satirlar:
        print("serbest kip — adet dayatılmadı, zincirde sapma var:",
              file=sys.stderr)
        for satir in satirlar:
            print(satir, file=sys.stderr)
    else:
        print("serbest kip — zincir kusursuz, sapma yok", file=sys.stderr)


def main(argv=None):
    p = argparse.ArgumentParser(
        description="Metin katmanlı sınav PDF'sinden golden-v2 üret")
    p.add_argument("pdf")
    p.add_argument("--cikti", required=True)
    p.add_argument("--dataset", required=True)
    p.add_argument(
        "--split", choices=("calibration", "holdout"), required=True)
    p.add_argument("--denemeler", default="1-8")
    p.add_argument("--sayfalar")
    p.add_argument("--onizleme")
    p.add_argument(
        "--profil",
        help=("kalite/altin_profil/profiller.json içindeki profil adı; "
              "verilmezse gömülü MEBİ TYT denemesi profili kullanılır"))
    p.add_argument(
        "--serbest", action="store_true",
        help=("beklenen soru adedini dayatma; zinciri doğrula, sapmayı "
              "stderr'e özetle"))
    args = p.parse_args(argv)

    profil = profil_coz(args.profil)
    with fitz.open(args.pdf) as doc:
        sayfa_adedi = doc.page_count
    denemeler = _aralik(
        args.denemeler, alt=1, ust=8, ad="denemeler")
    sayfalar = _aralik(
        args.sayfalar, alt=1, ust=sayfa_adedi, ad="sayfalar")

    altin, denetim = altin_uret(
        args.pdf, dataset_id=args.dataset, split=args.split,
        denemeler=denemeler, sayfalar=sayfalar, profil=profil,
        serbest=args.serbest)

    if "chain" in denetim:
        _serbest_ozeti(denetim)
    _ciktiyi_denetle(altin)
    _yaz_json(altin, args.cikti)
    denetim_yolu = os.path.splitext(args.cikti)[0] + ".audit.json"
    _yaz_json(denetim, denetim_yolu)

    print(f"altın: {args.cikti}")
    print(f"profil: {profil.ad}{' (serbest)' if args.serbest else ''}")
    print(f"denetim: {denetim_yolu}")
    print(f"soru: {denetim['question_count']}")
    print(f"ortak uyaran: {denetim['shared_stimulus_count']}")
    print(f"yok sayılan yinelenen baskı: "
          f"{denetim['ignored_duplicate_count']}")
    for ad, adet in denetim["region_counts"].items():
        print(f"bölge {ad}: {adet}")
    if args.onizleme:
        yollar = _renkli_onizleme(
            args.pdf, altin, args.onizleme)
        print(f"temas sayfası: {len(yollar)} -> {args.onizleme}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
