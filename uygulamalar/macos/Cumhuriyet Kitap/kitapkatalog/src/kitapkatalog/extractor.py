from __future__ import annotations

import json
import re
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
from collections.abc import Callable, Sequence
from dataclasses import dataclass, field
from difflib import SequenceMatcher
from typing import Any, Protocol

_PUBLISHER_RE = re.compile(
    r"\b(?:yayınları|yayıncılık|yayınevi|kitapları|kitabevi|publishing|publisher|press)\b",
    re.IGNORECASE,
)
_PUBLISHER_CORPORATE_RE = re.compile(
    r"(?:"
    r"\b(?:limited|ltd|inc|llc|company|corporation|group|grubu|kooperatifi)\b|"
    r"(?:^|\s)(?:a\.?\s*ş\.?|ltd\.?\s*şti\.?)(?:\s|$)"
    r")",
    re.IGNORECASE,
)
_ROLE_PATTERNS = {
    "translator": re.compile(r"^\s*(?:çeviren|çeviri|tercüme)\s*[:\-]\s*(.+)$", re.I),
    "editor": re.compile(r"^\s*(?:editör|editor)\s*[:\-]\s*(.+)$", re.I),
    "illustrator": re.compile(r"^\s*(?:çizer|resimleyen|illustrator)\s*[:\-]\s*(.+)$", re.I),
    "compiler": re.compile(r"^\s*(?:derleyen|hazırlayan|compiled by)\s*[:\-]\s*(.+)$", re.I),
}
_MODEL_CONTRIBUTOR_LABELS = {
    "author": re.compile(r"\b(?:yazar|author|written\s+by)\b", re.I),
    "translator": re.compile(
        r"\b(?:çeviren|çeviri|tercüme|translator|translated\s+by)\b",
        re.I,
    ),
    "editor": re.compile(r"\b(?:editör|editor|edited\s+by)\b", re.I),
    "illustrator": re.compile(
        r"\b(?:çizer|resimleyen|illustrator|illustrated\s+by)\b",
        re.I,
    ),
    "compiler": re.compile(
        r"\b(?:derleyen|hazırlayan|compiler|compiled\s+by)\b",
        re.I,
    ),
    "foreword": re.compile(r"\b(?:önsöz|foreword)\b", re.I),
    "other": re.compile(r"\b(?:katkıda\s+bulunan|contributor)\b", re.I),
}
_ISBN_RE = re.compile(
    r"(?:ISBN(?:-1[03])?\s*[:\-]?\s*)?((?:97[89][\s\-]?)?\d[\dXx\s\-]{8,20})",
    re.I,
)
_PRICE_RE = re.compile(
    r"(?:(?:fiyat|price)\s*[:\-]?\s*)?"
    r"((?:₺|TL|TRY|\$|€|£)\s*\d+(?:[.,]\d{1,2})?|\d+(?:[.,]\d{1,2})?\s*(?:₺|TL|TRY|\$|€|£))",
    re.I,
)
_URL_RE = re.compile(r"(?:https?://|www\.)\S+", re.I)
_YEAR_RE = re.compile(r"\b((?:1[5-9]|20)\d{2})\b")
_PAGE_COUNT_RE = re.compile(
    r"\b(\d{1,5})\s*(?:sayfa|sahife|pages?|pp\.?)\b",
    re.I,
)
_EDITION_RE = re.compile(
    r"\b(\d{1,3})\.?\s*(?:baskı|basım|edition|printing)\b",
    re.I,
)
_PRINTER_RE = re.compile(
    r"^\s*(?:matbaa|basıldığı\s+yer|baskı\s+ve\s+cilt|printer)\s*[:\-]\s*(.+)$",
    re.I,
)
_PLACE_RE = re.compile(
    r"^\s*(?:basım\s+yeri|yayın\s+yeri|place\s+of\s+publication)\s*[:\-]\s*(.+)$",
    re.I,
)
_DIMENSIONS_RE = re.compile(
    r"\b(\d{1,3}(?:[.,]\d)?\s*[x×]\s*\d{1,3}(?:[.,]\d)?\s*cm)\b",
    re.I,
)
_PAGE_COUNT_VALUE_RE = re.compile(
    r"^\s*(?:sayfa\s*[:\-]?\s*)?(\d{1,5})"
    r"(?:\s*(?:sayfa|sahife|pages?|pp\.?))?\s*$",
    re.I,
)
_FINAL_PAGE_NUMBER_RE = re.compile(r"^\s*(\d{2,5})\s*$")
_TITLE_METADATA_RE = re.compile(
    r"^\s*(?:"
    r"yazar|author|editör|editor|çeviren|çeviri|tercüme|translator|"
    r"çizer|resimleyen|illustrator|derleyen|hazırlayan|compiled\s+by|"
    r"önsöz|foreword|isbn|fiyat|price|baskı|basım|edition|printing|"
    r"matbaa|printer"
    r")\b",
    re.I,
)
_KUNYE_PATTERNS: dict[str, re.Pattern[str]] = {
    "publisher": re.compile(r"^\s*(?:yayınevi|yayıncı(?:lık)?)\s*[:\-]\s*(.+)$", re.I),
    "contributor.translator": re.compile(r"^\s*(?:çeviren|çeviri|tercüme)\s*[:\-]\s*(.+)$", re.I),
    "contributor.editor": re.compile(r"^\s*editör\s*[:\-]\s*(.+)$", re.I),
    "contributor.other": re.compile(
        r"^\s*(?:kapak\s+tasarım[ıi]?|yayın\s+yönetmeni)\s*[:\-]\s*(.+)$", re.I
    ),
    "edition_statement": re.compile(r"^\s*(?:baskı|basım)\s*[:\-]\s*(.+)$", re.I),
    # Recognised only so it does not fall through to a less specific rule;
    # no field is ever emitted for a certificate number.
    "__ignored__": re.compile(r"^\s*sertifika\s+no(?:su)?\s*[:\-]\s*(.+)$", re.I),
}
ALLOWED_MODEL_FIELDS: tuple[str, ...] = (
    "title",
    "subtitle",
    "original_title",
    "author",
    "contributor.author",
    "contributor.translator",
    "contributor.editor",
    "contributor.illustrator",
    "contributor.compiler",
    "contributor.foreword",
    "contributor.other",
    "publisher",
    "imprint",
    "series",
    "volume",
    "publication_place",
    "publication_date",
    "edition_statement",
    "printing_number",
    "printer",
    "language",
    "binding",
    "page_count",
    "dimensions",
    "printed_price",
    "price_amount",
    "currency",
    "synopsis",
    "blurb",
    "awards",
    "quotations",
    "publisher_url",
    "unmapped_claim",
)


