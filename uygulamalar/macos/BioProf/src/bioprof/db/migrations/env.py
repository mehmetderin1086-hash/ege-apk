"""Alembic ortamı.

FTS5 sanal tablosu (`chunk_fts`) ve gölge tabloları Alembic'in dışında yaşar:
kurulumları `Database._initialize_fts`'te idempotent DDL ile yapılır, autogenerate
karşılaştırmasına girerlerse her revizyonda "drop" önerisi üretirler.
"""

from __future__ import annotations

from alembic import context
from sqlalchemy import create_engine, pool
from sqlalchemy.engine import Connection

from bioprof.db.models import Base

target_metadata = Base.metadata

_FTS_TABLOLARI = {
    "chunk_fts",
    "chunk_fts_data",
    "chunk_fts_idx",
    "chunk_fts_content",
    "chunk_fts_docsize",
    "chunk_fts_config",
}


def include_object(
    obj: object, name: str | None, type_: str, reflected: bool, compare_to: object
) -> bool:
    return not (type_ == "table" and name in _FTS_TABLOLARI)


def _database_url() -> str:
    url = context.config.get_main_option("sqlalchemy.url")
    if url:
        return url
    from bioprof.config import Settings

    # Taze örnek: uygulamayla AYNI kaynakları okur (.env dahil) — CLI'dan
    # koşulan bir migration'ın yanlış (varsayılan) DB'ye gitmemesi buna bağlı.
    # lru_cache'li get_settings bilerek kullanılmıyor: ensure_directories yan
    # etkisi ve test izolasyonu.
    return Settings().db_url


def _configure_and_run(connection: Connection) -> None:
    context.configure(
        connection=connection,
        target_metadata=target_metadata,
        include_object=include_object,
        render_as_batch=True,  # SQLite ALTER kısıtları batch modunu şart koşar
    )
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_offline() -> None:
    context.configure(
        url=_database_url(),
        target_metadata=target_metadata,
        include_object=include_object,
        render_as_batch=True,
        literal_binds=True,
    )
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    connection = context.config.attributes.get("connection")
    if connection is not None:
        _configure_and_run(connection)
        return
    engine = create_engine(_database_url(), poolclass=pool.NullPool)
    try:
        with engine.connect() as conn:
            _configure_and_run(conn)
    finally:
        engine.dispose()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
