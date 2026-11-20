"""Deterministic, scalable two- and four-surface book discovery."""

from __future__ import annotations

import hashlib
import re
import unicodedata
from collections.abc import Iterable
from contextlib import suppress
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

from kitapkatalog.documents import SUPPORTED_DOCUMENT_SUFFIXES, SUPPORTED_IMAGE_SUFFIXES
from kitapkatalog.domain import BOOK_SURFACE_ORDER, CoverRole, ImagePair

_FRONT_MARKERS = (
    "front_cover",
    "cover_front",
    "on_kapak",
    "kapak_on",
    "on_yuz",
    "onyuz",
    "front",
    "on",
)
_FRONT_INSIDE_MARKERS = (
    "front_inside_cover",
    "inside_front_cover",
    "front_inside",
    "inside_front",
    "on_ic_kapak",
    "ic_on_kapak",
    "on_ic",
    "ilk_ic",
    "kunye",
    "copyright",
)
_BACK_INSIDE_MARKERS = (
    "back_inside_cover",
    "inside_back_cover",
    "back_inside",
    "inside_back",
    "arka_ic_kapak",
    "ic_arka_kapak",
    "arka_ic",
    "son_ic",
    "sondan_bir_onceki",
)
_BACK_MARKERS = (
    "back_cover",
    "cover_back",
    "arka_kapak",
    "kapak_arka",
    "arka_yuz",
    "arkayuz",
    "back",
    "arka",
)
_TRAILING_NUMBER = re.compile(r"^(.*?)(\d+)$")


@dataclass(frozen=True, slots=True)
class PairingIssue:
    reason: str
    candidates: tuple[Path, ...]


@dataclass(frozen=True, slots=True)
class PairingResult:
    pairs: tuple[ImagePair, ...]
    unpaired: tuple[Path, ...] = ()
    ambiguous: tuple[PairingIssue, ...] = ()
    ignored: tuple[Path, ...] = ()

    @property
    def needs_review_count(self) -> int:
        return sum(pair.needs_review for pair in self.pairs)