@dataclass(frozen=True, slots=True)
class EvidenceToken:
    token_id: str
    text: str
    cover: str
    polygon: tuple[tuple[float, float], ...] = ()
    confidence: float = 0.0
    line_index: int = 0

    @property
    def height(self) -> float:
        if not self.polygon:
            return 0.0
        ys = [point[1] for point in self.polygon]
        return max(ys) - min(ys)


@dataclass(frozen=True, slots=True)
class ExtractedField:
    field_name: str
    value: str
    evidence_token_ids: tuple[str, ...]
    confidence: float
    source: str
    status: str


@dataclass(slots=True)
class ExtractionResult:
    fields: list[ExtractedField] = field(default_factory=list)
    rejected_model_fields: list[dict[str, Any]] = field(default_factory=list)


class FieldModelClient(Protocol):
    def extract(self, tokens: Sequence[EvidenceToken]) -> list[dict[str, Any]]: ...


def _nfc(text: str) -> str:
    return unicodedata.normalize("NFC", text).strip()


def _evidence_form(text: str) -> str:
    text = _nfc(text).casefold()
    return "".join(character for character in text if character.isalnum())


def _value_is_grounded(value: str, evidence: Sequence[EvidenceToken]) -> bool:
    wanted = _evidence_form(value)
    if not wanted:
        return False
    joined = _evidence_form(" ".join(token.text for token in evidence))
    # Joining/splitting OCR tokens is allowed, but deleting arbitrary
    # characters in the middle (a subsequence) is not.
    return wanted in joined


