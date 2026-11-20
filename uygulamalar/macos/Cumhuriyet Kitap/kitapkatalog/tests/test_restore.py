"""Geri yükleme: hazırlık doğrulaması, onay, açılışta atomik değişim.

Senaryolar Codex çapraz değerlendirmesindeki çökme pencerelerini kapsar:
idempotan yeniden koşum, kilit ertelemesi, bozuk hazırlık, canlı verinin
her dalda korunması.
"""

from __future__ import annotations

import errno
import json
import sqlite3
import stat
import zipfile
from contextlib import closing
from pathlib import Path
from types import SimpleNamespace

import pytest

from kitapkatalog.archive import ArchiveError, create_archive
from kitapkatalog.catalog import Catalog
from kitapkatalog.config import AppPaths
from kitapkatalog.database import Database, StateConflictError
from kitapkatalog.domain import BookInput
from kitapkatalog.restore import (
    MARKER_NAME,
    RESTORE_DIRNAME,
    AppLock,
    apply_pending_restore,
    cancel_pending,
    confirm_restore,
    pending_info,
    stage_archive,
)


@pytest.fixture()
def paths(tmp_path: Path) -> AppPaths:
    selected = AppPaths(
        root=tmp_path,
        database=tmp_path / "catalog.sqlite3",
        assets=tmp_path / "assets",
        derivatives=tmp_path / "derivatives",
        ocr_raw=tmp_path / "ocr-raw",
        models=tmp_path / "models",
        exports=tmp_path / "exports",
        logs=tmp_path / "logs",
    )
    selected.ensure()
    return selected


def _make_archive(
    tmp_path: Path,
    *,
    titles: tuple[str, ...] = ("Yedek Kitabı",),
    with_cover: bool = False,
    root_cover: bool = False,
    user_version: int | None = None,
) -> Path:
    source_root = tmp_path / "kaynak"
    source_root.mkdir(parents=True, exist_ok=True)
    db_path = source_root / "catalog.sqlite3"
    database = Database(db_path)
    catalog = Catalog(database)
    edition_ids = [catalog.save_book(BookInput(title=title)).edition_id for title in titles]
    cover_paths: list[Path] = []
    asset_root = source_root / "assets"
    if with_cover:
        cover = asset_root / ("on.jpg" if root_cover else "kapaklar/on.jpg")
        cover.parent.mkdir(parents=True, exist_ok=True)
        cover.write_bytes(b"jpegimsi veri")
        with database.transaction() as connection:
            connection.execute(
                "UPDATE edition SET front_path = ? WHERE id = ?",
                (str(cover), edition_ids[0]),
            )
        cover_paths.append(cover)
    if user_version is not None:
        with database.connection() as connection:
            connection.execute(f"PRAGMA user_version = {user_version}")
    database.close()
    info = create_archive(
        db_path,
        tmp_path / "yedek.kitaparsiv",
        asset_root=asset_root,
        cover_paths=cover_paths,
        include_covers=bool(cover_paths),
    )
    return info.path


def _titles(db_path: Path) -> set[str]:
    with closing(sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)) as connection:
        return {row[0] for row in connection.execute("SELECT title FROM edition")}


class TestStage:
    def test_stage_summary(self, paths: AppPaths, tmp_path: Path) -> None:
        archive = _make_archive(tmp_path, titles=("Bir", "İki"), with_cover=True)
        summary = stage_archive(archive, paths)
        assert summary.counts["edition"] == 2
        assert summary.counts["copy"] == 2
        assert summary.cover_count == 1
        assert summary.staging_id.startswith("hazirlik-")
        staged = paths.root / RESTORE_DIRNAME / summary.staging_id / "catalog/catalog.sqlite3"
        assert staged.is_file()

    def test_stage_rejects_newer_schema(self, paths: AppPaths, tmp_path: Path) -> None:
        archive = _make_archive(tmp_path, user_version=99)
        with pytest.raises(ArchiveError, match="daha yeni bir sürümle"):
            stage_archive(archive, paths)
        # Hazırlık artığı bırakmaz.
        leftovers = list((paths.root / RESTORE_DIRNAME).glob("hazirlik-*"))
        assert leftovers == []


