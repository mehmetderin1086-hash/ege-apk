"""Deterministic, offline image ingestion and cover preprocessing."""

from __future__ import annotations

import hashlib
import io
import math
import os
import tempfile
from contextlib import suppress
from dataclasses import dataclass, replace
from pathlib import Path
from typing import Any

try:
    from PIL import Image, ImageEnhance, ImageFilter, ImageOps, UnidentifiedImageError
except ImportError as exc:  # pragma: no cover - base dependency, exercised by packaging
    raise RuntimeError(
        "Görüntü işleme için Pillow eksik. `pip install 'kitapkatalog'` ile temel "
        "bağımlılıkları kurun."
    ) from exc

PREPROCESSING_VERSION = "cover-v2"
SUPPORTED_SUFFIXES = frozenset(
    {".jpg", ".jpeg", ".png", ".webp", ".tif", ".tiff", ".heic", ".heif", ".bmp"}
)


class ImageProcessingError(RuntimeError):
    """The source cannot be decoded or safely canonicalized."""


class MissingImageDependencyError(ImageProcessingError):
    """An optional image feature was requested but its dependency is absent."""


@dataclass(frozen=True, slots=True)
class ImageQuality:
    width: int
    height: int
    blur_score: float | None
    clipped_dark_ratio: float
    clipped_light_ratio: float
    warnings: tuple[str, ...]


@dataclass(frozen=True, slots=True)
class PreparedImage:
    """Canonical cover plus reproducibility/provenance metadata."""

    source_path: Path
    source_sha256: str
    canonical_path: Path
    canonical_sha256: str
    crop_sha256: str
    width: int
    height: int
    original_width: int
    original_height: int
    preprocessing_version: str
    homography_to_source: tuple[float, ...]
    quality: ImageQuality
    variant_paths: dict[str, Path]

    @property
    def image_sha256(self) -> str:
        return self.canonical_sha256


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _atomic_write(path: Path, data: bytes) -> None:
    temporary_name: str | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="wb",
            dir=path.parent,
            prefix=f".{path.name}.",
            suffix=".part",
            delete=False,
        ) as handle:
            temporary_name = handle.name
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        Path(temporary_name).replace(path)
    except OSError as exc:
        if temporary_name is not None:
            with suppress(OSError):
                Path(temporary_name).unlink()
        raise ImageProcessingError(f"Görüntü türevi atomik yazılamadı: {path}: {exc}") from exc


def _register_heif_if_needed(path: Path) -> None:
    if path.suffix.lower() not in {".heic", ".heif"}:
        return
    try:
        from pillow_heif import register_heif_opener
    except ImportError as exc:
        raise MissingImageDependencyError(
            "HEIC/HEIF fotoğrafı için pillow-heif eksik. "
            "`pip install 'pillow-heif>=1.1,<2'` komutunu çalıştırın."
        ) from exc
    register_heif_opener()


def _open_rgb(path: Path) -> Image.Image:
    _register_heif_if_needed(path)
    try:
        with Image.open(path) as opened:
            oriented = ImageOps.exif_transpose(opened)
            oriented.load()
            return oriented.convert("RGB")
    except (UnidentifiedImageError, OSError, ValueError) as exc:
        raise ImageProcessingError(f"Fotoğraf çözülemedi: {path}: {exc}") from exc


def _png_bytes(image: Image.Image) -> bytes:
    buffer = io.BytesIO()
    image.save(buffer, "PNG", optimize=False, compress_level=6)
    return buffer.getvalue()


def _contours_by_area(gray: Any) -> list[Any]:
    """Canny contours over the area floor, largest first.

    Shared by every corner/rotation search below so the edge parameters only
    live in one place.
    """

    import cv2

    short_side = min(gray.shape[:2])
    kernel = max(3, int(short_side / 250) | 1)
    blurred = cv2.GaussianBlur(gray, (kernel, kernel), 0)
    edges = cv2.Canny(blurred, 50, 150)
    contours, _hierarchy = cv2.findContours(edges, cv2.RETR_LIST, cv2.CHAIN_APPROX_SIMPLE)
    area_floor = gray.shape[0] * gray.shape[1] * 0.25
    ordered = sorted(contours, key=cv2.contourArea, reverse=True)[:30]
    return [contour for contour in ordered if cv2.contourArea(contour) >= area_floor]