def _looks_like_unlabelled_front_author(value: str) -> bool:
    """Conservatively allow the common front-cover ``Given Family`` form."""

    parts = value.split()
    if not 2 <= len(parts) <= 4 or any("'" in part or "’" in part for part in parts):
        return False
    for part in parts:
        cleaned = part.strip(".,-")
        if (
            not cleaned
            or not cleaned[0].isalpha()
            or not cleaned[0].isupper()
            or not all(character.isalpha() or character in ".-" for character in cleaned)
        ):
            return False
    return True


def _status(confidence: float) -> str:
    if confidence >= 0.98:
        return "auto"
    if confidence >= 0.80:
        return "review"
    return "unresolved"


def _lines(tokens: Sequence[EvidenceToken], cover: str) -> list[list[EvidenceToken]]:
    grouped: dict[int, list[EvidenceToken]] = {}
    for token in tokens:
        if token.cover == cover and token.text.strip():
            grouped.setdefault(token.line_index, []).append(token)
    return [
        sorted(grouped[index], key=lambda token: token.polygon[0][0] if token.polygon else 0.0)
        for index in sorted(grouped)
    ]


def _line_text(line: Sequence[EvidenceToken]) -> str:
    return " ".join(token.text.strip() for token in line if token.text.strip()).strip()


def _line_bbox(
    line: Sequence[EvidenceToken],
) -> tuple[float, float, float, float] | None:
    points = [point for token in line for point in token.polygon]
    if not points:
        return None
    xs = [point[0] for point in points]
    ys = [point[1] for point in points]
    return min(xs), min(ys), max(xs), max(ys)


def _line_confidence(line: Sequence[EvidenceToken]) -> float:
    return min((token.confidence for token in line), default=0.0)


def _kunye_fields(lines: Sequence[Sequence[EvidenceToken]]) -> list[ExtractedField]:
    """Capture inline ``Etiket: Değer`` colophon lines the narrower rules miss."""

    fields: list[ExtractedField] = []
    for line in lines:
        text = _line_text(line)
        if not text:
            continue
        for field_name, pattern in _KUNYE_PATTERNS.items():
            match = pattern.match(text)
            if not match or field_name == "__ignored__":
                continue
            value = match.group(1).strip()
            if not value:
                continue
            ids = tuple(token.token_id for token in line)
            mean_confidence = sum(token.confidence for token in line) / len(line)
            fields.append(
                ExtractedField(
                    field_name,
                    value,
                    ids,
                    mean_confidence,
                    "rule:kunye",
                    _status(mean_confidence),
                )
            )
    return fields


def _title_line_is_eligible(text: str) -> bool:
    stripped = text.strip()
    if len(_evidence_form(stripped)) < 2:
        return False
    if stripped.startswith(("©", "®")):
        return False
    return not (
        _PUBLISHER_RE.search(stripped)
        or _TITLE_METADATA_RE.match(stripped)
        or _ISBN_RE.search(stripped)
        or _URL_RE.search(stripped)
    )


