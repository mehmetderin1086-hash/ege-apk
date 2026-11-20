"""`kitapkatalog online-oneri` komutu testleri (ağ yok, sahte kaynaklar)."""

from __future__ import annotations

import argparse
from pathlib import Path

import pytest

from kitapkatalog import offline
from kitapkatalog.cli import _run_online_suggestions, main
from kitapkatalog.database import Database
from kitapkatalog.online_suggest import OnlineSuggestion

ISBN = "9789750718533"


@pytest.fixture(autouse=True)
def clean_guards():
    offline._uninstall_for_tests()
    offline._uninstall_allowlist_for_tests()
    yield
    offline._uninstall_for_tests()
    offline._uninstall_allowlist_for_tests()


def _args(**overrides) -> argparse.Namespace:
    defaults = {"isbn": [ISBN], "limit": 50}
    defaults.update(overrides)
    return argparse.Namespace(**defaults)


def test_refuses_to_run_without_allowlist_guard(tmp_path: Path) -> None:
    database = Database(tmp_path / "catalog.sqlite3")
    with pytest.raises(RuntimeError, match="allowlist"):
        _run_online_suggestions(database, _args())


def test_writes_pending_suggestions_and_preserves_dismissed(
    tmp_path: Path, monkeypatch
) -> None:
    database = Database(tmp_path / "catalog.sqlite3")
    offline.install_allowlist_guard({"openlibrary.org"})
    monkeypatch.setattr(
        "kitapkatalog.online_suggest.fetch_suggestions",
        lambda isbn13: [
            OnlineSuggestion(isbn13=isbn13, source="openlibrary", title="Kar")
        ],
    )

    result = _run_online_suggestions(database, _args())
    assert result["queried"] == 1 and result["suggestions_written"] == 1
    row = database.fetchone(
        "SELECT status, payload_json FROM external_suggestion WHERE isbn13 = ?", (ISBN,)
    )
    assert row is not None and row["status"] == "pending"
    assert "Kar" in row["payload_json"]

    # Kullanıcının reddettiği öneri, yeniden sorguda diriltilmez.
    with database.transaction() as connection:
        connection.execute(
            "UPDATE external_suggestion SET status = 'dismissed' WHERE isbn13 = ?",
            (ISBN,),
        )
    _run_online_suggestions(database, _args())
    row = database.fetchone(
        "SELECT status FROM external_suggestion WHERE isbn13 = ?", (ISBN,)
    )
    assert row is not None and row["status"] == "dismissed"


def test_unreachable_sources_are_counted_not_fatal(tmp_path: Path, monkeypatch) -> None:
    database = Database(tmp_path / "catalog.sqlite3")
    offline.install_allowlist_guard({"openlibrary.org"})
    monkeypatch.setattr(
        "kitapkatalog.online_suggest.fetch_suggestions", lambda isbn13: []
    )
    result = _run_online_suggestions(database, _args())
    assert result == {
        "queried": 1,
        "suggestions_written": 0,
        "unreachable": 1,
        "note": result["note"],
    }


def test_invalid_isbn_input_is_rejected(tmp_path: Path) -> None:
    database = Database(tmp_path / "catalog.sqlite3")
    offline.install_allowlist_guard({"openlibrary.org"})
    with pytest.raises(ValueError, match="13 haneli"):
        _run_online_suggestions(database, _args(isbn=["kitap"]))


class TestGuardSelection:
    """Ana giriş noktası yalnız online-oneri komutunda allowlist kurar."""

    def test_ordinary_commands_install_full_guard(self, monkeypatch, tmp_path) -> None:
        calls: list[str] = []
        monkeypatch.setattr(
            "kitapkatalog.cli.install_network_guard", lambda: calls.append("full")
        )
        monkeypatch.setattr(
            offline, "install_allowlist_guard", lambda hosts: calls.append("allowlist")
        )
        # Komut guard kurulumundan sonra hata verip 2 dönebilir; önemli olan seçim.
        main(["--database", str(tmp_path / "yeni.sqlite3"), "init"])
        assert calls == ["full"]

    def test_online_oneri_installs_allowlist_only(self, monkeypatch, tmp_path) -> None:
        calls: list[str] = []
        monkeypatch.setattr(
            "kitapkatalog.cli.install_network_guard", lambda: calls.append("full")
        )
        monkeypatch.setattr(
            offline, "install_allowlist_guard", lambda hosts: calls.append("allowlist")
        )
        main(
            [
                "--database",
                str(tmp_path / "yeni.sqlite3"),
                "online-oneri",
                "--isbn",
                ISBN,
            ]
        )
        assert "allowlist" in calls and "full" not in calls


def test_real_flow_end_to_end_with_actual_guard(tmp_path: Path, monkeypatch) -> None:
    """Codex bulgusu regresyonu: GERÇEK allowlist kilidi + open_application
    birlikte çalışabilmeli (tam kilit çakışması RuntimeError üretmemeli)."""

    monkeypatch.setattr(
        "kitapkatalog.online_suggest.fetch_suggestions",
        lambda isbn13: [
            OnlineSuggestion(isbn13=isbn13, source="openlibrary", title="Gerçek Akış")
        ],
    )
    exit_code = main(
        [
            "--json",
            "--database",
            str(tmp_path / "gercek.sqlite3"),
            "online-oneri",
            "--isbn",
            ISBN,
        ]
    )
    assert exit_code == 0
    database = Database(tmp_path / "gercek.sqlite3")
    row = database.fetchone(
        "SELECT status, payload_json FROM external_suggestion WHERE isbn13 = ?", (ISBN,)
    )
    assert row is not None and row["status"] == "pending"
    assert "Gerçek Akış" in row["payload_json"]
