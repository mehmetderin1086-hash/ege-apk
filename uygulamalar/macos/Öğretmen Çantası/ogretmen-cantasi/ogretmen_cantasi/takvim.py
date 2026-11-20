"""Öğretim yılı takvimi: dönemler, tatiller ve haftalık ders saati hesabı.

Yıllık plan dağıtımı bu modülün ürettiği hafta listesine dayanır. Bir haftanın
"kaç ders saati" taşıdığı, şubenin ders programındaki günlerin o hafta içinde
tatile denk gelip gelmediğine göre hesaplanır — tatil haftasına ders yazılmaz.
"""

from __future__ import annotations

import calendar
from dataclasses import dataclass, field
from datetime import date, timedelta

AY_ADLARI = (
    "Ocak", "Şubat", "Mart", "Nisan", "Mayıs", "Haziran",
    "Temmuz", "Ağustos", "Eylül", "Ekim", "Kasım", "Aralık",
)
GUN_ADLARI = ("Pazartesi", "Salı", "Çarşamba", "Perşembe", "Cuma", "Cumartesi", "Pazar")

TUR_RESMI = "resmi_tatil"
TUR_ARA = "ara_tatil"
TUR_YARIYIL = "yariyil"
TUR_OKUL = "okul_ozel"
TUR_SINAV = "sinav_haftasi"
# Belirli gün ve haftalar TATİL DEĞİLDİR: o gün ders yapılır, yalnız yıllık
# planın ilgili sütununda anılır. Bu yüzden ders saati hesabından düşülmez.
TUR_BELIRLI = "belirli_gun"
DERS_YAPILAN_TURLER = (TUR_BELIRLI,)

# Yıllık planda gösterilmesi beklenen belirli gün ve haftalardan biyoloji
# dersiyle ilişkili olanlar (gün, ay, bitiş günü, bitiş ayı, ad). Liste
# bilinçli olarak kısa tutuldu: yalnız tarihi sabit ve yaygın kabul görenler
# var. Öğretmen kurulum ekranından kendi listesini ekleyip çıkarabilir.
BELIRLI_GUNLER: tuple[tuple[int, int, int, int, str], ...] = (
    (4, 10, 4, 10, "Hayvanları Koruma Günü"),
    (10, 11, 16, 11, "Atatürk Haftası"),
    (24, 11, 24, 11, "Öğretmenler Günü"),
    (14, 3, 14, 3, "Tıp Bayramı"),
    (21, 3, 26, 3, "Orman Haftası"),
    (22, 3, 22, 3, "Dünya Su Günü"),
    (1, 4, 7, 4, "Kanser Haftası"),
    (5, 6, 5, 6, "Dünya Çevre Günü"),
)

# Sabit tarihli resmî tatiller (gün, ay, ad). Dinî bayramlar burada YOK:
# tarihleri Diyanet takvimine göre yıldan yıla kayıyor ve tahmin edilerek
# yazılan bir tarih, yıllık planı sessizce yanlış haftaya kaydırır. Kullanıcı
# bunları kurulum ekranındaki "bayram ekle" formuyla girer.
SABIT_TATILLER: tuple[tuple[int, int, str], ...] = (
    (1, 1, "Yılbaşı"),
    (23, 4, "Ulusal Egemenlik ve Çocuk Bayramı"),
    (1, 5, "Emek ve Dayanışma Günü"),
    (19, 5, "Atatürk'ü Anma, Gençlik ve Spor Bayramı"),
    (15, 7, "Demokrasi ve Millî Birlik Günü"),
    (30, 8, "Zafer Bayramı"),
    (29, 10, "Cumhuriyet Bayramı"),
)


@dataclass(frozen=True)
class Donem:
    no: int
    baslangic: date
    bitis: date

    def icinde(self, gun: date) -> bool:
        return self.baslangic <= gun <= self.bitis


@dataclass(frozen=True)
class TatilGunu:
    tarih: date
    tur: str
    aciklama: str


