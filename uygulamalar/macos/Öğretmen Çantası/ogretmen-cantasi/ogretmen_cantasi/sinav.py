"""Açık uçlu sınav üretimi, belirtke tablosu ve kazanım bazlı başarı analizi.

Sınavlar yalnız açık uçlu sorulardan oluşur: hem öğretmenin tercihi hem de
Maarif Modeli'nin ölçme yaklaşımı (dereceli puanlama anahtarıyla değerlendirme)
bu yönde. Her sorunun bir kazanım kodu ve bir rubriği vardır; kazanım kodu
olmadan soru havuza girmez, çünkü başarı analizi tamamen ona dayanır.
"""

from __future__ import annotations

import random
from collections import defaultdict
from dataclasses import dataclass, field

VARSAYILAN_GRUPLAR = ("A", "B")


class SinavKurulamadi(ValueError):
    """İstenen dağılımı karşılayacak soru havuzda yok."""


@dataclass(frozen=True)
class Soru:
    id: int
    kazanim_kodu: str
    metin: str
    puan: float = 10.0
    rubrik: str = ""
    gorsel_yolu: str = ""
    zorluk: str = "orta"

    @property
    def gorselli(self) -> bool:
        return bool(self.gorsel_yolu)


@dataclass
class BelirtkeSatiri:
    anahtar: str
    ad: str
    hedef_yuzde: float
    soru_sayisi: int
    puan: float = 0.0

    @property
    def gerceklesen_yuzde(self) -> float:
        return self.puan


@dataclass
class Sinav:
    ad: str
    sube_adi: str
    sinif: int
    sure_dk: int
    sorular: list[Soru]
    belirtke: list[BelirtkeSatiri] = field(default_factory=list)
    gruplar: dict[str, list[Soru]] = field(default_factory=dict)

    @property
    def toplam_puan(self) -> float:
        return round(sum(s.puan for s in self.sorular), 2)


def soru_sayilarini_dagit(dagilim: dict[str, float], soru_sayisi: int) -> dict[str, int]:
    """Yüzde dağılımını tam sayı soru adedine çevirir.

    En büyük kalan yöntemi: paylar tam sayıya yuvarlanır, artan sorular ondalık
    kısmı en büyük olan başlıklara birer birer dağıtılır. Böylece toplam her
    zaman istenen soru sayısına eşit olur.
    """
    if not dagilim or soru_sayisi <= 0:
        return {}
    # Negatif yüzde kabul edilmez: `adet` negatife düşünce `adaylar[:adet]`
    # dilimi sondan kırpıp istenenden ÇOK soru seçilmesine yol açıyordu.
    temiz = {k: max(0.0, v) for k, v in dagilim.items()}
    toplam_yuzde = sum(temiz.values())
    if toplam_yuzde <= 0:
        return dict.fromkeys(dagilim, 0)

    ham = {k: soru_sayisi * v / toplam_yuzde for k, v in temiz.items()}
    paylar = {k: int(v) for k, v in ham.items()}
    kalan = soru_sayisi - sum(paylar.values())
    sirali = sorted(ham, key=lambda k: ham[k] - paylar[k], reverse=True)
    for anahtar in sirali[:kalan]:
        paylar[anahtar] += 1
    return paylar


def puanlari_dagit(toplam: float, soru_sayisi: int) -> list[float]:
    """Toplam puanı sorulara yarım puanlık adımlarla, toplamı bozmadan böler.

    Basit bölme 6 soruda 16,67 puan verip toplamı 100,02 yapıyordu; kâğıdın
    üstünde yazan toplam ile soruların toplamı tutmuyordu. Yarım puan
    adımlarında dağıtıp artanı ilk sorulara eklemek hem tam toplar hem de
    öğrencinin gördüğü puanlar yuvarlak kalır.
    """
    if soru_sayisi <= 0:
        return []
    yarimlar = round(toplam * 2)
    taban, artan = divmod(yarimlar, soru_sayisi)
    return [(taban + (1 if i < artan else 0)) / 2 for i in range(soru_sayisi)]


def _havuzu_grupla(havuz: list[Soru], anahtarla) -> dict[str, list[Soru]]:
    gruplu: dict[str, list[Soru]] = defaultdict(list)
    for soru in havuz:
        gruplu[anahtarla(soru)].append(soru)
    return gruplu


