"""SQLite persistence and the durable import-job state machine."""

from __future__ import annotations

import json
import math
import os
import sqlite3
import stat

from kitapkatalog import portable
import unicodedata
import uuid
from collections import Counter
from collections.abc import Iterable, Iterator, Mapping, Sequence
from contextlib import contextmanager
from contextvars import ContextVar
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any

from kitapkatalog.domain import (
    ALLOWED_STAGE_TRANSITIONS,
    ALLOWED_VOICE_STAGE_TRANSITIONS,
    REQUIRED_OCR_ENGINES,
    CoverRole,
    ImagePair,
    ImportJob,
    ImportJobStatus,
    JobItem,
    JobItemStage,
    OcrEngine,
    PersistedConsensusSpan,
    RunStatus,
    StorageMode,
    VoiceAlias,
    VoiceItem,
    VoiceItemStage,
    VoiceJob,
    VoiceJobPhase,
)

SCHEMA_VERSION = 12
_APPLICATION_ID = 0x4B4B4154  # "KKAT"
_TERMINAL_ITEM_STAGES = (
    JobItemStage.REVIEW.value,
    JobItemStage.COMPLETED.value,
    JobItemStage.FAILED.value,
    JobItemStage.CANCELLED.value,
)
_TERMINAL_VOICE_STAGES = (
    VoiceItemStage.REVIEW.value,
    VoiceItemStage.COMPLETED.value,
    VoiceItemStage.FAILED.value,
    VoiceItemStage.CANCELLED.value,
)


def _clean_location(value: str | None) -> str | None:
    """Dolap adını `copy.location` ile birebir eşleşecek biçimde sadeleştirir."""

    cleaned = str(value or "").strip()
    return cleaned[:120] or None


def _terminal_count_vector(stage: str) -> tuple[int, int, int]:
    """Return (successful, failed, review) contribution for one item stage."""

    return (
        int(stage == JobItemStage.COMPLETED.value),
        int(stage in {JobItemStage.FAILED.value, JobItemStage.CANCELLED.value}),
        int(stage == JobItemStage.REVIEW.value),
    )


class DatabaseError(RuntimeError):
    """Base error for persistence failures."""


class StateConflictError(DatabaseError):
    """Raised when a worker tries an invalid or stale state transition."""


class LeaseLostError(StateConflictError):
    """Raised when a worker no longer owns a claimed item."""