class TestConfirm:
    def test_confirm_writes_marker_and_relocates(self, paths: AppPaths, tmp_path: Path) -> None:
        archive = _make_archive(tmp_path, with_cover=True)
        summary = stage_archive(archive, paths)
        result = confirm_restore(summary.staging_id, paths)
        assert result["pending"] is True
        assert result["relocation"]["rewritten"] == 1
        marker = json.loads(
            (paths.root / RESTORE_DIRNAME / MARKER_NAME).read_text(encoding="utf-8")
        )
        marker_path = paths.root / RESTORE_DIRNAME / MARKER_NAME
        assert marker["staging"] == summary.staging_id
        assert stat.S_IMODE(marker_path.stat().st_mode) == 0o600
        assert stat.S_IMODE(marker_path.parent.stat().st_mode) == 0o700
        staged = paths.root / RESTORE_DIRNAME / summary.staging_id / "catalog/catalog.sqlite3"
        # Temiz kapanış: WAL artığı yok; kapak yolu yeni ad alanına yazıldı.
        assert not Path(str(staged) + "-wal").exists()
        with closing(sqlite3.connect(f"file:{staged}?mode=ro", uri=True)) as connection:
            front = connection.execute(
                "SELECT front_path FROM edition WHERE front_path IS NOT NULL"
            ).fetchone()[0]
            assert f"geri-yukleme-{result['restore_id']}" in front
            assert front.endswith("kapaklar/on.jpg")

    def test_legacy_archive_without_path_provenance_keeps_standard_assets_cover(
        self, paths: AppPaths, tmp_path: Path
    ) -> None:
        archive_path = _make_archive(tmp_path, with_cover=True)
        with zipfile.ZipFile(archive_path) as source:
            payloads = {item.filename: source.read(item.filename) for item in source.infolist()}
        manifest = json.loads(payloads["manifest.json"])
        manifest.pop("cover_path_provenance")
        for cover in manifest["covers"]:
            cover.pop("source_path_fingerprint")
        payloads["manifest.json"] = json.dumps(manifest, ensure_ascii=False).encode("utf-8")
        with zipfile.ZipFile(archive_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            for member, payload in payloads.items():
                archive.writestr(member, payload)

        summary = stage_archive(archive_path, paths)
        result = confirm_restore(summary.staging_id, paths)

        assert result["relocation"] == {"rewritten": 1, "unmatched": 0, "cleared": 0}

    def test_second_confirm_conflicts(self, paths: AppPaths, tmp_path: Path) -> None:
        first = stage_archive(_make_archive(tmp_path), paths)
        confirm_restore(first.staging_id, paths)
        second = stage_archive(_make_archive(tmp_path / "b"), paths)
        with pytest.raises(StateConflictError, match="bekleyen"):
            confirm_restore(second.staging_id, paths)

    def test_cancel_pending(self, paths: AppPaths, tmp_path: Path) -> None:
        summary = stage_archive(_make_archive(tmp_path), paths)
        confirm_restore(summary.staging_id, paths)
        assert cancel_pending(paths) is True
        assert pending_info(paths)["pending"] is None
        assert not (paths.root / RESTORE_DIRNAME / summary.staging_id).exists()
        assert cancel_pending(paths) is False

    def test_root_level_managed_cover_survives_full_restore(
        self, paths: AppPaths, tmp_path: Path
    ) -> None:
        archive = _make_archive(tmp_path, with_cover=True, root_cover=True)
        summary = stage_archive(archive, paths)
        confirmed = confirm_restore(summary.staging_id, paths)
        assert confirmed["relocation"] == {"rewritten": 1, "unmatched": 0, "cleared": 0}

        applied = apply_pending_restore(paths, AppLock(paths))
        assert applied is not None and applied["status"] == "applied"
        with closing(sqlite3.connect(paths.database)) as connection:
            restored_path = connection.execute(
                "SELECT front_path FROM edition WHERE front_path IS NOT NULL"
            ).fetchone()[0]
        assert Path(restored_path).name == "on.jpg"
        assert Path(restored_path).read_bytes() == b"jpegimsi veri"
        assert stat.S_IMODE(Path(restored_path).parent.stat().st_mode) == 0o700
        assert stat.S_IMODE(Path(restored_path).stat().st_mode) == 0o600


def _prepare_pending(paths: AppPaths, tmp_path: Path, **kwargs) -> dict:
    summary = stage_archive(_make_archive(tmp_path, **kwargs), paths)
    return confirm_restore(summary.staging_id, paths)


class TestCollectCoverPaths:
    def test_includes_image_asset_managed_paths(self, paths: AppPaths) -> None:
        from kitapkatalog.restore import collect_cover_paths

        database = Database(paths.database)
        catalog = Catalog(database)
        record = catalog.save_book(BookInput(title="Görselli"))
        cover = paths.assets / "on.jpg"
        cover.write_bytes(b"a")
        managed = paths.assets / "yonetilen.jpg"
        managed.write_bytes(b"b")
        outside = paths.root / "disarida.jpg"
        outside.write_bytes(b"c")
        with database.transaction() as connection:
            connection.execute(
                "UPDATE edition SET front_path = ? WHERE id = ?",
                (str(cover), record.edition_id),
            )
        database.close()
        # image_asset satırı: iş kuyruğu zincirini kurmamak için FK kapalı
        # ham bağlantıyla (collect_cover_paths yalnız managed_path okur).
        with closing(sqlite3.connect(paths.database)) as connection:
            connection.execute("PRAGMA foreign_keys = OFF")
            connection.execute(
                """
                INSERT INTO image_asset(item_id, edition_id, cover_role,
                                        source_path, managed_path,
                                        created_at, updated_at)
                VALUES (999, ?, 'front', 'kaynak', ?, '2026-01-01', '2026-01-01')
                """,
                (record.edition_id, str(managed)),
            )
            connection.commit()
        covers = collect_cover_paths(paths.database, paths.assets)
        assert cover in covers
        assert managed in covers  # image_asset.managed_path da toplanır
        assert outside not in covers  # varlık kökü dışı asla girmez


class TestApply:
    def test_happy_path_swaps_and_backs_up(self, paths: AppPaths, tmp_path: Path) -> None:
        # Canlı katalogda farklı bir kitap var; değişim sonrası arşiv içeriği gelir.
        live = Database(paths.database)
        Catalog(live).save_book(BookInput(title="Eski Canlı Kitap"))
        live.close()
        confirm = _prepare_pending(paths, tmp_path, with_cover=True)

        result = apply_pending_restore(paths, AppLock(paths))
        assert result is not None and result["status"] == "applied"
        assert _titles(paths.database) == {"Yedek Kitabı"}
        # Eski veri iki kopyada yaşıyor: ham kopya + kapaklı güvenlik arşivi.
        restore_dir = paths.root / RESTORE_DIRNAME
        previous = list(restore_dir.glob("onceki-catalog-*.sqlite3"))
        assert len(previous) == 1
        assert _titles(previous[0]) == {"Eski Canlı Kitap"}
        assert stat.S_IMODE(previous[0].stat().st_mode) == 0o600
        archives = list((paths.root / "yedekler").glob("geri-yukleme-oncesi-*.kitaparsiv"))
        assert len(archives) == 1
        assert stat.S_IMODE(archives[0].stat().st_mode) == 0o600
        # Kapak yeni ad alanında ve DB o yolu gösteriyor.
        cover_root = paths.assets / f"geri-yukleme-{confirm['restore_id']}"
        assert (cover_root / "kapaklar" / "on.jpg").is_file()
        with closing(sqlite3.connect(f"file:{paths.database}?mode=ro", uri=True)) as connection:
            front = connection.execute(
                "SELECT front_path FROM edition WHERE front_path IS NOT NULL"
            ).fetchone()[0]
            assert Path(front).is_file()
        # İşaret ve hazırlık temizlendi; sonuç yazıldı.
        assert not (restore_dir / MARKER_NAME).exists()
        assert pending_info(paths)["last_result"]["status"] == "applied"

    def test_no_live_database(self, paths: AppPaths, tmp_path: Path) -> None:
        # İlk kurulumda canlı DB olmayabilir; değişim yine çalışır.
        _prepare_pending(paths, tmp_path)
        result = apply_pending_restore(paths, AppLock(paths))
        assert result is not None and result["status"] == "applied"
        assert _titles(paths.database) == {"Yedek Kitabı"}

    def test_idempotent_rerun_after_crash(self, paths: AppPaths, tmp_path: Path) -> None:
        # 7-8 arası çökme: değişim uygulanmış ama işaret temizlenememiş.
        confirm = _prepare_pending(paths, tmp_path)
        marker_path = paths.root / RESTORE_DIRNAME / MARKER_NAME
        marker = json.loads(marker_path.read_text(encoding="utf-8"))
        first = apply_pending_restore(paths, AppLock(paths))
        assert first is not None and first["status"] == "applied"
        # İşareti geri koy (çökme simülasyonu) → yeniden koşum veri kaybetmez.
        marker_path.write_text(json.dumps(marker), encoding="utf-8")
        second = apply_pending_restore(paths, AppLock(paths))
        assert second is not None and second["status"] == "applied"
        assert second["restore_id"] == confirm["restore_id"]
        assert _titles(paths.database) == {"Yedek Kitabı"}

    def test_deferred_when_another_process_holds_lock(
        self, paths: AppPaths, tmp_path: Path
    ) -> None:
        _prepare_pending(paths, tmp_path)
        other = AppLock(paths)
        other.acquire_shared()  # açık bir uygulama sürecini taklit eder
        try:
            result = apply_pending_restore(paths, AppLock(paths))
        finally:
            other.release()
        assert result is not None and result["status"] == "deferred"
        # İşaret BEKLEMEDE kalır (başarısız değil); sonraki açılış uygular.
        assert (paths.root / RESTORE_DIRNAME / MARKER_NAME).is_file()
        applied = apply_pending_restore(paths, AppLock(paths))
        assert applied is not None and applied["status"] == "applied"

    def test_tampered_staging_fails_closed(self, paths: AppPaths, tmp_path: Path) -> None:
        live = Database(paths.database)
        Catalog(live).save_book(BookInput(title="Dokunulmamış"))
        live.close()
        confirm = _prepare_pending(paths, tmp_path)
        marker = json.loads(
            (paths.root / RESTORE_DIRNAME / MARKER_NAME).read_text(encoding="utf-8")
        )
        staged = paths.root / RESTORE_DIRNAME / marker["staging"] / "catalog/catalog.sqlite3"
        staged.write_bytes(b"bozuk veri")
        result = apply_pending_restore(paths, AppLock(paths))
        assert result is not None and result["status"] == "failed"
        # Canlı veri dokunulmamış; işaret başarısız'a taşınmış (tekrar denemez).
        assert _titles(paths.database) == {"Dokunulmamış"}
        assert not (paths.root / RESTORE_DIRNAME / MARKER_NAME).exists()
        assert list((paths.root / RESTORE_DIRNAME).glob("basarisiz-*.json"))
        assert confirm["restore_id"]

    def test_insufficient_apply_budget_stays_pending_without_partial_copy(
        self,
        paths: AppPaths,
        tmp_path: Path,
        monkeypatch: pytest.MonkeyPatch,
    ) -> None:
        live = Database(paths.database)
        Catalog(live).save_book(BookInput(title="Korunan Canlı"))
        live.close()
        _prepare_pending(paths, tmp_path)
        monkeypatch.setattr(
            "kitapkatalog.restore.shutil.disk_usage",
            lambda _path: SimpleNamespace(free=1),
        )

        result = apply_pending_restore(paths, AppLock(paths))

        assert result is not None and result["status"] == "deferred"
        restore_dir = paths.root / RESTORE_DIRNAME
        assert (restore_dir / MARKER_NAME).is_file()
        assert not list(restore_dir.glob("onceki-catalog-*.sqlite3"))
        assert not list(restore_dir.glob("basarisiz-*.json"))
        assert _titles(paths.database) == {"Korunan Canlı"}

    def test_enospc_cleans_partial_copy_and_keeps_restore_retryable(
        self,
        paths: AppPaths,
        tmp_path: Path,
        monkeypatch: pytest.MonkeyPatch,
    ) -> None:
        live = Database(paths.database)
        Catalog(live).save_book(BookInput(title="Korunan Canlı"))
        live.close()
        _prepare_pending(paths, tmp_path)

        def no_space(_source: Path, target: Path) -> None:
            target.write_bytes(b"kismi")
            Path(f"{target}-journal").write_bytes(b"kismi-journal")
            raise OSError(errno.ENOSPC, "No space left on device")

        monkeypatch.setattr("kitapkatalog.restore._checkpoint_and_copy", no_space)
        result = apply_pending_restore(paths, AppLock(paths))

        assert result is not None and result["status"] == "deferred"
        restore_dir = paths.root / RESTORE_DIRNAME
        assert (restore_dir / MARKER_NAME).is_file()
        assert not list(restore_dir.glob("onceki-catalog-*"))
        assert not list(restore_dir.glob("basarisiz-*.json"))
        assert _titles(paths.database) == {"Korunan Canlı"}

    def test_enospc_during_safety_archive_cleans_all_attempt_files(
        self,
        paths: AppPaths,
        tmp_path: Path,
        monkeypatch: pytest.MonkeyPatch,
    ) -> None:
        live = Database(paths.database)
        Catalog(live).save_book(BookInput(title="Korunan Canlı"))
        live.close()
        _prepare_pending(paths, tmp_path)

        def no_space(_database: Path, target: Path, **_kwargs: object) -> None:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(b"kismi-arsiv")
            try:
                raise OSError(errno.ENOSPC, "No space left on device")
            except OSError as error:
                raise ArchiveError("Arşiv oluşturulamadı") from error

        monkeypatch.setattr("kitapkatalog.archive.create_archive", no_space)
        result = apply_pending_restore(paths, AppLock(paths))

        assert result is not None and result["status"] == "deferred"
        restore_dir = paths.root / RESTORE_DIRNAME
        assert (restore_dir / MARKER_NAME).is_file()
        assert not list(restore_dir.glob("onceki-catalog-*"))
        assert not list((paths.root / "yedekler").glob("geri-yukleme-oncesi-*"))
        assert not list(restore_dir.glob("basarisiz-*.json"))
        assert _titles(paths.database) == {"Korunan Canlı"}


class TestOpenApplicationIntegration:
    def test_boot_applies_pending_restore(self, paths: AppPaths, tmp_path: Path) -> None:
        from kitapkatalog.application import open_application

        context = open_application(paths, enforce_offline=False)
        context.catalog.save_book(BookInput(title="Açık Uygulama Kitabı"))
        context.close()
        _prepare_pending(paths, tmp_path)

        restored = open_application(paths, enforce_offline=False)
        try:
            page = restored.catalog.search()
            titles = {record.title for record in page.items}
            assert titles == {"Yedek Kitabı"}
        finally:
            restored.close()

    def test_boot_defers_while_first_process_open(self, paths: AppPaths, tmp_path: Path) -> None:
        from kitapkatalog.application import open_application

        first = open_application(paths, enforce_offline=False)
        first.catalog.save_book(BookInput(title="Canlı Süreç Kitabı"))
        _prepare_pending(paths, tmp_path)
        # İlk süreç hâlâ açıkken ikinci açılış geri yüklemeyi ERTELER.
        second = open_application(paths, enforce_offline=False)
        try:
            titles = {record.title for record in second.catalog.search().items}
            assert titles == {"Canlı Süreç Kitabı"}
            assert (paths.root / RESTORE_DIRNAME / MARKER_NAME).is_file()
        finally:
            second.close()
            first.close()