def _front_title_group(
    lines: Sequence[Sequence[EvidenceToken]],
) -> list[Sequence[EvidenceToken]]:
    """Select adjacent display-title lines without swallowing contributor metadata.

    Vision OCR may attach one coarse polygon to several physical title lines.
    Line order remains reliable, so the coarse box is useful as an anchor but
    explicit role/publisher lines form hard boundaries.
    """

    eligible = [
        (index, line)
        for index, line in enumerate(lines)
        if _title_line_is_eligible(_line_text(line))
    ]
    if not eligible:
        return []
    anchor_index, anchor = max(
        eligible,
        key=lambda item: (
            max((token.height for token in item[1]), default=0.0),
            _line_confidence(item[1]),
        ),
    )
    anchor_box = _line_bbox(anchor)
    if anchor_box is None:
        return [anchor]
    anchor_height = max(0.0, anchor_box[3] - anchor_box[1])
    if anchor_height <= 0.0:
        return [anchor]

    selected: dict[int, Sequence[EvidenceToken]] = {anchor_index: anchor}
    minimum_height = anchor_height * 0.20
    maximum_gap = anchor_height * 0.45
    for direction in (-1, 1):
        index = anchor_index + direction
        previous_box = anchor_box
        while 0 <= index < len(lines):
            line = lines[index]
            text = _line_text(line)
            if not _title_line_is_eligible(text):
                break
            box = _line_bbox(line)
            if box is None:
                break
            height = max(0.0, box[3] - box[1])
            gap = (
                max(0.0, previous_box[1] - box[3])
                if direction < 0
                else max(0.0, box[1] - previous_box[3])
            )
            if height < minimum_height or gap > maximum_gap:
                break
            selected[index] = line
            previous_box = box
            index += direction
    return [selected[index] for index in sorted(selected)]


# A layout heuristic decides *which* text on a cover is the title, and that
# decision carries its own uncertainty on top of the OCR confidence. Capping it
# at a constant made the most basic field structurally impossible to accept
# automatically, because the auto threshold sits above the cap. The ceiling now
# follows how clear-cut the layout decision actually was.
_TITLE_CEILING_AMBIGUOUS = 0.89
_TITLE_CEILING_DOMINANT = 0.995
_TITLE_DOMINANCE_RATIO = 1.5


def _title_layout_ceiling(
    lines: Sequence[Sequence[EvidenceToken]],
    group: Sequence[Sequence[EvidenceToken]],
) -> float:
    """How far the layout decision alone may lift a title's confidence.

    A cover whose title towers over every other candidate leaves little room to
    pick the wrong block; a cover with two similarly sized blocks leaves a lot.
    """

    if not group:
        return _TITLE_CEILING_AMBIGUOUS
    chosen = {id(line) for line in group}
    group_height = max(
        (max((token.height for token in line), default=0.0) for line in group),
        default=0.0,
    )
    if group_height <= 0.0:
        return _TITLE_CEILING_AMBIGUOUS
    rival_height = max(
        (
            max((token.height for token in line), default=0.0)
            for line in lines
            if id(line) not in chosen and _title_line_is_eligible(_line_text(line))
        ),
        default=0.0,
    )
    if rival_height <= 0.0:
        # Nothing else on the cover could plausibly have been the title.
        return _TITLE_CEILING_DOMINANT
    return (
        _TITLE_CEILING_DOMINANT
        if group_height >= rival_height * _TITLE_DOMINANCE_RATIO
        else _TITLE_CEILING_AMBIGUOUS
    )


def _front_inside_title_fallback(
    front_title: str,
    lines: Sequence[Sequence[EvidenceToken]],
) -> Sequence[EvidenceToken] | None:
    """Find a colophon heading that independently corroborates the front title."""

    reference = _evidence_form(front_title)
    if len(reference) < 4:
        return None
    candidates: list[tuple[float, int, Sequence[EvidenceToken]]] = []
    for index, line in enumerate(lines[:8]):
        text = _line_text(line)
        if not _title_line_is_eligible(text):
            continue
        candidate = _evidence_form(text)
        if len(candidate) < max(4, int(len(reference) * 0.75)):
            continue
        similarity = SequenceMatcher(None, reference, candidate, autojunk=False).ratio()
        corroborated = (
            similarity >= 0.72
            or (len(reference) >= 6 and reference in candidate)
            or (len(candidate) >= 6 and candidate in reference)
        )
        if corroborated:
            candidates.append((similarity, -index, line))
    return max(candidates)[2] if candidates else None


