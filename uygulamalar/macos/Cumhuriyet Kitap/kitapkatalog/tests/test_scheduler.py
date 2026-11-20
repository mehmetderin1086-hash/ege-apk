from __future__ import annotations

import threading
import time
from collections import Counter
from pathlib import Path
from typing import Any

import pytest
from PIL import Image

from kitapkatalog.calibration import CalibrationBin, ConfidenceCalibrationProfile
from kitapkatalog.config import RuntimeLimits
from kitapkatalog.database import Database
from kitapkatalog.domain import (
    CoverRole,
    FieldStatus,
    ImagePair,
    JobItemStage,
    OcrEngine,
    StorageMode,
)
from kitapkatalog.extractor import (
    EvidenceBoundExtractor,
    EvidenceToken,
    ExtractedField,
)
from kitapkatalog.images import CoverPreprocessor, PreparedImage
from kitapkatalog.ocr.contracts import (
    CLASSIC_ENGINE_IDS,
    REQUIRED_ENGINE_IDS,
    VISION_ENGINE_IDS,
    EngineAvailability,
    EngineOcrResult,
    OcrEngineAdapter,
    OcrToken,
    rectangular_polygon,
)
from kitapkatalog.ocr.registry import FiveEngineRegistry
from kitapkatalog.pipeline import FiveOcrPipeline, ZstdJsonResultStore
from kitapkatalog.resources import MemoryAdmissionController
from kitapkatalog.scheduler import (
    DurableScheduler,
    SchedulerResources,
    _choose_field_candidate,
    _FieldEvidence,
    _FieldResolutionCandidate,
)

_TRUSTED_CALIBRATION = ConfidenceCalibrationProfile(
    version="test-calibration-v1",
    bins=(
        CalibrationBin(upper_bound=0.995, calibrated_probability=0.50, sample_count=250),
        CalibrationBin(upper_bound=1.0, calibrated_probability=0.999, sample_count=250),
    ),
    total_samples=500,
)


class ConcurrencyTracker:
    def __init__(self) -> None:
        self.lock = threading.Lock()
        self.active = 0
        self.maximum = 0


class FakeEngine(OcrEngineAdapter):
    def __init__(
        self,
        engine_id: str,
        calls: Counter[str],
        *,
        fail: bool = False,
        tracker: ConcurrencyTracker | None = None,
    ) -> None:
        self.engine_id = engine_id
        self.evidence_kind = "classic" if engine_id in CLASSIC_ENGINE_IDS else "vision"
        self.model_version = "fixture-1"
        self.calls = calls
        self.fail = fail
        self.tracker = tracker
        self.releases = 0

    def availability(self) -> EngineAvailability:
        return EngineAvailability(
            engine_id=self.engine_id,
            available=True,
            version=self.model_version,
        )

    def recognize(self, image: PreparedImage) -> EngineOcrResult:
        if self.tracker is None:
            self.calls[self.engine_id] += 1
        else:
            with self.tracker.lock:
                self.calls[self.engine_id] += 1
                self.tracker.active += 1
                self.tracker.maximum = max(
                    self.tracker.maximum,
                    self.tracker.active,
                )
        try:
            if self.tracker is not None:
                time.sleep(0.02)
            if self.fail:
                raise RuntimeError(f"{self.engine_id} fixture failure")
            lines = (
                ("Kürk Mantolu Madonna", 20.0, 20.0, 620.0, 120.0, "title"),
                ("Sabahattin Ali", 20.0, 180.0, 450.0, 240.0, "author"),
                ("Yapı Kredi Yayınları", 20.0, 300.0, 580.0, 360.0, "publisher"),
                ("ISBN 9789753638029", 20.0, 430.0, 620.0, 490.0, "isbn"),
                ("Çizer: Sadi Güran", 20.0, 540.0, 620.0, 600.0, "illustrator"),
                ("320 sayfa", 20.0, 650.0, 320.0, 710.0, "page_count"),
            )
            tokens = tuple(
                OcrToken(
                    token_id=f"{self.engine_id}:{line_id}",
                    text=text,
                    confidence=0.999,
                    polygon=rectangular_polygon(left, top, right, bottom),
                    line_id=line_id,
                    language="tr",
                )
                for text, left, top, right, bottom, line_id in lines
            )
            return EngineOcrResult(
                engine_id=self.engine_id,
                model_version=self.model_version,
                image_sha256=image.image_sha256,
                variant="canonical",
                tokens=tokens,
                raw_text="\n".join(item[0] for item in lines),
                duration_ms=7,
                evidence_kind=self.evidence_kind,
            )
        finally:
            if self.tracker is not None:
                with self.tracker.lock:
                    self.tracker.active -= 1

    def release(self) -> None:
        self.releases += 1


