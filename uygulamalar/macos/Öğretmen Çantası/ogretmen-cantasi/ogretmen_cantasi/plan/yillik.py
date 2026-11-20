"""Ünitelendirilmiş yıllık plan üretimi.

Tema saatleri kazanımlara dağıtılır, kazanımlar da öğretim yılının haftalarına
sırayla yerleştirilir. Tatile denk gelen haftalar ders almaz ama planda görünür;
müfettişe verilen planda tatil haftalarının gösterilmesi beklenir.
"""

from __future__ import annotations

from dataclasses import dataclass, field

from ..mufredat import OgrenmeCiktisi, SinifDuzeyi, Tema
from ..takvim import Hafta
from . import oneriler

TUR_TEMA = "tema"
TUR_OKUL_TEMELLI = "okul_temelli"
TUR_TATIL = "tatil"


@dataclass
class Birim:
    """Haftalara yerleştirilecek bir ders saati bloğu."""

    tur: str
    saat: int
    tema: Tema | None = None
    kazanim: OgrenmeCiktisi | None = None
    baslik: str = ""


@dataclass
class PlanSatiri:
    sira: int
    hafta_no: int
    donem: int
    ay: str
    baslangic: str
    bitis: str
    ders_saati: int
    tur: str
    tema_no: int | None = None
    tema_adi: str = ""
    kazanim_kodlari: list[str] = field(default_factory=list)
    kazanim_ifadeleri: list[str] = field(default_factory=list)
    surec_bilesenleri: list[str] = field(default_factory=list)
    icerik: str = ""
    yontem_teknik: list[str] = field(default_factory=list)
    arac_gerec: list[str] = field(default_factory=list)
    olcme_degerlendirme: list[str] = field(default_factory=list)
    aciklama: str = ""
    # MEB'in ünitelendirilmiş plan biçiminde ayrı sütun olarak beklenen iki
    # alan: derste ilişkilendirilen diğer disiplinler ve o haftaya düşen
    # belirli gün/haftalar.
    disiplinler_arasi: list[str] = field(default_factory=list)
    belirli_gunler: list[str] = field(default_factory=list)
    # Önceki haftalardan sürüp gelen kazanım kodları. Belgede tam metin yerine
    # "(devam)" yazılır; aynı kazanımın metni üst üste üç hafta tekrarlanınca
    # plan okunmaz oluyordu.
    devam_kodlari: list[str] = field(default_factory=list)
    # Kazanım kodu → o kazanımın süreç bileşenleri. Düz listeden ayrı tutuluyor
    # ki devam eden kazanımların bileşenleri satırdan çıkarılabilsin.
    bilesen_haritasi: dict[str, list[str]] = field(default_factory=dict)

    def yeni_kazanim_bilesenleri(self) -> list[str]:
        """Yalnız bu hafta BAŞLAYAN kazanımların süreç bileşenleri."""
        yeniler = [k for k in self.kazanim_kodlari if k not in self.devam_kodlari]
        if not self.bilesen_haritasi:
            return list(self.surec_bilesenleri) if yeniler else []
        return [b for kod in yeniler for b in self.bilesen_haritasi.get(kod, [])]

    @property
    def kazanim_metni(self) -> str:
        return "\n".join(
            f"{kod} {ifade}"
            for kod, ifade in zip(self.kazanim_kodlari, self.kazanim_ifadeleri, strict=False)
        )


def saatleri_dagit(toplam: int, agirliklar: list[int]) -> list[int]:
    """Tema saatini kazanımlara, toplamı bozmadan dağıtır.

    En büyük kalan yöntemi kullanılır: önce tam bölümler verilir, artan saatler
    ondalık kısmı en büyük olanlara birer birer eklenir. Böylece parçaların
    toplamı her zaman temanın resmî ders saatine eşit çıkar.
    """
    if not agirliklar:
        return []
    agirlik_toplami = sum(agirliklar)
    if agirlik_toplami == 0:
        return [0] * len(agirliklar)

    ham = [toplam * a / agirlik_toplami for a in agirliklar]
    paylar = [int(h) for h in ham]
    kalan = toplam - sum(paylar)
    sirali = sorted(range(len(ham)), key=lambda i: ham[i] - paylar[i], reverse=True)
    for i in sirali[:kalan]:
        paylar[i] += 1
    return paylar


