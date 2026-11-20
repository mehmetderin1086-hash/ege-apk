"""Puanlama motoru değişikliğinin mevcut kâğıtlara etkisini ÖNCEDEN ölçer.

``anahtar_etkisini_onizle`` ile aynı sözleşme: depoya hiçbir şey yazmaz.
Fark, değişenin anahtar değil MOTOR olması (gömlemcinin açılması, eşiklerin
değişmesi, bu turdaki puanlama düzeltmeleri).

Bu rapor olmadan motor değişikliği sessiz bir toplu kaydırmadır: öğretmen
bambaşka bir sorunun anahtarına dokunduğu anda ``_anahtari_uygula`` tüm
kutuları yeni motorla yeniden puanlar ve eski notlar sessizce değişir.

**Kilit ölçü** ``ogretmen_puaniyla_uyum``: öğretmenin elle puan verdiği
kutular hazır bir altın settir. Yeni motor onlara daha mı yakın, daha mı
uzak? Veri toplanmasını beklemeden cevaplanabilen tek doğruluk sorusu budur.
"""

from __future__ import annotations

import statistics
from dataclasses import dataclass, field

from .yeniden_puanlama import (
    bilinen_terimleri_getir,
    metni_puanla,
    referans_pasajlari_getir,
)

# Kabul kapısı: rapor bu şartları sağlamazsa "açma" der.
AZAMI_DUSEN_ORAN = 0.05
AZAMI_MAE_KOTULESMESI = 0.0
# Öğretmen puanı referansı olmadan "kanıtsız" sayılan değişim oranı.
# Altındaki küçük oynamalar için kanıt aramak gereksiz sürtünme yaratır;
# üstünde ise ölçemediğimiz bir şeyi açmış oluruz.
KANITSIZ_AZAMI_DEGISIM_ORANI = 0.10


@dataclass
class MotorEtkisi:
    """Tek bir motor değişikliğinin ölçülen etkisi."""

    incelenen: int = 0
    degisen: int = 0
    yukselen: int = 0
    dusen: int = 0
    kuyruga_giren: int = 0
    kuyruktan_cikan: int = 0
    elle_dokunulmus_etkilenen: int = 0
    ornekler: list[dict] = field(default_factory=list)
    ogretmen_puaniyla_uyum: dict = field(default_factory=dict)

    @property
    def dusen_orani(self) -> float:
        return self.dusen / self.incelenen if self.incelenen else 0.0


def _elle_dokunuldu(satir) -> bool:
    """Öğretmen bu kutunun puanına gerçekten dokundu mu?

    ``duzeltilmis_metin`` tek başına kanıt değildir: program da o alanı
    yazıyor. Gerçek kanıt, son puanın otomatik puandan sapmasıdır.
    """
    otomatik = satir["otomatik_puan"]
    son = satir["son_puan"]
    if otomatik is None or son is None:
        return False
    return abs(float(son) - float(otomatik)) > 1e-6


