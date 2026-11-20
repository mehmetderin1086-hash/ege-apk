"""Headless command-line interface for KitapKatalog."""

from __future__ import annotations

import argparse
import csv
import json
import os
import shutil
import socket
import sys
import tempfile
from collections import Counter
from collections.abc import Mapping
from dataclasses import asdict
from datetime import date, datetime
from enum import Enum
from pathlib import Path
from typing import Any

from kitapkatalog.archive import create_archive, extract_archive, inspect_archive
from kitapkatalog.calibration import (
    CalibrationSample,
    ReviewLabel,
    fit_isotonic_profile,
    samples_from_reviews,
)
from kitapkatalog.capacity import estimate_import_capacity, require_capacity
from kitapkatalog.catalog import Catalog
from kitapkatalog.config import AppPaths, RuntimeLimits
from kitapkatalog.database import Database
from kitapkatalog.documents import (
    SUPPORTED_DOCUMENT_SUFFIXES,
    build_single_book_scan,
    expand_bulk_documents,
    folder_locations,
)
from kitapkatalog.domain import BOOK_SURFACE_ORDER, SearchFilters, StorageMode
from kitapkatalog.evaluation import FieldEvaluation, evaluate_acceptance
from kitapkatalog.exporters import ExportFormat, export_catalog, import_local_catalog
from kitapkatalog.importzip import ZipExpansionError, expand_zip_upload
from kitapkatalog.offline import install_network_guard
from kitapkatalog.pairing import discover_documents, pair_cover_files
from kitapkatalog.pipeline import PipelineConfig
from kitapkatalog.resources import HEAVY_ENGINE_IDS
from kitapkatalog.restore import collect_cover_paths

# Web yükleme uçlarındaki (routes_imports.py) sınırlarla aynı büyüklük
# mertebesi; CLI'nin kendi çok dosyalı istek bütçesi olmadığından burada
# yalnızca zip bombasına karşı bağımsız bir tavan olarak tutulur.
_CLI_ZIP_MAX_FILES = 2_000
_CLI_ZIP_MAX_FILE_BYTES = 512 * 1024**2
_CLI_ZIP_MAX_TOTAL_BYTES = 8 * 1024**3


