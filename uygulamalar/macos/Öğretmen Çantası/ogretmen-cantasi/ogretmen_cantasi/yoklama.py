"""Yoklama: sesli dökümü sınıf listesiyle eşleştirme ve devamsızlık hesabı.

Kullanım biçimi "sadece gelmeyenleri söyle": öğretmen "Ayşe yok, Mehmet Kaya
yok, Ali geç geldi" der; geri kalan herkes VAR sayılır. Bu, tam liste okumaya
göre hem çok daha kısa hem de yanlış duyma riskini gelmeyen öğrenci sayısıyla
sınırlıyor.

Eşleşme sonucu doğrudan kaydedilmez: her zaman bir onay ekranından geçer.
Emin olunamayan eşleşmeler `belirsizler` listesinde işaretlenir.
"""

from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass, field
from datetime import date

from rapidfuzz import fuzz, process

DURUM_VAR = "var"
DURUM_YOK = "yok"
DURUM_GEC = "gec"
DURUM_IZINLI = "izinli"

DURUM_ADLARI = {
    DURUM_VAR: "Var",
    DURUM_YOK: "Yok",
    DURUM_GEC: "Geç geldi",
    DURUM_IZINLI: "İzinli",
}

# Durum belirten ifadeler. Sıra önemli: "geç geldi" önce denenmezse "geldi"
# öğrenciyi var sayar.
DURUM_IPUCLARI: tuple[tuple[str, str], ...] = (
    (r"\bgeç\s*(geldi|kaldı)?\b", DURUM_GEC),
    (r"\bizinli\b|\braporlu\b|\bmazeret\w*\b", DURUM_IZINLI),
    (r"\byok(tur)?\b|\bgelmedi\b|\bgelmemiş\b|\bdevamsız\b|\byoklar\b", DURUM_YOK),
    (r"\bvar(dır)?\b|\bburada\b|\bgeldi\b", DURUM_VAR),
)

# Dökümün başındaki giriş kalıpları ("Gelmeyenler: …") atılır.
GIRIS_KALIPLARI = (r"^\s*(gelmeyenler|yoklama|devamsızlar|bugün)\s*[:,]?",)

# İki öğrenci adını ayıran işaretler. Bağlaçlar da ayırıcıdır: konuşurken
# "Ayşe ve Ali yok" denince virgül duyulmaz.
BOLUCU = r"[,;\n]|\.\s|\.$|\bve\b|\bile\b|\bbir de\b|\bsonra\b"

ESIK_KESIN = 88.0
ESIK_BELIRSIZ = 70.0


def turkce_kucult(metin: str) -> str:
    """Türkçe büyük-küçük harf kurallarına göre küçültür.

    Python'un `lower()` metodu 'I' harfini 'i'ye çeviriyor; Türkçede karşılığı
    'ı'. Düzeltilmezse "ILGAZ" ile "Ilgaz" eşleşmiyor.
    """
    return unicodedata.normalize("NFC", metin.replace("I", "ı").replace("İ", "i")).lower()


def sadelestir(ad: str) -> str:
    ad = turkce_kucult(ad)
    ad = re.sub(r"[^\wçğıöşü\s]", " ", ad)
    return re.sub(r"\s+", " ", ad).strip()


def eslesme_indeksi(kayitlar) -> tuple[dict, dict]:
    """(numara, ad_soyad, nesne) üçlülerinden eşleştirme indeksi kurar.

    Öğrenci/deneme içe aktarma önizlemeleri ile aktarımın kendisi AYNI
    eşleştirmeyi kullanmak zorunda: kural üç yerde ayrı yazıldığında biri
    değişince önizleme, kullanıcının onaylamadığı bir eşleşmeyi gösteriyordu.
    Tek kural: dolu numara birebir eşleşir; numara yoksa sadeleştirilmiş ada
    bakılır.
    """
    numaraya: dict[str, list] = {}
    ada: dict[str, list] = {}
    for numara, ad, nesne in kayitlar:
        anahtar = numara.strip()
        if anahtar:
            numaraya.setdefault(anahtar, []).append(nesne)
        ada.setdefault(sadelestir(ad), []).append(nesne)
    return numaraya, ada


def aday_bul(indeks: tuple[dict, dict], numara: str, ad: str) -> list:
    numaraya, ada = indeks
    anahtar = numara.strip()
    return numaraya.get(anahtar, []) if anahtar else ada.get(sadelestir(ad), [])


@dataclass(frozen=True)
class Ogrenci:
    id: int
    numara: str
    ad_soyad: str

    @property
    def anahtar(self) -> str:
        return sadelestir(self.ad_soyad)


@dataclass
class Atama:
    ogrenci: Ogrenci
    durum: str
    duyulan: str
    skor: float

    @property
    def kesin(self) -> bool:
        return self.skor >= ESIK_KESIN


@dataclass
class Cozum:
    atamalar: list[Atama] = field(default_factory=list)
    belirsizler: list[Atama] = field(default_factory=list)
    eslesmeyenler: list[tuple[str, str]] = field(default_factory=list)

    def durum_haritasi(self, ogrenciler: list[Ogrenci]) -> dict[int, str]:
        """Kesin eşleşmelerden tam sınıf tablosu üretir; kalan herkes VAR."""
        harita = {o.id: DURUM_VAR for o in ogrenciler}
        for atama in self.atamalar:
            harita[atama.ogrenci.id] = atama.durum
        return harita


