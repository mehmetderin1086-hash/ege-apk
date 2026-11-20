from __future__ import annotations

import os
from pathlib import Path

from PIL import Image, ImageDraw

from kitapkatalog.domain import CoverRole
from kitapkatalog.pairing import (
    classify_cover_filename,
    discover_images,
    pair_cover_files,
)


def _touch(path: Path, timestamp: float = 1000.0) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.touch()
    os.utime(path, (timestamp, timestamp))
    return path


def test_turkish_and_english_filename_roles_are_paired(tmp_path: Path) -> None:
    paths = [
        _touch(tmp_path / "İnce_Memed_ön_kapak.jpg"),
        _touch(tmp_path / "İnce_Memed_arka_kapak.jpg"),
        _touch(tmp_path / "Dune-front.png"),
        _touch(tmp_path / "Dune-back.png"),
    ]

    result = pair_cover_files(reversed(paths), infer_sequence=False)

    assert len(result.pairs) == 2
    assert not result.unpaired
    assert not result.ambiguous
    assert all(pair.confidence == 0.99 for pair in result.pairs)
    assert all(not pair.needs_review for pair in result.pairs)


def test_four_surface_role_names_form_a_complete_book(tmp_path: Path) -> None:
    paths = [
        _touch(tmp_path / "İnce_Memed_ön_kapak.jpg"),
        _touch(tmp_path / "İnce_Memed_ön_iç_kapak.jpg"),
        _touch(tmp_path / "İnce_Memed_arka_iç_kapak.jpg"),
        _touch(tmp_path / "İnce_Memed_arka_kapak.jpg"),
    ]

    result = pair_cover_files(
        reversed(paths),
        infer_sequence=False,
        require_four_surfaces=True,
    )

    assert len(result.pairs) == 1
    assert result.pairs[0].complete_four_surface
    assert result.pairs[0].basis == "four_role_filename"
    assert not result.unpaired


def test_unlabelled_four_document_sequence_requires_review(tmp_path: Path) -> None:
    paths = [_touch(tmp_path / f"IMG_{index:04d}.JPG", 1000.0 + index) for index in range(1, 5)]

    result = pair_cover_files(paths, require_four_surfaces=True)

    assert len(result.pairs) == 1
    assert result.pairs[0].front == paths[0]
    assert result.pairs[0].front_inside == paths[1]
    assert result.pairs[0].back_inside == paths[2]
    assert result.pairs[0].back == paths[3]
    assert result.pairs[0].needs_review


def test_unlabelled_capture_sequence_is_proposed_for_review(tmp_path: Path) -> None:
    paths = [
        _touch(tmp_path / "IMG_0001.JPG", 1000.0),
        _touch(tmp_path / "IMG_0002.JPG", 1001.0),
        _touch(tmp_path / "IMG_0003.JPG", 1010.0),
        _touch(tmp_path / "IMG_0004.JPG", 1011.0),
    ]

    result = pair_cover_files(paths)

    assert len(result.pairs) == 2
    assert result.needs_review_count == 2
    assert len(result.ambiguous) == 2
    assert result.pairs[0].front.name == "IMG_0001.JPG"
    assert result.pairs[0].back.name == "IMG_0002.JPG"


def test_duplicate_named_candidates_are_not_silently_accepted(tmp_path: Path) -> None:
    paths = [
        _touch(tmp_path / "book_front.jpg"),
        _touch(tmp_path / "book_front.png"),
        _touch(tmp_path / "book_back.jpg"),
        _touch(tmp_path / "book_back.png"),
    ]

    result = pair_cover_files(paths, infer_sequence=False)

    assert len(result.pairs) == 2
    assert len(result.ambiguous) == 1
    assert all(pair.needs_review for pair in result.pairs)
    assert all(pair.basis == "ambiguous_filename" for pair in result.pairs)


def test_discovery_filters_non_images_and_classification_is_boundary_based(
    tmp_path: Path,
) -> None:
    _touch(tmp_path / "nested" / "book_on.jpg")
    _touch(tmp_path / "nested" / "book_arka.jpeg")
    _touch(tmp_path / "notes.txt")

    images = discover_images(tmp_path)

    assert [path.name for path in images] == ["book_arka.jpeg", "book_on.jpg"]
    assert classify_cover_filename("London.jpg") is None
    assert classify_cover_filename("book_on.jpg") == (CoverRole.FRONT, "book")
    assert classify_cover_filename("book_arka.jpg") == (CoverRole.BACK, "book")


def test_visual_text_density_orients_unlabelled_pair_for_review(
    tmp_path: Path,
) -> None:
    back_first = tmp_path / "IMG_0001.png"
    front_second = tmp_path / "IMG_0002.png"
    back = Image.new("L", (500, 700), "white")
    draw = ImageDraw.Draw(back)
    for top in range(80, 620, 18):
        draw.rectangle((50, top, 450, top + 4), fill="black")
    back.save(back_first)
    Image.new("L", (500, 700), "white").save(front_second)
    os.utime(back_first, (1000.0, 1000.0))
    os.utime(front_second, (1001.0, 1001.0))

    result = pair_cover_files((back_first, front_second))

    assert len(result.pairs) == 1
    pair = result.pairs[0]
    assert pair.front == front_second
    assert pair.back == back_first
    assert pair.needs_review
    assert "barcode_text_density" in pair.basis