class CoverPairer:
    """Pair images by explicit role, capture sequence and visual back-cover clues."""

    def __init__(
        self,
        *,
        infer_sequence: bool = True,
        infer_visual_role: bool = True,
        max_capture_gap_seconds: float = 120.0,
        require_four_surfaces: bool = False,
    ) -> None:
        self.infer_sequence = infer_sequence
        self.infer_visual_role = infer_visual_role
        self.max_capture_gap_seconds = max(0.0, float(max_capture_gap_seconds))
        self.require_four_surfaces = bool(require_four_surfaces)

    def pair(self, paths: Iterable[str | Path]) -> PairingResult:
        candidates: list[Path] = []
        ignored: list[Path] = []
        seen: set[str] = set()
        for value in paths:
            path = Path(value).expanduser()
            identity = str(path.absolute())
            if identity in seen:
                continue
            seen.add(identity)
            if path.suffix.casefold() not in SUPPORTED_IMAGE_SUFFIXES:
                ignored.append(path)
            else:
                candidates.append(path)

        grouped: dict[tuple[str, str], dict[CoverRole, list[Path]]] = {}
        unclassified: list[Path] = []
        for path in candidates:
            classified = classify_cover_filename(path)
            if classified is None:
                unclassified.append(path)
                continue
            role, base = classified
            parent = unicodedata.normalize("NFC", str(path.parent.absolute())).casefold()
            grouped.setdefault(
                (parent, base),
                {role: [] for role in BOOK_SURFACE_ORDER},
            )[role].append(path)

        pairs: list[ImagePair] = []
        unpaired: list[Path] = []
        ambiguous: list[PairingIssue] = []
        for (_parent, base), roles in sorted(grouped.items()):
            fronts = sorted(roles[CoverRole.FRONT], key=_sort_key)
            front_insides = sorted(roles[CoverRole.FRONT_INSIDE], key=_sort_key)
            back_insides = sorted(roles[CoverRole.BACK_INSIDE], key=_sort_key)
            backs = sorted(roles[CoverRole.BACK], key=_sort_key)
            if self.require_four_surfaces:
                role_lists = (fronts, front_insides, back_insides, backs)
                if all(len(items) == 1 for items in role_lists):
                    pairs.append(
                        _make_pair(
                            fronts[0],
                            backs[0],
                            front_inside=front_insides[0],
                            back_inside=back_insides[0],
                            base=base,
                            confidence=0.99,
                            basis="four_role_filename",
                            needs_review=False,
                        )
                    )
                    continue
                candidates_for_group = tuple(path for items in role_lists for path in items)
                if candidates_for_group:
                    ambiguous.append(
                        PairingIssue(
                            reason=(
                                "Kitap anahtarında ön/ön iç/arka iç/arka rollerinin "
                                "her birinden tam bir belge bulunamadı"
                            ),
                            candidates=candidates_for_group,
                        )
                    )
                    unpaired.extend(candidates_for_group)
                continue
            if len(fronts) == 1 and len(backs) == 1:
                pairs.append(
                    _make_pair(
                        fronts[0],
                        backs[0],
                        front_inside=front_insides[0] if len(front_insides) == 1 else None,
                        back_inside=back_insides[0] if len(back_insides) == 1 else None,
                        base=base,
                        confidence=0.99,
                        basis="filename",
                        needs_review=False,
                    )
                )
                continue
            if fronts and backs:
                issue_paths = tuple((*fronts, *front_insides, *back_insides, *backs))
                ambiguous.append(
                    PairingIssue(
                        reason="Aynı kitap anahtarında birden fazla ön/arka aday var",
                        candidates=issue_paths,
                    )
                )
                pair_count = min(len(fronts), len(backs))
                # Deterministic proposals let the review UI fix the few
                # ambiguous groups without blocking a 10k-file discovery pass.
                for index in range(pair_count):
                    pairs.append(
                        _make_pair(
                            fronts[index],
                            backs[index],
                            front_inside=(
                                front_insides[index] if index < len(front_insides) else None
                            ),
                            back_inside=(
                                back_insides[index] if index < len(back_insides) else None
                            ),
                            base=f"{base}-{index + 1}",
                            confidence=0.65,
                            basis="ambiguous_filename",
                            needs_review=True,
                        )
                    )
                unpaired.extend(fronts[pair_count:])
                unpaired.extend(backs[pair_count:])
                unpaired.extend(front_insides[pair_count:])
                unpaired.extend(back_insides[pair_count:])
            else:
                unpaired.extend(fronts)
                unpaired.extend(front_insides)
                unpaired.extend(back_insides)
                unpaired.extend(backs)

        if self.infer_sequence:
            sequence_pairs, sequence_unpaired, sequence_issues = self._pair_sequence(unclassified)
            pairs.extend(sequence_pairs)
            unpaired.extend(sequence_unpaired)
            ambiguous.extend(sequence_issues)
        else:
            unpaired.extend(unclassified)

        pairs.sort(key=lambda pair: (_sort_key(pair.front), _sort_key(pair.back)))
        return PairingResult(
            pairs=tuple(pairs),
            unpaired=tuple(sorted(unpaired, key=_sort_key)),
            ambiguous=tuple(ambiguous),
            ignored=tuple(sorted(ignored, key=_sort_key)),
        )

    def _pair_sequence(
        self, paths: list[Path]
    ) -> tuple[list[ImagePair], list[Path], list[PairingIssue]]:
        by_parent: dict[str, list[Path]] = {}
        for path in paths:
            by_parent.setdefault(str(path.parent.absolute()), []).append(path)
        pairs: list[ImagePair] = []
        unpaired: list[Path] = []
        issues: list[PairingIssue] = []
        for parent, group in sorted(by_parent.items()):
            stamped = sorted(
                ((_capture_time(path), path) for path in group),
                key=lambda item: (item[0][0], _natural_name(item[1])),
            )
            index = 0
            group_size = 4 if self.require_four_surfaces else 2
            while index + group_size - 1 < len(stamped):
                if self.require_four_surfaces:
                    ordered = [item[1] for item in stamped[index : index + 4]]
                    pair = _make_pair(
                        ordered[0],
                        ordered[3],
                        front_inside=ordered[1],
                        back_inside=ordered[2],
                        base=f"{Path(parent).name}-{index // 4 + 1}",
                        confidence=0.55,
                        basis="four_document_sequence",
                        needs_review=True,
                    )
                    pairs.append(pair)
                    issues.append(
                        PairingIssue(
                            reason=(
                                "Dört yüz rolü dosya adında yok; sıra ön/ön iç/"
                                "arka iç/arka olarak önerildi"
                            ),
                            candidates=tuple(ordered),
                        )
                    )
                    index += 4
                    continue
                (front_time, front_source), front = stamped[index]
                (back_time, back_source), back = stamped[index + 1]
                gap = abs(back_time - front_time)
                consecutive = _consecutive_names(front, back)
                if (
                    gap > self.max_capture_gap_seconds
                    and not consecutive
                    and front_source == back_source == "exif"
                ):
                    unpaired.append(front)
                    index += 1
                    continue
                if front_source == back_source == "exif":
                    confidence = 0.82 if gap <= 30 else 0.70
                    basis = "capture_time"
                elif consecutive:
                    confidence = 0.60 if gap <= self.max_capture_gap_seconds else 0.52
                    basis = "filename_sequence"
                else:
                    confidence = 0.52
                    basis = "file_sequence"
                visual_basis = ""
                if self.infer_visual_role:
                    first_score = _back_cover_score(front)
                    second_score = _back_cover_score(back)
                    if (
                        first_score is not None
                        and second_score is not None
                        and abs(first_score - second_score) >= 0.12
                    ):
                        if first_score > second_score:
                            front, back = back, front
                        visual_basis = "+barcode_text_density"
                        confidence = min(0.78, confidence + 0.08)
                pair = _make_pair(
                    front,
                    back,
                    front_inside=None,
                    back_inside=None,
                    base=f"{Path(parent).name}-{index // 2 + 1}",
                    confidence=confidence,
                    basis=basis + visual_basis,
                    needs_review=True,
                )
                pairs.append(pair)
                issues.append(
                    PairingIssue(
                        reason=("Kapak rolleri dosya adında yok; sıralamaya göre ön/arka önerildi"),
                        candidates=(front, back),
                    )
                )
                index += 2
            unpaired.extend(path for _timestamp, path in stamped[index:])
        return pairs, unpaired, issues


