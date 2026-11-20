from __future__ import annotations

from types import SimpleNamespace

from kitapkatalog.isbn import (
    BarcodeObservation,
    IsbnCandidate,
    ZxingBarcodeScanner,
    _candidate_strings,
    _resolves_to_isbn13_prefix,
    canonical_isbn,
    extract_isbn_candidates,
    is_book_ean,
    is_valid_isbn10,
    is_valid_isbn13,
    isbn10_check_digit,
    isbn10_to_isbn13,
    isbn13_check_digit,
    merge_isbn_evidence,
    normalize_isbn,
    recover_unique_isbn,
)


def test_isbn_check_digits_and_conversion() -> None:
    assert isbn10_check_digit("030640615") == "2"
    assert isbn13_check_digit("978030640615") == "7"
    assert is_valid_isbn10("0-306-40615-2")
    assert is_valid_isbn13("978-0-306-40615-7")
    assert isbn10_to_isbn13("0-306-40615-2") == "9780306406157"
    assert normalize_isbn("978 975 363 802 9") == "9789753638029"


def test_979_isbn_and_non_book_ean_are_separated() -> None:
    body = "979123456789"
    isbn = body + isbn13_check_digit(body)
    assert is_valid_isbn13(isbn)
    assert is_book_ean(isbn)
    assert not is_book_ean("8691234567890")
    assert not is_valid_isbn13("9771234567898")


def test_invalid_check_digit_is_rejected() -> None:
    assert normalize_isbn("9789753638028") is None
    assert not is_valid_isbn10("0306406153")
    assert recover_unique_isbn("978-975-363-802-8") is None


def test_ocr_confusion_is_repaired_only_to_a_valid_isbn() -> None:
    assert recover_unique_isbn("978-975-363-8O2-9") == ("9789753638029", True)
    candidates = extract_isbn_candidates(
        "Arka kapak\nISBN: 978-975-363-8O2-9\nBaskı 2024",
        source="ocr:tesseract",
    )
    assert candidates == (
        IsbnCandidate(
            isbn="9789753638029",
            kind="ISBN-13",
            raw="978-975-363-8O2-9",
            source="ocr:tesseract",
            corrected=True,
        ),
    )


def test_z_ocr_confusion_is_repaired_only_to_a_valid_isbn() -> None:
    assert recover_unique_isbn("97897536380Z9") == ("9789753638029", True)
    assert recover_unique_isbn("97897536380z9") == ("9789753638029", True)


def test_z_ocr_confusion_with_a_broken_checksum_is_rejected() -> None:
    assert recover_unique_isbn("97897536380Z1") is None


def test_g_ocr_confusion_is_repaired_only_to_a_valid_isbn() -> None:
    assert recover_unique_isbn("9789753G38029") == ("9789753638029", True)


def test_g_ocr_confusion_with_a_broken_checksum_is_rejected() -> None:
    assert recover_unique_isbn("9789753G38021") is None


def test_g_and_q_lowercase_ocr_confusion_is_repaired_only_to_a_valid_isbn() -> None:
    assert recover_unique_isbn("978g753638029") == ("9789753638029", True)
    assert recover_unique_isbn("978q753638029") == ("9789753638029", True)


def test_g_and_q_lowercase_ocr_confusion_with_a_broken_checksum_is_rejected() -> None:
    assert recover_unique_isbn("978g753638021") is None
    assert recover_unique_isbn("978q753638021") is None


def test_d_and_q_uppercase_ocr_confusion_is_repaired_only_to_a_valid_isbn() -> None:
    assert recover_unique_isbn("9789753638D29") == ("9789753638029", True)
    assert recover_unique_isbn("9789753638Q29") == ("9789753638029", True)


def test_d_and_q_uppercase_ocr_confusion_with_a_broken_checksum_is_rejected() -> None:
    assert recover_unique_isbn("9789753638D21") is None
    assert recover_unique_isbn("9789753638Q21") is None


def test_a_ocr_confusion_is_repaired_only_to_a_valid_isbn() -> None:
    # 9789753638043 is the checksum-valid ISBN-13 whose twelfth digit is a 4,
    # which the existing base "...029" fixture never exercises.
    assert recover_unique_isbn("97897536380A3") == ("9789753638043", True)


def test_a_ocr_confusion_with_a_broken_checksum_is_rejected() -> None:
    assert recover_unique_isbn("97897536380A1") is None


def test_isbn13_prefix_elimination_short_circuits_unresolvable_candidates() -> None:
    # A genuine 978/979 prefix, even spelled through OCR-confusable letters,
    # is resolvable.
    assert _resolves_to_isbn13_prefix(list("978"))
    assert _resolves_to_isbn13_prefix(["9", "7", "B"])  # B -> 8
    # A prefix that can never spell 978/979 short-circuits candidate
    # generation instead of exploring the combinatorial space for nothing.
    assert not _resolves_to_isbn13_prefix(list("977"))
    assert _candidate_strings("1234567890123") == set()


def test_isbn13_prefix_elimination_does_not_affect_isbn10_candidates() -> None:
    # A ten-character candidate never reaches the 978/979 prefix check, so an
    # OCR-confusable ISBN-10 still resolves normally.
    assert recover_unique_isbn("030640615Z") == ("0306406152", True)
    assert _candidate_strings("030640615Z") == {"0306406152"}