@dataclass
class Hafta:
    no: int
    donem: int
    baslangic: date
    bitis: date
    ders_saati: int = 0
    ders_gunleri: list[date] = field(default_factory=list)
    tatiller: list[TatilGunu] = field(default_factory=list)

    @property
    def ay(self) -> str:
        """Haftanın ait olduğu ay — çoğunluk hangi aydaysa o.

        Ay sınırına oturan haftalar yıllık planda tek bir ay satırına yazılmak
        zorunda; "başlangıç günü hangi aysa o" kuralı, haftanın dört gününün
        yeni ayda olduğu durumlarda yanıltıcı oluyordu.
        """
        gunler = [self.baslangic + timedelta(days=i) for i in range(5)]
        aylar = [g.month for g in gunler]
        baskin = max(set(aylar), key=aylar.count)
        return AY_ADLARI[baskin - 1]

    @property
    def gercek_tatiller(self) -> list[TatilGunu]:
        """Ders yapılmayan günler — belirli gün ve haftalar buna dahil değil."""
        return [t for t in self.tatiller if t.tur not in DERS_YAPILAN_TURLER]

    @property
    def belirli_gun_adlari(self) -> list[str]:
        return sorted({t.aciklama for t in self.tatiller if t.tur in DERS_YAPILAN_TURLER})

    @property
    def etiket(self) -> str:
        return f"{self.baslangic.strftime('%d.%m')}-{self.bitis.strftime('%d.%m.%Y')}"


def varsayilan_ogretim_yili(baslangic_yili: int) -> tuple[str, Donem, Donem]:
    """MEB çalışma takvimi yayımlanana kadar kullanılan makul varsayılan.

    Eylül'ün ikinci pazartesi başlar, ocak ortasında birinci dönem biter,
    şubat başında ikinci dönem başlar, haziran ortasında sona erer. Kullanıcı
    kurulum ekranından düzeltir; amaç boş forma değil, düzeltilebilir bir
    taslağa başlatmak.
    """
    ad = f"{baslangic_yili}-{baslangic_yili + 1}"
    eylul = date(baslangic_yili, 9, 1)
    ilk_pazartesi = eylul + timedelta(days=(7 - eylul.weekday()) % 7)
    d1_bas = ilk_pazartesi + timedelta(days=7)
    d1_bit = date(baslangic_yili + 1, 1, 16)
    d2_bas = date(baslangic_yili + 1, 2, 2)
    d2_bit = date(baslangic_yili + 1, 6, 18)
    return ad, Donem(1, d1_bas, d1_bit), Donem(2, d2_bas, d2_bit)


def sabit_tatiller(donemler: tuple[Donem, ...]) -> list[TatilGunu]:
    """Dönem aralıklarına düşen sabit tarihli resmî tatilleri üretir."""
    tatiller: list[TatilGunu] = []
    yillar = {d.baslangic.year for d in donemler} | {d.bitis.year for d in donemler}
    for yil in sorted(yillar):
        for gun, ay, ad in SABIT_TATILLER:
            tarih = date(yil, ay, gun)
            if any(d.icinde(tarih) for d in donemler):
                tatiller.append(TatilGunu(tarih, TUR_RESMI, ad))
    return sorted(tatiller, key=lambda t: t.tarih)


def belirli_gunler(donemler: tuple[Donem, ...]) -> list[TatilGunu]:
    """Dönem aralıklarına düşen belirli gün ve haftaları üretir."""
    gunler: list[TatilGunu] = []
    yillar = {d.baslangic.year for d in donemler} | {d.bitis.year for d in donemler}
    for yil in sorted(yillar):
        for gun, ay, bitis_gun, bitis_ay, ad in BELIRLI_GUNLER:
            imlec = date(yil, ay, gun)
            son = date(yil, bitis_ay, bitis_gun)
            while imlec <= son:
                if any(d.icinde(imlec) for d in donemler):
                    gunler.append(TatilGunu(imlec, TUR_BELIRLI, ad))
                imlec += timedelta(days=1)
    return sorted(gunler, key=lambda t: t.tarih)


