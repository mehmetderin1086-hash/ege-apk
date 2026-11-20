"""Ödünç servisi: verme/iade/uzatma, kurallar, yarış güvenliği, anlık görüntüler."""

from __future__ import annotations

import threading
from datetime import UTC, datetime, timedelta
from pathlib import Path

import pytest

from kitapkatalog.catalog import Catalog
from kitapkatalog.database import Database, StateConflictError
from kitapkatalog.domain import BookInput, CopyInput, IdentifierInput
from kitapkatalog.loans import Loans
from kitapkatalog.members import Members
from kitapkatalog.reports import Reports
from kitapkatalog.settings import AppSettings

NOW = datetime(2026, 3, 10, 9, 0, tzinfo=UTC)


@pytest.fixture()
def env(tmp_path: Path):
    database = Database(tmp_path / "catalog.sqlite3")
    catalog = Catalog(database)
    members = Members(database)
    settings = AppSettings(database)
    loans = Loans(database, settings)
    student = members.add(
        member_type="student", school_number="101", first_name="Işıl", last_name="Yılmaz",
        class_name="9-A",
    )
    book = catalog.save_book(
        BookInput(
            title="Beyaz Gemi",
            identifiers=(IdentifierInput(scheme="isbn13", value="9789750718533"),),
            copy=CopyInput(inventory_code="2026-000001"),
        )
    )
    return database, catalog, members, settings, loans, student, book


