from __future__ import annotations

import pytest

from kitapkatalog.domain import TranscriptSegment
from kitapkatalog.voice_protocol import (
    BookUtterance,
    boundary_warnings,
    extract_field_spans,
    filter_hallucinations,
    fold_text,
    isbn_candidates_from_span,
    parse_int_span,
    parse_number_words,
    parse_year_span,
    segment_books,
)


def _segment(text: str, start: float = 0.0, end: float = 5.0, **kwargs) -> TranscriptSegment:
    return TranscriptSegment(start_seconds=start, end_seconds=end, text=text, **kwargs)


@pytest.mark.parametrize(
    ("words", "expected"),
    [
        (["dokuz", "yuz", "doksan", "dokuz"], 999),
        (["iki", "bin", "iki"], 2002),
        (["bin", "dokuz", "yuz", "doksan"], 1990),
        (["iki", "bin", "yirmi", "dort"], 2024),
        (["yuz"], 100),
        (["bin"], 1000),
        (["sifir"], 0),
        (["bi", "bin"], 1000),
        (["kitap"], None),
    ],
)
def test_parse_number_words(words: list[str], expected: int | None) -> None:
    assert parse_number_words(words) == expected


@pytest.mark.parametrize(
    ("raw", "expected"),
    [
        ("üç yüz on iki", 312),
        ("312", 312),
        ("1.002", 1002),
        ("1,002", 1002),
        ("ikibin yirmi", 2020),
        ("üçyüz", 300),
        ("dort yuz elli", 450),
        ("sayı yok", None),
    ],
)
def test_parse_int_span(raw: str, expected: int | None) -> None:
    assert parse_int_span(raw) == expected


def test_parse_year_span_rejects_nonsense() -> None:
    assert parse_year_span("iki bin iki") == 2002
    assert parse_year_span("üç yüz on iki") is None
    assert parse_year_span("dokuz") is None


class TestIsbnCandidates:
    def test_digits_with_dashes(self) -> None:
        assert isbn_candidates_from_span("978-975-07-0718-5 33") == ()
        assert isbn_candidates_from_span("978-975-07-1853-3") == ("9789750718533",)

    def test_single_digit_words(self) -> None:
        spoken = "dokuz yedi sekiz dokuz yedi beş sıfır yedi bir sekiz beş üç üç"
        assert isbn_candidates_from_span(spoken) == ("9789750718533",)

    def test_grouped_prefix(self) -> None:
        spoken = "dokuz yüz yetmiş sekiz dokuz yedi beş 0 7 1 8 5 3 3"
        assert "9789750718533" in isbn_candidates_from_span(spoken)

    def test_mixed_digits_and_words(self) -> None:
        spoken = "978 dokuz yedi beş sıfır yedi bir sekiz beş üç üç"
        assert isbn_candidates_from_span(spoken) == ("9789750718533",)

    def test_invalid_checksum_yields_nothing(self) -> None:
        assert isbn_candidates_from_span("978 975 07 1853 4") == ()

    def test_isbn10_is_canonicalized(self) -> None:
        candidates = isbn_candidates_from_span("9750718534")
        assert candidates == ("9789750718533",)


class TestFieldSpans:
    def test_template_utterance(self) -> None:
        text = (
            "ISBN 978 975 07 1853 3. Başlık Kar. Yazar Orhan Pamuk. "
            "Yayınevi İletişim. Yıl iki bin iki. Sayfa dört yüz yirmi sekiz. "
            "Dil Türkçe. Kategori roman. Üç adet."
        )
        spans = {span.field: span for span in extract_field_spans(text)}
        assert spans["title"].raw_value == "Kar"
        assert spans["author"].raw_value == "Orhan Pamuk"
        assert spans["publisher"].raw_value == "İletişim"
        assert parse_year_span(spans["publication_date"].raw_value) == 2002
        assert parse_int_span(spans["page_count"].raw_value) == 428
        assert spans["language"].raw_value == "Türkçe"
        assert spans["category"].raw_value == "roman"
        assert parse_int_span(spans["copy_count"].raw_value) == 3
        assert isbn_candidates_from_span(spans["isbn"].raw_value) == ("9789750718533",)

    def test_copy_count_before_keyword_does_not_leak_into_category(self) -> None:
        text = "Kategori bilim kurgu iki adet"
        spans = {span.field: span for span in extract_field_spans(text)}
        assert spans["category"].raw_value == "bilim kurgu"
        assert parse_int_span(spans["copy_count"].raw_value) == 2

    def test_longest_keyword_wins(self) -> None:
        text = "Basım yılı bin dokuz yüz seksen dört başlık 1984"
        spans = {span.field: span for span in extract_field_spans(text)}
        assert parse_year_span(spans["publication_date"].raw_value) == 1984
        assert spans["title"].raw_value == "1984"

    def test_folded_keyword_matching(self) -> None:
        text = "BASLIK Tutunamayanlar yazar Oğuz Atay"
        spans = {span.field: span for span in extract_field_spans(text)}
        assert spans["title"].raw_value == "Tutunamayanlar"
        assert spans["author"].raw_value == "Oğuz Atay"


