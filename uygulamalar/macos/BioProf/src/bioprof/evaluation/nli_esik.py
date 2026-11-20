"""NLI hakemi için eşik taraması.

Altın set dört kategoriden oluşur: ``parafraz`` (bugün kelime-eşleşmenin
YANLIŞ elediği doğru iddialar — hakemin kazandırması beklenen küme) ve üç
"kötü" kategori (``polarite``, ``sayi``, ``karisim``) — bunlarda tek bir
yanlış kabul bile kapının varlık nedenini bozar.

Karar kuralı: kötü kategorilerde SIFIR yanlış kabul veren en düşük eşik
seçilir; parafraz geri çağırması o eşikte raporlanır.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

from bioprof.rag.nli import NliCift, NLIVerifier

KOTU_KATEGORILER = ("polarite", "sayi", "karisim")


@dataclass(frozen=True)
class EsikSonucu:
    esik: float
    parafraz_kabul: int
    parafraz_toplam: int
    kotu_kabul: int
    kotu_toplam: int
    kategori_kabul: dict[str, tuple[int, int]]

    @property
    def temiz(self) -> bool:
        return self.kotu_kabul == 0


@dataclass(frozen=True)
class TaramaRaporu:
    sonuclar: list[EsikSonucu]
    secilen: EsikSonucu | None


def altin_seti_yukle(yol: Path) -> list[dict[str, object]]:
    kayitlar = []
    for satir in yol.read_text(encoding="utf-8").splitlines():
        satir = satir.strip()
        if satir:
            kayitlar.append(json.loads(satir))
    return kayitlar


def esik_taramasi(
    kayitlar: list[dict[str, object]],
    *,
    model: str,
    karsi_esik: float,
    esikler: tuple[float, ...] = (0.5, 0.55, 0.6, 0.65, 0.7, 0.75, 0.8, 0.85, 0.9, 0.95),
) -> TaramaRaporu:
    """Tek model yüklemesiyle tüm eşikleri tarar.

    Model her eşik için yeniden koşulmaz: entailment/çelişki olasılıkları bir
    kez hesaplanır, eşikler olasılıklar üzerinde uygulanır.
    """
    # Ölçüm bilinçli bir hazırlık adımıdır: model yoksa burada İNDİRİLİR
    # (yalniz_yerel=False); üretim yolu ise yalnız yerelden yükler.
    dogrulayici = NLIVerifier(
        model, esik=0.0, karsi_esik=1.0, azami_cift=len(kayitlar), yalniz_yerel=False
    )
    # esik=0: toplu() kararı "entail_p >= kaydırılmış eşik ve celiski_p < karşı"
    # olduğu için burada ham olasılıklara ihtiyaç var; toplu() yerine iç API
    # kullanmamak adına her eşik için ayrı karar hesaplamak yerine, eşiği
    # kaydırma alanıyla taşıyoruz: cift.esik_kaydirma = hedef eşik.
    sonuclar: list[EsikSonucu] = []
    for esik in esikler:
        ciftler = [
            NliCift(
                iddia=str(kayit["iddia"]),
                kanit=str(kayit["kanit"]),
                esik_kaydirma=esik,
            )
            for kayit in kayitlar
        ]
        dogrulayici.karsi_esik = karsi_esik
        kararlar = dogrulayici.toplu(ciftler)
        kategori: dict[str, tuple[int, int]] = {}
        parafraz_kabul = parafraz_toplam = kotu_kabul = kotu_toplam = 0
        for kayit, karar in zip(kayitlar, kararlar, strict=True):
            ad = str(kayit["kategori"])
            kabul, toplam = kategori.get(ad, (0, 0))
            kategori[ad] = (kabul + (1 if karar else 0), toplam + 1)
            if ad == "parafraz":
                parafraz_toplam += 1
                parafraz_kabul += 1 if karar else 0
            elif ad in KOTU_KATEGORILER:
                kotu_toplam += 1
                kotu_kabul += 1 if karar else 0
        sonuclar.append(
            EsikSonucu(
                esik=esik,
                parafraz_kabul=parafraz_kabul,
                parafraz_toplam=parafraz_toplam,
                kotu_kabul=kotu_kabul,
                kotu_toplam=kotu_toplam,
                kategori_kabul=kategori,
            )
        )
    dogrulayici.birak()
    secilen = next((s for s in sonuclar if s.temiz), None)
    return TaramaRaporu(sonuclar=sonuclar, secilen=secilen)


def rapor_metni(rapor: TaramaRaporu) -> str:
    satirlar = ["eşik  parafraz-kabul  kötü-kabul  durum"]
    for s in rapor.sonuclar:
        durum = "TEMİZ" if s.temiz else "yanlış kabul var"
        satirlar.append(
            f"{s.esik:.2f}  {s.parafraz_kabul}/{s.parafraz_toplam}"
            f"            {s.kotu_kabul}/{s.kotu_toplam}       {durum}"
        )
    if rapor.secilen is not None:
        s = rapor.secilen
        satirlar.append(
            f"\nSEÇİLEN EŞİK: {s.esik:.2f} — kötü kategorilerde 0 yanlış kabul, "
            f"parafraz geri çağırması {s.parafraz_kabul}/{s.parafraz_toplam}."
        )
        for ad, (kabul, toplam) in sorted(s.kategori_kabul.items()):
            satirlar.append(f"  {ad}: {kabul}/{toplam} kabul")
    else:
        satirlar.append("\nHiçbir eşik kötü kategorileri sıfırlayamadı; NLI AÇILMAMALI.")
    return "\n".join(satirlar)