class TestCheckout:
    def test_checkout_and_return_by_isbn(self, env) -> None:
        *_, loans, student, book = env
        loan = loans.checkout(student.id, isbn="9789750718533", now=NOW)
        assert loan.edition_id == book.edition_id
        assert loan.title_snapshot == "Beyaz Gemi"
        assert loan.inventory_code_snapshot == "2026-000001"
        assert loan.due_at == "2026-03-25"  # varsayılan 15 gün
        # Aynı tek nüsha ikinci kez verilemez.
        with pytest.raises(StateConflictError, match="nüsha"):
            loans.checkout(student.id, isbn="9789750718533", now=NOW)
        returned = loans.return_by_code("9789750718533", now=NOW)
        assert returned.id == loan.id and returned.returned_at is not None

    def test_checkout_by_free_code(self, env) -> None:
        *_, loans, student, book = env
        loan = loans.checkout(student.id, code="2026-000001", now=NOW)
        assert loan.copy_id == book.copies[0].id
        loans.return_loan(loan.id, now=NOW)
        loan = loans.checkout(student.id, code="978-975-07-1853-3", now=NOW)
        assert loan.edition_id == book.edition_id
        with pytest.raises(KeyError, match="kayıtlı değil"):
            loans.checkout(student.id, code="OLMAYAN-KOD", now=NOW)

    def test_return_by_inventory_code(self, env) -> None:
        *_, loans, student, book = env
        loans.checkout(student.id, edition_id=book.edition_id, now=NOW)
        returned = loans.return_by_code("2026-000001", now=NOW)
        assert returned.returned_at is not None

    def test_return_by_code_prefers_inventory_over_isbn(self, env) -> None:
        # Codex bulgusu: demirbaşın kompakt hâli kayıtlı bir ISBN'e denk gelirse
        # iade yanlış kitaba işlenebilir; önce demirbaş eşleşmeli.
        database, catalog, members, _, loans, student, book = env
        other = catalog.save_book(BookInput(title="Çakışan Kitap", copy=CopyInput()))
        # "2026-000001" kompaktı ("2026000001") başka baskının tanımlayıcısıymış gibi
        # kaydedilsin (checksum doğrulamasını aşmak için ham SQL).
        with database.transaction() as connection:
            connection.execute(
                """
                INSERT INTO identifier(edition_id, scheme, value, normalized_value,
                                       source, created_at)
                VALUES (?, 'ISBN10', '2026000001', '2026000001', 'user', '2026-01-01')
                """,
                (other.edition_id,),
            )
        second_member = members.add(
            member_type="student", school_number="333", first_name="X", last_name="Y"
        )
        loans.checkout(second_member.id, edition_id=other.edition_id, now=NOW)
        loans.checkout(student.id, copy_id=book.copies[0].id, now=NOW)
        returned = loans.return_by_code("2026-000001", now=NOW)
        assert returned.edition_id == book.edition_id  # demirbaş kazanır

    def test_penalty_survives_long_lookback(self, env) -> None:
        # 180 günlük pencere, hâlâ süren uzun cezayı unutuyordu; pencere due_at'e
        # değil ceza bitişine yetecek kadar geniş olmalı.
        _, catalog, _, settings, loans, student, book = env
        settings.set("overdue_penalty_per_day", "1")
        long_ago = NOW - timedelta(days=500)
        loans.checkout(student.id, edition_id=book.edition_id, now=long_ago)
        loans.return_by_code("9789750718533", now=NOW - timedelta(days=200))  # 285 gün geç
        other = catalog.save_book(BookInput(title="Uzun Ceza"))
        with pytest.raises(StateConflictError, match="bekleme"):
            loans.checkout(student.id, edition_id=other.edition_id, now=NOW)

    def test_checkout_isbn_param_accepts_non_isbn_identifier(self, env) -> None:
        # Reviewer bulgusu: açık isbn= parametresi eskiden hane kapısız
        # aranırdı; ISSN gibi 8 haneli normalized değerler bulunmaya devam
        # etmeli (10/13 kapısı yalnız serbest `code` çözümlemesinde).
        database, catalog, _, _, loans, student, _ = env
        other = catalog.save_book(BookInput(title="Dergi"))
        with database.transaction() as connection:
            connection.execute(
                """
                INSERT INTO identifier(edition_id, scheme, value, normalized_value,
                                       source, created_at)
                VALUES (?, 'ISSN', '1300-1337', '13001337', 'user', '2026-01-01')
                """,
                (other.edition_id,),
            )
        loan = loans.checkout(student.id, isbn="1300-1337", now=NOW)
        assert loan.edition_id == other.edition_id

    def test_extend_limit_and_overdue_base(self, env) -> None:
        _, _, _, settings, loans, student, book = env
        loan = loans.checkout(student.id, edition_id=book.edition_id, now=NOW)
        # Varsayılan sınır 2: iki uzatma serbest, üçüncüsü 409.
        loans.extend(loan.id, now=NOW)
        second = loans.extend(loan.id, now=NOW)
        assert second.renewal_count == 2
        with pytest.raises(StateConflictError, match="Uzatma sınırı"):
            loans.extend(loan.id, now=NOW)
        # 0 = sınırsız.
        settings.set("loan_max_renewals", "0")
        third = loans.extend(loan.id, now=NOW)
        assert third.renewal_count == 3

    def test_extend_overdue_uses_today_as_base(self, env) -> None:
        # Gecikmiş kayıt uzatılınca yeni tarih geçmişte kalmamalı.
        _, _, _, settings, loans, student, book = env
        settings.set("loan_max_renewals", "0")
        past = NOW - timedelta(days=40)
        loan = loans.checkout(student.id, edition_id=book.edition_id, now=past)
        assert loan.due_at < NOW.date().isoformat()  # gecikmiş
        extended = loans.extend(loan.id, now=NOW)
        assert extended.due_at == (NOW.date() + timedelta(days=15)).isoformat()

    def test_active_counts(self, env) -> None:
        _, catalog, _, _, loans, student, book = env
        other = catalog.save_book(BookInput(title="Sayaçsız"))
        loans.checkout(student.id, edition_id=book.edition_id, now=NOW)
        counts = loans.active_counts([book.edition_id, other.edition_id])
        assert counts == {book.edition_id: 1}
        assert loans.active_counts([]) == {}

    def test_penalty_end_for_public_view(self, env) -> None:
        # Üye özeti ekranı için: ceza kapalıyken/temiz geçmişte None,
        # geç iade sonrası bitiş günü döner ve gün geçince kendiliğinden düşer.
        _, _, _, settings, loans, student, book = env
        assert loans.penalty_end_for(student.id, now=NOW) is None  # ceza kapalı
        settings.set("overdue_penalty_per_day", "2")
        assert loans.penalty_end_for(student.id, now=NOW) is None  # geçmiş temiz
        loan = loans.checkout(
            student.id, edition_id=book.edition_id, now=NOW - timedelta(days=20)
        )
        loans.return_loan(loan.id, now=NOW)  # 15 günlük süre → 5 gün geç
        end = loans.penalty_end_for(student.id, now=NOW)
        assert end == NOW.date() + timedelta(days=10)  # 5 gün × 2 katsayı
        assert loans.penalty_end_for(student.id, now=NOW + timedelta(days=11)) is None

    def test_stats_today_counters(self, env) -> None:
        *_, loans, student, book = env
        loan = loans.checkout(student.id, edition_id=book.edition_id, now=NOW)
        loans.return_loan(loan.id, now=NOW)
        stats = loans.stats(now=NOW)
        assert stats["today_out"] == 1
        assert stats["today_in"] == 1
        tomorrow = loans.stats(now=NOW + timedelta(days=1))
        assert tomorrow["today_out"] == 0 and tomorrow["today_in"] == 0

    def test_member_limit(self, env) -> None:
        _, catalog, _, settings, loans, student, _ = env
        settings.set("loan_max_books", "2")
        for index in range(2):
            record = catalog.save_book(BookInput(title=f"Kitap {index}"))
            loans.checkout(student.id, edition_id=record.edition_id, now=NOW)
        extra = catalog.save_book(BookInput(title="Fazla Kitap"))
        with pytest.raises(StateConflictError, match="en fazla"):
            loans.checkout(student.id, edition_id=extra.edition_id, now=NOW)

    def test_staff_gets_different_rules(self, env) -> None:
        _, _, members, _, loans, _, book = env
        staff = members.add(member_type="staff", first_name="Ali", last_name="Hoca")
        loan = loans.checkout(staff.id, edition_id=book.edition_id, now=NOW)
        assert loan.due_at == "2026-04-09"  # personel 30 gün

    def test_inactive_member_rejected(self, env) -> None:
        _, _, members, _, loans, student, book = env
        members.update(student.id, is_active=False)
        with pytest.raises(StateConflictError, match="pasif"):
            loans.checkout(student.id, edition_id=book.edition_id, now=NOW)

    def test_extend(self, env) -> None:
        *_, loans, student, book = env
        loan = loans.checkout(student.id, edition_id=book.edition_id, now=NOW)
        extended = loans.extend(loan.id, now=NOW)
        assert extended.due_at == "2026-04-09"  # +15 gün daha
        assert extended.renewal_count == 1
        loans.return_loan(loan.id, now=NOW)
        with pytest.raises(StateConflictError, match="İade"):
            loans.extend(loan.id, now=NOW)