def sorulari_sec(
    havuz: list[Soru],
    hedefler: dict[str, int],
    *,
    anahtarla=lambda s: s.kazanim_kodu,
    tohum: int = 0,
) -> tuple[list[Soru], list[str]]:
    """Hedef dağılıma göre havuzdan soru seçer.

    Yetersiz kalan başlıklar hata olarak değil UYARI olarak döner: öğretmen
    sınavı yine de üretip eksik soruyu elle eklemek isteyebilir. Sessizce
    başka bir başlıktan doldurmak, belirtke tablosunu yalancı çıkarır.
    """
    rastgele = random.Random(tohum)  # noqa: S311 - kriptografik değil, yeniden üretilebilirlik için
    gruplu = _havuzu_grupla(havuz, anahtarla)
    secilenler: list[Soru] = []
    uyarilar: list[str] = []

    for anahtar, adet in hedefler.items():
        adaylar = list(gruplu.get(anahtar, []))
        rastgele.shuffle(adaylar)
        if len(adaylar) < adet:
            uyarilar.append(
                f"{anahtar}: {adet} soru istendi, havuzda {len(adaylar)} var"
            )
        secilenler.extend(adaylar[:adet])
    return secilenler, uyarilar


def belirtke_kur(
    sorular: list[Soru], dagilim: dict[str, float], adlar: dict[str, str] | None = None
) -> list[BelirtkeSatiri]:
    """Seçilen sorulardan belirtke tablosunu üretir."""
    adlar = adlar or {}
    toplam_puan = sum(s.puan for s in sorular) or 1.0
    # Hedef yüzdeler seçimde zaten normalize ediliyor; tabloda ham hâlleriyle
    # gösterilirse "hedef %60 + %60" gibi toplamı 120 olan bir tablo çıkıyor ve
    # gerçekleşenle karşılaştırılamıyor.
    yuzde_toplami = sum(max(0.0, y) for y in dagilim.values()) or 1.0
    satirlar: list[BelirtkeSatiri] = []
    for anahtar, hedef in dagilim.items():
        ait = [s for s in sorular if _koda_ait(s.kazanim_kodu, anahtar)]
        satirlar.append(
            BelirtkeSatiri(
                anahtar=anahtar,
                ad=adlar.get(anahtar, anahtar),
                hedef_yuzde=round(100 * max(0.0, hedef) / yuzde_toplami, 1),
                soru_sayisi=len(ait),
                puan=round(100 * sum(s.puan for s in ait) / toplam_puan, 1),
            )
        )
    return satirlar


def gruplari_uret(
    sorular: list[Soru], gruplar: tuple[str, ...] = VARSAYILAN_GRUPLAR, *, tohum: int = 0
) -> dict[str, list[Soru]]:
    """Aynı soruları farklı sırayla dizerek A/B grupları üretir.

    İlk grup her zaman özgün sıradadır; cevap anahtarı hazırlarken referans
    noktası olması için. Sonraki gruplar sabit bir tohumla karıştırılır, yani
    aynı sınav yeniden üretildiğinde aynı sıra çıkar — yazdırılan kâğıtla
    kayıtlı cevap anahtarı ayrışmaz.
    """
    uretilen: dict[str, list[Soru]] = {}
    for sira, grup in enumerate(gruplar):
        if sira == 0:
            uretilen[grup] = list(sorular)
            continue
        karisik = list(sorular)
        random.Random(tohum + sira).shuffle(karisik)  # noqa: S311 - yeniden üretilebilir sıra
        uretilen[grup] = karisik
    return uretilen


def sinav_uret(
    *,
    ad: str,
    sube_adi: str,
    sinif: int,
    havuz: list[Soru],
    dagilim: dict[str, float],
    soru_sayisi: int,
    sure_dk: int = 40,
    gruplar: tuple[str, ...] = VARSAYILAN_GRUPLAR,
    toplam_puan: float = 100.0,
    adlar: dict[str, str] | None = None,
    tohum: int = 0,
) -> tuple[Sinav, list[str]]:
    if not havuz:
        raise SinavKurulamadi("Soru havuzu boş.")
    hedefler = soru_sayilarini_dagit(dagilim, soru_sayisi)
    secilenler, uyarilar = sorulari_sec(
        havuz, hedefler, anahtarla=lambda s: _tema_anahtari(s.kazanim_kodu, dagilim), tohum=tohum
    )
    if not secilenler:
        raise SinavKurulamadi("Verilen dağılıma uyan soru bulunamadı.")

    paylar = puanlari_dagit(toplam_puan, len(secilenler))
    puanli = [
        Soru(
            id=s.id,
            kazanim_kodu=s.kazanim_kodu,
            metin=s.metin,
            puan=pay,
            rubrik=s.rubrik,
            gorsel_yolu=s.gorsel_yolu,
            zorluk=s.zorluk,
        )
        for s, pay in zip(secilenler, paylar, strict=True)
    ]
    sinav = Sinav(
        ad=ad,
        sube_adi=sube_adi,
        sinif=sinif,
        sure_dk=sure_dk,
        sorular=puanli,
        belirtke=belirtke_kur(puanli, dagilim, adlar),
        gruplar=gruplari_uret(puanli, gruplar, tohum=tohum),
    )
    return sinav, uyarilar


