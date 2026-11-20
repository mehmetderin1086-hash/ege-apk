"""Kitap ve çözüm kaynaklarından referans örnek alımı.

Desteklenen girdiler: PDF, Word (.docx), düz metin, ses (mp3/m4a/wav…) ve
video (mp4/mov…). Akış üç katmandır:

1. `cikarim` — dosyayı düz metne çevirir (sayfa/zaman damgası korunur).
2. `bolutleme` — düz metinden soru/çözüm adaylarını ayırır.
3. Çağıran (web ya da CLI) adayları **öğretmene onaylatır**; hiçbir aday
   doğrudan hafızaya yazılmaz. Kitap taraması gürültülüdür ve yanlış
   ayrıştırılmış bir çözüm kalıcı referans örneğe dönüşürse modeli sürekli
   yanlış yönlendirir.
"""

from __future__ import annotations

from .bolutleme import SoruAdayi, adaylari_cikar
from .cikarim import (
    DESTEKLENEN_UZANTILAR,
    AlimHatasi,
    Kaynak,
    metni_cikar,
)
from .konusma import sorulari_cikar

# `youtube` modülü bilinçli olarak buradan dışa aktarılmıyor: yt-dlp opsiyonel
# bir ekstra ve YouTube alımı kullanmayan yollar (webapp dahil) o modülün
# varlığını hiç yoklamamalı. Gerektiğinde `from .alim import youtube` ile alın.

__all__ = [
    "DESTEKLENEN_UZANTILAR",
    "AlimHatasi",
    "Kaynak",
    "SoruAdayi",
    "adaylari_cikar",
    "metni_cikar",
    "sorulari_cikar",
]