def test_duplicate_isbn_occurrences_are_collapsed() -> None:
    candidates = extract_isbn_candidates(
        "ISBN 978-0-306-40615-7 / yine 9780306406157",
    )
    assert [candidate.isbn for candidate in candidates] == ["9780306406157"]


def test_barcode_ocr_conflict_is_explicit() -> None:
    ocr = (IsbnCandidate("9789753638029", "ISBN-13", "9789753638029", "ocr", False),)
    barcode = (BarcodeObservation("9780306406157", "EAN13", "9780306406157", None),)
    values, conflict = merge_isbn_evidence(ocr, barcode)
    # A single OCR engine is retained for review but is not an accepted
    # automatic identifier.
    assert values == ("9780306406157",)
    assert conflict


def test_matching_barcode_and_ocr_do_not_conflict() -> None:
    ocr = (IsbnCandidate("9780306406157", "ISBN-13", "9780306406157", "ocr", False),)
    barcode = (BarcodeObservation("9780306406157", "EAN13", "9780306406157", None),)
    assert merge_isbn_evidence(ocr, barcode) == (("9780306406157",), False)


def test_ocr_only_isbn_requires_two_independent_engines() -> None:
    single = (
        IsbnCandidate("9780306406157", "ISBN-13", "9780306406157", "ocr:tesseract", False),
        IsbnCandidate("9780306406157", "ISBN-13", "9780306406157", "ocr:consensus", False),
    )
    assert merge_isbn_evidence(single, ()) == ((), False)
    corroborated = (
        *single,
        IsbnCandidate("9780306406157", "ISBN-13", "9780306406157", "ocr:easyocr", False),
    )
    assert merge_isbn_evidence(corroborated, ()) == (("9780306406157",), False)


def test_partial_barcode_ocr_overlap_is_a_conflict() -> None:
    ocr = (
        IsbnCandidate("9780306406157", "ISBN-13", "", "ocr:tesseract", False),
        IsbnCandidate("9780306406157", "ISBN-13", "", "ocr:easyocr", False),
        IsbnCandidate("9789753638029", "ISBN-13", "", "ocr:tesseract", False),
        IsbnCandidate("9789753638029", "ISBN-13", "", "ocr:easyocr", False),
    )
    barcode = (BarcodeObservation("9780306406157", "EAN13", "9780306406157", None),)
    assert merge_isbn_evidence(ocr, barcode) == (
        ("9780306406157", "9789753638029"),
        True,
    )


def test_isbn10_and_equivalent_isbn13_share_one_canonical_value() -> None:
    assert canonical_isbn("0-306-40615-2") == "9780306406157"
    ocr = (IsbnCandidate("0306406152", "ISBN-10", "", "ocr:tesseract", False),)
    barcode = (BarcodeObservation("9780306406157", "EAN13", "9780306406157", None),)
    assert merge_isbn_evidence(ocr, barcode) == (("9780306406157",), False)


class _FakeZxing:
    """Counts decode attempts; only succeeds on a transformed copy."""

    def __init__(self, *, succeed_after: int) -> None:
        self.succeed_after = succeed_after
        self.calls = 0

    def read_barcodes(self, array: object) -> list[object]:
        self.calls += 1
        if self.calls <= self.succeed_after:
            return []
        return [SimpleNamespace(text="9789753638029", format="EAN13", position=None)]


def _grey_array(size: tuple[int, int] = (60, 40)) -> object:
    import numpy as np

    return np.zeros((size[1], size[0], 3), dtype="uint8")


def test_a_front_cover_pays_a_single_decode_attempt() -> None:
    from PIL import Image

    zxing = _FakeZxing(succeed_after=99)

    found, transformed = ZxingBarcodeScanner._decode_with_retries(
        _grey_array(), zxingcpp=zxing, image_module=Image, exhaustive=False
    )

    # Four surfaces × two variants × a five-step ladder would be forty decodes
    # per book, thirty-two of them on surfaces that never carry a barcode.
    assert zxing.calls == 1
    assert list(found) == []
    assert transformed is False


def test_a_back_cover_climbs_the_ladder_until_it_reads() -> None:
    from PIL import Image

    zxing = _FakeZxing(succeed_after=2)

    found, transformed = ZxingBarcodeScanner._decode_with_retries(
        _grey_array(), zxingcpp=zxing, image_module=Image, exhaustive=True
    )

    assert zxing.calls == 3  # full size, 2×, then 0.5× succeeded
    assert len(list(found)) == 1
    # The match came from a rescaled copy, so its coordinates are not the
    # original frame's.
    assert transformed is True


def test_a_clean_back_cover_still_costs_one_decode() -> None:
    from PIL import Image

    zxing = _FakeZxing(succeed_after=0)

    found, transformed = ZxingBarcodeScanner._decode_with_retries(
        _grey_array(), zxingcpp=zxing, image_module=Image, exhaustive=True
    )

    assert zxing.calls == 1
    assert len(list(found)) == 1
    assert transformed is False
