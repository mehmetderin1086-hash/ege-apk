from __future__ import annotations

from pathlib import Path

import pytest

from kitapkatalog.catalog import Catalog
from kitapkatalog.database import Database
from kitapkatalog.domain import BookInput, ContributorInput
from kitapkatalog.voice_prompt import build_transcription_prompt


@pytest.fixture()
def database(tmp_path: Path) -> Database:
    return Database(tmp_path / "catalog.sqlite3")


def _seed(catalog: Catalog) -> None:
    catalog.save_book(
        BookInput(
            title="Kar",
            publisher="İletişim",
            contributors=(ContributorInput("Orhan Pamuk", "author"),),
        ),
        source_fingerprint="seed:1",
    )
    catalog.save_book(
        BookInput(
            title="Sessiz Ev",
            publisher="Can Yayınları",
            contributors=(ContributorInput("Orhan Pamuk", "author"),),
        ),
        source_fingerprint="seed:2",
    )


class TestBuildTranscriptionPrompt:
    def test_includes_protocol_sentence(self, database: Database) -> None:
        prompt = build_transcription_prompt(database)
        assert prompt.startswith("Başlık, yazar, çevirmen")

    def test_includes_frequent_authors_and_publishers(self, database: Database) -> None:
        catalog = Catalog(database)
        _seed(catalog)
        prompt = build_transcription_prompt(database)
        assert "Orhan Pamuk" in prompt
        assert "İletişim" in prompt
        assert "Can Yayınları" in prompt

    def test_includes_extra_text(self, database: Database) -> None:
        prompt = build_transcription_prompt(database, extra="Nutuk, Kürk Mantolu Madonna")
        assert "Nutuk, Kürk Mantolu Madonna" in prompt

    def test_blank_extra_is_ignored(self, database: Database) -> None:
        with_blank = build_transcription_prompt(database, extra="   ")
        without = build_transcription_prompt(database)
        assert with_blank == without

    def test_truncated_at_max_chars(self, database: Database) -> None:
        catalog = Catalog(database)
        _seed(catalog)
        prompt = build_transcription_prompt(database, max_chars=40)
        assert len(prompt) == 40

    def test_default_max_chars_is_600(self, database: Database) -> None:
        catalog = Catalog(database)
        for index in range(60):
            catalog.save_book(
                BookInput(
                    title=f"Kitap {index}",
                    publisher=f"Yayınevi {index}",
                    contributors=(ContributorInput(f"Yazar Soyad {index}", "author"),),
                ),
                source_fingerprint=f"seed:{index}",
            )
        prompt = build_transcription_prompt(database)
        assert len(prompt) <= 600
