from __future__ import annotations

import wave
from array import array
from pathlib import Path

import pytest

from kitapkatalog.audio import WAV_SAMPLE_RATE
from kitapkatalog.domain import TranscriptSegment, VoiceAlias
from kitapkatalog.voice_extractor import FieldClaim, VoiceParseResult
from kitapkatalog.voice_protocol import BookUtterance, utterance_pieces
from kitapkatalog.voice_refine import (
    alias_suggestions,
    refine_foreign_fields,
    refine_missing_title,
    span_to_sample_range,
)


def _wav(path: Path, seconds: float) -> Path:
    with wave.open(str(path), "wb") as writer:
        writer.setnchannels(1)
        writer.setsampwidth(2)
        writer.setframerate(WAV_SAMPLE_RATE)
        writer.writeframes((array("h", [0]) * int(seconds * WAV_SAMPLE_RATE)).tobytes())
    return path


def _utterance(*pieces: tuple[str, float, float]) -> BookUtterance:
    segments = tuple(
        TranscriptSegment(start_seconds=start, end_seconds=end, text=text)
        for text, start, end in pieces
    )
    return BookUtterance(
        ordinal=0,
        start_seconds=segments[0].start_seconds,
        end_seconds=segments[-1].end_seconds,
        segments=segments,
    )


class FakeWhisper:
    """Programlanabilir sahte whisper istemcisi (bağlam yöneticisi DEĞİL)."""

    def __init__(self, script: list) -> None:
        self.script = script
        self.calls: list[dict] = []

    def transcribe(self, wav_path, **kwargs):
        self.calls.append({"wav_path": Path(wav_path), **kwargs})
        behavior = self.script.pop(0)
        if isinstance(behavior, Exception):
            raise behavior
        return behavior


class TestSpanToSampleRange:
    def test_single_segment_span_matches_proportional_formula(self) -> None:
        utterance = _utterance(("başlık dı greyt gatsbi yazar", 0.0, 4.0))
        text = utterance.segments[0].text
        start_char = text.index("dı greyt gatsbi")
        end_char = start_char + len("dı greyt gatsbi")
        start_sample, end_sample = span_to_sample_range(
            utterance,
            start_char,
            end_char,
            pad_seconds=0.0,
            sample_rate=WAV_SAMPLE_RATE,
            total_samples=4 * WAV_SAMPLE_RATE,
        )
        expected_start = (start_char / len(text)) * 4.0
        expected_end = (end_char / len(text)) * 4.0
        assert start_sample == pytest.approx(int(expected_start * WAV_SAMPLE_RATE), abs=1)
        assert end_sample == pytest.approx(int(expected_end * WAV_SAMPLE_RATE), abs=1)

    def test_span_crossing_two_segments_covers_boundary(self) -> None:
        utterance = _utterance(
            ("başlık dı greyt", 0.0, 2.0),
            ("gatsbi yazar", 2.0, 4.0),
        )
        joined = utterance.text
        start_char = joined.index("dı greyt gatsbi")
        end_char = start_char + len("dı greyt gatsbi")
        start_sample, end_sample = span_to_sample_range(
            utterance,
            start_char,
            end_char,
            pad_seconds=0.0,
            sample_rate=WAV_SAMPLE_RATE,
            total_samples=4 * WAV_SAMPLE_RATE,
        )
        boundary = int(2.0 * WAV_SAMPLE_RATE)
        assert start_sample < boundary < end_sample

    def test_pad_and_clamp_stay_within_bounds(self) -> None:
        utterance = _utterance(("kar", 0.0, 1.0))
        total_samples = int(1.0 * WAV_SAMPLE_RATE)
        start_sample, end_sample = span_to_sample_range(
            utterance,
            0,
            3,
            pad_seconds=5.0,
            sample_rate=WAV_SAMPLE_RATE,
            total_samples=total_samples,
        )
        assert start_sample == 0  # negatif pad 0'a clamp edilir
        assert end_sample == total_samples  # toplam örnek sayısını aşamaz


def test_utterance_pieces_join_matches_text_property() -> None:
    utterance = _utterance(("başlık kar", 0.0, 1.0), ("yazar orhan pamuk", 1.0, 2.0))
    pieces = utterance_pieces(utterance)
    assert " ".join(piece for piece, _segment in pieces) == utterance.text


def _title_claim(text: str, keyword_value: str) -> tuple[VoiceParseResult, int, int]:
    start_char = text.index(keyword_value)
    end_char = start_char + len(keyword_value)
    result = VoiceParseResult()
    result.claims.append(
        FieldClaim(
            field_path="title",
            value=keyword_value,
            raw_text=keyword_value,
            start_char=start_char,
            end_char=end_char,
            source="rule",
        )
    )
    return result, start_char, end_char