class GroundedFieldModel:
    def extract(self, tokens: list[EvidenceToken]) -> list[dict[str, Any]]:
        by_text: dict[str, EvidenceToken] = {}
        for token in tokens:
            by_text.setdefault(token.text, token)
        fields = [
            {
                "field_name": field,
                "value": value,
                "evidence_token_ids": [by_text[evidence_text].token_id],
                "confidence": 0.999,
            }
            for field, value, evidence_text in (
                ("title", "Kürk Mantolu Madonna", "Kürk Mantolu Madonna"),
                ("author", "Sabahattin Ali", "Sabahattin Ali"),
                ("publisher", "Yapı Kredi Yayınları", "Yapı Kredi Yayınları"),
                ("contributor.illustrator", "Sadi Güran", "Çizer: Sadi Güran"),
            )
        ]
        page_token = next(
            (
                token
                for token in tokens
                if token.cover == "back_inside" and token.text == "320 sayfa"
            ),
            None,
        )
        if page_token is not None:
            fields.append(
                {
                    "field_name": "page_count",
                    "value": "320 sayfa",
                    "evidence_token_ids": [page_token.token_id],
                    "confidence": 0.999,
                }
            )
        return fields


def _limits() -> RuntimeLimits:
    return RuntimeLimits(
        chunk_books=250,
        microbatch_pairs=8,
        soft_rss_bytes=10**15,
        hard_rss_bytes=10**15 + 1,
        lease_seconds=30,
        max_retries=2,
    )


def _scheduler(
    root: Path,
    calls: Counter[str],
    *,
    failing_engine: str | None = None,
    tracker: ConcurrencyTracker | None = None,
) -> tuple[DurableScheduler, Database, list[FakeEngine]]:
    database = Database(root / "catalog.sqlite3")
    engines = [
        FakeEngine(
            engine_id,
            calls,
            fail=engine_id == failing_engine,
            tracker=tracker,
        )
        for engine_id in REQUIRED_ENGINE_IDS
    ]
    registry = FiveEngineRegistry(engines)
    pipeline = FiveOcrPipeline(
        registry=registry,
        preprocessor=CoverPreprocessor(root / "derivatives"),
        result_store=ZstdJsonResultStore(root / "ocr-raw"),
        calibration_profile=_TRUSTED_CALIBRATION,
    )
    limits = _limits()
    resources = SchedulerResources(
        controller=MemoryAdmissionController(
            limits,
            minimum_system_available=0,
        ),
        heavy_lock_path=root / "locks" / "heavy-model.lock",
        admission_timeout_seconds=5,
    )
    scheduler = DurableScheduler(
        database=database,
        pipeline=pipeline,
        extractor=EvidenceBoundExtractor(GroundedFieldModel()),
        asset_root=root / "assets",
        resources=resources,
        limits=limits,
    )
    return scheduler, database, engines


def _cover(path: Path, color: tuple[int, int, int]) -> None:
    Image.new("RGB", (800, 1100), color).save(path, format="PNG")


