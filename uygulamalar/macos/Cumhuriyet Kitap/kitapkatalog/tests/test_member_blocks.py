"""Üye yasağı/af: waiver cezayı düşürür, manuel blok checkout engeller, kaldırma."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from pathlib import Path

import pytest

from kitapkatalog.catalog import Catalog
from kitapkatalog.database import Database, StateConflictError
from kitapkatalog.domain import BookInput
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
    settings.set("overdue_penalty_per_day", "1")
    loans = Loans(database, settings)
    member = members.add(
        member_type="student", school_number="1", first_name="Ayşe", last_name="A"
    )
    book = catalog.save_book(BookInput(title="Ceza Kitabı"))
    return database, catalog, members, settings, loans, member, book


def _incur_penalty(loans: Loans, member_id: int, edition_id: int) -> None:
    """60 gün önce ver, bugün iade et: 45 gün gecikme -> ceza bugünden sonraya taşar."""

    checkout_at = NOW - timedelta(days=60)
    loan = loans.checkout(member_id, edition_id=edition_id, now=checkout_at)
    loans.return_loan(loan.id, now=NOW)


class TestOverdueWaiver:
    def test_amnesty_lifts_the_currently_computed_penalty(self, env) -> None:
        _, _, _, _, loans, member, book = env
        _incur_penalty(loans, member.id, book.edition_id)
        assert loans.penalty_end_for(member.id, now=NOW) is not None
        with pytest.raises(StateConflictError, match="bekleme süresi"):
            loans.checkout(member.id, edition_id=book.edition_id, now=NOW)

        block = loans.grant_amnesty(member.id, reason="Veli görüşmesi", now=NOW)
        assert block.kind == "auto_overdue_waiver"
        assert loans.penalty_end_for(member.id, now=NOW) is None
        loan = loans.checkout(member.id, edition_id=book.edition_id, now=NOW)
        assert loan.member_id == member.id

    def test_amnesty_without_active_penalty_is_rejected(self, env) -> None:
        _, _, _, _, loans, member, _book = env
        with pytest.raises(StateConflictError, match="süren bir cezası yok"):
            loans.grant_amnesty(member.id, reason="Gerekçe", now=NOW)

    def test_amnesty_requires_a_reason(self, env) -> None:
        _, _, _, _, loans, member, book = env
        _incur_penalty(loans, member.id, book.edition_id)
        with pytest.raises(ValueError, match="gerekçesi"):
            loans.grant_amnesty(member.id, reason="   ", now=NOW)

    def test_waiver_only_covers_its_own_date_range(self, env) -> None:
        _, _, _, _, loans, member, book = env
        _incur_penalty(loans, member.id, book.edition_id)
        penalty_end = loans.penalty_end_for(member.id, now=NOW)
        assert penalty_end is not None
        loans.grant_amnesty(member.id, reason="Af", now=NOW)
        after_waiver_range = datetime.combine(
            penalty_end + timedelta(days=1), datetime.min.time(), tzinfo=UTC
        )
        # Af yalnız hesaplandığı anki cezayı söndürür; bittiği tarihten sonrası
        # zaten cezasız olduğundan burada da None dönmesi beklenir.
        assert loans.penalty_end_for(member.id, now=after_waiver_range) is None


class TestManualBlock:
    def test_manual_block_prevents_checkout(self, env) -> None:
        _, _, _, _, loans, member, book = env
        block = loans.add_block(member.id, reason="Disiplin", now=NOW)
        assert block.kind == "manual"
        with pytest.raises(StateConflictError, match="yasaklı"):
            loans.checkout(member.id, edition_id=book.edition_id, now=NOW)

    def test_manual_block_requires_a_reason(self, env) -> None:
        _, _, _, _, loans, member, _book = env
        with pytest.raises(ValueError, match="gerekçesi"):
            loans.add_block(member.id, reason="", now=NOW)

    def test_lifting_the_block_restores_checkout(self, env) -> None:
        _, _, _, _, loans, member, book = env
        block = loans.add_block(member.id, reason="Disiplin", now=NOW)
        lifted = loans.lift_block(member.id, block.id, reason="Görüşüldü", now=NOW)
        assert lifted.lifted_at is not None
        assert lifted.lift_reason == "Görüşüldü"
        loan = loans.checkout(member.id, edition_id=book.edition_id, now=NOW)
        assert loan.member_id == member.id

    def test_lifting_twice_raises_conflict(self, env) -> None:
        _, _, _, _, loans, member, _book = env
        block = loans.add_block(member.id, reason="Disiplin", now=NOW)
        loans.lift_block(member.id, block.id, now=NOW)
        with pytest.raises(StateConflictError, match="zaten kaldırılmış"):
            loans.lift_block(member.id, block.id, now=NOW)

    def test_block_expires_after_its_end_date(self, env) -> None:
        _, _, _, _, loans, member, book = env
        end_date = NOW.date().isoformat()
        loans.add_block(member.id, reason="Kısa süreli", end_date=end_date, now=NOW)
        later = NOW + timedelta(days=2)
        loan = loans.checkout(member.id, edition_id=book.edition_id, now=later)
        assert loan.member_id == member.id

    def test_lift_block_for_wrong_member_raises_key_error(self, env) -> None:
        _, _, members, _, loans, member, _book = env
        other = members.add(
            member_type="student", school_number="2", first_name="Berk", last_name="B"
        )
        block = loans.add_block(member.id, reason="Disiplin", now=NOW)
        with pytest.raises(KeyError):
            loans.lift_block(other.id, block.id, now=NOW)


class TestMemberSummaryAndListing:
    def test_active_manual_block_helper(self, env) -> None:
        _, _, _, _, loans, member, _book = env
        assert loans.active_manual_block(member.id, now=NOW) is None
        loans.add_block(member.id, reason="Disiplin", now=NOW)
        active = loans.active_manual_block(member.id, now=NOW)
        assert active is not None and active.kind == "manual"

    def test_list_blocks_returns_newest_first(self, env) -> None:
        _, _, _, _, loans, member, book = env
        _incur_penalty(loans, member.id, book.edition_id)
        loans.grant_amnesty(member.id, reason="Af", now=NOW)
        loans.add_block(member.id, reason="Disiplin", now=NOW + timedelta(seconds=1))
        blocks = loans.list_blocks(member.id)
        assert len(blocks) == 2
        assert blocks[0].kind == "manual"
        assert blocks[1].kind == "auto_overdue_waiver"


class TestMemberBlocksHttpRoutes:
    def test_block_amnesty_lift_round_trip(self, tmp_path: Path) -> None:
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
            member = client.post(
                "/api/members",
                json={
                    "member_type": "student", "school_number": "1",
                    "first_name": "Ayşe", "last_name": "A",
                },
            ).json()

            created = client.post(
                f"/api/members/{member['id']}/blocks",
                json={"reason": "Disiplin"},
            )
            assert created.status_code == 201, created.text
            block = created.json()
            assert block["kind"] == "manual"

            missing_reason = client.post(
                f"/api/members/{member['id']}/blocks", json={"reason": ""}
            )
            assert missing_reason.status_code == 422  # pydantic min_length=1

            listed = client.get(f"/api/members/{member['id']}/blocks").json()
            assert len(listed) == 1

            summary = client.get(f"/api/members/{member['id']}/summary").json()
            assert summary["active_block"]["id"] == block["id"]

            no_penalty = client.post(
                f"/api/members/{member['id']}/amnesty", json={"reason": "Af"}
            )
            assert no_penalty.status_code == 409  # süren ceza yok

            lifted = client.post(
                f"/api/members/{member['id']}/blocks/{block['id']}/lift",
                json={"reason": "Görüşüldü"},
            )
            assert lifted.status_code == 200
            assert lifted.json()["lifted_at"] is not None

            summary_after = client.get(f"/api/members/{member['id']}/summary").json()
            assert summary_after["active_block"] is None


class TestWaiverScopeRegression:
    """Bulgu 2 regresyonu: af yalnız af ANINDAKİ cezayı söndürür; af sonrası
    işlenen yeni gecikme cezaları pencere içinde bile yaşamaya devam eder."""

    def test_new_penalty_after_amnesty_still_blocks(self, env) -> None:
        _, catalog, _, _, loans, member, book = env
        _incur_penalty(loans, member.id, book.edition_id)
        loans.grant_amnesty(member.id, reason="Kütüphane haftası affı", now=NOW)
        # Af çalışıyor: hemen sonrasında ödünç alabilmeli.
        other = catalog.save_book(BookInput(title="Af Sonrası Kitap"))
        loan = loans.checkout(member.id, edition_id=other.edition_id, now=NOW)

        # Af penceresi İÇİNDE yeni bir gecikme işlenir: 20 gün sonra iade
        # (vade 15 gün → 5 gün gecikme → 5 gün yeni ceza).
        late_return = NOW + timedelta(days=20)
        loans.return_loan(loan.id, now=late_return)

        third = catalog.save_book(BookInput(title="Üçüncü Kitap"))
        with pytest.raises(StateConflictError, match="bekleme süresi"):
            loans.checkout(member.id, edition_id=third.edition_id, now=late_return)
        # Eski (affedilmiş) ceza geri gelmemeli: yeni cezanın bitiminden sonra
        # ödünç yeniden açılır.
        after_new_penalty = late_return + timedelta(days=6)
        loans.checkout(member.id, edition_id=third.edition_id, now=after_new_penalty)
