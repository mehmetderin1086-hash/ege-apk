"""Bildirim merkezi: dedupe_key idempotency, okundu/dismiss, badge sayısı,
DailyMaintenance'ın günde bir çalışan gecikme taraması."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from pathlib import Path

import pytest

from kitapkatalog.catalog import Catalog
from kitapkatalog.database import Database
from kitapkatalog.domain import BookInput
from kitapkatalog.loans import Loans
from kitapkatalog.maintenance import DailyMaintenance
from kitapkatalog.members import Members
from kitapkatalog.notifications import Notifications
from kitapkatalog.settings import AppSettings

NOW = datetime(2026, 3, 10, 9, 0, tzinfo=UTC)


@pytest.fixture()
def env(tmp_path: Path):
    database = Database(tmp_path / "catalog.sqlite3")
    catalog = Catalog(database)
    members = Members(database)
    settings = AppSettings(database)
    loans = Loans(database, settings)
    notifications = Notifications(database)
    return database, catalog, members, settings, loans, notifications


class TestNotificationsCrud:
    def test_dedupe_key_is_idempotent(self, env) -> None:
        _, _, _, _, _, notifications = env
        notifications.create(kind="test", title="Birinci", dedupe_key="dedupe-1", now=NOW)
        notifications.create(kind="test", title="İkinci (yutulmalı)", dedupe_key="dedupe-1", now=NOW)
        items, total = notifications.list()
        assert total == 1
        assert items[0]["title"] == "Birinci"

    def test_notifications_without_dedupe_key_can_repeat(self, env) -> None:
        _, _, _, _, _, notifications = env
        notifications.create(kind="test", title="A", now=NOW)
        notifications.create(kind="test", title="B", now=NOW)
        _, total = notifications.list()
        assert total == 2

    def test_mark_read_and_unread_filter(self, env) -> None:
        _, _, _, _, _, notifications = env
        notifications.create(kind="test", title="A", dedupe_key="k1", now=NOW)
        notifications.create(kind="test", title="B", dedupe_key="k2", now=NOW)
        items, _ = notifications.list(unread=True)
        assert len(items) == 2
        notifications.mark_read(items[0]["id"], now=NOW)
        unread_items, unread_total = notifications.list(unread=True)
        assert unread_total == 1
        assert unread_items[0]["id"] != items[0]["id"]

    def test_mark_read_is_idempotent_on_already_read(self, env) -> None:
        _, _, _, _, _, notifications = env
        notifications.create(kind="test", title="A", dedupe_key="k1", now=NOW)
        notification_id = notifications.list()[0][0]["id"]
        first = notifications.mark_read(notification_id, now=NOW)
        second = notifications.mark_read(notification_id, now=NOW + timedelta(hours=1))
        assert first["read_at"] == second["read_at"]

    def test_mark_all_read(self, env) -> None:
        _, _, _, _, _, notifications = env
        for index in range(3):
            notifications.create(kind="test", title=f"N{index}", dedupe_key=f"k{index}", now=NOW)
        updated = notifications.mark_all_read(now=NOW)
        assert updated == 3
        _, unread_total = notifications.list(unread=True)
        assert unread_total == 0

    def test_dismiss_removes_from_list_but_counts_stay_consistent(self, env) -> None:
        _, _, _, _, _, notifications = env
        notifications.create(kind="test", title="A", dedupe_key="k1", now=NOW)
        notification_id = notifications.list()[0][0]["id"]
        notifications.dismiss(notification_id, now=NOW)
        items, total = notifications.list()
        assert total == 0
        assert items == []
        assert notifications.unread_count() == 0

    def test_unknown_notification_raises_key_error(self, env) -> None:
        _, _, _, _, _, notifications = env
        with pytest.raises(KeyError):
            notifications.mark_read(999_999, now=NOW)
        with pytest.raises(KeyError):
            notifications.dismiss(999_999, now=NOW)


class TestBadgesUnreadCount:
    def test_badges_endpoint_reflects_unread_notification_count(self, tmp_path: Path) -> None:
        fastapi = pytest.importorskip("fastapi")  # noqa: F841
        from fastapi.testclient import TestClient

        from kitapkatalog.application import open_application
        from kitapkatalog.config import AppPaths
        from kitapkatalog.webapp.app import create_app

        paths = AppPaths(
            root=tmp_path,
            database=tmp_path / "catalog.sqlite3",
            assets=tmp_path / "assets",
            derivatives=tmp_path / "derivatives",
            ocr_raw=tmp_path / "ocr-raw",
            models=tmp_path / "models",
            exports=tmp_path / "exports",
            logs=tmp_path / "logs",
        )
        context = open_application(paths, enforce_offline=False)
        app = create_app(context)
        with TestClient(app, base_url="http://127.0.0.1") as client:
            client.get(f"/?token={app.state.web.token}", follow_redirects=False)
            assert client.get("/api/badges").json()["notifications"] == 0
            Notifications(app.state.web.database).create(
                kind="test", title="A", dedupe_key="k1", now=NOW
            )
            assert client.get("/api/badges").json()["notifications"] == 1

    def test_unread_count_matches_notifications_service(self, env) -> None:
        _, _, _, _, _, notifications = env
        notifications.create(kind="test", title="A", dedupe_key="k1", now=NOW)
        notifications.create(kind="test", title="B", dedupe_key="k2", now=NOW)
        assert notifications.unread_count() == 2
        item_id = notifications.list()[0][0]["id"]
        notifications.mark_read(item_id, now=NOW)
        assert notifications.unread_count() == 1


class TestNotificationsHttpRoutes:
    def test_list_read_read_all_dismiss(self, tmp_path: Path) -> None:
        fastapi = pytest.importorskip("fastapi")  # noqa: F841
        from fastapi.testclient import TestClient

        from kitapkatalog.application import open_application
        from kitapkatalog.config import AppPaths
        from kitapkatalog.webapp.app import create_app

        paths = AppPaths(
            root=tmp_path,
            database=tmp_path / "catalog.sqlite3",
            assets=tmp_path / "assets",
            derivatives=tmp_path / "derivatives",
            ocr_raw=tmp_path / "ocr-raw",
            models=tmp_path / "models",
            exports=tmp_path / "exports",
            logs=tmp_path / "logs",
        )
        context = open_application(paths, enforce_offline=False)
        app = create_app(context)
        with TestClient(app, base_url="http://127.0.0.1") as client:
            client.get(f"/?token={app.state.web.token}", follow_redirects=False)
            service = Notifications(app.state.web.database)
            service.create(kind="test", title="A", dedupe_key="k1", now=NOW)
            service.create(kind="test", title="B", dedupe_key="k2", now=NOW)

            listed = client.get("/api/notifications").json()
            assert listed["total"] == 2
            unread_only = client.get("/api/notifications?unread=true").json()
            assert unread_only["total"] == 2

            first_id = listed["items"][0]["id"]
            read = client.post(f"/api/notifications/{first_id}/read")
            assert read.status_code == 200
            assert read.json()["read_at"] is not None
            assert client.get("/api/notifications?unread=true").json()["total"] == 1

            read_all = client.post("/api/notifications/read-all")
            assert read_all.json()["updated"] == 1
            assert client.get("/api/notifications?unread=true").json()["total"] == 0

            dismissed = client.post(f"/api/notifications/{first_id}/dismiss")
            assert dismissed.status_code == 204
            assert client.get("/api/notifications").json()["total"] == 1

            missing = client.post("/api/notifications/999999/read")
            assert missing.status_code == 404


class TestDailyMaintenanceOverdueScan:
    def _setup(self, tmp_path: Path):
        database = Database(tmp_path / "catalog.sqlite3")
        catalog = Catalog(database)
        members = Members(database)
        settings = AppSettings(database)
        loans = Loans(database, settings)
        maintenance = DailyMaintenance(database, settings)
        return database, catalog, members, settings, loans, maintenance

    def test_run_creates_one_notification_per_overdue_member_per_day(self, tmp_path: Path) -> None:
        database, catalog, members, _, loans, maintenance = self._setup(tmp_path)
        member = members.add(
            member_type="student", school_number="1", first_name="Ayşe", last_name="A"
        )
        book_a = catalog.save_book(BookInput(title="Kitap A"))
        book_b = catalog.save_book(BookInput(title="Kitap B"))
        checkout_at = NOW - timedelta(days=40)
        loans.checkout(member.id, edition_id=book_a.edition_id, now=checkout_at)
        loans.checkout(member.id, edition_id=book_b.edition_id, now=checkout_at)

        result = maintenance.run(now=NOW)
        assert result["overdue_notified"] == 1  # tek üye, iki kitap -> tek bildirim

        notifications = database.fetchall(
            "SELECT * FROM notification WHERE kind = 'overdue'"
        )
        assert len(notifications) == 1
        assert notifications[0]["member_id"] == member.id
        assert notifications[0]["dedupe_key"] == f"overdue:{member.id}:{NOW.date().isoformat()}"

    def test_run_is_idempotent_within_the_same_day(self, tmp_path: Path) -> None:
        database, catalog, members, _, loans, maintenance = self._setup(tmp_path)
        member = members.add(
            member_type="student", school_number="1", first_name="Ayşe", last_name="A"
        )
        book = catalog.save_book(BookInput(title="Kitap"))
        loans.checkout(member.id, edition_id=book.edition_id, now=NOW - timedelta(days=40))

        maintenance.run(now=NOW)
        maintenance.run(now=NOW + timedelta(hours=2))  # aynı gün ikinci koşum
        notifications = database.fetchall(
            "SELECT * FROM notification WHERE kind = 'overdue'"
        )
        assert len(notifications) == 1

    def test_run_if_due_only_runs_once_per_day(self, tmp_path: Path) -> None:
        _, _, _, _, _, maintenance = self._setup(tmp_path)
        first = maintenance.run_if_due(now=NOW)
        assert first is not None
        second = maintenance.run_if_due(now=NOW + timedelta(hours=3))
        assert second is None
        third = maintenance.run_if_due(now=NOW + timedelta(days=1))
        assert third is not None

    def test_run_advances_expired_holds(self, tmp_path: Path) -> None:
        _, catalog, members, settings, loans, maintenance = self._setup(tmp_path)
        a = members.add(member_type="student", school_number="1", first_name="A", last_name="A")
        b = members.add(member_type="student", school_number="2", first_name="B", last_name="B")
        book = catalog.save_book(BookInput(title="Rezervasyonlu Kitap"))
        loan = loans.checkout(a.id, edition_id=book.edition_id, now=NOW)
        loans.create_hold(edition_id=book.edition_id, member_id=b.id, now=NOW)
        loans.return_loan(loan.id, now=NOW)
        after_expiry = NOW + timedelta(days=settings.hold_pickup_days + 1)
        result = maintenance.run(now=after_expiry)
        assert result["holds_advanced"] == 1