def _default_database() -> str:
    return str(AppPaths.default().database)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="kitapkatalog",
        description="Beş OCR motorlu, tamamen çevrimdışı kitap kataloğu",
    )
    parser.add_argument(
        "--database",
        default=_default_database(),
        help="SQLite katalog yolu (varsayılan: %(default)s)",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        dest="json_output",
        help="Sonucu makine-okunur JSON olarak yaz",
    )
    commands = parser.add_subparsers(dest="command", required=True)

    commands.add_parser("init", help="Veritabanını ve veri klasörlerini hazırla")

    add = commands.add_parser(
        "import",
        aliases=["import-images", "import-bulk"],
        help="Dört yüzlü kitap klasörünü toplu eşleştirip kuyruğa ekle",
    )
    add.add_argument("source", help="Fotoğraf/PDF klasörü")
    add.add_argument("--name", help="İçe aktarma işi adı")
    add.add_argument("--no-recursive", action="store_true")
    add.add_argument("--no-sequence", action="store_true")
    add.add_argument(
        "--reference",
        action="store_true",
        help="Fotoğrafları yönetilen alana kopyalama; kaynaklara başvur",
    )
    add.add_argument(
        "--dolap",
        help="Bu partideki kitapların yerleştirileceği dolap/raf adı",
    )
    add.add_argument(
        "--klasor-dolap",
        action="store_true",
        help="Her kitabın dolabı, dosyalarının bulunduğu klasörün adı olsun",
    )
    add.add_argument("--idempotency-key")

    single = commands.add_parser(
        "import-single",
        help="Bir kitabı dört sıralı belge veya tek dört-sayfalı PDF olarak ekle",
    )
    single.add_argument(
        "documents",
        nargs="+",
        help="Ön, ön iç, arka iç, arka sırasıyla dört belge; veya tek 4 sayfalı PDF",
    )
    single.add_argument("--name", help="İçe aktarma işi adı")
    single.add_argument(
        "--reference",
        action="store_true",
        help="Görüntüleri yönetilen alana kopyalama; kaynaklara başvur",
    )
    single.add_argument("--dolap", help="Kitabın yerleştirileceği dolap/raf adı")
    single.add_argument("--idempotency-key")

    metadata = commands.add_parser(
        "import-metadata", help="Yerel CSV/JSON/JSONL kataloğunu içe aktar"
    )
    metadata.add_argument("source")
    metadata.add_argument("--fail-fast", action="store_true", help="İlk hatalı kayıtta dur")

    run = commands.add_parser(
        "run",
        aliases=["process"],
        help="Kuyruktaki kitapları beş OCR ve alan çıkarıcıyla işle",
    )
    run.add_argument(
        "job_id",
        nargs="?",
        help="Yalnız bu işi çalıştır; verilmezse bütün hazır kuyruktan tüket",
    )
    run.add_argument("--worker-id")

    export = commands.add_parser("export", help="Kataloğu dışa aktar")
    export.add_argument("destination")
    export.add_argument("--format", choices=[item.value for item in ExportFormat])
    export.add_argument(
        "--include-incomplete",
        action="store_true",
        help="Devam eden işlere bağlı taslak kayıtları da ekle",
    )

    search = commands.add_parser("search", help="Tam metin katalog araması")
    search.add_argument("query", nargs="?", default="")
    search.add_argument("--publisher")
    search.add_argument("--language")
    search.add_argument("--review-status")
    search.add_argument("--identifier")
    search.add_argument("--limit", type=int, default=50)
    search.add_argument("--offset", type=int, default=0)

    listing = commands.add_parser("list", help="Katalog kayıtlarını listele")
    listing.add_argument("--review-status")
    listing.add_argument("--limit", type=int, default=100)
    listing.add_argument("--offset", type=int, default=0)

    jobs = commands.add_parser("jobs", help="İçe aktarma işlerini listele")
    jobs.add_argument("--limit", type=int, default=100)
    jobs.add_argument("--offset", type=int, default=0)

    job = commands.add_parser("job", help="Bir işin aşama ve motor ilerlemesini göster")
    job.add_argument("job_id")

    performance = commands.add_parser(
        "perf-report",
        help="Kayıtlı OCR sürelerinden motor kırılımı ve kitap/saat raporu üret",
    )
    performance.add_argument("--job-id", default=None, help="Yalnız bu işin koşumlarını özetle")
    performance.add_argument(
        "--book-workers",
        type=int,
        default=None,
        help="Eşzamanlı kitap işçisi sayısı (varsayılan: RuntimeLimits)",
    )

    for name, help_text in (
        ("pause", "İşi duraklat"),
        ("resume", "Duraklatılmış işi sürdür"),
        ("cancel", "İşi iptal et"),
    ):
        action = commands.add_parser(name, help=help_text)
        action.add_argument("job_id")

    retry = commands.add_parser("retry", help="Başarısız iş öğesini yeniden kuyruğa al")
    retry.add_argument("item_id", type=int)

    voice = commands.add_parser("voice", help="Sesli kitap kaydı: ses dosyasından kataloğa")
    voice_commands = voice.add_subparsers(dest="voice_command", required=True)
    voice_add = voice_commands.add_parser("add", help="Ses dosyasını kuyruğa al (m4a/mp3/wav)")
    voice_add.add_argument("audio")
    voice_add.add_argument("--name", default=None, help="İş adı")
    voice_add.add_argument(
        "--single",
        action="store_true",
        help="Kayıt tek kitap içerir; ayraç aranmaz",
    )
    voice_run = voice_commands.add_parser(
        "run", help="Ses işini çalıştır (transkripsiyon + kataloglama)"
    )
    voice_run.add_argument("job_id", nargs="?", default=None)
    voice_commands.add_parser("jobs", help="Ses işlerini listele")
    voice_job = voice_commands.add_parser("job", help="Ses işinin öğelerini göster")
    voice_job.add_argument("job_id")
    for voice_name, voice_help in (
        ("pause", "Ses işini duraklat"),
        ("resume", "Ses işini sürdür"),
        ("cancel", "Ses işini iptal et"),
    ):
        voice_action = voice_commands.add_parser(voice_name, help=voice_help)
        voice_action.add_argument("job_id")
    voice_retry = voice_commands.add_parser(
        "retry", help="Hatalı/incelemedeki ses öğesini yeniden kuyruğa al"
    )
    voice_retry.add_argument("item_id", type=int)

    pair_reviews = commands.add_parser(
        "pair-reviews",
        help="Onay bekleyen dört-yüzlü kitap eşleştirmelerini listele",
    )
    pair_reviews.add_argument("--job-id")
    pair_reviews.add_argument("--limit", type=int, default=250)
    pair_reviews.add_argument("--offset", type=int, default=0)

    pair_review = commands.add_parser(
        "pair-review",
        help="Belirsiz bir dört-yüzlü kitap eşleştirmesini onayla veya reddet",
    )
    pair_review.add_argument("item_id", type=int)
    pair_decision = pair_review.add_mutually_exclusive_group(required=True)
    pair_decision.add_argument("--approve", action="store_true", help="Çifti onayla")
    pair_decision.add_argument(
        "--reject",
        action="store_true",
        help="Çifti hata kuyruğuna gönder",
    )

    engines = commands.add_parser(
        "engine-status", aliases=["engines"], help="Beş OCR ve Qwen paketini doğrula"
    )
    engines.add_argument("--model-root")
    engines.add_argument("--manifest")

    review = commands.add_parser("review", help="İnceleme kayıtlarını listele veya düzelt")
    review.add_argument("--id", type=int, dest="edition_id")
    review.add_argument(
        "--set",
        action="append",
        default=[],
        metavar="ALAN=DEĞER",
        help="Alanı kullanıcı değeriyle değiştir ve kilitle",
    )
    review.add_argument("--approve", action="store_true")
    review.add_argument("--limit", type=int, default=100)

    archive = commands.add_parser(
        "archive",
        help=".kitaparsiv yedeği oluştur, doğrula veya güvenli biçimde çıkar",
    )
    archive_commands = archive.add_subparsers(dest="archive_command", required=True)
    archive_create = archive_commands.add_parser(
        "create", help="Tutarlı SQLite anlık görüntüsünden yedek oluştur"
    )
    archive_create.add_argument("destination")
    archive_create.add_argument(
        "--include-covers",
        action="store_true",
        help="Yönetilen kapak dosyalarını da yedeğe ekle",
    )
    archive_create.add_argument(
        "--asset-root",
        help="Yönetilen kapak kökü (varsayılan: veri klasöründeki assets)",
    )
    archive_inspect = archive_commands.add_parser(
        "inspect", help="Yedeği ve bütünlük hash'lerini doğrula"
    )
    archive_inspect.add_argument("source")
    archive_extract = archive_commands.add_parser(
        "extract", help="Doğrulanmış yedeği boş bir klasöre çıkar"
    )
    archive_extract.add_argument("source")
    archive_extract.add_argument("destination")

    evaluate = commands.add_parser(
        "evaluate",
        help="İncelenen alanlardan kabul raporu üret (precision/recall/ECE kapıları)",
    )
    evaluate.add_argument(
        "--minimum-fields",
        type=int,
        default=50,
        help="Rapor için gereken en az incelenmiş alan (varsayılan: %(default)s)",
    )

    samples = commands.add_parser(
        "export-calibration-samples",
        help="İncelenen alanlardan kalibrasyon örnekleri çıkar (fit-calibration girdisi)",
    )
    samples.add_argument(
        "destination",
        nargs="?",
        default=None,
        help="Hedef .jsonl dosyası; verilmezse yalnız özet yazılır",
    )
    samples.add_argument(
        "--minimum-samples",
        type=int,
        default=200,
        help="Otomatik kabulü açmak için gereken örnek sayısı (varsayılan: %(default)s)",
    )

    calibration = commands.add_parser(
        "fit-calibration",
        help="Etiketli JSON/JSONL/CSV güven örneklerinden izotonik profil üret",
    )
    calibration.add_argument("source")
    calibration.add_argument("destination")
    calibration.add_argument("--version")
    calibration.add_argument("--minimum-samples", type=int, default=200)

    online = commands.add_parser(
        "online-oneri",
        help=(
            "İnternetten ISBN önerisi getir (OpenLibrary/Google Books). "
            "Yalnız bu komut ağa çıkar; öneriler otomatik kabul edilmez."
        ),
    )
    online.add_argument(
        "--isbn",
        nargs="*",
        default=None,
        help="Yalnız bu ISBN-13'leri sorgula (verilmezse eksik künyeli kitaplar)",
    )
    online.add_argument(
        "--limit", type=int, default=50, help="En fazla kaç ISBN sorgulansın (varsayılan 50)"
    )

    commands.add_parser("gui", help="Masaüstü arayüzünü aç")
    return parser


