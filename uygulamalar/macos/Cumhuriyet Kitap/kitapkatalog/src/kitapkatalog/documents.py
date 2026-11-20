"""Offline image/PDF normalization for four-surface book imports."""

from __future__ import annotations

import hashlib
import os
import shutil
import unicodedata
from collections.abc import Iterable, Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path

from kitapkatalog.domain import ImagePair

SUPPORTED_IMAGE_SUFFIXES = frozenset(
    {".jpg", ".jpeg", ".png", ".heic", ".heif", ".webp", ".tif", ".tiff", ".bmp"}
)
SUPPORTED_DOCUMENT_SUFFIXES = SUPPORTED_IMAGE_SUFFIXES | {".pdf"}
FOUR_SURFACE_COUNT = 4
PDF_RENDER_DPI = 300
# Tek PDF'ten üretilebilecek en fazla kitap: tarayıcıdan gelen 4'ün katı
# belgeler bölünür, kazara yüklenen dev bir kitap taraması ise reddedilir.
MAX_BOOKS_PER_PDF = 400
# 300 DPI A4 PNG kabaca 2-3 MB; muhafazakâr tarafta kalınır.
RENDERED_PAGE_BYTES = 4 * 1024**2
RENDER_FREE_SPACE_RESERVE = 1024**3


class DocumentInputError(ValueError):
    """A selected image/PDF set cannot represent one four-surface book."""


@dataclass(frozen=True, slots=True)
class ExpandedDocuments:
    images: tuple[Path, ...]
    four_page_books: tuple[ImagePair, ...] = ()
    rejected: tuple[tuple[Path, str], ...] = ()
    #: Dörder sayfalık kitaplara bölünen çok kitaplı PDF'ler: (dosya, kitap).
    split_documents: tuple[tuple[Path, int], ...] = ()
    #: Üretilmiş görüntü → onu doğuran kaynak belge (tek sayfalık PDF'ler).
    image_origins: tuple[tuple[Path, Path], ...] = ()
    #: PDF'ten doğrudan çıkan kitabın eşleştirme anahtarı → kaynak belge.
    book_origins: tuple[tuple[str, Path], ...] = ()

    def origin_of(self, rendered: Path) -> Path:
        """Üretilmiş görüntünün kaynak belgesini (yoksa kendisini) verir."""

        return dict(self.image_origins).get(rendered, rendered)


def pdf_page_count(path: str | Path) -> int:
    source = _require_pdf(path)
    import pypdfium2 as pdfium

    with pdfium.PdfDocument(source) as document:
        return len(document)


def render_pdf_pages(
    path: str | Path,
    output_root: str | Path,
    *,
    page_indices: Sequence[int] | None = None,
    dpi: int = PDF_RENDER_DPI,
) -> tuple[Path, ...]:
    """Render selected PDF pages to content-addressed PNG files.

    Existing complete PNGs are reused.  Runtime rendering is entirely local;
    pypdfium2 ships PDFium inside its platform wheel and performs no download.
    """

    source = _require_pdf(path)
    if dpi < 72 or dpi > 600:
        raise DocumentInputError("PDF çözünürlüğü 72-600 DPI arasında olmalıdır")
    import pypdfium2 as pdfium

    digest = _sha256_file(source)
    target_root = Path(output_root).expanduser() / digest[:2] / digest
    target_root.mkdir(parents=True, exist_ok=True)
    rendered: list[Path] = []
    with pdfium.PdfDocument(source) as document:
        indices = tuple(range(len(document))) if page_indices is None else tuple(page_indices)
        if not indices:
            raise DocumentInputError(f"PDF içinde seçili sayfa yok: {source}")
        for index in indices:
            if index < 0 or index >= len(document):
                raise DocumentInputError(
                    f"PDF sayfa numarası geçersiz: {index + 1}/{len(document)}"
                )
            target = target_root / f"page-{index + 1:04d}-{dpi}dpi.png"
            if target.is_file() and target.stat().st_size > 0:
                rendered.append(target)
                continue
            part = target.with_name(f".{target.name}.{os.getpid()}.part")
            page = document[index]
            bitmap = None
            try:
                bitmap = page.render(scale=dpi / 72.0)
                image = bitmap.to_pil().convert("RGB")
                image.save(part, format="PNG", optimize=True)
                with part.open("rb") as stream:
                    os.fsync(stream.fileno())
                part.replace(target)
            except Exception:
                part.unlink(missing_ok=True)
                raise
            finally:
                if bitmap is not None:
                    bitmap.close()
                page.close()
            rendered.append(target)
    return tuple(rendered)