def _model_field_is_semantically_valid(
    field_name: str,
    value: str,
    evidence: Sequence[EvidenceToken],
) -> bool:
    """Apply strict surface and syntax checks to physical-description fields."""

    if field_name == "publisher":
        if _PUBLISHER_RE.search(value) or _PUBLISHER_CORPORATE_RE.search(value):
            return True
        return any(
            _value_is_grounded(value, (token,))
            and (_PUBLISHER_RE.search(token.text) or _PUBLISHER_CORPORATE_RE.search(token.text))
            for token in evidence
        )

    contributor_role = (
        field_name.removeprefix("contributor.")
        if field_name.startswith("contributor.")
        else ("author" if field_name == "author" else None)
    )
    if contributor_role is not None:
        label_pattern = _MODEL_CONTRIBUTOR_LABELS.get(contributor_role)
        if label_pattern is None:
            return False
        if label_pattern.search(value):
            return True
        if (
            contributor_role == "author"
            and _looks_like_unlabelled_front_author(value)
            and evidence
            and {token.cover for token in evidence} == {"front"}
            and any(_value_is_grounded(value, (token,)) for token in evidence)
        ):
            # Author names are commonly printed without a role label.  This
            # narrow person-name/front-cover exception preserves that case;
            # every other contributor role still requires an explicit label.
            return True
        label_tokens = [token for token in evidence if label_pattern.search(token.text)]
        if not label_tokens:
            return False
        value_form = _evidence_form(value)
        value_tokens = [
            token
            for token in evidence
            if (token_form := _evidence_form(token.text))
            and (value_form in token_form or token_form in value_form)
        ]
        if any(
            label.line_index == value_token.line_index
            for label in label_tokens
            for value_token in value_tokens
        ):
            return True
        return any(
            0 < value_token.line_index - label.line_index <= 1
            for label in label_tokens
            for value_token in value_tokens
        )

    if field_name not in {"page_count", "dimensions"}:
        return True
    if not evidence or {token.cover for token in evidence} != {"back_inside"}:
        return False
    evidence_text = " ".join(token.text for token in evidence)
    if field_name == "page_count":
        evidence_match = _PAGE_COUNT_RE.search(evidence_text)
        value_match = _PAGE_COUNT_VALUE_RE.fullmatch(value)
        return bool(
            evidence_match
            and value_match
            and int(evidence_match.group(1)) == int(value_match.group(1))
        )
    evidence_match = _DIMENSIONS_RE.search(evidence_text)
    value_match = _DIMENSIONS_RE.fullmatch(value.strip())
    return bool(
        evidence_match
        and value_match
        and _evidence_form(evidence_match.group(1)) == _evidence_form(value_match.group(1))
    )