def birimleri_kur(duzey: SinifDuzeyi) -> list[Birim]:
    """Sınıf düzeyinin tüm ders saatini sıralı bloklara çevirir.

    Okul temelli planlama saati temalar arasında bölünür: yarısı birinci tema
    bitiminde, kalanı yıl sonunda. Program bu süreyi "eğitim öğretim yılı içinde
    planlanır ve yıllık planlarda ifade edilir" diye tanımlıyor; tek blok hâlinde
    yıl sonuna yığmak plana da öğretime de uymuyor.
    """
    birimler: list[Birim] = []
    okul_temelli = duzey.okul_temelli_planlama_saati
    tema_sayisi = max(1, len(duzey.temalar))
    okul_paylari = saatleri_dagit(okul_temelli, [1] * tema_sayisi)

    for sira, tema in enumerate(duzey.temalar):
        agirliklar = [c.agirlik for c in tema.ogrenme_ciktilari]
        paylar = saatleri_dagit(tema.ders_saati, agirliklar)
        for kazanim, saat in zip(tema.ogrenme_ciktilari, paylar, strict=True):
            if saat > 0:
                birimler.append(Birim(TUR_TEMA, saat, tema=tema, kazanim=kazanim))
        if okul_paylari[sira] > 0:
            birimler.append(
                Birim(
                    TUR_OKUL_TEMELLI,
                    okul_paylari[sira],
                    tema=tema,
                    baslik="Okul temelli planlama",
                )
            )
    return birimler


def _tatil_metni(hafta: Hafta) -> str:
    return ", ".join(sorted({t.aciklama for t in hafta.gercek_tatiller}))


def _tatil_satiri(sira: int, hafta: Hafta) -> PlanSatiri:
    aciklamalar = sorted({t.aciklama for t in hafta.gercek_tatiller})
    return PlanSatiri(
        sira=sira,
        hafta_no=hafta.no,
        donem=hafta.donem,
        ay=hafta.ay,
        baslangic=hafta.baslangic.isoformat(),
        bitis=hafta.bitis.isoformat(),
        ders_saati=0,
        tur=TUR_TATIL,
        aciklama=", ".join(aciklamalar) or "Ders yapılmadı",
    )


def _satir_kur(sira: int, hafta: Hafta, parcalar: list[tuple[Birim, int]]) -> PlanSatiri:
    kazanimlar = [(b.kazanim, saat) for b, saat in parcalar if b.kazanim is not None]
    # Tema, ÖNCE kazanımı olan birimden alınır: bir haftaya hem önceki temanın
    # okul temelli bloğu hem yeni temanın ilk kazanımı düştüğünde, "ilk birimin
    # teması" kuralı satırı yanlış temaya yazıyordu.
    ilk_tema = next(
        (b.tema for b, _ in parcalar if b.kazanim is not None and b.tema is not None),
        next((b.tema for b, _ in parcalar if b.tema is not None), None),
    )
    okul_temelli_saat = sum(saat for b, saat in parcalar if b.tur == TUR_OKUL_TEMELLI)

    uygulama_metni = " ".join(
        b.tema.uygulama(b.kazanim.kod) for b, _ in parcalar if b.tema and b.kazanim
    )
    kanit_metni = " ".join({b.tema.ogrenme_kanitlari for b, _ in parcalar if b.tema})

    satir = PlanSatiri(
        sira=sira,
        hafta_no=hafta.no,
        donem=hafta.donem,
        ay=hafta.ay,
        baslangic=hafta.baslangic.isoformat(),
        bitis=hafta.bitis.isoformat(),
        ders_saati=sum(saat for _, saat in parcalar),
        tur=TUR_OKUL_TEMELLI if not kazanimlar and okul_temelli_saat else TUR_TEMA,
        tema_no=ilk_tema.no if ilk_tema else None,
        tema_adi=ilk_tema.ad if ilk_tema else "",
        kazanim_kodlari=[k.kod for k, _ in kazanimlar],
        kazanim_ifadeleri=[k.ifade for k, _ in kazanimlar],
        surec_bilesenleri=[
            f"{b.harf}) {b.ifade}" for k, _ in kazanimlar for b in k.surec_bilesenleri
        ],
        bilesen_haritasi={
            k.kod: [f"{b.harf}) {b.ifade}" for b in k.surec_bilesenleri] for k, _ in kazanimlar
        },
        icerik=ilk_tema.icerik_cercevesi if ilk_tema else "",
        yontem_teknik=oneriler.yontemler(uygulama_metni),
        arac_gerec=oneriler.araclar(uygulama_metni),
        olcme_degerlendirme=oneriler.olcme_araclari(kanit_metni),
        disiplinler_arasi=list(ilk_tema.disiplinler_arasi) if ilk_tema else [],
        belirli_gunler=hafta.belirli_gun_adlari,
    )
    if okul_temelli_saat and kazanimlar:
        satir.aciklama = f"Okul temelli planlama: {okul_temelli_saat} saat"
    elif okul_temelli_saat:
        satir.aciklama = (
            "Zümre kararıyla belirlenen çalışmalar (okul dışı öğrenme etkinlikleri, "
            "araştırma ve gözlem, proje çalışmaları, mesleki rehberlik)"
        )
    tatil_metni = _tatil_metni(hafta)
    if tatil_metni:
        satir.aciklama = f"{satir.aciklama} — {tatil_metni}".strip(" —")
    return satir


