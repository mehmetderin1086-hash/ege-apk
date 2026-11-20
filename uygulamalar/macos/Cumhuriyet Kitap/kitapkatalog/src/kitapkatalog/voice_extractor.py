"""Transkriptten kitap alanı çıkarımı: kural katmanı + kanıt-bağlı Qwen yedeği.

Öncelik sırası kesindir: sağlaması geçen TEK ISBN > kural ayrıştırıcı > Qwen.
Qwen yalnız kural katmanının BOŞ bıraktığı metinsel alanları doldurabilir ve
mevcut ``EvidenceBoundExtractor`` alt-dize topraklaması değişmeden uygulanır
(transkriptte geçmeyen değer üretemez). Sayısal alanlar (yıl, sayfa, adet,
ISBN) Qwen'e HİÇ sorulmaz: "iki bin iki" -> 2002 dönüşümü topraklamayı
geçemeyeceği için bu dönüşümler yalnız deterministik katmanda yapılır ve ham
söylem aralığı kanıt olarak saklanır.
"""

from __future__ import annotations

import json
import math
from collections.abc import Callable, Sequence
from dataclasses import dataclass, field

from kitapkatalog.domain import (
    UNKNOWN_VALUE,
    BookInput,
    ContributorInput,
    IdentifierInput,
)
from kitapkatalog.extractor import (
    EvidenceBoundExtractor,
    EvidenceToken,
    FieldModelClient,
)
from kitapkatalog.voice_protocol import (
    BookUtterance,
    boundary_warnings,
    extract_field_spans,
    isbn_candidates_from_span,
    parse_int_span,
    parse_year_span,
)

RULE_VERSION = "voice-rule-1"
_QWEN_TEXT_FIELDS = frozenset(
    {
        "title",
        "subtitle",
        "original_title",
        "author",
        "contributor.author",
        "contributor.translator",
        "publisher",
        "imprint",
        "series",
        "language",
    }
)
_AUTHOR_SPLIT = (";", ",", " ve ", " ile ")
_MAX_COPY_COUNT = 99
_MAX_PAGE_COUNT = 99_999
_QWEN_LEFTOVER_RATIO = 0.5


@dataclass(frozen=True, slots=True)
class FieldClaim:
    field_path: str
    value: str
    raw_text: str
    start_char: int
    end_char: int
    source: str  # "rule" | "qwen"
    rule_version: str = RULE_VERSION


@dataclass(slots=True)
class VoiceParseResult:
    claims: list[FieldClaim] = field(default_factory=list)
    review_reasons: list[str] = field(default_factory=list)
    isbn: str | None = None
    copy_count: int = 1
    used_qwen: bool = False
    # İkinci geçiş (yabancı dil) önerileri: ASLA claims'e girmez, kanıt
    # sözleşmesini bozmaz; kullanıcı onayıyla source="form" yolundan yazılır.
    suggestions: list[dict] = field(default_factory=list)

    def value_of(self, field_path: str) -> str | None:
        for claim in self.claims:
            if claim.field_path == field_path:
                return claim.value
        return None

    def to_json(self) -> str:
        return json.dumps(
            {
                "claims": [
                    {
                        "field_path": claim.field_path,
                        "value": claim.value,
                        "raw_text": claim.raw_text,
                        "start_char": claim.start_char,
                        "end_char": claim.end_char,
                        "source": claim.source,
                        "rule_version": claim.rule_version,
                    }
                    for claim in self.claims
                ],
                "review_reasons": self.review_reasons,
                "isbn": self.isbn,
                "copy_count": self.copy_count,
                "used_qwen": self.used_qwen,
                "suggestions": self.suggestions,
            },
            ensure_ascii=False,
        )

    @classmethod
    def from_json(cls, payload: str) -> VoiceParseResult:
        document = json.loads(payload)
        result = cls(
            review_reasons=list(document.get("review_reasons", [])),
            isbn=document.get("isbn"),
            copy_count=int(document.get("copy_count", 1)),
            used_qwen=bool(document.get("used_qwen", False)),
            suggestions=list(document.get("suggestions", [])),
        )
        for item in document.get("claims", []):
            result.claims.append(
                FieldClaim(
                    field_path=str(item["field_path"]),
                    value=str(item["value"]),
                    raw_text=str(item.get("raw_text", "")),
                    start_char=int(item.get("start_char", 0)),
                    end_char=int(item.get("end_char", 0)),
                    source=str(item.get("source", "rule")),
                    rule_version=str(item.get("rule_version", RULE_VERSION)),
                )
            )
        return result