def _find_cover_quad(gray: Any) -> Any | None:
    """Return the largest convex four-corner contour, or ``None``."""

    import cv2

    for contour in _contours_by_area(gray):
        perimeter = cv2.arcLength(contour, True)
        approximation = cv2.approxPolyDP(contour, 0.02 * perimeter, True)
        if len(approximation) == 4 and cv2.isContourConvex(approximation):
            return approximation.reshape(4, 2).astype("float32")
    return None


def _illumination_flattened(gray: Any) -> Any:
    """Divide out a large-kernel background estimate, then Otsu-threshold it.

    Uneven lighting (a shadow across the cover, a glare down one edge) blends
    the cover's edge into the background in the raw Canny pass. Flattening
    the illumination first gives the same corner search a second, independent
    try before falling back to a rotation-only correction.
    """

    import cv2

    short_side = min(gray.shape[:2])
    kernel = max(31, int(short_side / 4) | 1)
    background = cv2.GaussianBlur(gray, (kernel, kernel), 0)
    normalized = cv2.divide(gray, background, scale=255)
    _threshold, binarized = cv2.threshold(normalized, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
    return binarized


def _warp_to_quad(array: Any, quad: Any) -> tuple[Any, tuple[float, ...]] | None:
    """Rectify ``quad`` to an axis-aligned canvas, or ``None`` if it is too small."""

    import cv2
    import numpy as np

    points = _order_quad(quad)
    top_left, top_right, bottom_right, bottom_left = points
    width = round(
        max(
            float(np.linalg.norm(bottom_right - bottom_left)),
            float(np.linalg.norm(top_right - top_left)),
        )
    )
    height = round(
        max(
            float(np.linalg.norm(top_right - bottom_right)),
            float(np.linalg.norm(top_left - bottom_left)),
        )
    )
    if width < 320 or height < 320:
        return None

    destination = np.array(
        [[0, 0], [width - 1, 0], [width - 1, height - 1], [0, height - 1]],
        dtype="float32",
    )
    source_to_canonical = cv2.getPerspectiveTransform(points, destination)
    canonical_to_source = np.linalg.inv(source_to_canonical)
    warped = cv2.warpPerspective(array, source_to_canonical, (width, height))
    return warped, tuple(float(value) for value in canonical_to_source.flatten())


def _min_area_rect_angle(gray: Any) -> float | None:
    """The rotation (degrees, in ``(-45, 45]``) that would square off the
    largest contour, or ``None`` when there is no contour to measure or the
    tilt is too steep to trust as a simple rotation.
    """

    import cv2

    contours = _contours_by_area(gray)
    if not contours:
        return None
    box = cv2.boxPoints(cv2.minAreaRect(contours[0]))
    edge_x, edge_y = float(box[1][0] - box[0][0]), float(box[1][1] - box[0][1])
    if edge_x == 0.0 and edge_y == 0.0:
        return None
    angle = math.degrees(math.atan2(edge_y, edge_x))
    angle = ((angle + 45.0) % 90.0) - 45.0
    return angle if abs(angle) <= 30.0 else None


def _hough_text_angle(gray: Any) -> float | None:
    """The median near-horizontal text-line tilt, when it looks like real skew."""

    import cv2
    import numpy as np

    edges = cv2.Canny(gray, 50, 150)
    min_length = max(20, int(min(gray.shape[:2]) * 0.15))
    lines = cv2.HoughLinesP(
        edges, 1, np.pi / 180, threshold=80, minLineLength=min_length, maxLineGap=10
    )
    if lines is None:
        return None
    angles: list[float] = []
    for line in lines:
        x1, y1, x2, y2 = (float(value) for value in line[0])
        if x1 == x2 and y1 == y2:
            continue
        angle = math.degrees(math.atan2(y2 - y1, x2 - x1))
        if angle <= -90.0:
            angle += 180.0
        elif angle > 90.0:
            angle -= 180.0
        if abs(angle) <= 20.0:
            angles.append(angle)
    if not angles:
        return None
    angles.sort()
    middle = len(angles) // 2
    median = (
        angles[middle]
        if len(angles) % 2
        else (angles[middle - 1] + angles[middle]) / 2.0
    )
    return median if 1.0 <= abs(median) <= 15.0 else None


def _rotate_full_frame(array: Any, angle_degrees: float) -> tuple[Any, tuple[float, ...]]:
    """Rotate about the center onto a canvas expanded to fit every corner.

    Nothing is cropped: a fallback rotation must never cut off the title or
    author line it was meant to straighten.
    """

    import cv2
    import numpy as np

    height, width = array.shape[:2]
    center = (width / 2.0, height / 2.0)
    rotation = cv2.getRotationMatrix2D(center, angle_degrees, 1.0)
    cos = abs(rotation[0, 0])
    sin = abs(rotation[0, 1])
    new_width = max(1, round(height * sin + width * cos))
    new_height = max(1, round(height * cos + width * sin))
    rotation[0, 2] += (new_width / 2.0) - center[0]
    rotation[1, 2] += (new_height / 2.0) - center[1]
    rotated = cv2.warpAffine(array, rotation, (new_width, new_height), flags=cv2.INTER_LINEAR)
    forward = np.vstack([rotation, [0.0, 0.0, 1.0]])
    inverse = np.linalg.inv(forward)
    return rotated, tuple(float(value) for value in inverse.flatten())


def _perspective_correct(
    image: Image.Image,
) -> tuple[Image.Image, tuple[float, ...], tuple[str, ...]]:
    """Find the largest four-sided cover and rectify it when OpenCV is present.

    A four-corner match is tried on the raw frame, then again on an
    illumination-flattened one. If neither finds a usable quad, a rotation-only
    fallback (a squared-off ``minAreaRect``, then a Hough text-line deskew)
    straightens the photo without cropping it. Returning the identity mapping
    is the last, explicit, recorded fallback; it is not used when callers
    request strict perspective support.
    """

    try:
        import cv2
        import numpy as np
    except ImportError:
        return image, _identity_homography(), ("OpenCV yok; perspektif düzeltme uygulanmadı",)

    array = np.asarray(image)
    gray = cv2.cvtColor(array, cv2.COLOR_RGB2GRAY)

    def _quad_warp(candidate_gray: Any) -> tuple[Any, tuple[float, ...]] | None:
        quad = _find_cover_quad(candidate_gray)
        return None if quad is None else _warp_to_quad(array, quad)

    warped = _quad_warp(gray)
    stage_warning: str | None = None
    if warped is None:
        # Only pay for the large-kernel illumination pass when the raw one
        # did not already find a usable quad.
        warped = _quad_warp(_illumination_flattened(gray))
        if warped is not None:
            stage_warning = "Perspektif: aydınlatma düzleştirme sonrası dörtgen bulundu"
    if warped is not None:
        canonical_array, homography = warped
        return (
            Image.fromarray(canonical_array),
            homography,
            (stage_warning,) if stage_warning else (),
        )

    rotation_angle = _min_area_rect_angle(gray)
    if rotation_angle is not None:
        # cv2.getRotationMatrix2D's positive-angle direction already undoes
        # the tilt atan2 measured; verified empirically (a negated angle
        # doubles the skew instead of levelling it).
        rotated, homography = _rotate_full_frame(array, rotation_angle)
        return (
            Image.fromarray(rotated),
            homography,
            ("Perspektif: minAreaRect fallback uygulandı (yalnızca döndürme)",),
        )

    deskew_angle = _hough_text_angle(gray)
    if deskew_angle is not None:
        rotated, homography = _rotate_full_frame(array, deskew_angle)
        return (
            Image.fromarray(rotated),
            homography,
            ("Perspektif: Hough metin deskew uygulandı",),
        )

    return (
        image,
        _identity_homography(),
        ("Kapak dörtgeni bulunamadı; tam fotoğraf kullanıldı",),
    )


def _identity_homography() -> tuple[float, ...]:
    return (1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0)


def _order_quad(points: Any) -> Any:
    # Kept NumPy-shaped without importing NumPy at module import time.
    import numpy as np

    ordered = np.zeros((4, 2), dtype="float32")
    sums = points.sum(axis=1)
    differences = np.diff(points, axis=1).reshape(-1)
    ordered[0] = points[np.argmin(sums)]
    ordered[2] = points[np.argmax(sums)]
    ordered[1] = points[np.argmin(differences)]
    ordered[3] = points[np.argmax(differences)]
    return ordered


def _quality(image: Image.Image, perspective_warnings: tuple[str, ...]) -> ImageQuality:
    gray = ImageOps.grayscale(image)
    histogram = gray.histogram()
    pixels = max(1, image.width * image.height)
    dark_ratio = sum(histogram[:8]) / pixels
    light_ratio = sum(histogram[248:]) / pixels
    warnings = list(perspective_warnings)
    if min(image.size) < 1000:
        warnings.append("Kısa kenar 1000 pikselden küçük")
    if dark_ratio > 0.12:
        warnings.append("Görüntüde çok fazla karanlık/kırpılmış bölge var")
    if light_ratio > 0.12:
        warnings.append("Görüntüde parlama veya aşırı pozlama olabilir")

    blur_score: float | None = None
    try:
        import cv2
        import numpy as np

        blur_score = float(cv2.Laplacian(np.asarray(gray), cv2.CV_64F).var())
        if blur_score < 75.0:
            warnings.append("Fotoğraf bulanık olabilir")
    except ImportError:
        pass
    return ImageQuality(
        width=image.width,
        height=image.height,
        blur_score=blur_score,
        clipped_dark_ratio=dark_ratio,
        clipped_light_ratio=light_ratio,
        warnings=tuple(warnings),
    )


#: Blur floor for :func:`assess_upload_quality`, distinct from ``_quality``'s
#: 75.0.  The analysis copy is downscaled for cost control, which lowers
#: Laplacian variance on its own, so the two scores are not comparable.
PREFLIGHT_BLUR_FLOOR = 45.0


def assess_upload_quality(path: Path, *, analysis_max_edge: int = 1600) -> ImageQuality:
    """Cheap, side-effect-free quality read before a photo is staged for OCR.

    Reuses cover-v2's histogram/blur heuristics (:func:`_quality`) on a
    capped-resolution copy so a several-hundred-photo batch does not pay
    full-resolution Laplacian cost per file. Nothing is written to disk and
    no perspective correction runs, so the reported ``width``/``height`` are
    the analyzed (possibly downscaled) dimensions, not necessarily the
    source file's.
    """

    image = _open_rgb(path)
    if analysis_max_edge > 0 and max(image.size) > analysis_max_edge:
        scale = analysis_max_edge / max(image.size)
        image = image.resize(
            (max(1, round(image.width * scale)), max(1, round(image.height * scale))),
            Image.Resampling.LANCZOS,
        )
    quality = _quality(image, ())
    warnings = [warning for warning in quality.warnings if warning != "Fotoğraf bulanık olabilir"]
    if quality.blur_score is not None and quality.blur_score < PREFLIGHT_BLUR_FLOOR:
        warnings.append("Fotoğraf bulanık olabilir")
    return replace(quality, warnings=tuple(f"Ön kontrol: {warning}" for warning in warnings))


def _make_clahe_or_contrast(image: Image.Image) -> Image.Image:
    gray = ImageOps.grayscale(image)
    try:
        import cv2
        import numpy as np

        array = np.asarray(gray)
        enhanced = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8)).apply(array)
        return Image.fromarray(enhanced)
    except ImportError:
        return ImageEnhance.Contrast(gray).enhance(1.8).filter(ImageFilter.SHARPEN)


