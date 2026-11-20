"""Cover preprocessing and the provenance projection built on top of it.

Every automatically accepted field must point back at a box on the original
photograph.  That link is `homography_to_source` plus the projection below, so
an error here silently misplaces the evidence a reviewer is shown.
"""

from __future__ import annotations

import math
from pathlib import Path
from typing import Any

import pytest
from PIL import Image

from kitapkatalog.images import (
    PREFLIGHT_BLUR_FLOOR,
    CoverPreprocessor,
    ImageProcessingError,
    assess_upload_quality,
    project_point_to_source,
    project_polygon_to_source,
)

_IDENTITY = (1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0)


def _photo(path: Path, *, size: tuple[int, int] = (1200, 1800), color: str = "white") -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.new("RGB", size, color).save(path)
    return path


def test_identity_homography_leaves_a_point_where_it_was() -> None:
    assert project_point_to_source((12.5, 40.0), _IDENTITY) == (12.5, 40.0)


def test_translation_and_scale_are_applied_to_every_polygon_point() -> None:
    # Canonical coordinates halved and shifted: the usual downscale-plus-crop.
    homography = (2.0, 0.0, 30.0, 0.0, 2.0, 10.0, 0.0, 0.0, 1.0)

    projected = project_polygon_to_source(((0.0, 0.0), (10.0, 0.0), (10.0, 5.0)), homography)

    assert projected == ((30.0, 10.0), (50.0, 10.0), (50.0, 20.0))


def test_a_perspective_homography_divides_by_the_third_row() -> None:
    homography = (1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.5, 1.0)

    x, y = project_point_to_source((4.0, 2.0), homography)

    assert (x, y) == pytest.approx((2.0, 1.0))


def test_a_point_projected_to_infinity_is_refused_rather_than_guessed() -> None:
    # A denominator of zero means the point has no image in the source frame;
    # returning any coordinate would be an invented provenance box.
    homography = (1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0)

    with pytest.raises(ImageProcessingError, match="sonsuza"):
        project_point_to_source((1.0, 1.0), homography)


def test_a_homography_of_the_wrong_shape_is_rejected() -> None:
    with pytest.raises(ValueError, match="dokuz"):
        project_point_to_source((1.0, 1.0), (1.0, 0.0, 0.0))


def test_a_missing_polygon_stays_missing() -> None:
    assert project_polygon_to_source(None, _IDENTITY) is None


def test_preparation_is_content_addressed_and_repeatable(tmp_path: Path) -> None:
    source = _photo(tmp_path / "cover.jpg")
    preprocessor = CoverPreprocessor(tmp_path / "derivatives")

    first = preprocessor.prepare(source)
    second = preprocessor.prepare(source)

    assert first.canonical_sha256 == second.canonical_sha256
    assert first.source_sha256 == second.source_sha256
    assert first.homography_to_source == second.homography_to_source
    assert len(first.canonical_sha256) == 64


def test_prepared_covers_expose_the_variants_the_engines_read(tmp_path: Path) -> None:
    prepared = CoverPreprocessor(tmp_path / "derivatives").prepare(_photo(tmp_path / "cover.png"))

    # The three classic engines climb this same canonical/CLAHE/binarized
    # ladder, which is why consensus treats their agreement as correlated.
    assert prepared.variant_paths["canonical"].is_file()
    assert prepared.variant_paths["gray_clahe"].is_file()
    assert prepared.variant_paths["binarized"].is_file()


def test_a_small_photograph_is_flagged_for_the_reviewer(tmp_path: Path) -> None:
    prepared = CoverPreprocessor(tmp_path / "derivatives").prepare(
        _photo(tmp_path / "small.png", size=(400, 600))
    )

    assert any("1000 pikselden" in warning for warning in prepared.quality.warnings)


def test_a_blown_out_photograph_is_flagged(tmp_path: Path) -> None:
    prepared = CoverPreprocessor(tmp_path / "derivatives").prepare(
        _photo(tmp_path / "bright.png", color="white")
    )

    assert any("parlama" in warning for warning in prepared.quality.warnings)


def test_a_very_dark_photograph_is_flagged(tmp_path: Path) -> None:
    prepared = CoverPreprocessor(tmp_path / "derivatives").prepare(
        _photo(tmp_path / "dark.png", color="black")
    )

    assert any("karanlık" in warning for warning in prepared.quality.warnings)


# --------------------------------------------------------- assess_upload_quality


def test_preflight_warnings_are_labeled_so_they_are_not_mistaken_for_the_pipeline(
    tmp_path: Path,
) -> None:
    quality = assess_upload_quality(_photo(tmp_path / "small.png", size=(400, 600)))

    assert quality.warnings
    assert all(warning.startswith("Ön kontrol:") for warning in quality.warnings)
    assert any("1000 pikselden" in warning for warning in quality.warnings)


