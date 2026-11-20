"""Okuma yarışması: standings dönem/scope filtreleri, sınıf ligi, sertifika sicili."""

from __future__ import annotations

from datetime import UTC, datetime
from pathlib import Path

import pytest

from kitapkatalog.catalog import Catalog
from kitapkatalog.challenges import Challenges
from kitapkatalog.database import Database
from kitapkatalog.domain import BookInput, CopyInput
from kitapkatalog.loans import Loans
from kitapkatalog.members import Members
from kitapkatalog.settings import AppSettings

IN_PERIOD = datetime(2026, 3, 10, 9, 0, tzinfo=UTC)
BEFORE_PERIOD = datetime(2026, 1, 5, 9, 0, tzinfo=UTC)


@pytest.fixture()
def env(tmp_path: Path):
    database = Database(tmp_path / "catalog.sqlite3")
    catalog = Catalog(database)
    members = Members(database)
    settings = AppSettings(database)
    loans = Loans(database, settings)
    challenges = Challenges(database)
    a = members.add(
        member_type="student", school_number="1", first_name="Ayşe", last_name="A",
        class_name="9-A",
    )
    b = members.add(
        member_type="student", school_number="2", first_name="Berk", last_name="B",
        class_name="9-A",
    )
    c = members.add(
        member_type="student", school_number="3", first_name="Can", last_name="C",
        class_name="9-B",
    )
    books = [
        catalog.save_book(BookInput(title=f"Kitap {i}", copy=CopyInput(inventory_code=f"H-{i:04d}")))
        for i in range(1, 5)
    ]
    return database, catalog, members, settings, loans, challenges, a, b, c, books


def _checkout_and_return(loans, member_id, edition_id, when):
    loan = loans.checkout(member_id, edition_id=edition_id, now=when)
    return loans.return_loan(loan.id, now=when)


class TestChallengeCrud:
    def test_create_requires_positive_target(self, env) -> None:
        *_, challenges, _, _, _, _ = env
        with pytest.raises(ValueError):
            challenges.create(
                name="Yarışma", start_date="2026-01-01", end_date="2026-06-01", target_books=0,
            )

    def test_class_scope_requires_class_name(self, env) -> None:
        *_, challenges, _, _, _, _ = env
        with pytest.raises(ValueError):
            challenges.create(
                name="Yarışma", start_date="2026-01-01", end_date="2026-06-01",
                target_books=3, scope="class",
            )

    def test_malformed_dates_are_rejected(self, env) -> None:
        *_, challenges, _, _, _, _ = env
        with pytest.raises(ValueError):
            challenges.create(
                name="Yarışma", start_date="2026-2-1", end_date="2026-06-01", target_books=3,
            )
        with pytest.raises(ValueError):
            challenges.create(
                name="Yarışma", start_date="2026-01-01", end_date="bilinmeyen", target_books=3,
            )

    def test_update_rejects_malformed_date(self, env) -> None:
        *_, challenges, _, _, _, _ = env
        created = challenges.create(
            name="Yarışma", start_date="2026-01-01", end_date="2026-06-01", target_books=3,
        )
        with pytest.raises(ValueError):
            challenges.update(created.id, start_date="not-a-date")

    def test_create_update_archive(self, env) -> None:
        *_, challenges, _, _, _, _ = env
        created = challenges.create(
            name="Bahar Okuma Şenliği", start_date="2026-01-01", end_date="2026-06-01",
            target_books=3,
        )
        assert created.status == "active"
        updated = challenges.update(created.id, name="Bahar Şenliği Yeni")
        assert updated.name == "Bahar Şenliği Yeni"
        archived = challenges.archive(created.id)
        assert archived.status == "archived"

    def test_update_unknown_challenge_raises(self, env) -> None:
        *_, challenges, _, _, _, _ = env
        with pytest.raises(KeyError):
            challenges.update(999_999, name="x")