def _resolution_candidate(
    value: str,
    status: FieldStatus,
    confidence: float,
    *,
    field_name: str = "publisher",
    role: CoverRole = CoverRole.FRONT_INSIDE,
) -> _FieldResolutionCandidate:
    evidence = _FieldEvidence(
        role=role,
        spans=(),
        confidence=confidence,
        polygon=((0.0, 0.0), (10.0, 0.0), (10.0, 10.0), (0.0, 10.0)),
        source_polygon=None,
        source_token_ids=("token",),
        engines=(OcrEngine.RAPIDOCR, OcrEngine.EASYOCR),
    )
    field = ExtractedField(
        field_name=field_name,
        value=value,
        evidence_token_ids=("token",),
        confidence=confidence,
        source="test",
        status=status.value,
    )
    return _FieldResolutionCandidate(
        field=field,
        path=f"edition.{field_name}",
        value=value,
        evidence=evidence,
        status=status,
    )


def test_publisher_resolution_keeps_all_evidence_but_selects_complete_name() -> None:
    winner = _choose_field_candidate(
        "edition.publisher",
        (
            _resolution_candidate("Kültür Yayınları", FieldStatus.AUTO, 0.98),
            _resolution_candidate(
                "TÜRKİYE İŞ BANKASI KÜLTÜR YAYINLARI",
                FieldStatus.REVIEW,
                0.937,
            ),
            _resolution_candidate(
                "© TÜRKİYE İŞ BANKASI KÜLTÜR YAYINLARI, 2020",
                FieldStatus.AUTO,
                0.99,
            ),
        ),
    )

    assert winner.value == "TÜRKİYE İŞ BANKASI KÜLTÜR YAYINLARI"
    assert winner.status == FieldStatus.REVIEW


def test_equal_corroborated_title_prefers_original_front_cover_casing() -> None:
    winner = _choose_field_candidate(
        "edition.title",
        (
            _resolution_candidate(
                "TÜRKİYE'NIN BÜTÜN AĞAÇLARI VE ÇALILARI",
                FieldStatus.REVIEW,
                0.89,
                field_name="title",
                role=CoverRole.FRONT_INSIDE,
            ),
            _resolution_candidate(
                "Türkiye'nin Bütün Ağaçları ve Çalıları",
                FieldStatus.REVIEW,
                0.89,
                field_name="title",
                role=CoverRole.FRONT,
            ),
        ),
    )

    assert winner.value == "Türkiye'nin Bütün Ağaçları ve Çalıları"


