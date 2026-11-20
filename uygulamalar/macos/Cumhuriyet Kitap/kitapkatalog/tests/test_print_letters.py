"""Veli mektubu yazdırma sayfası testleri (/print/letters)."""

from __future__ import annotations

from pathlib import Path

import pytest

fastapi = pytest.importorskip("fastapi")

from fastapi.testclient import TestClient  # noqa: E402

from kitapkatalog.application import open_application  # noqa: E402
from kitapkatalog.config import AppPaths  # noqa: E402
from kitapkatalog.webapp.app import create_app  # noqa: E402


@pytest.fixture()
def client(tmp_path: Path):
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
    with TestClient(app, base_url="http://127.0.0.1") as test_client:
        test_client.get(f"/?token={app.state.web.token}", follow_redirects=False)
        yield test_client


def _overdue_member(client: TestClient, *, school_number: str, title: str, isbn: str) -> dict:
    book = client.post(
        "/api/books",
        json={
            "title": title,
            "authors": "Test Yazar",
            "isbn": isbn,
            "location": "Dolap A",
            "copy_count": 1,
        },
    )
    assert book.status_code == 201, book.text
    member = client.post(
        "/api/members",
        json={
            "member_type": "student",
            "school_number": school_number,
            "first_name": "Geciken",
            "last_name": f"Öğrenci {school_number}",
            "class_name": "7-B",
        },
    ).json()
    loan = client.post("/api/loans", json={"member_id": member["id"], "isbn": isbn})
    assert loan.status_code == 201, loan.text
    database = client.app.state.web.database
    with database.transaction() as connection:
        connection.execute(
            "UPDATE loan SET due_at = '2000-01-01' WHERE id = ?", (loan.json()["id"],)
        )
    return member


def test_letters_require_session(tmp_path: Path) -> None:
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
    with TestClient(app, base_url="http://127.0.0.1") as anon:
        assert anon.get("/print/letters").status_code == 401


def test_letters_one_page_per_member_with_school_name(client: TestClient) -> None:
    client.put("/api/settings", json={"school_name": "Atatürk Ortaokulu"})
    _overdue_member(client, school_number="101", title="Beyaz Gemi", isbn="9789750718533")
    _overdue_member(client, school_number="102", title="Küçük Prens", isbn="9789750726477")

    page = client.get("/print/letters")
    assert page.status_code == 200
    assert page.headers["cache-control"] == "no-store"
    assert page.text.count('class="mektup"') == 2
    assert "Atatürk Ortaokulu" in page.text
    assert "Sayın Velimiz" in page.text
    assert "Beyaz Gemi" in page.text and "Küçük Prens" in page.text
    assert "7-B" in page.text


def test_letters_single_member_filter_and_escape(client: TestClient) -> None:
    member = _overdue_member(
        client, school_number="103", title="<b>Kötü</b> Başlık", isbn="9789750733314"
    )
    _overdue_member(client, school_number="104", title="Diğer Kitap", isbn="9789750500930")

    single = client.get(f"/print/letters?member_id={member['id']}")
    assert single.status_code == 200
    assert single.text.count('class="mektup"') == 1
    assert "&lt;b&gt;Kötü&lt;/b&gt;" in single.text
    assert "Diğer Kitap" not in single.text

    assert client.get("/print/letters?member_id=999999").status_code == 404
    assert client.get("/print/letters?kind=bilinmeyen").status_code == 400


def test_letters_empty_state(client: TestClient) -> None:
    page = client.get("/print/letters")
    assert page.status_code == 200
    assert "mektup gerekmiyor" in page.text


def test_inventory_ledger_lists_copies(client: TestClient) -> None:
    client.put("/api/settings", json={"school_name": "Cumhuriyet Lisesi"})
    book = client.post(
        "/api/books",
        json={
            "title": "Demirbaş Kitabı",
            "authors": "Yazar Bir; Yazar İki",
            "isbn": "9789750718533",
            "publisher": "Deneme",
            "location": "Dolap A",
            "copy_count": 2,
        },
    )
    assert book.status_code == 201
    client.post("/api/copies/assign-codes", json={"scope": "all"})

    page = client.get("/print/inventory-ledger")
    assert page.status_code == 200
    assert "Cumhuriyet Lisesi" in page.text
    assert "Demirbaş Kitabı" in page.text
    assert "Yazar Bir" in page.text
    assert "Toplam 2 nüsha" in page.text

    assert client.get("/print/inventory-ledger?year=abcd").status_code == 400
    empty = client.get("/print/inventory-ledger?year=1999")
    assert "Kapsamda nüsha yok" in empty.text


def test_annual_report_print_renders_sections(client: TestClient) -> None:
    _overdue_member(client, school_number="777", title="Rapor Kitabı", isbn="9789750718533")
    page = client.get("/print/annual-report?start=2000-01-01&end=2099-12-31")
    assert page.status_code == 200
    for heading in ("Koleksiyon", "Dolaşım", "En Çok Okunan 10 Kitap", "Yaş Analizi"):
        assert heading in page.text
    assert "Rapor Kitabı" in page.text


def test_certificate_renders_for_challenge_member(client: TestClient) -> None:
    client.put("/api/settings", json={"school_name": "Gazi Ortaokulu"})
    book = client.post(
        "/api/books",
        json={
            "title": "Yarışma Kitabı",
            "authors": "Test Yazar",
            "isbn": "9789750718533",
            "location": "Dolap A",
            "copy_count": 1,
        },
    )
    assert book.status_code == 201
    member = client.post(
        "/api/members",
        json={
            "member_type": "student",
            "school_number": "801",
            "first_name": "Okuyan",
            "last_name": "Şampiyon",
            "class_name": "6-C",
        },
    ).json()
    loan = client.post(
        "/api/loans", json={"member_id": member["id"], "isbn": "9789750718533"}
    ).json()
    returned = client.post(
        "/api/loans/return-by-code", json={"code": "9789750718533"}
    )
    assert returned.status_code == 200, loan
    challenge = client.post(
        "/api/challenges",
        json={
            "name": "Kitap Kurdu 2026",
            "start_date": "2020-01-01",
            "end_date": "2099-12-31",
            "target_books": 1,
        },
    ).json()
    recorded = client.post(
        f"/api/challenges/{challenge['id']}/certificates",
        json={"member_id": member["id"], "rank": 1},
    )
    assert recorded.status_code in (200, 201), recorded.text

    page = client.get(
        f"/print/certificate?challenge_id={challenge['id']}&member_id={member['id']}"
    )
    assert page.status_code == 200
    assert "Gazi Ortaokulu" in page.text
    assert "Okuyan Şampiyon" in page.text
    assert "Kitap Kurdu 2026" in page.text
    assert "1. sıra" in page.text

    assert client.get("/print/certificate?challenge_id=999&member_id=1").status_code == 404
    assert (
        client.get(
            f"/print/certificate?challenge_id={challenge['id']}&member_id=999999"
        ).status_code
        == 404
    )
