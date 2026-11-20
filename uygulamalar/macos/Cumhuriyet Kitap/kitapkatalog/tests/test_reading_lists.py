"""Okuma listeleri: CRUD, kitap/üye atama, ilerleme türetme, OPAC görünürlüğü, şablon."""

from __future__ import annotations

from datetime import UTC, datetime
from pathlib import Path

import pytest

from kitapkatalog.catalog import Catalog
from kitapkatalog.database import Database, StateConflictError
from kitapkatalog.domain import BookInput, CopyInput
from kitapkatalog.loans import Loans
from kitapkatalog.members import Members
from kitapkatalog.reading_lists import ReadingLists
from kitapkatalog.settings import AppSettings

NOW = datetime(2026, 3, 10, 9, 0, tzinfo=UTC)


@pytest.fixture()
def env(tmp_path: Path):
    database = Database(tmp_path / "catalog.sqlite3")
    catalog = Catalog(database)
    members = Members(database)
    settings = AppSettings(database)
    loans = Loans(database, settings)
    lists = ReadingLists(database)
    student = members.add(
        member_type="student", school_number="1", first_name="Ayşe", last_name="A",
        class_name="9-A",
    )
    book_a = catalog.save_book(
        BookInput(title="Küçük Prens", copy=CopyInput(inventory_code="H-0001"))
    )
    book_b = catalog.save_book(
        BookInput(title="Kaşağı", copy=CopyInput(inventory_code="H-0002"))
    )
    return database, catalog, members, loans, lists, student, book_a, book_b


class TestListCrud:
    def test_create_requires_a_name(self, env) -> None:
        *_, lists, _, _, _ = env
        with pytest.raises(ValueError):
            lists.create(name="  ")

    def test_create_update_delete(self, env) -> None:
        *_, lists, _, _, _ = env
        created = lists.create(name="Yaz Tatili", description="8. sınıf", now=NOW)
        assert created.name == "Yaz Tatili"
        assert created.is_opac_visible is False

        updated = lists.update(created.id, is_opac_visible=True, description=None)
        assert updated.is_opac_visible is True
        assert updated.description is None

        lists.delete(created.id)
        with pytest.raises(KeyError):
            lists.get(created.id)

    def test_update_unknown_field_rejected(self, env) -> None:
        *_, lists, _, _, _ = env
        created = lists.create(name="Liste")
        with pytest.raises(ValueError):
            lists.update(created.id, unknown_field="x")

    def test_delete_unknown_list_raises(self, env) -> None:
        *_, lists, _, _, _ = env
        with pytest.raises(KeyError):
            lists.delete(999_999)


class TestListItems:
    def test_add_and_remove_item(self, env) -> None:
        *_, lists, _, book_a, _ = env
        created = lists.create(name="Liste")
        item = lists.add_item(created.id, book_a.edition_id)
        assert item.title == "Küçük Prens"
        assert lists.get(created.id).item_count == 1

        lists.remove_item(created.id, book_a.edition_id)
        assert lists.get(created.id).item_count == 0

    def test_duplicate_item_is_rejected(self, env) -> None:
        *_, lists, _, book_a, _ = env
        created = lists.create(name="Liste")
        lists.add_item(created.id, book_a.edition_id)
        with pytest.raises(StateConflictError):
            lists.add_item(created.id, book_a.edition_id)

    def test_add_item_unknown_edition_raises(self, env) -> None:
        *_, lists, _, _, _ = env
        created = lists.create(name="Liste")
        with pytest.raises(KeyError):
            lists.add_item(created.id, 999_999)

    def test_reorder_items(self, env) -> None:
        *_, lists, _, book_a, book_b = env
        created = lists.create(name="Liste")
        lists.add_item(created.id, book_a.edition_id)
        lists.add_item(created.id, book_b.edition_id)
        reordered = lists.reorder_items(created.id, [book_b.edition_id, book_a.edition_id])
        assert [item.edition_id for item in reordered] == [book_b.edition_id, book_a.edition_id]

    def test_reorder_mismatched_set_rejected(self, env) -> None:
        *_, lists, _, book_a, book_b = env
        created = lists.create(name="Liste")
        lists.add_item(created.id, book_a.edition_id)
        with pytest.raises(ValueError):
            lists.reorder_items(created.id, [book_a.edition_id, book_b.edition_id])

    def test_reorder_rejects_duplicate_ids_even_if_set_matches(self, env) -> None:
        *_, lists, _, book_a, book_b = env
        created = lists.create(name="Liste")
        lists.add_item(created.id, book_a.edition_id)
        lists.add_item(created.id, book_b.edition_id)
        # {a, a} == {a, b} kümesel eşitliği YALANCI geçer; uzunluk/tekillik de kontrol edilmeli.
        with pytest.raises(ValueError):
            lists.reorder_items(created.id, [book_a.edition_id, book_a.edition_id])


