from __future__ import annotations

import csv
import importlib
import importlib.metadata
import importlib.util
import json
import mimetypes
import os
import re
import zipfile
from collections import defaultdict
from collections.abc import Iterable
from pathlib import Path
from typing import Any
from xml.etree import ElementTree

from bioprof.domain.models import AnchorType
from bioprof.ingest.models import (
    DocumentBlock,
    MediaTranscriptionHook,
    ParsedDocument,
    SourceParser,
    UnsafeSourceError,
    UnsupportedFormatError,
)


def _package_version(package: str, fallback: str = "builtin") -> str:
    try:
        return importlib.metadata.version(package)
    except importlib.metadata.PackageNotFoundError:
        return fallback


def _read_text(path: Path) -> str:
    data = path.read_bytes()
    for encoding in ("utf-8-sig", "utf-8", "cp1254", "latin-1"):
        try:
            return data.decode(encoding)
        except UnicodeDecodeError:
            continue
    return data.decode("utf-8", errors="replace")


def _clean_text(text: str) -> str:
    text = text.replace("\x00", "")
    text = re.sub(r"[ \t]+\n", "\n", text)
    text = re.sub(r"\n{4,}", "\n\n\n", text)
    return text.strip()


def _env_enabled(name: str) -> bool:
    return os.getenv(name, "").strip().casefold() in {"1", "true", "yes", "on"}


def _safe_zip_members(path: Path, *, max_uncompressed: int = 512 * 1024 * 1024) -> zipfile.ZipFile:
    archive = zipfile.ZipFile(path)
    total = 0
    try:
        for info in archive.infolist():
            if info.filename.startswith(("/", "\\")) or ".." in Path(info.filename).parts:
                raise UnsafeSourceError("Arşiv güvenli olmayan bir dosya yolu içeriyor.")
            total += info.file_size
            if total > max_uncompressed:
                raise UnsafeSourceError("Arşivin açılmış boyutu güvenlik sınırını aşıyor.")
            if (
                info.file_size > 10 * 1024 * 1024
                and info.compress_size
                and info.file_size / info.compress_size > 250
            ):
                raise UnsafeSourceError("Şüpheli arşiv sıkıştırma oranı tespit edildi.")
        return archive
    except Exception:
        archive.close()
        raise


def _blocks_from_text(text: str, *, section: str | None = None) -> list[DocumentBlock]:
    text = _clean_text(text)
    if not text:
        return []
    return [DocumentBlock(text=text, section=section)]


class TextParser:
    name = "text"
    version = "1"

    def parse(self, path: Path, *, title: str | None = None) -> ParsedDocument:
        text = _read_text(path)
        return ParsedDocument(
            title=title or path.stem,
            blocks=_blocks_from_text(text),
            parser=self.name,
            parser_version=self.version,
        )


class UnavailableImageParser:
    name = "image-ocr-unavailable"
    version = "1"

    def parse(self, path: Path, *, title: str | None = None) -> ParsedDocument:
        del path, title
        raise UnsupportedFormatError(
            "Görsel OCR için Docling veya ayrı bir OCR hook'u kurulmalıdır."
        )


