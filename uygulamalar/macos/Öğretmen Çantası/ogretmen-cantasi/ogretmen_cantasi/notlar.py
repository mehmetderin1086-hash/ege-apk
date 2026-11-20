"""Not hesabı: e-Okul yönetmeliği + öğretmenin kendi iç takibi.

Yönetmelik kuralı: dönem puanı, o dönemdeki yazılı sınav, performans çalışması
ve proje notlarının EŞİT AĞIRLIKLI aritmetik ortalamasıdır; yıl sonu başarı
puanı iki dönem puanının ortalamasıdır.

Sayılar ve ağırlıklar `Kurallar` ile değiştirilebilir tutuldu: yönetmelik
değişiyor ve okulun zümre kararı sınav sayısını etkileyebiliyor. Varsayılanlar
yürürlükteki düzenlemeye uyar.

İç takip kayıtları (derse katılım, ödev, deneme) resmî ortalamaya GİRMEZ;
ayrı bir gösterge olarak hesaplanır.
"""

from __future__ import annotations

from dataclasses import dataclass, field

TUR_YAZILI = "yazili"
TUR_PERFORMANS = "performans"
TUR_PROJE = "proje"
TUR_IC_TAKIP = "ic_takip"

RESMI_TURLER = (TUR_YAZILI, TUR_PERFORMANS, TUR_PROJE)

TUR_ADLARI = {
    TUR_YAZILI: "Yazılı sınav",
    TUR_PERFORMANS: "Performans çalışması",
    TUR_PROJE: "Proje",
    TUR_IC_TAKIP: "İç takip",
}


@dataclass(frozen=True)
class Kurallar:
    """Okulun/yönetmeliğin sayısal kuralları."""

    donem_basina_yazili: int = 2
    donem_basina_performans: int = 1
    yil_basina_proje: int = 1
    gecme_puani: float = 50.0
    # Yönetmelik eşit ağırlık öngörüyor; ağırlık değiştirilmek istenirse
    # tür başına çarpan verilir (1.0 = eşit).
    agirliklar: dict[str, float] = field(
        default_factory=lambda: {TUR_YAZILI: 1.0, TUR_PERFORMANS: 1.0, TUR_PROJE: 1.0}
    )

    def beklenen_sayi(self, tur: str) -> int:
        return {
            TUR_YAZILI: self.donem_basina_yazili,
            TUR_PERFORMANS: self.donem_basina_performans,
            TUR_PROJE: self.yil_basina_proje,
        }.get(tur, 0)


@dataclass(frozen=True)
class Puan:
    tur: str
    ad: str
    deger: float | None
    donem: int
    resmi: bool = True


@dataclass
class DonemSonucu:
    donem: int
    puanlar: list[Puan]
    ortalama: float | None
    eksik: dict[str, int]

    @property
    def girilen_sayisi(self) -> int:
        return sum(1 for p in self.puanlar if p.deger is not None)


@dataclass
class OgrenciKarnesi:
    ogrenci_id: int
    ad_soyad: str
    donemler: dict[int, DonemSonucu]
    yil_sonu: float | None
    ic_takip_ortalamasi: float | None
    gecme_puani: float = 50.0

    @property
    def gecti(self) -> bool | None:
        if self.yil_sonu is None:
            return None
        return self.yil_sonu >= self.gecme_puani


def donem_ortalamasi(puanlar: list[Puan], kurallar: Kurallar | None = None) -> float | None:
    """Bir dönemin resmî puan ortalaması.

    Girilmemiş (None) notlar hesaba katılmaz — henüz yapılmamış bir sınavı sıfır
    saymak öğrenciyi haksız yere düşürür. Kaç notun eksik olduğu ayrıca
    raporlanır (bkz. `donem_sonucu`).
    """
    kurallar = kurallar or Kurallar()
    girilen = [p for p in puanlar if p.resmi and p.deger is not None]
    if not girilen:
        return None
    toplam_agirlik = sum(kurallar.agirliklar.get(p.tur, 1.0) for p in girilen)
    if toplam_agirlik == 0:
        return None
    toplam = sum((p.deger or 0) * kurallar.agirliklar.get(p.tur, 1.0) for p in girilen)
    return round(toplam / toplam_agirlik, 2)