class TestStandings:
    def test_only_loans_returned_within_period_count(self, env) -> None:
        _, _, _, _, loans, challenges, a, b, _c, books = env
        challenge = challenges.create(
            name="Şenlik", start_date="2026-03-01", end_date="2026-03-31", target_books=2,
        )
        _checkout_and_return(loans, a.id, books[0].edition_id, IN_PERIOD)
        # Dönem dışı ödünç sayılmamalı.
        _checkout_and_return(loans, a.id, books[1].edition_id, BEFORE_PERIOD)
        # İade edilmemiş (aktif) ödünç sayılmamalı.
        loans.checkout(b.id, edition_id=books[2].edition_id, now=IN_PERIOD)

        result = challenges.standings(challenge.id)
        by_id = {row["member_id"]: row for row in result["standings"]}
        assert by_id[a.id]["book_count"] == 1
        assert by_id[b.id]["book_count"] == 0
        assert by_id[a.id]["reached_target"] is False

    def test_reached_target_flag(self, env) -> None:
        _, _, _, _, loans, challenges, a, _, _, books = env
        challenge = challenges.create(
            name="Şenlik", start_date="2026-03-01", end_date="2026-03-31", target_books=1,
        )
        _checkout_and_return(loans, a.id, books[0].edition_id, IN_PERIOD)
        result = challenges.standings(challenge.id)
        row = next(r for r in result["standings"] if r["member_id"] == a.id)
        assert row["reached_target"] is True

    def test_class_scope_filters_members(self, env) -> None:
        _, _, _, _, loans, challenges, a, b, c, books = env
        challenge = challenges.create(
            name="9-A Şenliği", start_date="2026-03-01", end_date="2026-03-31",
            target_books=1, scope="class", class_name="9-A",
        )
        _checkout_and_return(loans, c.id, books[0].edition_id, IN_PERIOD)  # 9-B, hariç tutulmalı
        result = challenges.standings(challenge.id)
        member_ids = {row["member_id"] for row in result["standings"]}
        assert a.id in member_ids and b.id in member_ids
        assert c.id not in member_ids

    def test_class_league_totals_and_averages(self, env) -> None:
        _, _, _, _, loans, challenges, a, b, c, books = env
        challenge = challenges.create(
            name="Şenlik", start_date="2026-03-01", end_date="2026-03-31", target_books=5,
        )
        _checkout_and_return(loans, a.id, books[0].edition_id, IN_PERIOD)
        _checkout_and_return(loans, a.id, books[1].edition_id, IN_PERIOD)
        _checkout_and_return(loans, b.id, books[2].edition_id, IN_PERIOD)
        _checkout_and_return(loans, c.id, books[3].edition_id, IN_PERIOD)

        result = challenges.standings(challenge.id)
        league = {row["class_name"]: row for row in result["class_league"]}
        assert league["9-A"]["total_books"] == 3
        assert league["9-A"]["member_count"] == 2
        assert league["9-A"]["average"] == 1.5
        assert league["9-B"]["total_books"] == 1

    def test_standings_for_unknown_challenge_raises(self, env) -> None:
        *_, challenges, _, _, _, _ = env
        with pytest.raises(KeyError):
            challenges.standings(999_999)


class TestCertificates:
    def test_record_certificate_upserts_on_reprint(self, env) -> None:
        *_, challenges, a, _, _, _ = env
        challenge = challenges.create(
            name="Şenlik", start_date="2026-01-01", end_date="2026-06-01", target_books=3,
        )
        first = challenges.record_certificate(challenge.id, a.id, rank=1)
        second = challenges.record_certificate(challenge.id, a.id, rank=2)
        assert first["id"] == second["id"]
        assert second["rank"] == 2
        certs = challenges.list_certificates(challenge.id)
        assert len(certs) == 1
        assert certs[0]["rank"] == 2

    def test_record_certificate_unknown_member_raises(self, env) -> None:
        *_, challenges, _, _, _, _ = env
        challenge = challenges.create(
            name="Şenlik", start_date="2026-01-01", end_date="2026-06-01", target_books=3,
        )
        with pytest.raises(KeyError):
            challenges.record_certificate(challenge.id, 999_999, rank=1)


fastapi = pytest.importorskip("fastapi")


@pytest.fixture()
def http_env(tmp_path: Path):
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
                "first_name": "Ayşe", "last_name": "A", "class_name": "9-A",
            },
        ).json()
        book = client.post("/api/books", json={"title": "Kitap", "copy_count": 1}).json()
        yield client, member, book["edition_id"]


class TestChallengesHttp:
    def test_create_standings_and_certificate_flow(self, http_env) -> None:
        client, member, edition_id = http_env
        created = client.post(
            "/api/challenges",
            json={
                "name": "Bahar Okuma Şenliği", "start_date": "2026-01-01",
                "end_date": "2026-12-31", "target_books": 1,
            },
        )
        assert created.status_code == 201, created.text
        challenge_id = created.json()["id"]

        client.post("/api/loans", json={"member_id": member["id"], "edition_id": edition_id})
        loan_id = client.get(f"/api/loans?member_id={member['id']}").json()["items"][0]["id"]
        client.post(f"/api/loans/{loan_id}/return")

        standings = client.get(f"/api/challenges/{challenge_id}/standings")
        assert standings.status_code == 200
        row = next(r for r in standings.json()["standings"] if r["member_id"] == member["id"])
        assert row["book_count"] == 1
        assert row["reached_target"] is True

        cert = client.post(
            f"/api/challenges/{challenge_id}/certificates",
            json={"member_id": member["id"], "rank": 1},
        )
        assert cert.status_code == 201, cert.text
        listed = client.get(f"/api/challenges/{challenge_id}/certificates").json()
        assert listed["items"][0]["rank"] == 1

        archived = client.patch(f"/api/challenges/{challenge_id}", json={"status": "archived"})
        assert archived.status_code == 200
        assert archived.json()["status"] == "archived"
