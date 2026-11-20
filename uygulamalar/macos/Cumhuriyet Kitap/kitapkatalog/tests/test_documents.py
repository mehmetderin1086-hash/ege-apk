from __future__ import annotations

from pathlib import Path

import pytest
from PIL import Image

import kitapkatalog.documents as documents
from kitapkatalog.documents import (
    DocumentInputError,
    build_single_book_scan,
    expand_bulk_documents,
    pdf_page_count,
)
from kitapkatalog.domain import CoverRole
from kitapkatalog.pairing import pair_cover_files


def _pdf(path: Path, colors: list[str]) -> Path:
    pages = [Image.new("RGB", (180, 240), color) for color in colors]
    pages[0].save(path, "PDF", save_all=True, append_images=pages[1:], resolution=72)
    return path


def test_four_page_pdf_becomes_one_ordered_book(tmp_path: Path) -> None:
    source = _pdf(tmp_path / "kitap.pdf", ["red", "green", "blue", "yellow"])

    scan = build_single_book_scan([source], tmp_path / "rendered")

    assert pdf_page_count(source) == 4
    assert scan.complete_four_surface
    assert scan.basis == "single_four_page_pdf"
    assert scan.active_roles == tuple(CoverRole)
    for path in scan.paths_by_role.values():
        assert path is not None and path.is_file() and path.suffix == ".png"

    # PDF sayfa sırasının yüz rollerine gerçekten korunduğunu piksel düzeyinde doğrula.
    expected = {
        CoverRole.FRONT: (255, 0, 0),
        CoverRole.FRONT_INSIDE: (0, 128, 0),
        CoverRole.BACK_INSIDE: (0, 0, 255),
        CoverRole.BACK: (255, 255, 0),
    }
    for role, expected_rgb in expected.items():
        with Image.open(scan.paths_by_role[role]) as image:
            actual = image.convert("RGB").getpixel((image.width // 2, image.height // 2))
        assert all(
            abs(channel - target) <= 5 for channel, target in zip(actual, expected_rgb, strict=True)
        )


def test_manual_single_book_accepts_images_and_single_page_pdfs(tmp_path: Path) -> None:
    front = tmp_path / "front.png"
    back = tmp_path / "back.png"
    Image.new("RGB", (40, 60), "white").save(front)
    Image.new("RGB", (40, 60), "black").save(back)
    front_inside = _pdf(tmp_path / "front_inside.pdf", ["green"])
    back_inside = _pdf(tmp_path / "back_inside.pdf", ["blue"])

    scan = build_single_book_scan(
        [front, front_inside, back_inside, back],
        tmp_path / "rendered",
    )

    assert scan.front == front
    assert scan.back == back
    assert scan.front_inside is not None and scan.front_inside.suffix == ".png"
    assert scan.back_inside is not None and scan.back_inside.suffix == ".png"


def test_isbn_barcode_resolves_reversed_last_two_surfaces(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    paths = tuple(tmp_path / f"page-{index}.png" for index in range(1, 5))
    for path in paths:
        Image.new("RGB", (40, 60), "white").save(path)

    monkeypatch.setattr(
        documents,
        "_isbn_barcode_presence",
        lambda path: path == paths[2],
    )

    scan = build_single_book_scan(paths, tmp_path / "rendered")

    assert scan.front == paths[0]
    assert scan.front_inside == paths[1]
    assert scan.back_inside == paths[3]
    assert scan.back == paths[2]
    assert scan.basis.endswith("+isbn_barcode_roles")


def test_ambiguous_barcode_probe_preserves_selected_order(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    paths = tuple(tmp_path / f"page-{index}.png" for index in range(1, 5))
    for path in paths:
        Image.new("RGB", (40, 60), "white").save(path)

    monkeypatch.setattr(documents, "_isbn_barcode_presence", lambda _path: None)

    scan = build_single_book_scan(paths, tmp_path / "rendered")

    assert scan.back_inside == paths[2]
    assert scan.back == paths[3]
    assert not scan.basis.endswith("+isbn_barcode_roles")


def test_bulk_single_page_pdfs_keep_role_names_for_pairing(tmp_path: Path) -> None:
    documents = [
        _pdf(tmp_path / "ince_memed_on.pdf", ["red"]),
        _pdf(tmp_path / "ince_memed_on_ic.pdf", ["green"]),
        _pdf(tmp_path / "ince_memed_arka_ic.pdf", ["blue"]),
        _pdf(tmp_path / "ince_memed_arka.pdf", ["yellow"]),
    ]

    expanded = expand_bulk_documents(documents, tmp_path / "rendered")
    paired = pair_cover_files(
        expanded.images,
        infer_sequence=False,
        require_four_surfaces=True,
    )

    assert not expanded.rejected
    assert len(paired.pairs) == 1
    assert paired.pairs[0].complete_four_surface
    assert not paired.pairs[0].needs_review


def test_non_four_page_book_pdf_is_explicitly_rejected(tmp_path: Path) -> None:
    source = _pdf(tmp_path / "three-pages.pdf", ["red", "green", "blue"])

    with pytest.raises(DocumentInputError, match="dört sayfa"):
        build_single_book_scan([source], tmp_path / "rendered")

    expanded = expand_bulk_documents([source], tmp_path / "rendered")
    assert len(expanded.rejected) == 1
    assert "4'ün katı" in expanded.rejected[0][1]


def test_every_uploadable_image_suffix_survives_preprocessing() -> None:
    """Yüklemede kabul edilen her görüntü uzantısı ön işlemede de desteklenmeli.

    Aksi hâlde dosya kuyruğa girer ama OCR aşamasında ImageProcessingError ile
    patlar; kullanıcı hatayı ancak işleme başlayınca görür (.bmp regresyonu).
    """
    from kitapkatalog.images import SUPPORTED_SUFFIXES
    from kitapkatalog.webapp.routes_imports import _UPLOAD_SUFFIXES

    image_uploads = {s for s in _UPLOAD_SUFFIXES if s not in {".pdf", ".zip"}}
    assert image_uploads <= SUPPORTED_SUFFIXES
    assert documents.SUPPORTED_IMAGE_SUFFIXES <= SUPPORTED_SUFFIXES