def _serialise(value: Any) -> Any:
    if isinstance(value, (datetime, date)):
        return value.isoformat()
    if isinstance(value, Path):
        return str(value)
    if isinstance(value, Enum):
        return value.value
    if isinstance(value, tuple):
        return [_serialise(item) for item in value]
    if isinstance(value, list):
        return [_serialise(item) for item in value]
    if isinstance(value, dict):
        return {str(key): _serialise(item) for key, item in value.items()}
    if hasattr(value, "__dataclass_fields__"):
        return _serialise(asdict(value))
    if hasattr(value, "__dict__"):
        return _serialise(vars(value))
    return value


def _emit(value: Any, *, json_output: bool) -> None:
    if json_output:
        print(json.dumps(_serialise(value), ensure_ascii=False, indent=2))
        return
    if isinstance(value, str):
        print(value)
    elif isinstance(value, list):
        for item in value:
            print(_human_line(item))
    else:
        print(_human_line(value))


def _human_line(value: Any) -> str:
    if hasattr(value, "title") and hasattr(value, "edition_id"):
        authors = ", ".join(contributor.name for contributor in getattr(value, "contributors", ()))
        suffix = f" — {authors}" if authors else ""
        return f"{value.edition_id}: {value.title}{suffix}"
    if hasattr(value, "id") and hasattr(value, "status"):
        total = getattr(value, "total_items", None)
        progress = f" ({getattr(value, 'terminal_items', 0)}/{total})" if total is not None else ""
        return f"{value.id}: {getattr(value, 'name', '')} — {value.status}{progress}"
    if isinstance(value, dict):
        return " | ".join(f"{key}={_serialise(item)}" for key, item in value.items())
    return str(value)


def _paths_for_database(path: str | Path) -> AppPaths:
    defaults = AppPaths.default()
    database = Path(path).expanduser()
    if database.resolve() == defaults.database.resolve():
        return defaults
    root = database.parent
    return AppPaths(
        root=root,
        database=database,
        assets=root / "assets",
        derivatives=root / "derivatives",
        ocr_raw=root / "ocr-raw",
        models=defaults.models,
        exports=root / "exports",
        logs=root / "logs",
        owns_data_root=False,
    )


def _enqueue_pairs(
    database: Database,
    *,
    name: str,
    pairs: tuple[Any, ...],
    storage_mode: StorageMode,
    idempotency_key: str | None,
    location: str | None = None,
    locations: Mapping[str, str] | None = None,
) -> Any:
    """Persist large imports in independent chunks without loading OCR models."""

    if idempotency_key:
        existing = database.fetchone(
            "SELECT id FROM import_job WHERE idempotency_key = ?",
            (idempotency_key,),
        )
        if existing is not None:
            return database.get_import_job(str(existing["id"]))
    first = pairs[:250]
    job = database.create_import_job(
        name,
        first,
        storage_mode=storage_mode,
        idempotency_key=idempotency_key,
        location=location,
        locations=locations,
    )
    for start in range(250, len(pairs), 250):
        database.append_job_items(job.id, pairs[start : start + 250], locations=locations)
    return database.get_import_job(job.id) or job


def _parse_changes(values: list[str]) -> dict[str, str]:
    changes: dict[str, str] = {}
    for value in values:
        if "=" not in value:
            raise ValueError(f"--set ALAN=DEĞER biçiminde olmalıdır: {value}")
        field, text = value.split("=", 1)
        field = field.strip()
        if not field:
            raise ValueError("--set alan adı boş olamaz")
        changes[field] = text
    return changes