class TestOverdueRules:
    def test_overdue_blocks_new_checkout(self, env) -> None:
        _, catalog, _, settings, loans, student, book = env
        past = NOW - timedelta(days=30)
        loans.checkout(student.id, edition_id=book.edition_id, now=past)
        other = catalog.save_book(BookInput(title="İkinci Kitap"))
        with pytest.raises(StateConflictError, match="gecikmiş"):
            loans.checkout(student.id, edition_id=other.edition_id, now=NOW)
        # Ayar kapatılırsa engel kalkar.
        settings.set("overdue_block", "0")
        loan = loans.checkout(student.id, edition_id=other.edition_id, now=NOW)
        assert loan.id > 0

    def test_penalty_days_block_after_late_return(self, env) -> None:
        _, catalog, _, settings, loans, student, book = env
        settings.set("overdue_penalty_per_day", "1")
        past = NOW - timedelta(days=30)  # 15 günlük süre → 15 gün gecikme
        loans.checkout(student.id, edition_id=book.edition_id, now=past)
        loans.return_by_code("9789750718533", now=NOW)
        other = catalog.save_book(BookInput(title="Ceza Testi"))
        with pytest.raises(StateConflictError, match="bekleme"):
            loans.checkout(student.id, edition_id=other.edition_id, now=NOW)
        # Ceza süresi (15 gün) dolunca serbest.
        after = NOW + timedelta(days=16)
        loan = loans.checkout(student.id, edition_id=other.edition_id, now=after)
        assert loan.id > 0

    def test_late_return_payload_keeps_historical_delay(self, env) -> None:
        *_, loans, student, book = env
        loan = loans.checkout(
            student.id,
            edition_id=book.edition_id,
            now=NOW - timedelta(days=20),
        )
        returned = loans.return_loan(loan.id, now=NOW)
        assert returned.to_dict(now=NOW)["days_overdue"] == 5
        assert returned.to_dict(now=NOW)["overdue"] is False

    def test_overdue_listing(self, env) -> None:
        *_, loans, student, book = env
        loans.checkout(student.id, edition_id=book.edition_id, now=NOW - timedelta(days=20))
        overdue = loans.list_overdue(now=NOW)
        assert len(overdue) == 1
        assert overdue[0].member_name == "Işıl Yılmaz"
        assert overdue[0].days_overdue(NOW) == 5