class DoclingParser:
    """Optional structure/provenance parser isolated from Docling API drift."""

    name = "docling"
    version = _package_version("docling", "not-installed")

    def __init__(self, *, enabled: bool | None = None) -> None:
        self._converter: Any | None = None
        self.enabled = _env_enabled("BIOPROF_ENABLE_DOCLING") if enabled is None else enabled

    @property
    def installed(self) -> bool:
        return importlib.util.find_spec("docling") is not None

    @property
    def available(self) -> bool:
        return self.enabled and self.installed

    @property
    def status_message(self) -> str:
        if not self.enabled:
            return (
                "Docling kapalıdır: yerel-öncelikli modda olası model indirmelerini "
                "önlemek için kullanmadan önce BIOPROF_ENABLE_DOCLING=1 verin."
            )
        if not self.installed:
            return "Docling etkin ancak kurulu değil; `uv sync --extra documents` çalıştırın."
        return "Docling açık ve kullanıma hazır."

    def _get_converter(self) -> Any:
        if not self.enabled:
            raise UnsupportedFormatError(self.status_message)
        if not self.installed:
            raise UnsupportedFormatError(self.status_message)
        if self._converter is None:
            module = importlib.import_module("docling.document_converter")
            self._converter = module.DocumentConverter()
        return self._converter

    @staticmethod
    def _provenance(item: Any) -> tuple[int | None, tuple[float, float, float, float] | None]:
        provenance = getattr(item, "prov", None) or []
        if not provenance:
            return None, None
        first = provenance[0]
        page = getattr(first, "page_no", None)
        bbox_value = getattr(first, "bbox", None)
        bbox = None
        if bbox_value is not None:
            left = getattr(bbox_value, "l", None)
            top = getattr(bbox_value, "t", None)
            right = getattr(bbox_value, "r", None)
            bottom = getattr(bbox_value, "b", None)
            if left is not None and top is not None and right is not None and bottom is not None:
                bbox = (float(left), float(top), float(right), float(bottom))
        return int(page) if page is not None else None, bbox

    def parse(self, path: Path, *, title: str | None = None) -> ParsedDocument:
        try:
            result = self._get_converter().convert(path)
            document = result.document
            blocks: list[DocumentBlock] = []
            current_section: str | None = None
            iterator = document.iterate_items() if hasattr(document, "iterate_items") else ()
            for entry in iterator:
                item = entry[0] if isinstance(entry, tuple) else entry
                label = str(getattr(item, "label", "")).casefold()
                value = getattr(item, "text", None)
                if not value and hasattr(item, "export_to_markdown"):
                    value = item.export_to_markdown()
                value = _clean_text(str(value or ""))
                if not value:
                    continue
                if "title" in label or "section" in label or "heading" in label:
                    current_section = value
                page, bbox = self._provenance(item)
                anchor_type = AnchorType.PAGE if page is not None else AnchorType.TEXT
                if "table" in label:
                    anchor_type = AnchorType.TABLE
                blocks.append(
                    DocumentBlock(
                        text=value,
                        section=current_section,
                        page=page,
                        bbox=bbox,
                        anchor_type=anchor_type,
                    )
                )
            if not blocks and hasattr(document, "export_to_markdown"):
                blocks = _blocks_from_text(document.export_to_markdown())
            if not blocks:
                raise UnsupportedFormatError("Docling indekslenebilir içerik üretmedi.")
            detected_title = getattr(document, "name", None)
            return ParsedDocument(
                title=title or detected_title or path.stem,
                blocks=blocks,
                parser=self.name,
                parser_version=self.version,
                metadata={"structured_parser": "docling"},
            )
        except UnsupportedFormatError:
            raise
        except Exception as exc:
            raise UnsupportedFormatError(
                f"Docling ayrıştırması başarısız: {type(exc).__name__}"
            ) from exc


class DoclingPreferredParser:
    """Use Docling when installed, retaining a dependency-light native fallback."""

    name = "docling-preferred"
    version = "1"

    def __init__(self, docling: DoclingParser, fallback: SourceParser) -> None:
        self.docling = docling
        self.fallback = fallback

    def parse(self, path: Path, *, title: str | None = None) -> ParsedDocument:
        docling_status = self.docling.status_message
        if self.docling.available:
            try:
                return self.docling.parse(path, title=title)
            except UnsupportedFormatError as exc:
                docling_status = str(exc)
        try:
            parsed = self.fallback.parse(path, title=title)
        except UnsupportedFormatError as exc:
            raise UnsupportedFormatError(f"{exc} {docling_status}") from exc
        parsed.metadata["structured_parser_fallback"] = parsed.parser
        parsed.metadata["docling_status"] = docling_status
        return parsed


class HtmlParser:
    name = "html"
    version = _package_version("beautifulsoup4")

    def parse(self, path: Path, *, title: str | None = None) -> ParsedDocument:
        try:
            from bs4 import BeautifulSoup
        except ImportError as exc:  # pragma: no cover - declared base dependency
            raise UnsupportedFormatError("HTML için beautifulsoup4 kurulmalıdır.") from exc

        soup = BeautifulSoup(_read_text(path), "html.parser")
        for element in soup(["script", "style", "noscript", "iframe", "object"]):
            element.decompose()
        detected_title = soup.title.get_text(" ", strip=True) if soup.title else None
        blocks: list[DocumentBlock] = []
        section: str | None = None
        buffer: list[str] = []
        for element in soup.find_all(["h1", "h2", "h3", "h4", "p", "li", "pre", "table"]):
            value = element.get_text(" ", strip=True)
            if not value:
                continue
            if element.name and element.name.startswith("h"):
                if buffer:
                    blocks.append(DocumentBlock(text="\n\n".join(buffer), section=section))
                    buffer = []
                section = value
            elif element.name == "table":
                if buffer:
                    blocks.append(DocumentBlock(text="\n\n".join(buffer), section=section))
                    buffer = []
                rows = [
                    " | ".join(
                        cell.get_text(" ", strip=True) for cell in row.find_all(["th", "td"])
                    )
                    for row in element.find_all("tr")
                ]
                table_text = "\n".join(row for row in rows if row.strip(" |"))
                if table_text:
                    blocks.append(
                        DocumentBlock(
                            text=table_text,
                            section=section,
                            anchor_type=AnchorType.TABLE,
                        )
                    )
            else:
                buffer.append(value)
        if buffer:
            blocks.append(DocumentBlock(text="\n\n".join(buffer), section=section))
        if not blocks:
            blocks = _blocks_from_text(soup.get_text("\n", strip=True))
        return ParsedDocument(
            title=title or detected_title or path.stem,
            blocks=blocks,
            parser=self.name,
            parser_version=self.version,
        )