def test_preflight_flags_a_blown_out_photograph(tmp_path: Path) -> None:
    quality = assess_upload_quality(_photo(tmp_path / "bright.png", color="white"))

    assert any("parlama" in warning for warning in quality.warnings)


def test_preflight_flags_a_very_dark_photograph(tmp_path: Path) -> None:
    quality = assess_upload_quality(_photo(tmp_path / "dark.png", color="black"))

    assert any("karanlık" in warning for warning in quality.warnings)


def test_preflight_flags_a_featureless_photograph_as_blurry(tmp_path: Path) -> None:
    # A flat mid-gray field has ~zero Laplacian variance (no edges at all) but
    # avoids the dark/light clipping bins, isolating the blur check.
    quality = assess_upload_quality(_photo(tmp_path / "flat.png", color=(128, 128, 128)))

    assert quality.blur_score is not None
    assert quality.blur_score < PREFLIGHT_BLUR_FLOOR
    assert any("bulanık" in warning for warning in quality.warnings)


def test_preflight_has_no_warnings_for_a_sharp_well_lit_photograph(tmp_path: Path) -> None:
    path = tmp_path / "sharp.png"
    path.parent.mkdir(parents=True, exist_ok=True)
    # A checkerboard has plenty of high-frequency edges to score well above
    # the blur floor. Mid-tone grays (not near 0 or 255) keep both clipping
    # ratios under their warning thresholds, unlike pure black/white would.
    image = Image.new("RGB", (1200, 1600), (180, 180, 180))
    pixels = image.load()
    for y in range(image.height):
        for x in range(0, image.width, 20):
            if (x // 20 + y // 20) % 2 == 0:
                for dx in range(20):
                    if x + dx < image.width:
                        pixels[x + dx, y] = (80, 80, 80)
    image.save(path)

    quality = assess_upload_quality(path)

    assert quality.warnings == ()


def test_preflight_analyzes_a_downscaled_copy_for_a_large_source(tmp_path: Path) -> None:
    quality = assess_upload_quality(
        _photo(tmp_path / "huge.png", size=(3200, 4000)), analysis_max_edge=1600
    )

    assert max(quality.width, quality.height) <= 1600


def test_preflight_does_not_write_any_derivative_files(tmp_path: Path) -> None:
    source = _photo(tmp_path / "cover.png")
    before = set(tmp_path.rglob("*"))

    assess_upload_quality(source)

    after = set(tmp_path.rglob("*"))
    assert after == before


def test_preflight_refuses_a_document_it_cannot_decode_as_an_image(tmp_path: Path) -> None:
    pdf_path = tmp_path / "kitap.pdf"
    pdf_path.parent.mkdir(parents=True, exist_ok=True)
    Image.new("RGB", (180, 240), "white").save(pdf_path, "PDF")

    with pytest.raises(ImageProcessingError):
        assess_upload_quality(pdf_path)


def test_the_recorded_homography_maps_the_canonical_corner_back(tmp_path: Path) -> None:
    prepared = CoverPreprocessor(tmp_path / "derivatives").prepare(_photo(tmp_path / "cover.jpg"))

    origin = project_point_to_source((0.0, 0.0), prepared.homography_to_source)
    far = project_point_to_source(
        (float(prepared.width), float(prepared.height)),
        prepared.homography_to_source,
    )

    # Whatever the transform, the canonical frame has to cover the source one:
    # a box drawn on the canonical image lands inside the original photograph.
    assert all(math.isfinite(value) for value in (*origin, *far))
    assert far[0] == pytest.approx(prepared.original_width, rel=0.05)
    assert far[1] == pytest.approx(prepared.original_height, rel=0.05)


def _residual_square_angle(gray: Any) -> float:
    """Re-measure, independently of production code, how far ``gray`` is from square."""

    import cv2

    edges = cv2.Canny(cv2.GaussianBlur(gray, (5, 5), 0), 50, 150)
    contours, _hierarchy = cv2.findContours(edges, cv2.RETR_LIST, cv2.CHAIN_APPROX_SIMPLE)
    largest = max(contours, key=cv2.contourArea)
    box = cv2.boxPoints(cv2.minAreaRect(largest))
    edge = box[1] - box[0]
    angle = math.degrees(math.atan2(float(edge[1]), float(edge[0])))
    return ((angle + 45.0) % 90.0) - 45.0


def test_minarearect_fallback_squares_off_a_tilted_cover_without_cropping(
    tmp_path: Path,
) -> None:
    cv2 = pytest.importorskip("cv2")
    import numpy as np

    # A chamfered corner defeats the four-corner search (it is a pentagon,
    # not a quad) while staying rectangular enough for minAreaRect to square
    # off.
    canvas = np.zeros((1200, 900), dtype=np.uint8)
    points = np.array(
        [[150, 300], [650, 300], [750, 400], [750, 900], [150, 900]], dtype=np.int32
    )
    cv2.fillPoly(canvas, [points], 255)
    rotation = cv2.getRotationMatrix2D((450.0, 600.0), 12.0, 1.0)
    tilted = cv2.warpAffine(canvas, rotation, (900, 1200))
    source = tmp_path / "tilted.png"
    source.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(np.stack([tilted] * 3, axis=-1)).save(source)

    prepared = CoverPreprocessor(tmp_path / "derivatives").prepare(source)

    assert any("minAreaRect" in warning for warning in prepared.quality.warnings)
    # Nothing is cropped away: the corrected canvas grows to fit every corner.
    assert prepared.width * prepared.height > tilted.shape[0] * tilted.shape[1]
    corrected = np.asarray(Image.open(prepared.canonical_path).convert("L"))
    assert abs(_residual_square_angle(corrected)) < 2.0

    origin = project_point_to_source((0.0, 0.0), prepared.homography_to_source)
    assert all(math.isfinite(value) for value in origin)


def test_illumination_flattening_finds_the_quad_under_a_lighting_gradient(
    tmp_path: Path,
) -> None:
    pytest.importorskip("cv2")
    import numpy as np

    height, width = 1400, 1000
    base = np.full((height, width), 60, dtype=np.float64)
    base[150:1250, 150:850] = 75  # only faintly brighter than the background
    gradient = np.linspace(1.6, 0.55, width)[None, :]  # bright left, glare-dark right
    lit = np.clip(base * gradient, 0, 255).astype(np.uint8)
    source = tmp_path / "glare.png"
    source.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(np.stack([lit] * 3, axis=-1)).save(source)

    prepared = CoverPreprocessor(tmp_path / "derivatives").prepare(source)

    assert any(
        "aydınlatma düzleştirme" in warning for warning in prepared.quality.warnings
    )
    origin = project_point_to_source((0.0, 0.0), prepared.homography_to_source)
    far = project_point_to_source(
        (float(prepared.width), float(prepared.height)), prepared.homography_to_source
    )
    assert all(math.isfinite(value) for value in (*origin, *far))
    # The rectified crop is the cover, comfortably inside the lit photograph.
    assert 0 <= origin[0] <= far[0] <= width
    assert 0 <= origin[1] <= far[1] <= height


def test_hough_deskew_straightens_tilted_text_lines(tmp_path: Path) -> None:
    cv2 = pytest.importorskip("cv2")
    import numpy as np

    canvas = np.zeros((900, 1200), dtype=np.uint8)
    rng = np.random.default_rng(1)
    for row in range(120, 800, 40):
        left = int(rng.integers(60, 300))
        right = left + int(rng.integers(400, 700))
        cv2.line(canvas, (left, row), (right, row), 255, 3)
    rotation = cv2.getRotationMatrix2D((600.0, 450.0), 6.0, 1.0)
    tilted = cv2.warpAffine(canvas, rotation, (1200, 900))
    source = tmp_path / "skewed-text.png"
    source.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(np.stack([tilted] * 3, axis=-1)).save(source)

    prepared = CoverPreprocessor(tmp_path / "derivatives").prepare(source)

    assert any("Hough" in warning for warning in prepared.quality.warnings)
    corrected = np.asarray(Image.open(prepared.canonical_path).convert("L"))
    edges = cv2.Canny(corrected, 50, 150)
    lines = cv2.HoughLinesP(
        edges, 1, np.pi / 180, threshold=80, minLineLength=150, maxLineGap=10
    )
    assert lines is not None
    angles: list[float] = []
    for line in lines:
        x1, y1, x2, y2 = (float(value) for value in line[0])
        if x1 == x2 and y1 == y2:
            continue
        angle = math.degrees(math.atan2(y2 - y1, x2 - x1))
        if angle <= -90:
            angle += 180
        elif angle > 90:
            angle -= 180
        if abs(angle) <= 20:
            angles.append(angle)
    assert angles
    angles.sort()
    median = angles[len(angles) // 2]
    assert abs(median) < 1.5

    origin = project_point_to_source((0.0, 0.0), prepared.homography_to_source)
    assert all(math.isfinite(value) for value in origin)


def test_binarized_derivative_is_deterministic_and_preserves_canonical_geometry(
    tmp_path: Path,
) -> None:
    pytest.importorskip("cv2")
    source = _photo(tmp_path / "cover.png")

    first = CoverPreprocessor(tmp_path / "derivatives").prepare(source)
    second = CoverPreprocessor(tmp_path / "derivatives").prepare(source)

    assert first.variant_paths["binarized"].read_bytes() == second.variant_paths["binarized"].read_bytes()
    with Image.open(first.variant_paths["binarized"]) as binarized:
        # No resize happens on this derivative, so polygons stay valid in
        # canonical coordinates.
        assert binarized.size == (first.width, first.height)
