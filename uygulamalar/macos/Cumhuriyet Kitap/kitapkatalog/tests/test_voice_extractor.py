from __future__ import annotations

import pytest

from kitapkatalog.domain import TranscriptSegment
from kitapkatalog.extractor import EvidenceToken
from kitapkatalog.voice_extractor import (
    VoiceFieldExtractor,
    VoiceParseResult,
    build_book_input,
    split_person_names,
    transcript_semantic_validator,
    utterance_tokens,
)
from kitapkatalog.voice_protocol import BookUtterance


def _utterance(text: str, *, avg_logprob: float | None = -0.1) -> BookUtterance:
    return BookUtterance(
        ordinal=0,
        start_seconds=0.0,
        end_seconds=10.0,
        segments=(
            TranscriptSegment(
                start_seconds=0.0,
                end_seconds=10.0,
                text=text,
                avg_logprob=avg_logprob,
            ),
        ),
    )


_TEMPLATE = (
    "ISBN 978 975 07 1853 3. Başlık Kar. Yazar Orhan Pamuk. "
    "Yayınevi İletişim. Yıl iki bin iki. Sayfa dört yüz yirmi sekiz. "
    "Dil Türkçe. Kategori roman. Üç adet."
)


class TestRuleLayer:
    def test_full_template_parses_without_review(self) -> None:
        result = VoiceFieldExtractor().parse(_utterance(_TEMPLATE))
        assert result.review_reasons == []
        assert result.isbn == "9789750718533"
        assert result.copy_count == 3
        assert result.value_of("title") == "Kar"
        assert result.value_of("author") == "Orhan Pamuk"
        assert result.value_of("publisher") == "İletişim"
        assert result.value_of("publication_date") == "2002"
        assert result.value_of("page_count") == "428"
        assert result.value_of("language") == "Türkçe"
        assert result.value_of("category") == "roman"
        assert not result.used_qwen

    def test_bad_isbn_checksum_goes_to_review(self) -> None:
        result = VoiceFieldExtractor().parse(_utterance("ISBN 978 975 07 1853 4 başlık Kar"))
        assert result.isbn is None
        assert any("sağlaması geçmedi" in reason for reason in result.review_reasons)

    def test_missing_title_flagged(self) -> None:
        result = VoiceFieldExtractor().parse(_utterance("Yazar Orhan Pamuk iki adet"))
        assert any("Başlık bulunamadı" in reason for reason in result.review_reasons)

    def test_conflicting_field_values_flagged(self) -> None:
        result = VoiceFieldExtractor().parse(_utterance("Başlık Kar yazar Orhan Pamuk başlık Kar"))
        # Aynı değer çelişki değildir; farklı değer çelişkidir.
        assert not any("çelişen" in reason for reason in result.review_reasons)
        conflicted = VoiceFieldExtractor().parse(
            _utterance("Yıl iki bin iki yazar Orhan Pamuk yıl bin dokuz yüz doksan")
        )
        assert any("çelişen" in r for r in conflicted.review_reasons)

    def test_round_trip_json(self) -> None:
        result = VoiceFieldExtractor().parse(_utterance(_TEMPLATE))
        restored = VoiceParseResult.from_json(result.to_json())
        assert restored.isbn == result.isbn
        assert restored.copy_count == result.copy_count
        assert [claim.field_path for claim in restored.claims] == [
            claim.field_path for claim in result.claims
        ]


class _FakeQwen:
    """Transkript kelimelerinden topraklanabilir/topraklanamaz adaylar üretir."""

    def __init__(self, candidates):
        self.candidates = candidates
        self.calls = 0

    def extract(self, tokens):
        self.calls += 1
        return list(self.candidates(tokens))


class TestQwenFallback:
    def test_untriggered_when_rule_layer_complete(self) -> None:
        fake = _FakeQwen(lambda tokens: [])
        extractor = VoiceFieldExtractor(qwen_client_factory=lambda: fake)
        extractor.parse(_utterance(_TEMPLATE))
        assert fake.calls == 0

    def test_fills_only_missing_fields_with_grounded_values(self) -> None:
        text = "Orhan Pamuk'un Kar romanı İletişim'den iki adet"

        def candidates(tokens):
            ids = {token.text: token.token_id for token in tokens}
            return [
                {
                    "field_name": "title",
                    "value": "Kar",
                    "evidence_token_ids": [ids["Kar"]],
                    "confidence": 0.9,
                },
                {
                    "field_name": "title",
                    "value": "Uydurma Kitap",  # transkriptte yok -> topraklanamaz
                    "evidence_token_ids": [ids["Kar"]],
                    "confidence": 0.99,
                },
                {
                    "field_name": "page_count",
                    "value": "300",  # sayısal alan Qwen'den kabul edilmez
                    "evidence_token_ids": [ids["romanı"]],
                    "confidence": 0.9,
                },
            ]

        fake = _FakeQwen(candidates)
        extractor = VoiceFieldExtractor(qwen_client_factory=lambda: fake)
        result = extractor.parse(_utterance(text))
        assert fake.calls == 1
        assert result.used_qwen
        assert result.value_of("title") == "Kar"
        assert result.value_of("page_count") is None
        title_claims = [c for c in result.claims if c.field_path == "title"]
        assert len(title_claims) == 1
        assert title_claims[0].source == "qwen"

    def test_rule_claims_are_never_overwritten(self) -> None:
        def candidates(tokens):
            ids = [token.token_id for token in tokens]
            return [
                {
                    "field_name": "publisher",
                    "value": "Can",
                    "evidence_token_ids": ids[:1],
                    "confidence": 0.9,
                }
            ]

        fake = _FakeQwen(candidates)
        extractor = VoiceFieldExtractor(qwen_client_factory=lambda: fake)
        # başlık yok -> Qwen tetiklenir; ama yayınevi kuraldan dolu
        result = extractor.parse(
            _utterance("Yayınevi İletişim. Can Yücel'in şiirlerini rafa diziyorum")
        )
        assert result.value_of("publisher") == "İletişim"

    def test_qwen_failure_is_review_reason_not_crash(self) -> None:
        def boom():
            raise RuntimeError("llama-server yok")

        extractor = VoiceFieldExtractor(qwen_client_factory=boom)
        result = extractor.parse(_utterance("Orhan Pamuk romanı"))
        assert any("Qwen yedeği başarısız" in r for r in result.review_reasons)


