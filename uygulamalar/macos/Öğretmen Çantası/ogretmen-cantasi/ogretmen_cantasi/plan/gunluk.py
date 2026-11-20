"""Günlük ders planı üretimi.

Bölümlerin gövdesi resmî programın metinlerinden gelir. Program, "ön
değerlendirme" ve "köprü kurma" paragraflarında her cümleyi ilgili kazanım
koduyla etiketlemiş — bu sayede o günün kazanımına ait cümleler süzülebiliyor
ve plana temanın tamamı değil yalnız o dersin metni giriyor.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from datetime import date

from ..mufredat import OgrenmeCiktisi, Tema
from . import oneriler

VARSAYILAN_DERS_DAKIKASI = 40

# (bölüm adı, süre payı, kaynak alan). Paylar toplamı 1.0 olacak şekilde
# ölçeklenir; tek saatlik derste de iki saatlik blokta da aynı oran korunur.
BOLUM_TANIMLARI: tuple[tuple[str, float, str], ...] = (
    ("Dikkat Çekme ve Ön Değerlendirme", 0.12, "on_degerlendirme"),
    ("Derse Giriş — Köprü Kurma", 0.13, "kopru_kurma"),
    ("İşleniş", 0.35, "uygulama"),
    ("Etkinlik", 0.25, "uygulama"),
    ("Ölçme ve Değerlendirme", 0.10, "ogrenme_kanitlari"),
    ("Kapanış ve Ödev", 0.05, "kapanis"),
)


@dataclass
class Bolum:
    ad: str
    dakika: int
    metin: str


@dataclass
class GunlukPlan:
    tarih: date
    sube_adi: str
    sinif: int
    tema_no: int
    tema_adi: str
    ders_saatleri: list[int]
    kazanim_kodlari: list[str] = field(default_factory=list)
    kazanim_ifadeleri: list[str] = field(default_factory=list)
    surec_bilesenleri: list[str] = field(default_factory=list)
    bolumler: list[Bolum] = field(default_factory=list)
    arac_gerec: list[str] = field(default_factory=list)
    yontem_teknik: list[str] = field(default_factory=list)
    temel_kabuller: str = ""
    zenginlestirme: str = ""
    destekleme: str = ""
    beceriler: list[str] = field(default_factory=list)
    degerler: list[str] = field(default_factory=list)
    notlar: str = ""

    @property
    def toplam_dakika(self) -> int:
        return sum(b.dakika for b in self.bolumler)

    def sozluge(self) -> dict:
        return {
            "tarih": self.tarih.isoformat(),
            "sube_adi": self.sube_adi,
            "sinif": self.sinif,
            "tema_no": self.tema_no,
            "tema_adi": self.tema_adi,
            "ders_saatleri": self.ders_saatleri,
            "kazanim_kodlari": self.kazanim_kodlari,
            "kazanim_ifadeleri": self.kazanim_ifadeleri,
            "surec_bilesenleri": self.surec_bilesenleri,
            "bolumler": [{"ad": b.ad, "dakika": b.dakika, "metin": b.metin} for b in self.bolumler],
            "arac_gerec": self.arac_gerec,
            "yontem_teknik": self.yontem_teknik,
            "temel_kabuller": self.temel_kabuller,
            "zenginlestirme": self.zenginlestirme,
            "destekleme": self.destekleme,
            "beceriler": self.beceriler,
            "degerler": self.degerler,
            "notlar": self.notlar,
        }


def cumlelere_bol(metin: str) -> list[str]:
    """Metni cümlelere böler; kısaltmalardaki noktaları sınır saymaz."""
    if not metin:
        return []
    korumali = re.sub(r"(\b[A-ZÇĞİÖŞÜ]{2,}\.|\bvb\.|\bBİY\.)", lambda e: e.group().replace(".", "\x00"), metin)
    parcalar = re.split(r"(?<=[.!?])\s+", korumali)
    return [p.replace("\x00", ".").strip() for p in parcalar if p.strip()]


def kazanima_ait_metin(metin: str, kodlar: list[str]) -> str:
    """Kazanım koduyla etiketlenmiş cümleleri süzer.

    Resmî metin cümle sonlarında "(BİY.9.1.3)" biçiminde kazanım işaretliyor,
    ama bir kazanımın anlatımı birden çok cümle sürüp kod yalnız sonuncuya
    konabiliyor. Bu yüzden etiketsiz cümle EN SON görülen koda bağlanır; hiçbir
    kod görülmeden gelen baştaki cümleler ise temanın geneline aittir ve her
    kazanımın planına girer.

    Kazanıma ait hiç cümle yoksa boş döner — ilgisiz bir paragrafı o dersin
    planına yazmaktansa bölümü boş bırakıp öğretmene "burayı siz doldurun"
    demek doğru olanı.
    """
    cumleler = cumlelere_bol(metin)
    if not cumleler:
        return ""

    kod_kumesi = set(kodlar)
    genel: list[str] = []
    secilen: list[str] = []
    yapisik: set[str] = set()

    for cumle in cumleler:
        bulunan = set(re.findall(r"BİY\.\s?\d{1,2}\.\d+\.\d+", cumle))
        if bulunan:
            yapisik = {k.replace(" ", "") for k in bulunan}
        if not yapisik:
            genel.append(cumle)
        elif yapisik & kod_kumesi:
            secilen.append(cumle)

    if not secilen:
        return " ".join(genel)
    return " ".join(genel + secilen)


def _kapanis_metni(kazanimlar: list[OgrenmeCiktisi]) -> str:
    if not kazanimlar:
        return "Dersin özeti yapılır, sorular alınır."
    son = kazanimlar[-1]
    bilesen = son.surec_bilesenleri[-1].ifade if son.surec_bilesenleri else son.ifade
    return (
        "Dersin kazanımları özetlenir ve öğrencilerden şu davranışı göstermeleri beklenir: "
        f"{bilesen} Bir sonraki ders için ön hazırlık ödevi verilir."
    )


def dakikalari_dagit(toplam: float, paylar: list[float]) -> list[int]:
    """Süreyi bölümlere böler; toplamı korur ve 5 dakikanın katlarına yuvarlar."""
    ham = [toplam * p for p in paylar]
    dakikalar = [max(5, round(h / 5.0) * 5) for h in ham]
    fark = int(toplam) - sum(dakikalar)
    if fark:
        # Farkı en uzun bölüme ekleyip çıkarmak, kısa bölümleri bozmaz.
        en_uzun = max(range(len(dakikalar)), key=lambda i: dakikalar[i])
        dakikalar[en_uzun] = max(5, dakikalar[en_uzun] + fark)
    return dakikalar


def gunluk_plan_uret(
    *,
    tarih: date,
    sube_adi: str,
    sinif: int,
    tema: Tema,
    kazanimlar: list[OgrenmeCiktisi],
    ders_saatleri: list[int],
    ders_dakikasi: int = VARSAYILAN_DERS_DAKIKASI,
) -> GunlukPlan:
    kodlar = [k.kod for k in kazanimlar]
    uygulama = " ".join(tema.uygulama(k) for k in kodlar).strip()

    kaynaklar = {
        "on_degerlendirme": kazanima_ait_metin(tema.on_degerlendirme, kodlar),
        "kopru_kurma": kazanima_ait_metin(tema.kopru_kurma, kodlar),
        "uygulama": uygulama,
        "ogrenme_kanitlari": tema.ogrenme_kanitlari,
        "kapanis": _kapanis_metni(kazanimlar),
    }

    toplam_dakika = max(1, len(ders_saatleri)) * ders_dakikasi
    dakikalar = dakikalari_dagit(toplam_dakika, [pay for _, pay, _ in BOLUM_TANIMLARI])

    # İşleniş ve etkinlik aynı kaynaktan besleniyor; metni ikiye bölerek
    # ikisine de gövde veriyoruz, yoksa aynı paragraf iki kez yazılırdı.
    uygulama_cumleleri = cumlelere_bol(uygulama)
    orta = len(uygulama_cumleleri) // 2 or len(uygulama_cumleleri)
    islenis_metni = " ".join(uygulama_cumleleri[:orta])
    etkinlik_metni = " ".join(uygulama_cumleleri[orta:]) or islenis_metni

    bolumler: list[Bolum] = []
    for (ad, _, kaynak), dakika in zip(BOLUM_TANIMLARI, dakikalar, strict=True):
        if ad == "İşleniş":
            metin = islenis_metni
        elif ad == "Etkinlik":
            metin = etkinlik_metni
        else:
            metin = kaynaklar.get(kaynak, "")
        bolumler.append(Bolum(ad=ad, dakika=dakika, metin=metin.strip()))

    return GunlukPlan(
        tarih=tarih,
        sube_adi=sube_adi,
        sinif=sinif,
        tema_no=tema.no,
        tema_adi=tema.ad,
        ders_saatleri=list(ders_saatleri),
        kazanim_kodlari=kodlar,
        kazanim_ifadeleri=[k.ifade for k in kazanimlar],
        surec_bilesenleri=[f"{b.harf}) {b.ifade}" for k in kazanimlar for b in k.surec_bilesenleri],
        bolumler=bolumler,
        arac_gerec=oneriler.araclar(uygulama),
        yontem_teknik=oneriler.yontemler(uygulama),
        temel_kabuller=tema.temel_kabuller,
        zenginlestirme=kazanima_ait_metin(tema.zenginlestirme, kodlar),
        destekleme=kazanima_ait_metin(tema.destekleme, kodlar),
        beceriler=list(tema.alan_becerileri) + list(tema.kavramsal_beceriler),
        degerler=list(tema.degerler),
    )