def motor_etkisini_onizle(
    depo,
    sinav,
    *,
    yeni_gomlemci=None,
    eski_gomlemci=None,
    referans_indeks_dizini=None,
    ayar=None,
) -> dict:
    """Yeni motorun mevcut cevaplara etkisini hesaplar; DEPOYA YAZMAZ."""
    etki = MotorEtkisi()
    pasaj_onbellek: dict[int, list[str] | None] = {}
    terim_onbellek: dict[int, set[str] | None] = {}
    eski_farklar: list[float] = []
    yeni_farklar: list[float] = []

    for satir in depo.sinav_cevaplari(sinav.kimlik):
        soru_no = int(satir["soru_no"])
        try:
            sinav.soru(soru_no)
        except KeyError:
            continue
        metin = str(
            satir["duzeltilmis_metin"]
            if satir["duzeltilmis_metin"] is not None
            else satir["taninan_metin"] or ""
        )
        if soru_no not in pasaj_onbellek:
            pasaj_onbellek[soru_no] = referans_pasajlari_getir(
                referans_indeks_dizini, sinav.soru(soru_no).metin
            )
            terim_onbellek[soru_no] = bilinen_terimleri_getir(
                sinav, soru_no, referans_indeks_dizini
            )
        ortak = {
            "referans_pasajlari": pasaj_onbellek[soru_no],
            "bilinen_terimler": terim_onbellek[soru_no],
            "ayar": ayar,
        }
        try:
            eski = metni_puanla(sinav, soru_no, metin, gomlemci=eski_gomlemci, **ortak)
            yeni = metni_puanla(sinav, soru_no, metin, gomlemci=yeni_gomlemci, **ortak)
        except (KeyError, ValueError):
            continue

        etki.incelenen += 1
        fark = yeni.puan - eski.puan
        if abs(fark) > 1e-9:
            etki.degisen += 1
            if fark > 0:
                etki.yukselen += 1
            else:
                etki.dusen += 1
            if _elle_dokunuldu(satir):
                etki.elle_dokunulmus_etkilenen += 1
            etki.ornekler.append(
                {
                    "soru_no": soru_no,
                    "kagit_id": satir["kagit_id"],
                    "metin": metin[:160],
                    "eski_puan": round(float(eski.puan), 2),
                    "yeni_puan": round(float(yeni.puan), 2),
                    "delta": round(float(fark), 2),
                }
            )
        if eski.incele and not yeni.incele:
            etki.kuyruktan_cikan += 1
        elif yeni.incele and not eski.incele:
            etki.kuyruga_giren += 1

        # Öğretmenin elle verdiği puan = referans doğru cevap.
        if _elle_dokunuldu(satir):
            ogretmen = float(satir["son_puan"])
            eski_farklar.append(abs(eski.puan - ogretmen))
            yeni_farklar.append(abs(yeni.puan - ogretmen))

    if eski_farklar:
        etki.ogretmen_puaniyla_uyum = {
            "ornek": len(eski_farklar),
            "mae_eski": round(statistics.mean(eski_farklar), 3),
            "mae_yeni": round(statistics.mean(yeni_farklar), 3),
            "iyilesme": round(
                statistics.mean(eski_farklar) - statistics.mean(yeni_farklar), 3
            ),
        }

    etki.ornekler.sort(key=lambda x: -abs(x["delta"]))
    etki.ornekler = etki.ornekler[:10]
    return _karar_ekle(etki)


def _karar_ekle(etki: MotorEtkisi) -> dict:
    """Ölçüme bakıp "açılabilir mi" sorusunu gerekçeleriyle cevaplar."""
    engeller: list[str] = []
    uyum = etki.ogretmen_puaniyla_uyum
    degisim_orani = (
        etki.degisen / etki.incelenen if etki.incelenen else 0.0
    )
    if uyum:
        kotulesme = uyum["mae_yeni"] - uyum["mae_eski"]
        if kotulesme > AZAMI_MAE_KOTULESMESI:
            engeller.append(
                f"Öğretmen puanlarından uzaklaşıyor: MAE {uyum['mae_eski']} → "
                f"{uyum['mae_yeni']} ({uyum['ornek']} elle puanlanmış cevap)."
            )
    elif degisim_orani > KANITSIZ_AZAMI_DEGISIM_ORANI:
        # "Ölçerek aç" ilkesi: ölçemiyorsak açmayız. Elle puanlanmış kutu
        # yoksa değişimin doğru yönde olduğunu gösteren hiçbir kanıt yok;
        # yalnız "düşen yok" demek yeterli değildir, yükselen puanlar da
        # yanlış olabilir.
        engeller.append(
            f"Cevapların %{degisim_orani * 100:.0f}'i değişiyor ama karşılaştırılacak "
            "öğretmen puanı yok. Birkaç cevabı elle puanlayın, rapor sonra "
            "değişimin doğru yönde olduğunu gösterebilsin."
        )
    if etki.elle_dokunulmus_etkilenen:
        engeller.append(
            f"{etki.elle_dokunulmus_etkilenen} elle puanlanmış cevabın program "
            "puanı değişiyor; öğretmen kararı bulanıklaşır."
        )
    if etki.dusen_orani > AZAMI_DUSEN_ORAN:
        engeller.append(
            f"Cevapların %{etki.dusen_orani * 100:.1f}'inde puan düşüyor "
            f"(sınır %{AZAMI_DUSEN_ORAN * 100:.0f})."
        )
    return {
        "incelenen": etki.incelenen,
        "degisen": etki.degisen,
        "yukselen": etki.yukselen,
        "dusen": etki.dusen,
        "dusen_orani": round(etki.dusen_orani, 4),
        "kuyruga_giren": etki.kuyruga_giren,
        "kuyruktan_cikan": etki.kuyruktan_cikan,
        "elle_dokunulmus_etkilenen": etki.elle_dokunulmus_etkilenen,
        "ogretmen_puaniyla_uyum": uyum,
        "ornekler": etki.ornekler,
        "acilabilir": not engeller,
        "engeller": engeller,
    }