class TestAssignment:
    def test_assign_and_unassign(self, env) -> None:
        *_, lists, student, _, _ = env
        created = lists.create(name="Liste")
        assignment = lists.assign(created.id, student.id, note="Zorunlu")
        assert assignment.member_name == "Ayşe A"
        assert len(lists.list_assignments(created.id)) == 1

        lists.unassign(created.id, student.id)
        assert lists.list_assignments(created.id) == []

    def test_duplicate_assignment_is_rejected(self, env) -> None:
        *_, lists, student, _, _ = env
        created = lists.create(name="Liste")
        lists.assign(created.id, student.id)
        with pytest.raises(StateConflictError):
            lists.assign(created.id, student.id)

    def test_assign_unknown_member_raises(self, env) -> None:
        *_, lists, _, _, _ = env
        created = lists.create(name="Liste")
        with pytest.raises(KeyError):
            lists.assign(created.id, 999_999)


class TestProgress:
    def test_active_loan_does_not_count(self, env) -> None:
        _, _, _, loans, lists, student, book_a, _ = env
        created = lists.create(name="Liste")
        lists.add_item(created.id, book_a.edition_id)
        loans.checkout(student.id, edition_id=book_a.edition_id, now=NOW)

        progress = lists.progress(created.id, student.id)
        assert progress["completed"] == 0
        assert progress["total"] == 1
        assert progress["fraction"] == 0.0

    def test_returned_loan_counts_once(self, env) -> None:
        _, _, _, loans, lists, student, book_a, _ = env
        created = lists.create(name="Liste")
        lists.add_item(created.id, book_a.edition_id)
        loan = loans.checkout(student.id, edition_id=book_a.edition_id, now=NOW)
        loans.return_loan(loan.id, now=NOW)

        progress = lists.progress(created.id, student.id)
        assert progress["completed"] == 1
        assert progress["fraction"] == 1.0

        # Aynı baskı ikinci kez ödünç alınıp iade edilse bile ilerleme 1 kalır
        # (DISTINCT edition_id — liste boyutunu aşan bir sayaç anlamsız olurdu).
        second = loans.checkout(student.id, edition_id=book_a.edition_id, now=NOW)
        loans.return_loan(second.id, now=NOW)
        progress_again = lists.progress(created.id, student.id)
        assert progress_again["completed"] == 1

    def test_member_progress_spans_multiple_lists(self, env) -> None:
        _, _, _, loans, lists, student, book_a, book_b = env
        list_one = lists.create(name="Liste 1")
        list_two = lists.create(name="Liste 2")
        lists.add_item(list_one.id, book_a.edition_id)
        lists.add_item(list_two.id, book_b.edition_id)
        lists.assign(list_one.id, student.id)
        lists.assign(list_two.id, student.id)
        loan = loans.checkout(student.id, edition_id=book_a.edition_id, now=NOW)
        loans.return_loan(loan.id, now=NOW)

        overview = lists.member_progress(student.id)
        by_name = {entry["list_name"]: entry for entry in overview}
        assert by_name["Liste 1"]["completed"] == 1
        assert by_name["Liste 2"]["completed"] == 0


