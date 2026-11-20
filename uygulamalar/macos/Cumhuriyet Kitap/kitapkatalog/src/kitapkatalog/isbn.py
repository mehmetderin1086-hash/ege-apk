"""ISBN validation, OCR candidate recovery, and offline barcode decoding."""

from __future__ import annotations

import itertools
import re
import unicodedata
from collections.abc import Iterable
from dataclasses import dataclass
from pathlib import Path
from typing import Any

_ISBN_LABEL = re.compile(
    r"(?i)\bISBN(?:-1[03])?\s*:?\s*([0-9XxOolIıİSBbZzGgqDQA\-\u2010-\u2015\s]{10,28})"
)
_BARE_CANDIDATE = re.compile(
    r"(?<![0-9A-Za-z])(?:97[89OolIıİSBbgq][0-9OolIıİSBbZzGgqDQA\-\u2010-\u2015\s]{9,22}"
    r"|[0-9OolIıİSBbZzGgqDQA][0-9OolIıİSBbZzGgqDQA\-\u2010-\u2015\s]{8,18}"
    r"[0-9XxOolIıİSBbZzGgqDQA])"
    r"(?![0-9A-Za-z])"
)
_DASHES = "\u2010\u2011\u2012\u2013\u2014\u2015"
_OCR_DIGIT_OPTIONS: dict[str, tuple[str, ...]] = {
    "O": ("0",),
    "o": ("0",),
    "I": ("1",),
    "İ": ("1",),
    "ı": ("1",),
    "l": ("1",),
    "S": ("5",),
    "s": ("5",),
    "B": ("8",),
    "b": ("8",),
    "Z": ("2",),
    "z": ("2",),
    "G": ("6",),
    "g": ("9",),
    "q": ("9",),
    "D": ("0",),
    "Q": ("0",),
    "A": ("4",),
}


class BarcodeDependencyError(RuntimeError):
    """ZXing-C++ or an image bridge is not installed."""


@dataclass(frozen=True, slots=True)
class IsbnCandidate:
    isbn: str
    kind: str
    raw: str
    source: str
    corrected: bool


@dataclass(frozen=True, slots=True)
class BarcodeObservation:
    text: str
    format: str
    isbn: str | None
    polygon: tuple[tuple[float, float], ...] | None
    variant: str = "canonical"


def compact_identifier(value: str) -> str:
    normalized = unicodedata.normalize("NFKC", value)
    return "".join(
        character for character in normalized if character.isdigit() or character in "Xx"
    )


def isbn10_check_digit(first_nine: str) -> str:
    if len(first_nine) != 9 or not first_nine.isdigit():
        raise ValueError("ISBN-10 gövdesi tam dokuz rakam olmalıdır")
    remainder = (
        sum((10 - index) * int(character) for index, character in enumerate(first_nine)) % 11
    )
    check = (11 - remainder) % 11
    return "X" if check == 10 else str(check)


def isbn13_check_digit(first_twelve: str) -> str:
    if len(first_twelve) != 12 or not first_twelve.isdigit():
        raise ValueError("ISBN-13 gövdesi tam on iki rakam olmalıdır")
    total = sum(
        int(character) * (1 if index % 2 == 0 else 3)
        for index, character in enumerate(first_twelve)
    )
    return str((10 - total % 10) % 10)


def is_valid_isbn10(value: str) -> bool:
    compact = compact_identifier(value).upper()
    return (
        len(compact) == 10
        and compact[:9].isdigit()
        and compact[-1] in "0123456789X"
        and isbn10_check_digit(compact[:9]) == compact[-1]
    )


def is_valid_isbn13(value: str) -> bool:
    compact = compact_identifier(value)
    return (
        len(compact) == 13
        and compact.isdigit()
        and compact.startswith(("978", "979"))
        and isbn13_check_digit(compact[:12]) == compact[-1]
    )


def normalize_isbn(value: str) -> str | None:
    compact = compact_identifier(value).upper()
    if is_valid_isbn10(compact) or is_valid_isbn13(compact):
        return compact
    return None


def isbn10_to_isbn13(value: str) -> str:
    compact = compact_identifier(value).upper()
    if not is_valid_isbn10(compact):
        raise ValueError(f"Geçersiz ISBN-10: {value}")
    body = "978" + compact[:9]
    return body + isbn13_check_digit(body)


def canonical_isbn(value: str) -> str | None:
    """Return one comparison/storage form for equivalent ISBN-10/13 values.

    A valid ISBN-10 and its 978-prefixed ISBN-13 identify the same edition.
    Normalising both to ISBN-13 prevents a harmless representation difference
    from being reported as a barcode/OCR conflict or stored twice.
    """

    normalized = normalize_isbn(value)
    if normalized is None:
        return None
    return isbn10_to_isbn13(normalized) if len(normalized) == 10 else normalized