class EpubParser:
    name = "epub"
    version = "1"

    def parse(self, path: Path, *, title: str | None = None) -> ParsedDocument:
        blocks: list[DocumentBlock] = []
        archive = _safe_zip_members(path)
        try:
            names = sorted(
                name
                for name in archive.namelist()
                if Path(name).suffix.casefold() in {".html", ".htm", ".xhtml"}
            )
            if not names:
                raise UnsupportedFormatError("EPUB içinde okunabilir XHTML bulunamadı.")
            try:
                from bs4 import BeautifulSoup
            except ImportError as exc:  # pragma: no cover
                raise UnsupportedFormatError("EPUB için beautifulsoup4 kurulmalıdır.") from exc
            for name in names:
                raw = archive.read(name)
                soup = BeautifulSoup(raw, "html.parser")
                for element in soup(["script", "style", "noscript"]):
                    element.decompose()
                value = _clean_text(soup.get_text("\n", strip=True))
                if value:
                    blocks.append(DocumentBlock(text=value, section=Path(name).stem))
        finally:
            archive.close()
        return ParsedDocument(
            title=title or path.stem,
            blocks=blocks,
            parser=self.name,
            parser_version=self.version,
        )


class PdfParser:
    name = "pypdf"
    version = _package_version("pypdf")

    def parse(self, path: Path, *, title: str | None = None) -> ParsedDocument:
        try:
            from pypdf import PdfReader
        except ImportError as exc:  # pragma: no cover
            raise UnsupportedFormatError("PDF için pypdf kurulmalıdır.") from exc
        try:
            reader = PdfReader(path, strict=False)
            if reader.is_encrypted:
                try:
                    unlocked = reader.decrypt("")
                except Exception as exc:
                    raise UnsupportedFormatError("Parolalı PDF açılamadı.") from exc
                if not unlocked:
                    raise UnsupportedFormatError("Parolalı PDF açılamadı.")
            blocks = []
            for page_number, page in enumerate(reader.pages, start=1):
                value = _clean_text(page.extract_text() or "")
                if value:
                    blocks.append(
                        DocumentBlock(
                            text=value,
                            page=page_number,
                            anchor_type=AnchorType.PAGE,
                        )
                    )
            metadata = {}
            if reader.metadata:
                metadata = {
                    str(key).lstrip("/"): str(value) for key, value in reader.metadata.items()
                }
            detected_title = metadata.get("Title")
        except UnsupportedFormatError:
            raise
        except Exception as exc:
            raise UnsupportedFormatError(f"PDF ayrıştırılamadı: {type(exc).__name__}") from exc
        if not blocks:
            raise UnsupportedFormatError("PDF metin içermiyor; OCR eklentisi gereklidir.")
        return ParsedDocument(
            title=title or detected_title or path.stem,
            blocks=blocks,
            parser=self.name,
            parser_version=self.version,
            metadata=metadata,
        )


class DocxParser:
    name = "python-docx"
    version = _package_version("python-docx")

    def parse(self, path: Path, *, title: str | None = None) -> ParsedDocument:
        _safe_zip_members(path).close()
        try:
            from docx import Document
        except ImportError as exc:  # pragma: no cover
            raise UnsupportedFormatError("DOCX için python-docx kurulmalıdır.") from exc
        document = Document(str(path))
        blocks: list[DocumentBlock] = []
        section: str | None = None
        buffer: list[str] = []
        for paragraph in document.paragraphs:
            value = paragraph.text.strip()
            if not value:
                continue
            style = (paragraph.style.name if paragraph.style else "").casefold()
            if style.startswith(("heading", "başlık")):
                if buffer:
                    blocks.append(DocumentBlock(text="\n\n".join(buffer), section=section))
                    buffer = []
                section = value
            else:
                buffer.append(value)
        if buffer:
            blocks.append(DocumentBlock(text="\n\n".join(buffer), section=section))
        for table_index, table in enumerate(document.tables, start=1):
            rows = [" | ".join(cell.text.strip() for cell in row.cells) for row in table.rows]
            value = "\n".join(row for row in rows if row.strip(" |"))
            if value:
                blocks.append(
                    DocumentBlock(
                        text=value,
                        section=f"Tablo {table_index}",
                        anchor_type=AnchorType.TABLE,
                    )
                )
        props = document.core_properties
        metadata = {"author": props.author or "", "subject": props.subject or ""}
        return ParsedDocument(
            title=title or props.title or path.stem,
            blocks=blocks,
            parser=self.name,
            parser_version=self.version,
            metadata=metadata,
        )


