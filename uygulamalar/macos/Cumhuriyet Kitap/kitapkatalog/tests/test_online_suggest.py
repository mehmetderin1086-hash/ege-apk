"""online_suggest saf sorgu/ayrıştırma testleri (sahte opener, ağ yok)."""

from __future__ import annotations

import io
import json
from contextlib import contextmanager

from kitapkatalog.online_suggest import (
    fetch_google_books,
    fetch_openlibrary,
    fetch_suggestions,
)

ISBN = "9789750718533"


def _opener_for(responses: dict[str, object]):
    """URL → JSON eşlemesinden urlopen benzeri bir sahte üretir."""

    @contextmanager
    def opener(url: str, timeout: float = 0):
        if url not in responses:
            raise OSError(f"beklenmeyen URL: {url}")
        payload = responses[url]
        if isinstance(payload, Exception):
            raise payload
        yield io.BytesIO(json.dumps(payload).encode("utf-8"))

    return opener


class TestOpenLibrary:
    def test_parses_title_authors_and_publisher(self) -> None:
        opener = _opener_for(
            {
                f"https://openlibrary.org/isbn/{ISBN}.json": {
                    "title": "Kar",
                    "publishers": ["İletişim"],
                    "publish_date": "2002",
                    "number_of_pages": 428,
                    "authors": [{"key": "/authors/OL123A"}],
                },
                "https://openlibrary.org/authors/OL123A.json": {"name": "Orhan Pamuk"},
            }
        )
        suggestion = fetch_openlibrary(ISBN, opener=opener)
        assert suggestion is not None
        assert suggestion.source == "openlibrary"
        assert suggestion.title == "Kar"
        assert suggestion.authors == ("Orhan Pamuk",)
        assert suggestion.publisher == "İletişim"
        assert suggestion.page_count == 428
        assert suggestion.payload()["authors"] == ["Orhan Pamuk"]

    def test_network_error_returns_none(self) -> None:
        opener = _opener_for(
            {f"https://openlibrary.org/isbn/{ISBN}.json": OSError("bağlantı yok")}
        )
        assert fetch_openlibrary(ISBN, opener=opener) is None

    def test_missing_title_returns_none(self) -> None:
        opener = _opener_for(
            {f"https://openlibrary.org/isbn/{ISBN}.json": {"publishers": ["X"]}}
        )
        assert fetch_openlibrary(ISBN, opener=opener) is None

    def test_author_detail_failure_keeps_other_fields(self) -> None:
        opener = _opener_for(
            {
                f"https://openlibrary.org/isbn/{ISBN}.json": {
                    "title": "Kar",
                    "authors": [{"key": "/authors/OL404A"}],
                },
                "https://openlibrary.org/authors/OL404A.json": OSError("404"),
            }
        )
        suggestion = fetch_openlibrary(ISBN, opener=opener)
        assert suggestion is not None and suggestion.authors == ()


class TestGoogleBooks:
    def test_parses_volume_info(self) -> None:
        opener = _opener_for(
            {
                f"https://www.googleapis.com/books/v1/volumes?q=isbn:{ISBN}": {
                    "items": [
                        {
                            "volumeInfo": {
                                "title": "Beyaz Gemi",
                                "authors": ["Cengiz Aytmatov"],
                                "publisher": "İletişim",
                                "publishedDate": "1970",
                                "pageCount": 180,
                                "language": "tr",
                            }
                        }
                    ]
                }
            }
        )
        suggestion = fetch_google_books(ISBN, opener=opener)
        assert suggestion is not None
        assert suggestion.title == "Beyaz Gemi"
        assert suggestion.authors == ("Cengiz Aytmatov",)
        assert suggestion.language == "tr"

    def test_empty_items_returns_none(self) -> None:
        opener = _opener_for(
            {f"https://www.googleapis.com/books/v1/volumes?q=isbn:{ISBN}": {"items": []}}
        )
        assert fetch_google_books(ISBN, opener=opener) is None

    def test_bogus_page_count_is_dropped(self) -> None:
        opener = _opener_for(
            {
                f"https://www.googleapis.com/books/v1/volumes?q=isbn:{ISBN}": {
                    "items": [{"volumeInfo": {"title": "X", "pageCount": -5}}]
                }
            }
        )
        suggestion = fetch_google_books(ISBN, opener=opener)
        assert suggestion is not None and suggestion.page_count is None


def test_fetch_suggestions_skips_failed_sources() -> None:
    opener = _opener_for(
        {
            f"https://openlibrary.org/isbn/{ISBN}.json": OSError("erişilemiyor"),
            f"https://www.googleapis.com/books/v1/volumes?q=isbn:{ISBN}": {
                "items": [{"volumeInfo": {"title": "Tek Kaynak"}}]
            },
        }
    )
    results = fetch_suggestions(ISBN, opener=opener)
    assert [s.source for s in results] == ["google_books"]
