"""Dış API ve üretim tokenı kullanmayan, kitap-pasajı tabanlı yerel RAG."""

from __future__ import annotations

import json
import math
import re
from collections import Counter
from dataclasses import asdict, dataclass
from pathlib import Path

from .kitap import KitapPasaji, metin_cikar, pasajlara_bol

_KELIME = re.compile(r"[a-zA-ZçğıöşüÇĞİÖŞÜ]{2,}")
_DURAK = {
    "acaba", "ama", "ancak", "bana", "bazı", "bile", "bir", "biri", "biz",
    "bu", "buna", "bunu", "çok", "da", "daha", "de", "diye", "en", "gibi",
    "hangi", "hem", "her", "için", "ile", "ise", "kadar", "ki", "mı", "mi",
    "mu", "mü", "nasıl", "ne", "neden", "nedir", "olan", "olarak", "olduğunu",
    "ve", "veya", "ya", "yani",
}


def _terimler(metin: str) -> list[str]:
    return [
        k.casefold()
        for k in _KELIME.findall(metin)
        if k.casefold() not in _DURAK
    ]


def _kok_eslesir(sol: str, sag: str) -> bool:
    """Basit Türkçe çekim eklerinde tam sözcük kaçırmalarını azaltır."""
    return sol == sag or (
        min(len(sol), len(sag)) >= 5
        and (sol.startswith(sag) or sag.startswith(sol))
    )


@dataclass
class YerelRAGCevabi:
    soru_no: int
    cevap: str
    rubrik: list[str]
    kaynaklar: list[str]