class PptxParser:
    name = "python-pptx"
    version = _package_version("python-pptx")

    def parse(self, path: Path, *, title: str | None = None) -> ParsedDocument:
        _safe_zip_members(path).close()
        try:
            from pptx import Presentation
        except ImportError as exc:  # pragma: no cover
            raise UnsupportedFormatError("PPTX için python-pptx kurulmalıdır.") from exc
        presentation = Presentation(str(path))
        blocks: list[DocumentBlock] = []
        for number, slide in enumerate(presentation.slides, start=1):
            values: list[str] = []
            for shape in slide.shapes:
                if getattr(shape, "has_text_frame", False):
                    text_value = _clean_text(shape.text)
                    if text_value:
                        values.append(text_value)
                if getattr(shape, "has_table", False):
                    for row in shape.table.rows:
                        values.append(" | ".join(cell.text.strip() for cell in row.cells))
            notes_slide = getattr(slide, "notes_slide", None)
            if notes_slide is not None:
                note_texts = [
                    shape.text.strip()
                    for shape in notes_slide.shapes
                    if getattr(shape, "has_text_frame", False) and shape.text.strip()
                ]
                if note_texts:
                    values.append("Konuşmacı notları:\n" + "\n".join(note_texts))
            if values:
                blocks.append(
                    DocumentBlock(
                        text="\n\n".join(values),
                        section=f"Slayt {number}",
                        slide=number,
                        anchor_type=AnchorType.SLIDE,
                    )
                )
        return ParsedDocument(
            title=title or presentation.core_properties.title or path.stem,
            blocks=blocks,
            parser=self.name,
            parser_version=self.version,
        )


class XlsxParser:
    name = "openpyxl"
    version = _package_version("openpyxl")

    def parse(self, path: Path, *, title: str | None = None) -> ParsedDocument:
        _safe_zip_members(path).close()
        try:
            from openpyxl import load_workbook  # type: ignore[import-untyped]
        except ImportError as exc:  # pragma: no cover
            raise UnsupportedFormatError("XLSX için openpyxl kurulmalıdır.") from exc
        workbook = load_workbook(path, read_only=True, data_only=True)
        blocks: list[DocumentBlock] = []
        try:
            for sheet in workbook.worksheets:
                batch: list[str] = []
                start_row = 1
                for row_number, row in enumerate(sheet.iter_rows(values_only=True), start=1):
                    values = ["" if value is None else str(value) for value in row]
                    if any(value for value in values):
                        batch.append(" | ".join(values).rstrip(" |"))
                    if len(batch) >= 100:
                        blocks.append(
                            DocumentBlock(
                                text="\n".join(batch),
                                section=f"{sheet.title} satır {start_row}-{row_number}",
                                anchor_type=AnchorType.TABLE,
                            )
                        )
                        batch = []
                        start_row = row_number + 1
                if batch:
                    blocks.append(
                        DocumentBlock(
                            text="\n".join(batch),
                            section=f"{sheet.title} satır {start_row}-{sheet.max_row}",
                            anchor_type=AnchorType.TABLE,
                        )
                    )
        finally:
            workbook.close()
        return ParsedDocument(
            title=title or path.stem,
            blocks=blocks,
            parser=self.name,
            parser_version=self.version,
        )


class DelimitedParser:
    name = "delimited"
    version = "1"

    def __init__(self, delimiter: str | None = None) -> None:
        self.delimiter = delimiter

    def parse(self, path: Path, *, title: str | None = None) -> ParsedDocument:
        text_value = _read_text(path)
        sample = text_value[:8192]
        delimiter = self.delimiter
        if delimiter is None:
            try:
                delimiter = csv.Sniffer().sniff(sample, delimiters=",;\t|").delimiter
            except csv.Error:
                delimiter = ","
        reader = csv.reader(text_value.splitlines(), delimiter=delimiter)
        blocks: list[DocumentBlock] = []
        batch: list[str] = []
        start_row = 1
        last_row = 0
        for last_row, row in enumerate(reader, start=1):
            batch.append(" | ".join(cell.strip() for cell in row))
            if len(batch) >= 100:
                blocks.append(
                    DocumentBlock(
                        text="\n".join(batch),
                        section=f"Satır {start_row}-{last_row}",
                        anchor_type=AnchorType.TABLE,
                    )
                )
                batch = []
                start_row = last_row + 1
        if batch:
            blocks.append(
                DocumentBlock(
                    text="\n".join(batch),
                    section=f"Satır {start_row}-{last_row}",
                    anchor_type=AnchorType.TABLE,
                )
            )
        return ParsedDocument(
            title=title or path.stem,
            blocks=blocks,
            parser=self.name,
            parser_version=self.version,
            metadata={"delimiter": delimiter},
        )