def _resolves_to_isbn13_prefix(prefix_characters: list[str]) -> bool:
    """Whether the first three characters can plausibly spell 978 or 979.

    Checked before the full combinatorial expansion so a barcode-shaped
    13-character candidate that can never carry a valid ISBN-13 prefix (a
    phone number, a shelf code) does not pay for candidate generation it
    could never use.  ISBN-10 candidates are ten characters long and never
    reach this check.
    """

    options = [
        _OCR_DIGIT_OPTIONS.get(character, (character.upper(),)) for character in prefix_characters
    ]
    return any("".join(combo) in ("978", "979") for combo in itertools.product(*options))


def _candidate_strings(raw: str, *, max_ambiguous: int = 5) -> set[str]:
    """Return exact/uniquely recoverable digit strings.

    OCR substitutions are explored only inside an ISBN-shaped candidate and
    capped to avoid a combinatorial or speculative repair.  The caller accepts
    a correction only when exactly one valid ISBN survives.
    """

    characters = [
        character
        for character in unicodedata.normalize("NFKC", raw)
        if character.isalnum() and character not in _DASHES
    ]
    ambiguous_positions = [
        index for index, character in enumerate(characters) if character in _OCR_DIGIT_OPTIONS
    ]
    if len(ambiguous_positions) > max_ambiguous:
        return set()
    if len(characters) == 13 and not _resolves_to_isbn13_prefix(characters[:3]):
        return set()
    variants = [""]
    for character in characters:
        options = _OCR_DIGIT_OPTIONS.get(character, (character.upper(),))
        variants = [prefix + replacement for prefix in variants for replacement in options]
    return set(variants)


def recover_unique_isbn(raw: str) -> tuple[str, bool] | None:
    exact = normalize_isbn(raw)
    if exact:
        return exact, False
    valid: set[str] = set()
    for candidate in _candidate_strings(raw):
        normalized = normalize_isbn(candidate)
        if normalized:
            valid.add(normalized)
    if len(valid) == 1:
        return valid.pop(), True
    return None


def extract_isbn_candidates(text: str, *, source: str = "ocr") -> tuple[IsbnCandidate, ...]:
    seen: set[str] = set()
    results: list[IsbnCandidate] = []
    matches = [match.group(1) for match in _ISBN_LABEL.finditer(text)]
    matches.extend(match.group(0) for match in _BARE_CANDIDATE.finditer(text))
    for raw in matches:
        recovered = recover_unique_isbn(raw)
        if not recovered:
            continue
        isbn, corrected = recovered
        if isbn in seen:
            continue
        seen.add(isbn)
        results.append(
            IsbnCandidate(
                isbn=isbn,
                kind="ISBN-13" if len(isbn) == 13 else "ISBN-10",
                raw=raw.strip(),
                source=source,
                corrected=corrected,
            )
        )
    return tuple(results)


def is_book_ean(value: str) -> bool:
    compact = compact_identifier(value)
    return is_valid_isbn13(compact)


def _position_polygon(position: Any) -> tuple[tuple[float, float], ...] | None:
    if position is None:
        return None
    points: list[tuple[float, float]] = []
    for name in ("top_left", "top_right", "bottom_right", "bottom_left"):
        point = getattr(position, name, None)
        if point is None:
            return None
        points.append((float(point.x), float(point.y)))
    return tuple(points)


