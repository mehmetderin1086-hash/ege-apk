"""Rezervasyon (hold) yaşam döngüsü: oluşturma kuralları, iade/checkout etkileşimi,
süre dolumu devri, iptal, idempotency ve hold_enabled kapısı."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from pathlib import Path

import pytest

from kitapkatalog.catalog import Catalog
from kitapkatalog.database import Database, StateConflictError
from kitapkatalog.domain import BookInput, CopyInput
from kitapkatalog.loans import Loans
from kitapkatalog.members import Members
from kitapkatalog.settings import AppSettings

NOW = datetime(2026, 3, 10, 9, 0, tzinfo=UTC)


@pytest.fixture()
def env(tmp_path: Path):
    database = Database(tmp_path / "catalog.sqlite3")
    catalog = Catalog(database)
    members = Members(database)
    settings = AppSettings(database)
    loans = Loans(database, settings)
    a = members.add(member_type="student", school_number="1", first_name="Ayşe", last_name="A")
    b = members.add(member_type="student", school_number="2", first_name="Berk", last_name="B")
    c = members.add(member_type="student", school_number="3", first_name="Can", last_name="C")
    book = catalog.save_book(
        BookInput(title="Tek Nüsha Kitap", copy=CopyInput(inventory_code="H-0001"))
    )
    return database, catalog, members, settings, loans, a, b, c, book


class TestCreateHold:
    def test_rejects_when_a_copy_is_available(self, env) -> None:
        *_, loans, a, _, _, book = env
        with pytest.raises(StateConflictError, match="Rafta"):
            loans.create_hold(edition_id=book.edition_id, member_id=a.id, now=NOW)

    def test_rejects_duplicate_active_hold(self, env) -> None:
        *_, loans, a, b, _, book = env
        loans.checkout(a.id, edition_id=book.edition_id, now=NOW)
        loans.create_hold(edition_id=book.edition_id, member_id=b.id, now=NOW)
        with pytest.raises(StateConflictError, match="zaten bir rezervasyonu"):
            loans.create_hold(edition_id=book.edition_id, member_id=b.id, now=NOW)

    def test_rejects_over_member_limit(self, env) -> None:
        _, catalog, _, settings, loans, a, b, _, book = env
        settings.set("hold_max_per_member", "1")
        loans.checkout(a.id, edition_id=book.edition_id, now=NOW)
        other_book = catalog.save_book(BookInput(title="Başka Kitap"))
        loans.checkout(a.id, edition_id=other_book.edition_id, now=NOW)
        loans.create_hold(edition_id=book.edition_id, member_id=b.id, now=NOW)
        with pytest.raises(StateConflictError, match="en fazla"):
            loans.create_hold(edition_id=other_book.edition_id, member_id=b.id, now=NOW)

    def test_unknown_edition_or_member_raise_key_error(self, env) -> None:
        *_, loans, a, _, _, book = env
        with pytest.raises(KeyError):
            loans.create_hold(edition_id=999_999, member_id=a.id, now=NOW)
        with pytest.raises(KeyError):
            loans.create_hold(edition_id=book.edition_id, member_id=999_999, now=NOW)

    def test_idempotent_request_id_replays_same_hold(self, env) -> None:
        *_, loans, a, b, _, book = env
        loans.checkout(a.id, edition_id=book.edition_id, now=NOW)
        first = loans.create_hold(
            edition_id=book.edition_id, member_id=b.id, request_id="req-hold-x", now=NOW
        )
        second = loans.create_hold(
            edition_id=book.edition_id, member_id=b.id, request_id="req-hold-x", now=NOW
        )
        assert first.id == second.id

    def test_request_id_reused_for_different_hold_is_rejected(self, env) -> None:
        _, catalog, _, _, loans, a, b, c, book = env
        loans.checkout(a.id, edition_id=book.edition_id, now=NOW)
        loans.create_hold(
            edition_id=book.edition_id, member_id=b.id, request_id="req-shared", now=NOW
        )
        other_book = catalog.save_book(BookInput(title="Farklı Kitap"))
        loans.checkout(a.id, edition_id=other_book.edition_id, now=NOW)
        with pytest.raises(StateConflictError, match="farklı bir rezervasyon"):
            loans.create_hold(
                edition_id=other_book.edition_id, member_id=c.id, request_id="req-shared", now=NOW
            )


class TestReturnPromotesHold:
    def test_return_marks_next_hold_ready_and_notifies(self, env) -> None:
        database, _, _, settings, loans, a, b, _, book = env
        loans.checkout(a.id, edition_id=book.edition_id, now=NOW)
        loans.create_hold(edition_id=book.edition_id, member_id=b.id, now=NOW)
        returned = loans.return_by_code("H-0001", now=NOW)
        assert returned.hold_ready is not None
        assert returned.hold_ready["member_id"] == b.id
        expected_expiry = (NOW.date() + timedelta(days=settings.hold_pickup_days)).isoformat()
        assert returned.hold_ready["expires_at"] == expected_expiry

        holds = loans.list_holds(member_id=b.id, now=NOW)
        assert len(holds) == 1
        assert holds[0].status == "ready"
        assert holds[0].expires_at == expected_expiry

        notifications = database.fetchall(
            "SELECT * FROM notification WHERE kind = 'hold_ready'"
        )
        assert len(notifications) == 1
        assert notifications[0]["member_id"] == b.id
        assert notifications[0]["dedupe_key"].startswith(f"hold_ready:{holds[0].id}:")

    def test_return_without_a_waiting_hold_leaves_hold_ready_none(self, env) -> None:
        *_, loans, a, _, _, book = env
        loans.checkout(a.id, edition_id=book.edition_id, now=NOW)
        returned = loans.return_by_code("H-0001", now=NOW)
        assert returned.hold_ready is None


class TestCheckoutHoldInteraction:
    def test_ready_copy_is_protected_from_other_members_auto_pick(self, env) -> None:
        database, _, members, _, loans, a, b, c, book = env
        # İkinci nüsha ekle ki otomatik seçim havuzda iki nüsha olsun.
        with database.transaction() as connection:
            edition = connection.execute(
                "SELECT id FROM edition WHERE id = ?", (book.edition_id,)
            ).fetchone()
            assert edition is not None
            connection.execute(
                "INSERT INTO copy(edition_id, inventory_code, status, created_at, updated_at) "
                "VALUES (?, 'H-0002', 'active', '2026-01-01', '2026-01-01')",
                (book.edition_id,),
            )
        # Nüsha 1'i a'ya, nüsha 2'yi c'ye ver; ikisi de dolu -> hold oluştur.
        loans.checkout(a.id, copy_id=book.copies[0].id, now=NOW)
        loan_c = loans.checkout(c.id, code="H-0002", now=NOW)
        loans.create_hold(edition_id=book.edition_id, member_id=b.id, now=NOW)
        loans.return_by_code("H-0001", now=NOW)  # b'nin hold'u nüsha 1 üzerinde 'ready' olur

        # c iade eder, sonra tekrar otomatik seçimle (edition_id) alır: nüsha 1
        # b için ayrılmış olduğundan c'ye VERİLMEMELİ (nüsha 2 serbest kalmıştı zaten).
        loans.return_loan(loan_c.id, now=NOW)
        third = members.add(
            member_type="student", school_number="9", first_name="Deniz", last_name="D"
        )
        loan_third = loans.checkout(third.id, edition_id=book.edition_id, now=NOW)
        assert loan_third.copy_id != book.copies[0].id

    def test_explicit_copy_id_reserved_for_another_member_is_rejected(self, env) -> None:
        *_, loans, a, b, _, book = env
        loans.checkout(a.id, edition_id=book.edition_id, now=NOW)
        loans.create_hold(edition_id=book.edition_id, member_id=b.id, now=NOW)
        loans.return_by_code("H-0001", now=NOW)
        with pytest.raises(StateConflictError, match="ayrılmış"):
            loans.checkout(a.id, copy_id=book.copies[0].id, now=NOW)

    def test_hold_owner_checkout_fulfills_the_hold(self, env) -> None:
        *_, loans, a, b, _, book = env
        loans.checkout(a.id, edition_id=book.edition_id, now=NOW)
        loans.create_hold(edition_id=book.edition_id, member_id=b.id, now=NOW)
        loans.return_by_code("H-0001", now=NOW)
        loan_b = loans.checkout(b.id, edition_id=book.edition_id, now=NOW)
        assert loan_b.copy_id == book.copies[0].id
        holds = loans.list_holds(member_id=b.id, now=NOW)
        assert holds[0].status == "fulfilled"


class TestHoldExpiry:
    def test_advance_expired_holds_promotes_the_next_member(self, env) -> None:
        _, _, _, settings, loans, a, b, c, book = env
        loans.checkout(a.id, edition_id=book.edition_id, now=NOW)
        loans.create_hold(edition_id=book.edition_id, member_id=b.id, now=NOW)
        loans.create_hold(edition_id=book.edition_id, member_id=c.id, now=NOW)
        loans.return_by_code("H-0001", now=NOW)
        after_expiry = NOW + timedelta(days=settings.hold_pickup_days + 1)

        advanced = loans.advance_expired_holds(now=after_expiry)
        assert advanced == 1

        b_hold = loans.list_holds(member_id=b.id, now=after_expiry)[0]
        assert b_hold.status == "expired"
        c_hold = loans.list_holds(member_id=c.id, now=after_expiry)[0]
        assert c_hold.status == "ready"
        assert c_hold.ready_copy_id == book.copies[0].id

    def test_listing_holds_lazily_advances_expiry(self, env) -> None:
        *_, loans, a, b, _, book = env
        loans.checkout(a.id, edition_id=book.edition_id, now=NOW)
        loans.create_hold(edition_id=book.edition_id, member_id=b.id, now=NOW)
        loans.return_by_code("H-0001", now=NOW)
        after_expiry = NOW + timedelta(days=30)
        holds = loans.list_holds(member_id=b.id, now=after_expiry)
        assert holds[0].status == "expired"


class TestCancelHold:
    def test_cancel_active_hold(self, env) -> None:
        *_, loans, a, b, _, book = env
        loans.checkout(a.id, edition_id=book.edition_id, now=NOW)
        hold = loans.create_hold(edition_id=book.edition_id, member_id=b.id, now=NOW)
        cancelled = loans.cancel_hold(hold.id, now=NOW)
        assert cancelled.status == "cancelled"

    def test_cancel_is_idempotent(self, env) -> None:
        *_, loans, a, b, _, book = env
        loans.checkout(a.id, edition_id=book.edition_id, now=NOW)
        hold = loans.create_hold(edition_id=book.edition_id, member_id=b.id, now=NOW)
        loans.cancel_hold(hold.id, now=NOW)
        again = loans.cancel_hold(hold.id, now=NOW)  # ikinci çağrı hata vermez
        assert again.status == "cancelled"

    def test_cancelling_a_ready_hold_promotes_the_next_member(self, env) -> None:
        *_, loans, a, b, c, book = env
        loans.checkout(a.id, edition_id=book.edition_id, now=NOW)
        hold_b = loans.create_hold(edition_id=book.edition_id, member_id=b.id, now=NOW)
        loans.create_hold(edition_id=book.edition_id, member_id=c.id, now=NOW)
        loans.return_by_code("H-0001", now=NOW)
        assert loans.list_holds(member_id=b.id, now=NOW)[0].status == "ready"

        loans.cancel_hold(hold_b.id, now=NOW)
        c_hold = loans.list_holds(member_id=c.id, now=NOW)[0]
        assert c_hold.status == "ready"

    def test_cancel_unknown_hold_raises_key_error(self, env) -> None:
        _, _, _, _, loans, *_ = env
        with pytest.raises(KeyError):
            loans.cancel_hold(999_999, now=NOW)


fastapi = pytest.importorskip("fastapi")


@pytest.fixture()
def http_env(tmp_path: Path):
    """`/api/holds` ve dolaşım uçlarını gerçek HTTP üzerinden test etmek için
    tek nüshalı bir kitap + ödünç alan üye kurar; dönüş: (client, member, edition_id)."""

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
        client.post("/api/books", json={"title": "Kitap", "copy_count": 1})
        holder = client.post(
            "/api/members",
            json={
                "member_type": "student", "school_number": "1",
                "first_name": "Ayşe", "last_name": "A",
            },
        ).json()
        waiter = client.post(
            "/api/members",
            json={
                "member_type": "student", "school_number": "2",
                "first_name": "Berk", "last_name": "B",
            },
        ).json()
        edition_id = client.get("/api/books?limit=1").json()["items"][0]["edition_id"]
        client.post("/api/loans", json={"member_id": holder["id"], "edition_id": edition_id})
        yield client, holder, waiter, edition_id


class TestHoldsHttpRoutes:
    def test_create_list_and_cancel(self, http_env) -> None:
        client, _holder, waiter, edition_id = http_env
        created = client.post(
            "/api/holds", json={"member_id": waiter["id"], "edition_id": edition_id}
        )
        assert created.status_code == 201, created.text
        hold = created.json()
        assert hold["status"] == "active"
        assert hold["member_name"] == "Berk B"

        listed = client.get(f"/api/holds?member_id={waiter['id']}").json()
        assert len(listed["items"]) == 1
        assert listed["items"][0]["id"] == hold["id"]

        cancelled = client.post(f"/api/holds/{hold['id']}/cancel")
        assert cancelled.status_code == 200
        assert cancelled.json()["status"] == "cancelled"

    def test_return_produces_hold_ready_and_printable_slip(self, http_env) -> None:
        client, holder, waiter, edition_id = http_env
        client.post("/api/holds", json={"member_id": waiter["id"], "edition_id": edition_id})
        loan_id = client.get(f"/api/loans?member_id={holder['id']}").json()["items"][0]["id"]
        returned = client.post(f"/api/loans/{loan_id}/return")
        assert returned.status_code == 200
        hold_ready = returned.json()["hold_ready"]
        assert hold_ready is not None and hold_ready["member_id"] == waiter["id"]

        slip = client.get(f"/print/hold-slip?hold_id={hold_ready['hold_id']}")
        assert slip.status_code == 200
        assert "Ayırma Fişi" in slip.text
        assert "Berk" in slip.text

    def test_hold_slip_for_unknown_hold_is_404(self, http_env) -> None:
        client, *_ = http_env
        assert client.get("/print/hold-slip?hold_id=999999").status_code == 404


class TestHoldEnabledFlag:
    def test_disabled_hold_creation_is_rejected_at_the_route(self, http_env) -> None:
        client, _holder, waiter, edition_id = http_env
        client.put("/api/settings", json={"hold_enabled": False})
        response = client.post(
            "/api/holds", json={"member_id": waiter["id"], "edition_id": edition_id}
        )
        assert response.status_code == 403


class TestReviewFindings:
    """Bağımsız inceleme bulgularının regresyonları (2026-08-09 turu)."""

    def test_checkout_of_other_copy_fulfills_ready_hold_and_frees_reserved(
        self, env
    ) -> None:
        """Bulgu 1: hazır rezervasyonlu üye BAŞKA nüshayı alınca rezervasyon
        askıda kalmamalı, ayrılan nüsha sıradakine devredilmeli."""

        _, catalog, _, _, loans, a, b, c, book = env
        loans.checkout(a.id, code="H-0001", now=NOW)
        # B ve C sıraya girer.
        loans.create_hold(edition_id=book.edition_id, member_id=b.id, now=NOW)
        loans.create_hold(edition_id=book.edition_id, member_id=c.id, now=NOW)
        # A iade eder → B'nin holdü H-0001 ile hazır olur.
        loans.return_by_code("H-0001", now=NOW)
        ready = [h for h in loans.list_holds(member_id=b.id, now=NOW) if h.status == "ready"]
        assert len(ready) == 1 and ready[0].ready_copy_id is not None
        # Yeni bir nüsha (H-0002) rafa girer; görevli B'ye ONU okutur.
        catalog.add_copy(book.edition_id, CopyInput(inventory_code="H-0002"))
        loans.checkout(b.id, code="H-0002", now=NOW)
        # B'nin holdü kapanmış, ayrılan H-0001 sıradaki C'ye devredilmiş olmalı.
        b_holds = loans.list_holds(member_id=b.id, now=NOW)
        assert all(h.status == "fulfilled" for h in b_holds)
        c_ready = [h for h in loans.list_holds(member_id=c.id, now=NOW) if h.status == "ready"]
        assert len(c_ready) == 1
        assert c_ready[0].ready_copy_id == ready[0].ready_copy_id

    def test_discard_reverts_ready_hold_to_active(self, env) -> None:
        """Bulgu 3: ayrılan nüsha düşülürse rezervasyon 'hazır'da kalmamalı;
        sıraya (active) geri dönmeli, kuyruk ölü nüshayla erimemeli."""

        from kitapkatalog.discards import Discards

        database, *_, loans, a, b, _c, book = env
        loans.checkout(a.id, code="H-0001", now=NOW)
        loans.create_hold(edition_id=book.edition_id, member_id=b.id, now=NOW)
        loans.return_by_code("H-0001", now=NOW)
        ready = [h for h in loans.list_holds(member_id=b.id, now=NOW) if h.status == "ready"]
        assert len(ready) == 1
        copy_id = ready[0].ready_copy_id
        assert copy_id is not None

        Discards(database).discard_copy(copy_id, reason="kayip")
        after = loans.list_holds(member_id=b.id, now=NOW)
        assert [h.status for h in after] == ["active"]
        assert after[0].ready_copy_id is None and after[0].expires_at is None
        # Süre dolumu taraması ölü nüshayı sıradakine TAŞIMAMALI.
        advanced = loans.advance_expired_holds(now=NOW + timedelta(days=30))
        assert advanced == 0

    def test_promote_skips_dead_copy(self, env) -> None:
        """Bulgu 3 devamı: devir zinciri yaşamayan nüshaya 'hazır' üretmez."""

        database, *_, loans, a, b, c, book = env
        loans.checkout(a.id, code="H-0001", now=NOW)
        loans.create_hold(edition_id=book.edition_id, member_id=b.id, now=NOW)
        loans.create_hold(edition_id=book.edition_id, member_id=c.id, now=NOW)
        loans.return_by_code("H-0001", now=NOW)  # B ready (H-0001)
        # H-0001'i düş: B active'e döner (önceki test); şimdi süre geçse bile
        # C asla ölü nüshayla ready olmamalı.
        from kitapkatalog.discards import Discards

        ready = [h for h in loans.list_holds(member_id=b.id, now=NOW) if h.status == "ready"]
        Discards(database).discard_copy(ready[0].ready_copy_id, reason="yipranma")
        statuses = {h.member_id: h.status for h in loans.list_holds(now=NOW)}
        assert statuses[b.id] == "active" and statuses[c.id] == "active"

    def test_existing_ready_hold_protected_even_when_setting_disabled(self, env) -> None:
        """Codex bulgusu: hold_enabled=0 yalnız YENİ rezervasyonu kapatır;
        mevcut hazır rezervasyonun koruması/kapanışı çalışmaya devam eder."""

        _, _, _, settings, loans, a, b, _c, book = env
        loans.checkout(a.id, code="H-0001", now=NOW)
        loans.create_hold(edition_id=book.edition_id, member_id=b.id, now=NOW)
        loans.return_by_code("H-0001", now=NOW)  # b ready (H-0001)
        settings.set("hold_enabled", "0")
        # Ayrılan nüsha başka üyeye verilemez...
        with pytest.raises(StateConflictError, match="ayrılmış"):
            loans.checkout(a.id, copy_id=book.copies[0].id, now=NOW)
        # ...sahibi alınca rezervasyon kapanır.
        loans.checkout(b.id, code="H-0001", now=NOW)
        assert all(
            h.status == "fulfilled" for h in loans.list_holds(member_id=b.id, now=NOW)
        )

    def test_discard_promotes_hold_to_available_replacement_copy(self, env) -> None:
        """Codex bulgusu: ayrılan nüsha düşülünce rafta uygun başka nüsha varsa
        sıra hemen ona devredilmeli (üçüncü üye araya girip sırayı geçmesin)."""

        from kitapkatalog.discards import Discards

        database, catalog, members, _, loans, a, b, _c, book = env
        d = members.add(member_type="student", school_number="7", first_name="D", last_name="D")
        catalog.add_copy(book.edition_id, CopyInput(inventory_code="H-0003"))
        loans.checkout(a.id, code="H-0001", now=NOW)
        loans.checkout(d.id, code="H-0003", now=NOW)
        loans.create_hold(edition_id=book.edition_id, member_id=b.id, now=NOW)
        loans.return_by_code("H-0001", now=NOW)  # b ready (H-0001)
        loans.return_by_code("H-0003", now=NOW)  # başka aktif hold yok → H-0003 rafta

        ready = [h for h in loans.list_holds(member_id=b.id, now=NOW) if h.status == "ready"]
        Discards(database).discard_copy(ready[0].ready_copy_id, reason="kayip")

        after = [h for h in loans.list_holds(member_id=b.id, now=NOW)]
        assert [h.status for h in after] == ["ready"]
        replacement = database.fetchone(
            "SELECT id FROM copy WHERE inventory_code = 'H-0003'"
        )
        assert after[0].ready_copy_id == int(replacement["id"])
