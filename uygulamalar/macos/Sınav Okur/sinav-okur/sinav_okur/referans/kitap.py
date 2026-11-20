"""Referans kitap alımı, pasaj bölme, gömme indeksi ve erişim (retrieval)."""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path

import numpy as np

from ..metin import nfc
from ..puanlama.gomme import Gomlemci, kosinus


@dataclass
class KitapPasaji:
    kaynak: str      # dosya adı
    sira: int        # kaynak içindeki pasaj sırası
    metin: str


def metin_cikar(yol: str | Path) -> str:
    """PDF veya düz metin dosyasından ham metni çıkarır."""
    yol = Path(yol)
    if yol.suffix.lower() == ".pdf":
        import pypdfium2 as pdfium

        belge = pdfium.PdfDocument(str(yol))
        try:
            parcalar = []
            for sayfa in belge:
                metin_sayfa = sayfa.get_textpage()
                parcalar.append(metin_sayfa.get_text_range())
                metin_sayfa.close()
            return nfc("\n".join(parcalar))
        finally:
            belge.close()
    return nfc(yol.read_text(encoding="utf-8", errors="ignore"))


def pasajlara_bol(
    metin: str, min_kelime: int = 12, max_kelime: int = 80
) -> list[str]:
    """Metni anlamlı pasajlara böler.

    Önce paragraflara (boş satır), uzun paragrafları cümle sınırlarından
    ~max_kelime uzunluğunda pencerelere böler; çok kısa parçaları komşusuyla
    birleştirir. Amaç: her pasaj tek bir kavramı taşıyacak kadar küçük,
    anlamı taşıyacak kadar büyük olsun.
    """
    metin = re.sub(r"[ \t]+", " ", metin)
    paragraflar = [p.strip() for p in re.split(r"\n\s*\n", metin) if p.strip()]
    pasajlar: list[str] = []
    for p in paragraflar:
        kelimeler = p.split()
        if len(kelimeler) <= max_kelime:
            if len(kelimeler) >= 3:
                pasajlar.append(p)
            continue
        # uzun paragrafı cümlelerden pencerele
        cumleler = re.split(r"(?<=[.!?])\s+", p)
        tampon: list[str] = []
        for c in cumleler:
            # Tek başına max_kelime'yi aşan cümleyi kelime penceresine böl
            # (aksi halde gömme modelinde sessizce kesilir).
            c_kelime = c.split()
            if len(c_kelime) > max_kelime:
                if tampon:
                    pasajlar.append(" ".join(tampon)); tampon = []
                for i in range(0, len(c_kelime), max_kelime):
                    pasajlar.append(" ".join(c_kelime[i:i + max_kelime]))
                continue
            tampon.append(c)
            if sum(len(x.split()) for x in tampon) >= max_kelime:
                pasajlar.append(" ".join(tampon))
                tampon = []
        if tampon:
            pasajlar.append(" ".join(tampon))

    # Yalnızca ANLAM taşımayacak kadar kısa parçaları (cümle kırıntısı) öncekiyle
    # birleştir; meşru kısa paragrafları koru. Eşik min_kelime'nin yarısı.
    birlesim_esigi = max(3, min_kelime // 2)
    birlesik: list[str] = []
    for pas in pasajlar:
        if birlesik and len(pas.split()) < birlesim_esigi:
            birlesik[-1] = birlesik[-1] + " " + pas
        else:
            birlesik.append(pas)
    return birlesik


class KitapDeposu:
    """Referans kitap gömme indeksi: kur, kaydet, yükle, ilgili pasajları getir."""

    def __init__(self, pasajlar: list[KitapPasaji], gomme: np.ndarray):
        self.pasajlar = pasajlar
        self.gomme = gomme  # (N, D), satır-normalize

    # --- kurulum ---

    @classmethod
    def kur(
        cls,
        kaynaklar: list[str | Path],
        gomlemci: Gomlemci,
        min_kelime: int = 12,
        max_kelime: int = 80,
    ) -> "KitapDeposu":
        pasajlar: list[KitapPasaji] = []
        for kaynak in kaynaklar:
            ham = metin_cikar(kaynak)
            for i, metin in enumerate(pasajlara_bol(ham, min_kelime, max_kelime)):
                pasajlar.append(KitapPasaji(kaynak=Path(kaynak).name, sira=i, metin=metin))
        if not pasajlar:
            raise ValueError("Kaynaklardan hiç pasaj çıkarılamadı")
        gomme = np.asarray(gomlemci.gom([p.metin for p in pasajlar]), dtype=np.float32)
        gomme /= np.clip(np.linalg.norm(gomme, axis=1, keepdims=True), 1e-9, None)
        return cls(pasajlar, gomme)

    # --- kalıcılık ---

    def kaydet(self, dizin: str | Path) -> None:
        dizin = Path(dizin)
        dizin.mkdir(parents=True, exist_ok=True)
        np.save(dizin / "gomme.npy", self.gomme)
        (dizin / "pasajlar.jsonl").write_text(
            "\n".join(
                json.dumps({"kaynak": p.kaynak, "sira": p.sira, "metin": p.metin},
                           ensure_ascii=False)
                for p in self.pasajlar
            ),
            encoding="utf-8",
        )

    @classmethod
    def yukle(cls, dizin: str | Path) -> "KitapDeposu":
        dizin = Path(dizin)
        gomme = np.load(dizin / "gomme.npy")
        pasajlar = [
            KitapPasaji(**json.loads(satir))
            for satir in (dizin / "pasajlar.jsonl").read_text(encoding="utf-8").splitlines()
            if satir.strip()
        ]
        return cls(pasajlar, gomme)

    # --- erişim ---

    def ilgili(
        self, sorgu: str, gomlemci: Gomlemci, k: int = 3
    ) -> list[tuple[KitapPasaji, float]]:
        """Sorguya en yakın k pasajı (pasaj, benzerlik) olarak döner."""
        q = np.asarray(gomlemci.gom([sorgu]), dtype=np.float32)
        benzerlik = kosinus(q, self.gomme)[0]  # (N,)
        if k >= len(benzerlik):
            idx = np.argsort(-benzerlik)
        else:
            idx = np.argpartition(-benzerlik, k)[:k]
            idx = idx[np.argsort(-benzerlik[idx])]
        return [(self.pasajlar[i], float(benzerlik[i])) for i in idx]