def discover_images(root: str | Path, *, recursive: bool = True) -> tuple[Path, ...]:
    directory = Path(root).expanduser()
    if not directory.is_dir():
        raise NotADirectoryError(directory)
    iterator = directory.rglob("*") if recursive else directory.iterdir()
    return tuple(
        sorted(
            (
                path
                for path in iterator
                if path.is_file() and path.suffix.casefold() in SUPPORTED_IMAGE_SUFFIXES
            ),
            key=_sort_key,
        )
    )


def discover_documents(root: str | Path, *, recursive: bool = True) -> tuple[Path, ...]:
    directory = Path(root).expanduser()
    if not directory.is_dir():
        raise NotADirectoryError(directory)
    iterator = directory.rglob("*") if recursive else directory.iterdir()
    return tuple(
        sorted(
            (
                path
                for path in iterator
                if path.is_file() and path.suffix.casefold() in SUPPORTED_DOCUMENT_SUFFIXES
            ),
            key=_sort_key,
        )
    )


def pair_cover_files(
    paths: Iterable[str | Path],
    *,
    infer_sequence: bool = True,
    infer_visual_role: bool = True,
    max_capture_gap_seconds: float = 120.0,
    require_four_surfaces: bool = False,
) -> PairingResult:
    return CoverPairer(
        infer_sequence=infer_sequence,
        infer_visual_role=infer_visual_role,
        max_capture_gap_seconds=max_capture_gap_seconds,
        require_four_surfaces=require_four_surfaces,
    ).pair(paths)


def classify_cover_filename(path: str | Path) -> tuple[CoverRole, str] | None:
    folded = _fold(Path(path).stem)
    for role, markers in (
        (CoverRole.FRONT_INSIDE, _FRONT_INSIDE_MARKERS),
        (CoverRole.BACK_INSIDE, _BACK_INSIDE_MARKERS),
        (CoverRole.FRONT, _FRONT_MARKERS),
        (CoverRole.BACK, _BACK_MARKERS),
    ):
        for marker in markers:
            if folded.endswith(f"_{marker}"):
                base = folded[: -(len(marker) + 1)].strip("_")
                return role, base or "kitap"
            if folded.startswith(f"{marker}_"):
                base = folded[len(marker) + 1 :].strip("_")
                return role, base or "kitap"
            if folded == marker:
                return role, "kitap"
    return None


