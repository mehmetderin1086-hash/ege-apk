from __future__ import annotations

import os
import sqlite3
from collections.abc import Generator
from datetime import UTC, datetime
from pathlib import Path
from typing import TYPE_CHECKING, Any

from sqlalchemy import Engine, create_engine, event, inspect, text

if TYPE_CHECKING:
    from alembic.config import Config as AlembicConfig
from sqlalchemy.orm import Session, sessionmaker

from bioprof.config import Settings
from bioprof.db.models import Base

BASLANGIC_REVIZYONU = "0001_baseline"
_YEDEK_SAKLAMA_ADEDI = 5


class Database:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.engine: Engine = create_engine(
            settings.db_url,
            connect_args=(
                {"check_same_thread": False} if settings.db_url.startswith("sqlite") else {}
            ),
            pool_pre_ping=True,
        )
        if settings.db_url.startswith("sqlite"):
            event.listen(self.engine, "connect", self._configure_sqlite)
        self.session_factory = sessionmaker(
            bind=self.engine, class_=Session, expire_on_commit=False
        )

    @staticmethod
    def _configure_sqlite(dbapi_connection: object, _connection_record: object) -> None:
        cursor = dbapi_connection.cursor()  # type: ignore[attr-defined]
        cursor.execute("PRAGMA foreign_keys=ON")
        cursor.execute("PRAGMA journal_mode=WAL")
        cursor.execute("PRAGMA synchronous=NORMAL")
        cursor.close()

    def initialize(self) -> None:
        self._migrate()
        # Güvenlik ağı: migration zinciri bir tabloyu ıskalarsa uygulama yine açılır;
        # mevcut tabloları ALTER etmez, yalnız eksik olanı yaratır.
        Base.metadata.create_all(self.engine)
        self._initialize_fts()
        self._secure_sqlite_files()

    def _alembic_config(self) -> AlembicConfig:
        from alembic.config import Config as AlembicConfig

        cfg = AlembicConfig()
        cfg.set_main_option(
            "script_location", str(Path(__file__).resolve().parent / "migrations")
        )
        return cfg

    def _migrate(self) -> None:
        from alembic import command
        from alembic.runtime.migration import MigrationContext
        from alembic.script import ScriptDirectory

        cfg = self._alembic_config()
        script = ScriptDirectory.from_config(cfg)
        head = script.get_current_head()
        if head is None:
            return
        with self.engine.connect() as connection:
            current = MigrationContext.configure(connection).get_current_revision()
            eski_kurulum = current is None and inspect(connection).has_table("notebooks")
        if current == head:
            return
        if current is not None or eski_kurulum:
            # Bekleyen revizyon dolu bir DB'ye uygulanacak: önce anlık görüntü.
            self._migration_oncesi_yedek(head)
        # Migration'lar uygulama engine'inde DEĞİL, DDL'i gerçekten transaction'a
        # alan özel bir engine'de koşar: pysqlite açık BEGIN yoksa DDL'i anında
        # commit'ler; yarım kalan bir zincir "tablo var ama alembic_version eski"
        # durumunda her açılışta patlayan bir DB bırakırdı.
        motor = self._migration_motoru()
        try:
            with motor.begin() as connection:
                cfg.attributes["connection"] = connection
                if eski_kurulum:
                    # create_all ile kurulmuş DB baseline şemasına zaten sahip.
                    command.stamp(cfg, BASLANGIC_REVIZYONU)
                command.upgrade(cfg, "head")
        finally:
            motor.dispose()

    def _migration_motoru(self) -> Engine:
        """Transactional-DDL engine'i: BEGIN elle yayılır (SQLAlchemy pysqlite reçetesi)."""
        motor = create_engine(
            self.settings.db_url,
            connect_args=(
                {"check_same_thread": False}
                if self.settings.db_url.startswith("sqlite")
                else {}
            ),
        )
        if motor.url.get_backend_name() == "sqlite":

            @event.listens_for(motor, "connect")
            def _baglaninca(dbapi_connection: object, _record: object) -> None:
                # isolation_level=None: pysqlite'ın örtük (yalnız DML'de açılan)
                # transaction yönetimi kapanır; BEGIN aşağıda elle yayılır.
                dbapi_connection.isolation_level = None  # type: ignore[attr-defined]
                cursor = dbapi_connection.cursor()  # type: ignore[attr-defined]
                cursor.execute("PRAGMA foreign_keys=ON")
                cursor.close()

            @event.listens_for(motor, "begin")
            def _baslarken(conn: Any) -> None:
                conn.exec_driver_sql("BEGIN")

        return motor

    def _migration_oncesi_yedek(self, head: str) -> None:
        """WAL-güvenli salt-DB yedeği (sqlite3 backup API; dosya kopyası DEĞİL)."""
        if self.engine.url.get_backend_name() != "sqlite":
            return
        database = self.engine.url.database
        if not database or database == ":memory:":
            return
        kaynak_yolu = Path(database).expanduser()
        if not kaynak_yolu.exists():
            return
        yedek_dizini = kaynak_yolu.parent / "backups"
        yedek_dizini.mkdir(parents=True, exist_ok=True)
        yedek_dizini.chmod(0o700)
        an = datetime.now(UTC).strftime("%Y%m%d-%H%M%S")
        hedef = yedek_dizini / f"bioprof-oncesi-{head[:20]}-{an}.sqlite3"
        kaynak = sqlite3.connect(str(kaynak_yolu))
        try:
            yedek = sqlite3.connect(str(hedef))
            try:
                kaynak.backup(yedek)
            finally:
                yedek.close()
        finally:
            kaynak.close()
        hedef.chmod(0o600)
        # Kronolojik budama: ad sözlüksel sıralanırsa gelecekte hex revizyon
        # kimlikli en YENİ yedek listenin başına düşüp yanlışlıkla silinebilir.
        eskiler = sorted(
            yedek_dizini.glob("bioprof-oncesi-*.sqlite3"),
            key=lambda yol: yol.stat().st_mtime,
        )
        for artik in eskiler[:-_YEDEK_SAKLAMA_ADEDI]:
            artik.unlink()

    def _secure_sqlite_files(self) -> None:
        if self.engine.url.get_backend_name() != "sqlite":
            return
        database = self.engine.url.database
        if not database or database == ":memory:":
            return
        path = Path(database).expanduser()
        for candidate in (path, Path(f"{path}-wal"), Path(f"{path}-shm")):
            if candidate.exists():
                os.chmod(candidate, 0o600)

    def _initialize_fts(self) -> None:
        if not self.settings.db_url.startswith("sqlite"):
            return
        with self.engine.begin() as connection:
            connection.execute(
                text(
                    """
                    CREATE VIRTUAL TABLE IF NOT EXISTS chunk_fts USING fts5(
                        chunk_id UNINDEXED,
                        source_id UNINDEXED,
                        notebook_id UNINDEXED,
                        title,
                        section,
                        text,
                        tokenize='unicode61 remove_diacritics 2'
                    )
                    """
                )
            )

    def session(self) -> Session:
        return self.session_factory()

    def dependency(self) -> Generator[Session, None, None]:
        session = self.session_factory()
        try:
            yield session
        finally:
            session.close()