class JsonParser:
    name = "json"
    version = "1"

    def parse(self, path: Path, *, title: str | None = None) -> ParsedDocument:
        try:
            value = json.loads(_read_text(path))
        except json.JSONDecodeError as exc:
            raise UnsupportedFormatError(f"Geçersiz JSON: satır {exc.lineno}") from exc
        blocks: list[DocumentBlock] = []
        if isinstance(value, dict):
            for key, item in value.items():
                blocks.append(
                    DocumentBlock(
                        text=json.dumps(item, ensure_ascii=False, indent=2), section=str(key)
                    )
                )
        elif isinstance(value, list):
            for start in range(0, len(value), 50):
                blocks.append(
                    DocumentBlock(
                        text=json.dumps(value[start : start + 50], ensure_ascii=False, indent=2),
                        section=f"Öğe {start + 1}-{min(start + 50, len(value))}",
                    )
                )
        else:
            blocks = [DocumentBlock(text=json.dumps(value, ensure_ascii=False))]
        return ParsedDocument(
            title=title or path.stem,
            blocks=blocks,
            parser=self.name,
            parser_version=self.version,
        )


class XmlParser:
    name = "xml"
    version = "1"

    def parse(self, path: Path, *, title: str | None = None) -> ParsedDocument:
        try:
            root = ElementTree.fromstring(path.read_bytes())
        except ElementTree.ParseError as exc:
            raise UnsupportedFormatError(f"Geçersiz XML: {exc}") from exc
        blocks: list[DocumentBlock] = []
        candidates = list(root)
        if not candidates:
            candidates = [root]
        for index, element in enumerate(candidates, start=1):
            text_value = _clean_text(
                " ".join(piece.strip() for piece in element.itertext() if piece.strip())
            )
            if not text_value:
                continue
            tag = element.tag.rsplit("}", 1)[-1]
            blocks.append(DocumentBlock(text=text_value, section=f"{tag} {index}"))
        return ParsedDocument(
            title=title or path.stem,
            blocks=blocks,
            parser=self.name,
            parser_version=self.version,
            metadata={"root": root.tag.rsplit("}", 1)[-1]},
        )


class OpenDocumentParser:
    name = "opendocument"
    version = "1"

    def parse(self, path: Path, *, title: str | None = None) -> ParsedDocument:
        archive = _safe_zip_members(path)
        try:
            if "content.xml" not in archive.namelist():
                raise UnsupportedFormatError("OpenDocument content.xml içermiyor.")
            try:
                root = ElementTree.fromstring(archive.read("content.xml"))
            except ElementTree.ParseError as exc:
                raise UnsupportedFormatError("OpenDocument XML'i bozuk.") from exc
        finally:
            archive.close()
        blocks: list[DocumentBlock] = []
        for element in root.iter():
            local = element.tag.rsplit("}", 1)[-1]
            if local not in {"p", "h", "table-row"}:
                continue
            value = _clean_text(
                " ".join(part.strip() for part in element.itertext() if part.strip())
            )
            if value:
                blocks.append(DocumentBlock(text=value, section=local if local == "h" else None))
        return ParsedDocument(
            title=title or path.stem,
            blocks=blocks,
            parser=self.name,
            parser_version=self.version,
        )


class BibtexParser:
    name = "bibtex"
    version = "1"
    _entry = re.compile(r"@(?P<type>\w+)\s*\{(?P<key>[^,]+),(?P<body>.*?)(?=\n@|\Z)", re.DOTALL)

    def parse(self, path: Path, *, title: str | None = None) -> ParsedDocument:
        text_value = _read_text(path)
        blocks = [
            DocumentBlock(
                text=_clean_text(match.group(0)),
                section=f"{match.group('type')}:{match.group('key').strip()}",
            )
            for match in self._entry.finditer(text_value)
        ]
        if not blocks and text_value.strip():
            blocks = [DocumentBlock(text=_clean_text(text_value), section="BibTeX")]
        return ParsedDocument(
            title=title or path.stem,
            blocks=blocks,
            parser=self.name,
            parser_version=self.version,
        )


class RisParser:
    name = "ris"
    version = "1"

    def parse(self, path: Path, *, title: str | None = None) -> ParsedDocument:
        records = re.split(r"(?m)^ER\s*-\s*.*$", _read_text(path))
        blocks = []
        for index, record in enumerate(records, start=1):
            value = _clean_text(record)
            if value:
                title_match = re.search(r"(?m)^(?:TI|T1)\s*-\s*(.+)$", value)
                blocks.append(
                    DocumentBlock(
                        text=value,
                        section=title_match.group(1).strip() if title_match else f"Kayıt {index}",
                    )
                )
        return ParsedDocument(
            title=title or path.stem,
            blocks=blocks,
            parser=self.name,
            parser_version=self.version,
        )


