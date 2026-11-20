"""VoiceSession çekirdeğinin ikinci-geçiş (yabancı dil) entegrasyon testleri.

Qt'ye dokunmadan çalışır (bkz. voice_controller.py docstring'i); GUI akışı
zaten test_gui_voice.py'de ayrıca doğrulanıyor.
"""

from __future__ import annotations

import wave
from array import array
from pathlib import Path

from test_voice_scheduler import FakeWhisper, _paths

from kitapkatalog.audio import WAV_SAMPLE_RATE
from kitapkatalog.database import Database
from kitapkatalog.domain import TranscriptSegment
from kitapkatalog.settings import AppSettings
from kitapkatalog.voice_controller import VoiceSession


def _wav(path: Path, seconds: float = 2.0) -> Path:
    with wave.open(str(path), "wb") as writer:
        writer.setnchannels(1)
        writer.setsampwidth(2)
        writer.setframerate(WAV_SAMPLE_RATE)
        writer.writeframes((array("h", [64]) * int(seconds * WAV_SAMPLE_RATE)).tobytes())
    return path


_MAIN_SEGMENTS = (
    TranscriptSegment(
        start_seconds=0.0,
        end_seconds=8.0,
        text=(
            "ISBN dokuz yedi sekiz dokuz yedi beş sıfır yedi bir sekiz beş üç üç "
            "başlık Kar yazar Orhan Pamuk yayınevi İletişim kategori roman "
            "yıl iki bin iki üç adet"
        ),
        avg_logprob=-0.1,
    ),
)


def _session(tmp_path: Path, script: list) -> tuple[VoiceSession, Database]:
    paths = _paths(tmp_path / "veri")
    database = Database(paths.database)
    session = VoiceSession(database, paths, whisper_client_factory=lambda: FakeWhisper(script))
    return session, database


class TestSecondPassIntegration:
    def test_second_pass_off_makes_single_whisper_call(self, tmp_path: Path) -> None:
        session, database = _session(tmp_path, [_MAIN_SEGMENTS])
        AppSettings(database).update({"voice_second_pass": "0", "voice_prompt_bias": "0"})

        pending = session.analyze(_wav(tmp_path / "soylem.wav", seconds=8.0))

        assert pending.result.suggestions == []
        assert len(session._whisper.calls) == 1

    def test_second_pass_on_refines_title_and_author_with_configured_language(
        self, tmp_path: Path
    ) -> None:
        script = [
            _MAIN_SEGMENTS,
            (TranscriptSegment(start_seconds=0.0, end_seconds=1.0, text="Kar"),),
            (TranscriptSegment(start_seconds=0.0, end_seconds=1.0, text="Orhan Pamuk"),),
        ]
        session, database = _session(tmp_path, script)
        AppSettings(database).update(
            {
                "voice_second_pass": "1",
                "voice_second_pass_language": "en",
                "voice_prompt_bias": "0",
            }
        )

        pending = session.analyze(_wav(tmp_path / "soylem.wav", seconds=8.0))

        whisper = session._whisper
        assert len(whisper.calls) == 3  # ana geçiş + başlık + yazar dilimi
        assert whisper.call_kwargs[1]["language"] == "en"
        assert whisper.call_kwargs[2]["language"] == "en"
        # İkinci geçiş kural değeriyle aynı metni üretti -> öneri yok.
        assert pending.result.suggestions == []

    def test_foreign_title_suggestion_blocks_auto_save(self, tmp_path: Path) -> None:
        # "dı greyt gatsbi" -> Türkçe fonetik yazım; ikinci geçiş İngilizce
        # gerçek başlığı bulur (görev örneğiyle birebir aynı senaryo).
        phonetic_segments = (
            TranscriptSegment(
                start_seconds=0.0,
                end_seconds=4.0,
                text="başlık dı greyt gatsbi yazar Orhan Pamuk",
                avg_logprob=-0.1,
            ),
        )
        script = [
            phonetic_segments,
            (TranscriptSegment(start_seconds=0.0, end_seconds=1.0, text="The Great Gatsby"),),
            (TranscriptSegment(start_seconds=0.0, end_seconds=1.0, text="Orhan Pamuk"),),
        ]
        session, database = _session(tmp_path, script)
        AppSettings(database).update(
            {
                "voice_second_pass": "1",
                "voice_second_pass_language": "en",
                "voice_prompt_bias": "0",
            }
        )

        pending = session.analyze(_wav(tmp_path / "soylem.wav", seconds=4.0))
        result = pending.result

        assert any(item["field_path"] == "title" for item in result.suggestions)
        assert session.auto_save_allowed(result, []) is False

    def test_refine_failure_is_fail_open(self, tmp_path: Path) -> None:
        """Whisper ikinci geçişte patlarsa analyze() yine de sonuç döndürür."""

        script = [_MAIN_SEGMENTS, RuntimeError("whisper çöktü")]
        session, database = _session(tmp_path, script)
        AppSettings(database).update({"voice_second_pass": "1", "voice_prompt_bias": "0"})

        pending = session.analyze(_wav(tmp_path / "soylem.wav", seconds=8.0))

        assert pending.result.value_of("title") == "Kar"
        assert pending.result.suggestions == []