def test_real_fake_five_engine_queue_is_durable_and_cache_only_on_rerun(
    tmp_path: Path,
) -> None:
    front = tmp_path / "book_front.png"
    back = tmp_path / "book_back.png"
    _cover(front, (90, 20, 20))
    _cover(back, (20, 40, 90))
    calls: Counter[str] = Counter()
    scheduler, database, engines = _scheduler(tmp_path / "runtime", calls)

    first = scheduler.enqueue(
        "İlk tarama",
        [ImagePair(front, back, pair_key="book-1")],
        storage_mode=StorageMode.MANAGED_COPY,
    )
    first_run = scheduler.run_job(first.id, worker_id="worker-a")

    assert first_run.job.successful_items == 1
    assert first_run.job.failed_items == 0
    assert first_run.cache_hits == 0
    assert calls == Counter({engine_id: 2 for engine_id in REQUIRED_ENGINE_IDS})
    assert database.fetchone("SELECT COUNT(*) FROM edition")[0] == 1
    assert database.fetchone("SELECT COUNT(*) FROM copy")[0] == 1
    assert database.fetchone("SELECT COUNT(*) FROM job_item_engine")[0] == 10
    assert (
        database.fetchone("SELECT COUNT(*) FROM job_item_engine WHERE status = 'completed'")[0]
        == 10
    )
    assert database.fetchone("SELECT COUNT(*) FROM consensus_span")[0] >= 8
    assert (
        database.fetchone(
            "SELECT COUNT(*) FROM consensus_span WHERE source_polygon_json IS NOT NULL"
        )[0]
        >= 8
    )
    raw_paths = database.fetchall(
        "SELECT raw_result_path FROM job_item_engine ORDER BY raw_result_path"
    )
    assert len(raw_paths) == 10
    assert all(
        Path(row["raw_result_path"]).is_file()
        and Path(row["raw_result_path"]).suffixes[-2:] == [".json", ".zst"]
        for row in raw_paths
    )
    book = scheduler.catalog.list_books(limit=10)[0]
    assert book.title == "Kürk Mantolu Madonna"
    assert book.publisher == "Yapı Kredi Yayınları"
    assert book.page_count is None
    assert book.subtitle == "bilinmiyor"
    assert "9789753638029" in {item.value for item in book.identifiers}
    assert any(
        item.name == "Sabahattin Ali" and item.role == "author" for item in book.contributors
    )
    assert any(
        item.name == "Sadi Güran" and item.role == "illustrator" for item in book.contributors
    )
    assets = database.fetchall("SELECT source_path, managed_path, source_sha256 FROM image_asset")
    assert len(assets) == 2
    assert {Path(row["source_path"]) for row in assets} == {front, back}
    assert all(Path(row["managed_path"]).is_file() for row in assets)
    assert all(len(row["source_sha256"]) == 64 for row in assets)
    auto_title = database.fetchone(
        """
        SELECT rf.status, fo.polygon_json, fo.source_polygon_json,
               fo.engine_evidence_json
        FROM resolved_field AS rf
        JOIN field_observation AS fo ON fo.id = rf.observation_id
        WHERE rf.field_path = 'edition.title'
        """
    )
    assert auto_title is not None
    assert auto_title["status"] == "auto"
    assert auto_title["polygon_json"]
    assert auto_title["source_polygon_json"]
    assert "rapidocr_ppocrv6" in auto_title["engine_evidence_json"]
    # Qwen needs headroom from the heavy engines only. Unloading the light
    # in-process ones frees nothing and would make the next book reload them.
    released = {engine.engine_id for engine in engines if engine.releases >= 1}
    assert released == set(VISION_ENGINE_IDS)
    observation_count = database.fetchone("SELECT COUNT(*) FROM field_observation")[0]

    # A separate import of the same covers uses all ten content-addressed
    # checkpoints. No fake OCR adapter is called and the edition/copy is not
    # duplicated.
    second = scheduler.enqueue(
        "Önbellek taraması",
        [ImagePair(front, back, pair_key="book-1-again")],
        storage_mode=StorageMode.REFERENCE,
    )
    before = calls.copy()
    second_run = scheduler.run_job(second.id, worker_id="worker-b")
    assert second_run.job.successful_items == 1
    assert second_run.cache_hits == 10
    assert calls == before
    assert database.fetchone("SELECT COUNT(*) FROM edition")[0] == 1
    assert database.fetchone("SELECT COUNT(*) FROM copy")[0] == 1
    assert database.fetchone("SELECT COUNT(*) FROM field_observation")[0] == observation_count
    assert (
        database.fetchone("SELECT COUNT(*) FROM job_item_engine WHERE status = 'completed'")[0]
        == 20
    )
    assert database.integrity_check() == "ok"


def test_four_surface_book_runs_all_five_engines_on_each_surface(
    tmp_path: Path,
) -> None:
    paths = {
        "front": tmp_path / "book_front.png",
        "front_inside": tmp_path / "book_front_inside.png",
        "back_inside": tmp_path / "book_back_inside.png",
        "back": tmp_path / "book_back.png",
    }
    for index, path in enumerate(paths.values(), 1):
        _cover(path, (index * 30, index * 20, index * 10))
    calls: Counter[str] = Counter()
    scheduler, database, _engines = _scheduler(tmp_path / "runtime", calls)
    job = scheduler.enqueue(
        "Dört yüzlü kitap",
        [
            ImagePair(
                front=paths["front"],
                front_inside=paths["front_inside"],
                back_inside=paths["back_inside"],
                back=paths["back"],
                pair_key="book-four",
            )
        ],
        storage_mode=StorageMode.REFERENCE,
    )

    summary = scheduler.run_job(job.id, worker_id="worker-four")

    assert summary.job.successful_items == 1
    assert calls == Counter({engine_id: 4 for engine_id in REQUIRED_ENGINE_IDS})
    assert database.fetchone("SELECT COUNT(*) FROM job_item_engine")[0] == 20
    assert database.fetchone("SELECT COUNT(*) FROM image_asset")[0] == 4
    book = scheduler.catalog.list_books(limit=1)[0]
    assert book.front_path == str(paths["front"])
    assert book.front_inside_path == str(paths["front_inside"])
    assert book.back_inside_path == str(paths["back_inside"])
    assert book.back_path == str(paths["back"])
    assert book.page_count == 320