class EvidenceBoundExtractor:
    """Maps OCR evidence to fields and rejects ungrounded model output."""

    def __init__(
        self,
        model_client: FieldModelClient | None = None,
        *,
        semantic_validator: Callable[[str, str, Sequence[EvidenceToken]], bool] | None = None,
    ) -> None:
        self.model_client = model_client
        # None -> OCR yüzey/sözdizim kuralları (mevcut davranış). Ses hattı
        # transkript kanıtına uygun kendi doğrulayıcısını enjekte eder.
        self.semantic_validator = (
            semantic_validator
            if semantic_validator is not None
            else _model_field_is_semantically_valid
        )

    def extract(self, tokens: Sequence[EvidenceToken]) -> ExtractionResult:
        result = ExtractionResult()
        by_id = {token.token_id: token for token in tokens}
        token_positions = {token.token_id: index for index, token in enumerate(tokens)}
        self._deterministic(tokens, result)
        if self.model_client is not None:
            try:
                model_candidates = self.model_client.extract(tokens)
            except Exception as exc:
                # Qwen is an evidence classifier, not one of the five strict
                # OCR votes.  A malformed/oversized local response must remain
                # visible and force review, but must not discard deterministic
                # fields already grounded in all five OCR outputs.
                result.rejected_model_fields.append(
                    {
                        "field_name": "__model_error__",
                        "error": f"{type(exc).__name__}: {exc}"[:2000],
                    }
                )
                model_candidates = []
            for candidate in model_candidates:
                ids = tuple(str(item) for item in candidate.get("evidence_token_ids", []))
                evidence = [by_id[item] for item in ids if item in by_id]
                value = _nfc(str(candidate.get("value", "")))
                field_name = str(candidate.get("field_name", ""))
                ordered_ids = tuple(
                    sorted(ids, key=lambda item: token_positions.get(item, len(tokens)))
                )
                if (
                    field_name not in ALLOWED_MODEL_FIELDS
                    or not ids
                    or len(set(ids)) != len(ids)
                    or len(evidence) != len(ids)
                    or ids != ordered_ids
                    or len({token.cover for token in evidence}) != 1
                    or not _value_is_grounded(value, evidence)
                    or not self.semantic_validator(field_name, value, evidence)
                ):
                    result.rejected_model_fields.append(candidate)
                    continue
                confidence = min(
                    float(candidate.get("confidence", 0.0)),
                    sum(token.confidence for token in evidence) / len(evidence),
                )
                result.fields.append(
                    ExtractedField(
                        field_name=field_name,
                        value=value,
                        evidence_token_ids=ids,
                        confidence=confidence,
                        source="qwen3-evidence-bound",
                        status=_status(confidence),
                    )
                )
        result.fields = self._deduplicate(result.fields)
        return result

    def _deterministic(self, tokens: Sequence[EvidenceToken], result: ExtractionResult) -> None:
        all_lines = [
            *_lines(tokens, "front"),
            *_lines(tokens, "front_inside"),
            *_lines(tokens, "back_inside"),
            *_lines(tokens, "back"),
        ]
        for line in all_lines:
            text = _line_text(line)
            ids = tuple(token.token_id for token in line)
            mean_confidence = sum(token.confidence for token in line) / len(line)
            for match in _ISBN_RE.finditer(text):
                compact = re.sub(r"[\s\-]", "", match.group(1)).upper()
                if len(compact) in {10, 13}:
                    result.fields.append(
                        ExtractedField(
                            "isbn_candidate",
                            compact,
                            ids,
                            mean_confidence,
                            "rule:isbn",
                            "review",
                        )
                    )
            if match := _PRICE_RE.search(text):
                result.fields.append(
                    ExtractedField(
                        "printed_price",
                        match.group(1).strip(),
                        ids,
                        mean_confidence,
                        "rule:price",
                        _status(mean_confidence),
                    )
                )
            if _PUBLISHER_RE.search(text):
                result.fields.append(
                    ExtractedField(
                        "publisher",
                        text,
                        ids,
                        mean_confidence,
                        "rule:publisher",
                        _status(mean_confidence),
                    )
                )
            for role, pattern in _ROLE_PATTERNS.items():
                if match := pattern.match(text):
                    result.fields.append(
                        ExtractedField(
                            f"contributor.{role}",
                            match.group(1).strip(),
                            ids,
                            mean_confidence,
                            f"rule:{role}",
                            _status(mean_confidence),
                        )
                    )
            if match := _URL_RE.search(text):
                result.fields.append(
                    ExtractedField(
                        "publisher_url",
                        match.group(0).rstrip(".,;)"),
                        ids,
                        mean_confidence,
                        "rule:url",
                        _status(mean_confidence),
                    )
                )

        front_inside_lines = _lines(tokens, "front_inside")
        for line in front_inside_lines:
            text = _line_text(line)
            ids = tuple(token.token_id for token in line)
            mean_confidence = sum(token.confidence for token in line) / len(line)
            if match := _YEAR_RE.search(text):
                result.fields.append(
                    ExtractedField(
                        "publication_date",
                        match.group(1),
                        ids,
                        mean_confidence,
                        "rule:front-inside-year",
                        _status(mean_confidence),
                    )
                )
            if match := _EDITION_RE.search(text):
                result.fields.append(
                    ExtractedField(
                        "edition_statement",
                        match.group(0).strip(),
                        ids,
                        mean_confidence,
                        "rule:front-inside-edition",
                        _status(mean_confidence),
                    )
                )
                result.fields.append(
                    ExtractedField(
                        "printing_number",
                        match.group(1),
                        ids,
                        mean_confidence,
                        "rule:front-inside-printing",
                        _status(mean_confidence),
                    )
                )
            if match := _PRINTER_RE.match(text):
                result.fields.append(
                    ExtractedField(
                        "printer",
                        match.group(1).strip(),
                        ids,
                        mean_confidence,
                        "rule:front-inside-printer",
                        _status(mean_confidence),
                    )
                )
            if match := _PLACE_RE.match(text):
                result.fields.append(
                    ExtractedField(
                        "publication_place",
                        match.group(1).strip(),
                        ids,
                        mean_confidence,
                        "rule:front-inside-place",
                        _status(mean_confidence),
                    )
                )

        back_inside_lines = _lines(tokens, "back_inside")
        for line in back_inside_lines:
            text = _line_text(line)
            ids = tuple(token.token_id for token in line)
            mean_confidence = sum(token.confidence for token in line) / len(line)
            if match := _PAGE_COUNT_RE.search(text):
                result.fields.append(
                    ExtractedField(
                        "page_count",
                        match.group(1),
                        ids,
                        mean_confidence,
                        "rule:back-inside-page-count",
                        _status(mean_confidence),
                    )
                )
            if match := _DIMENSIONS_RE.search(text):
                result.fields.append(
                    ExtractedField(
                        "dimensions",
                        match.group(1),
                        ids,
                        mean_confidence,
                        "rule:back-inside-dimensions",
                        _status(mean_confidence),
                    )
                )

        result.fields.extend(_kunye_fields(front_inside_lines))
        result.fields.extend(_kunye_fields(back_inside_lines))

        positioned_back_inside_lines = [
            (line, box) for line in back_inside_lines if (box := _line_bbox(line)) is not None
        ]
        if positioned_back_inside_lines:
            bottom_line, _bottom_box = max(
                positioned_back_inside_lines,
                key=lambda item: (item[1][3], item[1][1]),
            )
            bottom_text = _line_text(bottom_line)
            bottom_confidence = _line_confidence(bottom_line)
            if (
                (match := _FINAL_PAGE_NUMBER_RE.fullmatch(bottom_text))
                and 16 <= int(match.group(1)) <= 99_999
                and bottom_confidence >= 0.80
            ):
                result.fields.append(
                    ExtractedField(
                        "page_count",
                        str(int(match.group(1))),
                        tuple(token.token_id for token in bottom_line),
                        min(bottom_confidence, 0.97),
                        "layout:back-inside-final-page-number",
                        "review",
                    )
                )

        front_lines = _lines(tokens, "front")
        title_group = _front_title_group(front_lines)
        if title_group:
            front_title = " ".join(_line_text(line) for line in title_group)
            front_ids = tuple(token.token_id for line in title_group for token in line)
            front_confidence = min(
                _title_layout_ceiling(front_lines, title_group),
                *(_line_confidence(line) for line in title_group),
            )
            front_field = ExtractedField(
                "title",
                front_title,
                front_ids,
                front_confidence,
                "layout:multiline-title-candidate",
                _status(front_confidence),
            )
            fallback = _front_inside_title_fallback(
                front_title,
                front_inside_lines,
            )
            if fallback is None:
                result.fields.append(front_field)
            else:
                fallback_text = _line_text(fallback)
                # The colophon heading corroborates the front cover, but only an
                # exact match is independent confirmation. `_front_inside_title_fallback`
                # also accepts a fuzzy ratio, and lifting the ceiling for those
                # would let "KÜÇÜK PRENSES" replace "KÜÇÜK PRENS" automatically.
                exact = _evidence_form(fallback_text) == _evidence_form(front_title)
                fallback_confidence = min(
                    _TITLE_CEILING_DOMINANT if exact else _TITLE_CEILING_AMBIGUOUS,
                    _line_confidence(fallback),
                )
                fallback_field = ExtractedField(
                    "title",
                    fallback_text,
                    tuple(token.token_id for token in fallback),
                    fallback_confidence,
                    "layout:front-inside-title-fallback",
                    _status(fallback_confidence),
                )
                front_form = _evidence_form(front_title)
                fallback_form = _evidence_form(fallback_text)
                if front_form in fallback_form and len(fallback_form) > len(front_form):
                    result.fields.append(fallback_field)
                else:
                    result.fields.extend((front_field, fallback_field))

    @staticmethod
    def _deduplicate(fields: Sequence[ExtractedField]) -> list[ExtractedField]:
        chosen: dict[tuple[str, str], ExtractedField] = {}
        for item in fields:
            key = (item.field_name, _evidence_form(item.value))
            current = chosen.get(key)
            if current is None or item.confidence > current.confidence:
                chosen[key] = item
        return sorted(chosen.values(), key=lambda item: (item.field_name, item.value))