class Database:
    """Small connection factory around a versioned SQLite database.

    Connections are intentionally short-lived.  WAL plus ``busy_timeout``
    permits the UI to read while worker processes commit OCR checkpoints.
    """

    def __init__(self, path: str | Path, *, busy_timeout_ms: int = 10_000) -> None:
        self.path = Path(path) if str(path) != ":memory:" else Path(":memory:")
        self.busy_timeout_ms = int(busy_timeout_ms)
        # Composite service operations (web form + ISBN + authors + copies)
        # can open nested Catalog transactions. A context-local connection
        # turns those calls into savepoints of one outer unit-of-work without
        # sharing SQLite connections between request threads/tasks.
        self._transaction_connection: ContextVar[sqlite3.Connection | None] = ContextVar(
            f"kitapkatalog_transaction_{id(self)}", default=None
        )
        self._keeper: sqlite3.Connection | None = None
        if str(path) == ":memory:":
            self._dsn = f"file:kitapkatalog-{uuid.uuid4().hex}?mode=memory&cache=shared"
            self._uri = True
            self._keeper = self._new_connection()
        else:
            self.path.parent.mkdir(parents=True, exist_ok=True)
            self._prepare_private_database_file()
            self._dsn = str(self.path)
            self._uri = False
        self.migrate()

    @staticmethod
    def _verify_private_regular_file(path: Path) -> None:
        """Require an owned regular SQLite file with mode exactly ``0600``.

        SQLite can create the main database and WAL sidecars under the process
        umask. A common ``022`` umask would otherwise leave catalogue and
        circulation data group/world-readable. Refuse symlinks or files owned
        by another user, chmod the file, then verify the resulting mode instead
        of treating permission hardening as best effort.
        """

        try:
            metadata = path.lstat()
        except FileNotFoundError:
            return
        if not portable.kullanici_sahibi_mi(metadata):
            raise DatabaseError(f"Güvenli olmayan veritabanı dosyası: {path}")
        try:
            portable.sikilastir_0600(path)
            secured = path.lstat()
        except OSError as exc:
            raise DatabaseError(f"Veritabanı dosya izni 0600 yapılamadı: {path}") from exc
        if not portable.izin_0600_mu(secured):
            raise DatabaseError(f"Veritabanı dosya izni doğrulanamadı (0600 gerekli): {path}")

    def _prepare_private_database_file(self) -> None:
        """Pre-create a new DB as 0600 and secure any existing sidecars."""

        try:
            descriptor = os.open(
                self.path,
                os.O_RDWR | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0),
                0o600,
            )
        except FileExistsError:
            pass
        except OSError as exc:
            raise DatabaseError(f"Veritabanı dosyası güvenli oluşturulamadı: {self.path}") from exc
        else:
            os.close(descriptor)
        self._secure_storage_files()

    def _secure_storage_files(self) -> None:
        if self.path == Path(":memory:"):
            return
        for candidate in (
            self.path,
            Path(f"{self.path}-wal"),
            Path(f"{self.path}-shm"),
        ):
            self._verify_private_regular_file(candidate)

    def close(self) -> None:
        if self._keeper is not None:
            self._keeper.close()
            self._keeper = None

    def __enter__(self) -> Database:
        return self

    def __exit__(self, *_: object) -> None:
        self.close()

    def _new_connection(self, *, readonly: bool = False) -> sqlite3.Connection:
        if not self._uri:
            self._secure_storage_files()
        if readonly and not self._uri:
            dsn = f"file:{self.path}?mode=ro"
            uri = True
        else:
            dsn = self._dsn
            uri = self._uri
        connection = sqlite3.connect(
            dsn,
            timeout=self.busy_timeout_ms / 1000,
            isolation_level=None,
            check_same_thread=False,
            uri=uri,
        )
        connection.row_factory = sqlite3.Row
        connection.create_collation("UNICODE_NOCASE", _unicode_nocase)
        connection.execute("PRAGMA foreign_keys = ON")
        connection.execute(f"PRAGMA busy_timeout = {self.busy_timeout_ms}")
        connection.execute("PRAGMA temp_store = MEMORY")
        if not readonly:
            connection.execute("PRAGMA journal_mode = WAL")
            connection.execute("PRAGMA synchronous = NORMAL")
            connection.execute("PRAGMA wal_autocheckpoint = 1000")
        if not self._uri:
            try:
                self._secure_storage_files()
            except BaseException:
                connection.close()
                raise
        return connection

    @contextmanager
    def connection(self, *, readonly: bool = False) -> Iterator[sqlite3.Connection]:
        active = self._transaction_connection.get()
        if active is not None:
            # Reads inside a unit-of-work must see its uncommitted changes.
            yield active
            return
        connection = self._new_connection(readonly=readonly)
        try:
            yield connection
        finally:
            try:
                if not self._uri:
                    # WAL/SHM yan dosyaları ilk yazma veya okuma sırasında
                    # bağlantı açıldıktan sonra oluşabilir. Kapanmadan hemen
                    # önce onları da kesin olarak 0600'e getirip doğrula.
                    self._secure_storage_files()
            finally:
                connection.close()

    # Friendly alias for exporters.
    read_connection = connection

    @contextmanager
    def transaction(self, *, immediate: bool = False) -> Iterator[sqlite3.Connection]:
        active = self._transaction_connection.get()
        if active is not None:
            savepoint = f"nested_{uuid.uuid4().hex}"
            active.execute(f"SAVEPOINT {savepoint}")
            try:
                yield active
            except BaseException:
                active.execute(f"ROLLBACK TO SAVEPOINT {savepoint}")
                active.execute(f"RELEASE SAVEPOINT {savepoint}")
                raise
            else:
                active.execute(f"RELEASE SAVEPOINT {savepoint}")
            return
        with self.connection() as connection:
            token = self._transaction_connection.set(connection)
            try:
                connection.execute("BEGIN IMMEDIATE" if immediate else "BEGIN")
                try:
                    yield connection
                except BaseException:
                    connection.rollback()
                    raise
                else:
                    connection.commit()
            finally:
                self._transaction_connection.reset(token)

    def fetchone(
        self, sql: str, parameters: Iterable[Any] | Mapping[str, Any] = ()
    ) -> sqlite3.Row | None:
        with self.connection(readonly=True) as connection:
            return connection.execute(sql, parameters).fetchone()

    def fetchall(
        self, sql: str, parameters: Iterable[Any] | Mapping[str, Any] = ()
    ) -> list[sqlite3.Row]:
        with self.connection(readonly=True) as connection:
            return list(connection.execute(sql, parameters).fetchall())

    def migrate(self) -> None:
        with self.connection() as connection:
            version = int(connection.execute("PRAGMA user_version").fetchone()[0])
            if version > SCHEMA_VERSION:
                raise DatabaseError(
                    f"Veritabanı sürümü {version}; uygulamanın desteklediği en yeni sürüm "
                    f"{SCHEMA_VERSION}"
                )
            if version == 0:
                self._migrate_v1(connection)
                version = 1
            if version == 1:
                self._migrate_v2(connection)
                version = 2
            if version == 2:
                self._migrate_v3(connection)
                version = 3
            if version == 3:
                self._migrate_v4(connection)
                version = 4
            if version == 4:
                self._migrate_v5(connection)
                version = 5
            if version == 5:
                self._migrate_v6(connection)
                version = 6
            if version == 6:
                self._migrate_v7(connection)
                version = 7
            if version == 7:
                self._migrate_v8(connection)
                version = 8
            if version == 8:
                self._migrate_v9(connection)
                version = 9
            if version == 9:
                self._migrate_v10(connection)
                version = 10
            if version == 10:
                self._migrate_v11(connection)
                version = 11
            if version == 11:
                self._migrate_v12(connection)
                version = 12
            if version != SCHEMA_VERSION:
                raise DatabaseError(f"Eksik veritabanı geçişi: {version}")
            # SQLite'ın önerdiği hafif bakım çağrısı transaction dışında çalışır.
            # Genellikle no-op'tur; yeni indekslerden sonra planner istatistiklerini
            # gerektiğinde günceller ve sonraki açılışlarda kendi kendini sınırlar.
            connection.execute("PRAGMA optimize")

    @staticmethod
    def _migrate_v1(connection: sqlite3.Connection) -> None:
        # executescript supplies one atomic transaction and is safe on a new DB.
        connection.executescript(
            f"""
            BEGIN IMMEDIATE;
            PRAGMA application_id = {_APPLICATION_ID};

            CREATE TABLE IF NOT EXISTS schema_migration (
                version INTEGER PRIMARY KEY,
                applied_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS work (
                id INTEGER PRIMARY KEY,
                canonical_title TEXT NOT NULL DEFAULT 'bilinmiyor',
                original_title TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS edition (
                id INTEGER PRIMARY KEY,
                work_id INTEGER NOT NULL REFERENCES work(id) ON DELETE CASCADE,
                title TEXT NOT NULL DEFAULT 'bilinmiyor',
                subtitle TEXT,
                original_title TEXT,
                publisher TEXT,
                imprint TEXT,
                series TEXT,
                volume TEXT,
                language TEXT,
                publication_place TEXT,
                publication_date TEXT,
                edition_statement TEXT,
                printing_number TEXT,
                printer TEXT,
                binding TEXT,
                page_count INTEGER CHECK(page_count IS NULL OR page_count >= 0),
                dimensions TEXT,
                price_amount TEXT,
                currency TEXT,
                blurb TEXT,
                awards TEXT,
                quotations TEXT,
                review_status TEXT NOT NULL DEFAULT 'review',
                source_fingerprint TEXT UNIQUE,
                front_path TEXT,
                back_path TEXT,
                raw_ocr_text TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS copy (
                id INTEGER PRIMARY KEY,
                edition_id INTEGER NOT NULL REFERENCES edition(id) ON DELETE CASCADE,
                inventory_code TEXT UNIQUE,
                source_fingerprint TEXT UNIQUE,
                location TEXT,
                notes TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS contributor (
                id INTEGER PRIMARY KEY,
                display_name TEXT NOT NULL,
                normalized_name TEXT NOT NULL UNIQUE
            );

            CREATE TABLE IF NOT EXISTS edition_contributor (
                edition_id INTEGER NOT NULL REFERENCES edition(id) ON DELETE CASCADE,
                contributor_id INTEGER NOT NULL REFERENCES contributor(id) ON DELETE RESTRICT,
                role TEXT NOT NULL,
                sort_order INTEGER NOT NULL DEFAULT 0,
                PRIMARY KEY (edition_id, contributor_id, role)
            );

            CREATE TABLE IF NOT EXISTS identifier (
                id INTEGER PRIMARY KEY,
                edition_id INTEGER NOT NULL REFERENCES edition(id) ON DELETE CASCADE,
                scheme TEXT NOT NULL,
                value TEXT NOT NULL,
                normalized_value TEXT NOT NULL,
                source TEXT NOT NULL DEFAULT 'cover',
                confidence REAL CHECK(
                    confidence IS NULL OR (confidence >= 0.0 AND confidence <= 1.0)
                ),
                created_at TEXT NOT NULL,
                UNIQUE (scheme, normalized_value)
            );

            CREATE TABLE IF NOT EXISTS import_job (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                status TEXT NOT NULL,
                storage_mode TEXT NOT NULL,
                total_items INTEGER NOT NULL DEFAULT 0,
                successful_items INTEGER NOT NULL DEFAULT 0,
                failed_items INTEGER NOT NULL DEFAULT 0,
                review_items INTEGER NOT NULL DEFAULT 0,
                idempotency_key TEXT UNIQUE,
                config_hash TEXT NOT NULL DEFAULT '',
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                started_at TEXT,
                finished_at TEXT
            );

            CREATE TABLE IF NOT EXISTS job_item (
                id INTEGER PRIMARY KEY,
                job_id TEXT NOT NULL REFERENCES import_job(id) ON DELETE CASCADE,
                pair_key TEXT NOT NULL,
                front_path TEXT NOT NULL,
                back_path TEXT NOT NULL,
                pairing_confidence REAL NOT NULL,
                pairing_basis TEXT NOT NULL,
                needs_pair_review INTEGER NOT NULL DEFAULT 0,
                stage TEXT NOT NULL,
                retry_count INTEGER NOT NULL DEFAULT 0,
                lease_owner TEXT,
                lease_until TEXT,
                heartbeat_at TEXT,
                not_before TEXT,
                last_error TEXT,
                edition_id INTEGER REFERENCES edition(id) ON DELETE SET NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                UNIQUE (job_id, pair_key)
            );

            CREATE TABLE IF NOT EXISTS image_asset (
                id INTEGER PRIMARY KEY,
                item_id INTEGER NOT NULL REFERENCES job_item(id) ON DELETE CASCADE,
                edition_id INTEGER REFERENCES edition(id) ON DELETE SET NULL,
                cover_role TEXT NOT NULL,
                source_path TEXT NOT NULL,
                managed_path TEXT,
                source_sha256 TEXT,
                crop_sha256 TEXT,
                mime_type TEXT,
                width INTEGER,
                height INTEGER,
                preprocessing_version TEXT NOT NULL DEFAULT '',
                homography_json TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                UNIQUE (item_id, cover_role)
            );

            CREATE TABLE IF NOT EXISTS job_item_engine (
                item_id INTEGER NOT NULL REFERENCES job_item(id) ON DELETE CASCADE,
                cover_role TEXT NOT NULL,
                engine_name TEXT NOT NULL,
                status TEXT NOT NULL DEFAULT 'pending',
                attempt_count INTEGER NOT NULL DEFAULT 0,
                cache_key TEXT,
                raw_result_path TEXT,
                text TEXT,
                error TEXT,
                duration_ms INTEGER,
                updated_at TEXT NOT NULL,
                PRIMARY KEY (item_id, cover_role, engine_name)
            );

            CREATE TABLE IF NOT EXISTS ocr_engine_run (
                id INTEGER PRIMARY KEY,
                image_asset_id INTEGER NOT NULL REFERENCES image_asset(id) ON DELETE CASCADE,
                engine_name TEXT NOT NULL,
                model_digest TEXT NOT NULL,
                config_hash TEXT NOT NULL,
                preprocessing_version TEXT NOT NULL,
                cache_key TEXT NOT NULL,
                status TEXT NOT NULL,
                attempt_count INTEGER NOT NULL DEFAULT 0,
                raw_result_path TEXT,
                raw_text TEXT,
                normalized_text TEXT,
                error TEXT,
                duration_ms INTEGER,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                UNIQUE (
                    image_asset_id, engine_name, model_digest, config_hash,
                    preprocessing_version
                )
            );

            CREATE TABLE IF NOT EXISTS consensus_span (
                id INTEGER PRIMARY KEY,
                image_asset_id INTEGER NOT NULL REFERENCES image_asset(id) ON DELETE CASCADE,
                span_index INTEGER NOT NULL,
                text TEXT NOT NULL,
                normalized_text TEXT NOT NULL,
                polygon_json TEXT,
                confidence REAL NOT NULL,
                source_refs_json TEXT NOT NULL,
                engine_support_json TEXT NOT NULL,
                UNIQUE (image_asset_id, span_index)
            );

            CREATE TABLE IF NOT EXISTS field_observation (
                id INTEGER PRIMARY KEY,
                edition_id INTEGER REFERENCES edition(id) ON DELETE CASCADE,
                item_id INTEGER REFERENCES job_item(id) ON DELETE CASCADE,
                field_path TEXT NOT NULL,
                raw_value TEXT NOT NULL,
                normalized_value TEXT NOT NULL,
                cover_role TEXT,
                polygon_json TEXT,
                engine_evidence_json TEXT NOT NULL DEFAULT '[]',
                source_token_ids_json TEXT NOT NULL DEFAULT '[]',
                confidence REAL NOT NULL,
                created_at TEXT NOT NULL,
                CHECK(edition_id IS NOT NULL OR item_id IS NOT NULL)
            );

            CREATE TABLE IF NOT EXISTS resolved_field (
                id INTEGER PRIMARY KEY,
                edition_id INTEGER NOT NULL REFERENCES edition(id) ON DELETE CASCADE,
                field_path TEXT NOT NULL,
                observation_id INTEGER REFERENCES field_observation(id) ON DELETE SET NULL,
                value TEXT NOT NULL,
                status TEXT NOT NULL,
                user_locked INTEGER NOT NULL DEFAULT 0,
                resolver_version TEXT NOT NULL DEFAULT '',
                updated_at TEXT NOT NULL,
                UNIQUE (edition_id, field_path)
            );

            CREATE TABLE IF NOT EXISTS edition_search_document (
                edition_id INTEGER PRIMARY KEY REFERENCES edition(id) ON DELETE CASCADE,
                title TEXT NOT NULL DEFAULT '',
                subtitle TEXT NOT NULL DEFAULT '',
                original_title TEXT NOT NULL DEFAULT '',
                contributors TEXT NOT NULL DEFAULT '',
                publisher TEXT NOT NULL DEFAULT '',
                identifiers TEXT NOT NULL DEFAULT '',
                blurb TEXT NOT NULL DEFAULT '',
                raw_ocr TEXT NOT NULL DEFAULT ''
            );

            CREATE VIRTUAL TABLE IF NOT EXISTS edition_fts USING fts5(
                title,
                subtitle,
                original_title,
                contributors,
                publisher,
                identifiers,
                blurb,
                raw_ocr,
                content='edition_search_document',
                content_rowid='edition_id',
                tokenize='unicode61 remove_diacritics 0'
            );

            CREATE TRIGGER IF NOT EXISTS edition_search_ai
            AFTER INSERT ON edition_search_document BEGIN
                INSERT INTO edition_fts(
                    rowid, title, subtitle, original_title, contributors,
                    publisher, identifiers, blurb, raw_ocr
                ) VALUES (
                    new.edition_id, new.title, new.subtitle, new.original_title,
                    new.contributors, new.publisher, new.identifiers, new.blurb,
                    new.raw_ocr
                );
            END;

            CREATE TRIGGER IF NOT EXISTS edition_search_ad
            AFTER DELETE ON edition_search_document BEGIN
                INSERT INTO edition_fts(
                    edition_fts, rowid, title, subtitle, original_title,
                    contributors, publisher, identifiers, blurb, raw_ocr
                ) VALUES (
                    'delete', old.edition_id, old.title, old.subtitle,
                    old.original_title, old.contributors, old.publisher,
                    old.identifiers, old.blurb, old.raw_ocr
                );
            END;

            CREATE TRIGGER IF NOT EXISTS edition_search_au
            AFTER UPDATE ON edition_search_document BEGIN
                INSERT INTO edition_fts(
                    edition_fts, rowid, title, subtitle, original_title,
                    contributors, publisher, identifiers, blurb, raw_ocr
                ) VALUES (
                    'delete', old.edition_id, old.title, old.subtitle,
                    old.original_title, old.contributors, old.publisher,
                    old.identifiers, old.blurb, old.raw_ocr
                );
                INSERT INTO edition_fts(
                    rowid, title, subtitle, original_title, contributors,
                    publisher, identifiers, blurb, raw_ocr
                ) VALUES (
                    new.edition_id, new.title, new.subtitle, new.original_title,
                    new.contributors, new.publisher, new.identifiers, new.blurb,
                    new.raw_ocr
                );
            END;

            CREATE INDEX IF NOT EXISTS idx_edition_work ON edition(work_id);
            CREATE INDEX IF NOT EXISTS idx_edition_publisher ON edition(publisher);
            CREATE INDEX IF NOT EXISTS idx_edition_review ON edition(review_status);
            CREATE INDEX IF NOT EXISTS idx_copy_edition ON copy(edition_id);
            CREATE INDEX IF NOT EXISTS idx_identifier_edition ON identifier(edition_id);
            CREATE INDEX IF NOT EXISTS idx_identifier_normalized
                ON identifier(normalized_value);
            CREATE INDEX IF NOT EXISTS idx_job_status ON import_job(status, created_at);
            CREATE INDEX IF NOT EXISTS idx_job_item_claim ON job_item(
                stage, needs_pair_review, lease_until, not_before, id
            );
            CREATE INDEX IF NOT EXISTS idx_job_item_job_stage
                ON job_item(job_id, stage);
            CREATE INDEX IF NOT EXISTS idx_engine_status
                ON job_item_engine(item_id, status);
            CREATE INDEX IF NOT EXISTS idx_ocr_cache_key
                ON ocr_engine_run(cache_key);
            CREATE INDEX IF NOT EXISTS idx_observation_edition ON field_observation(
                edition_id, field_path
            );

            INSERT OR IGNORE INTO schema_migration(version, applied_at)
            VALUES (1, '{_now_text()}');
            PRAGMA user_version = 1;
            COMMIT;
            """
        )

    @staticmethod
    def _migrate_v2(connection: sqlite3.Connection) -> None:
        """Persist canonical and original-photo polygons independently."""

        connection.executescript(
            """
            BEGIN IMMEDIATE;
            ALTER TABLE consensus_span ADD COLUMN source_polygon_json TEXT;
            ALTER TABLE field_observation ADD COLUMN source_polygon_json TEXT;
            INSERT OR IGNORE INTO schema_migration(version, applied_at)
            VALUES (2, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'));
            PRAGMA user_version = 2;
            COMMIT;
            """
        )

    @staticmethod
    def _migrate_v3(connection: sqlite3.Connection) -> None:
        """Add the two inner-cover document roles without invalidating old jobs."""

        connection.executescript(
            """
            BEGIN IMMEDIATE;
            ALTER TABLE job_item ADD COLUMN front_inside_path TEXT;
            ALTER TABLE job_item ADD COLUMN back_inside_path TEXT;
            ALTER TABLE edition ADD COLUMN front_inside_path TEXT;
            ALTER TABLE edition ADD COLUMN back_inside_path TEXT;
            INSERT OR IGNORE INTO schema_migration(version, applied_at)
            VALUES (3, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'));
            PRAGMA user_version = 3;
            COMMIT;
            """
        )

    @staticmethod
    def _migrate_v4(connection: sqlite3.Connection) -> None:
        """Add the edition category column and the voice-capture queue tables."""

        connection.executescript(
            """
            BEGIN IMMEDIATE;
            ALTER TABLE edition ADD COLUMN category TEXT;

            CREATE TABLE IF NOT EXISTS voice_job (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                status TEXT NOT NULL,
                phase TEXT NOT NULL DEFAULT 'ingested',
                source_audio_path TEXT NOT NULL,
                source_sha256 TEXT,
                canonical_wav_path TEXT,
                segmentation_version INTEGER NOT NULL DEFAULT 1,
                single_book INTEGER NOT NULL DEFAULT 0,
                total_items INTEGER NOT NULL DEFAULT 0,
                successful_items INTEGER NOT NULL DEFAULT 0,
                failed_items INTEGER NOT NULL DEFAULT 0,
                review_items INTEGER NOT NULL DEFAULT 0,
                idempotency_key TEXT UNIQUE,
                config_hash TEXT NOT NULL DEFAULT '',
                lease_owner TEXT,
                lease_until TEXT,
                heartbeat_at TEXT,
                last_error TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                started_at TEXT,
                finished_at TEXT
            );

            CREATE TABLE IF NOT EXISTS voice_transcript_chunk (
                job_id TEXT NOT NULL REFERENCES voice_job(id) ON DELETE CASCADE,
                chunk_index INTEGER NOT NULL,
                start_sample INTEGER NOT NULL,
                end_sample INTEGER NOT NULL,
                segments_json TEXT NOT NULL,
                model_id TEXT NOT NULL DEFAULT '',
                created_at TEXT NOT NULL,
                PRIMARY KEY (job_id, chunk_index)
            );

            CREATE TABLE IF NOT EXISTS voice_item (
                id INTEGER PRIMARY KEY,
                job_id TEXT NOT NULL REFERENCES voice_job(id) ON DELETE CASCADE,
                item_key TEXT NOT NULL,
                ordinal INTEGER NOT NULL,
                start_sample INTEGER NOT NULL,
                end_sample INTEGER NOT NULL,
                transcript_json TEXT NOT NULL,
                claims_json TEXT,
                stage TEXT NOT NULL,
                retry_count INTEGER NOT NULL DEFAULT 0,
                lease_owner TEXT,
                lease_until TEXT,
                heartbeat_at TEXT,
                not_before TEXT,
                last_error TEXT,
                edition_id INTEGER REFERENCES edition(id) ON DELETE SET NULL,
                review_reasons_json TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                UNIQUE (job_id, item_key)
            );

            CREATE INDEX IF NOT EXISTS idx_voice_job_status
                ON voice_job(status, created_at);
            CREATE INDEX IF NOT EXISTS idx_voice_item_claim ON voice_item(
                stage, lease_until, not_before, id
            );
            CREATE INDEX IF NOT EXISTS idx_voice_item_job_stage
                ON voice_item(job_id, stage);

            INSERT OR IGNORE INTO schema_migration(version, applied_at)
            VALUES (4, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'));
            PRAGMA user_version = 4;
            COMMIT;
            """
        )

    @staticmethod
    def _migrate_v5(connection: sqlite3.Connection) -> None:
        """Kütüphane otomasyonu: üyeler, ödünç, sayım, düşüm, ayarlar."""

        connection.executescript(
            """
            BEGIN IMMEDIATE;

            CREATE TABLE IF NOT EXISTS app_setting (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS inventory_sequence (
                year INTEGER PRIMARY KEY,
                next_value INTEGER NOT NULL
            );

            CREATE TABLE IF NOT EXISTS member (
                id INTEGER PRIMARY KEY,
                member_type TEXT NOT NULL DEFAULT 'student'
                    CHECK (member_type IN ('student', 'staff')),
                school_number TEXT,
                first_name TEXT NOT NULL,
                last_name TEXT NOT NULL,
                class_name TEXT,
                is_active INTEGER NOT NULL DEFAULT 1,
                notes TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );
            CREATE UNIQUE INDEX IF NOT EXISTS idx_member_school_number
                ON member(school_number) WHERE school_number IS NOT NULL;
            CREATE INDEX IF NOT EXISTS idx_member_class
                ON member(class_name, last_name);

            CREATE TABLE IF NOT EXISTS loan (
                id INTEGER PRIMARY KEY,
                copy_id INTEGER REFERENCES copy(id) ON DELETE SET NULL,
                member_id INTEGER NOT NULL REFERENCES member(id) ON DELETE RESTRICT,
                edition_id INTEGER REFERENCES edition(id) ON DELETE SET NULL,
                title_snapshot TEXT NOT NULL,
                inventory_code_snapshot TEXT,
                loaned_at TEXT NOT NULL,
                due_at TEXT NOT NULL,
                returned_at TEXT,
                renewal_count INTEGER NOT NULL DEFAULT 0,
                notes TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );
            CREATE UNIQUE INDEX IF NOT EXISTS idx_loan_active_copy
                ON loan(copy_id) WHERE returned_at IS NULL;
            CREATE INDEX IF NOT EXISTS idx_loan_member
                ON loan(member_id, loaned_at);
            CREATE INDEX IF NOT EXISTS idx_loan_due
                ON loan(due_at) WHERE returned_at IS NULL;
            CREATE INDEX IF NOT EXISTS idx_loan_edition_active
                ON loan(edition_id) WHERE returned_at IS NULL;

            ALTER TABLE copy ADD COLUMN status TEXT NOT NULL DEFAULT 'active'
                CHECK (status IN ('active', 'discarded'));

            CREATE TRIGGER IF NOT EXISTS copy_no_delete_when_loaned
            BEFORE DELETE ON copy
            WHEN EXISTS (
                SELECT 1 FROM loan
                WHERE copy_id = OLD.id AND returned_at IS NULL
            )
            BEGIN
                SELECT RAISE(ABORT, 'Nüsha aktif ödünçte; önce iade alın');
            END;

            CREATE TABLE IF NOT EXISTS stocktake_session (
                id INTEGER PRIMARY KEY,
                name TEXT NOT NULL,
                scope_location TEXT,
                status TEXT NOT NULL DEFAULT 'open'
                    CHECK (status IN ('open', 'closed')),
                started_at TEXT NOT NULL,
                closed_at TEXT,
                notes TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS discard_record (
                id INTEGER PRIMARY KEY,
                copy_id INTEGER REFERENCES copy(id) ON DELETE SET NULL,
                edition_id INTEGER REFERENCES edition(id) ON DELETE SET NULL,
                title_snapshot TEXT NOT NULL,
                inventory_code_snapshot TEXT,
                reason TEXT NOT NULL
                    CHECK (reason IN ('yipranma', 'kayip', 'guncelligini_yitirme', 'diger')),
                note TEXT,
                stocktake_session_id INTEGER
                    REFERENCES stocktake_session(id) ON DELETE SET NULL,
                discarded_at TEXT NOT NULL,
                created_at TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_discard_copy ON discard_record(copy_id);

            CREATE TABLE IF NOT EXISTS stocktake_scan (
                id INTEGER PRIMARY KEY,
                session_id INTEGER NOT NULL
                    REFERENCES stocktake_session(id) ON DELETE CASCADE,
                raw_code TEXT NOT NULL,
                code_type TEXT NOT NULL
                    CHECK (code_type IN ('isbn', 'inventory', 'manual', 'unresolved')),
                edition_id INTEGER REFERENCES edition(id) ON DELETE SET NULL,
                copy_id INTEGER REFERENCES copy(id) ON DELETE SET NULL,
                created_at TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_scan_session_edition
                ON stocktake_scan(session_id, edition_id);

            INSERT OR IGNORE INTO schema_migration(version, applied_at)
            VALUES (5, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'));
            PRAGMA user_version = 5;
            COMMIT;
            """
        )

    @staticmethod
    def _migrate_v6(connection: sqlite3.Connection) -> None:
        """Raf haritası: dolap kayıtları + konum/popülerlik indeksleri."""

        connection.executescript(
            """
            BEGIN IMMEDIATE;

            CREATE TABLE IF NOT EXISTS shelf (
                id INTEGER PRIMARY KEY,
                name TEXT NOT NULL UNIQUE
                    CHECK (name = trim(name) AND name <> ''),
                grid_row INTEGER CHECK (grid_row IS NULL OR grid_row >= 0),
                grid_col INTEGER CHECK (grid_col IS NULL OR grid_col >= 0),
                capacity INTEGER CHECK (capacity IS NULL OR capacity > 0),
                color TEXT,
                notes TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                CHECK ((grid_row IS NULL) = (grid_col IS NULL))
            );
            CREATE UNIQUE INDEX IF NOT EXISTS idx_shelf_cell
                ON shelf(grid_row, grid_col)
                WHERE grid_row IS NOT NULL AND grid_col IS NOT NULL;

            CREATE INDEX IF NOT EXISTS idx_copy_location ON copy(location);
            CREATE INDEX IF NOT EXISTS idx_loan_edition
                ON loan(edition_id, loaned_at);

            INSERT OR IGNORE INTO schema_migration(version, applied_at)
            VALUES (6, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'));
            PRAGMA user_version = 6;
            COMMIT;
            """
        )

    @staticmethod
    def _migrate_v7(connection: sqlite3.Connection) -> None:
        """Arama/rapor indeksleri ve delta sayaçları için güvenli başlangıç."""

        connection.executescript(
            """
            BEGIN IMMEDIATE;

            CREATE INDEX IF NOT EXISTS idx_edition_title_nocase
                ON edition(title COLLATE NOCASE, id);
            CREATE INDEX IF NOT EXISTS idx_edition_created_id
                ON edition(created_at DESC, id);
            CREATE INDEX IF NOT EXISTS idx_edition_publisher_unicode_title
                ON edition(
                    publisher COLLATE UNICODE_NOCASE,
                    title COLLATE NOCASE,
                    id
                );
            CREATE INDEX IF NOT EXISTS idx_edition_language_unicode_title
                ON edition(
                    language COLLATE UNICODE_NOCASE,
                    title COLLATE NOCASE,
                    id
                );
            CREATE INDEX IF NOT EXISTS idx_edition_category_unicode_title
                ON edition(
                    category COLLATE UNICODE_NOCASE,
                    title COLLATE NOCASE,
                    id
                );
            CREATE INDEX IF NOT EXISTS idx_edition_review_title
                ON edition(review_status, title COLLATE NOCASE, id);
            CREATE INDEX IF NOT EXISTS idx_edition_publication_year
                ON edition(CAST(substr(publication_date, 1, 4) AS INTEGER))
                WHERE publication_date GLOB '[0-9][0-9][0-9][0-9]*';
            CREATE INDEX IF NOT EXISTS idx_copy_edition_status_location
                ON copy(edition_id, status, location);
            CREATE INDEX IF NOT EXISTS idx_job_item_pair_review
                ON job_item(needs_pair_review, created_at, id);
            CREATE INDEX IF NOT EXISTS idx_loan_loaned_at
                ON loan(loaned_at);
            CREATE INDEX IF NOT EXISTS idx_loan_returned_at
                ON loan(returned_at) WHERE returned_at IS NOT NULL;

            -- v6 ve öncesinde iptal/yeniden-deneme yolları sayaçları toplu
            -- taramayla güncelliyordu. Delta düzenine geçmeden önce mevcut
            -- veriyi bir kez gerçek öğe aşamalarından uzlaştır.
            UPDATE import_job
            SET total_items = (
                    SELECT COUNT(*) FROM job_item WHERE job_id = import_job.id
                ),
                successful_items = (
                    SELECT COUNT(*) FROM job_item
                    WHERE job_id = import_job.id AND stage = 'completed'
                ),
                failed_items = (
                    SELECT COUNT(*) FROM job_item
                    WHERE job_id = import_job.id AND stage IN ('failed', 'cancelled')
                ),
                review_items = (
                    SELECT COUNT(*) FROM job_item
                    WHERE job_id = import_job.id AND stage = 'review'
                );

            UPDATE voice_job
            SET total_items = (
                    SELECT COUNT(*) FROM voice_item WHERE job_id = voice_job.id
                ),
                successful_items = (
                    SELECT COUNT(*) FROM voice_item
                    WHERE job_id = voice_job.id AND stage = 'completed'
                ),
                failed_items = (
                    SELECT COUNT(*) FROM voice_item
                    WHERE job_id = voice_job.id AND stage IN ('failed', 'cancelled')
                ),
                review_items = (
                    SELECT COUNT(*) FROM voice_item
                    WHERE job_id = voice_job.id AND stage = 'review'
                );

            INSERT OR IGNORE INTO schema_migration(version, applied_at)
            VALUES (7, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'));
            PRAGMA user_version = 7;
            COMMIT;
            """
        )

    @staticmethod
    def _migrate_v8(connection: sqlite3.Connection) -> None:
        """Immutable circulation snapshots and an append-only event ledger."""

        existing_columns = {
            str(row[1]) for row in connection.execute("PRAGMA table_info(loan)")
        }
        column_definitions = (
            ("member_name_snapshot", "TEXT"),
            ("member_number_snapshot", "TEXT"),
            ("member_class_snapshot", "TEXT"),
            ("member_type_snapshot", "TEXT"),
            ("academic_period_snapshot", "TEXT"),
            (
                "snapshot_source",
                "TEXT NOT NULL DEFAULT 'migration-estimate'",
            ),
        )
        # SQLite has no portable ``ADD COLUMN IF NOT EXISTS``. Build only the
        # missing fixed DDL so a previously interrupted/manual version reset
        # can safely re-enter v8 without duplicate-column failures.
        add_columns = "\n".join(
            f"ALTER TABLE loan ADD COLUMN {name} {definition};"
            for name, definition in column_definitions
            if name not in existing_columns
        )
        connection.executescript(
            f"""
            BEGIN IMMEDIATE;

            {add_columns}

            -- Earlier schemas joined live member fields at read time. Preserve
            -- the best available value while explicitly marking that it is an
            -- estimate, not a claim about the member's historical class.
            UPDATE loan
            SET member_name_snapshot = COALESCE(
                    (SELECT trim(m.first_name || ' ' || m.last_name)
                     FROM member AS m WHERE m.id = loan.member_id),
                    'Bilinmeyen üye'
                ),
                member_number_snapshot = (
                    SELECT m.school_number FROM member AS m WHERE m.id = loan.member_id
                ),
                member_class_snapshot = (
                    SELECT m.class_name FROM member AS m WHERE m.id = loan.member_id
                ),
                member_type_snapshot = COALESCE(
                    (SELECT m.member_type FROM member AS m WHERE m.id = loan.member_id),
                    'student'
                ),
                academic_period_snapshot = CASE
                    WHEN loaned_at GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]*'
                    THEN CASE
                        WHEN CAST(substr(loaned_at, 6, 2) AS INTEGER) >= 9
                        THEN printf(
                            '%04d-%04d',
                            CAST(substr(loaned_at, 1, 4) AS INTEGER),
                            CAST(substr(loaned_at, 1, 4) AS INTEGER) + 1
                        )
                        ELSE printf(
                            '%04d-%04d',
                            CAST(substr(loaned_at, 1, 4) AS INTEGER) - 1,
                            CAST(substr(loaned_at, 1, 4) AS INTEGER)
                        )
                    END
                    ELSE 'bilinmiyor'
                END,
                snapshot_source = 'migration-estimate'
            WHERE member_name_snapshot IS NULL
               OR trim(member_name_snapshot) = ''
               OR member_type_snapshot NOT IN ('student', 'staff')
               OR academic_period_snapshot IS NULL
               OR trim(academic_period_snapshot) = ''
               OR snapshot_source IS NULL
               OR trim(snapshot_source) = '';

            CREATE TRIGGER IF NOT EXISTS loan_snapshot_required
            BEFORE INSERT ON loan
            WHEN NEW.member_name_snapshot IS NULL
              OR trim(NEW.member_name_snapshot) = ''
              OR NEW.member_type_snapshot NOT IN ('student', 'staff')
              OR NEW.academic_period_snapshot IS NULL
              OR trim(NEW.academic_period_snapshot) = ''
              OR NEW.snapshot_source IS NULL
              OR trim(NEW.snapshot_source) = ''
            BEGIN
                SELECT RAISE(ABORT, 'Ödünç üye/dönem anlık görüntüsü zorunludur');
            END;

            CREATE TRIGGER IF NOT EXISTS loan_snapshot_immutable
            BEFORE UPDATE OF member_name_snapshot, member_number_snapshot,
                             member_class_snapshot, member_type_snapshot,
                             academic_period_snapshot, snapshot_source ON loan
            WHEN NEW.member_name_snapshot IS NOT OLD.member_name_snapshot
              OR NEW.member_number_snapshot IS NOT OLD.member_number_snapshot
              OR NEW.member_class_snapshot IS NOT OLD.member_class_snapshot
              OR NEW.member_type_snapshot IS NOT OLD.member_type_snapshot
              OR NEW.academic_period_snapshot IS NOT OLD.academic_period_snapshot
              OR NEW.snapshot_source IS NOT OLD.snapshot_source
            BEGIN
                SELECT RAISE(ABORT, 'Ödünç anlık görüntüsü değiştirilemez');
            END;

            CREATE INDEX IF NOT EXISTS idx_loan_active_member_edition
                ON loan(member_id, edition_id)
                WHERE returned_at IS NULL AND edition_id IS NOT NULL;

            -- A non-unique index keeps upgrades compatible even if an old DB
            -- already contains a duplicate. These triggers reject every new or
            -- reopened duplicate at the storage boundary.
            CREATE TRIGGER IF NOT EXISTS loan_one_active_edition_insert
            BEFORE INSERT ON loan
            WHEN NEW.returned_at IS NULL AND NEW.edition_id IS NOT NULL
              AND EXISTS(
                  SELECT 1 FROM loan AS existing
                  WHERE existing.member_id = NEW.member_id
                    AND existing.edition_id = NEW.edition_id
                    AND existing.returned_at IS NULL
              )
            BEGIN
                SELECT RAISE(ABORT, 'Üyenin aynı baskıdan aktif nüshası zaten var');
            END;

            CREATE TRIGGER IF NOT EXISTS loan_one_active_edition_update
            BEFORE UPDATE OF member_id, edition_id, returned_at ON loan
            WHEN NEW.returned_at IS NULL AND NEW.edition_id IS NOT NULL
              AND EXISTS(
                  SELECT 1 FROM loan AS existing
                  WHERE existing.id != OLD.id
                    AND existing.member_id = NEW.member_id
                    AND existing.edition_id = NEW.edition_id
                    AND existing.returned_at IS NULL
              )
            BEGIN
                SELECT RAISE(ABORT, 'Üyenin aynı baskıdan aktif nüshası zaten var');
            END;

            CREATE TABLE IF NOT EXISTS circulation_event (
                id INTEGER PRIMARY KEY,
                request_id TEXT NOT NULL UNIQUE
                    CHECK (request_id = trim(request_id)
                           AND length(request_id) BETWEEN 8 AND 200),
                event_type TEXT NOT NULL
                    CHECK (event_type IN ('checkout', 'return', 'extend')),
                loan_id INTEGER NOT NULL,
                copy_id INTEGER,
                member_id INTEGER NOT NULL,
                edition_id INTEGER,
                request_json TEXT NOT NULL,
                result_json TEXT NOT NULL,
                occurred_at TEXT NOT NULL,
                created_at TEXT NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_circulation_event_loan
                ON circulation_event(loan_id, id);
            CREATE INDEX IF NOT EXISTS idx_circulation_event_member_time
                ON circulation_event(member_id, occurred_at, id);

            CREATE TRIGGER IF NOT EXISTS circulation_event_no_update
            BEFORE UPDATE ON circulation_event
            BEGIN
                SELECT RAISE(ABORT, 'Dolaşım olay günlüğü değiştirilemez');
            END;
            CREATE TRIGGER IF NOT EXISTS circulation_event_no_delete
            BEFORE DELETE ON circulation_event
            BEGIN
                SELECT RAISE(ABORT, 'Dolaşım olay günlüğü silinemez');
            END;

            INSERT OR IGNORE INTO schema_migration(version, applied_at)
            VALUES (8, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'));
            PRAGMA user_version = 8;
            COMMIT;
            """
        )

    @staticmethod
    def _migrate_v9(connection: sqlite3.Connection) -> None:
        """Dolap (raf) hedefini içe aktarma işine ve öğesine bağla.

        İşin dolabı bütün partiye; öğe dolabı yalnız o kitaba uygulanır (klasör
        adından türetilen dolaplar için).  Kataloglama sırasında öğe dolabı işin
        dolabını ezer.
        """

        # Sütun yoklaması yazma kilidi ALINDIKTAN sonra yapılır: iki uygulama
        # aynı v8 veritabanını aynı anda açtığında ikisi de "sütun yok" görüp
        # ikincisi duplicate-column hatası alırdı.  DDL de bu transaction'a
        # katılsın diye BEGIN elle yayılır (pysqlite DDL'i kendiliğinden
        # işlemlemez).
        connection.execute("BEGIN IMMEDIATE")
        try:
            job_columns = {
                str(row[1]) for row in connection.execute("PRAGMA table_info(import_job)")
            }
            item_columns = {
                str(row[1]) for row in connection.execute("PRAGMA table_info(job_item)")
            }
            for statement, missing in (
                ("ALTER TABLE import_job ADD COLUMN location TEXT", "location" not in job_columns),
                ("ALTER TABLE job_item ADD COLUMN location TEXT", "location" not in item_columns),
            ):
                if missing:
                    connection.execute(statement)
            connection.execute(
                """
                INSERT OR IGNORE INTO schema_migration(version, applied_at)
                VALUES (9, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
                """
            )
            connection.execute("PRAGMA user_version = 9")
            connection.execute("COMMIT")
        except BaseException:
            connection.execute("ROLLBACK")
            raise

    @staticmethod
    def _migrate_v10(connection: sqlite3.Connection) -> None:
        """Sesli düzeltme sözlüğü (voice_alias) ve iş başına dil tercihi.

        Kullanıcının onayladığı "duyulan -> kanonik" düzeltmeler kalıcı bir
        sözlüğe yazılır (bkz. voice_refine.alias_suggestions); toplu ses
        işleri artık ayar varsayılanını ezen isteğe bağlı bir dil taşıyabilir.
        """

        # Aynı kilit/DDL deseni _migrate_v9 ile birebir: sütun yoklaması yazma
        # kilidi ALINDIKTAN sonra yapılır, DDL elle yayılan BEGIN'e katılır.
        connection.execute("BEGIN IMMEDIATE")
        try:
            job_columns = {
                str(row[1]) for row in connection.execute("PRAGMA table_info(voice_job)")
            }
            if "language" not in job_columns:
                connection.execute("ALTER TABLE voice_job ADD COLUMN language TEXT")
            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS voice_alias (
                    id INTEGER PRIMARY KEY,
                    heard TEXT NOT NULL,
                    canonical TEXT NOT NULL,
                    field_scope TEXT NOT NULL DEFAULT 'any'
                        CHECK (field_scope IN ('any', 'title', 'author', 'publisher')),
                    created_at TEXT NOT NULL,
                    UNIQUE (heard, field_scope)
                )
                """
            )
            connection.execute(
                """
                INSERT OR IGNORE INTO schema_migration(version, applied_at)
                VALUES (10, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
                """
            )
            connection.execute("PRAGMA user_version = 10")
            connection.execute("COMMIT")
        except BaseException:
            connection.execute("ROLLBACK")
            raise

    @staticmethod
    def _migrate_v11(connection: sqlite3.Connection) -> None:
        """Dolaşım çekirdeği: rezervasyon (hold), bildirim merkezi, yasak/af.

        Rezervasyon kendi ``request_id UNIQUE`` sütunuyla idempotenttir (mevcut
        ``circulation_event`` defteri yalnız checkout/return/extend'e ayrılmış
        kalır; CHECK kısıtını genişletmek defterin bütünlük tetikleyicilerini
        yeniden kurmayı gerektirirdi — riski gereksiz büyütmemek için ayrı bir
        idempotency sütunu tercih edildi). ``notification.dedupe_key`` aynı
        şekilde tekrar-güvenli üretim sağlar (ör. "overdue:12:2026-08-09").
        """

        connection.execute("BEGIN IMMEDIATE")
        try:
            copy_columns = {
                str(row[1]) for row in connection.execute("PRAGMA table_info(copy)")
            }
            for statement, missing in (
                ("ALTER TABLE copy ADD COLUMN acquisition_method TEXT",
                 "acquisition_method" not in copy_columns),
                ("ALTER TABLE copy ADD COLUMN acquisition_date TEXT",
                 "acquisition_date" not in copy_columns),
                ("ALTER TABLE copy ADD COLUMN acquisition_price TEXT",
                 "acquisition_price" not in copy_columns),
            ):
                if missing:
                    connection.execute(statement)

            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS hold (
                    id INTEGER PRIMARY KEY,
                    edition_id INTEGER NOT NULL REFERENCES edition(id) ON DELETE CASCADE,
                    member_id INTEGER NOT NULL REFERENCES member(id) ON DELETE CASCADE,
                    status TEXT NOT NULL
                        CHECK (status IN ('active', 'ready', 'fulfilled', 'cancelled', 'expired')),
                    created_at TEXT NOT NULL,
                    ready_at TEXT,
                    ready_copy_id INTEGER REFERENCES copy(id) ON DELETE SET NULL,
                    expires_at TEXT,
                    request_id TEXT UNIQUE
                        CHECK (request_id IS NULL OR length(request_id) BETWEEN 8 AND 200)
                )
                """
            )
            connection.execute(
                "CREATE INDEX IF NOT EXISTS idx_hold_edition_status ON hold(edition_id, status)"
            )
            connection.execute(
                "CREATE INDEX IF NOT EXISTS idx_hold_member_status ON hold(member_id, status)"
            )

            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS notification (
                    id INTEGER PRIMARY KEY,
                    kind TEXT NOT NULL,
                    member_id INTEGER REFERENCES member(id) ON DELETE CASCADE,
                    ref_kind TEXT,
                    ref_id INTEGER,
                    title TEXT NOT NULL,
                    body TEXT,
                    created_at TEXT NOT NULL,
                    read_at TEXT,
                    dismissed_at TEXT,
                    dedupe_key TEXT UNIQUE
                )
                """
            )
            connection.execute(
                "CREATE INDEX IF NOT EXISTS idx_notification_unread "
                "ON notification(read_at, dismissed_at, created_at)"
            )
            connection.execute(
                "CREATE INDEX IF NOT EXISTS idx_notification_member "
                "ON notification(member_id, created_at)"
            )

            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS member_block (
                    id INTEGER PRIMARY KEY,
                    member_id INTEGER NOT NULL REFERENCES member(id) ON DELETE CASCADE,
                    kind TEXT NOT NULL CHECK (kind IN ('auto_overdue_waiver', 'manual')),
                    start_date TEXT NOT NULL,
                    end_date TEXT,
                    reason TEXT,
                    created_at TEXT NOT NULL,
                    lifted_at TEXT,
                    lift_reason TEXT
                )
                """
            )
            connection.execute(
                "CREATE INDEX IF NOT EXISTS idx_member_block_member "
                "ON member_block(member_id, kind, lifted_at)"
            )

            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS external_suggestion (
                    id INTEGER PRIMARY KEY,
                    isbn13 TEXT NOT NULL,
                    source TEXT NOT NULL,
                    payload_json TEXT NOT NULL,
                    fetched_at TEXT NOT NULL,
                    edition_id INTEGER REFERENCES edition(id) ON DELETE SET NULL,
                    status TEXT NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending', 'accepted', 'dismissed')),
                    UNIQUE (isbn13, source)
                )
                """
            )

            connection.execute(
                """
                INSERT OR IGNORE INTO schema_migration(version, applied_at)
                VALUES (11, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
                """
            )
            connection.execute("PRAGMA user_version = 11")
            connection.execute("COMMIT")
        except BaseException:
            connection.execute("ROLLBACK")
            raise

    @staticmethod
    def _migrate_v12(connection: sqlite3.Connection) -> None:
        """Pedagojik katman: okuma listeleri ve okuma yarışması.

        İlerleme/skor ayrı bir tabloda TUTULMAZ; her ikisi de ``loan`` defterinden
        (iade edilmiş = ``returned_at NOT NULL``) türetilir, böylece iki kaynağın
        birbirinden sapması mümkün olmaz.
        """

        connection.execute("BEGIN IMMEDIATE")
        try:
            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS reading_list (
                    id INTEGER PRIMARY KEY,
                    name TEXT NOT NULL,
                    description TEXT,
                    is_opac_visible INTEGER NOT NULL DEFAULT 0,
                    position INTEGER NOT NULL DEFAULT 0,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                )
                """
            )
            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS reading_list_item (
                    id INTEGER PRIMARY KEY,
                    list_id INTEGER NOT NULL REFERENCES reading_list(id) ON DELETE CASCADE,
                    edition_id INTEGER NOT NULL REFERENCES edition(id) ON DELETE CASCADE,
                    position INTEGER NOT NULL DEFAULT 0,
                    UNIQUE (list_id, edition_id)
                )
                """
            )
            connection.execute(
                "CREATE INDEX IF NOT EXISTS idx_reading_list_item_list "
                "ON reading_list_item(list_id, position)"
            )
            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS reading_assignment (
                    id INTEGER PRIMARY KEY,
                    list_id INTEGER NOT NULL REFERENCES reading_list(id) ON DELETE CASCADE,
                    member_id INTEGER NOT NULL REFERENCES member(id) ON DELETE CASCADE,
                    assigned_at TEXT NOT NULL,
                    note TEXT,
                    UNIQUE (list_id, member_id)
                )
                """
            )
            connection.execute(
                "CREATE INDEX IF NOT EXISTS idx_reading_assignment_member "
                "ON reading_assignment(member_id)"
            )
            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS reading_challenge (
                    id INTEGER PRIMARY KEY,
                    name TEXT NOT NULL,
                    start_date TEXT NOT NULL,
                    end_date TEXT NOT NULL,
                    target_books INTEGER NOT NULL CHECK (target_books > 0),
                    scope TEXT NOT NULL DEFAULT 'all' CHECK (scope IN ('all', 'class')),
                    class_name TEXT,
                    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'archived')),
                    created_at TEXT NOT NULL
                )
                """
            )
            connection.execute(
                "CREATE INDEX IF NOT EXISTS idx_reading_challenge_status "
                "ON reading_challenge(status, start_date)"
            )
            connection.execute(
                """
                CREATE TABLE IF NOT EXISTS challenge_certificate (
                    id INTEGER PRIMARY KEY,
                    challenge_id INTEGER NOT NULL REFERENCES reading_challenge(id) ON DELETE CASCADE,
                    member_id INTEGER NOT NULL REFERENCES member(id) ON DELETE CASCADE,
                    rank INTEGER,
                    printed_at TEXT NOT NULL,
                    UNIQUE (challenge_id, member_id)
                )
                """
            )

            connection.execute(
                """
                INSERT OR IGNORE INTO schema_migration(version, applied_at)
                VALUES (12, strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
                """
            )
            connection.execute("PRAGMA user_version = 12")
            connection.execute("COMMIT")
        except BaseException:
            connection.execute("ROLLBACK")
            raise

    def integrity_check(self) -> str:
        row = self.fetchone("PRAGMA integrity_check")
        return str(row[0]) if row is not None else "unknown"

    def checkpoint(self, *, truncate: bool = False) -> tuple[int, int, int]:
        mode = "TRUNCATE" if truncate else "PASSIVE"
        with self.connection() as connection:
            row = connection.execute(f"PRAGMA wal_checkpoint({mode})").fetchone()
            return int(row[0]), int(row[1]), int(row[2])

    def backup_to(self, destination: str | Path) -> Path:
        target = Path(destination)
        target.parent.mkdir(parents=True, exist_ok=True)
        part = target.with_name(f"{target.name}.part")
        if part.exists():
            part.unlink()
        with self.connection(readonly=True) as source, sqlite3.connect(part) as output:
            source.backup(output)
        part.replace(target)
        return target

    # ------------------------------------------------------------------
    # Durable import jobs

    def create_import_job(
        self,
        name: str,
        pairs: Iterable[ImagePair],
        *,
        storage_mode: StorageMode | str = StorageMode.MANAGED_COPY,
        idempotency_key: str | None = None,
        config_hash: str = "",
        job_id: str | None = None,
        location: str | None = None,
        locations: Mapping[str, str] | None = None,
    ) -> ImportJob:
        storage_mode = StorageMode(storage_mode)
        job_id = job_id or str(uuid.uuid4())
        now = _now_text()
        with self.transaction(immediate=True) as connection:
            if idempotency_key:
                existing = connection.execute(
                    "SELECT * FROM import_job WHERE idempotency_key = ?",
                    (idempotency_key,),
                ).fetchone()
                if existing is not None:
                    return _row_to_job(existing)
            connection.execute(
                """
                INSERT INTO import_job(
                    id, name, status, storage_mode, idempotency_key, config_hash,
                    location, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    job_id,
                    name.strip() or "Adsız içe aktarma",
                    ImportJobStatus.QUEUED.value,
                    storage_mode.value,
                    idempotency_key,
                    config_hash,
                    _clean_location(location),
                    now,
                    now,
                ),
            )
            count = self._insert_job_items(connection, job_id, pairs, now, locations=locations)
            status = ImportJobStatus.QUEUED.value if count else ImportJobStatus.COMPLETED.value
            finished = None if count else now
            connection.execute(
                """
                UPDATE import_job
                SET total_items = ?, status = ?, finished_at = ?, updated_at = ?
                WHERE id = ?
                """,
                (count, status, finished, now, job_id),
            )
            row = connection.execute("SELECT * FROM import_job WHERE id = ?", (job_id,)).fetchone()
            assert row is not None
            return _row_to_job(row)

    @staticmethod
    def _insert_job_items(
        connection: sqlite3.Connection,
        job_id: str,
        pairs: Iterable[ImagePair],
        now: str,
        *,
        locations: Mapping[str, str] | None = None,
    ) -> int:
        count = 0
        for pair in pairs:
            cursor = connection.execute(
                """
                INSERT OR IGNORE INTO job_item(
                    job_id, pair_key, front_path, front_inside_path,
                    back_inside_path, back_path, pairing_confidence,
                    pairing_basis, needs_pair_review, stage, location,
                    created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    job_id,
                    pair.pair_key,
                    str(pair.front),
                    str(pair.front_inside) if pair.front_inside is not None else None,
                    str(pair.back_inside) if pair.back_inside is not None else None,
                    str(pair.back),
                    pair.confidence,
                    pair.basis,
                    int(pair.needs_review),
                    JobItemStage.PAIRED.value,
                    _clean_location((locations or {}).get(pair.pair_key)),
                    now,
                    now,
                ),
            )
            count += int(cursor.rowcount > 0)
        return count

    def append_job_items(
        self,
        job_id: str,
        pairs: Iterable[ImagePair],
        *,
        locations: Mapping[str, str] | None = None,
    ) -> int:
        now = _now_text()
        with self.transaction(immediate=True) as connection:
            job = connection.execute(
                "SELECT status FROM import_job WHERE id = ?", (job_id,)
            ).fetchone()
            if job is None:
                raise KeyError(f"İçe aktarma işi bulunamadı: {job_id}")
            if job["status"] in {
                ImportJobStatus.CANCELLED.value,
                ImportJobStatus.COMPLETED.value,
                ImportJobStatus.COMPLETED_WITH_ERRORS.value,
            }:
                raise StateConflictError("Tamamlanmış işe yeni kayıt eklenemez")
            inserted = self._insert_job_items(connection, job_id, pairs, now, locations=locations)
            if inserted:
                connection.execute(
                    """
                    UPDATE import_job
                    SET total_items = total_items + ?, updated_at = ?
                    WHERE id = ?
                    """,
                    (inserted, now, job_id),
                )
            return inserted

    def get_import_job(self, job_id: str) -> ImportJob | None:
        row = self.fetchone("SELECT * FROM import_job WHERE id = ?", (job_id,))
        return _row_to_job(row) if row is not None else None

    def list_import_jobs(self, *, limit: int = 100, offset: int = 0) -> list[ImportJob]:
        rows = self.fetchall(
            """
            SELECT * FROM import_job
            ORDER BY created_at DESC, id DESC LIMIT ? OFFSET ?
            """,
            (_bounded_limit(limit), max(0, offset)),
        )
        return [_row_to_job(row) for row in rows]

    def get_job_item(self, item_id: int) -> JobItem | None:
        row = self.fetchone("SELECT * FROM job_item WHERE id = ?", (item_id,))
        return _row_to_job_item(row) if row is not None else None

    def list_job_items(
        self,
        job_id: str,
        *,
        stage: JobItemStage | str | None = None,
        limit: int = 250,
        offset: int = 0,
    ) -> list[JobItem]:
        parameters: list[Any] = [job_id]
        where = "job_id = ?"
        if stage is not None:
            where += " AND stage = ?"
            parameters.append(JobItemStage(stage).value)
        parameters.extend((_bounded_limit(limit, maximum=10_000), max(0, offset)))
        rows = self.fetchall(
            f"""
            SELECT * FROM job_item WHERE {where}
            ORDER BY id LIMIT ? OFFSET ?
            """,
            parameters,
        )
        return [_row_to_job_item(row) for row in rows]

    def list_pending_pair_reviews(
        self,
        *,
        job_id: str | None = None,
        limit: int = 250,
        offset: int = 0,
    ) -> list[JobItem]:
        """List ambiguous book-surface proposals needing a user decision."""

        parameters: list[Any] = []
        where = "needs_pair_review = 1"
        if job_id is not None:
            where += " AND job_id = ?"
            parameters.append(job_id)
        parameters.extend((_bounded_limit(limit, maximum=10_000), max(0, offset)))
        rows = self.fetchall(
            f"""
            SELECT * FROM job_item
            WHERE {where}
            ORDER BY created_at, id
            LIMIT ? OFFSET ?
            """,
            parameters,
        )
        return [_row_to_job_item(row) for row in rows]

    def set_job_status(self, job_id: str, status: ImportJobStatus | str) -> ImportJob:
        status = ImportJobStatus(status)
        now = _now_text()
        with self.transaction(immediate=True) as connection:
            row = connection.execute("SELECT * FROM import_job WHERE id = ?", (job_id,)).fetchone()
            if row is None:
                raise KeyError(f"İçe aktarma işi bulunamadı: {job_id}")
            current = ImportJobStatus(row["status"])
            allowed: dict[ImportJobStatus, frozenset[ImportJobStatus]] = {
                ImportJobStatus.QUEUED: frozenset(
                    {
                        ImportJobStatus.RUNNING,
                        ImportJobStatus.PAUSED,
                        ImportJobStatus.CANCELLED,
                    }
                ),
                ImportJobStatus.RUNNING: frozenset(
                    {ImportJobStatus.PAUSED, ImportJobStatus.CANCELLED}
                ),
                ImportJobStatus.PAUSED: frozenset(
                    {ImportJobStatus.RUNNING, ImportJobStatus.CANCELLED}
                ),
                ImportJobStatus.COMPLETED: frozenset(),
                ImportJobStatus.COMPLETED_WITH_ERRORS: frozenset(),
                ImportJobStatus.CANCELLED: frozenset(),
            }
            if status == current:
                return _row_to_job(row)
            if status not in allowed[current]:
                raise StateConflictError(f"Geçersiz iş geçişi: {current} → {status}")
            started = row["started_at"]
            if status == ImportJobStatus.RUNNING and started is None:
                started = now
            finished = now if status == ImportJobStatus.CANCELLED else row["finished_at"]
            connection.execute(
                """
                UPDATE import_job
                SET status = ?, started_at = ?, finished_at = ?, updated_at = ?
                WHERE id = ?
                """,
                (status.value, started, finished, now, job_id),
            )
            if status == ImportJobStatus.CANCELLED:
                placeholders = ",".join("?" for _ in _TERMINAL_ITEM_STAGES)
                cancelled = connection.execute(
                    f"""
                    UPDATE job_item
                    SET stage = ?, lease_owner = NULL, lease_until = NULL,
                        heartbeat_at = NULL, updated_at = ?
                    WHERE job_id = ? AND stage NOT IN ({placeholders})
                    """,
                    (
                        JobItemStage.CANCELLED.value,
                        now,
                        job_id,
                        *_TERMINAL_ITEM_STAGES,
                    ),
                )
                self._apply_import_job_count_delta(
                    connection,
                    job_id,
                    failed_delta=cancelled.rowcount,
                    now=now,
                )
            updated = connection.execute(
                "SELECT * FROM import_job WHERE id = ?", (job_id,)
            ).fetchone()
            assert updated is not None
            return _row_to_job(updated)

    def pause_job(self, job_id: str) -> ImportJob:
        return self.set_job_status(job_id, ImportJobStatus.PAUSED)

    def resume_job(self, job_id: str) -> ImportJob:
        return self.set_job_status(job_id, ImportJobStatus.RUNNING)

    def cancel_job(self, job_id: str) -> ImportJob:
        return self.set_job_status(job_id, ImportJobStatus.CANCELLED)

    def set_job_location(self, job_id: str, location: str | None) -> ImportJob:
        """İşin dolabını değiştirir; yalnız henüz kataloglanmamış kitapları etkiler.

        Kataloglanmış öğeler eski dolabı kendi üzerlerine yazılı olarak alır:
        nüshanın gerçek `copy.location` değeri değişmediği için iş özetinin de
        değişmemesi gerekir.
        """

        now = _now_text()
        with self.transaction(immediate=True) as connection:
            row = connection.execute(
                "SELECT location FROM import_job WHERE id = ?", (job_id,)
            ).fetchone()
            if row is None:
                raise KeyError(f"İçe aktarma işi bulunamadı: {job_id}")
            previous = row["location"]
            if previous:
                connection.execute(
                    """
                    UPDATE job_item SET location = ?, updated_at = ?
                    WHERE job_id = ? AND location IS NULL
                      AND (edition_id IS NOT NULL OR stage IN (?, ?, ?))
                    """,
                    (
                        previous,
                        now,
                        job_id,
                        JobItemStage.COMPLETED.value,
                        JobItemStage.REVIEW.value,
                        JobItemStage.CANCELLED.value,
                    ),
                )
            connection.execute(
                "UPDATE import_job SET location = ?, updated_at = ? WHERE id = ?",
                (_clean_location(location), now, job_id),
            )
            updated = connection.execute(
                "SELECT * FROM import_job WHERE id = ?", (job_id,)
            ).fetchone()
            assert updated is not None
            return _row_to_job(updated)

    def approve_pair(self, item_id: int, *, approved: bool = True) -> JobItem:
        now = _now_text()
        with self.transaction(immediate=True) as connection:
            row = connection.execute(
                """
                SELECT job_id, stage, needs_pair_review
                FROM job_item WHERE id = ?
                """,
                (item_id,),
            ).fetchone()
            if row is None:
                raise KeyError(f"İş öğesi bulunamadı: {item_id}")
            if JobItemStage(row["stage"]).terminal:
                raise StateConflictError("Terminal durumdaki eşleştirme değiştirilemez")
            if not bool(row["needs_pair_review"]):
                raise StateConflictError("Eşleştirme kullanıcı kararı beklemiyor")
            if approved:
                connection.execute(
                    """
                    UPDATE job_item
                    SET needs_pair_review = 0, updated_at = ? WHERE id = ?
                    """,
                    (now, item_id),
                )
            else:
                connection.execute(
                    """
                    UPDATE job_item
                    SET needs_pair_review = 0, stage = ?, last_error = ?,
                        lease_owner = NULL, lease_until = NULL, updated_at = ?
                    WHERE id = ?
                    """,
                    (
                        JobItemStage.FAILED.value,
                        "Kapak eşleştirmesi kullanıcı tarafından reddedildi",
                        now,
                        item_id,
                    ),
                )
                self._apply_import_item_transition(
                    connection,
                    row["job_id"],
                    row["stage"],
                    JobItemStage.FAILED.value,
                    now,
                )
            updated = connection.execute(
                "SELECT * FROM job_item WHERE id = ?", (item_id,)
            ).fetchone()
            assert updated is not None
            return _row_to_job_item(updated)

    def claim_next_item(
        self,
        worker_id: str,
        *,
        job_id: str | None = None,
        lease_seconds: int = 300,
        now: datetime | None = None,
    ) -> JobItem | None:
        if not worker_id.strip():
            raise ValueError("worker_id boş olamaz")
        instant = now or datetime.now(UTC)
        now_text = _datetime_text(instant)
        lease_until = _datetime_text(instant + timedelta(seconds=max(1, lease_seconds)))
        terminal_placeholders = ",".join("?" for _ in _TERMINAL_ITEM_STAGES)
        with self.transaction(immediate=True) as connection:
            parameters: list[Any] = [
                ImportJobStatus.QUEUED.value,
                ImportJobStatus.RUNNING.value,
                *_TERMINAL_ITEM_STAGES,
                now_text,
                now_text,
            ]
            job_filter = ""
            if job_id is not None:
                job_filter = "AND ji.job_id = ?"
                parameters.append(job_id)
            row = connection.execute(
                f"""
                SELECT ji.*
                FROM job_item AS ji
                JOIN import_job AS j ON j.id = ji.job_id
                WHERE j.status IN (?, ?)
                  AND ji.stage NOT IN ({terminal_placeholders})
                  AND ji.needs_pair_review = 0
                  AND (ji.lease_until IS NULL OR ji.lease_until <= ?)
                  AND (ji.not_before IS NULL OR ji.not_before <= ?)
                  {job_filter}
                ORDER BY j.created_at, ji.id
                LIMIT 1
                """,
                parameters,
            ).fetchone()
            if row is None:
                return None
            cursor = connection.execute(
                """
                UPDATE job_item
                SET lease_owner = ?, lease_until = ?, heartbeat_at = ?, updated_at = ?
                WHERE id = ? AND (lease_until IS NULL OR lease_until <= ?)
                """,
                (
                    worker_id,
                    lease_until,
                    now_text,
                    now_text,
                    row["id"],
                    now_text,
                ),
            )
            if cursor.rowcount != 1:
                return None
            connection.execute(
                """
                UPDATE import_job
                SET status = ?, started_at = COALESCE(started_at, ?), updated_at = ?
                WHERE id = ? AND status = ?
                """,
                (
                    ImportJobStatus.RUNNING.value,
                    now_text,
                    now_text,
                    row["job_id"],
                    ImportJobStatus.QUEUED.value,
                ),
            )
            claimed = connection.execute(
                "SELECT * FROM job_item WHERE id = ?", (row["id"],)
            ).fetchone()
            assert claimed is not None
            return _row_to_job_item(claimed)

    def heartbeat_item(
        self,
        item_id: int,
        worker_id: str,
        *,
        lease_seconds: int = 300,
        now: datetime | None = None,
    ) -> bool:
        instant = now or datetime.now(UTC)
        now_text = _datetime_text(instant)
        lease_until = _datetime_text(instant + timedelta(seconds=max(1, lease_seconds)))
        with self.transaction(immediate=True) as connection:
            cursor = connection.execute(
                """
                UPDATE job_item
                SET heartbeat_at = ?, lease_until = ?, updated_at = ?
                WHERE id = ? AND lease_owner = ? AND lease_until > ?
                """,
                (now_text, lease_until, now_text, item_id, worker_id, now_text),
            )
            return cursor.rowcount == 1

    def release_item(self, item_id: int, worker_id: str) -> bool:
        now = _now_text()
        with self.transaction(immediate=True) as connection:
            cursor = connection.execute(
                """
                UPDATE job_item
                SET lease_owner = NULL, lease_until = NULL, heartbeat_at = NULL,
                    updated_at = ?
                WHERE id = ? AND lease_owner = ?
                """,
                (now, item_id, worker_id),
            )
            return cursor.rowcount == 1

    def advance_item(
        self,
        item_id: int,
        worker_id: str,
        new_stage: JobItemStage | str,
        *,
        expected_stage: JobItemStage | str | None = None,
        edition_id: int | None = None,
        release: bool | None = None,
    ) -> JobItem:
        target = JobItemStage(new_stage)
        now = _now_text()
        with self.transaction(immediate=True) as connection:
            row = connection.execute("SELECT * FROM job_item WHERE id = ?", (item_id,)).fetchone()
            if row is None:
                raise KeyError(f"İş öğesi bulunamadı: {item_id}")
            self._assert_lease(row, worker_id, now)
            current = JobItemStage(row["stage"])
            if expected_stage is not None and current != JobItemStage(expected_stage):
                raise StateConflictError(
                    f"Beklenen aşama {JobItemStage(expected_stage)}, mevcut {current}"
                )
            if target == current:
                return _row_to_job_item(row)
            if target not in ALLOWED_STAGE_TRANSITIONS[current]:
                raise StateConflictError(f"Geçersiz öğe geçişi: {current} → {target}")
            if (
                current == JobItemStage.PREPROCESSED
                and target == JobItemStage.OCR_COMPLETE
                and not self._all_engines_complete(connection, item_id)
            ):
                raise StateConflictError(
                    "Tanımlı bütün kitap yüzlerinde beş OCR motoru tamamlanmadan ilerlenemez"
                )
            should_release = target.terminal if release is None else release
            connection.execute(
                """
                UPDATE job_item
                SET stage = ?, edition_id = COALESCE(?, edition_id),
                    lease_owner = CASE WHEN ? THEN NULL ELSE lease_owner END,
                    lease_until = CASE WHEN ? THEN NULL ELSE lease_until END,
                    heartbeat_at = CASE WHEN ? THEN NULL ELSE heartbeat_at END,
                    last_error = NULL, updated_at = ?
                WHERE id = ?
                """,
                (
                    target.value,
                    edition_id,
                    int(should_release),
                    int(should_release),
                    int(should_release),
                    now,
                    item_id,
                ),
            )
            self._apply_import_item_transition(
                connection,
                row["job_id"],
                current.value,
                target.value,
                now,
            )
            updated = connection.execute(
                "SELECT * FROM job_item WHERE id = ?", (item_id,)
            ).fetchone()
            assert updated is not None
            return _row_to_job_item(updated)

    def link_item_edition(
        self,
        item_id: int,
        worker_id: str,
        edition_id: int,
        *,
        expected_stage: JobItemStage | str = JobItemStage.RECONCILED,
    ) -> JobItem:
        """Lease-safely link a newly saved edition before subsequent writes.

        Completed-only exporters treat an edition with no job link as a manual
        catalogue record.  Linking immediately after ``save_book`` closes the
        small window in which an in-progress edition could leak into a
        consistent partial export.
        """

        now = _now_text()
        expected = JobItemStage(expected_stage)
        with self.transaction(immediate=True) as connection:
            row = connection.execute("SELECT * FROM job_item WHERE id = ?", (item_id,)).fetchone()
            if row is None:
                raise KeyError(f"İş öğesi bulunamadı: {item_id}")
            self._assert_lease(row, worker_id, now)
            current = JobItemStage(row["stage"])
            if current != expected:
                raise StateConflictError(
                    f"Baskı bağlantısı için beklenen aşama {expected}, mevcut {current}"
                )
            if (
                connection.execute("SELECT 1 FROM edition WHERE id = ?", (edition_id,)).fetchone()
                is None
            ):
                raise KeyError(f"Baskı bulunamadı: {edition_id}")
            linked = row["edition_id"]
            if linked is not None and int(linked) != int(edition_id):
                raise StateConflictError(f"İş öğesi zaten farklı baskıya bağlı: {linked}")
            connection.execute(
                """
                UPDATE job_item
                SET edition_id = ?, updated_at = ?
                WHERE id = ?
                """,
                (edition_id, now, item_id),
            )
            updated = connection.execute(
                "SELECT * FROM job_item WHERE id = ?", (item_id,)
            ).fetchone()
            assert updated is not None
            return _row_to_job_item(updated)

    def fail_item(
        self,
        item_id: int,
        worker_id: str,
        error: str,
        *,
        max_retries: int = 2,
        retry_delay_seconds: int = 0,
    ) -> JobItem:
        now_dt = datetime.now(UTC)
        now = _datetime_text(now_dt)
        with self.transaction(immediate=True) as connection:
            row = connection.execute("SELECT * FROM job_item WHERE id = ?", (item_id,)).fetchone()
            if row is None:
                raise KeyError(f"İş öğesi bulunamadı: {item_id}")
            self._assert_lease(row, worker_id, now)
            attempts = int(row["retry_count"]) + 1
            terminal = attempts > max(0, max_retries)
            stage = JobItemStage.FAILED.value if terminal else row["stage"]
            not_before = (
                None
                if terminal or retry_delay_seconds <= 0
                else _datetime_text(now_dt + timedelta(seconds=retry_delay_seconds))
            )
            connection.execute(
                """
                UPDATE job_item
                SET retry_count = ?, stage = ?, last_error = ?, not_before = ?,
                    lease_owner = NULL, lease_until = NULL, heartbeat_at = NULL,
                    updated_at = ?
                WHERE id = ?
                """,
                (attempts, stage, error[:4000], not_before, now, item_id),
            )
            if terminal:
                self._apply_import_item_transition(
                    connection,
                    row["job_id"],
                    row["stage"],
                    JobItemStage.FAILED.value,
                    now,
                )
            updated = connection.execute(
                "SELECT * FROM job_item WHERE id = ?", (item_id,)
            ).fetchone()
            assert updated is not None
            return _row_to_job_item(updated)

    def retry_failed_item(
        self,
        item_id: int,
        *,
        restart_stage: JobItemStage | str = JobItemStage.PAIRED,
        clear_engine_checkpoints: bool = False,
    ) -> JobItem:
        restart = JobItemStage(restart_stage)
        if restart.terminal or restart == JobItemStage.OCR_COMPLETE:
            raise ValueError("Yeniden deneme başlangıç aşaması işlenebilir olmalıdır")
        now = _now_text()
        with self.transaction(immediate=True) as connection:
            row = connection.execute("SELECT * FROM job_item WHERE id = ?", (item_id,)).fetchone()
            if row is None:
                raise KeyError(f"İş öğesi bulunamadı: {item_id}")
            if JobItemStage(row["stage"]) not in {
                JobItemStage.FAILED,
                JobItemStage.REVIEW,
            }:
                raise StateConflictError("Yalnız hata/inceleme öğesi yeniden denenebilir")
            if clear_engine_checkpoints:
                connection.execute("DELETE FROM job_item_engine WHERE item_id = ?", (item_id,))
            else:
                # A user-requested retry starts a fresh initial-attempt + two
                # retries cycle only for unfinished motors. Completed rows keep
                # their cache keys and remain authoritative checkpoints.
                connection.execute(
                    """
                    UPDATE job_item_engine
                    SET status = ?, attempt_count = 0, cache_key = NULL,
                        raw_result_path = NULL, text = NULL, error = NULL,
                        duration_ms = NULL, updated_at = ?
                    WHERE item_id = ? AND status <> ?
                    """,
                    (
                        RunStatus.PENDING.value,
                        now,
                        item_id,
                        RunStatus.COMPLETED.value,
                    ),
                )
            connection.execute(
                """
                UPDATE job_item
                SET stage = ?, retry_count = 0, last_error = NULL,
                    not_before = NULL, lease_owner = NULL, lease_until = NULL,
                    heartbeat_at = NULL, updated_at = ?
                WHERE id = ?
                """,
                (restart.value, now, item_id),
            )
            connection.execute(
                """
                UPDATE import_job
                SET status = ?, finished_at = NULL, updated_at = ?
                WHERE id = ?
                """,
                (ImportJobStatus.RUNNING.value, now, row["job_id"]),
            )
            self._apply_import_item_transition(
                connection,
                row["job_id"],
                row["stage"],
                restart.value,
                now,
            )
            updated = connection.execute(
                "SELECT * FROM job_item WHERE id = ?", (item_id,)
            ).fetchone()
            assert updated is not None
            return _row_to_job_item(updated)

    def retry_failed_items(self, job_id: str, *, limit: int = 500) -> tuple[int, int]:
        """İşin hatalı öğelerini toplu olarak yeniden kuyruğa alır.

        (yeniden kuyruğa alınan, hâlâ hatalı kalan) döner; tek çağrıda en çok
        ``limit`` öğe işlenir ve kalan sayı sessizce yutulmaz.  Her öğe kendi
        işleminde, tek öğelik yolun aynı durum makinesinden geçer.
        """

        job = self.get_import_job(job_id)
        if job is None:
            raise KeyError(f"İçe aktarma işi bulunamadı: {job_id}")
        # Yeniden deneme işi RUNNING'e çeker; iptal edilmiş ya da bilerek
        # duraklatılmış iş böyle sessizce diriltilmemelidir.
        if job.status == ImportJobStatus.CANCELLED:
            raise StateConflictError("İptal edilmiş işin öğeleri yeniden denenemez")
        if job.status == ImportJobStatus.PAUSED:
            raise StateConflictError(
                "Duraklatılmış iş yeniden denenemez; önce 'Devam' ile sürdürün"
            )
        items = self.list_job_items(job_id, stage=JobItemStage.FAILED, limit=limit)
        requeued = 0
        for item in items:
            try:
                self.retry_failed_item(item.id)
            except (KeyError, StateConflictError):
                # Başka bir çalışan bu arada öğeyi devraldıysa atlanır.
                continue
            requeued += 1
        remaining = int(
            self.fetchone(
                "SELECT COUNT(*) AS total FROM job_item WHERE job_id = ? AND stage = ?",
                (job_id, JobItemStage.FAILED.value),
            )["total"]
        )
        return requeued, remaining

    def delete_import_job(self, job_id: str) -> None:
        """Kataloğa hiç kitap yazmamış, durmuş bir işi kayıtlarıyla siler.

        job_item silinince ona bağlı alan gözlemleri de gider.  Bu yüzden üç
        kapı vardır: iş durmuş olmalı (çalışan iş önce iptal edilir), hiçbir
        öğesinde canlı kiralama kalmamalı (bir işçi hâlâ o kitabın içindeyse
        silme, işçinin yazdığı kaydı köksüz bırakırdı) ve iş kataloğa kitap
        yazmamış olmalı.
        """

        now = _now_text()
        with self.transaction(immediate=True) as connection:
            row = connection.execute(
                "SELECT status, successful_items FROM import_job WHERE id = ?", (job_id,)
            ).fetchone()
            if row is None:
                raise KeyError(f"İçe aktarma işi bulunamadı: {job_id}")
            if ImportJobStatus(row["status"]) not in {
                ImportJobStatus.CANCELLED,
                ImportJobStatus.COMPLETED,
                ImportJobStatus.COMPLETED_WITH_ERRORS,
            }:
                raise StateConflictError(
                    "Çalışan ya da sıradaki iş silinemez; önce iptal edin"
                )
            leased = connection.execute(
                """
                SELECT COUNT(*) AS total FROM job_item
                WHERE job_id = ? AND lease_until IS NOT NULL AND lease_until > ?
                """,
                (job_id, now),
            ).fetchone()
            if int(leased["total"]):
                raise StateConflictError(
                    "Bir işçi bu işin kitabını hâlâ işliyor; birkaç saniye sonra deneyin"
                )
            catalogued = connection.execute(
                """
                SELECT COUNT(*) AS total FROM job_item
                WHERE job_id = ? AND (stage = ? OR edition_id IS NOT NULL)
                """,
                (job_id, JobItemStage.COMPLETED.value),
            ).fetchone()
            if int(row["successful_items"]) or int(catalogued["total"]):
                raise StateConflictError(
                    "Kataloğa kitap yazmış iş silinemez; iptal edip kayıtta bırakın"
                )
            connection.execute("DELETE FROM import_job WHERE id = ?", (job_id,))

    # ------------------------------------------------------------------
    # Sesli kayıt kuyruğu (voice_job / voice_transcript_chunk / voice_item).
    # Görüntü kuyruğunun lease/heartbeat/idempotenlik sözleşmesinin birebir
    # analoğudur; job_item şeması görüntüye sıkı bağlı olduğu için ayrı
    # tablolar kullanılır, DurableScheduler'a dokunulmaz.

    def create_voice_job(
        self,
        *,
        name: str,
        source_audio_path: str | Path,
        source_sha256: str | None = None,
        single_book: bool = False,
        idempotency_key: str | None = None,
        config_hash: str = "",
        language: str | None = None,
    ) -> VoiceJob:
        now = _now_text()
        job_id = f"vj-{uuid.uuid4().hex[:12]}"
        with self.transaction(immediate=True) as connection:
            if idempotency_key is not None:
                existing = connection.execute(
                    "SELECT * FROM voice_job WHERE idempotency_key = ?",
                    (idempotency_key,),
                ).fetchone()
                if existing is not None:
                    return _row_to_voice_job(existing)
            connection.execute(
                """
                INSERT INTO voice_job(
                    id, name, status, phase, source_audio_path, source_sha256,
                    single_book, idempotency_key, config_hash, language,
                    created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    job_id,
                    name,
                    ImportJobStatus.QUEUED.value,
                    VoiceJobPhase.INGESTED.value,
                    str(source_audio_path),
                    source_sha256,
                    int(single_book),
                    idempotency_key,
                    config_hash,
                    language,
                    now,
                    now,
                ),
            )
            row = connection.execute("SELECT * FROM voice_job WHERE id = ?", (job_id,)).fetchone()
            assert row is not None
            return _row_to_voice_job(row)

    def get_voice_job(self, job_id: str) -> VoiceJob | None:
        row = self.fetchone("SELECT * FROM voice_job WHERE id = ?", (job_id,))
        return _row_to_voice_job(row) if row is not None else None

    def list_voice_jobs(self) -> list[VoiceJob]:
        rows = self.fetchall("SELECT * FROM voice_job ORDER BY created_at DESC, id DESC")
        return [_row_to_voice_job(row) for row in rows]

    def set_voice_job_status(self, job_id: str, status: ImportJobStatus | str) -> VoiceJob:
        target = ImportJobStatus(status)
        now = _now_text()
        with self.transaction(immediate=True) as connection:
            row = connection.execute("SELECT * FROM voice_job WHERE id = ?", (job_id,)).fetchone()
            if row is None:
                raise KeyError(f"Ses işi bulunamadı: {job_id}")
            current = ImportJobStatus(row["status"])
            if current == ImportJobStatus.CANCELLED and target in {
                ImportJobStatus.RUNNING,
                ImportJobStatus.PAUSED,
            }:
                raise StateConflictError("İptal edilmiş ses işi sürdürülemez")
            connection.execute(
                """
                UPDATE voice_job
                SET status = ?, updated_at = ?,
                    finished_at = CASE WHEN ? THEN ? ELSE finished_at END
                WHERE id = ?
                """,
                (
                    target.value,
                    now,
                    int(target == ImportJobStatus.CANCELLED),
                    now,
                    job_id,
                ),
            )
            if target == ImportJobStatus.CANCELLED:
                placeholders = ",".join("?" for _ in _TERMINAL_VOICE_STAGES)
                cancelled = connection.execute(
                    f"""
                    UPDATE voice_item
                    SET stage = ?, lease_owner = NULL, lease_until = NULL,
                        heartbeat_at = NULL, updated_at = ?
                    WHERE job_id = ? AND stage NOT IN ({placeholders})
                    """,
                    (
                        VoiceItemStage.CANCELLED.value,
                        now,
                        job_id,
                        *_TERMINAL_VOICE_STAGES,
                    ),
                )
                self._apply_voice_job_count_delta(
                    connection,
                    job_id,
                    failed_delta=cancelled.rowcount,
                    now=now,
                )
            updated = connection.execute(
                "SELECT * FROM voice_job WHERE id = ?", (job_id,)
            ).fetchone()
            assert updated is not None
            return _row_to_voice_job(updated)

    def pause_voice_job(self, job_id: str) -> VoiceJob:
        return self.set_voice_job_status(job_id, ImportJobStatus.PAUSED)

    def resume_voice_job(self, job_id: str) -> VoiceJob:
        return self.set_voice_job_status(job_id, ImportJobStatus.RUNNING)

    def cancel_voice_job(self, job_id: str) -> VoiceJob:
        return self.set_voice_job_status(job_id, ImportJobStatus.CANCELLED)

    def update_voice_job_progress(
        self,
        job_id: str,
        *,
        phase: VoiceJobPhase | str | None = None,
        canonical_wav_path: str | Path | None = None,
        source_sha256: str | None = None,
        error: str | None = None,
        mark_started: bool = False,
        mark_finished: bool = False,
    ) -> VoiceJob:
        now = _now_text()
        with self.transaction(immediate=True) as connection:
            row = connection.execute("SELECT * FROM voice_job WHERE id = ?", (job_id,)).fetchone()
            if row is None:
                raise KeyError(f"Ses işi bulunamadı: {job_id}")
            connection.execute(
                """
                UPDATE voice_job
                SET phase = COALESCE(?, phase),
                    canonical_wav_path = COALESCE(?, canonical_wav_path),
                    source_sha256 = COALESCE(?, source_sha256),
                    last_error = ?,
                    status = CASE WHEN ? THEN ? ELSE status END,
                    started_at = CASE
                        WHEN ? THEN COALESCE(started_at, ?) ELSE started_at
                    END,
                    finished_at = CASE WHEN ? THEN ? ELSE finished_at END,
                    updated_at = ?
                WHERE id = ?
                """,
                (
                    VoiceJobPhase(phase).value if phase is not None else None,
                    str(canonical_wav_path) if canonical_wav_path is not None else None,
                    source_sha256,
                    error[:4000] if error else None,
                    int(mark_started),
                    ImportJobStatus.RUNNING.value,
                    int(mark_started),
                    now,
                    int(mark_finished),
                    now,
                    now,
                    job_id,
                ),
            )
            updated = connection.execute(
                "SELECT * FROM voice_job WHERE id = ?", (job_id,)
            ).fetchone()
            assert updated is not None
            return _row_to_voice_job(updated)

    def claim_voice_job(
        self,
        job_id: str,
        worker_id: str,
        *,
        lease_seconds: int = 600,
        now: datetime | None = None,
    ) -> bool:
        """Faz-1'i (dönüştürme/transkripsiyon/bölütleme) tek işçiye kilitle.

        İki sürecin aynı işi eşzamanlı koşup chunk/scratch dosyalarında
        yarışmasını engeller; süresi dolmuş lease devralınabilir.
        """

        instant = now or datetime.now(UTC)
        now_text = _datetime_text(instant)
        lease_until = _datetime_text(instant + timedelta(seconds=max(1, lease_seconds)))
        with self.transaction(immediate=True) as connection:
            cursor = connection.execute(
                """
                UPDATE voice_job
                SET lease_owner = ?, lease_until = ?, heartbeat_at = ?,
                    updated_at = ?
                WHERE id = ?
                  AND status IN (?, ?)
                  AND (
                    lease_owner IS NULL
                    OR lease_owner = ?
                    OR lease_until IS NULL
                    OR lease_until <= ?
                  )
                """,
                (
                    worker_id,
                    lease_until,
                    now_text,
                    now_text,
                    job_id,
                    ImportJobStatus.QUEUED.value,
                    ImportJobStatus.RUNNING.value,
                    worker_id,
                    now_text,
                ),
            )
            return cursor.rowcount == 1

    def heartbeat_voice_job(
        self,
        job_id: str,
        worker_id: str,
        *,
        lease_seconds: int = 600,
        now: datetime | None = None,
    ) -> bool:
        instant = now or datetime.now(UTC)
        now_text = _datetime_text(instant)
        lease_until = _datetime_text(instant + timedelta(seconds=max(1, lease_seconds)))
        with self.transaction(immediate=True) as connection:
            cursor = connection.execute(
                """
                UPDATE voice_job
                SET heartbeat_at = ?, lease_until = ?, updated_at = ?
                WHERE id = ? AND lease_owner = ? AND lease_until > ?
                """,
                (now_text, lease_until, now_text, job_id, worker_id, now_text),
            )
            return cursor.rowcount == 1

    def release_voice_job(self, job_id: str, worker_id: str) -> bool:
        now = _now_text()
        with self.transaction(immediate=True) as connection:
            cursor = connection.execute(
                """
                UPDATE voice_job
                SET lease_owner = NULL, lease_until = NULL, heartbeat_at = NULL,
                    updated_at = ?
                WHERE id = ? AND lease_owner = ?
                """,
                (now, job_id, worker_id),
            )
            return cursor.rowcount == 1

    def next_voice_wake_seconds(self, job_id: str) -> float | None:
        """Şimdi claim edilemeyen ama ileride edilebilecek öğe için bekleme süresi.

        ``not_before`` (retry gecikmesi) veya yabancı ``lease_until`` içinden
        en yakın gelecekteki zamanı saniye cinsinden döndürür; işlenecek bir
        şey kalmadıysa None.
        """

        now = datetime.now(UTC)
        now_text = _datetime_text(now)
        placeholders = ",".join("?" for _ in _TERMINAL_VOICE_STAGES)
        row = self.fetchone(
            f"""
            SELECT MIN(wake) AS wake FROM (
                SELECT not_before AS wake FROM voice_item
                WHERE job_id = ? AND stage NOT IN ({placeholders})
                  AND not_before IS NOT NULL AND not_before > ?
                UNION ALL
                SELECT lease_until AS wake FROM voice_item
                WHERE job_id = ? AND stage NOT IN ({placeholders})
                  AND lease_until IS NOT NULL AND lease_until > ?
            )
            """,
            (
                job_id,
                *_TERMINAL_VOICE_STAGES,
                now_text,
                job_id,
                *_TERMINAL_VOICE_STAGES,
                now_text,
            ),
        )
        if row is None or row["wake"] is None:
            return None
        wake = _parse_datetime(row["wake"])
        if wake is None:
            return None
        return max(0.0, (wake - now).total_seconds())

    def upsert_voice_chunk(
        self,
        job_id: str,
        chunk_index: int,
        *,
        start_sample: int,
        end_sample: int,
        segments_json: str,
        model_id: str = "",
    ) -> None:
        now = _now_text()
        with self.transaction(immediate=True) as connection:
            connection.execute(
                """
                INSERT INTO voice_transcript_chunk(
                    job_id, chunk_index, start_sample, end_sample,
                    segments_json, model_id, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(job_id, chunk_index) DO UPDATE SET
                    start_sample = excluded.start_sample,
                    end_sample = excluded.end_sample,
                    segments_json = excluded.segments_json,
                    model_id = excluded.model_id
                """,
                (
                    job_id,
                    int(chunk_index),
                    int(start_sample),
                    int(end_sample),
                    segments_json,
                    model_id,
                    now,
                ),
            )

    def list_voice_chunks(self, job_id: str) -> list[sqlite3.Row]:
        return self.fetchall(
            """
            SELECT * FROM voice_transcript_chunk
            WHERE job_id = ? ORDER BY chunk_index
            """,
            (job_id,),
        )

    def insert_voice_items(self, job_id: str, items: Iterable[Mapping[str, Any]]) -> int:
        now = _now_text()
        inserted = 0
        with self.transaction(immediate=True) as connection:
            for item in items:
                cursor = connection.execute(
                    """
                    INSERT OR IGNORE INTO voice_item(
                        job_id, item_key, ordinal, start_sample, end_sample,
                        transcript_json, stage, created_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        job_id,
                        str(item["item_key"]),
                        int(item["ordinal"]),
                        int(item["start_sample"]),
                        int(item["end_sample"]),
                        str(item["transcript_json"]),
                        VoiceItemStage.SEGMENTED.value,
                        now,
                        now,
                    ),
                )
                inserted += cursor.rowcount
            if inserted:
                connection.execute(
                    """
                    UPDATE voice_job
                    SET total_items = total_items + ?, updated_at = ?
                    WHERE id = ?
                    """,
                    (inserted, now, job_id),
                )
        return inserted

    def list_voice_items(self, job_id: str) -> list[VoiceItem]:
        rows = self.fetchall(
            "SELECT * FROM voice_item WHERE job_id = ? ORDER BY ordinal",
            (job_id,),
        )
        return [_row_to_voice_item(row) for row in rows]

    def get_voice_item(self, item_id: int) -> VoiceItem | None:
        row = self.fetchone("SELECT * FROM voice_item WHERE id = ?", (item_id,))
        return _row_to_voice_item(row) if row is not None else None

    def get_voice_item_by_edition(self, edition_id: int) -> VoiceItem | None:
        row = self.fetchone(
            """
            SELECT * FROM voice_item
            WHERE edition_id = ? ORDER BY updated_at DESC LIMIT 1
            """,
            (edition_id,),
        )
        return _row_to_voice_item(row) if row is not None else None

    def claim_next_voice_item(
        self,
        worker_id: str,
        *,
        job_id: str | None = None,
        lease_seconds: int = 300,
        now: datetime | None = None,
    ) -> VoiceItem | None:
        if not worker_id.strip():
            raise ValueError("worker_id boş olamaz")
        instant = now or datetime.now(UTC)
        now_text = _datetime_text(instant)
        lease_until = _datetime_text(instant + timedelta(seconds=max(1, lease_seconds)))
        placeholders = ",".join("?" for _ in _TERMINAL_VOICE_STAGES)
        with self.transaction(immediate=True) as connection:
            parameters: list[Any] = [
                ImportJobStatus.QUEUED.value,
                ImportJobStatus.RUNNING.value,
                *_TERMINAL_VOICE_STAGES,
                now_text,
                now_text,
            ]
            job_filter = ""
            if job_id is not None:
                job_filter = "AND vi.job_id = ?"
                parameters.append(job_id)
            row = connection.execute(
                f"""
                SELECT vi.*
                FROM voice_item AS vi
                JOIN voice_job AS vj ON vj.id = vi.job_id
                WHERE vj.status IN (?, ?)
                  AND vi.stage NOT IN ({placeholders})
                  AND (vi.lease_until IS NULL OR vi.lease_until <= ?)
                  AND (vi.not_before IS NULL OR vi.not_before <= ?)
                  {job_filter}
                ORDER BY vj.created_at, vi.ordinal
                LIMIT 1
                """,
                parameters,
            ).fetchone()
            if row is None:
                return None
            cursor = connection.execute(
                """
                UPDATE voice_item
                SET lease_owner = ?, lease_until = ?, heartbeat_at = ?,
                    updated_at = ?
                WHERE id = ? AND (lease_until IS NULL OR lease_until <= ?)
                """,
                (worker_id, lease_until, now_text, now_text, row["id"], now_text),
            )
            if cursor.rowcount != 1:
                return None
            connection.execute(
                """
                UPDATE voice_job
                SET status = ?, started_at = COALESCE(started_at, ?),
                    updated_at = ?
                WHERE id = ? AND status = ?
                """,
                (
                    ImportJobStatus.RUNNING.value,
                    now_text,
                    now_text,
                    row["job_id"],
                    ImportJobStatus.QUEUED.value,
                ),
            )
            claimed = connection.execute(
                "SELECT * FROM voice_item WHERE id = ?", (row["id"],)
            ).fetchone()
            assert claimed is not None
            return _row_to_voice_item(claimed)

    def heartbeat_voice_item(
        self,
        item_id: int,
        worker_id: str,
        *,
        lease_seconds: int = 300,
        now: datetime | None = None,
    ) -> bool:
        instant = now or datetime.now(UTC)
        now_text = _datetime_text(instant)
        lease_until = _datetime_text(instant + timedelta(seconds=max(1, lease_seconds)))
        with self.transaction(immediate=True) as connection:
            cursor = connection.execute(
                """
                UPDATE voice_item
                SET heartbeat_at = ?, lease_until = ?, updated_at = ?
                WHERE id = ? AND lease_owner = ? AND lease_until > ?
                """,
                (now_text, lease_until, now_text, item_id, worker_id, now_text),
            )
            return cursor.rowcount == 1

    def advance_voice_item(
        self,
        item_id: int,
        worker_id: str,
        new_stage: VoiceItemStage | str,
        *,
        expected_stage: VoiceItemStage | str | None = None,
        edition_id: int | None = None,
        claims_json: str | None = None,
        review_reasons_json: str | None = None,
        release: bool | None = None,
    ) -> VoiceItem:
        target = VoiceItemStage(new_stage)
        now = _now_text()
        with self.transaction(immediate=True) as connection:
            row = connection.execute("SELECT * FROM voice_item WHERE id = ?", (item_id,)).fetchone()
            if row is None:
                raise KeyError(f"Ses öğesi bulunamadı: {item_id}")
            self._assert_lease(row, worker_id, now)
            current = VoiceItemStage(row["stage"])
            if expected_stage is not None and current != VoiceItemStage(expected_stage):
                raise StateConflictError(
                    f"Beklenen aşama {VoiceItemStage(expected_stage)}, mevcut {current}"
                )
            if target == current:
                return _row_to_voice_item(row)
            if target not in ALLOWED_VOICE_STAGE_TRANSITIONS[current]:
                raise StateConflictError(f"Geçersiz ses öğesi geçişi: {current} → {target}")
            should_release = target.terminal if release is None else release
            connection.execute(
                """
                UPDATE voice_item
                SET stage = ?, edition_id = COALESCE(?, edition_id),
                    claims_json = COALESCE(?, claims_json),
                    review_reasons_json = COALESCE(?, review_reasons_json),
                    lease_owner = CASE WHEN ? THEN NULL ELSE lease_owner END,
                    lease_until = CASE WHEN ? THEN NULL ELSE lease_until END,
                    heartbeat_at = CASE WHEN ? THEN NULL ELSE heartbeat_at END,
                    last_error = NULL, updated_at = ?
                WHERE id = ?
                """,
                (
                    target.value,
                    edition_id,
                    claims_json,
                    review_reasons_json,
                    int(should_release),
                    int(should_release),
                    int(should_release),
                    now,
                    item_id,
                ),
            )
            self._apply_voice_item_transition(
                connection,
                row["job_id"],
                current.value,
                target.value,
                now,
            )
            updated = connection.execute(
                "SELECT * FROM voice_item WHERE id = ?", (item_id,)
            ).fetchone()
            assert updated is not None
            return _row_to_voice_item(updated)

    def fail_voice_item(
        self,
        item_id: int,
        worker_id: str,
        error: str,
        *,
        max_retries: int = 2,
        retry_delay_seconds: int = 0,
    ) -> VoiceItem:
        now_dt = datetime.now(UTC)
        now = _datetime_text(now_dt)
        with self.transaction(immediate=True) as connection:
            row = connection.execute("SELECT * FROM voice_item WHERE id = ?", (item_id,)).fetchone()
            if row is None:
                raise KeyError(f"Ses öğesi bulunamadı: {item_id}")
            self._assert_lease(row, worker_id, now)
            attempts = int(row["retry_count"]) + 1
            terminal = attempts > max(0, max_retries)
            stage = VoiceItemStage.FAILED.value if terminal else row["stage"]
            not_before = (
                None
                if terminal or retry_delay_seconds <= 0
                else _datetime_text(now_dt + timedelta(seconds=retry_delay_seconds))
            )
            connection.execute(
                """
                UPDATE voice_item
                SET retry_count = ?, stage = ?, last_error = ?, not_before = ?,
                    lease_owner = NULL, lease_until = NULL, heartbeat_at = NULL,
                    updated_at = ?
                WHERE id = ?
                """,
                (attempts, stage, error[:4000], not_before, now, item_id),
            )
            if terminal:
                self._apply_voice_item_transition(
                    connection,
                    row["job_id"],
                    row["stage"],
                    VoiceItemStage.FAILED.value,
                    now,
                )
            updated = connection.execute(
                "SELECT * FROM voice_item WHERE id = ?", (item_id,)
            ).fetchone()
            assert updated is not None
            return _row_to_voice_item(updated)

    def retry_failed_voice_item(self, item_id: int) -> VoiceItem:
        now = _now_text()
        with self.transaction(immediate=True) as connection:
            row = connection.execute("SELECT * FROM voice_item WHERE id = ?", (item_id,)).fetchone()
            if row is None:
                raise KeyError(f"Ses öğesi bulunamadı: {item_id}")
            if VoiceItemStage(row["stage"]) not in {
                VoiceItemStage.FAILED,
                VoiceItemStage.REVIEW,
            }:
                raise StateConflictError("Yalnız hata/inceleme öğesi yeniden denenebilir")
            connection.execute(
                """
                UPDATE voice_item
                SET stage = ?, retry_count = 0, last_error = NULL,
                    not_before = NULL, lease_owner = NULL, lease_until = NULL,
                    heartbeat_at = NULL, updated_at = ?
                WHERE id = ?
                """,
                (VoiceItemStage.SEGMENTED.value, now, item_id),
            )
            connection.execute(
                """
                UPDATE voice_job
                SET status = ?, phase = ?, finished_at = NULL, updated_at = ?
                WHERE id = ?
                """,
                (
                    ImportJobStatus.RUNNING.value,
                    VoiceJobPhase.ITEMS.value,
                    now,
                    row["job_id"],
                ),
            )
            self._apply_voice_item_transition(
                connection,
                row["job_id"],
                row["stage"],
                VoiceItemStage.SEGMENTED.value,
                now,
            )
            updated = connection.execute(
                "SELECT * FROM voice_item WHERE id = ?", (item_id,)
            ).fetchone()
            assert updated is not None
            return _row_to_voice_item(updated)

    @staticmethod
    def _apply_voice_item_transition(
        connection: sqlite3.Connection,
        job_id: str,
        previous_stage: str,
        new_stage: str,
        now: str,
    ) -> None:
        before = _terminal_count_vector(previous_stage)
        after = _terminal_count_vector(new_stage)
        Database._apply_voice_job_count_delta(
            connection,
            job_id,
            successful_delta=after[0] - before[0],
            failed_delta=after[1] - before[1],
            review_delta=after[2] - before[2],
            now=now,
        )

    @staticmethod
    def _apply_voice_job_count_delta(
        connection: sqlite3.Connection,
        job_id: str,
        *,
        successful_delta: int = 0,
        failed_delta: int = 0,
        review_delta: int = 0,
        now: str,
    ) -> None:
        """Apply one O(1) voice-item counter delta inside its state transaction."""

        if not (successful_delta or failed_delta or review_delta):
            return
        job = connection.execute(
            """
            UPDATE voice_job
            SET successful_items = successful_items + ?,
                failed_items = failed_items + ?,
                review_items = review_items + ?,
                updated_at = ?
            WHERE id = ?
            RETURNING total_items, successful_items, failed_items, review_items, status
            """,
            (successful_delta, failed_delta, review_delta, now, job_id),
        ).fetchone()
        if job is None:
            return
        successful = int(job["successful_items"])
        failed = int(job["failed_items"])
        review = int(job["review_items"])
        total = int(job["total_items"])
        terminal = successful + failed + review
        if min(successful, failed, review) < 0 or terminal > total:
            raise DatabaseError(f"Ses işi sayaçları tutarsız: {job_id}")
        current = ImportJobStatus(job["status"])
        if current != ImportJobStatus.CANCELLED and total > 0 and terminal == total:
            status = (
                ImportJobStatus.COMPLETED_WITH_ERRORS
                if failed
                else ImportJobStatus.COMPLETED
            )
            connection.execute(
                """
                UPDATE voice_job
                SET status = ?, phase = ?, finished_at = COALESCE(finished_at, ?),
                    updated_at = ?
                WHERE id = ?
                """,
                (status.value, VoiceJobPhase.DONE.value, now, now, job_id),
            )

    def reconcile_voice_job_counts(self, job_id: str) -> VoiceJob:
        """Explicit repair path; normal transitions must use constant-time deltas."""

        now = _now_text()
        with self.transaction(immediate=True) as connection:
            if (
                connection.execute("SELECT 1 FROM voice_job WHERE id = ?", (job_id,)).fetchone()
                is None
            ):
                raise KeyError(f"Ses işi bulunamadı: {job_id}")
            self._reconcile_voice_job_counts(connection, job_id, now)
            updated = connection.execute(
                "SELECT * FROM voice_job WHERE id = ?", (job_id,)
            ).fetchone()
            assert updated is not None
            return _row_to_voice_job(updated)

    @staticmethod
    def _reconcile_voice_job_counts(
        connection: sqlite3.Connection, job_id: str, now: str
    ) -> None:
        """Rebuild counters from rows for migrations/manual integrity repair only."""

        counts = connection.execute(
            """
            SELECT
                SUM(CASE WHEN stage = ? THEN 1 ELSE 0 END) AS successful,
                SUM(CASE WHEN stage IN (?, ?) THEN 1 ELSE 0 END) AS failed,
                SUM(CASE WHEN stage = ? THEN 1 ELSE 0 END) AS review,
                COUNT(*) AS total
            FROM voice_item WHERE job_id = ?
            """,
            (
                VoiceItemStage.COMPLETED.value,
                VoiceItemStage.FAILED.value,
                VoiceItemStage.CANCELLED.value,
                VoiceItemStage.REVIEW.value,
                job_id,
            ),
        ).fetchone()
        assert counts is not None
        successful = int(counts["successful"] or 0)
        failed = int(counts["failed"] or 0)
        review = int(counts["review"] or 0)
        total = int(counts["total"] or 0)
        terminal = successful + failed + review
        job = connection.execute(
            "SELECT status, phase, finished_at FROM voice_job WHERE id = ?", (job_id,)
        ).fetchone()
        if job is None:
            return
        current = ImportJobStatus(job["status"])
        status = current.value
        phase = job["phase"]
        finished_at = job["finished_at"]
        if current == ImportJobStatus.CANCELLED:
            finished_at = finished_at or now
        elif total > 0 and terminal == total:
            status = (
                ImportJobStatus.COMPLETED_WITH_ERRORS.value
                if failed
                else ImportJobStatus.COMPLETED.value
            )
            phase = VoiceJobPhase.DONE.value
            finished_at = finished_at or now
        elif current in {
            ImportJobStatus.COMPLETED,
            ImportJobStatus.COMPLETED_WITH_ERRORS,
        }:
            status = ImportJobStatus.RUNNING.value
            phase = VoiceJobPhase.ITEMS.value
            finished_at = None
        connection.execute(
            """
            UPDATE voice_job
            SET total_items = ?, successful_items = ?, failed_items = ?,
                review_items = ?, status = ?, phase = ?, finished_at = ?, updated_at = ?
            WHERE id = ?
            """,
            (
                total,
                successful,
                failed,
                review,
                status,
                phase,
                finished_at,
                now,
                job_id,
            ),
        )

    # ------------------------------------------------ sesli düzeltme sözlüğü

    def list_voice_aliases(self) -> list[VoiceAlias]:
        rows = self.fetchall(
            "SELECT * FROM voice_alias ORDER BY field_scope, heard COLLATE NOCASE"
        )
        return [_row_to_voice_alias(row) for row in rows]

    def upsert_voice_alias(self, heard: str, canonical: str, field_scope: str) -> VoiceAlias:
        """(heard, field_scope) çiftini kanonik değerle ekle/güncelle."""

        now = _now_text()
        with self.transaction(immediate=True) as connection:
            connection.execute(
                """
                INSERT INTO voice_alias(heard, canonical, field_scope, created_at)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(heard, field_scope) DO UPDATE SET canonical = excluded.canonical
                """,
                (heard, canonical, field_scope, now),
            )
            row = connection.execute(
                "SELECT * FROM voice_alias WHERE heard = ? AND field_scope = ?",
                (heard, field_scope),
            ).fetchone()
            assert row is not None
            return _row_to_voice_alias(row)

    def delete_voice_alias(self, alias_id: int) -> None:
        with self.transaction(immediate=True) as connection:
            cursor = connection.execute("DELETE FROM voice_alias WHERE id = ?", (alias_id,))
            if cursor.rowcount == 0:
                raise KeyError(f"Sözlük kaydı bulunamadı: {alias_id}")

    @staticmethod
    def _assert_lease(row: sqlite3.Row, worker_id: str, now: str) -> None:
        if row["lease_owner"] != worker_id:
            raise LeaseLostError(f"Öğe kilidi artık {worker_id} işçisine ait değil")
        if row["lease_until"] is None or row["lease_until"] <= now:
            raise LeaseLostError("Öğe kilidinin süresi dolmuş")

    def register_image_asset(
        self,
        item_id: int,
        cover_role: CoverRole | str,
        *,
        source_path: str | Path,
        managed_path: str | Path | None = None,
        source_sha256: str | None = None,
        crop_sha256: str | None = None,
        mime_type: str | None = None,
        width: int | None = None,
        height: int | None = None,
        preprocessing_version: str = "",
        homography: Any | None = None,
        edition_id: int | None = None,
    ) -> int:
        role = CoverRole(cover_role)
        now = _now_text()
        homography_json = (
            json.dumps(homography, ensure_ascii=False, separators=(",", ":"))
            if homography is not None
            else None
        )
        with self.transaction(immediate=True) as connection:
            connection.execute(
                """
                INSERT INTO image_asset(
                    item_id, edition_id, cover_role, source_path, managed_path, source_sha256,
                    crop_sha256, mime_type, width, height, preprocessing_version,
                    homography_json, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(item_id, cover_role) DO UPDATE SET
                    edition_id = COALESCE(excluded.edition_id, image_asset.edition_id),
                    source_path = excluded.source_path,
                    managed_path = excluded.managed_path,
                    source_sha256 = excluded.source_sha256,
                    crop_sha256 = excluded.crop_sha256,
                    mime_type = excluded.mime_type,
                    width = excluded.width,
                    height = excluded.height,
                    preprocessing_version = excluded.preprocessing_version,
                    homography_json = excluded.homography_json,
                    updated_at = excluded.updated_at
                """,
                (
                    item_id,
                    edition_id,
                    role.value,
                    str(source_path),
                    str(managed_path) if managed_path is not None else None,
                    source_sha256,
                    crop_sha256,
                    mime_type,
                    width,
                    height,
                    preprocessing_version,
                    homography_json,
                    now,
                    now,
                ),
            )
            row = connection.execute(
                """
                SELECT id FROM image_asset WHERE item_id = ? AND cover_role = ?
                """,
                (item_id, role.value),
            ).fetchone()
            assert row is not None
            return int(row["id"])

    def replace_consensus_spans(
        self, image_asset_id: int, spans: Iterable[PersistedConsensusSpan]
    ) -> int:
        """Atomically replace reconciled spans for one canonical cover."""

        with self.transaction(immediate=True) as connection:
            if (
                connection.execute(
                    "SELECT 1 FROM image_asset WHERE id = ?", (image_asset_id,)
                ).fetchone()
                is None
            ):
                raise KeyError(f"Görüntü varlığı bulunamadı: {image_asset_id}")
            connection.execute(
                "DELETE FROM consensus_span WHERE image_asset_id = ?",
                (image_asset_id,),
            )
            count = 0
            for index, span in enumerate(spans):
                connection.execute(
                    """
                    INSERT INTO consensus_span(
                        image_asset_id, span_index, text, normalized_text,
                        polygon_json, source_polygon_json, confidence,
                        source_refs_json, engine_support_json
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        image_asset_id,
                        index,
                        span.text,
                        span.normalized_text,
                        (
                            json.dumps(span.polygon, separators=(",", ":"))
                            if span.polygon is not None
                            else None
                        ),
                        (
                            json.dumps(span.source_polygon, separators=(",", ":"))
                            if span.source_polygon is not None
                            else None
                        ),
                        span.confidence,
                        json.dumps(list(span.source_token_ids), separators=(",", ":")),
                        json.dumps(
                            [engine.value for engine in span.engine_support],
                            separators=(",", ":"),
                        ),
                    ),
                )
                count += 1
            return count

    def get_consensus_spans(self, image_asset_id: int) -> tuple[PersistedConsensusSpan, ...]:
        rows = self.fetchall(
            """
            SELECT * FROM consensus_span
            WHERE image_asset_id = ? ORDER BY span_index
            """,
            (image_asset_id,),
        )
        return tuple(
            PersistedConsensusSpan(
                text=row["text"],
                normalized_text=row["normalized_text"],
                confidence=float(row["confidence"]),
                source_token_ids=tuple(json.loads(row["source_refs_json"])),
                polygon=(
                    tuple(
                        (float(point[0]), float(point[1]))
                        for point in json.loads(row["polygon_json"])
                    )
                    if row["polygon_json"]
                    else None
                ),
                source_polygon=(
                    tuple(
                        (float(point[0]), float(point[1]))
                        for point in json.loads(row["source_polygon_json"])
                    )
                    if row["source_polygon_json"]
                    else None
                ),
                engine_support=tuple(
                    OcrEngine(engine) for engine in json.loads(row["engine_support_json"])
                ),
            )
            for row in rows
        )

    def record_engine_success(
        self,
        item_id: int,
        cover_role: CoverRole | str,
        engine: OcrEngine | str,
        *,
        cache_key: str,
        text: str = "",
        raw_result_path: str | Path | None = None,
        duration_ms: int | None = None,
        worker_id: str | None = None,
        model_digest: str = "",
        config_hash: str = "",
        preprocessing_version: str = "",
        normalized_text: str = "",
    ) -> JobItem:
        role = CoverRole(cover_role)
        engine = OcrEngine(engine)
        now = _now_text()
        with self.transaction(immediate=True) as connection:
            item = connection.execute("SELECT * FROM job_item WHERE id = ?", (item_id,)).fetchone()
            if item is None:
                raise KeyError(f"İş öğesi bulunamadı: {item_id}")
            self._assert_active_cover_role(item, role)
            if worker_id is not None:
                self._assert_lease(item, worker_id, now)
            stage = JobItemStage(item["stage"])
            if stage not in {JobItemStage.PREPROCESSED, JobItemStage.OCR_COMPLETE}:
                raise StateConflictError(f"OCR sonucu {stage} aşamasında kaydedilemez")
            previous = connection.execute(
                """
                SELECT attempt_count, status FROM job_item_engine
                WHERE item_id = ? AND cover_role = ? AND engine_name = ?
                """,
                (item_id, role.value, engine.value),
            ).fetchone()
            attempts = (
                int(previous["attempt_count"])
                if previous is not None and previous["status"] == RunStatus.COMPLETED.value
                else (int(previous["attempt_count"]) if previous else 0) + 1
            )
            connection.execute(
                """
                INSERT INTO job_item_engine(
                    item_id, cover_role, engine_name, status, attempt_count,
                    cache_key, raw_result_path, text, error, duration_ms, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, NULL, ?, ?)
                ON CONFLICT(item_id, cover_role, engine_name) DO UPDATE SET
                    status = excluded.status,
                    attempt_count = MAX(
                        job_item_engine.attempt_count, excluded.attempt_count
                    ),
                    cache_key = excluded.cache_key,
                    raw_result_path = excluded.raw_result_path,
                    text = excluded.text,
                    error = NULL,
                    duration_ms = excluded.duration_ms,
                    updated_at = excluded.updated_at
                """,
                (
                    item_id,
                    role.value,
                    engine.value,
                    RunStatus.COMPLETED.value,
                    attempts,
                    cache_key,
                    str(raw_result_path) if raw_result_path is not None else None,
                    text,
                    duration_ms,
                    now,
                ),
            )
            asset = connection.execute(
                """
                SELECT id FROM image_asset WHERE item_id = ? AND cover_role = ?
                """,
                (item_id, role.value),
            ).fetchone()
            if asset is not None:
                connection.execute(
                    """
                    INSERT INTO ocr_engine_run(
                        image_asset_id, engine_name, model_digest, config_hash,
                        preprocessing_version, cache_key, status, attempt_count,
                        raw_result_path, raw_text, normalized_text, duration_ms,
                        created_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(
                        image_asset_id, engine_name, model_digest, config_hash,
                        preprocessing_version
                    ) DO UPDATE SET
                        cache_key = excluded.cache_key,
                        status = excluded.status,
                        attempt_count = MAX(
                            ocr_engine_run.attempt_count, excluded.attempt_count
                        ),
                        raw_result_path = excluded.raw_result_path,
                        raw_text = excluded.raw_text,
                        normalized_text = excluded.normalized_text,
                        error = NULL,
                        duration_ms = excluded.duration_ms,
                        updated_at = excluded.updated_at
                    """,
                    (
                        asset["id"],
                        engine.value,
                        model_digest,
                        config_hash,
                        preprocessing_version,
                        cache_key,
                        RunStatus.COMPLETED.value,
                        attempts,
                        str(raw_result_path) if raw_result_path is not None else None,
                        text,
                        normalized_text or text,
                        duration_ms,
                        now,
                        now,
                    ),
                )
            if stage == JobItemStage.PREPROCESSED and self._all_engines_complete(
                connection, item_id
            ):
                connection.execute(
                    """
                    UPDATE job_item SET stage = ?, updated_at = ? WHERE id = ?
                    """,
                    (JobItemStage.OCR_COMPLETE.value, now, item_id),
                )
            updated = connection.execute(
                "SELECT * FROM job_item WHERE id = ?", (item_id,)
            ).fetchone()
            assert updated is not None
            return _row_to_job_item(updated)

    def record_engine_failure(
        self,
        item_id: int,
        cover_role: CoverRole | str,
        engine: OcrEngine | str,
        error: str,
        *,
        max_retries: int = 2,
        worker_id: str | None = None,
    ) -> bool:
        """Checkpoint an engine error.

        Returns ``True`` while another attempt remains.  After the initial
        failure plus ``max_retries`` retries, the entire book item is failed.
        """

        role = CoverRole(cover_role)
        engine = OcrEngine(engine)
        now = _now_text()
        with self.transaction(immediate=True) as connection:
            item = connection.execute("SELECT * FROM job_item WHERE id = ?", (item_id,)).fetchone()
            if item is None:
                raise KeyError(f"İş öğesi bulunamadı: {item_id}")
            self._assert_active_cover_role(item, role)
            if worker_id is not None:
                self._assert_lease(item, worker_id, now)
            previous = connection.execute(
                """
                SELECT attempt_count, status FROM job_item_engine
                WHERE item_id = ? AND cover_role = ? AND engine_name = ?
                """,
                (item_id, role.value, engine.value),
            ).fetchone()
            if previous is not None and previous["status"] == RunStatus.COMPLETED.value:
                return False
            attempts = (int(previous["attempt_count"]) if previous else 0) + 1
            exhausted = attempts > max(0, max_retries)
            status = RunStatus.FAILED if exhausted else RunStatus.PENDING
            connection.execute(
                """
                INSERT INTO job_item_engine(
                    item_id, cover_role, engine_name, status, attempt_count,
                    error, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(item_id, cover_role, engine_name) DO UPDATE SET
                    status = excluded.status,
                    attempt_count = excluded.attempt_count,
                    error = excluded.error,
                    updated_at = excluded.updated_at
                """,
                (
                    item_id,
                    role.value,
                    engine.value,
                    status.value,
                    attempts,
                    error[:4000],
                    now,
                ),
            )
            if exhausted:
                connection.execute(
                    """
                    UPDATE job_item
                    SET stage = ?, last_error = ?, lease_owner = NULL,
                        lease_until = NULL, heartbeat_at = NULL, updated_at = ?
                    WHERE id = ?
                    """,
                    (
                        JobItemStage.FAILED.value,
                        f"{engine.value}/{role.value}: {error}"[:4000],
                        now,
                        item_id,
                    ),
                )
                self._apply_import_item_transition(
                    connection,
                    item["job_id"],
                    item["stage"],
                    JobItemStage.FAILED.value,
                    now,
                )
            return not exhausted

    def get_engine_statuses(self, item_id: int) -> dict[tuple[CoverRole, OcrEngine], RunStatus]:
        rows = self.fetchall(
            """
            SELECT cover_role, engine_name, status
            FROM job_item_engine WHERE item_id = ?
            """,
            (item_id,),
        )
        return {
            (CoverRole(row["cover_role"]), OcrEngine(row["engine_name"])): RunStatus(row["status"])
            for row in rows
        }

    @staticmethod
    def _all_engines_complete(connection: sqlite3.Connection, item_id: int) -> bool:
        item = connection.execute(
            "SELECT * FROM job_item WHERE id = ?",
            (item_id,),
        ).fetchone()
        if item is None:
            return False
        active_roles = Database._active_cover_roles(item)
        placeholders = ", ".join("?" for _ in active_roles)
        row = connection.execute(
            f"""
            SELECT COUNT(*) AS completed
            FROM job_item_engine
            WHERE item_id = ? AND status = ?
              AND cover_role IN ({placeholders})
            """,
            (item_id, RunStatus.COMPLETED.value, *(role.value for role in active_roles)),
        ).fetchone()
        expected = len(REQUIRED_OCR_ENGINES) * len(active_roles)
        return row is not None and int(row["completed"]) == expected

    @staticmethod
    def _active_cover_roles(item: sqlite3.Row) -> tuple[CoverRole, ...]:
        roles = [CoverRole.FRONT]
        if item["front_inside_path"] is not None:
            roles.append(CoverRole.FRONT_INSIDE)
        if item["back_inside_path"] is not None:
            roles.append(CoverRole.BACK_INSIDE)
        roles.append(CoverRole.BACK)
        return tuple(roles)

    @staticmethod
    def _assert_active_cover_role(item: sqlite3.Row, role: CoverRole) -> None:
        if role not in Database._active_cover_roles(item):
            raise StateConflictError(f"{role.value} yüzü bu iş öğesinde tanımlı değil")

    def job_progress(self, job_id: str) -> dict[str, Any]:
        job = self.get_import_job(job_id)
        if job is None:
            raise KeyError(f"İçe aktarma işi bulunamadı: {job_id}")
        stage_rows = self.fetchall(
            """
            SELECT stage, COUNT(*) AS count
            FROM job_item WHERE job_id = ? GROUP BY stage
            """,
            (job_id,),
        )
        engine_rows = self.fetchall(
            """
            SELECT jie.engine_name, jie.status, COUNT(*) AS count
            FROM job_item_engine AS jie
            JOIN job_item AS ji ON ji.id = jie.item_id
            WHERE ji.job_id = ?
            GROUP BY jie.engine_name, jie.status
            """,
            (job_id,),
        )
        return {
            "job": job,
            "stages": {row["stage"]: int(row["count"]) for row in stage_rows},
            "engines": {
                f"{row['engine_name']}:{row['status']}": int(row["count"]) for row in engine_rows
            },
        }

    def job_location_summary(self, job_id: str) -> list[dict[str, Any]]:
        """İşin kitaplarını dolaba göre sayar (dolapsızlar için ad boştur).

        Kataloglanmış öğe için nüshanın GERÇEK konumu okunur; iş dolabı sonradan
        değişse bile rafta duran kitap yeni dolapta sayılmaz.  Kataloglanmamış
        öğeler ise gidecekleri dolapta, yani niyet değerinde görünür.
        """

        rows = self.fetchall(
            """
            SELECT
                CASE WHEN ji.edition_id IS NOT NULL THEN (
                        SELECT c.location FROM copy AS c
                        WHERE c.edition_id = ji.edition_id
                        ORDER BY c.id LIMIT 1
                     )
                     ELSE COALESCE(ji.location, ij.location)
                END AS shelf_name,
                COUNT(*) AS count
            FROM job_item AS ji
            JOIN import_job AS ij ON ij.id = ji.job_id
            WHERE ji.job_id = ?
            -- Takma ad yerine ifadenin kendisi: ``import_job.name`` sütunu
            -- takma adı gölgeleyip işi ada göre gruplardı.
            GROUP BY shelf_name
            ORDER BY count DESC, shelf_name
            """,
            (job_id,),
        )
        return [{"name": row["shelf_name"], "count": int(row["count"])} for row in rows]

    def review_labels(self, *, limit: int | None = None) -> list[dict[str, Any]]:
        """Return the proposal each reviewed field judged, one row per field.

        Exactly one row per reviewed field matters.  The extractor writes an
        observation for every candidate it considered — the front-cover title
        and the colophon fallback, for instance — but the pipeline only ever
        proposed the winner.  Joining on ``(edition_id, field_path)`` alone
        would turn one review decision into several samples, inflating the
        count towards the trust threshold and feeding the curve losing
        candidates the user was never shown.

        The winner is ``resolved_field.observation_id`` when it survives; a user
        edit clears it, and then the highest-confidence observation is the one
        the resolver would have picked.  Only user-locked fields are used:
        judging model output with other model output calibrates nothing.
        """

        clause = "LIMIT ?" if limit is not None else ""
        parameters: tuple[Any, ...] = (int(limit),) if limit is not None else ()
        rows = self.fetchall(
            f"""
            SELECT rf.field_path AS field_path,
                   fo.confidence AS raw_confidence,
                   fo.normalized_value AS observed_value,
                   rf.value AS confirmed_value,
                   fo.source_polygon_json AS source_polygon_json,
                   fo.engine_evidence_json AS engine_evidence_json
            FROM resolved_field AS rf
            JOIN field_observation AS fo
              ON fo.id = COALESCE(
                     rf.observation_id,
                     (
                         SELECT best.id FROM field_observation AS best
                         WHERE best.edition_id = rf.edition_id
                           AND best.field_path = rf.field_path
                         ORDER BY best.confidence DESC, best.id DESC
                         LIMIT 1
                     )
                 )
            WHERE rf.user_locked = 1
            ORDER BY rf.edition_id, rf.field_path
            {clause}
            """,
            parameters,
        )
        labels: list[dict[str, Any]] = []
        for row in rows:
            engine_evidence = row["engine_evidence_json"]
            try:
                engines = tuple(
                    str(item) for item in json.loads(engine_evidence or "[]") if item is not None
                )
            except (TypeError, ValueError):
                engines = ()
            labels.append(
                {
                    "field_path": row["field_path"],
                    "raw_confidence": row["raw_confidence"],
                    "observed_value": row["observed_value"],
                    "confirmed_value": row["confirmed_value"],
                    "has_visual_provenance": bool(row["source_polygon_json"]),
                    "engine_ids": engines,
                }
            )
        return labels

    def review_label_count(self) -> int:
        """Count reviewed fields without materialising them.

        The review screen shows this after every saved record, and a catalogue
        with ten thousand books holds hundreds of thousands of observations —
        far too many to build objects for just to display a number.
        """

        row = self.fetchone(
            """
            SELECT COUNT(*) AS total
            FROM resolved_field AS rf
            WHERE rf.user_locked = 1
              AND EXISTS (
                  SELECT 1 FROM field_observation AS fo
                  WHERE fo.edition_id = rf.edition_id
                    AND fo.field_path = rf.field_path
              )
            """
        )
        return int(row["total"]) if row else 0

    def engine_durations(self, *, job_id: str | None = None) -> dict[str, Any]:
        """Summarise recorded per-engine OCR durations.

        Every engine run already stores ``duration_ms``, so throughput needs no
        new instrumentation — only reading what the queue wrote.  Percentiles
        come from the raw rows because a mean hides the model-load spike that
        dominates the first call of each engine.
        """

        clause = ""
        parameters: tuple[Any, ...] = ()
        if job_id is not None:
            clause = """
            WHERE oer.image_asset_id IN (
                SELECT ia.id FROM image_asset AS ia
                JOIN job_item AS ji ON ji.id = ia.item_id
                WHERE ji.job_id = ?
            )
            """
            parameters = (job_id,)
        rows = self.fetchall(
            f"""
            SELECT oer.engine_name, oer.status, oer.duration_ms
            FROM ocr_engine_run AS oer
            {clause}
            ORDER BY oer.engine_name
            """,
            parameters,
        )
        by_engine: dict[str, list[int]] = {}
        failures: Counter[str] = Counter()
        for row in rows:
            engine_name = str(row["engine_name"])
            if row["status"] != "completed":
                failures[engine_name] += 1
                continue
            duration = row["duration_ms"]
            if duration is not None:
                by_engine.setdefault(engine_name, []).append(int(duration))
        engines = {
            engine_name: _duration_summary(durations, failures[engine_name])
            for engine_name, durations in sorted(by_engine.items())
        }
        surfaces = self.fetchone(
            f"""
            SELECT COUNT(DISTINCT oer.image_asset_id) AS surfaces
            FROM ocr_engine_run AS oer
            {clause}
            """,
            parameters,
        )
        return {
            "engines": engines,
            "surfaces_measured": int(surfaces["surfaces"]) if surfaces else 0,
            "mean_ms_per_surface": sum(item["mean_ms"] for item in engines.values()),
        }

    @staticmethod
    def _apply_import_item_transition(
        connection: sqlite3.Connection,
        job_id: str,
        previous_stage: str,
        new_stage: str,
        now: str,
    ) -> None:
        before = _terminal_count_vector(previous_stage)
        after = _terminal_count_vector(new_stage)
        Database._apply_import_job_count_delta(
            connection,
            job_id,
            successful_delta=after[0] - before[0],
            failed_delta=after[1] - before[1],
            review_delta=after[2] - before[2],
            now=now,
        )

    @staticmethod
    def _apply_import_job_count_delta(
        connection: sqlite3.Connection,
        job_id: str,
        *,
        successful_delta: int = 0,
        failed_delta: int = 0,
        review_delta: int = 0,
        now: str,
    ) -> None:
        """Apply one O(1) import-item counter delta inside its state transaction."""

        if not (successful_delta or failed_delta or review_delta):
            return
        job = connection.execute(
            """
            UPDATE import_job
            SET successful_items = successful_items + ?,
                failed_items = failed_items + ?,
                review_items = review_items + ?,
                updated_at = ?
            WHERE id = ?
            RETURNING total_items, successful_items, failed_items, review_items, status
            """,
            (successful_delta, failed_delta, review_delta, now, job_id),
        ).fetchone()
        if job is None:
            return
        successful = int(job["successful_items"])
        failed = int(job["failed_items"])
        review = int(job["review_items"])
        total = int(job["total_items"])
        terminal = successful + failed + review
        if min(successful, failed, review) < 0 or terminal > total:
            raise DatabaseError(f"İçe aktarma sayaçları tutarsız: {job_id}")
        current = ImportJobStatus(job["status"])
        if current != ImportJobStatus.CANCELLED and total > 0 and terminal == total:
            status = (
                ImportJobStatus.COMPLETED_WITH_ERRORS
                if failed
                else ImportJobStatus.COMPLETED
            )
            connection.execute(
                """
                UPDATE import_job
                SET status = ?, finished_at = COALESCE(finished_at, ?), updated_at = ?
                WHERE id = ?
                """,
                (status.value, now, now, job_id),
            )

    def reconcile_job_counts(self, job_id: str) -> ImportJob:
        """Explicit repair path; normal transitions must use constant-time deltas."""

        now = _now_text()
        with self.transaction(immediate=True) as connection:
            if (
                connection.execute("SELECT 1 FROM import_job WHERE id = ?", (job_id,)).fetchone()
                is None
            ):
                raise KeyError(f"İçe aktarma işi bulunamadı: {job_id}")
            self._reconcile_job_counts(connection, job_id, now)
            updated = connection.execute(
                "SELECT * FROM import_job WHERE id = ?", (job_id,)
            ).fetchone()
            assert updated is not None
            return _row_to_job(updated)

    @staticmethod
    def _reconcile_job_counts(
        connection: sqlite3.Connection, job_id: str, now: str
    ) -> None:
        """Rebuild counters from rows for migrations/manual integrity repair only."""

        counts = connection.execute(
            """
            SELECT
                SUM(CASE WHEN stage = ? THEN 1 ELSE 0 END) AS successful,
                SUM(CASE WHEN stage IN (?, ?) THEN 1 ELSE 0 END) AS failed,
                SUM(CASE WHEN stage = ? THEN 1 ELSE 0 END) AS review,
                COUNT(*) AS total
            FROM job_item WHERE job_id = ?
            """,
            (
                JobItemStage.COMPLETED.value,
                JobItemStage.FAILED.value,
                JobItemStage.CANCELLED.value,
                JobItemStage.REVIEW.value,
                job_id,
            ),
        ).fetchone()
        assert counts is not None
        successful = int(counts["successful"] or 0)
        failed = int(counts["failed"] or 0)
        review = int(counts["review"] or 0)
        total = int(counts["total"] or 0)
        terminal = successful + failed + review
        job = connection.execute(
            "SELECT status, finished_at FROM import_job WHERE id = ?", (job_id,)
        ).fetchone()
        if job is None:
            return
        current = ImportJobStatus(job["status"])
        status = current.value
        finished_at = job["finished_at"]
        if current == ImportJobStatus.CANCELLED:
            finished_at = finished_at or now
        elif total > 0 and terminal == total:
            status = (
                ImportJobStatus.COMPLETED_WITH_ERRORS.value
                if failed
                else ImportJobStatus.COMPLETED.value
            )
            finished_at = finished_at or now
        elif current in {
            ImportJobStatus.COMPLETED,
            ImportJobStatus.COMPLETED_WITH_ERRORS,
        }:
            status = ImportJobStatus.RUNNING.value
            finished_at = None
        connection.execute(
            """
            UPDATE import_job
            SET total_items = ?, successful_items = ?, failed_items = ?,
                review_items = ?, status = ?, finished_at = ?, updated_at = ?
            WHERE id = ?
            """,
            (
                total,
                successful,
                failed,
                review,
                status,
                finished_at,
                now,
                job_id,
            ),
        )


def _bounded_limit(value: int, *, maximum: int = 1000) -> int:
    return max(1, min(int(value), maximum))


def _percentile(sorted_values: Sequence[int], fraction: float) -> int:
    """Nearest-rank percentile; exact on the samples, no interpolation."""

    if not sorted_values:
        return 0
    rank = max(1, math.ceil(fraction * len(sorted_values)))
    return int(sorted_values[min(rank, len(sorted_values)) - 1])


def _duration_summary(durations: list[int], failures: int) -> dict[str, Any]:
    ordered = sorted(durations)
    total = sum(ordered)
    return {
        "runs": len(ordered),
        "failures": failures,
        "total_ms": total,
        "mean_ms": round(total / len(ordered)) if ordered else 0,
        "median_ms": _percentile(ordered, 0.5),
        "p95_ms": _percentile(ordered, 0.95),
        "max_ms": ordered[-1] if ordered else 0,
        # Spread, not model-load cost: while every invocation reloads its model,
        # each of these samples already contains one, so the gap between the
        # slowest and the typical run measures run-to-run variance. Separating
        # load from inference needs the sidecar to report them apart.
        "spread_ms": (ordered[-1] - _percentile(ordered, 0.5)) if ordered else 0,
    }


def _datetime_text(value: datetime) -> str:
    if value.tzinfo is None:
        value = value.replace(tzinfo=UTC)
    return value.astimezone(UTC).isoformat(timespec="microseconds")


def _now_text() -> str:
    return _datetime_text(datetime.now(UTC))


def _parse_datetime(value: str | None) -> datetime | None:
    return datetime.fromisoformat(value) if value else None


def _unicode_nocase(left: str, right: str) -> int:
    left_key = unicodedata.normalize("NFC", left).casefold()
    right_key = unicodedata.normalize("NFC", right).casefold()
    return (left_key > right_key) - (left_key < right_key)


def _row_to_voice_job(row: sqlite3.Row) -> VoiceJob:
    return VoiceJob(
        id=row["id"],
        name=row["name"],
        status=ImportJobStatus(row["status"]),
        phase=VoiceJobPhase(row["phase"]),
        source_audio_path=Path(row["source_audio_path"]),
        source_sha256=row["source_sha256"],
        canonical_wav_path=(Path(row["canonical_wav_path"]) if row["canonical_wav_path"] else None),
        segmentation_version=int(row["segmentation_version"]),
        single_book=bool(row["single_book"]),
        total_items=int(row["total_items"]),
        successful_items=int(row["successful_items"]),
        failed_items=int(row["failed_items"]),
        review_items=int(row["review_items"]),
        idempotency_key=row["idempotency_key"],
        config_hash=row["config_hash"],
        lease_owner=row["lease_owner"],
        lease_until=_parse_datetime(row["lease_until"]),
        heartbeat_at=_parse_datetime(row["heartbeat_at"]),
        last_error=row["last_error"],
        created_at=_parse_datetime(row["created_at"]),
        updated_at=_parse_datetime(row["updated_at"]),
        started_at=_parse_datetime(row["started_at"]),
        finished_at=_parse_datetime(row["finished_at"]),
        language=row["language"],
    )


def _row_to_voice_item(row: sqlite3.Row) -> VoiceItem:
    return VoiceItem(
        id=int(row["id"]),
        job_id=row["job_id"],
        item_key=row["item_key"],
        ordinal=int(row["ordinal"]),
        start_sample=int(row["start_sample"]),
        end_sample=int(row["end_sample"]),
        transcript_json=row["transcript_json"],
        stage=VoiceItemStage(row["stage"]),
        retry_count=int(row["retry_count"]),
        claims_json=row["claims_json"],
        lease_owner=row["lease_owner"],
        lease_until=_parse_datetime(row["lease_until"]),
        heartbeat_at=_parse_datetime(row["heartbeat_at"]),
        last_error=row["last_error"],
        edition_id=row["edition_id"],
        review_reasons_json=row["review_reasons_json"],
        created_at=_parse_datetime(row["created_at"]),
        updated_at=_parse_datetime(row["updated_at"]),
    )


def _row_to_voice_alias(row: sqlite3.Row) -> VoiceAlias:
    return VoiceAlias(
        id=int(row["id"]),
        heard=row["heard"],
        canonical=row["canonical"],
        field_scope=row["field_scope"],
        created_at=_parse_datetime(row["created_at"]),
    )


def _row_to_job(row: sqlite3.Row) -> ImportJob:
    return ImportJob(
        id=row["id"],
        name=row["name"],
        status=ImportJobStatus(row["status"]),
        storage_mode=StorageMode(row["storage_mode"]),
        total_items=int(row["total_items"]),
        successful_items=int(row["successful_items"]),
        failed_items=int(row["failed_items"]),
        review_items=int(row["review_items"]),
        idempotency_key=row["idempotency_key"],
        config_hash=row["config_hash"],
        location=row["location"],
        created_at=_parse_datetime(row["created_at"]),
        updated_at=_parse_datetime(row["updated_at"]),
        started_at=_parse_datetime(row["started_at"]),
        finished_at=_parse_datetime(row["finished_at"]),
    )


def _row_to_job_item(row: sqlite3.Row) -> JobItem:
    return JobItem(
        id=int(row["id"]),
        job_id=row["job_id"],
        pair_key=row["pair_key"],
        front_path=Path(row["front_path"]),
        back_path=Path(row["back_path"]),
        front_inside_path=(Path(row["front_inside_path"]) if row["front_inside_path"] else None),
        back_inside_path=(Path(row["back_inside_path"]) if row["back_inside_path"] else None),
        pairing_confidence=float(row["pairing_confidence"]),
        pairing_basis=row["pairing_basis"],
        needs_pair_review=bool(row["needs_pair_review"]),
        stage=JobItemStage(row["stage"]),
        retry_count=int(row["retry_count"]),
        lease_owner=row["lease_owner"],
        lease_until=_parse_datetime(row["lease_until"]),
        heartbeat_at=_parse_datetime(row["heartbeat_at"]),
        last_error=row["last_error"],
        edition_id=row["edition_id"],
        location=row["location"],
        created_at=_parse_datetime(row["created_at"]),
        updated_at=_parse_datetime(row["updated_at"]),
    )
