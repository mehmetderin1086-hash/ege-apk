"""Biyoloji/tıp Türkçe korpusu — sentetik el yazısı satırlarının kaynağı.

Sınavlarda gerçekten geçecek terminolojiyi (hücre biyolojisi, anatomi,
fizyoloji, genetik, mikrobiyoloji...) içerir. Satır üretici bu terimlerden ve
şablon cümlelerden agglutinatif çekimlere uygun kısa cevap benzeri diziler
kurar. Öğretmen kendi terim listesini ``ek_terimler`` ile genişletebilir.
"""

from __future__ import annotations

import random

BIYOLOJI_TERIMLERI = [
    "hücre", "hücre zarı", "sitoplazma", "çekirdek", "mitokondri", "ribozom",
    "endoplazmik retikulum", "golgi cisimciği", "lizozom", "kloroplast",
    "vakuol", "sentrozom", "hücre duvarı", "kromozom", "gen", "DNA", "RNA",
    "nükleotit", "protein sentezi", "enzim", "ATP", "fotosentez", "solunum",
    "difüzyon", "osmoz", "aktif taşıma", "pasif taşıma", "mitoz", "mayoz",
    "homeostazi", "metabolizma", "anabolizma", "katabolizma", "glikoz",
    "nişasta", "selüloz", "lipit", "karbonhidrat", "aminoasit", "hormon",
    "fotosentez hızı", "klorofil", "stoma", "ksilem", "floem", "terleme",
    "ekosistem", "besin zinciri", "üretici", "tüketici", "ayrıştırıcı",
    "biyoçeşitlilik", "adaptasyon", "doğal seçilim", "evrim", "kalıtım",
    "baskın gen", "çekinik gen", "genotip", "fenotip", "alel",
]

TIP_TERIMLERI = [
    "epitel doku", "bağ doku", "kas doku", "sinir doku", "nöron", "akson",
    "dendrit", "sinaps", "refleks", "merkezi sinir sistemi", "beyin",
    "omurilik", "serebrum", "serebellum", "kalp", "atardamar", "toplardamar",
    "kılcal damar", "kan basıncı", "alyuvar", "akyuvar", "trombosit",
    "hemoglobin", "bağışıklık", "antikor", "antijen", "lenfosit", "aşı",
    "akciğer", "alveol", "soluk borusu", "diyafram", "böbrek", "nefron",
    "üre", "idrar", "karaciğer", "safra", "pankreas", "insülin", "mide",
    "ince bağırsak", "kalın bağırsak", "villus", "peristaltik hareket",
    "sindirim enzimi", "hipofiz", "tiroit", "adrenalin", "metabolizma hızı",
    "kemik", "kıkırdak", "eklem", "iskelet kası", "tendon",
]

# Kısa cevap/boşluk doldurma benzeri şablonlar ("{terim}" doldurulur)
SABLON_CUMLELER = [
    "{terim}",
    "{terim} olarak adlandırılır",
    "Bu yapı {terim} adını alır",
    "Cevap: {terim}",
    "{terim} görevini yapar",
    "{terim} sayesinde gerçekleşir",
    "Buna {terim} denir",
    "{terim} ve {terim2}",
    "{terim}, {terim2} ile ilişkilidir",
    "hücrede {terim} bulunur",
    "{terim} ile {terim2} arasındaki fark önemlidir",
    "{terim2} olmadan {terim} gerçekleşemez",
    "öğrenci {terim} yerine {terim2} yazmıştır",
    "{terim} yapısı {terim2} tarafından denetlenir",
    "{terim}, {terim2} ve {terim3} birlikte çalışır",
    "kısaca {terim} diyebiliriz",
    "{terim} miktarı artarsa {terim2} azalır",
    "sınavda {terim} sorulmuştu",
    "{terim} bir {terim2} çeşididir",
    "{terim2} içinde {terim} yer alır",
    "bence doğru cevap {terim} olmalı",
    "{terim} konusunu tekrar etmeliyim",
    "{terim} olayı {terim2} ile başlar",
    "hem {terim} hem {terim2} gereklidir",
    "{terim} eksikliğinde {terim2} bozulur",
]