def test_scheduler_links_edition_before_persisting_fields(tmp_path: Path) -> None:
    front = tmp_path / "book_front.png"
    back = tmp_path / "book_back.png"
    _cover(front, (90, 20, 20))
    _cover(back, (20, 40, 90))
    scheduler, database, _engines = _scheduler(
        tmp_path / "runtime",
        Counter(),
    )
    job = scheduler.enqueue(
        "Atomik görünürlük",
        [ImagePair(front, back, pair_key="book-link")],
        storage_mode=StorageMode.REFERENCE,
    )
    observed: list[int] = []
    original = scheduler._persist_fields

    def checking_persist_fields(**kwargs: Any) -> None:
        row = database.fetchone(
            "SELECT edition_id, stage FROM job_item WHERE id = ?",
            (kwargs["item_id"],),
        )
        assert row is not None
        assert row["edition_id"] == kwargs["edition_id"]
        assert row["stage"] == JobItemStage.RECONCILED.value
        observed.append(int(row["edition_id"]))
        original(**kwargs)

    scheduler._persist_fields = checking_persist_fields  # type: ignore[method-assign]
    summary = scheduler.run_job(job.id, worker_id="worker-link")
    assert summary.job.successful_items == 1
    assert len(observed) == 1


def test_enqueue_streams_in_250_book_chunks(tmp_path: Path) -> None:
    scheduler, database, _engines = _scheduler(
        tmp_path / "runtime",
        Counter(),
    )
    pairs = (
        ImagePair(
            Path(f"/not-read/front-{index}.png"),
            Path(f"/not-read/back-{index}.png"),
            pair_key=f"pair-{index}",
        )
        for index in range(601)
    )
    job = scheduler.enqueue(
        "601 çift",
        pairs,
        storage_mode=StorageMode.REFERENCE,
        chunk_size=999,  # hard-capped at the durable 250-book chunk size
    )
    assert job.total_items == 601
    assert (
        database.fetchone(
            "SELECT COUNT(*) FROM job_item WHERE job_id = ?",
            (job.id,),
        )[0]
        == 601
    )


def test_run_job_uses_bounded_parallel_book_workers(tmp_path: Path) -> None:
    tracker = ConcurrencyTracker()
    calls: Counter[str] = Counter()
    scheduler, database, _engines = _scheduler(
        tmp_path / "runtime",
        calls,
        tracker=tracker,
    )
    pairs: list[ImagePair] = []
    for index, colors in enumerate(
        (
            ((100, 10, 10), (10, 10, 100)),
            ((10, 100, 10), (100, 100, 10)),
        )
    ):
        front = tmp_path / f"book-{index}_front.png"
        back = tmp_path / f"book-{index}_back.png"
        _cover(front, colors[0])
        _cover(back, colors[1])
        pairs.append(ImagePair(front, back, pair_key=f"parallel-{index}"))
    job = scheduler.enqueue(
        "Paralel iki kitap",
        pairs,
        storage_mode=StorageMode.REFERENCE,
    )

    summary = scheduler.run_job(job.id, worker_id="parallel")

    assert summary.claims == 2
    assert summary.job.successful_items == 2
    assert tracker.maximum >= 2
    assert calls == Counter({engine_id: 4 for engine_id in REQUIRED_ENGINE_IDS})
    assert database.fetchone("SELECT COUNT(*) FROM job_item_engine")[0] == 20


