"""Alembic bootstrap davranışı: boş DB, eski (create_all'lu) DB, yedek ve FTS."""

from __future__ import annotations

from pathlib import Path

import pytest
from sqlalchemy import inspect, text

from bioprof.config import Settings
from bioprof.db.models import Base, NotebookRecord
from bioprof.db.session import BASLANGIC_REVIZYONU, Database


def _ayarlar(tmp_path: Path) -> Settings:
    ayarlar = Settings(
        _env_file=None,
        data_dir=tmp_path / "veri",
        model_cache_dir=tmp_path / "modeller",
        use_qdrant=False,
        local_embeddings=False,
    )
    ayarlar.ensure_directories()
    return ayarlar


def _gecerli_revizyon(database: Database) -> str | None:
    with database.engine.connect() as baglanti:
        satir = baglanti.execute(text("SELECT version_num FROM alembic_version")).fetchone()
    return satir[0] if satir else None


# Gerçek "eski kurulum" yalnız baseline'daki 8 tabloya sahipti; güncel modellerle
# create_all çağırmak geleceğin tablolarını da yaratıp göç zinciriyle çakışır.
_ESKI_TABLO_ADLARI = (
    "notebooks",
    "sources",
    "chunks",
    "conversations",
    "messages",
    "jobs",
    "artifacts",
    "training_runs",
)


def _eski_kurulum_olustur(database: Database) -> None:
    tablolar = [Base.metadata.tables[ad] for ad in _ESKI_TABLO_ADLARI]
    Base.metadata.create_all(database.engine, tables=tablolar)


def test_bos_db_upgrade_semasi_modellerle_birebir(tmp_path: Path) -> None:
    database = Database(_ayarlar(tmp_path))
    database.initialize()

    denetci = inspect(database.engine)
    model_tablolari = set(Base.metadata.tables)
    db_tablolari = set(denetci.get_table_names())
    assert model_tablolari <= db_tablolari
    for tablo in model_tablolari:
        model_kolonlari = {kolon.name for kolon in Base.metadata.tables[tablo].columns}
        db_kolonlari = {kolon["name"] for kolon in denetci.get_columns(tablo)}
        assert model_kolonlari == db_kolonlari, f"{tablo} kolonları uyuşmuyor"
    assert _gecerli_revizyon(database) is not None


def test_eski_kurulum_stamp_edilir_ve_veri_korunur(tmp_path: Path) -> None:
    ayarlar = _ayarlar(tmp_path)
    eski = Database(ayarlar)
    _eski_kurulum_olustur(eski)
    with eski.session() as oturum:
        oturum.add(NotebookRecord(id="nb1", name="Hücre"))
        oturum.commit()
    eski.engine.dispose()

    yeni = Database(ayarlar)
    yeni.initialize()

    revizyon = _gecerli_revizyon(yeni)
    assert revizyon is not None
    with yeni.session() as oturum:
        kayit = oturum.get(NotebookRecord, "nb1")
        assert kayit is not None and kayit.name == "Hücre"


def test_eski_kurulum_migration_oncesi_yedek_alinir(tmp_path: Path) -> None:
    ayarlar = _ayarlar(tmp_path)
    eski = Database(ayarlar)
    _eski_kurulum_olustur(eski)
    with eski.session() as oturum:
        oturum.add(NotebookRecord(id="nb1", name="Yedeklenecek"))
        oturum.commit()
    eski.engine.dispose()

    yeni = Database(ayarlar)
    yeni.initialize()

    yedekler = list((ayarlar.data_dir / "backups").glob("bioprof-oncesi-*.sqlite3"))
    assert len(yedekler) == 1
    # Yedek gerçek bir DB ve veriyi içeriyor.
    import sqlite3

    with sqlite3.connect(yedekler[0]) as yedek:
        satir = yedek.execute("SELECT name FROM notebooks WHERE id='nb1'").fetchone()
    assert satir == ("Yedeklenecek",)


def test_guncel_db_ikinci_acilista_yedek_uretmez(tmp_path: Path) -> None:
    ayarlar = _ayarlar(tmp_path)
    Database(ayarlar).initialize()
    Database(ayarlar).initialize()
    yedek_dizini = ayarlar.data_dir / "backups"
    assert not yedek_dizini.exists() or not list(yedek_dizini.iterdir())


def test_fts_tablosu_migrationdan_sonra_da_kurulur(tmp_path: Path) -> None:
    database = Database(_ayarlar(tmp_path))
    database.initialize()
    with database.engine.connect() as baglanti:
        satir = baglanti.execute(
            text("SELECT name FROM sqlite_master WHERE name='chunk_fts'")
        ).fetchone()
    assert satir is not None


def test_db_zincirin_headine_oturur_ve_stamp_hedefi_zincirde(tmp_path: Path) -> None:
    from alembic.script import ScriptDirectory

    database = Database(_ayarlar(tmp_path))
    database.initialize()
    script = ScriptDirectory.from_config(database._alembic_config())
    assert _gecerli_revizyon(database) == script.get_current_head()
    # Stamp hedefi koddaki sabitle migration dosyasındaki revizyonun aynı olmasına dayanır.
    assert script.get_revision(BASLANGIC_REVIZYONU) is not None


@pytest.mark.parametrize("tablo", ["notebooks", "sources", "chunks", "artifacts"])
def test_temel_tablolar_kuruldu(tmp_path: Path, tablo: str) -> None:
    database = Database(_ayarlar(tmp_path))
    database.initialize()
    assert inspect(database.engine).has_table(tablo)


def test_migration_motoru_ddl_transactionaldir(tmp_path: Path) -> None:
    """pysqlite DDL'i autocommit'ler; migration motoru BEGIN'i elle yayarak
    yarım migration'ın kalıcı tablo bırakmasını engellemeli."""
    from sqlalchemy import text as sa_text

    database = Database(_ayarlar(tmp_path))
    motor = database._migration_motoru()
    try:
        with motor.connect() as baglanti:
            islem = baglanti.begin()
            baglanti.execute(sa_text("CREATE TABLE yarim_kalan (id INTEGER)"))
            islem.rollback()
        with motor.connect() as baglanti:
            satir = baglanti.execute(
                sa_text("SELECT name FROM sqlite_master WHERE name='yarim_kalan'")
            ).fetchone()
        assert satir is None, "DDL rollback'e rağmen kalıcı oldu — migration atomik değil"
    finally:
        motor.dispose()