class TestOpacVisibility:
    def test_only_visible_lists_are_returned(self, env) -> None:
        *_, lists, student, book_a, _ = env
        visible = lists.create(name="Görünür", is_opac_visible=True)
        lists.create(name="Gizli", is_opac_visible=False)
        lists.add_item(visible.id, book_a.edition_id)
        lists.assign(visible.id, student.id)

        opac_data = lists.opac_lists()
        names = [entry["name"] for entry in opac_data]
        assert "Görünür" in names
        assert "Gizli" not in names
        entry = next(e for e in opac_data if e["name"] == "Görünür")
        assert entry["items"][0]["title"] == "Küçük Prens"
        # Üye/atama alanları OPAC gövdesine asla sızmaz.
        dumped = str(entry)
        assert "Ayşe" not in dumped
        assert "member" not in entry


class TestTemplateImport:
    def test_import_matches_close_titles(self, env) -> None:
        _, catalog, _, _, lists, *_ = env
        catalog.save_book(BookInput(title="Kucuk Prens"))  # aksansız yazım
        result = lists.import_template("100-temel-eser")
        matched_titles = {item["template_title"] for item in result["matched"]}
        assert "Küçük Prens" in matched_titles
        assert "Kaşağı" in matched_titles
        assert result["unmatched"]
        assert result["list"]["name"] == "100 Temel Eser"

    def test_import_is_idempotent_and_reuses_the_same_list(self, env) -> None:
        _, _catalog, _, _, lists, *_ = env
        first = lists.import_template("100-temel-eser")
        second = lists.import_template("100-temel-eser")
        assert first["list"]["id"] == second["list"]["id"]
        assert lists.get(first["list"]["id"]).item_count == len(first["matched"])

    def test_unknown_template_raises(self, env) -> None:
        *_, lists, _, _, _ = env
        with pytest.raises(KeyError):
            lists.import_template("bilinmeyen-sablon")


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
        book = client.post("/api/books", json={"title": "Küçük Prens", "copy_count": 1}).json()
        member = client.post(
            "/api/members",
            json={
                "member_type": "student", "school_number": "1",
                "first_name": "Ayşe", "last_name": "A", "class_name": "9-A",
            },
        ).json()
        yield client, member, book["edition_id"]


class TestReadingListsHttp:
    def test_crud_items_and_assignment_flow(self, http_env) -> None:
        client, member, edition_id = http_env
        created = client.post("/api/lists", json={"name": "Yaz Listesi"})
        assert created.status_code == 201, created.text
        list_id = created.json()["id"]

        added = client.post(f"/api/lists/{list_id}/items", json={"edition_id": edition_id})
        assert added.status_code == 201, added.text

        assigned = client.post(
            f"/api/lists/{list_id}/assign", json={"member_id": member["id"]}
        )
        assert assigned.status_code == 201, assigned.text

        detail = client.get(f"/api/lists/{list_id}").json()
        assert detail["items"][0]["edition_id"] == edition_id
        assert detail["assignments"][0]["member_id"] == member["id"]

        progress = client.get(f"/api/lists/{list_id}/progress?member_id={member['id']}").json()
        assert progress["total"] == 1
        assert progress["completed"] == 0

        removed = client.delete(f"/api/lists/{list_id}/items/{edition_id}")
        assert removed.status_code == 204

        unassigned = client.delete(f"/api/lists/{list_id}/assign/{member['id']}")
        assert unassigned.status_code == 204

    def test_opac_lists_endpoint_hides_hidden_lists_and_member_data(self, http_env) -> None:
        client, member, edition_id = http_env
        visible = client.post(
            "/api/lists", json={"name": "Görünür", "is_opac_visible": True}
        ).json()
        client.post("/api/lists", json={"name": "Gizli", "is_opac_visible": False})
        client.post(f"/api/lists/{visible['id']}/items", json={"edition_id": edition_id})
        client.post(f"/api/lists/{visible['id']}/assign", json={"member_id": member["id"]})

        response = client.get("/api/opac/lists")
        assert response.status_code == 200
        items = response.json()["items"]
        names = [entry["name"] for entry in items]
        assert "Görünür" in names
        assert "Gizli" not in names
        assert "Ayşe" not in str(items)

    def test_template_endpoint(self, http_env) -> None:
        client, *_ = http_env
        response = client.post("/api/lists/template/100-temel-eser")
        assert response.status_code == 200, response.text
        body = response.json()
        assert "matched" in body and "unmatched" in body
        assert any(item["template_title"] == "Küçük Prens" for item in body["matched"])
