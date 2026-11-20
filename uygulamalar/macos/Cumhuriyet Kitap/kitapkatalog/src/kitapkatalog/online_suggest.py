"""Çevrimiçi ISBN öneri sorguları — YALNIZ ayrı "online-oneri" süreci için.

Ana uygulama tamamen çevrimdışıdır; bu modül yalnız `kitapkatalog online-oneri`
komutunun kurduğu allowlist ağ kilidi (offline.install_allowlist_guard) altında
çalışır. Sonuçlar asla otomatik kabul edilmez: `external_suggestion` tablosuna
`pending` olarak yazılır ve Onay Merkezi'nde kullanıcı onayı bekler.

Ağ erişimi test edilebilirlik için enjekte edilen bir `opener` (urlopen benzeri)
üzerinden yapılır; her hata sessizce None'a düşer (öneri katmanı fail-open).
"""

from __future__ import annotations

import json
from collections.abc import Callable
from dataclasses import dataclass, field
from typing import Any
from urllib.request import urlopen

ALLOWED_SUGGESTION_HOSTS = frozenset({"openlibrary.org", "www.googleapis.com"})
_TIMEOUT_SECONDS = 10.0
_MAX_RESPONSE_BYTES = 1_000_000

Opener = Callable[..., Any]


@dataclass(frozen=True, slots=True)
class OnlineSuggestion:
    """Tek kaynaktan gelen, kanıt sayılmayan dış öneri."""

    isbn13: str
    source: str
    title: str | None = None
    authors: tuple[str, ...] = ()
    publisher: str | None = None
    publication_date: str | None = None
    page_count: int | None = None
    language: str | None = None
    extra: dict[str, Any] = field(default_factory=dict)

    def payload(self) -> dict[str, Any]:
        return {
            "title": self.title,
            "authors": list(self.authors),
            "publisher": self.publisher,
            "publication_date": self.publication_date,
            "page_count": self.page_count,
            "language": self.language,
            **({"extra": self.extra} if self.extra else {}),
        }


def _read_json(opener: Opener, url: str) -> Any | None:
    try:
        with opener(url, timeout=_TIMEOUT_SECONDS) as response:
            raw = response.read(_MAX_RESPONSE_BYTES + 1)
    except Exception:  # Öneri katmanı fail-open: her ağ/protokol hatası atlanır.
        return None
    if len(raw) > _MAX_RESPONSE_BYTES:
        return None
    try:
        return json.loads(raw.decode("utf-8"))
    except (ValueError, UnicodeDecodeError):
        return None


def _clean(value: Any) -> str | None:
    if not isinstance(value, str):
        return None
    stripped = value.strip()
    return stripped or None


def _clean_int(value: Any) -> int | None:
    if isinstance(value, bool) or not isinstance(value, int):
        return None
    return value if 0 < value < 100_000 else None


def fetch_openlibrary(isbn13: str, *, opener: Opener = urlopen) -> OnlineSuggestion | None:
    data = _read_json(opener, f"https://openlibrary.org/isbn/{isbn13}.json")
    if not isinstance(data, dict):
        return None
    authors: list[str] = []
    for author_ref in data.get("authors", []) or []:
        if not isinstance(author_ref, dict):
            continue
        key = _clean(author_ref.get("key"))
        # Savunma derinliği: key doğrudan URL'ye gömülür; "@evil.com/x" gibi
        # bir değer host'u değiştirebilirdi. Allowlist kilidi zaten keser ama
        # modül kilitsiz import edilirse de güvenli kalsın.
        if key is None or not key.startswith("/authors/"):
            continue
        detail = _read_json(opener, f"https://openlibrary.org{key}.json")
        name = _clean(detail.get("name")) if isinstance(detail, dict) else None
        if name:
            authors.append(name)
    publishers = data.get("publishers")
    publisher = None
    if isinstance(publishers, list) and publishers:
        publisher = _clean(publishers[0])
    title = _clean(data.get("title"))
    if title is None:
        return None
    return OnlineSuggestion(
        isbn13=isbn13,
        source="openlibrary",
        title=title,
        authors=tuple(authors),
        publisher=publisher,
        publication_date=_clean(data.get("publish_date")),
        page_count=_clean_int(data.get("number_of_pages")),
    )


def fetch_google_books(isbn13: str, *, opener: Opener = urlopen) -> OnlineSuggestion | None:
    data = _read_json(
        opener, f"https://www.googleapis.com/books/v1/volumes?q=isbn:{isbn13}"
    )
    if not isinstance(data, dict):
        return None
    items = data.get("items")
    if not isinstance(items, list) or not items:
        return None
    info = items[0].get("volumeInfo") if isinstance(items[0], dict) else None
    if not isinstance(info, dict):
        return None
    title = _clean(info.get("title"))
    if title is None:
        return None
    raw_authors = info.get("authors")
    authors = tuple(
        name
        for name in (
            _clean(a) for a in (raw_authors if isinstance(raw_authors, list) else [])
        )
        if name
    )
    return OnlineSuggestion(
        isbn13=isbn13,
        source="google_books",
        title=title,
        authors=authors,
        publisher=_clean(info.get("publisher")),
        publication_date=_clean(info.get("publishedDate")),
        page_count=_clean_int(info.get("pageCount")),
        language=_clean(info.get("language")),
    )


def fetch_suggestions(
    isbn13: str, *, opener: Opener = urlopen
) -> list[OnlineSuggestion]:
    """Tüm kaynakları dener; erişilemeyen/uyumsuz kaynaklar sessizce atlanır."""

    suggestions = []
    for fetcher in (fetch_openlibrary, fetch_google_books):
        suggestion = fetcher(isbn13, opener=opener)
        if suggestion is not None:
            suggestions.append(suggestion)
    return suggestions