class SequenceParser:
    name = "biopython-sequence"
    version = _package_version("biopython")

    def __init__(self, file_format: str) -> None:
        self.file_format = file_format

    def parse(self, path: Path, *, title: str | None = None) -> ParsedDocument:
        try:
            from Bio import SeqIO
        except ImportError as exc:  # pragma: no cover - declared base dependency
            raise UnsupportedFormatError("Dizi formatları için Biopython kurulmalıdır.") from exc
        try:
            records = list(SeqIO.parse(str(path), self.file_format))
        except Exception as exc:
            raise UnsupportedFormatError(f"Biyolojik dizi ayrıştırılamadı: {exc}") from exc
        if not records:
            raise UnsupportedFormatError("Dosyada biyolojik dizi kaydı bulunamadı.")
        blocks: list[DocumentBlock] = []
        for record in records:
            sequence = str(record.seq)
            description = record.description or record.id
            metadata_lines = [
                f"Kayıt: {record.id}",
                f"Açıklama: {description}",
                f"Uzunluk: {len(sequence)}",
            ]
            if self.file_format == "fastq" and "phred_quality" in record.letter_annotations:
                qualities = record.letter_annotations["phred_quality"]
                metadata_lines.append(
                    f"Ortalama Phred: {sum(qualities) / max(1, len(qualities)):.2f}"
                )
            blocks.append(DocumentBlock(text="\n".join(metadata_lines), section=record.id))
            for start in range(0, len(sequence), 1800):
                end = min(start + 1800, len(sequence))
                blocks.append(
                    DocumentBlock(
                        text=f">{record.id} baz {start + 1}-{end}\n{sequence[start:end]}",
                        section=record.id,
                        anchor_type=AnchorType.SEQUENCE,
                        sequence_start=start + 1,
                        sequence_end=end,
                    )
                )
            if self.file_format in {"genbank", "embl"}:
                feature_lines = []
                for feature in record.features:
                    feature_lines.append(
                        f"{feature.type}\t{feature.location}\t"
                        f"{json.dumps(dict(feature.qualifiers), ensure_ascii=False)}"
                    )
                for start in range(0, len(feature_lines), 50):
                    block_lines = feature_lines[start : start + 50]
                    if block_lines:
                        blocks.append(
                            DocumentBlock(
                                text="\n".join(block_lines),
                                section=(
                                    f"{record.id} özellikler {start + 1}-{start + len(block_lines)}"
                                ),
                                anchor_type=AnchorType.SEQUENCE,
                            )
                        )
        return ParsedDocument(
            title=title or path.stem,
            blocks=blocks,
            parser=self.name,
            parser_version=self.version,
            metadata={"format": self.file_format, "records": len(records)},
        )


class FeatureTableParser:
    name = "genomic-feature-table"
    version = "1"

    def __init__(self, kind: str) -> None:
        self.kind = kind

    def parse(self, path: Path, *, title: str | None = None) -> ParsedDocument:
        headers: list[str] = []
        groups: dict[str, list[tuple[int, int, str]]] = defaultdict(list)
        for line_number, line in enumerate(_read_text(path).splitlines(), start=1):
            if not line.strip() or line.startswith("#"):
                headers.append(line)
                continue
            columns = line.split("\t")
            try:
                if self.kind == "vcf":
                    key, start, end = columns[0], int(columns[1]), int(columns[1])
                else:
                    key, start, end = columns[0], int(columns[3]), int(columns[4])
            except (IndexError, ValueError) as exc:
                raise UnsupportedFormatError(
                    f"{self.kind.upper()} satır {line_number} geçersiz."
                ) from exc
            groups[key].append((start, end, line))
        blocks: list[DocumentBlock] = []
        if headers:
            blocks.append(
                DocumentBlock(text="\n".join(headers), section=f"{self.kind.upper()} başlık")
            )
        for key, entries in groups.items():
            for offset in range(0, len(entries), 100):
                batch = entries[offset : offset + 100]
                blocks.append(
                    DocumentBlock(
                        text="\n".join(item[2] for item in batch),
                        section=f"{key} kayıt {offset + 1}-{offset + len(batch)}",
                        anchor_type=AnchorType.SEQUENCE,
                        sequence_start=min(item[0] for item in batch),
                        sequence_end=max(item[1] for item in batch),
                    )
                )
        return ParsedDocument(
            title=title or path.stem,
            blocks=blocks,
            parser=self.name,
            parser_version=self.version,
            metadata={"format": self.kind},
        )