def _pair_image_paths(pairs: tuple[Any, ...]) -> tuple[Path, ...]:
    return tuple(
        dict.fromkeys(
            Path(path) for pair in pairs for path in pair.paths_by_role.values() if path is not None
        )
    )


def _correct_value(value: object) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, int | float) and value in {0, 1}:
        return bool(value)
    normalized = str(value).strip().casefold()
    if normalized in {"1", "true", "yes", "doğru", "dogru"}:
        return True
    if normalized in {"0", "false", "no", "yanlış", "yanlis"}:
        return False
    raise ValueError(f"Kalibrasyon correct değeri boolean değil: {value!r}")


def _calibration_samples(path: Path) -> list[CalibrationSample]:
    suffix = path.suffix.casefold()
    rows: list[dict[str, object]]
    if suffix == ".csv":
        with path.open("r", encoding="utf-8-sig", newline="") as handle:
            rows = [dict(row) for row in csv.DictReader(handle)]
    elif suffix == ".jsonl":
        rows = []
        for line_number, line in enumerate(
            path.read_text(encoding="utf-8-sig").splitlines(),
            1,
        ):
            if not line.strip():
                continue
            value = json.loads(line)
            if not isinstance(value, dict):
                raise ValueError(f"JSONL satırı nesne değil: {line_number}")
            rows.append(value)
    elif suffix == ".json":
        payload = json.loads(path.read_text(encoding="utf-8-sig"))
        raw_rows = payload.get("samples") if isinstance(payload, dict) else payload
        if not isinstance(raw_rows, list) or not all(isinstance(item, dict) for item in raw_rows):
            raise ValueError("Kalibrasyon JSON'u nesne listesi veya samples listesi olmalıdır")
        rows = raw_rows
    else:
        raise ValueError("Kalibrasyon kaynağı .json, .jsonl veya .csv olmalıdır")
    samples: list[CalibrationSample] = []
    for index, row in enumerate(rows, 1):
        confidence = row.get("raw_confidence", row.get("confidence"))
        if confidence is None or "correct" not in row:
            raise ValueError(
                f"Kalibrasyon örneği #{index} raw_confidence/confidence ve correct içermelidir"
            )
        samples.append(
            CalibrationSample(
                raw_confidence=float(confidence),
                correct=_correct_value(row["correct"]),
            )
        )
    if not samples:
        raise ValueError("Kalibrasyon kaynağında örnek yok")
    return samples


# Otomatik kabul eşiği boru hattıyla aynı kaynaktan gelmeli.
AUTO_CONFIDENCE = PipelineConfig().auto_confidence

# `docs/TEST_VE_KABUL_TR.md` sürüm kapısı: M4/16 GB üzerinde en az bu hız.
BOOKS_PER_HOUR_GATE = 60
SURFACES_PER_BOOK = len(BOOK_SURFACE_ORDER)


def _performance_report(
    durations: dict[str, Any],
    *,
    book_workers: int | None,
) -> dict[str, Any]:
    """Turn recorded engine durations into the throughput the gate asks about.

    Heavy engines hold a process-wide lock, so their time never overlaps no
    matter how many book workers run.  The projection therefore reports two
    numbers: what the light engines allow with the configured workers, and the
    ceiling the serialised heavy path imposes regardless.
    """

    workers = max(
        1, int(book_workers if book_workers is not None else RuntimeLimits().book_workers)
    )
    engines: dict[str, Any] = durations["engines"]
    heavy_ms = sum(
        summary["mean_ms"] for name, summary in engines.items() if name in HEAVY_ENGINE_IDS
    )
    light_ms = sum(
        summary["mean_ms"] for name, summary in engines.items() if name not in HEAVY_ENGINE_IDS
    )
    per_book_ms = (heavy_ms + light_ms) * SURFACES_PER_BOOK
    heavy_per_book_ms = heavy_ms * SURFACES_PER_BOOK
    worker_books_per_hour = _books_per_hour(per_book_ms / workers)
    heavy_ceiling_books_per_hour = _books_per_hour(heavy_per_book_ms)
    # No heavy-engine measurement means no heavy-engine constraint. Reporting a
    # ceiling of zero would read as "this catalogue cannot process anything".
    limits = [worker_books_per_hour]
    if heavy_ceiling_books_per_hour:
        limits.append(heavy_ceiling_books_per_hour)
    books_per_hour = min(limits)
    return {
        **durations,
        "book_workers": workers,
        "surfaces_per_book": SURFACES_PER_BOOK,
        "engine_ms_per_book": per_book_ms,
        "heavy_ms_per_book": heavy_per_book_ms,
        "books_per_hour": books_per_hour,
        "books_per_hour_worker_bound": worker_books_per_hour,
        "books_per_hour_heavy_ceiling": heavy_ceiling_books_per_hour or None,
        "gate_books_per_hour": BOOKS_PER_HOUR_GATE,
        "meets_gate": books_per_hour >= BOOKS_PER_HOUR_GATE,
        "days_for_10000_books": (
            round(10_000 / books_per_hour / 24, 2) if books_per_hour else None
        ),
        "bottleneck": max(engines, key=lambda name: engines[name]["mean_ms"]) if engines else None,
    }