def _make_pair(
    front: Path,
    back: Path,
    *,
    front_inside: Path | None,
    back_inside: Path | None,
    base: str,
    confidence: float,
    basis: str,
    needs_review: bool,
) -> ImagePair:
    material = "\0".join(
        (
            unicodedata.normalize("NFC", str(front.absolute())),
            (
                unicodedata.normalize("NFC", str(front_inside.absolute()))
                if front_inside is not None
                else ""
            ),
            (
                unicodedata.normalize("NFC", str(back_inside.absolute()))
                if back_inside is not None
                else ""
            ),
            unicodedata.normalize("NFC", str(back.absolute())),
        )
    )
    digest = hashlib.sha256(material.encode("utf-8")).hexdigest()[:20]
    clean_base = re.sub(r"[^a-z0-9]+", "-", _fold(base)).strip("-") or "kitap"
    return ImagePair(
        front=front,
        back=back,
        front_inside=front_inside,
        back_inside=back_inside,
        pair_key=f"{clean_base}-{digest}",
        confidence=confidence,
        basis=basis,
        needs_review=needs_review,
    )


def _fold(value: str) -> str:
    decomposed = unicodedata.normalize("NFKD", value).translate(str.maketrans({"ı": "i", "İ": "I"}))
    without_marks = "".join(
        character for character in decomposed if unicodedata.category(character) != "Mn"
    )
    folded = without_marks.casefold()
    return re.sub(r"[^a-z0-9]+", "_", folded).strip("_")


def _capture_time(path: Path) -> tuple[float, str]:
    try:
        from PIL import Image

        with Image.open(path) as image:
            exif = image.getexif()
            value = exif.get(36867) or exif.get(306)
            if value:
                parsed = datetime.strptime(str(value), "%Y:%m:%d %H:%M:%S")
                return parsed.timestamp(), "exif"
    except (ImportError, OSError, TypeError, ValueError):
        pass
    try:
        return path.stat().st_mtime, "mtime"
    except OSError:
        return 0.0, "name"


def _back_cover_score(path: Path) -> float | None:
    """Estimate which member of an unlabelled pair is the back cover.

    A valid book barcode is a strong clue.  Otherwise the score uses only a
    small grayscale thumbnail: back covers generally contain a larger share of
    compact high-frequency text.  This heuristic never auto-approves a pair;
    it only chooses the proposed orientation shown in the review screen.
    """

    try:
        from PIL import Image, ImageFilter, ImageOps

        with Image.open(path) as source:
            image = ImageOps.exif_transpose(source).convert("L")
            image.thumbnail((512, 512))
            if image.width < 8 or image.height < 8:
                return None
            edges = image.filter(ImageFilter.FIND_EDGES)
            edge_histogram = edges.histogram()
            gray_histogram = image.histogram()
            pixels = max(1, image.width * image.height)
            strong_edges = sum(edge_histogram[96:]) / pixels
            ink_pixels = sum(gray_histogram[:160]) / pixels
    except (ImportError, OSError, ValueError):
        return None

    barcode_bonus = 0.0
    # ZXing is an optional local dependency at pairing time.  Import or decode
    # errors deliberately fall back to text density without changing safety.
    with suppress(Exception):
        import numpy as np
        import zxingcpp

        with Image.open(path) as source:
            rgb = ImageOps.exif_transpose(source).convert("RGB")
            decoded = zxingcpp.read_barcodes(np.asarray(rgb))
        if any(
            str(getattr(item, "text", "")).replace("-", "").replace(" ", "").isdigit()
            and len(str(getattr(item, "text", "")).replace("-", "").replace(" ", "")) in {10, 13}
            for item in decoded
        ):
            barcode_bonus = 0.65

    return min(1.0, barcode_bonus + strong_edges * 1.8 + ink_pixels * 0.15)


def _consecutive_names(first: Path, second: Path) -> bool:
    left = _TRAILING_NUMBER.match(_fold(first.stem))
    right = _TRAILING_NUMBER.match(_fold(second.stem))
    if left is None or right is None or left.group(1) != right.group(1):
        return False
    return abs(int(left.group(2)) - int(right.group(2))) == 1


def _natural_name(path: Path) -> tuple[object, ...]:
    parts = re.split(r"(\d+)", unicodedata.normalize("NFC", path.name).casefold())
    return tuple(int(part) if part.isdigit() else part for part in parts)


def _sort_key(path: Path) -> tuple[object, ...]:
    return (*_natural_name(path), str(path.absolute()).casefold())