def donem_sonucu(donem: int, puanlar: list[Puan], kurallar: Kurallar | None = None) -> DonemSonucu:
    kurallar = kurallar or Kurallar()
    donemin = [p for p in puanlar if p.donem == donem]
    eksik: dict[str, int] = {}
    for tur in (TUR_YAZILI, TUR_PERFORMANS):
        girilen = sum(1 for p in donemin if p.tur == tur and p.deger is not None)
        fark = kurallar.beklenen_sayi(tur) - girilen
        if fark > 0:
            eksik[tur] = fark
    return DonemSonucu(
        donem=donem,
        puanlar=donemin,
        ortalama=donem_ortalamasi(donemin, kurallar),
        eksik=eksik,
    )


def yil_sonu_puani(donem1: float | None, donem2: float | None) -> float | None:
    """Yıl sonu başarı puanı = İKİ dönem puanının ortalaması.

    Bir dönem eksikken hesaplanmaz. Yıl ortasında tek dönemin ortalamasını
    "yıl sonu" diye göstermek, öğrenciyi daha ikinci dönem başlamadan
    "geçti/kaldı" olarak işaretliyordu; dönem sütunları zaten ayrı duruyor.
    """
    if donem1 is None or donem2 is None:
        return None
    return round((donem1 + donem2) / 2, 2)


def karne_kur(
    ogrenci_id: int,
    ad_soyad: str,
    puanlar: list[Puan],
    kurallar: Kurallar | None = None,
) -> OgrenciKarnesi:
    kurallar = kurallar or Kurallar()
    donemler = {d: donem_sonucu(d, puanlar, kurallar) for d in (1, 2)}
    ic_takip = [p.deger for p in puanlar if not p.resmi and p.deger is not None]
    return OgrenciKarnesi(
        ogrenci_id=ogrenci_id,
        ad_soyad=ad_soyad,
        donemler=donemler,
        yil_sonu=yil_sonu_puani(donemler[1].ortalama, donemler[2].ortalama),
        ic_takip_ortalamasi=round(sum(ic_takip) / len(ic_takip), 2) if ic_takip else None,
        gecme_puani=kurallar.gecme_puani,
    )


def sinif_istatistigi(
    karneler: list[OgrenciKarnesi], donem: int, kurallar: Kurallar | None = None
) -> dict:
    """Şubenin dönem ortalaması, en düşük/en yüksek ve zayıf sayısı."""
    # Eşik sabit 50 değil, kurallardan gelir: zümre kararıyla değişebiliyor ve
    # iki yerde farklı eşik kullanmak karneyle sınıf özetini çelişkiye düşürür.
    esik = (kurallar or Kurallar()).gecme_puani
    ortalamalar = [
        k.donemler[donem].ortalama for k in karneler if k.donemler[donem].ortalama is not None
    ]
    if not ortalamalar:
        return {"ogrenci": len(karneler), "ortalama": None, "en_dusuk": None, "en_yuksek": None, "zayif": 0}
    return {
        "ogrenci": len(karneler),
        "ortalama": round(sum(ortalamalar) / len(ortalamalar), 2),
        "en_dusuk": min(ortalamalar),
        "en_yuksek": max(ortalamalar),
        "zayif": sum(1 for o in ortalamalar if o < esik),
    }


def devamsizlik_uyarisi(devamsiz_gun: float, sinir: int = 10) -> str:
    """Özürsüz devamsızlık sınırı yaklaşırken uyarı metni üretir.

    Sınır ders bazlı değil okul geneli işlese de, öğretmenin kendi dersindeki
    birikimi görmesi erken müdahale için tek pratik gösterge.
    """
    if devamsiz_gun >= sinir:
        return f"Sınır aşıldı: {devamsiz_gun:g} gün (sınır {sinir})"
    if devamsiz_gun >= sinir * 0.7:
        return f"Sınıra yaklaşıyor: {devamsiz_gun:g} gün (sınır {sinir})"
    return ""