def _koda_ait(kazanim_kodu: str, anahtar: str) -> bool:
    """Kazanım kodu, dağılım başlığının altında mı?

    Nokta sınırı olmadan `startswith` kullanılırsa "BİY.11.1.1" başlığı
    "BİY.11.1.10" kodunu da yakalıyor ve belirtke tablosunda soru iki kez
    sayılıyordu.
    """
    return kazanim_kodu == anahtar or kazanim_kodu.startswith(anahtar + ".")


def _tema_anahtari(kazanim_kodu: str, dagilim: dict[str, float]) -> str:
    """Kazanım kodunu dağılımdaki başlıkla eşler.

    Dağılım tema düzeyinde ("BİY.9.1") verilebilir; kazanım kodu ("BİY.9.1.4")
    onun altına düşer. Tam kazanım kodu verilmişse doğrudan eşleşir.
    """
    if kazanim_kodu in dagilim:
        return kazanim_kodu
    # Uzun başlık önce denenir: hem "BİY.9.1" hem "BİY.9.1.4" verilmişse
    # kazanım daha özel olana yazılmalı.
    for anahtar in sorted(dagilim, key=len, reverse=True):
        if _koda_ait(kazanim_kodu, anahtar):
            return anahtar
    return kazanim_kodu


# --- kazanım bazlı analiz -------------------------------------------------


@dataclass
class KazanimBasarisi:
    kazanim_kodu: str
    alinan: float
    tam: float

    @property
    def yuzde(self) -> float | None:
        if self.tam <= 0:
            return None
        return round(100 * self.alinan / self.tam, 1)

    @property
    def durum(self) -> str:
        oran = self.yuzde
        if oran is None:
            return "veri yok"
        if oran >= 70:
            return "iyi"
        if oran >= 50:
            return "orta"
        return "zayıf"


def ogrenci_kazanim_analizi(
    puanlar: list[tuple[str, float, float]],
) -> list[KazanimBasarisi]:
    """(kazanım kodu, alınan puan, tam puan) kayıtlarını kazanıma göre toplar."""
    toplam: dict[str, list[float]] = defaultdict(lambda: [0.0, 0.0])
    for kod, alinan, tam in puanlar:
        toplam[kod][0] += alinan
        toplam[kod][1] += tam
    return [
        KazanimBasarisi(kazanim_kodu=kod, alinan=round(a, 2), tam=round(t, 2))
        for kod, (a, t) in sorted(toplam.items())
    ]


def sinif_kazanim_analizi(
    kayitlar: list[tuple[int, str, float, float]],
) -> dict[str, KazanimBasarisi]:
    """(öğrenci id, kazanım kodu, alınan, tam) kayıtlarından sınıf ısı haritası."""
    toplam: dict[str, list[float]] = defaultdict(lambda: [0.0, 0.0])
    for _, kod, alinan, tam in kayitlar:
        toplam[kod][0] += alinan
        toplam[kod][1] += tam
    return {
        kod: KazanimBasarisi(kazanim_kodu=kod, alinan=round(a, 2), tam=round(t, 2))
        for kod, (a, t) in sorted(toplam.items())
    }


def zayif_kazanimlar(analiz: dict[str, KazanimBasarisi], esik: float = 50.0) -> list[str]:
    """Eşiğin altında kalan kazanımlar.

    Hiç puanlanmamış kazanım (yuzde None) listeye GİRMEZ: "ölçülmedi" ile
    "başarısız" aynı şey değil, ikisini karıştırmak öğretmeni olmayan bir
    eksiği telafi etmeye yönlendirir.
    """
    return [kod for kod, basari in analiz.items() if basari.yuzde is not None and basari.yuzde < esik]