def _acceptance_report(database: Database, *, minimum_fields: int) -> dict[str, Any]:
    """Run the acceptance metrics over the fields this catalogue has reviewed.

    `evaluate_acceptance` has always existed but nothing outside the tests
    called it, so the gates it defines could never be checked against a real
    catalogue.  CER and barcode inputs need a labelled OCR corpus, which this
    catalogue does not have; those gates stay unmeasured and are reported as
    such rather than being silently reported as passed.

    Provenance is read from the stored observation rather than assumed.  Passing
    a constant would make the coverage gate report a perfect score it never
    checked — the same dishonesty the unmeasured gates above avoid.
    """

    labels = [ReviewLabel(**row) for row in database.review_labels()]
    fields = [
        FieldEvaluation(
            predicted=label.observed_value,
            expected=label.confirmed_value,
            confidence=min(1.0, max(0.0, label.raw_confidence)),
            # Only proposals the pipeline would have accepted on its own count
            # towards precision.
            auto_accepted=label.raw_confidence >= AUTO_CONFIDENCE,
            has_visual_provenance=label.has_visual_provenance,
            engine_support=label.engine_ids,
            field_name=label.field_path,
        )
        for label in labels
    ]
    if len(fields) < minimum_fields:
        return {
            "measurable": False,
            "fields": len(fields),
            "minimum_fields": minimum_fields,
            "reason": (
                f"Kabul raporu için en az {minimum_fields} incelenmiş alan gerekiyor; "
                f"şu an {len(fields)} var."
            ),
        }
    report = evaluate_acceptance(
        fields,
        expected_ocr_texts=(),
        ensemble_ocr_texts=(),
        single_engine_ocr_texts={},
    )
    metrics = report.metrics
    return {
        "measurable": True,
        "fields": len(fields),
        "automatic_precision": metrics.automatic_precision,
        "automatic_recall": metrics.automatic_recall,
        "automatic_f1": metrics.automatic_f1,
        "automatic_count": metrics.automatic_count,
        "ece": metrics.ece,
        "ece_all_candidates": metrics.ece_all_candidates,
        "by_field": {name: asdict(value) for name, value in sorted(metrics.by_field.items())},
        "violations": list(report.violations),
        # A labelled OCR corpus is a separate artefact; without it these gates
        # are unmeasured, not passed.
        "unmeasured_gates": [
            "ensemble CER iyileşmesi",
            "Türkçe karakter hatası",
            "barkod ISBN recall",
        ],
    }


def _export_calibration_samples(
    database: Database,
    *,
    destination: str | None,
    minimum_samples: int,
) -> dict[str, Any]:
    """Turn reviewed fields into the file ``fit-calibration`` already reads.

    This closes the loop the pipeline was missing: reviewing books is what
    produces the labels, and enough labels are what switch automatic acceptance
    back on. The output format is the existing one, so nothing downstream
    changes.
    """

    labels = [ReviewLabel(**row) for row in database.review_labels()]
    samples = samples_from_reviews(labels)
    by_field: Counter[str] = Counter(label.field_path for label in labels)
    correct = sum(1 for sample in samples if sample.correct)
    written: Path | None = None
    if destination is not None:
        written = Path(destination).expanduser()
        written.parent.mkdir(parents=True, exist_ok=True)
        lines = "".join(
            json.dumps(
                {"raw_confidence": sample.raw_confidence, "correct": sample.correct},
                ensure_ascii=False,
            )
            + "\n"
            for sample in samples
        )
        written.write_text(lines, encoding="utf-8")
    return {
        "samples": len(samples),
        "correct": correct,
        "incorrect": len(samples) - correct,
        "minimum_samples": minimum_samples,
        "sufficient": len(samples) >= minimum_samples,
        "remaining": max(0, minimum_samples - len(samples)),
        "fields": dict(by_field.most_common()),
        "destination": written,
    }


def _books_per_hour(milliseconds_per_book: float) -> float:
    if milliseconds_per_book <= 0:
        return 0.0
    return round(3_600_000 / milliseconds_per_book, 1)