def transcript_semantic_validator(
    field_name: str, value: str, evidence: Sequence[EvidenceToken]
) -> bool:
    """Transkript kanıtı için alan kuralları: yalnız metinsel alanlar, tek kaynak.

    OCR'daki ``back_inside``/etiket-satırı varsayımları transkripte uymaz;
    sayısal ve fiziksel alanlar burada da reddedilir (kural katmanının işi).
    """

    if not evidence or {token.cover for token in evidence} != {"transcript"}:
        return False
    return field_name in _QWEN_TEXT_FIELDS


def utterance_tokens(utterance: BookUtterance) -> tuple[EvidenceToken, ...]:
    """Söylem segmentlerini kelime düzeyinde EvidenceToken'lara çevir."""

    tokens: list[EvidenceToken] = []
    for segment_index, segment in enumerate(utterance.segments):
        confidence = 0.5
        if segment.avg_logprob is not None:
            confidence = max(0.0, min(1.0, math.exp(segment.avg_logprob)))
        for word_index, word in enumerate(segment.text.split()):
            tokens.append(
                EvidenceToken(
                    token_id=f"tr:{segment_index}:{word_index}",
                    text=word,
                    cover="transcript",
                    confidence=confidence,
                    line_index=segment_index,
                )
            )
    return tuple(tokens)


class VoiceFieldExtractor:
    """Kural katmanı + gerektiğinde Qwen yedeğiyle söylem -> alan iddiaları."""

    def __init__(
        self,
        *,
        qwen_client_factory: Callable[[], FieldModelClient] | None = None,
    ) -> None:
        self.qwen_client_factory = qwen_client_factory

    def parse(self, utterance: BookUtterance) -> VoiceParseResult:
        result = VoiceParseResult()
        text = utterance.text
        spans = extract_field_spans(text)
        covered: list[tuple[int, int]] = []
        seen_values: dict[str, str] = {}

        for span in spans:
            covered.append((span.start, span.end))
            if span.field == "isbn":
                self._claim_isbn(result, span.raw_value, span.start, span.end)
            elif span.field == "copy_count":
                self._claim_copy_count(result, span.raw_value, span.start, span.end)
            elif span.field == "publication_date":
                year = parse_year_span(span.raw_value)
                if year is None:
                    result.review_reasons.append(f"Basım yılı anlaşılamadı: {span.raw_value!r}")
                else:
                    self._add_claim(result, "publication_date", str(year), span, seen_values)
            elif span.field == "page_count":
                pages = parse_int_span(span.raw_value)
                if pages is None or not 1 <= pages <= _MAX_PAGE_COUNT:
                    result.review_reasons.append(f"Sayfa sayısı anlaşılamadı: {span.raw_value!r}")
                else:
                    self._add_claim(result, "page_count", str(pages), span, seen_values)
            else:
                self._add_claim(result, span.field, span.raw_value, span, seen_values)

        result.review_reasons.extend(boundary_warnings(text))

        if self._should_use_qwen(result, text, covered):
            self._qwen_fallback(result, utterance)

        if result.value_of("title") is None:
            result.review_reasons.append("Başlık bulunamadı")
        return result

    def _add_claim(
        self,
        result: VoiceParseResult,
        field_path: str,
        value: str,
        span,
        seen_values: dict[str, str],
    ) -> None:
        previous = seen_values.get(field_path)
        if previous is not None and previous != value:
            result.review_reasons.append(
                f"'{field_path}' için çelişen değerler: {previous!r} / {value!r}"
            )
            return
        seen_values[field_path] = value
        result.claims.append(
            FieldClaim(
                field_path=field_path,
                value=value,
                raw_text=span.raw_value,
                start_char=span.start,
                end_char=span.end,
                source="rule",
            )
        )

    def _claim_isbn(self, result: VoiceParseResult, raw_value: str, start: int, end: int) -> None:
        candidates = isbn_candidates_from_span(raw_value)
        if len(candidates) == 1:
            result.isbn = candidates[0]
            result.claims.append(
                FieldClaim(
                    field_path="isbn",
                    value=candidates[0],
                    raw_text=raw_value,
                    start_char=start,
                    end_char=end,
                    source="rule",
                )
            )
        elif not candidates:
            result.review_reasons.append(f"ISBN sağlaması geçmedi: {raw_value!r}")
        else:
            result.review_reasons.append(
                "Birden fazla sağlaması geçerli ISBN adayı var: " + ", ".join(candidates)
            )

    def _claim_copy_count(
        self, result: VoiceParseResult, raw_value: str, start: int, end: int
    ) -> None:
        count = parse_int_span(raw_value)
        if count is None or not 1 <= count <= _MAX_COPY_COUNT:
            result.review_reasons.append(f"Adet anlaşılamadı: {raw_value!r}")
            return
        previous = next(
            (claim for claim in result.claims if claim.field_path == "copy_count"),
            None,
        )
        if previous is not None and previous.value != str(count):
            result.review_reasons.append(
                f"'copy_count' için çelişen değerler: {previous.value!r} / {count!r}"
            )
            return
        result.copy_count = count
        result.claims.append(
            FieldClaim(
                field_path="copy_count",
                value=str(count),
                raw_text=raw_value,
                start_char=start,
                end_char=end,
                source="rule",
            )
        )

    def _should_use_qwen(
        self,
        result: VoiceParseResult,
        text: str,
        covered: list[tuple[int, int]],
    ) -> bool:
        if self.qwen_client_factory is None:
            return False
        if result.value_of("title") is None:
            return True
        alpha_total = sum(1 for char in text if char.isalpha())
        if alpha_total == 0:
            return False
        uncovered = sum(
            1
            for index, char in enumerate(text)
            if char.isalpha() and not any(start <= index < end for start, end in covered)
        )
        return uncovered / alpha_total > _QWEN_LEFTOVER_RATIO

    def _qwen_fallback(self, result: VoiceParseResult, utterance: BookUtterance) -> None:
        assert self.qwen_client_factory is not None
        tokens = utterance_tokens(utterance)
        if not tokens:
            return
        try:
            client = self.qwen_client_factory()
            extractor = EvidenceBoundExtractor(
                client, semantic_validator=transcript_semantic_validator
            )
            extraction = extractor.extract(tokens)
        except Exception as error:
            result.review_reasons.append(f"Qwen yedeği başarısız: {error}")
            return
        result.used_qwen = True
        existing = {claim.field_path for claim in result.claims}
        for extracted in extraction.fields:
            field_path = extracted.field_name
            if field_path == "contributor.author":
                field_path = "author"
            if field_path == "contributor.translator":
                field_path = "translator"
            if field_path not in {
                "title",
                "subtitle",
                "original_title",
                "author",
                "translator",
                "publisher",
                "imprint",
                "series",
                "language",
            }:
                continue
            if field_path in existing:
                continue  # kural katmanı kazanır; Qwen üzerine yazamaz
            existing.add(field_path)
            result.claims.append(
                FieldClaim(
                    field_path=field_path,
                    value=extracted.value,
                    raw_text=extracted.value,
                    start_char=0,
                    end_char=0,
                    source="qwen",
                )
            )