class TestRaceAndIntegrity:
    def test_single_copy_race_only_one_wins(self, env) -> None:
        _, _, members, _, loans, student, book = env
        other = members.add(
            member_type="student", school_number="102", first_name="Can", last_name="Demir"
        )
        barrier = threading.Barrier(2)
        results: list[str] = []

        def attempt(member_id: int) -> None:
            barrier.wait()
            try:
                loans.checkout(member_id, edition_id=book.edition_id, now=NOW)
                results.append("ok")
            except StateConflictError:
                results.append("conflict")

        threads = [
            threading.Thread(target=attempt, args=(member_id,))
            for member_id in (student.id, other.id)
        ]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()
        assert sorted(results) == ["conflict", "ok"]

    def test_delete_book_with_active_loan_blocked(self, env) -> None:
        _, catalog, _, _, loans, student, book = env
        loans.checkout(student.id, edition_id=book.edition_id, now=NOW)
        with pytest.raises(Exception, match="ödünçte"):
            catalog.delete_book(book.edition_id)
        # İade sonrası silinebilir; geçmiş kaydı anlık görüntüyle yaşar.
        loans.return_by_code("2026-000001", now=NOW)
        assert catalog.delete_book(book.edition_id) is True
        history, total = loans.member_history(student.id)
        assert total == 1
        assert history[0].title_snapshot == "Beyaz Gemi"
        assert history[0].copy_id is None

    def test_set_copy_count_spares_loaned_copies(self, env) -> None:
        _, catalog, _, _, loans, student, book = env
        catalog.add_copy(book.edition_id)
        catalog.add_copy(book.edition_id)
        loan = loans.checkout(student.id, copy_id=book.copies[0].id, now=NOW)
        result = catalog.set_copy_count(book.edition_id, 1)
        assert result == 1
        remaining = catalog.get_book(book.edition_id)
        assert [c.id for c in remaining.copies] == [loan.copy_id]
        # Hedef 0 bile olsa ödünçteki nüsha silinmez.
        result = catalog.set_copy_count(book.edition_id, 0)
        assert result == 1