class TestSegmentation:
    def test_separator_in_own_segment(self) -> None:
        segments = [
            _segment("Başlık Kar yazar Orhan Pamuk", 0, 6),
            _segment("Yeni kitap", 6, 7),
            _segment("Başlık Tutunamayanlar yazar Oğuz Atay", 7, 14),
        ]
        utterances = segment_books(segments)
        assert len(utterances) == 2
        assert "Kar" in utterances[0].text
        assert "Tutunamayanlar" in utterances[1].text
        assert utterances[0].ordinal == 0
        assert utterances[1].ordinal == 1

    def test_separator_mid_segment_splits_text(self) -> None:
        segments = [
            _segment(
                "Başlık Kar üç adet yeni kitap Başlık Puslu Kıtalar Atlası",
                0,
                12,
            )
        ]
        utterances = segment_books(segments)
        assert len(utterances) == 2
        assert "Kar" in utterances[0].text
        assert "Puslu" in utterances[1].text
        assert utterances[0].end_seconds <= utterances[1].start_seconds

    def test_no_separator_yields_single_utterance(self) -> None:
        utterances = segment_books([_segment("Başlık Kar"), _segment("iki adet")])
        assert len(utterances) == 1

    def test_alternative_separators(self) -> None:
        segments = [
            _segment("Başlık Kar"),
            _segment("sıradaki kitap"),
            _segment("Başlık Beyaz Kale"),
            _segment("kitap bitti"),
        ]
        assert len(segment_books(segments)) == 2


class TestHallucinationFilter:
    def test_drops_high_no_speech(self) -> None:
        segments = [
            _segment("Başlık Kar", no_speech_prob=0.1),
            _segment("Altyazı M.K.", no_speech_prob=0.97),
        ]
        kept = filter_hallucinations(segments)
        assert len(kept) == 1
        assert kept[0].text == "Başlık Kar"

    def test_missing_probability_is_kept(self) -> None:
        assert len(filter_hallucinations([_segment("Başlık Kar")])) == 1

    def test_repeat_loop_is_truncated(self) -> None:
        segments = [_segment("teşekkür ederim") for _ in range(6)]
        assert len(filter_hallucinations(segments)) == 2


def test_boundary_warnings_flags_two_isbns_and_repeats() -> None:
    text = "ISBN 978 975 07 1853 3 başlık Kar ISBN 978 605 09 9256 4 başlık Körlük"
    warnings = boundary_warnings(text)
    assert any("birden fazla geçerli ISBN" in item for item in warnings)
    assert any("'title'" in item for item in warnings)
    assert boundary_warnings("Başlık Kar yazar Orhan Pamuk") == ()


def test_book_utterance_text_joins_segments() -> None:
    utterance = BookUtterance(
        ordinal=0,
        start_seconds=0.0,
        end_seconds=4.0,
        segments=(_segment("Başlık Kar", 0, 2), _segment("iki adet", 2, 4)),
    )
    assert utterance.text == "Başlık Kar iki adet"
    assert fold_text("BAŞLIK") == "baslik"


class TestStrictNumberGrammar:
    @pytest.mark.parametrize(
        "words",
        [
            ["yirmi", "otuz"],
            ["iki", "uc"],
            ["yuz", "doksan", "iki", "on"],
            ["bin", "iki", "bin"],
            ["sifir", "bes"],
            ["bir", "on"],
            ["dokuz", "yedi", "sekiz"],
        ],
    )
    def test_invalid_sequences_rejected(self, words: list[str]) -> None:
        assert parse_number_words(words) is None

    def test_shared_run_multiword_copy_split(self) -> None:
        spans = {s.field: s for s in extract_field_spans("sayfa yüz doksan iki on iki adet")}
        assert parse_int_span(spans["page_count"].raw_value) == 192
        assert parse_int_span(spans["copy_count"].raw_value) == 12

        spans = {s.field: s for s in extract_field_spans("yıl iki bin yirmi dört on iki adet")}
        assert parse_year_span(spans["publication_date"].raw_value) == 2024
        assert parse_int_span(spans["copy_count"].raw_value) == 12

    def test_span_offsets_match_raw_value_exactly(self) -> None:
        text = "ISBN 978 975 07 1853 3. Başlık Kar. Yazar Orhan Pamuk. Kategori roman. Üç adet."
        for span in extract_field_spans(text):
            assert text[span.start : span.end] == span.raw_value