def _run_catalog_command(
    args: argparse.Namespace, database: Database, catalog: Catalog
) -> Any:
    if args.command == "init":
        return {
            "database": str(database.path),
            "integrity": database.integrity_check(),
        }
    if args.command == "import-single":
        paths = _paths_for_database(args.database)
        scan = build_single_book_scan(
            args.documents,
            paths.derivatives / "pdf-pages",
        )
        storage_mode = StorageMode.REFERENCE if args.reference else StorageMode.MANAGED_COPY
        estimate = estimate_import_capacity(
            _pair_image_paths((scan,)),
            data_root=paths.root,
            model_root=paths.models,
            storage_mode=storage_mode,
        )
        require_capacity(estimate)
        job = _enqueue_pairs(
            database,
            name=args.name or "Tek kitap - dört yüz",
            pairs=(scan,),
            storage_mode=storage_mode,
            idempotency_key=args.idempotency_key,
            location=getattr(args, "dolap", None),
        )
        return {
            "mode": "single",
            "job": job,
            "books": 1,
            "surfaces": 4,
            "dolap": job.location,
            "storage_mode": storage_mode,
            "capacity": {
                **asdict(estimate),
                "sufficient": estimate.sufficient,
                "shortfall_bytes": estimate.shortfall_bytes,
            },
            "paths": {
                role.value: str(path)
                for role, path in scan.paths_by_role.items()
                if path is not None
            },
        }
    if args.command in {"import", "import-images", "import-bulk"}:
        require_four_surfaces = args.command == "import-bulk"
        source = Path(args.source).expanduser()
        paths = _paths_for_database(args.database)
        zip_extraction_root: Path | None = None
        if source.is_file() and source.suffix.casefold() == ".zip":
            if args.reference:
                raise SystemExit(
                    "--reference bir ZIP kaynağıyla kullanılamaz: önce ZIP'i "
                    "açıp klasörü öyle referans gösterin"
                )
            # Açılım, render_root'un (paths.derivatives/pdf-pages) yanında,
            # aynı derivatives kökü altındaki geçici bir dizine yapılır.
            paths.derivatives.mkdir(parents=True, exist_ok=True)
            zip_extraction_root = Path(
                tempfile.mkdtemp(prefix="zip-import-", dir=paths.derivatives)
            )
            try:
                zip_expansion = expand_zip_upload(
                    source,
                    zip_extraction_root,
                    allowed_suffixes=SUPPORTED_DOCUMENT_SUFFIXES,
                    max_members=_CLI_ZIP_MAX_FILES,
                    max_total_bytes=_CLI_ZIP_MAX_TOTAL_BYTES,
                    max_file_bytes=_CLI_ZIP_MAX_FILE_BYTES,
                )
            except ZipExpansionError as error:
                shutil.rmtree(zip_extraction_root, ignore_errors=True)
                raise SystemExit(f"ZIP açılamadı: {error}") from error
            documents = tuple(sorted(zip_expansion.files))
            folder_root = zip_extraction_root
        else:
            documents = discover_documents(source, recursive=not args.no_recursive)
            folder_root = source
        # Sıraya alınan öğeler bu açılım dizinindeki yolları saklar; asıl
        # kopyalama/OCR ancak sonraki bir `run` çağrısında olur, dolayısıyla
        # dizin yalnızca kuyruğa yazma BAŞARISIZ olursa temizlenir — başarılı
        # bir işten sonra silmek kuyruktaki kayıtları kaynaksız bırakırdı.
        try:
            expanded = expand_bulk_documents(
                documents,
                paths.derivatives / "pdf-pages",
            )
            pairing = pair_cover_files(
                expanded.images,
                infer_sequence=not args.no_sequence,
                require_four_surfaces=require_four_surfaces,
            )
            pairs = (*expanded.four_page_books, *pairing.pairs)
            locations = (
                folder_locations(pairs, expanded, root=folder_root)
                if getattr(args, "klasor_dolap", False)
                else None
            )
            storage_mode = StorageMode.REFERENCE if args.reference else StorageMode.MANAGED_COPY
            estimate = estimate_import_capacity(
                _pair_image_paths(pairs),
                data_root=paths.root,
                model_root=paths.models,
                storage_mode=storage_mode,
            )
            require_capacity(estimate)
            job = _enqueue_pairs(
                database,
                name=args.name
                or source.name
                or (
                    "Toplu dört yüz içe aktarma"
                    if require_four_surfaces
                    else "Eski iki kapak içe aktarma"
                ),
                pairs=pairs,
                storage_mode=storage_mode,
                idempotency_key=args.idempotency_key,
                location=getattr(args, "dolap", None),
                locations=locations,
            )
            return {
                "job": job,
                "storage_mode": storage_mode,
                "dolap": job.location,
                "klasor_dolaplari": sorted(set((locations or {}).values())),
                "capacity": {
                    **asdict(estimate),
                    "sufficient": estimate.sufficient,
                    "shortfall_bytes": estimate.shortfall_bytes,
                },
                "mode": "bulk",
                "documents": len(documents),
                "images": len(expanded.images),
                "books": len(pairs),
                "pairs": len(pairs),
                "surfaces": sum(len(pair.active_roles) for pair in pairs),
                "needs_review": pairing.needs_review_count,
                "unpaired": [str(path) for path in pairing.unpaired],
                "ignored": [str(path) for path in pairing.ignored],
                "rejected_pdfs": [
                    {"path": str(path), "reason": reason} for path, reason in expanded.rejected
                ],
                "split_pdfs": [
                    {"path": str(path), "books": books}
                    for path, books in expanded.split_documents
                ],
                "ambiguous": [
                    {
                        "reason": issue.reason,
                        "candidates": [str(path) for path in issue.candidates],
                    }
                    for issue in pairing.ambiguous
                ],
            }
        except BaseException:
            if zip_extraction_root is not None:
                shutil.rmtree(zip_extraction_root, ignore_errors=True)
            raise
    if args.command == "import-metadata":
        return import_local_catalog(args.source, catalog, continue_on_error=not args.fail_fast)
    if args.command == "export":
        return export_catalog(
            database,
            args.destination,
            format=args.format,
            completed_only=not args.include_incomplete,
        )
    if args.command == "search":
        page = catalog.search(
            args.query,
            filters=SearchFilters(
                publisher=args.publisher,
                language=args.language,
                review_status=args.review_status,
                identifier=args.identifier,
            ),
            limit=args.limit,
            offset=args.offset,
        )
        return {
            "total": page.total,
            "limit": page.limit,
            "offset": page.offset,
            "items": page.items,
        }
    if args.command == "list":
        return catalog.list_books(
            limit=args.limit,
            offset=args.offset,
            review_status=args.review_status,
        )
    if args.command == "voice":
        from kitapkatalog.voice_scheduler import build_voice_scheduler

        paths = _paths_for_database(args.database)
        paths.ensure()
        voice_scheduler = build_voice_scheduler(database, paths)
        if args.voice_command == "add":
            return voice_scheduler.enqueue(
                Path(args.audio).expanduser(),
                name=args.name,
                single_book=args.single,
            )
        if args.voice_command == "run":
            if args.job_id is not None:
                return voice_scheduler.run_job(args.job_id)
            summary = voice_scheduler.run_next()
            return summary if summary is not None else {"durum": "kuyruk boş"}
        if args.voice_command == "jobs":
            return database.list_voice_jobs()
        if args.voice_command == "job":
            return {
                "job": database.get_voice_job(args.job_id),
                "items": database.list_voice_items(args.job_id),
            }
        if args.voice_command == "pause":
            return database.pause_voice_job(args.job_id)
        if args.voice_command == "resume":
            return database.resume_voice_job(args.job_id)
        if args.voice_command == "cancel":
            return database.cancel_voice_job(args.job_id)
        if args.voice_command == "retry":
            return database.retry_failed_voice_item(args.item_id)
        raise SystemExit(f"Bilinmeyen voice komutu: {args.voice_command}")

    if args.command == "jobs":
        return database.list_import_jobs(limit=args.limit, offset=args.offset)
    if args.command == "job":
        return database.job_progress(args.job_id)
    if args.command == "perf-report":
        return _performance_report(
            database.engine_durations(job_id=args.job_id),
            book_workers=args.book_workers,
        )
    if args.command == "export-calibration-samples":
        return _export_calibration_samples(
            database,
            destination=args.destination,
            minimum_samples=args.minimum_samples,
        )
    if args.command == "evaluate":
        return _acceptance_report(database, minimum_fields=args.minimum_fields)
    if args.command == "pause":
        return database.pause_job(args.job_id)
    if args.command == "resume":
        return database.resume_job(args.job_id)
    if args.command == "cancel":
        return database.cancel_job(args.job_id)
    if args.command == "retry":
        return database.retry_failed_item(args.item_id)
    if args.command == "pair-reviews":
        return database.list_pending_pair_reviews(
            job_id=args.job_id,
            limit=args.limit,
            offset=args.offset,
        )
    if args.command == "pair-review":
        return database.approve_pair(args.item_id, approved=args.approve)
    if args.command in {"engine-status", "engines"}:
        from kitapkatalog.model_manager import ModelManager

        paths = AppPaths.default()
        if args.model_root:
            paths = AppPaths(
                root=paths.root,
                database=paths.database,
                assets=paths.assets,
                derivatives=paths.derivatives,
                ocr_raw=paths.ocr_raw,
                models=Path(args.model_root).expanduser(),
                exports=paths.exports,
                logs=paths.logs,
            )
        manager = ModelManager(paths, manifest_path=Path(args.manifest) if args.manifest else None)
        return manager.runtime_report()
    if args.command == "review":
        if args.edition_id is None:
            return catalog.list_books(review_status="review", limit=args.limit, offset=0)
        changes = _parse_changes(args.set)
        if args.approve:
            changes["review_status"] = "completed"
        if changes:
            return catalog.update_book(args.edition_id, changes, user_edit=True)
        record = catalog.get_book(args.edition_id)
        if record is None:
            raise KeyError(f"Baskı bulunamadı: {args.edition_id}")
        return record
    if args.command == "archive":
        if args.archive_command == "create":
            paths = _paths_for_database(args.database)
            asset_root = Path(args.asset_root).expanduser() if args.asset_root else paths.assets
            return create_archive(
                database.path,
                Path(args.destination).expanduser(),
                asset_root=asset_root,
                cover_paths=(
                    collect_cover_paths(database.path, asset_root)
                    if args.include_covers
                    else ()
                ),
                include_covers=args.include_covers,
            )
        raise AssertionError(f"İşlenmeyen arşiv komutu: {args.archive_command}")
    raise AssertionError(f"İşlenmeyen komut: {args.command}")