class YerelRAGDeposu:
    """Küçük/orta ders kitabı koleksiyonları için kalıcı BM25-benzeri indeks."""

    def __init__(self, pasajlar: list[KitapPasaji]):
        self.pasajlar = pasajlar
        self._terim_sayilari = [Counter(_terimler(p.metin)) for p in pasajlar]
        belge_sayisi = max(1, len(pasajlar))
        belge_frekansi = Counter()
        for terimler in self._terim_sayilari:
            belge_frekansi.update(terimler.keys())
        self._idf = {
            terim: math.log(1.0 + (belge_sayisi - adet + 0.5) / (adet + 0.5))
            for terim, adet in belge_frekansi.items()
        }
        self._ortalama_boy = (
            sum(sum(x.values()) for x in self._terim_sayilari) / belge_sayisi
        )

    @classmethod
    def kur(cls, kaynaklar: list[str | Path]) -> "YerelRAGDeposu":
        pasajlar: list[KitapPasaji] = []
        for kaynak in kaynaklar:
            kaynak = Path(kaynak)
            ham = metin_cikar(kaynak)
            if len(_terimler(ham)) < 8:
                raise ValueError(
                    f"{kaynak.name}: yeterli seçilebilir metin çıkarılamadı. "
                    "Taranmış kitap için önce OCR uygulanmış PDF kullanın."
                )
            for sira, metin in enumerate(pasajlara_bol(ham, 12, 100)):
                pasajlar.append(
                    KitapPasaji(kaynak=kaynak.name, sira=sira, metin=metin)
                )
        if not pasajlar:
            raise ValueError("Kitaplardan yerel RAG pasajı çıkarılamadı.")
        return cls(pasajlar)

    def kaydet(self, dizin: str | Path) -> None:
        dizin = Path(dizin)
        dizin.mkdir(parents=True, exist_ok=True)
        (dizin / "yerel_pasajlar.jsonl").write_text(
            "\n".join(
                json.dumps(asdict(p), ensure_ascii=False) for p in self.pasajlar
            ),
            encoding="utf-8",
        )

    @classmethod
    def yukle(cls, dizin: str | Path) -> "YerelRAGDeposu":
        yol = Path(dizin) / "yerel_pasajlar.jsonl"
        pasajlar = [
            KitapPasaji(**json.loads(satir))
            for satir in yol.read_text(encoding="utf-8").splitlines()
            if satir.strip()
        ]
        return cls(pasajlar)

    @classmethod
    def hazir_mi(cls, dizin: str | Path) -> bool:
        yol = Path(dizin) / "yerel_pasajlar.jsonl"
        return yol.is_file() and yol.stat().st_size > 0

    def ilgili(self, sorgu: str, k: int = 5) -> list[tuple[KitapPasaji, float]]:
        sorgu_sayaci = Counter(_terimler(sorgu))
        if not sorgu_sayaci:
            return []
        puanlar = []
        k1, b = 1.5, 0.75
        for i, terimler in enumerate(self._terim_sayilari):
            boy = max(1, sum(terimler.values()))
            puan = 0.0
            for terim, qf in sorgu_sayaci.items():
                tf = terimler.get(terim, 0)
                idf = self._idf.get(terim, 0.0)
                if not tf:
                    eslesenler = [
                        (belge_terimi, adet)
                        for belge_terimi, adet in terimler.items()
                        if _kok_eslesir(terim, belge_terimi)
                    ]
                    if not eslesenler:
                        continue
                    belge_terimi, tf = max(
                        eslesenler,
                        key=lambda oge: oge[1] * self._idf.get(oge[0], 0.0),
                    )
                    idf = self._idf.get(belge_terimi, 0.0)
                payda = tf + k1 * (1 - b + b * boy / max(1.0, self._ortalama_boy))
                puan += idf * (tf * (k1 + 1) / payda) * min(2, qf)
            if puan > 0:
                puanlar.append((puan, i))
        puanlar.sort(reverse=True)
        return [(self.pasajlar[i], puan) for puan, i in puanlar[:k]]

    def cevap_uret(
        self, sorular: list[tuple[int, str, float]]
    ) -> list[YerelRAGCevabi]:
        cevaplar = []
        for no, soru, _puan in sorular:
            bulunan = self.ilgili(soru, k=6)
            if not bulunan:
                raise ValueError(f"{no}. soru için kitaplarda ilgili pasaj bulunamadı.")
            en_yuksek_puan = bulunan[0][1]
            bulunan = [
                (pasaj, puan)
                for pasaj, puan in bulunan
                if puan >= en_yuksek_puan * 0.65
            ]
            sorgu = set(_terimler(soru))
            cumle_adaylari = []
            for pasaj, puan in bulunan:
                cumleler = re.split(r"(?<=[.!?])\s+", pasaj.metin)
                for cumle in cumleler:
                    terimler = set(_terimler(cumle))
                    if len(terimler) < 3:
                        continue
                    ortak = sum(
                        max(
                            (
                                self._idf.get(cumle_terimi, self._idf.get(terim, 0.0))
                                for cumle_terimi in terimler
                                if _kok_eslesir(terim, cumle_terimi)
                            ),
                            default=0.0,
                        )
                        for terim in sorgu
                    )
                    cumle_adaylari.append(
                        (ortak + puan * 0.12, cumle.strip(), pasaj.kaynak, pasaj.sira)
                    )
            cumle_adaylari.sort(reverse=True)
            secilen = []
            gorulen = set()
            for _puan2, cumle, kaynak, sira in cumle_adaylari:
                anahtar = re.sub(r"\W+", " ", cumle.casefold()).strip()
                if anahtar in gorulen:
                    continue
                gorulen.add(anahtar)
                secilen.append((cumle, kaynak, sira))
                if len(secilen) == 3:
                    break
            if not secilen:
                pasaj, _ = bulunan[0]
                secilen = [(pasaj.metin, pasaj.kaynak, pasaj.sira)]
            cevap = " ".join(c[0] for c in secilen)
            rubrik = [c[0][:220].rstrip() for c in secilen]
            kaynaklar = list(
                dict.fromkeys(f"{kaynak} · pasaj {sira + 1}" for _, kaynak, sira in secilen)
            )
            cevaplar.append(YerelRAGCevabi(int(no), cevap, rubrik, kaynaklar))
        return cevaplar

    def durum(self) -> dict:
        return {
            "hazir": bool(self.pasajlar),
            "pasaj": len(self.pasajlar),
            "kitap": len({p.kaynak for p in self.pasajlar}),
        }