def build_single_book_scan(
    paths: Iterable[str | Path],
    render_root: str | Path,
) -> ImagePair:
    """Build one ordered book from four images/PDF pages or one four-page PDF."""

    selected = tuple(Path(value).expanduser() for value in paths)
    if not selected:
        raise DocumentInputError("Bir kitap için belge seçilmedi")
    normalized: list[Path] = []
    if len(selected) == 1 and selected[0].suffix.casefold() == ".pdf":
        count = pdf_page_count(selected[0])
        if count != FOUR_SURFACE_COUNT:
            raise DocumentInputError(f"Tek PDF tam dört sayfa olmalıdır; seçilen PDF {count} sayfa")
        normalized.extend(render_pdf_pages(selected[0], render_root))
        basis = "single_four_page_pdf"
    else:
        for path in selected:
            suffix = path.suffix.casefold()
            if suffix in SUPPORTED_IMAGE_SUFFIXES:
                _require_file(path)
                normalized.append(path)
            elif suffix == ".pdf":
                count = pdf_page_count(path)
                if count != 1:
                    raise DocumentInputError(
                        "Birden çok dosya seçildiğinde her PDF tek sayfa olmalıdır"
                    )
                normalized.extend(render_pdf_pages(path, render_root))
            else:
                raise DocumentInputError(f"Desteklenmeyen belge türü: {path.name}")
        basis = "single_manual_four_documents"
    if len(normalized) != FOUR_SURFACE_COUNT:
        raise DocumentInputError(
            "Bir kitap için sırayla dört belge seçin: ön, ön iç, arka iç, arka"
        )
    return _ordered_scan_set(
        normalized,
        pair_key_material="\0".join(str(path.absolute()) for path in selected),
        basis=basis,
        confidence=1.0,
        needs_review=False,
    )