class TestCirculationIntegrityV8:
    def test_checkout_requires_exactly_one_book_selector(self, env) -> None:
        _, _, _, _, loans, student, book = env
        with pytest.raises(ValueError, match="tam olarak biri"):
            loans.checkout(student.id, now=NOW, request_id="selector-none-001")
        with pytest.raises(ValueError, match="tam olarak biri"):
            loans.checkout(
                student.id,
                edition_id=book.edition_id,
                code="2026-000001",
                now=NOW,
                request_id="selector-many-001",
            )

    def test_same_member_cannot_hold_two_copies_of_same_edition(self, env) -> None:
        _, catalog, _, _, loans, student, book = env
        catalog.add_copy(book.edition_id)
        loans.checkout(
            student.id,
            edition_id=book.edition_id,
            now=NOW,
            request_id="same-edition-001",
        )
        with pytest.raises(StateConflictError, match="aynı baskı"):
            loans.checkout(
                student.id,
                edition_id=book.edition_id,
                now=NOW,
                request_id="same-edition-002",
            )

    def test_checkout_retry_creates_one_loan_and_one_event(self, env) -> None:
        database, _, _, _, loans, student, book = env
        first = loans.checkout(
            student.id,
            edition_id=book.edition_id,
            now=NOW,
            request_id="checkout-retry-001",
        )
        replay = loans.checkout(
            student.id,
            edition_id=book.edition_id,
            now=NOW + timedelta(minutes=10),
            request_id="checkout-retry-001",
        )
        assert replay == first
        assert database.fetchone("SELECT COUNT(*) FROM loan")[0] == 1
        assert database.fetchone("SELECT COUNT(*) FROM circulation_event")[0] == 1

    def test_extend_and_return_retries_do_not_repeat_side_effects(self, env) -> None:
        database, _, _, _, loans, student, book = env
        loan = loans.checkout(
            student.id,
            edition_id=book.edition_id,
            now=NOW,
            request_id="checkout-retry-002",
        )
        extended = loans.extend(
            loan.id, now=NOW, request_id="extend-retry-001"
        )
        replayed_extend = loans.extend(
            loan.id,
            now=NOW + timedelta(days=1),
            request_id="extend-retry-001",
        )
        assert replayed_extend == extended
        assert replayed_extend.renewal_count == 1

        returned = loans.return_loan(
            loan.id, now=NOW, request_id="return-retry-001"
        )
        replayed_return = loans.return_loan(
            loan.id,
            now=NOW + timedelta(days=1),
            request_id="return-retry-001",
        )
        assert replayed_return == returned
        assert database.fetchone("SELECT COUNT(*) FROM circulation_event")[0] == 3

    def test_return_by_code_retry_replays_after_loan_is_closed(self, env) -> None:
        database, _, _, _, loans, student, book = env
        loan = loans.checkout(
            student.id,
            edition_id=book.edition_id,
            now=NOW,
            request_id="checkout-return-code-001",
        )
        returned = loans.return_by_code(
            "2026-000001", now=NOW, request_id="return-code-retry-001"
        )
        replayed = loans.return_by_code(
            "2026-000001",
            now=NOW + timedelta(days=1),
            request_id="return-code-retry-001",
        )
        assert returned.id == replayed.id == loan.id
        assert replayed.returned_at == returned.returned_at
        assert database.fetchone("SELECT COUNT(*) FROM circulation_event")[0] == 2

    def test_request_id_reuse_for_different_command_conflicts(self, env) -> None:
        _, _, _, _, loans, student, book = env
        loan = loans.checkout(
            student.id,
            edition_id=book.edition_id,
            now=NOW,
            request_id="shared-request-001",
        )
        with pytest.raises(StateConflictError, match="farklı"):
            loans.checkout(
                student.id,
                copy_id=book.copies[0].id,
                now=NOW,
                request_id="shared-request-001",
            )
        with pytest.raises(StateConflictError, match="farklı"):
            loans.extend(loan.id, now=NOW, request_id="shared-request-001")

    def test_same_request_race_replays_single_result(self, env) -> None:
        database, _, _, _, loans, student, book = env
        barrier = threading.Barrier(2)
        results: list[int] = []
        failures: list[BaseException] = []

        def attempt() -> None:
            barrier.wait()
            try:
                record = loans.checkout(
                    student.id,
                    edition_id=book.edition_id,
                    now=NOW,
                    request_id="concurrent-retry-001",
                )
                results.append(record.id)
            except BaseException as exc:  # pragma: no cover - asserted below
                failures.append(exc)

        threads = [threading.Thread(target=attempt) for _ in range(2)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()

        assert failures == []
        assert len(results) == 2 and len(set(results)) == 1
        assert database.fetchone("SELECT COUNT(*) FROM loan")[0] == 1
        assert database.fetchone("SELECT COUNT(*) FROM circulation_event")[0] == 1

    def test_event_write_failure_rolls_back_loan(self, env, monkeypatch) -> None:
        database, _, _, _, loans, student, book = env

        def fail_event(*_args, **_kwargs) -> None:
            raise RuntimeError("olay yazılamadı")

        monkeypatch.setattr(loans, "_write_event", fail_event)
        with pytest.raises(RuntimeError, match="olay yazılamadı"):
            loans.checkout(
                student.id,
                edition_id=book.edition_id,
                now=NOW,
                request_id="atomic-failure-001",
            )
        assert database.fetchone("SELECT COUNT(*) FROM loan")[0] == 0
        assert database.fetchone("SELECT COUNT(*) FROM circulation_event")[0] == 0

    def test_member_changes_do_not_rewrite_history_or_reports(self, env) -> None:
        database, _, members, _, loans, student, book = env
        loan = loans.checkout(
            student.id,
            edition_id=book.edition_id,
            now=NOW,
            request_id="snapshot-history-001",
        )
        members.update(student.id, first_name="Yeni Işıl", class_name="10-B")

        historical = loans.get(loan.id)
        assert historical is not None
        assert historical.member_name == "Işıl Yılmaz"
        assert historical.member_class == "9-A"
        assert historical.academic_period == "2025-2026"
        assert Reports(database).by_class() == [
            {"class_name": "9-A", "loan_count": 1, "reader_count": 1}
        ]
        assert Reports(database).top_readers()[0]["member_name"] == "Işıl Yılmaz"


class TestStats:
    def test_stats_counts(self, env) -> None:
        _, _, _, _, loans, student, book = env
        loans.checkout(student.id, edition_id=book.edition_id, now=NOW - timedelta(days=20))
        stats = loans.stats(now=NOW)
        assert stats["active"] == 1
        assert stats["overdue"] == 1
        assert stats["this_month"] == 0  # Şubat'ta verildi