def bayram_gunleri(arefe: date, gun_sayisi: int, ad: str) -> list[TatilGunu]:
    """Arefe gününden başlayarak bayram tatili günlerini üretir.

    Ramazan üç, Kurban dört gündür; arefe yarım gün olsa da ders yapılmadığı
    için tam gün sayılır.
    """
    return [
        TatilGunu(arefe + timedelta(days=i), TUR_RESMI, f"{ad} ({i}. gün)" if i else f"{ad} arefe")
        for i in range(gun_sayisi + 1)
    ]


def aralik_gunleri(baslangic: date, bitis: date, tur: str, aciklama: str) -> list[TatilGunu]:
    gunler: list[TatilGunu] = []
    gun = baslangic
    while gun <= bitis:
        gunler.append(TatilGunu(gun, tur, aciklama))
        gun += timedelta(days=1)
    return gunler


def haftalari_uret(
    donemler: tuple[Donem, ...],
    tatiller: list[TatilGunu],
    ders_gunleri: dict[int, int],
) -> list[Hafta]:
    """Öğretim yılının haftalarını, her birinin ders saatiyle birlikte üretir.

    `ders_gunleri`: {haftanın günü (1=Pazartesi): o gün yapılan ders saati}.
    Tatile denk gelen gün o haftanın saatinden düşer; hiç saati kalmayan hafta
    listede kalır ama plana ders yazılmaz (öğretmen tatili planda görmek ister).
    """
    # Aynı güne birden çok tatil kaydı düşebilir (resmî bayram + okulun kendi
    # kapanışı); sözlükte tek değer tutulursa biri sessizce kayboluyordu.
    tatil_haritasi: dict[date, list[TatilGunu]] = {}
    for tatil in tatiller:
        tatil_haritasi.setdefault(tatil.tarih, []).append(tatil)

    haftalar: list[Hafta] = []
    # Bir takvim haftası iki döneme yayılabilir (birinci dönem çarşamba biter,
    # ikinci dönem aynı haftanın cuması başlar). Aynı Pazartesi iki kez hafta
    # açarsa plan o haftayı iki satır olarak gösteriyordu; var olan haftaya
    # eklemek doğrusu.
    haftaya_gore: dict[date, Hafta] = {}
    for donem in donemler:
        imlec = donem.baslangic - timedelta(days=donem.baslangic.weekday())
        while imlec <= donem.bitis:
            hafta = haftaya_gore.get(imlec)
            if hafta is None:
                hafta = Hafta(
                    no=len(haftalar) + 1,
                    donem=donem.no,
                    baslangic=imlec,
                    bitis=imlec + timedelta(days=6),
                )
                haftalar.append(hafta)
                haftaya_gore[imlec] = hafta

            for gun_no, saat in sorted(ders_gunleri.items()):
                gun = imlec + timedelta(days=gun_no - 1)
                if not donem.icinde(gun) or gun in hafta.ders_gunleri:
                    continue
                # Belirli gün ve haftalar ders saatini düşürmez; yalnız gerçek
                # tatiller (resmî, ara tatil, okula özgü kapanış) düşürür.
                if any(t.tur not in DERS_YAPILAN_TURLER for t in tatil_haritasi.get(gun, ())):
                    continue
                hafta.ders_saati += saat
                hafta.ders_gunleri.append(gun)

            # Haftanın içine düşen tüm tatiller gösterilir (ders günü olmasa da).
            for tarih, gunun_tatilleri in tatil_haritasi.items():
                if imlec <= tarih <= hafta.bitis:
                    for tatil in gunun_tatilleri:
                        if tatil not in hafta.tatiller:
                            hafta.tatiller.append(tatil)
            hafta.tatiller.sort(key=lambda t: t.tarih)
            hafta.ders_gunleri.sort()
            imlec += timedelta(days=7)
    return haftalar


def ay_gunleri(yil: int, ay: int) -> list[date]:
    _, son = calendar.monthrange(yil, ay)
    return [date(yil, ay, g) for g in range(1, son + 1)]


def tarih_metni(gun: date) -> str:
    return f"{gun.day} {AY_ADLARI[gun.month - 1]} {gun.year} {GUN_ADLARI[gun.weekday()]}"