class StructureParser:
    name = "molecular-structure"
    version = "1"

    def __init__(self, kind: str) -> None:
        self.kind = kind

    def parse(self, path: Path, *, title: str | None = None) -> ParsedDocument:
        lines = _read_text(path).splitlines()
        blocks: list[DocumentBlock] = []
        if self.kind == "pdb":
            summary = [
                line
                for line in lines
                if line.startswith(("HEADER", "TITLE ", "COMPND", "SOURCE", "KEYWDS", "SEQRES"))
            ]
            if summary:
                blocks.append(DocumentBlock(text="\n".join(summary), section="PDB üstveri"))
            by_chain: dict[str, list[tuple[int, str]]] = defaultdict(list)
            for line in lines:
                if line.startswith(("ATOM  ", "HETATM")) and len(line) >= 26:
                    chain = line[21].strip() or "_"
                    try:
                        residue = int(line[22:26].strip())
                    except ValueError:
                        residue = 0
                    by_chain[chain].append((residue, line))
            for chain, atoms in by_chain.items():
                for offset in range(0, len(atoms), 250):
                    batch = atoms[offset : offset + 250]
                    residues = [entry[0] for entry in batch if entry[0]]
                    blocks.append(
                        DocumentBlock(
                            text="\n".join(entry[1] for entry in batch),
                            section=f"Zincir {chain} atom {offset + 1}-{offset + len(batch)}",
                            anchor_type=AnchorType.SEQUENCE,
                            sequence_start=min(residues) if residues else None,
                            sequence_end=max(residues) if residues else None,
                        )
                    )
        else:
            # mmCIF is a tokenized tabular format. Keeping loop boundaries intact is
            # more useful for retrieval than flattening it through an XML-like parser.
            current: list[str] = []
            section = "mmCIF"
            for line in lines:
                if line.startswith("data_") or line.strip() == "loop_":
                    if current:
                        blocks.append(DocumentBlock(text="\n".join(current), section=section))
                    current = [line]
                    section = line.strip()
                else:
                    current.append(line)
                if len(current) >= 250:
                    blocks.append(DocumentBlock(text="\n".join(current), section=section))
                    current = []
            if current:
                blocks.append(DocumentBlock(text="\n".join(current), section=section))
        if not blocks:
            raise UnsupportedFormatError("Moleküler yapı kaydı bulunamadı.")
        return ParsedDocument(
            title=title or path.stem,
            blocks=blocks,
            parser=self.name,
            parser_version=self.version,
            metadata={"format": self.kind},
        )


class SmilesParser:
    name = "smiles"
    version = "1"

    def parse(self, path: Path, *, title: str | None = None) -> ParsedDocument:
        rows = [line.strip() for line in _read_text(path).splitlines() if line.strip()]
        blocks = [
            DocumentBlock(
                text="\n".join(rows[start : start + 100]),
                section=f"Molekül {start + 1}-{min(start + 100, len(rows))}",
            )
            for start in range(0, len(rows), 100)
        ]
        return ParsedDocument(
            title=title or path.stem,
            blocks=blocks,
            parser=self.name,
            parser_version=self.version,
        )


class SdfParser:
    name = "sdf"
    version = "1"

    def parse(self, path: Path, *, title: str | None = None) -> ParsedDocument:
        records = [record.strip() for record in _read_text(path).split("$$$$") if record.strip()]
        blocks = []
        for index, record in enumerate(records, start=1):
            first_line = record.splitlines()[0].strip() if record.splitlines() else ""
            blocks.append(DocumentBlock(text=record, section=first_line or f"Molekül {index}"))
        return ParsedDocument(
            title=title or path.stem,
            blocks=blocks,
            parser=self.name,
            parser_version=self.version,
        )


class HookedMediaParser:
    name = "media-hook"
    version = "1"

    def __init__(self, kind: str, hook: MediaTranscriptionHook | None) -> None:
        self.kind = kind
        self.hook = hook

    def parse(self, path: Path, *, title: str | None = None) -> ParsedDocument:
        if self.hook is None:
            raise UnsupportedFormatError(
                f"{self.kind.capitalize()} ayrıştırıcısı hazır değil; "
                "SesLab/Whisper hook'u yapılandırın."
            )
        blocks = self.hook(path, kind=self.kind)
        if not blocks:
            raise UnsupportedFormatError(f"{self.kind.capitalize()} transkripsiyonu boş döndü.")
        return ParsedDocument(
            title=title or path.stem,
            blocks=blocks,
            parser=self.name,
            parser_version=self.version,
            metadata={"media_kind": self.kind},
        )