class TestSemanticValidator:
    def test_rejects_non_transcript_cover(self) -> None:
        token = EvidenceToken(token_id="x", text="Kar", cover="front")
        assert not transcript_semantic_validator("title", "Kar", (token,))

    def test_rejects_numeric_fields(self) -> None:
        token = EvidenceToken(token_id="x", text="428", cover="transcript")
        assert not transcript_semantic_validator("page_count", "428", (token,))
        assert not transcript_semantic_validator("dimensions", "13x21", (token,))

    def test_accepts_text_fields(self) -> None:
        token = EvidenceToken(token_id="x", text="Kar", cover="transcript")
        assert transcript_semantic_validator("title", "Kar", (token,))
        assert transcript_semantic_validator("publisher", "İletişim", (token,))


class TestBookInput:
    def test_build_book_input_maps_all_fields(self) -> None:
        result = VoiceFieldExtractor().parse(_utterance(_TEMPLATE))
        book = build_book_input(result)
        assert book.title == "Kar"
        assert book.publisher == "İletişim"
        assert book.category == "roman"
        assert book.language == "Türkçe"
        assert book.publication_date == "2002"
        assert book.page_count == 428
        assert book.identifiers[0].value == "9789750718533"
        assert book.identifiers[0].source == "voice:whisper"
        assert book.contributors[0].name == "Orhan Pamuk"
        assert book.contributors[0].role == "author"

    def test_split_person_names(self) -> None:
        assert split_person_names("Orhan Pamuk ve Elif Şafak") == (
            "Orhan Pamuk",
            "Elif Şafak",
        )
        assert split_person_names("A. Kadir; Nazım Hikmet") == (
            "A. Kadir",
            "Nazım Hikmet",
        )

    def test_missing_title_becomes_unknown(self) -> None:
        result = VoiceFieldExtractor().parse(_utterance("iki adet"))
        assert build_book_input(result).title == "bilinmiyor"


def test_utterance_tokens_confidence_and_ids() -> None:
    utterance = _utterance("Başlık Kar", avg_logprob=None)
    tokens = utterance_tokens(utterance)
    assert [token.token_id for token in tokens] == ["tr:0:0", "tr:0:1"]
    assert all(token.cover == "transcript" for token in tokens)
    assert all(token.confidence == pytest.approx(0.5) for token in tokens)


def test_conflicting_copy_counts_flagged() -> None:
    result = VoiceFieldExtractor().parse(
        _utterance("Başlık Kar iki adet yazar Orhan Pamuk üç adet")
    )
    assert any("copy_count" in reason for reason in result.review_reasons)
    assert result.copy_count == 2  # ilk değer korunur, sessizce ezilmez


class TestLocationField:
    def test_dolap_keyword_parses_location(self) -> None:
        result = VoiceFieldExtractor().parse(
            _utterance("Başlık Kar yazar Orhan Pamuk dolap A5 iki adet")
        )
        assert result.value_of("location") == "A5"
        assert result.value_of("title") == "Kar"
        assert result.copy_count == 2

    def test_raf_alone_still_maps_to_category(self) -> None:
        result = VoiceFieldExtractor().parse(_utterance("Başlık Kar raf roman"))
        assert result.value_of("category") == "roman"
        assert result.value_of("location") is None


class TestSuggestionsBackwardCompatibility:
    def test_missing_suggestions_key_defaults_to_empty_list(self) -> None:
        # İkinci geçiş özelliğinden önce yazılmış bir JSON sidecar.
        old_payload = (
            '{"claims": [], "review_reasons": [], "isbn": null, '
            '"copy_count": 1, "used_qwen": false}'
        )
        result = VoiceParseResult.from_json(old_payload)
        assert result.suggestions == []

    def test_round_trips_suggestions(self) -> None:
        result = VoiceParseResult()
        result.suggestions.append(
            {
                "field_path": "title",
                "value": "The Great Gatsby",
                "origin": "second_pass",
                "language": "en",
                "score": 0.4,
            }
        )
        restored = VoiceParseResult.from_json(result.to_json())
        assert restored.suggestions == result.suggestions