class TestRefineForeignFields:
    def test_suggests_corrected_foreign_title(self, tmp_path: Path) -> None:
        text = "başlık dı greyt gatsbi yazar orhan pamuk"
        utterance = _utterance((text, 0.0, 4.0))
        result, _start, _end = _title_claim(text, "dı greyt gatsbi")
        whisper = FakeWhisper(
            [(TranscriptSegment(start_seconds=0.0, end_seconds=1.0, text="The Great Gatsby"),)]
        )
        suggestions = refine_foreign_fields(
            whisper,
            _wav(tmp_path / "soylem.wav", 4.0),
            utterance,
            result,
            language="en",
            scratch_dir=tmp_path / "scratch",
        )
        assert len(suggestions) == 1
        suggestion = suggestions[0]
        assert suggestion.field_path == "title"
        assert suggestion.value == "The Great Gatsby"
        assert suggestion.origin == "second_pass"
        assert suggestion.language == "en"
        assert whisper.calls[0]["language"] == "en"
        assert whisper.calls[0]["temperature_inc"] == 0.2

    def test_same_text_yields_no_suggestion(self, tmp_path: Path) -> None:
        text = "başlık kar yazar orhan pamuk"
        utterance = _utterance((text, 0.0, 4.0))
        result, _start, _end = _title_claim(text, "kar")
        whisper = FakeWhisper([(TranscriptSegment(start_seconds=0.0, end_seconds=1.0, text="kar"),)])
        suggestions = refine_foreign_fields(
            whisper,
            _wav(tmp_path / "soylem.wav", 4.0),
            utterance,
            result,
            language="en",
            scratch_dir=tmp_path / "scratch",
        )
        assert suggestions == []

    def test_empty_segments_yield_no_suggestion_and_no_review_reason(self, tmp_path: Path) -> None:
        text = "başlık kar yazar orhan pamuk"
        utterance = _utterance((text, 0.0, 4.0))
        result, _start, _end = _title_claim(text, "kar")
        whisper = FakeWhisper([()])
        suggestions = refine_foreign_fields(
            whisper,
            _wav(tmp_path / "soylem.wav", 4.0),
            utterance,
            result,
            language="en",
            scratch_dir=tmp_path / "scratch",
        )
        assert suggestions == []
        assert result.review_reasons == []

    def test_runaway_length_is_discarded(self, tmp_path: Path) -> None:
        text = "başlık kar yazar orhan pamuk"
        utterance = _utterance((text, 0.0, 4.0))
        result, _start, _end = _title_claim(text, "kar")
        runaway = "x" * 50
        whisper = FakeWhisper(
            [(TranscriptSegment(start_seconds=0.0, end_seconds=1.0, text=runaway),)]
        )
        suggestions = refine_foreign_fields(
            whisper,
            _wav(tmp_path / "soylem.wav", 4.0),
            utterance,
            result,
            language="en",
            scratch_dir=tmp_path / "scratch",
        )
        assert suggestions == []

    def test_prompt_identical_text_is_discarded(self, tmp_path: Path) -> None:
        text = "başlık dı greyt gatsbi yazar orhan pamuk"
        utterance = _utterance((text, 0.0, 4.0))
        result, _start, _end = _title_claim(text, "dı greyt gatsbi")
        prompt_text = "Başlık, yazar, çevirmen protokolü."
        whisper = FakeWhisper(
            [(TranscriptSegment(start_seconds=0.0, end_seconds=1.0, text=prompt_text),)]
        )
        suggestions = refine_foreign_fields(
            whisper,
            _wav(tmp_path / "soylem.wav", 4.0),
            utterance,
            result,
            language="en",
            scratch_dir=tmp_path / "scratch",
            prompt=prompt_text,
        )
        assert suggestions == []

    def test_form_source_claims_are_not_refined(self, tmp_path: Path) -> None:
        text = "başlık kar"
        utterance = _utterance((text, 0.0, 4.0))
        result = VoiceParseResult()
        result.claims.append(
            FieldClaim(
                field_path="title",
                value="kar",
                raw_text="kar",
                start_char=0,
                end_char=0,
                source="form",
            )
        )
        whisper = FakeWhisper([])
        suggestions = refine_foreign_fields(
            whisper,
            _wav(tmp_path / "soylem.wav", 4.0),
            utterance,
            result,
            language="en",
            scratch_dir=tmp_path / "scratch",
        )
        assert suggestions == []
        assert whisper.calls == []