def _make_binarized(image: Image.Image) -> Image.Image | None:
    """A local-adaptive-threshold derivative, or ``None`` without OpenCV.

    ``cv2.ADAPTIVE_THRESH_GAUSSIAN_C`` ships in plain ``opencv-python``; the
    true Sauvola implementation lives in ``opencv-contrib``'s ``ximgproc``,
    which is not a guaranteed dependency here, so this is its stand-in. No
    resize happens, so canonical-coordinate polygons stay valid on it.
    """

    try:
        import cv2
        import numpy as np
    except ImportError:
        return None

    array = np.asarray(ImageOps.grayscale(image))
    short_side = min(array.shape[:2])
    block_size = max(15, int(short_side / 40) | 1)
    binarized = cv2.adaptiveThreshold(
        array,
        255,
        cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
        cv2.THRESH_BINARY,
        block_size,
        10,
    )
    return Image.fromarray(binarized)


class CoverPreprocessor:
    def __init__(
        self,
        derivative_root: Path,
        *,
        max_long_edge: int = 3600,
        require_perspective: bool = False,
    ) -> None:
        self.derivative_root = Path(derivative_root)
        self.max_long_edge = int(max_long_edge)
        self.require_perspective = require_perspective

    def prepare(self, source_path: str | Path) -> PreparedImage:
        source = Path(source_path).expanduser().resolve()
        if not source.is_file():
            raise ImageProcessingError(f"Fotoğraf bulunamadı: {source}")
        if source.suffix.lower() not in SUPPORTED_SUFFIXES:
            supported = ", ".join(sorted(SUPPORTED_SUFFIXES))
            raise ImageProcessingError(
                f"Desteklenmeyen fotoğraf türü: {source.suffix}. Desteklenenler: {supported}"
            )
        source_sha = sha256_file(source)
        original = _open_rgb(source)
        original_width, original_height = original.size
        canonical, homography, perspective_warnings = _perspective_correct(original)
        if (
            self.require_perspective
            and perspective_warnings
            and perspective_warnings[0].startswith("OpenCV yok")
        ):
            raise MissingImageDependencyError(
                "Zorunlu perspektif düzeltme için NumPy ve OpenCV eksik. "
                "`pip install 'kitapkatalog[vision]'` komutunu çalıştırın."
            )

        if self.max_long_edge > 0 and max(canonical.size) > self.max_long_edge:
            scale = self.max_long_edge / max(canonical.size)
            canonical = canonical.resize(
                (
                    max(1, round(canonical.width * scale)),
                    max(1, round(canonical.height * scale)),
                ),
                Image.Resampling.LANCZOS,
            )
            # Coordinates must first undo resize, then the perspective warp.
            matrix = list(homography)
            matrix[0] /= scale
            matrix[1] /= scale
            matrix[3] /= scale
            matrix[4] /= scale
            matrix[6] /= scale
            matrix[7] /= scale
            homography = tuple(matrix)

        canonical_bytes = _png_bytes(canonical)
        canonical_sha = _sha256_bytes(canonical_bytes)
        output = self.derivative_root / source_sha[:2] / source_sha
        output.mkdir(parents=True, exist_ok=True)
        canonical_path = output / f"{PREPROCESSING_VERSION}-canonical.png"
        grayscale_path = output / f"{PREPROCESSING_VERSION}-gray-clahe.png"
        binarized_path = output / f"{PREPROCESSING_VERSION}-binarized.png"
        if not canonical_path.exists() or sha256_file(canonical_path) != canonical_sha:
            _atomic_write(canonical_path, canonical_bytes)
        gray = _make_clahe_or_contrast(canonical)
        gray_bytes = _png_bytes(gray)
        if not grayscale_path.exists() or sha256_file(grayscale_path) != _sha256_bytes(gray_bytes):
            _atomic_write(grayscale_path, gray_bytes)
        variant_paths = {"canonical": canonical_path, "gray_clahe": grayscale_path}
        binarized = _make_binarized(canonical)
        if binarized is not None:
            binarized_bytes = _png_bytes(binarized)
            binarized_sha = _sha256_bytes(binarized_bytes)
            if not binarized_path.exists() or sha256_file(binarized_path) != binarized_sha:
                _atomic_write(binarized_path, binarized_bytes)
            variant_paths["binarized"] = binarized_path

        crop_payload = (
            canonical_sha
            + ":"
            + ",".join(f"{value:.12g}" for value in homography)
            + ":"
            + PREPROCESSING_VERSION
        ).encode()
        quality = _quality(canonical, perspective_warnings)
        return PreparedImage(
            source_path=source,
            source_sha256=source_sha,
            canonical_path=canonical_path,
            canonical_sha256=canonical_sha,
            crop_sha256=hashlib.sha256(crop_payload).hexdigest(),
            width=canonical.width,
            height=canonical.height,
            original_width=original_width,
            original_height=original_height,
            preprocessing_version=PREPROCESSING_VERSION,
            homography_to_source=homography,
            quality=quality,
            variant_paths=variant_paths,
        )


def project_point_to_source(
    point: tuple[float, float], homography: tuple[float, ...]
) -> tuple[float, float]:
    """Project one canonical coordinate back to the EXIF-oriented source image."""

    if len(homography) != 9:
        raise ValueError("Homografi dokuz değer içermelidir")
    x, y = point
    denominator = homography[6] * x + homography[7] * y + homography[8]
    if math.isclose(denominator, 0.0):
        raise ImageProcessingError("Homografi noktayı sonsuza yansıtıyor")
    return (
        (homography[0] * x + homography[1] * y + homography[2]) / denominator,
        (homography[3] * x + homography[4] * y + homography[5]) / denominator,
    )


def project_polygon_to_source(
    polygon: tuple[tuple[float, float], ...] | None,
    homography: tuple[float, ...],
) -> tuple[tuple[float, float], ...] | None:
    if polygon is None:
        return None
    return tuple(project_point_to_source(point, homography) for point in polygon)