def _run(args: argparse.Namespace) -> Any:
    # These commands intentionally inspect external artifacts without opening,
    # creating or migrating the configured live catalogue.
    if args.command == "archive" and args.archive_command == "inspect":
        return inspect_archive(Path(args.source).expanduser())
    if args.command == "archive" and args.archive_command == "extract":
        return extract_archive(
            Path(args.source).expanduser(),
            Path(args.destination).expanduser(),
        )
    if args.command == "fit-calibration":
        source = Path(args.source).expanduser()
        destination = Path(args.destination).expanduser()
        profile = fit_isotonic_profile(
            _calibration_samples(source),
            version=args.version or source.stem,
            minimum_samples=args.minimum_samples,
        )
        profile.save(destination)
        return {
            "destination": destination,
            "version": profile.version,
            "samples": profile.total_samples,
            "minimum_samples": profile.minimum_samples,
            "trusted": profile.trusted,
            "automatic_acceptance": profile.trusted,
            "digest": profile.digest(),
        }
    if args.command == "gui":
        from kitapkatalog.gui import main as gui_main

        return gui_main(["--database", args.database])

    # Every catalogue-bearing command shares the web app's fail-closed open
    # path: pending restore first, exclusive pre-upgrade archive and verified
    # rollback, then a process-lifetime shared application lock.
    from kitapkatalog.application import open_application

    # online-oneri süreci allowlist kilidini main() içinde ZATEN kurdu;
    # open_application'ın tam çevrimdışı kilidi kurmasına izin verilirse iki
    # kilidin karşılıklı dışlaması RuntimeError üretir ve komut hiç çalışamaz.
    context = open_application(
        _paths_for_database(args.database),
        enforce_offline=(args.command != "online-oneri"),
    )
    try:
        if args.command == "online-oneri":
            return _run_online_suggestions(context.database, args)
        if args.command in {"run", "process"}:
            worker_id = (
                args.worker_id
                or f"cli-{socket.gethostname().split('.')[0]}-{os.getpid()}"
            )
            scheduler = context.processing_scheduler()
            if args.job_id:
                return scheduler.run_job(args.job_id, worker_id=worker_id)
            return scheduler.run_all(worker_id=worker_id)
        return _run_catalog_command(args, context.database, context.catalog)
    finally:
        context.close()