def test_one_engine_exhaustion_fails_closed_without_catalogue_record(
    tmp_path: Path,
) -> None:
    front = tmp_path / "front.png"
    back = tmp_path / "back.png"
    _cover(front, (10, 20, 30))
    _cover(back, (30, 20, 10))
    calls: Counter[str] = Counter()
    scheduler, database, _engines = _scheduler(
        tmp_path / "runtime",
        calls,
        failing_engine="easyocr",
    )
    job = scheduler.enqueue(
        "Hatalı motor",
        [ImagePair(front, back, pair_key="failure")],
        storage_mode=StorageMode.REFERENCE,
    )
    summary = scheduler.run_job(job.id, worker_id="worker-fail")
    item = database.list_job_items(job.id)[0]

    assert summary.job.failed_items == 1
    assert item.stage == JobItemStage.FAILED
    assert "easyocr" in (item.last_error or "")
    assert calls["rapidocr_ppocrv6"] == 1
    assert calls["tesseract"] == 1
    assert calls["easyocr"] == 3  # initial try plus exactly two retries
    assert calls["paddleocr_vl"] == 0
    assert calls["surya"] == 0
    assert database.fetchone("SELECT COUNT(*) FROM edition")[0] == 0
    assert (
        database.fetchone("SELECT COUNT(*) FROM job_item_engine WHERE status = 'completed'")[0] == 2
    )
    assert database.fetchone("SELECT COUNT(*) FROM job_item_engine WHERE status = 'failed'")[0] == 1


@pytest.mark.parametrize("mode", [StorageMode.MANAGED_COPY, StorageMode.REFERENCE])
def test_source_mode_is_persisted(tmp_path: Path, mode: StorageMode) -> None:
    calls: Counter[str] = Counter()
    scheduler, database, _engines = _scheduler(
        tmp_path / mode.value / "runtime",
        calls,
    )
    front = tmp_path / mode.value / "front.png"
    back = tmp_path / mode.value / "back.png"
    front.parent.mkdir(parents=True, exist_ok=True)
    _cover(front, (1, 2, 3))
    _cover(back, (3, 2, 1))
    job = scheduler.enqueue(
        mode.value,
        [ImagePair(front, back, pair_key=mode.value)],
        storage_mode=mode,
    )
    scheduler.run_job(job.id, worker_id=f"worker-{mode.value}")
    rows = database.fetchall("SELECT managed_path FROM image_asset ORDER BY cover_role")
    if mode == StorageMode.MANAGED_COPY:
        assert all(row["managed_path"] for row in rows)
    else:
        assert all(row["managed_path"] is None for row in rows)


def test_import_shelf_reaches_the_catalogued_copy(tmp_path: Path) -> None:
    """Partinin dolabı, öğe dolabı yoksa kitabın nüshasına yazılmalıdır."""

    covers = {}
    for name, color in (
        ("a_front", (10, 20, 30)),
        ("a_back", (30, 20, 10)),
        ("b_front", (60, 90, 120)),
        ("b_back", (120, 90, 60)),
    ):
        covers[name] = tmp_path / f"{name}.png"
        _cover(covers[name], color)
    scheduler, database, _engines = _scheduler(tmp_path / "runtime", Counter())

    job = scheduler.enqueue(
        "Dolap partisi",
        [
            ImagePair(covers["a_front"], covers["a_back"], pair_key="kitap-a"),
            ImagePair(covers["b_front"], covers["b_back"], pair_key="kitap-b"),
        ],
        storage_mode=StorageMode.REFERENCE,
        location="Dolap 1",
        locations={"kitap-b": "Dolap 2"},
    )
    # Tek işçiyle sırayla işlenir: eşzamanlı havuz, yüklü makinede kabul
    # zaman aşımına düşüp testi dolapla ilgisiz biçimde kırabiliyordu.
    while scheduler.run_next("worker-dolap", job_id=job.id) is not None:
        pass
    finished = database.get_import_job(job.id)

    assert finished is not None
    assert finished.successful_items == 2
    assert finished.location == "Dolap 1"
    locations = sorted(
        row["location"] for row in database.fetchall("SELECT location FROM copy")
    )
    assert locations == ["Dolap 1", "Dolap 2"]
