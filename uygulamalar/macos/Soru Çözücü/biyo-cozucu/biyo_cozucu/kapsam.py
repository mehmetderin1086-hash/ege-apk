"""Hafıza kapsamı: hangi konu × çözüm türü hücresi boş?

Hafızayı büyütmenin en pahalı yolu rastgele örnek eklemektir. Erişim katmanı
örnekleri **çözüm türü** uyumuna göre sıralıyor (bkz. `hafiza/getirme.py`);
bir tür için hiç örnek yoksa o türdeki sorular hep yapı uyumsuz kanıtla
çözülür. Bu modül eksiği isimlendirip sıraya koyar.
"""

from __future__ import annotations

from dataclasses import dataclass

from .hafiza.etiketleme import KONU_IPUCLARI
from .modeller import COZUM_TURLERI

# Eşikler `docs/egitim_runbook.md`'den: RAG'ın kendini göstermesi için ~50,
# LoRA'nın üslup değil muhakeme öğrenmesi için ~200 örnek.
RAG_ESIGI = 50
LORA_ESIGI = 200


@dataclass(frozen=True)
class Bosluk:
    konu: str
    cozum_turu: str
    adet: int


@dataclass
class KapsamRaporu:
    toplam: int
    hucre_sayisi: int
    dolu_hucre: int
    tur_dagilimi: dict[str, int]
    konu_dagilimi: dict[str, int]
    bos_turler: list[str]
    bos_konular: list[str]
    oneriler: list[Bosluk]

    @property
    def hucre_orani(self) -> float:
        return self.dolu_hucre / self.hucre_sayisi if self.hucre_sayisi else 0.0

    def esige_kalan(self, esik: int) -> int:
        return max(0, esik - self.toplam)

    def metin(self) -> str:
        satirlar = [
            f"Örnek: {self.toplam} · RAG eşiğine {self.esige_kalan(RAG_ESIGI)} · "
            f"LoRA eşiğine {self.esige_kalan(LORA_ESIGI)} kaldı",
            f"Kapsanan hücre: {self.dolu_hucre}/{self.hucre_sayisi} "
            f"({self.hucre_orani:.0%})",
        ]
        if self.bos_turler:
            satirlar.append(
                "Hiç örneği olmayan çözüm türü (en öncelikli eksik): "
                + ", ".join(self.bos_turler)
            )
        if self.oneriler:
            satirlar.append("Bu türlerde eksik konular:")
            satirlar.extend(
                f"  {o.konu or '(konusuz)':30s} {o.cozum_turu}" for o in self.oneriler
            )
        return "\n".join(satirlar)


def kapsami_cikar(
    matris: dict[tuple[str, str], int], *, oneri_sayisi: int = 10
) -> KapsamRaporu:
    """`Depo.kapsam_matrisi()` çıktısını okunur bir rapora çevirir."""
    konular = list(KONU_IPUCLARI)
    turler = list(COZUM_TURLERI)

    tur_dagilimi = dict.fromkeys(turler, 0)
    konu_dagilimi = dict.fromkeys(konular, 0)
    toplam = 0
    for (konu, tur), adet in matris.items():
        toplam += adet
        if tur in tur_dagilimi:
            tur_dagilimi[tur] += adet
        if konu in konu_dagilimi:
            konu_dagilimi[konu] += adet

    bos_turler = [tur for tur, adet in tur_dagilimi.items() if not adet]
    bos_konular = [konu for konu, adet in konu_dagilimi.items() if not adet]

    dolu_hucre = sum(
        1
        for konu in konular
        for tur in turler
        if matris.get((konu, tur), 0) > 0
    )

    # Öneriler YALNIZ en az bir örneği olan türler için üretiliyor. Hiç örneği
    # olmayan bir tür zaten `bos_turler`de ayrıca ve daha güçlü biçimde
    # bildiriliyor; ona ayrıca konu eşlemek "destek ve hareket × kalıtım
    # hesabı" gibi biyolojik olarak anlamsız çiftler doğuruyordu. Tür varken
    # eksik olan konu ise gerçek ve yazılabilir bir boşluktur.
    #
    # Konu seçiminde çeşitlilik gözetiliyor: her tür için ayrı ayrı "en boş
    # konu" seçilseydi liste baştan sona aynı konuyu önerirdi.
    oneriler: list[Bosluk] = []
    kullanilan_konular: set[str] = set()
    for tur in sorted(turler, key=lambda t: (tur_dagilimi[t], t)):
        if not tur_dagilimi[tur]:
            continue
        adaylar = [
            konu for konu in sorted(konular, key=lambda k: (konu_dagilimi[k], k))
            if matris.get((konu, tur), 0) == 0
        ]
        if not adaylar:
            continue
        secilen = next((k for k in adaylar if k not in kullanilan_konular), adaylar[0])
        kullanilan_konular.add(secilen)
        oneriler.append(Bosluk(konu=secilen, cozum_turu=tur, adet=0))
    oneriler = oneriler[:oneri_sayisi]

    return KapsamRaporu(
        toplam=toplam,
        hucre_sayisi=len(konular) * len(turler),
        dolu_hucre=dolu_hucre,
        tur_dagilimi=tur_dagilimi,
        konu_dagilimi=konu_dagilimi,
        bos_turler=bos_turler,
        bos_konular=bos_konular,
        oneriler=oneriler,
    )