class ParserRegistry:
    """Deterministic extension registry with explicit media integration hooks."""

    audio_suffixes = {".wav", ".mp3", ".m4a", ".flac", ".ogg", ".aac"}
    video_suffixes = {".mp4", ".mov", ".mkv", ".webm", ".m4v"}

    def __init__(self) -> None:
        self._parsers: dict[str, SourceParser] = {}
        self._media_hooks: dict[str, MediaTranscriptionHook | None] = {
            "audio": None,
            "video": None,
        }
        self._install_defaults()

    def _register_many(self, suffixes: Iterable[str], parser: SourceParser) -> None:
        for suffix in suffixes:
            self.register(suffix, parser)

    def _install_defaults(self) -> None:
        docling = DoclingParser()
        self._register_many({".txt", ".md", ".markdown", ".rst", ".tex", ".log"}, TextParser())
        self._register_many(
            {".html", ".htm", ".xhtml"}, DoclingPreferredParser(docling, HtmlParser())
        )
        self.register(".epub", EpubParser())
        self.register(".pdf", DoclingPreferredParser(docling, PdfParser()))
        self.register(".docx", DoclingPreferredParser(docling, DocxParser()))
        self.register(".pptx", DoclingPreferredParser(docling, PptxParser()))
        self.register(".xlsx", DoclingPreferredParser(docling, XlsxParser()))
        self._register_many(
            {".png", ".jpg", ".jpeg", ".tif", ".tiff", ".webp", ".heic"},
            DoclingPreferredParser(docling, UnavailableImageParser()),
        )
        self.register(".csv", DelimitedParser())
        self.register(".tsv", DelimitedParser("\t"))
        self.register(".json", JsonParser())
        self._register_many({".xml", ".jats"}, XmlParser())
        self._register_many({".odt", ".ods", ".odp"}, OpenDocumentParser())
        self.register(".bib", BibtexParser())
        self.register(".ris", RisParser())
        self._register_many({".fa", ".fasta", ".fna", ".faa", ".ffn"}, SequenceParser("fasta"))
        self._register_many({".fq", ".fastq"}, SequenceParser("fastq"))
        self._register_many({".gb", ".gbk", ".genbank"}, SequenceParser("genbank"))
        self.register(".embl", SequenceParser("embl"))
        self._register_many({".gff", ".gff3"}, FeatureTableParser("gff"))
        self.register(".gtf", FeatureTableParser("gtf"))
        self.register(".vcf", FeatureTableParser("vcf"))
        self.register(".pdb", StructureParser("pdb"))
        self._register_many({".cif", ".mmcif"}, StructureParser("mmcif"))
        self._register_many({".smi", ".smiles"}, SmilesParser())
        self._register_many({".sdf", ".mol"}, SdfParser())

    def register(self, suffix: str, parser: SourceParser) -> None:
        normalized = suffix.casefold()
        if not normalized.startswith("."):
            normalized = f".{normalized}"
        self._parsers[normalized] = parser

    def register_media_hook(self, kind: str, hook: MediaTranscriptionHook | None) -> None:
        if kind not in self._media_hooks:
            raise ValueError("kind must be 'audio' or 'video'")
        self._media_hooks[kind] = hook

    def resolve(self, path: Path, mime_type: str | None = None) -> SourceParser:
        suffix = path.suffix.casefold()
        normalized_mime = (mime_type or "").split(";", 1)[0].strip().casefold()
        if suffix in self.audio_suffixes or (mime_type or "").startswith("audio/"):
            return HookedMediaParser("audio", self._media_hooks["audio"])
        if suffix in self.video_suffixes or (mime_type or "").startswith("video/"):
            return HookedMediaParser("video", self._media_hooks["video"])
        parser = self._parsers.get(suffix)
        if parser is not None:
            return parser
        mime_suffix = {
            "application/pdf": ".pdf",
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document": ".docx",
            "application/vnd.openxmlformats-officedocument.presentationml.presentation": ".pptx",
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": ".xlsx",
            "application/epub+zip": ".epub",
            "application/json": ".json",
            "application/xml": ".xml",
            "text/html": ".html",
            "text/csv": ".csv",
        }.get(normalized_mime)
        if mime_suffix and mime_suffix in self._parsers:
            return self._parsers[mime_suffix]
        if (mime_type or "").startswith("text/"):
            return TextParser()
        raise UnsupportedFormatError(
            f"'{suffix or 'uzantısız'}' formatı için kayıtlı bir ayrıştırıcı yok."
        )

    def parse(
        self, path: Path, *, mime_type: str | None = None, title: str | None = None
    ) -> ParsedDocument:
        return self.resolve(path, mime_type).parse(path, title=title)

    @property
    def supported_suffixes(self) -> tuple[str, ...]:
        return tuple(sorted(set(self._parsers) | self.audio_suffixes | self.video_suffixes))


def detect_mime_type(path: Path, supplied: str | None = None) -> str:
    if supplied and supplied != "application/octet-stream":
        return supplied.split(";", 1)[0].strip().casefold()
    guessed, _encoding = mimetypes.guess_type(path.name)
    return guessed or "application/octet-stream"


def parse_path(
    path: str | Path,
    *,
    mime_type: str | None = None,
    title: str | None = None,
    registry: ParserRegistry | None = None,
) -> ParsedDocument:
    source_path = Path(path)
    active_registry = registry or ParserRegistry()
    return active_registry.parse(
        source_path,
        mime_type=detect_mime_type(source_path, mime_type),
        title=title,
    )