def expand_bulk_documents(
    paths: Iterable[str | Path],
    render_root: str | Path,
) -> ExpandedDocuments:
    """Expand bulk PDFs without retaining whole documents in memory.

    A PDF whose page count is a multiple of four becomes that many complete
    books, four consecutive surfaces each: one scanner session can therefore
    carry a whole shelf.  Single-page PDFs are rendered and then participate in
    normal filename-based four-role pairing.  Any other page count is rejected
    for explicit user review.
    """

    images: list[Path] = []
    direct: list[ImagePair] = []
    rejected: list[tuple[Path, str]] = []
    split: list[tuple[Path, int]] = []
    image_origins: list[tuple[Path, Path]] = []
    book_origins: list[tuple[str, Path]] = []
    for value in paths:
        path = Path(value).expanduser()
        suffix = path.suffix.casefold()
        if suffix in SUPPORTED_IMAGE_SUFFIXES:
            images.append(path)
            continue
        if suffix != ".pdf":
            rejected.append((path, "Desteklenmeyen belge türü"))
            continue
        try:
            count = pdf_page_count(path)
            if count % FOUR_SURFACE_COUNT == 0 and count > 0:
                books = count // FOUR_SURFACE_COUNT
                if books > MAX_BOOKS_PER_PDF:
                    rejected.append(
                        (
                            path,
                            f"Tek PDF'te en fazla {MAX_BOOKS_PER_PDF} kitap işlenir; "
                            f"{books} kitaplık belge bölünmedi",
                        )
                    )
                    continue
                require_render_space(render_root, count)
                rendered = render_pdf_pages(path, render_root)
                for index in range(books):
                    window = rendered[
                        index * FOUR_SURFACE_COUNT : (index + 1) * FOUR_SURFACE_COUNT
                    ]
                    scan = _ordered_scan_set(
                        window,
                        # Aynı PDF'in her kitabı ayrı bir eşleştirme anahtarı
                        # almalı; yoksa ikinci kitap birincinin kopyası sayılır.
                        pair_key_material=f"{path.absolute()}\0kitap-{index + 1}",
                        basis=(
                            "bulk_four_page_pdf"
                            if books == 1
                            else f"bulk_multi_book_pdf[{index + 1}/{books}]"
                        ),
                        confidence=0.99,
                        needs_review=False,
                    )
                    direct.append(scan)
                    book_origins.append((scan.pair_key, path))
                if books > 1:
                    split.append((path, books))
            elif count == 1:
                rendered = render_pdf_pages(path, render_root)
                # Preserve the source stem so role markers still classify the
                # rendered page. Files from the same source directory share a
                # mirror directory so their common book key still groups.
                parent_key = hashlib.sha256(
                    unicodedata.normalize("NFC", str(path.parent.absolute())).encode("utf-8")
                ).hexdigest()[:20]
                role_root = Path(render_root).expanduser() / "_single_pages" / parent_key
                # `_safe_stem` kayıplıdır: "kitap 1.pdf" ile "kitap_1.pdf" aynı
                # ada iner.  Aynı adı farklı bir kaynak isterse onu bir alt
                # klasöre alırız; yoksa ikincisi birincinin sayfasını sessizce
                # ezer ve kitaplara yanlış yüz girerdi.
                role_named = role_root / f"{_safe_stem(path.stem)}.png"
                if role_named.exists() and _sha256_file(role_named) != _sha256_file(rendered[0]):
                    stem_key = hashlib.sha256(
                        unicodedata.normalize("NFC", path.stem).encode("utf-8")
                    ).hexdigest()[:10]
                    role_root = role_root / f"_ayrik-{stem_key}"
                    role_named = role_root / role_named.name
                role_root.mkdir(parents=True, exist_ok=True)
                if not role_named.exists() or _sha256_file(role_named) != _sha256_file(rendered[0]):
                    part = role_named.with_name(f".{role_named.name}.{os.getpid()}.part")
                    part.unlink(missing_ok=True)
                    os.link(rendered[0], part)
                    part.replace(role_named)
                images.append(role_named)
                image_origins.append((role_named, path))
            else:
                rejected.append(
                    (
                        path,
                        "Toplu PDF ya tek sayfa olmalı ya da sayfa sayısı 4'ün katı "
                        f"olmalıdır; {count} sayfa bulundu",
                    )
                )
        except (DocumentInputError, OSError, RuntimeError) as exc:
            rejected.append((path, str(exc)))
    return ExpandedDocuments(
        images=tuple(images),
        four_page_books=tuple(direct),
        rejected=tuple(rejected),
        split_documents=tuple(split),
        image_origins=tuple(image_origins),
        book_origins=tuple(book_origins),
    )


def folder_locations(
    pairs: Iterable[ImagePair],
    expanded: ExpandedDocuments,
    *,
    root: str | Path | None = None,
    names: Mapping[Path, str] | None = None,
) -> dict[str, str]:
    """Derive each book's shelf from the folder its source document sits in.

    ``root`` marks the selection root: a document lying directly in it has no
    folder of its own, so that book is left to the batch-wide shelf instead of
    inheriting the root's name.  ``names`` maps a folder to the shelf name to
    report for it — web uploads keep folders apart on disk with a digest suffix
    while the shelf keeps the reader-facing name.
    """

    rendered_origins = dict(expanded.image_origins)
    book_origins = dict(expanded.book_origins)
    try:
        resolved_root = Path(root).expanduser().resolve() if root is not None else None
    except OSError:
        resolved_root = None
    locations: dict[str, str] = {}
    for pair in pairs:
        source = book_origins.get(pair.pair_key) or rendered_origins.get(pair.front, pair.front)
        folder = Path(source).parent
        if resolved_root is not None:
            try:
                resolved_folder = folder.resolve()
            except OSError:
                continue
            if resolved_folder == resolved_root or not resolved_folder.is_relative_to(
                resolved_root
            ):
                continue
        name = (names or {}).get(folder, folder.name).strip()
        if name:
            locations[pair.pair_key] = name
    return locations