class TestRefineMissingTitle:
    def test_returns_suggestion_from_whole_utterance(self, tmp_path: Path) -> None:
        whisper = FakeWhisper(
            [(TranscriptSegment(start_seconds=0.0, end_seconds=2.0, text="The Great Gatsby"),)]
        )
        suggestion = refine_missing_title(
            whisper, _wav(tmp_path / "soylem.wav", 2.0), language="en"
        )
        assert suggestion is not None
        assert suggestion.field_path == "title"
        assert suggestion.value == "The Great Gatsby"
        assert suggestion.origin == "second_pass"

    def test_returns_none_when_transcript_empty(self, tmp_path: Path) -> None:
        whisper = FakeWhisper([()])
        suggestion = refine_missing_title(
            whisper, _wav(tmp_path / "soylem.wav", 2.0), language="en"
        )
        assert suggestion is None

    def test_returns_none_when_identical_to_prompt(self, tmp_path: Path) -> None:
        prompt_text = "Başlık, yazar, çevirmen protokolü."
        whisper = FakeWhisper(
            [(TranscriptSegment(start_seconds=0.0, end_seconds=2.0, text=prompt_text),)]
        )
        suggestion = refine_missing_title(
            whisper,
            _wav(tmp_path / "soylem.wav", 2.0),
            language="en",
            prompt=prompt_text,
        )
        assert suggestion is None


def _alias(heard: str, canonical: str, field_scope: str = "any", *, alias_id: int = 1) -> VoiceAlias:
    return VoiceAlias(id=alias_id, heard=heard, canonical=canonical, field_scope=field_scope)


def _claim(field_path: str, value: str, *, source: str = "rule") -> FieldClaim:
    return FieldClaim(
        field_path=field_path, value=value, raw_text=value, start_char=0, end_char=0, source=source
    )


class TestAliasSuggestions:
    def test_exact_match_suggests_full_canonical_value(self) -> None:
        result = VoiceParseResult()
        result.claims.append(_claim("title", "di greyt gatsbi"))
        aliases = [_alias("di greyt gatsbi", "The Great Gatsby", "title")]

        suggestions = alias_suggestions(aliases, result)

        assert len(suggestions) == 1
        suggestion = suggestions[0]
        assert suggestion.field_path == "title"
        assert suggestion.value == "The Great Gatsby"
        assert suggestion.origin == "alias"
        assert suggestion.score == 1.0

    def test_word_bounded_substring_replaces_only_that_part(self) -> None:
        result = VoiceParseResult()
        result.claims.append(_claim("author", "orhan pamuk ve dı greyt gatsbi yazarı"))
        aliases = [_alias("di greyt gatsbi", "The Great Gatsby", "any")]

        suggestions = alias_suggestions(aliases, result)

        assert len(suggestions) == 1
        assert suggestions[0].value == "orhan pamuk ve The Great Gatsby yazarı"

    def test_substring_match_respects_word_boundaries(self) -> None:
        # "kar" bir alt-dize olarak "kardelen" içinde geçer ama kelime sınırını
        # AŞMADIĞI için eşleşmemeli.
        result = VoiceParseResult()
        result.claims.append(_claim("title", "Kardelen"))
        aliases = [_alias("kar", "Kar", "title")]

        assert alias_suggestions(aliases, result) == []

    def test_field_scope_any_applies_to_every_textual_field(self) -> None:
        result = VoiceParseResult()
        result.claims.append(_claim("title", "kar"))
        result.claims.append(_claim("author", "kar"))
        result.claims.append(_claim("publisher", "kar"))
        aliases = [_alias("kar", "KAR", "any")]

        suggestions = alias_suggestions(aliases, result)

        assert {item.field_path for item in suggestions} == {"title", "author", "publisher"}

    def test_field_scope_restricts_to_its_own_field(self) -> None:
        result = VoiceParseResult()
        result.claims.append(_claim("title", "kar"))
        result.claims.append(_claim("author", "kar"))
        aliases = [_alias("kar", "KAR", "title")]

        suggestions = alias_suggestions(aliases, result)

        assert len(suggestions) == 1
        assert suggestions[0].field_path == "title"

    def test_non_textual_fields_are_never_matched(self) -> None:
        result = VoiceParseResult()
        result.claims.append(_claim("language", "kar"))
        result.claims.append(_claim("publication_date", "kar"))
        aliases = [_alias("kar", "KAR", "any")]

        assert alias_suggestions(aliases, result) == []

    def test_alias_matching_already_correct_value_is_a_no_op(self) -> None:
        result = VoiceParseResult()
        result.claims.append(_claim("title", "Kar"))
        aliases = [_alias("kar", "Kar", "title")]

        assert alias_suggestions(aliases, result) == []

    def test_no_aliases_returns_empty_list(self) -> None:
        result = VoiceParseResult()
        result.claims.append(_claim("title", "kar"))

        assert alias_suggestions([], result) == []