class TestTranscribeField:
    def test_extracts_field_span_when_keyword_present(self, tmp_path: Path) -> None:
        script = [(TranscriptSegment(start_seconds=0.0, end_seconds=1.0, text="başlık Kar"),)]
        session, _database = _session(tmp_path, script)

        value, transcript = session.transcribe_field(
            _wav(tmp_path / "soylem.wav", 1.0), "title", language="tr", prompt="Başlık: "
        )

        assert value == "Kar"
        assert transcript == "başlık Kar"
        assert session._whisper.call_kwargs[0]["language"] == "tr"
        assert session._whisper.call_kwargs[0]["prompt"] == "Başlık: "

    def test_falls_back_to_full_transcript_without_keyword(self, tmp_path: Path) -> None:
        # Kısa yeniden-söyleme kayıtlarında kullanıcı genelde anahtar kelimeyi
        # söylemez; span bulunamazsa tüm transkript değer olarak dönmeli.
        script = [(TranscriptSegment(start_seconds=0.0, end_seconds=1.0, text="Kar"),)]
        session, _database = _session(tmp_path, script)

        value, transcript = session.transcribe_field(
            _wav(tmp_path / "soylem.wav", 1.0), "title", language="tr"
        )

        assert value == "Kar"
        assert transcript == "Kar"


class TestCatalogSuggestions:
    def test_title_band_suggests_close_but_not_duplicate_catalog_title(
        self, tmp_path: Path
    ) -> None:
        from kitapkatalog.domain import BookInput

        session, _database = _session(tmp_path, [])
        session.catalog.save_book(BookInput(title="Karlar"))

        suggestions = session.catalog_suggestions("Kar", "")

        assert any(
            item.field_path == "title" and item.value == "Karlar" and item.origin == "catalog"
            for item in suggestions
        )

    def test_author_similarity_suggests_top_contributor(self, tmp_path: Path) -> None:
        from kitapkatalog.domain import BookInput, ContributorInput

        session, _database = _session(tmp_path, [])
        session.catalog.save_book(
            BookInput(
                title="Kar",
                contributors=(ContributorInput(name="Orhan Pamuk", role="author"),),
            )
        )

        suggestions = session.catalog_suggestions("", "Orhan Pamu")

        assert any(
            item.field_path == "author" and item.value == "Orhan Pamuk" and item.origin == "catalog"
            for item in suggestions
        )

    def test_empty_title_and_authors_yield_no_suggestions(self, tmp_path: Path) -> None:
        session, _database = _session(tmp_path, [])
        assert session.catalog_suggestions("", "") == []


def test_top_suggestions_per_field_keeps_best_three_per_field() -> None:
    from kitapkatalog.voice_controller import FieldSuggestion, _top_suggestions_per_field

    author_candidates = [
        FieldSuggestion(field_path="author", value=f"Aday {i}", origin="catalog", language="", score=score)
        for i, score in enumerate([0.9, 0.8, 0.95, 0.76])
    ]
    title_candidate = FieldSuggestion(
        field_path="title", value="Tek", origin="catalog", language="", score=0.7
    )

    capped = _top_suggestions_per_field([*author_candidates, title_candidate], limit=3)

    author_values = {item.value for item in capped if item.field_path == "author"}
    assert author_values == {"Aday 2", "Aday 0", "Aday 1"}  # en düşük skorlu (Aday 3) elenir
    assert any(item.field_path == "title" and item.value == "Tek" for item in capped)
    assert len(capped) == 4


class TestOfflineSuggestionsIntegration:
    def test_analyze_applies_alias_suggestions_without_second_pass(self, tmp_path: Path) -> None:
        session, database = _session(tmp_path, [_MAIN_SEGMENTS])
        AppSettings(database).update({"voice_second_pass": "0", "voice_prompt_bias": "0"})
        database.upsert_voice_alias("kar", "Kar (Roman)", "title")

        pending = session.analyze(_wav(tmp_path / "soylem.wav", seconds=8.0))

        assert any(
            item["field_path"] == "title" and item["origin"] == "alias" and item["value"] == "Kar (Roman)"
            for item in pending.result.suggestions
        )