def _ordered_scan_set(
    paths: Sequence[Path],
    *,
    pair_key_material: str,
    basis: str,
    confidence: float,
    needs_review: bool,
) -> ImagePair:
    if len(paths) != FOUR_SURFACE_COUNT:
        raise DocumentInputError("Dört yüzlü kitap için tam dört görüntü gerekir")
    ordered_paths, barcode_role_resolved = _resolve_back_surface_order(paths)
    if barcode_role_resolved:
        basis += "+isbn_barcode_roles"
        confidence = max(confidence, 0.99)
    digest = hashlib.sha256(
        unicodedata.normalize("NFC", pair_key_material).encode("utf-8")
    ).hexdigest()[:20]
    return ImagePair(
        front=ordered_paths[0],
        front_inside=ordered_paths[1],
        back_inside=ordered_paths[2],
        back=ordered_paths[3],
        pair_key=f"four-{digest}",
        confidence=confidence,
        basis=basis,
        needs_review=needs_review,
    )


def _resolve_back_surface_order(
    paths: Sequence[Path],
) -> tuple[tuple[Path, ...], bool]:
    """Put the ISBN-bearing last surface in the back-cover role.

    Scanners and phone capture sessions commonly place the physical back cover
    before the inside-back page.  Sequence alone cannot distinguish those two
    surfaces, while a checksum-valid ISBN barcode is strong, local evidence.
    We only swap when exactly one of the last two images has that evidence; an
    unavailable decoder or an ambiguous pair preserves the user's order.
    """

    ordered = tuple(paths)
    third_has_isbn = _isbn_barcode_presence(ordered[2])
    fourth_has_isbn = _isbn_barcode_presence(ordered[3])
    if third_has_isbn is True and fourth_has_isbn is False:
        return ((*ordered[:2], ordered[3], ordered[2]), True)
    return ordered, fourth_has_isbn is True and third_has_isbn is False


def _isbn_barcode_presence(path: Path) -> bool | None:
    try:
        from kitapkatalog.isbn import BarcodeDependencyError, ZxingBarcodeScanner

        return any(
            observation.isbn is not None
            for observation in ZxingBarcodeScanner().scan(path, variant="role_probe")
        )
    except (BarcodeDependencyError, OSError, RuntimeError, ValueError):
        return None


def _safe_stem(value: str) -> str:
    normalized = unicodedata.normalize("NFC", value)
    return (
        "".join(
            character if character.isalnum() or character in {"-", "_"} else "_"
            for character in normalized
        ).strip("_")
        or "belge"
    )


def require_render_space(render_root: str | Path, pages: int) -> None:
    """Sayfalar diske sığmıyorsa render'a hiç başlama.

    Kapasite kapısı iş satırı yazılmadan hemen önce çalışır; çok sayfalı bir
    PDF ise ondan ÖNCE yüzlerce PNG üretebilir.  Bu yüzden yazmanın olduğu
    yerde ayrı ve muhafazakâr bir kontrol durur.
    """

    target = Path(render_root).expanduser()
    probe = target
    while not probe.exists() and probe != probe.parent:
        probe = probe.parent
    try:
        free = shutil.disk_usage(probe).free
    except OSError:
        return
    needed = pages * RENDERED_PAGE_BYTES + RENDER_FREE_SPACE_RESERVE
    if free < needed:
        raise DocumentInputError(
            f"{pages} sayfayı açmak için yeterli disk yok: yaklaşık "
            f"{needed // 1024**2} MiB gerekli, {free // 1024**2} MiB boş"
        )


def _require_file(path: Path) -> Path:
    if not path.is_file():
        raise DocumentInputError(f"Belge bulunamadı: {path}")
    return path


def _require_pdf(path: str | Path) -> Path:
    source = _require_file(Path(path).expanduser())
    if source.suffix.casefold() != ".pdf":
        raise DocumentInputError(f"PDF bekleniyordu: {source}")
    return source


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while block := stream.read(4 * 1024 * 1024):
            digest.update(block)
    return digest.hexdigest()