# Ölçü/sayı içeren kalıplar: rakam ve noktalama görsel çeşitliliği için şart.
SAYISAL_KALIPLAR = [
    "{sayi} adet {terim}",
    "{terim} oranı %{sayi}",
    "{sayi}. soruda {terim} isteniyor",
    "yaklaşık {sayi} {terim} sayıldı",
    "{terim} için {sayi} puan verildi",
    "{sayi},{kesir} birim {terim}",
]


def terimler(ek_terimler: list[str] | None = None) -> list[str]:
    tum = BIYOLOJI_TERIMLERI + TIP_TERIMLERI
    if ek_terimler:
        tum = tum + list(ek_terimler)
    return tum


def satir_uret(rng: random.Random, terim_havuzu: list[str]) -> str:
    """Tek bir sentetik cevap satırı üretir.

    Satırların bir kısmı bilinçli olarak dilbilgisiz terim dizisidir: yalnız
    akıcı şablonlarla eğitilen bir kodçözücü, görüntüyü okumak yerine cümleyi
    ezberleyip tamamlamayı öğrenir (dil modeli kısayolu). Karışık diziler bu
    kısayolu kapatıp modeli gerçekten görüntüye bakmaya zorlar.
    """
    secim = rng.random()
    if secim < 0.15:
        # dilbilgisiz terim dizisi — tahmin edilemez, görsel okumayı zorlar
        adet = rng.randint(2, 5)
        return " ".join(rng.choice(terim_havuzu) for _ in range(adet))
    if secim < 0.30:
        kalip = rng.choice(SAYISAL_KALIPLAR)
        metin = kalip.replace("{sayi}", str(rng.randint(1, 999)))
        metin = metin.replace("{kesir}", str(rng.randint(0, 99)))
    else:
        metin = rng.choice(SABLON_CUMLELER)
    for yer in ("{terim}", "{terim2}", "{terim3}"):
        while yer in metin:
            metin = metin.replace(yer, rng.choice(terim_havuzu), 1)
    return metin


def korpus_uret(
    adet: int,
    tohum: int = 0,
    ek_terimler: list[str] | None = None,
    benzersiz: bool = False,
) -> list[str]:
    """Sentetik satır listesi üretir.

    ``benzersiz=True`` yinelenen metinleri eler; aynı cümlenin onlarca kez
    tekrarlanması modelin ezberlemesine ve doğrulama ölçümünün şişmesine yol
    açar. Havuz tükenirse istenen adetten az satır dönebilir.
    """
    rng = random.Random(tohum)
    havuz = terimler(ek_terimler)
    if not benzersiz:
        return [satir_uret(rng, havuz) for _ in range(adet)]
    gorulen: set[str] = set()
    sonuc: list[str] = []
    bos_tur = 0
    while len(sonuc) < adet and bos_tur < 20000:
        metin = satir_uret(rng, havuz)
        if metin in gorulen:
            bos_tur += 1
            continue
        bos_tur = 0
        gorulen.add(metin)
        sonuc.append(metin)
    return sonuc


def metin_ayrik_bol(
    kayitlar: list[dict], test_orani: float = 0.05, tohum: int = 0
) -> tuple[list[dict], list[dict]]:
    """Kayıtları metin bazında ayırır: aynı cümle iki bölmede birden olmaz.

    Rastgele satır bölmesi, aynı metnin farklı fontlarla üretilmiş kopyalarını
    iki tarafa dağıtır; doğrulama kaybı gerçekte olmadığı kadar iyi görünür.
    """
    if not 0 <= test_orani < 1:
        raise ValueError("test_orani 0 ile 1 arasında olmalı")
    metinler = sorted({str(k["text"]) for k in kayitlar})
    rng = random.Random(tohum)
    rng.shuffle(metinler)
    test_sayisi = int(len(metinler) * test_orani)
    test_metinleri = set(metinler[:test_sayisi])
    egitim = [k for k in kayitlar if str(k["text"]) not in test_metinleri]
    test = [k for k in kayitlar if str(k["text"]) in test_metinleri]
    return egitim, test
