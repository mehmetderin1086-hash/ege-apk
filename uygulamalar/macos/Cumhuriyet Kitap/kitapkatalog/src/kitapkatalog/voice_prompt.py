"""Whisper transkripsiyonu için önek istemi (prompt biasing) kurulumu.

Whisper'ın ``prompt`` alanı modelin kelime dağarcığını yönlendirir; halüsinasyon
riskine karşı yalnız zaten katalogda geçen isimler (sık yazarlar, yayınevleri)
kullanılır — uydurma bir isim listesi üretilmez. İstem sabit bir protokol
cümlesiyle başlar ki whisper alan sırasını ("başlık… yazar… yayınevi…") tanısın.
"""

from __future__ import annotations

from kitapkatalog.catalog import Catalog
from kitapkatalog.database import Database

_PROTOCOL_SENTENCE = (
    "Başlık, yazar, çevirmen, yayınevi, basım yılı, sayfa sayısı, dil, "
    "kategori, dolap, adet, ISBN, yeni kitap."
)
_MAX_AUTHORS = 40
_MAX_PUBLISHERS = 20


def build_transcription_prompt(database: Database, *, extra: str = "", max_chars: int = 600) -> str:
    """Sabit protokol cümlesi + katalogdaki sık yazar/yayınevi + serbest ek metin.

    Sonuç ``max_chars`` karakterde kesilir (whisper prompt'unun token bütçesi
    sınırlıdır); kesme en sona uygulanır ki protokol cümlesi hep bütün kalsın.
    """

    catalog = Catalog(database)
    parts = [_PROTOCOL_SENTENCE]
    authors = catalog.top_contributors(role="author", limit=_MAX_AUTHORS)
    if authors:
        parts.append(", ".join(authors) + ".")
    publishers = catalog.list_distinct_values("publisher")[:_MAX_PUBLISHERS]
    if publishers:
        parts.append(", ".join(publishers) + ".")
    if extra.strip():
        parts.append(extra.strip())
    return " ".join(parts)[:max_chars]