def _run_online_suggestions(database: Database, args: argparse.Namespace) -> dict[str, Any]:
    """external_suggestion tablosuna bekleyen dış öneriler yazar.

    Kanıt-bağlılık ilkesi: dış veri asla otomatik kabul edilmez; her satır
    `pending` durumuyla Onay Merkezi'nde kullanıcı onayı bekler. Daha önce
    `dismissed`/`accepted` işaretlenen kayıtların durumu korunur.
    """

    from kitapkatalog.offline import allowlist_guard_installed
    from kitapkatalog.online_suggest import fetch_suggestions

    if not allowlist_guard_installed():
        raise RuntimeError(
            "online-oneri yalnız allowlist ağ kilidiyle çalışır; "
            "bu komutu doğrudan `kitapkatalog online-oneri` olarak çalıştırın."
        )

    if args.isbn:
        targets = [
            (candidate, None)
            for raw in args.isbn
            if (candidate := "".join(ch for ch in raw if ch.isdigit()))
            and len(candidate) == 13
        ]
        if not targets:
            raise ValueError("Geçerli 13 haneli ISBN verilmedi")
    else:
        rows = database.fetchall(
            """
            SELECT i.normalized_value AS isbn13, i.edition_id
            FROM identifier AS i JOIN edition AS e ON e.id = i.edition_id
            WHERE i.scheme = 'isbn13'
              AND (e.publisher IS NULL OR e.publisher = ''
                   OR e.publication_date IS NULL OR e.publication_date = ''
                   OR e.page_count IS NULL)
            ORDER BY e.id DESC
            """
        )
        targets = [(row["isbn13"], row["edition_id"]) for row in rows]
    targets = targets[: max(1, min(int(args.limit), 500))]

    written = 0
    failures = 0
    from datetime import UTC

    now = datetime.now(UTC).isoformat(timespec="seconds")
    for isbn13, edition_id in targets:
        suggestions = fetch_suggestions(isbn13)
        if not suggestions:
            failures += 1
            continue
        with database.transaction() as connection:
            for suggestion in suggestions:
                connection.execute(
                    """
                    INSERT INTO external_suggestion
                        (isbn13, source, payload_json, fetched_at, edition_id, status)
                    VALUES (?, ?, ?, ?, ?, 'pending')
                    ON CONFLICT(isbn13, source) DO UPDATE SET
                        payload_json = excluded.payload_json,
                        fetched_at = excluded.fetched_at,
                        edition_id = COALESCE(excluded.edition_id, edition_id)
                    """,
                    (
                        isbn13,
                        suggestion.source,
                        json.dumps(suggestion.payload(), ensure_ascii=False),
                        now,
                        edition_id,
                    ),
                )
                written += 1
    return {
        "queried": len(targets),
        "suggestions_written": written,
        "unreachable": failures,
        "note": "Öneriler otomatik kabul edilmez; Onay Merkezi'nde gözden geçirin.",
    }


def _leading_command(raw_args: list[str]) -> str | None:
    """Global bayrakları (--database DEĞER, --json) atlayıp alt komutu bulur."""

    index = 0
    while index < len(raw_args):
        token = raw_args[index]
        if token == "--database":
            index += 2
            continue
        if token.startswith("--database="):
            index += 1
            continue
        if token in {"--json", "-h", "--help"}:
            index += 1
            continue
        if token.startswith("-"):
            index += 1
            continue
        return token
    return None


def main(argv: list[str] | None = None) -> int:
    # Must run before a command can import any OCR implementation.
    # Tek istisna "online-oneri": ayrı bir süreçte, yalnız öneri kaynaklarına
    # açık allowlist kilidiyle çalışır — ana kilit ile birleşemez (offline.py).
    raw_args = sys.argv[1:] if argv is None else argv
    if _leading_command(raw_args) == "online-oneri":
        from kitapkatalog.offline import install_allowlist_guard
        from kitapkatalog.online_suggest import ALLOWED_SUGGESTION_HOSTS

        install_allowlist_guard(ALLOWED_SUGGESTION_HOSTS)
    else:
        install_network_guard()
    parser = build_parser()
    try:
        args = parser.parse_args(argv)
        # Sigorta: _leading_command tahmini ile argparse sonucu uyuşmalı.
        # Uyuşmazsa (örn. ileride eklenecek bir global bayrak tahmini şaşırtırsa)
        # yanlış kilitle çalışmak yerine açık hatayla dururuz.
        from kitapkatalog.offline import allowlist_guard_installed

        if (args.command == "online-oneri") != allowlist_guard_installed():
            print(
                "Hata: ağ kilidi komutla uyuşmuyor; komutu doğrudan "
                "`kitapkatalog online-oneri` biçiminde çalıştırın.",
                file=sys.stderr,
            )
            return 2
        result = _run(args)
        if isinstance(result, int) and args.command == "gui":
            return result
        _emit(result, json_output=args.json_output)
        return 0
    except (
        FileNotFoundError,
        NotADirectoryError,
        KeyError,
        ValueError,
        OSError,
        RuntimeError,
    ) as exc:
        print(f"Hata: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