def _durum_ayikla(parca: str) -> tuple[str, str]:
    """Parçadan durumu çıkarır ve durum kelimelerini metinden siler."""
    durum = DURUM_YOK  # "sadece gelmeyenleri söyle" kipinde varsayılan
    kalan = parca
    for kalip, deger in DURUM_IPUCLARI:
        if re.search(kalip, kalan):
            durum = deger
            kalan = re.sub(kalip, " ", kalan)
            break
    return durum, re.sub(r"\s+", " ", kalan).strip()


def parcalara_bol(dokum: str) -> list[str]:
    """Dökümü öğrenci başına bir parçaya böler.

    Bölme, noktalama temizliğinden ÖNCE yapılmalı: `sadelestir` virgülü de
    sildiği için önce çağrılırsa bütün isimler tek parçaya yapışıyor ve
    "Ayşe Yılmaz yok, Mehmet Kaya yok" tek bir öğrenci gibi görünüyordu.
    """
    metin = turkce_kucult(dokum)
    for kalip in GIRIS_KALIPLARI:
        metin = re.sub(kalip, " ", metin)
    return [sadelestir(p) for p in re.split(BOLUCU, metin) if sadelestir(p)]


def cozumle(dokum: str, ogrenciler: list[Ogrenci]) -> Cozum:
    """Ses dökümünü sınıf listesiyle eşleştirir."""
    cozum = Cozum()
    if not ogrenciler:
        return cozum

    # Dict anahtarı ad olursa aynı isimli iki öğrenci tek kayda çöküyordu.
    # RapidFuzz sözlüğünde kimliği anahtar, normalize adı değer tutarak her
    # öğrenciyi ayrı aday olarak koruyoruz.
    anahtarlar = {o.id: o.anahtar for o in ogrenciler}
    kimlikler = {o.id: o for o in ogrenciler}
    kullanilan: set[int] = set()

    for parca in parcalara_bol(dokum):
        durum, ad_parcasi = _durum_ayikla(parca)
        if not ad_parcasi:
            continue

        adaylar = process.extract(
            ad_parcasi,
            anahtarlar,
            scorer=fuzz.token_set_ratio,
            limit=3,
        )
        if not adaylar:
            cozum.eslesmeyenler.append((ad_parcasi, durum))
            continue

        _, skor, en_iyi_id = adaylar[0]
        ogrenci = kimlikler[en_iyi_id]

        # Aynı adı taşıyan iki öğrenci varsa hangisi olduğu ses dökümünden
        # anlaşılamaz; öğretmene sorulmak üzere belirsiz sayılır.
        ikinci_skor = adaylar[1][1] if len(adaylar) > 1 else 0.0
        cakisma = ikinci_skor >= skor - 2

        atama = Atama(ogrenci=ogrenci, durum=durum, duyulan=ad_parcasi, skor=float(skor))
        if skor < ESIK_BELIRSIZ:
            cozum.eslesmeyenler.append((ad_parcasi, durum))
        elif skor < ESIK_KESIN or cakisma or ogrenci.id in kullanilan:
            cozum.belirsizler.append(atama)
        else:
            kullanilan.add(ogrenci.id)
            cozum.atamalar.append(atama)

    return cozum


def devamsizlik_ozeti(
    kayitlar: list[tuple[str, int, str]], gunler: dict[int, int] | None = None
) -> dict:
    """(tarih, ders_saati, durum) kayıtlarından devamsızlık özeti çıkarır.

    Devamsızlık gün cinsinden istenir; öğretmen kendi dersinde saat tutar.
    Gün karşılığı her tarihin KENDİ programına oranlanır (`gunler`:
    isoweekday → o günkü ders saati): Pazartesi 1, Salı 3 saatlik programda
    iki günün de tamamını kaçırmak birer gündür — haftalık ortalamayla
    bölmek 0,5/1,5 gibi yanıltıcı değerler veriyordu. Program girilmemişse
    payda o güne yazılmış yoklama sayısıdır.
    """
    yok = sum(1 for _, _, durum in kayitlar if durum == DURUM_YOK)
    izinli = sum(1 for _, _, durum in kayitlar if durum == DURUM_IZINLI)
    gec = sum(1 for _, _, durum in kayitlar if durum == DURUM_GEC)
    toplam = len(kayitlar)

    gun_bazinda: dict[str, list[str]] = {}
    for tarih, _, durum in kayitlar:
        gun_bazinda.setdefault(tarih, []).append(durum)
    yok_gun = 0.0
    for tarih, durumlar in gun_bazinda.items():
        gunun_yoku = sum(1 for d in durumlar if d == DURUM_YOK)
        if not gunun_yoku:
            continue
        try:
            program_saat = (gunler or {}).get(date.fromisoformat(tarih).isoweekday(), 0)
        except ValueError:
            program_saat = 0
        payda = program_saat or len(durumlar)
        yok_gun += min(1.0, gunun_yoku / payda)

    return {
        "toplam_ders": toplam,
        "yok_saat": yok,
        "izinli_saat": izinli,
        "gec_saat": gec,
        "yok_gun": round(yok_gun, 1),
        "devam_orani": round(100 * (toplam - yok) / toplam, 1) if toplam else None,
    }