class LlamaFieldClient:
    """Loopback-only client for a separately managed Qwen llama-server."""

    def __init__(self, endpoint: str, *, timeout_seconds: float = 120.0) -> None:
        parsed = urllib.parse.urlparse(endpoint)
        if parsed.scheme != "http" or parsed.hostname not in {"127.0.0.1", "localhost", "::1"}:
            raise ValueError("Alan çıkarıcı yalnız yerel loopback endpoint kullanabilir")
        self.endpoint = endpoint.rstrip("/")
        self.timeout_seconds = timeout_seconds

    def extract(self, tokens: Sequence[EvidenceToken]) -> list[dict[str, Any]]:
        evidence = [
            {
                "id": token.token_id,
                "text": token.text,
                "cover": token.cover,
                "line": token.line_index,
                "confidence": token.confidence,
            }
            for token in tokens
        ]
        system = (
            "You classify existing OCR evidence from four ordered book surfaces. "
            "Roles: front=title/author/publisher; front_inside=copyright, publication "
            "year/place, edition, printer, translator; back_inside=page count and "
            "dimensions; back=ISBN/barcode, price and synopsis. Return JSON only. "
            "Never invent, correct, translate or expand text. Every value must be composed "
            "only from the evidence_token_ids you cite."
        )
        user = json.dumps(
            {
                "allowed_fields": list(ALLOWED_MODEL_FIELDS),
                "tokens": evidence,
                "output": {
                    "fields": [
                        {
                            "field_name": "string",
                            "value": "verbatim evidence text",
                            "evidence_token_ids": ["id"],
                            "confidence": 0.0,
                        }
                    ]
                },
            },
            ensure_ascii=False,
        )
        body = json.dumps(
            {
                "model": "qwen3-field-extractor",
                "temperature": 0,
                "messages": [
                    {"role": "system", "content": system},
                    {"role": "user", "content": user},
                ],
                "response_format": {"type": "json_object"},
            }
        ).encode("utf-8")
        request = urllib.request.Request(
            f"{self.endpoint}/v1/chat/completions",
            data=body,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=self.timeout_seconds) as response:
                payload = json.load(response)
        except urllib.error.HTTPError as exc:
            detail = exc.read(4000).decode("utf-8", errors="replace").strip()
            raise ValueError(f"Qwen HTTP {exc.code}: {detail or exc.reason}") from exc
        content = payload["choices"][0]["message"]["content"]
        parsed = json.loads(content)
        if not isinstance(parsed, dict) or "fields" not in parsed:
            raise ValueError("Qwen yanıt şeması geçersiz: fields alanı eksik")
        fields = parsed["fields"]
        if not isinstance(fields, list) or any(not isinstance(item, dict) for item in fields):
            raise ValueError("Qwen yanıt şeması geçersiz: fields nesne listesi olmalıdır")
        return fields