def split_person_names(value: str) -> tuple[str, ...]:
    names = [value]
    for separator in _AUTHOR_SPLIT:
        parts: list[str] = []
        for item in names:
            parts.extend(item.split(separator))
        names = parts
    return tuple(name.strip(" .,;") for name in names if name.strip(" .,;"))


def build_book_input(
    result: VoiceParseResult, *, source_fingerprint: str | None = None
) -> BookInput:
    """İddia kümesinden Catalog.save_book'a hazır BookInput üret."""

    contributors: list[ContributorInput] = []
    author_value = result.value_of("author")
    if author_value:
        for order, name in enumerate(split_person_names(author_value)):
            contributors.append(ContributorInput(name=name, role="author", sort_order=order))
    translator_value = result.value_of("translator")
    if translator_value:
        for order, name in enumerate(split_person_names(translator_value)):
            contributors.append(
                ContributorInput(
                    name=name,
                    role="translator",
                    sort_order=len(contributors) + order,
                )
            )
    identifiers: tuple[IdentifierInput, ...] = ()
    if result.isbn:
        identifiers = (IdentifierInput(scheme="ISBN13", value=result.isbn, source="voice:whisper"),)
    page_count_value = result.value_of("page_count")
    return BookInput(
        title=result.value_of("title") or UNKNOWN_VALUE,
        publisher=result.value_of("publisher"),
        language=result.value_of("language"),
        category=result.value_of("category"),
        publication_date=result.value_of("publication_date"),
        page_count=int(page_count_value) if page_count_value else None,
        contributors=tuple(contributors),
        identifiers=identifiers,
    )