class ZxingBarcodeScanner:
    """ZXing-C++ adapter; barcode decoding is additional to the five OCR votes."""

    def availability(self) -> tuple[bool, tuple[str, ...]]:
        problems: list[str] = []
        try:
            import zxingcpp  # noqa: F401
        except ImportError:
            problems.append(
                "zxing-cpp eksik; `pip install 'kitapkatalog[vision]'` komutunu çalıştırın"
            )
        try:
            import numpy  # noqa: F401
        except ImportError:
            problems.append("NumPy eksik; `pip install 'kitapkatalog[vision]'` komutunu çalıştırın")
        return not problems, tuple(problems)

    @staticmethod
    def _decode_with_retries(
        array: Any,
        *,
        zxingcpp: Any,
        image_module: Any,
        exhaustive: bool,
    ) -> tuple[Iterable[Any], bool]:
        """Read the barcode; retry on rescaled and rotated copies if asked.

        A back cover photographed at an angle, or one whose barcode is small in
        a large frame, often fails a single full-resolution pass while decoding
        cleanly at a different scale.  The acceptance gate asks for 0.99 recall
        on readable barcodes, which one attempt does not reach.

        The ladder is only worth paying where a barcode can be.  A front cover
        never carries one, so running it there would spend several upscales of a
        multi-megapixel image per book to find nothing.  Attempts stop at the
        first success, so even a back cover that decodes cleanly costs one pass.

        Returns the matches and whether they came from a transformed copy, whose
        coordinates belong to that copy rather than to the original frame.
        """

        def decode(candidate: Any) -> Iterable[Any]:
            try:
                return zxingcpp.read_barcodes(candidate) or ()
            except Exception as exc:
                raise BarcodeDependencyError(f"ZXing-C++ barkod taraması başarısız: {exc}") from exc

        found = decode(array)
        if found or not exhaustive:
            return found, False
        import numpy as np

        base = image_module.fromarray(array)
        width, height = base.size
        for scale in (2.0, 0.5):
            resized = base.resize(
                (max(1, round(width * scale)), max(1, round(height * scale))),
                image_module.LANCZOS,
            )
            found = decode(np.asarray(resized))
            if found:
                return found, True
        # A rotated barcode reads as noise until the bars run the other way.
        for angle in (90, 270):
            found = decode(np.asarray(base.rotate(angle, expand=True)))
            if found:
                return found, True
        return (), False

    def scan(
        self,
        image_path: str | Path,
        *,
        variant: str = "canonical",
        exhaustive: bool = False,
    ) -> tuple[BarcodeObservation, ...]:
        available, problems = self.availability()
        if not available:
            raise BarcodeDependencyError("; ".join(problems))
        import numpy as np
        import zxingcpp
        from PIL import Image, ImageOps

        path = Path(image_path)
        if path.suffix.lower() in {".heic", ".heif"}:
            try:
                from pillow_heif import register_heif_opener
            except ImportError as exc:
                raise BarcodeDependencyError("HEIC barkod taraması için pillow-heif eksik") from exc
            register_heif_opener()
        try:
            with Image.open(path) as image:
                array = np.asarray(ImageOps.exif_transpose(image).convert("RGB"))
        except (OSError, ValueError) as exc:
            raise BarcodeDependencyError(f"Barkod görüntüsü açılamadı: {path}: {exc}") from exc

        decoded, transformed = self._decode_with_retries(
            array,
            zxingcpp=zxingcpp,
            image_module=Image,
            exhaustive=exhaustive,
        )

        observations: list[BarcodeObservation] = []
        for item in decoded:
            text = str(getattr(item, "text", "")).strip()
            if not text:
                continue
            format_value = getattr(item, "format", "unknown")
            format_name = getattr(format_value, "name", str(format_value))
            isbn = normalize_isbn(text) if len(compact_identifier(text)) in (10, 13) else None
            observations.append(
                BarcodeObservation(
                    text=text,
                    format=format_name,
                    isbn=isbn,
                    # A match found on a rescaled or rotated copy carries
                    # that copy's coordinates. Projecting them back is possible
                    # but unverified, and a wrong provenance box is worse than
                    # none in a catalogue that ties every accepted field to one.
                    polygon=(
                        None if transformed else _position_polygon(getattr(item, "position", None))
                    ),
                    variant=variant,
                )
            )
        return tuple(observations)


def merge_isbn_evidence(
    ocr_candidates: Iterable[IsbnCandidate],
    barcodes: Iterable[BarcodeObservation],
) -> tuple[tuple[str, ...], bool]:
    """Return safely accepted canonical ISBNs and an explicit conflict flag.

    A checksum-valid barcode is independently acceptable.  OCR-only ISBNs need
    matching observations from at least two distinct OCR engines.  The
    consensus text is derived from those engines and therefore never counts as
    an additional vote.  Any unequal non-empty barcode/OCR sets—including
    partial overlap—require review.
    """

    candidates = tuple(ocr_candidates)
    observations = tuple(barcodes)
    ocr_sources: dict[str, set[str]] = {}
    ocr_observed: set[str] = set()
    for candidate in candidates:
        canonical = canonical_isbn(candidate.isbn)
        if canonical is None:
            continue
        ocr_observed.add(canonical)
        source = candidate.source.strip()
        if source == "ocr:consensus":
            continue
        if source.startswith("ocr:"):
            engine_id = source.removeprefix("ocr:").strip()
        elif source == "ocr":
            engine_id = "ocr"
        else:
            # Only explicitly OCR-labelled evidence participates in the
            # independent-engine threshold.
            continue
        if engine_id and engine_id != "consensus":
            ocr_sources.setdefault(canonical, set()).add(engine_id)

    barcode = {
        canonical
        for observation in observations
        if observation.isbn
        if (canonical := canonical_isbn(observation.isbn)) is not None
    }
    corroborated_ocr = {isbn for isbn, sources in ocr_sources.items() if len(sources) >= 2}
    accepted = tuple(sorted(barcode | corroborated_ocr))
    conflict = len(barcode) > 1 or bool(barcode and ocr_observed and barcode != ocr_observed)
    return accepted, conflict
