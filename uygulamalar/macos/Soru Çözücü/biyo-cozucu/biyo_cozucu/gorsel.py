"""Soru görsellerinin saklanması ve okunması.

Görüntüler veritabanına DEĞİL dosya sistemine yazılıyor (`<kök>/gorseller/`),
veritabanında yalnız imza duruyor. Gerekçe: `biyo.db` şu an 128 KB; sayfa
görüntüleri BLOB olarak konsaydı birkaç yüz soruda yüzlerce MB'a çıkar,
yedeklemesi ve gözle incelenmesi zorlaşırdı. Dosya sisteminde duran bir PNG'yi
açıp bakmak ise bedava.

İmza içeriğin SHA-256'sıdır: aynı görüntü iki soruya iliştirilse de tek kopya
saklanır ve yeniden adlandırma kopya üretmez.
"""

from __future__ import annotations

import hashlib
from pathlib import Path

# Kabul edilen en büyük görüntü. Sayfa taramaları 300 DPI'da birkaç MB tutar;
# sınır, kazara yüklenen devasa dosyaların belleği doldurmasını engeller.
AZAMI_BOYUT_MB = 20

# Ayrıştırıcının tanıdığı biçimler. Pillow daha fazlasını açar ama depoya
# yazarken hepsi PNG'ye çevrilir: tek biçim, sürprizsiz okuma.
KABUL_EDILEN_UZANTILAR = {".png", ".jpg", ".jpeg", ".webp", ".gif", ".bmp", ".tif", ".tiff"}


class GorselHatasi(RuntimeError):
    """Görüntü okunamadığında ya da kabul edilmediğinde oluşur."""


def imzala(veri: bytes) -> str:
    """İçerik imzası (SHA-256'nın ilk 32 hanesi) — dosya adı olarak kullanılır."""
    return hashlib.sha256(veri).hexdigest()[:32]


def _pillow():
    try:
        from PIL import Image
    except ImportError as exc:  # pragma: no cover - ortam bağımlı
        raise GorselHatasi(
            "Pillow kurulu değil. Görsel soru desteği için: uv sync --extra vizyon"
        ) from exc
    return Image


class GorselDeposu:
    """`<kök>/gorseller/` altındaki PNG'leri imzayla adresler."""

    def __init__(self, kok: str | Path):
        self.dizin = Path(kok) / "gorseller"

    def yol(self, imza: str) -> Path:
        return self.dizin / f"{imza}.png"

    def var_mi(self, imza: str) -> bool:
        return bool(imza) and self.yol(imza).is_file()

    def yaz(self, veri: bytes) -> str:
        """Görüntüyü PNG olarak kaydeder ve imzasını döndürür.

        Aynı içerik ikinci kez verilirse yeniden yazılmaz; imza aynı olduğu
        için üzerine yazmak da zararsız olurdu ama gereksiz disk işi.
        """
        if not veri:
            raise GorselHatasi("Boş görüntü verisi.")
        if len(veri) > AZAMI_BOYUT_MB * 1024 * 1024:
            raise GorselHatasi(
                f"Görüntü {AZAMI_BOYUT_MB} MB sınırını aşıyor."
            )
        Image = _pillow()
        import io

        try:
            goruntu = Image.open(io.BytesIO(veri))
            goruntu.load()
        except Exception as exc:
            raise GorselHatasi(f"Görüntü okunamadı: {exc}") from exc

        # İmza HAM veriden değil, normalize edilmiş PNG'den alınıyor: aynı
        # görüntünün JPEG ve PNG kopyaları aynı imzaya düşsün, hafızada iki
        # ayrı kayıt oluşturmasın.
        tampon = io.BytesIO()
        goruntu.convert("RGB").save(tampon, format="PNG")
        png = tampon.getvalue()
        imza = imzala(png)

        hedef = self.yol(imza)
        if not hedef.is_file():
            self.dizin.mkdir(parents=True, exist_ok=True)
            hedef.write_bytes(png)
        return imza

    def oku(self, imza: str) -> bytes:
        hedef = self.yol(imza)
        if not hedef.is_file():
            raise GorselHatasi(f"Görüntü bulunamadı: {imza}")
        return hedef.read_bytes()

    def sil(self, imza: str) -> bool:
        hedef = self.yol(imza)
        if hedef.is_file():
            hedef.unlink()
            return True
        return False