def yillik_plan_uret(duzey: SinifDuzeyi, haftalar: list[Hafta]) -> list[PlanSatiri]:
    """Kazanımları haftalara yerleştirip plan satırlarını üretir."""
    birimler = birimleri_kur(duzey)
    kuyruk: list[tuple[Birim, int]] = [(b, b.saat) for b in birimler]
    satirlar: list[PlanSatiri] = []
    imlec = 0

    for hafta in haftalar:
        sira = len(satirlar) + 1
        if hafta.ders_saati <= 0:
            satirlar.append(_tatil_satiri(sira, hafta))
            continue

        kalan_saat = hafta.ders_saati
        parcalar: list[tuple[Birim, int]] = []
        while kalan_saat > 0 and imlec < len(kuyruk):
            birim, kalan_birim = kuyruk[imlec]
            alinan = min(kalan_saat, kalan_birim)
            parcalar.append((birim, alinan))
            kalan_saat -= alinan
            if alinan == kalan_birim:
                imlec += 1
            else:
                kuyruk[imlec] = (birim, kalan_birim - alinan)

        if not parcalar:
            # Müfredat bitti, yıl bitmedi: kalan haftalar telafi/değerlendirme.
            satir = _tatil_satiri(sira, hafta)
            satir.ders_saati = hafta.ders_saati
            satir.tur = TUR_OKUL_TEMELLI
            # Tatil açıklaması EZİLMEZ: kısmi tatili olan bir hafta hem tekrar
            # hem tatil taşıyabilir, ikisini de göstermek gerekir.
            satir.aciklama = "; ".join(
                p for p in ("Genel tekrar ve değerlendirme", _tatil_metni(hafta)) if p
            )
            satirlar.append(satir)
            continue

        satir = _satir_kur(sira, hafta, parcalar)
        if kalan_saat > 0:
            # Müfredat haftanın ortasında bitti: kalan saatler kaybolmasın.
            satir.ders_saati = hafta.ders_saati
            satir.aciklama = "; ".join(
                p for p in (satir.aciklama, f"Genel tekrar: {kalan_saat} saat") if p
            )
        satirlar.append(satir)

    _devamlari_isaretle(satirlar)
    return satirlar


def _devamlari_isaretle(satirlar: list[PlanSatiri]) -> None:
    gorulen: set[str] = set()
    for satir in satirlar:
        satir.devam_kodlari = [k for k in satir.kazanim_kodlari if k in gorulen]
        gorulen.update(satir.kazanim_kodlari)


def kapsam_raporu(duzey: SinifDuzeyi, satirlar: list[PlanSatiri]) -> dict:
    """Planın müfredatı ne kadar kapsadığını söyler.

    Öğretim yılı müfredattan kısa kaldığında (ders programı eksik girilmişse ya
    da çok gün tatil işaretlenmişse) kuyruğun sonundaki kazanımlar plana hiç
    girmiyor. Bu sessiz kalırsa öğretmen eksik planı fark etmeden teslim eder.
    """
    plandaki = {kod for s in satirlar for kod in s.kazanim_kodlari}
    tumu = [c.kod for c in duzey.ogrenme_ciktilari]
    eksik = [kod for kod in tumu if kod not in plandaki]
    return {
        "toplam": len(tumu),
        "kapsanan": len(tumu) - len(eksik),
        "eksik": eksik,
        "tam": not eksik,
    }


def plan_ozeti(satirlar: list[PlanSatiri]) -> dict[str, int]:
    return {
        "hafta": len(satirlar),
        "ders_saati": sum(s.ders_saati for s in satirlar),
        "tatil_haftasi": sum(1 for s in satirlar if s.tur == TUR_TATIL),
        "kazanim": len({kod for s in satirlar for kod in s.kazanim_kodlari}),
    }


def aylik_ozet(satirlar: list[PlanSatiri]) -> list[dict]:
    """Yıllık planın ay kırılımı — ayrı bir plan değil, aynı planın görünümü."""
    aylar: list[dict] = []
    for satir in satirlar:
        if not aylar or aylar[-1]["ay"] != satir.ay:
            aylar.append(
                {"ay": satir.ay, "donem": satir.donem, "ders_saati": 0, "kazanimlar": [], "haftalar": 0}
            )
        aylar[-1]["ders_saati"] += satir.ders_saati
        aylar[-1]["haftalar"] += 1
        for kod in satir.kazanim_kodlari:
            if kod not in aylar[-1]["kazanimlar"]:
                aylar[-1]["kazanimlar"].append(kod)
    return aylar
