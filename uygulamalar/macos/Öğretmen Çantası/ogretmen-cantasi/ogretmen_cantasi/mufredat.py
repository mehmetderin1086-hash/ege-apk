"""Müfredat verisine erişim.

Veri `veri/mufredat_*.json` dosyalarından gelir ve salt okunurdur; resmî
programın kendisidir, kullanıcı düzenlemez. Birden fazla müfredat sürümü aynı
anda yüklü olabilir: 2026-2027'de 9-11. sınıflar Maarif Modeli'ne, 12. sınıf
2018 programına tabi (bkz. `SINIF_SURUMLERI`).
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

VERI_DIZINI = Path(__file__).resolve().parents[1] / "veri"

MAARIF_2024 = "maarif_2024"
MFP_2018 = "mfp_2018"

# Paket içi emniyet varsayılanı. Asıl eşleme `mufredat_gecerlilik.json` içinde
# veri olarak tutulur; yeni öğretim yılında kod değiştirmek gerekmez.
SINIF_SURUMLERI: dict[str, dict[int, str]] = {
    "2026-2027": {9: MAARIF_2024, 10: MAARIF_2024, 11: MAARIF_2024, 12: MFP_2018},
    "2027-2028": {9: MAARIF_2024, 10: MAARIF_2024, 11: MAARIF_2024, 12: MAARIF_2024},
}
VARSAYILAN_SURUM = MAARIF_2024


class MufredatYok(LookupError):
    """İstenen müfredat sürümü ya da sınıf düzeyi yüklü değil."""


@dataclass(frozen=True)
class SurecBileseni:
    harf: str
    ifade: str


@dataclass(frozen=True)
class OgrenmeCiktisi:
    kod: str
    ifade: str
    surec_bilesenleri: tuple[SurecBileseni, ...]
    tema_no: int
    tema_adi: str
    sinif: int

    @property
    def agirlik(self) -> int:
        """Ders saati dağıtımında kullanılan görece ağırlık.

        Süreç bileşeni sayısı, kazanımın kapsamı için elimizdeki tek nesnel
        ölçü; resmî program kazanım başına saat vermiyor, yalnız tema toplamını
        veriyor. En az 1 döner ki bileşensiz bir kazanım sıfır saat almasın.
        """
        return max(1, len(self.surec_bilesenleri))


@dataclass(frozen=True)
class Tema:
    no: int
    ad: str
    aciklama: str
    ders_saati: int
    alan_becerileri: tuple[str, ...]
    kavramsal_beceriler: tuple[str, ...]
    egilimler: tuple[str, ...]
    sosyal_duygusal_beceriler: tuple[str, ...]
    degerler: tuple[str, ...]
    okuryazarlik_becerileri: tuple[str, ...]
    disiplinler_arasi: tuple[str, ...]
    beceriler_arasi: tuple[str, ...]
    icerik_cercevesi: str
    anahtar_kavramlar: tuple[str, ...]
    ogrenme_kanitlari: str
    temel_kabuller: str
    on_degerlendirme: str
    kopru_kurma: str
    zenginlestirme: str
    destekleme: str
    ogrenme_ciktilari: tuple[OgrenmeCiktisi, ...]
    ogretme_uygulamalari: dict[str, str]

    def uygulama(self, kod: str) -> str:
        return self.ogretme_uygulamalari.get(kod, "")


@dataclass(frozen=True)
class SinifDuzeyi:
    sinif: int
    haftalik_ders_saati: int
    okul_temelli_planlama_saati: int
    toplam_ders_saati: int
    temalar: tuple[Tema, ...]

    @property
    def ogrenme_ciktilari(self) -> tuple[OgrenmeCiktisi, ...]:
        return tuple(c for t in self.temalar for c in t.ogrenme_ciktilari)


@dataclass(frozen=True)
class Mufredat:
    surum: str
    ad: str
    ders: str
    siniflar: dict[int, SinifDuzeyi]

    def duzey(self, sinif: int) -> SinifDuzeyi:
        try:
            return self.siniflar[sinif]
        except KeyError:
            raise MufredatYok(f"{self.surum} sürümünde {sinif}. sınıf yok") from None

    def cikti(self, kod: str) -> OgrenmeCiktisi:
        for duzey in self.siniflar.values():
            for cikti in duzey.ogrenme_ciktilari:
                if cikti.kod == kod:
                    return cikti
        raise MufredatYok(f"{kod} bulunamadı")


def _tema_kur(ham: dict, sinif: int) -> Tema:
    ciktilar = tuple(
        OgrenmeCiktisi(
            kod=c["kod"],
            ifade=c["ifade"],
            surec_bilesenleri=tuple(
                SurecBileseni(b["harf"], b["ifade"]) for b in c["surec_bilesenleri"]
            ),
            tema_no=ham["no"],
            tema_adi=ham["ad"],
            sinif=sinif,
        )
        for c in ham["ogrenme_ciktilari"]
    )
    return Tema(
        no=ham["no"],
        ad=ham["ad"],
        aciklama=ham["aciklama"],
        ders_saati=ham["ders_saati"],
        alan_becerileri=tuple(ham["alan_becerileri"]),
        kavramsal_beceriler=tuple(ham["kavramsal_beceriler"]),
        egilimler=tuple(ham["egilimler"]),
        sosyal_duygusal_beceriler=tuple(ham["sosyal_duygusal_beceriler"]),
        degerler=tuple(ham["degerler"]),
        okuryazarlik_becerileri=tuple(ham["okuryazarlik_becerileri"]),
        disiplinler_arasi=tuple(ham["disiplinler_arasi"]),
        beceriler_arasi=tuple(ham["beceriler_arasi"]),
        icerik_cercevesi=ham["icerik_cercevesi"],
        anahtar_kavramlar=tuple(ham["anahtar_kavramlar"]),
        ogrenme_kanitlari=ham["ogrenme_kanitlari"],
        temel_kabuller=ham["temel_kabuller"],
        on_degerlendirme=ham["on_degerlendirme"],
        kopru_kurma=ham["kopru_kurma"],
        zenginlestirme=ham["zenginlestirme"],
        destekleme=ham["destekleme"],
        ogrenme_ciktilari=ciktilar,
        ogretme_uygulamalari=dict(ham["ogretme_uygulamalari"]),
    )


@lru_cache(maxsize=8)
def yukle(surum: str = VARSAYILAN_SURUM, dizin: Path | None = None) -> Mufredat:
    yol = (dizin or VERI_DIZINI) / f"mufredat_{surum}.json"
    if not yol.is_file():
        raise MufredatYok(
            f"{surum} müfredat dosyası yok: {yol}. "
            "12. sınıf 2018 programı için belge alındığında scripts/mufredat_cikar.py koşulur."
        )
    ham = json.loads(yol.read_text(encoding="utf-8"))
    siniflar = {
        d["sinif"]: SinifDuzeyi(
            sinif=d["sinif"],
            haftalik_ders_saati=d["haftalik_ders_saati"],
            okul_temelli_planlama_saati=d["okul_temelli_planlama_saati"],
            toplam_ders_saati=d["toplam_ders_saati"],
            temalar=tuple(_tema_kur(t, d["sinif"]) for t in d["temalar"]),
        )
        for d in ham["siniflar"]
    }
    return Mufredat(surum=ham["surum"], ad=ham["ad"], ders=ham["ders"], siniflar=siniflar)


def surum_sec(ogretim_yili: str, sinif: int) -> str:
    """Öğretim yılı ve sınıfa göre yürürlükteki müfredat sürümünü verir."""
    esleme = sinif_surumleri()
    return esleme.get(ogretim_yili, {}).get(sinif, VARSAYILAN_SURUM)


def mevcut_surumler(dizin: Path | None = None) -> list[str]:
    kok = dizin or VERI_DIZINI
    return sorted(y.stem.removeprefix("mufredat_") for y in kok.glob("mufredat_*.json"))


@lru_cache(maxsize=1)
def sinif_surumleri(dizin: Path | None = None) -> dict[str, dict[int, str]]:
    """Kaynak künyeli öğretim yılı/sınıf eşlemesini okur."""
    yol = (dizin or VERI_DIZINI) / "mufredat_gecerlilik.json"
    if not yol.is_file():
        return SINIF_SURUMLERI
    ham = json.loads(yol.read_text(encoding="utf-8"))
    return {
        yil: {int(sinif): str(surum) for sinif, surum in siniflar.items()}
        for yil, siniflar in ham.get("school_years", {}).items()
    }


def kaynak_kunyesi(surum: str, dizin: Path | None = None) -> dict:
    yol = (dizin or VERI_DIZINI) / "mufredat_kaynaklari.json"
    if not yol.is_file():
        return {}
    ham = json.loads(yol.read_text(encoding="utf-8"))
    return dict(ham.get("sources", {}).get(surum, {}))
