"""Kalıtım probleminin yapılandırılmış tanımı.

Model soruyu ÇÖZMEZ; yalnız buradaki yapıya çevirir. Hesabı saf Python
yapar (`punnett`). Ayrımın sebebi ölçüm: 4B model Punnett karesini ve
olasılık çarpımını yapamıyor (kalitim_hesabi türünde doğruluk %18), ama
"bu soruda anne Aa, baba Aa, çekinik çocuk olasılığı soruluyor" bilgisini
çıkarmak bir dil işidir ve modelin yapabildiği şeydir.

Tüm yapılar `frozen`: bir tanım üretildikten sonra değişmemeli, yoksa
hesabın hangi girdiyle yapıldığı raporlanamaz.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from fractions import Fraction

# Baskınlık ilişkileri.
BASKINLIK = ("tam", "eksik", "es", "coklu_alel", "kan_grubu")
# Lokusun bulunduğu kromozom.
KONUM = ("otozom", "x", "y", "xy_homolog")
# `Istek.tur` — sorunun ne istediği.
ISTEK_TURLERI = (
    "olasilik",          # belirli bir fenotip/genotipin olasılığı
    "fenotip_orani",     # 9:3:3:1 gibi
    "genotip_orani",
    "cesit_sayisi",      # kaç çeşit fenotip/genotip
    "gamet_cesidi",      # kaç çeşit gamet (en az / en çok)
    "gamet_olasiligi",   # belirli bir gametin olasılığı
    "kromozom_sayisi",   # genotipten diploit kromozom sayısı
    "kontrol_caprazi",   # test çaprazı için gereken genotip
)


@dataclass(frozen=True)
class Lokus:
    """Tek bir karakteri belirleyen gen bölgesi."""

    ad: str                                  # "A" | "kan" | "renk_korlugu"
    aleller: tuple[str, ...]                 # ("A","a") | ("A","B","0")
    baskinlik: str = "tam"
    konum: str = "otozom"
    # Çok alellide üstünlük sırası: ("A","0") → A, 0'a baskın. Eşit olanlar
    # aynı demette: kan grubunda A ve B eş baskın, ikisi de 0'a baskın.
    ustunluk: tuple[tuple[str, ...], ...] = ()
    fenotipler: dict[str, str] = field(default_factory=dict)

    def baskin_alel(self) -> str:
        return self.aleller[0] if self.aleller else ""

    def cekinik_alel(self) -> str:
        return self.aleller[-1] if self.aleller else ""


@dataclass(frozen=True)
class Birey:
    """Çaprazlamaya giren birey. Genotip lokus adından alel dizisine eşlenir."""

    etiket: str = ""
    genotip: dict[str, str] = field(default_factory=dict)   # {"A": "Aa"}
    cinsiyet: str = ""                                      # "disi" | "erkek" | ""
    fenotip: dict[str, str] = field(default_factory=dict)


@dataclass(frozen=True)
class Istek:
    """Sorunun ne istediği."""

    tur: str = "olasilik"
    hedef: dict = field(default_factory=dict)
    # "birinci çocuk çekinik, ikinci baskın" gibi sıralı olaylar; her öğe bir
    # `hedef` sözlüğü. Olasılıklar çarpılır.
    cocuk_sirasi: tuple[dict, ...] = ()
    # "en az" / "en cok" — gamet çeşidi sorularında bağlılık varsayımını seçer.
    sinir: str = ""
    # KOŞUL — dağılımı daraltır, çarpan uygulamaz. İki soru arasındaki fark
    # sessiz ve ölümcül:
    #   "bir çocuğun renk körü ERKEK olma olasılığı"  → birleşik, hedefe girer
    #   "ERKEK çocukların renk körü olma olasılığı"   → koşullu, buraya girer
    # Birincisi 1/2 ile çarpılır, ikincisi çarpılmaz. Ayrım yapılmazsa
    # cevabın yarısı ya da iki katı hesaplanır ve şıkla eşleşerek kendinden
    # emin yanlış cevap üretir — şık listesi genelde her iki değeri de içerir.
    kosul: dict = field(default_factory=dict)


@dataclass(frozen=True)
class Caprazlama:
    """Tam problem tanımı."""

    lokuslar: tuple[Lokus, ...] = ()
    ebeveynler: tuple[Birey, ...] = ()
    # Aynı kromozomda taşınan lokus adları. Her demet bir bağlantı grubu.
    bagli_gruplar: tuple[tuple[str, ...], ...] = ()
    krossing_orani: Fraction | None = None
    istek: Istek = field(default_factory=Istek)

    def lokus(self, ad: str) -> Lokus | None:
        for lokus in self.lokuslar:
            if lokus.ad == ad:
                return lokus
        return None

    def dogrula(self) -> list[str]:
        """Tanımın iç tutarlılığı; boş liste = geçerli.

        Model uydurduğunda bunu YAKALAMAK zorundayız: geçersiz bir tanımla
        yapılan hesap kendinden emin ama yanlış bir cevap üretir ve bu,
        cevapsız kalmaktan çok daha zararlıdır.
        """
        sorunlar: list[str] = []
        adlar = [k.ad for k in self.lokuslar]
        if len(adlar) != len(set(adlar)):
            sorunlar.append("Aynı lokus birden çok kez tanımlanmış.")
        for lokus in self.lokuslar:
            if not lokus.aleller:
                sorunlar.append(f"{lokus.ad}: alel listesi boş.")
            if lokus.baskinlik not in BASKINLIK:
                sorunlar.append(f"{lokus.ad}: bilinmeyen baskınlık {lokus.baskinlik!r}.")
            if lokus.konum not in KONUM:
                sorunlar.append(f"{lokus.ad}: bilinmeyen konum {lokus.konum!r}.")

        if self.istek.tur not in ISTEK_TURLERI:
            sorunlar.append(f"Bilinmeyen istek türü {self.istek.tur!r}.")

        for birey in self.ebeveynler:
            for lokus_adi, genotip in birey.genotip.items():
                lokus = self.lokus(lokus_adi)
                if lokus is None:
                    sorunlar.append(
                        f"{birey.etiket or '?'}: tanımsız lokus {lokus_adi!r}."
                    )
                    continue
                sorunlar.extend(self._genotip_denetle(birey, lokus, genotip))

        for grup in self.bagli_gruplar:
            for ad in grup:
                if self.lokus(ad) is None:
                    sorunlar.append(f"Bağlı grupta tanımsız lokus {ad!r}.")
        return sorunlar

    @staticmethod
    def _genotip_denetle(birey: Birey, lokus: Lokus, genotip: str) -> list[str]:
        sorunlar: list[str] = []
        gecerli = set(lokus.aleller)
        bilinmeyen = [a for a in _alellere_bol(genotip, lokus) if a not in gecerli]
        if bilinmeyen:
            sorunlar.append(
                f"{birey.etiket or '?'}/{lokus.ad}: {genotip!r} içinde "
                f"tanımsız alel {bilinmeyen!r}."
            )
            return sorunlar
        sayi = len(_alellere_bol(genotip, lokus))
        if lokus.konum == "x" and birey.cinsiyet == "erkek":
            # Erkek X'e bağlı lokusta hemizigottur: tek alel taşır.
            if sayi != 1:
                sorunlar.append(
                    f"{birey.etiket or '?'}/{lokus.ad}: erkek X'e bağlı lokusta "
                    f"tek alel taşır, {sayi} verilmiş."
                )
        elif lokus.konum == "y":
            if birey.cinsiyet == "disi" and sayi:
                sorunlar.append(
                    f"{birey.etiket or '?'}/{lokus.ad}: dişide Y'ye bağlı alel olamaz."
                )
        elif sayi != 2:
            sorunlar.append(
                f"{birey.etiket or '?'}/{lokus.ad}: {genotip!r} diploit değil "
                f"({sayi} alel)."
            )
        return sorunlar


def _alellere_bol(genotip: str, lokus: Lokus) -> list[str]:
    """Genotip dizisini alel listesine böler.

    Tek harfli alellerde ("Aa") karakter karakter; çok karakterli alel varsa
    ("XR", "0") en uzun eşleşme önce denenir. Bu, kan grubu ("A0") ve X'e
    bağlı gösterimlerin ("XRXr") aynı yapıyla ele alınmasını sağlıyor.
    """
    genotip = (genotip or "").strip()
    if not genotip:
        return []
    aleller = sorted(lokus.aleller, key=len, reverse=True)
    sonuc: list[str] = []
    i = 0
    while i < len(genotip):
        for alel in aleller:
            if alel and genotip.startswith(alel, i):
                sonuc.append(alel)
                i += len(alel)
                break
        else:
            # Tanınmayan karakter: bilinçli olarak olduğu gibi eklenir ki
            # `dogrula` bunu "tanımsız alel" diye yakalayabilsin.
            sonuc.append(genotip[i])
            i += 1
    return sonuc
