"""Dolap hedefli içe aktarma ve geliştirilmiş toplu aktarım sözleşmeleri.

Kapsam: v9 şeması (iş/öğe dolabı), çok kitaplı PDF bölme, klasör adından dolap
türetme, tek kitabın tek belgeden alınması ve iş yönetimi uçları.
"""

from __future__ import annotations

import io
import sqlite3
import zipfile
from pathlib import Path

import pytest
from PIL import Image

from kitapkatalog.catalog import Catalog
from kitapkatalog.database import SCHEMA_VERSION, Database, StateConflictError
from kitapkatalog.documents import (
    expand_bulk_documents,
    folder_locations,
)
from kitapkatalog.domain import BookInput, ImagePair, JobItemStage
from kitapkatalog.pairing import pair_cover_files
from kitapkatalog.webapp.uploads import safe_relative_directory, staging_folder


def _pdf(path: Path, colors: list[str]) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    pages = [Image.new("RGB", (180, 240), color) for color in colors]
    pages[0].save(path, "PDF", save_all=True, append_images=pages[1:], resolution=72)
    return path


def _image(path: Path, color: str = "red") -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.new("RGB", (120, 160), color).save(path, format="PNG")
    return path


def _pair(index: int, root: Path) -> ImagePair:
    return ImagePair(
        root / f"on-{index}.png",
        root / f"arka-{index}.png",
        pair_key=f"kitap-{index}",
    )


# ---------------------------------------------------------------- şema v9


def test_v9_adds_location_columns_to_a_v8_database(tmp_path: Path) -> None:
    path = tmp_path / "catalog.sqlite3"
    with sqlite3.connect(path, isolation_level=None) as connection:
        connection.create_collation(
            "UNICODE_NOCASE", lambda left, right: (left.casefold() > right.casefold()) - (
                left.casefold() < right.casefold()
            )
        )
        connection.execute("PRAGMA foreign_keys = ON")
        for version in range(1, 9):
            getattr(Database, f"_migrate_v{version}")(connection)

    database = Database(path)

    with database.connection(readonly=True) as connection:
        # Database(path) her zaman GÜNCEL şemaya kadar geçişi tamamlar; bu test
        # yalnız v9'un eklediği sütunları doğrular, en son sürümü değil.
        assert connection.execute("PRAGMA user_version").fetchone()[0] == SCHEMA_VERSION
        job_columns = {row[1] for row in connection.execute("PRAGMA table_info(import_job)")}
        item_columns = {row[1] for row in connection.execute("PRAGMA table_info(job_item)")}
        assert "location" in job_columns
        assert "location" in item_columns
        assert connection.execute(
            "SELECT 1 FROM schema_migration WHERE version = 9"
        ).fetchone()


def test_v9_migration_can_be_re_entered_without_duplicate_columns(tmp_path: Path) -> None:
    database = Database(tmp_path / "catalog.sqlite3")
    with database.connection() as connection:
        connection.execute("PRAGMA user_version = 8")
    # Sürüm elle geri alınmış bir veritabanı v9'a yeniden girebilmelidir.
    Database(tmp_path / "catalog.sqlite3")


# ------------------------------------------------------- iş ve öğe dolabı


def test_batch_shelf_is_stored_and_item_shelf_overrides_it(tmp_path: Path) -> None:
    database = Database(tmp_path / "catalog.sqlite3")

    job = database.create_import_job(
        "Parti",
        [_pair(1, tmp_path), _pair(2, tmp_path)],
        location="  Dolap 3  ",
        locations={"kitap-2": "Dolap 9"},
    )

    assert job.location == "Dolap 3"
    items = {item.pair_key: item for item in database.list_job_items(job.id)}
    assert items["kitap-1"].location is None
    assert items["kitap-2"].location == "Dolap 9"
    assert database.get_import_job(job.id).location == "Dolap 3"


def test_appended_chunks_keep_their_folder_shelves(tmp_path: Path) -> None:
    database = Database(tmp_path / "catalog.sqlite3")
    job = database.create_import_job("Parti", [_pair(1, tmp_path)], location="Dolap 1")

    database.append_job_items(job.id, [_pair(2, tmp_path)], locations={"kitap-2": "Dolap 5"})

    items = {item.pair_key: item for item in database.list_job_items(job.id)}
    assert items["kitap-2"].location == "Dolap 5"


def test_job_shelf_can_be_changed_later(tmp_path: Path) -> None:
    database = Database(tmp_path / "catalog.sqlite3")
    job = database.create_import_job("Parti", [_pair(1, tmp_path)])

    updated = database.set_job_location(job.id, "Dolap 7")

    assert updated.location == "Dolap 7"
    assert database.set_job_location(job.id, "  ").location is None
    with pytest.raises(KeyError):
        database.set_job_location("yok", "Dolap 7")


def test_location_summary_falls_back_to_the_batch_shelf(tmp_path: Path) -> None:
    database = Database(tmp_path / "catalog.sqlite3")
    job = database.create_import_job(
        "Parti",
        [_pair(1, tmp_path), _pair(2, tmp_path)],
        location="Dolap 1",
        locations={"kitap-2": "Dolap 2"},
    )

    summary = {row["name"]: row["count"] for row in database.job_location_summary(job.id)}

    assert summary == {"Dolap 1": 1, "Dolap 2": 1}


# ------------------------------------------------------- iş yönetim uçları


def test_a_job_that_catalogued_books_cannot_be_deleted(tmp_path: Path) -> None:
    database = Database(tmp_path / "catalog.sqlite3")
    job = database.create_import_job("Parti", [_pair(1, tmp_path)])
    item = database.list_job_items(job.id)[0]
    with database.transaction(immediate=True) as connection:
        connection.execute(
            "UPDATE job_item SET stage = ? WHERE id = ?",
            (JobItemStage.COMPLETED.value, item.id),
        )

    with pytest.raises(StateConflictError):
        database.delete_import_job(job.id)

    assert database.get_import_job(job.id) is not None


def test_a_running_job_must_be_cancelled_before_deletion(tmp_path: Path) -> None:
    database = Database(tmp_path / "catalog.sqlite3")
    job = database.create_import_job("Parti", [_pair(1, tmp_path)])

    with pytest.raises(StateConflictError, match="önce iptal"):
        database.delete_import_job(job.id)

    database.cancel_job(job.id)
    database.delete_import_job(job.id)
    assert database.get_import_job(job.id) is None


def test_a_leased_item_blocks_deletion(tmp_path: Path) -> None:
    database = Database(tmp_path / "catalog.sqlite3")
    job = database.create_import_job("Parti", [_pair(1, tmp_path)])
    database.claim_next_item("worker", job_id=job.id, lease_seconds=300)
    database.cancel_job(job.id)

    # İptal öğeyi terminale çeker ama işçi hâlâ o kitabın içinde olabilir.
    with database.transaction(immediate=True) as connection:
        connection.execute(
            "UPDATE job_item SET lease_until = ? WHERE job_id = ?",
            ("9999-01-01T00:00:00.000000+00:00", job.id),
        )

    with pytest.raises(StateConflictError, match="işçi"):
        database.delete_import_job(job.id)


def test_an_untouched_job_is_deleted_with_its_items(tmp_path: Path) -> None:
    database = Database(tmp_path / "catalog.sqlite3")
    job = database.create_import_job("Parti", [_pair(1, tmp_path)])
    database.cancel_job(job.id)

    database.delete_import_job(job.id)

    assert database.get_import_job(job.id) is None
    assert database.fetchone(
        "SELECT COUNT(*) AS total FROM job_item WHERE job_id = ?", (job.id,)
    )["total"] == 0
    with pytest.raises(KeyError):
        database.delete_import_job(job.id)


def test_failed_items_are_requeued_in_one_call(tmp_path: Path) -> None:
    database = Database(tmp_path / "catalog.sqlite3")
    job = database.create_import_job("Parti", [_pair(1, tmp_path), _pair(2, tmp_path)])
    while (claimed := database.claim_next_item("worker", job_id=job.id)) is not None:
        database.fail_item(claimed.id, "worker", "motor hatası", max_retries=0)
    assert database.get_import_job(job.id).failed_items == 2

    requeued, remaining = database.retry_failed_items(job.id)

    assert (requeued, remaining) == (2, 0)
    stages = {item.stage for item in database.list_job_items(job.id)}
    assert stages == {JobItemStage.PAIRED}
    assert database.get_import_job(job.id).failed_items == 0


def test_bulk_retry_reports_what_it_could_not_reach(tmp_path: Path) -> None:
    database = Database(tmp_path / "catalog.sqlite3")
    job = database.create_import_job(
        "Parti", [_pair(index, tmp_path) for index in range(1, 4)]
    )
    while (claimed := database.claim_next_item("worker", job_id=job.id)) is not None:
        database.fail_item(claimed.id, "worker", "motor hatası", max_retries=0)

    requeued, remaining = database.retry_failed_items(job.id, limit=2)

    # Sessiz kırpma yok: kalan öğe sayısı çağırana bildirilir.
    assert (requeued, remaining) == (2, 1)


def test_a_cancelled_job_is_not_resurrected_by_a_bulk_retry(tmp_path: Path) -> None:
    database = Database(tmp_path / "catalog.sqlite3")
    job = database.create_import_job("Parti", [_pair(1, tmp_path), _pair(2, tmp_path)])
    claimed = database.claim_next_item("worker", job_id=job.id)
    database.fail_item(claimed.id, "worker", "motor hatası", max_retries=0)
    database.cancel_job(job.id)

    with pytest.raises(StateConflictError, match="İptal edilmiş"):
        database.retry_failed_items(job.id)

    assert database.get_import_job(job.id).status.value == "cancelled"


# ------------------------------------------------- çok kitaplı PDF bölme


def test_a_multiple_of_four_pdf_becomes_that_many_books(tmp_path: Path) -> None:
    source = _pdf(
        tmp_path / "tarama.pdf",
        ["red", "green", "blue", "yellow", "purple", "orange", "cyan", "magenta"],
    )

    expanded = expand_bulk_documents([source], tmp_path / "rendered")

    assert len(expanded.four_page_books) == 2
    assert not expanded.rejected
    assert expanded.split_documents == ((source, 2),)
    keys = {book.pair_key for book in expanded.four_page_books}
    assert len(keys) == 2
    firsts = {book.front for book in expanded.four_page_books}
    assert len(firsts) == 2


def test_an_oversized_pdf_is_rejected_instead_of_split(tmp_path: Path, monkeypatch) -> None:
    source = _pdf(tmp_path / "dev.pdf", ["red", "green", "blue", "yellow"])
    monkeypatch.setattr("kitapkatalog.documents.MAX_BOOKS_PER_PDF", 0)

    expanded = expand_bulk_documents([source], tmp_path / "rendered")

    assert not expanded.four_page_books
    assert "en fazla" in expanded.rejected[0][1]


# ------------------------------------------------ klasörden dolap türetme


def test_folder_names_become_per_book_shelves(tmp_path: Path) -> None:
    root = tmp_path / "yukleme"
    for index in range(1, 5):
        _image(root / "Dolap 1" / f"kitap-{index}.png")
    pdf = _pdf(root / "Dolap 2" / "tarama.pdf", ["red", "green", "blue", "yellow"])
    kok = _image(root / "koksuz-1.png")
    for index in range(2, 5):
        _image(root / f"koksuz-{index}.png")

    documents = [*sorted(root.rglob("*.png")), pdf]
    expanded = expand_bulk_documents(documents, tmp_path / "rendered")
    pairing = pair_cover_files(
        expanded.images, infer_sequence=True, require_four_surfaces=True
    )
    pairs = (*expanded.four_page_books, *pairing.pairs)

    locations = folder_locations(pairs, expanded, root=root)

    assert sorted(set(locations.values())) == ["Dolap 1", "Dolap 2"]
    # Seçim kökünde duran kitaplar kökün adını miras almaz; parti dolabına kalır.
    assert len(locations) == len(pairs) - 1
    assert kok.exists()


def test_single_page_pdfs_keep_the_folder_of_their_source(tmp_path: Path) -> None:
    root = tmp_path / "yukleme"
    pages = [
        _pdf(root / "Dolap 4" / f"sayfa-{index}.pdf", ["red"]) for index in range(1, 5)
    ]

    expanded = expand_bulk_documents(pages, tmp_path / "rendered")
    pairing = pair_cover_files(
        expanded.images, infer_sequence=True, require_four_surfaces=True
    )
    pairs = (*expanded.four_page_books, *pairing.pairs)

    assert pairs
    assert set(folder_locations(pairs, expanded, root=root).values()) == {"Dolap 4"}


def test_a_changed_job_shelf_does_not_rewrite_already_catalogued_books(tmp_path: Path) -> None:
    """Kataloglanmış kitap eski dolabında kalır; özet de öyle göstermelidir."""

    database = Database(tmp_path / "catalog.sqlite3")
    job = database.create_import_job(
        "Parti", [_pair(1, tmp_path), _pair(2, tmp_path)], location="Dolap 1"
    )
    done = database.list_job_items(job.id)[0]
    with database.transaction(immediate=True) as connection:
        connection.execute(
            "UPDATE job_item SET stage = ? WHERE id = ?",
            (JobItemStage.COMPLETED.value, done.id),
        )

    database.set_job_location(job.id, "Dolap 2")

    summary = {row["name"]: row["count"] for row in database.job_location_summary(job.id)}
    assert summary == {"Dolap 1": 1, "Dolap 2": 1}
    items = {item.pair_key: item.location for item in database.list_job_items(job.id)}
    assert items["kitap-1"] == "Dolap 1"
    assert items["kitap-2"] is None


def test_colliding_single_page_names_do_not_overwrite_each_other(tmp_path: Path) -> None:
    """`kitap 1` ile `kitap_1` aynı ada iner; sayfa sessizce ezilmemeli."""

    root = tmp_path / "kaynak"
    first = _pdf(root / "kitap 1.pdf", ["red"])
    second = _pdf(root / "kitap_1.pdf", ["blue"])

    expanded = expand_bulk_documents([first, second], tmp_path / "rendered")

    assert len(expanded.images) == 2
    assert len(set(expanded.images)) == 2
    origins = dict(expanded.image_origins)
    # Her üretilmiş görüntü kendi kaynağını korur.
    assert sorted(origins.values()) == sorted([first, second])
    digests = {path.read_bytes() for path in expanded.images}
    assert len(digests) == 2


def test_web_staging_keeps_similar_folders_apart(tmp_path: Path) -> None:
    """Sanitize sonrası aynı ada inen iki klasör staging'de birleşmemeli."""

    first = staging_folder("Dolap 1/kitap-1.png")
    second = staging_folder("Dolap_1/kitap-1.png")

    assert first is not None and second is not None
    assert first[0] != second[0]
    # Dolap adı okunur kalır; ayrıştırma yalnız dizin adındadır.
    assert first[1] == "Dolap 1"
    assert staging_folder("kitap-1.png") is None


def test_summary_reports_the_real_shelf_of_catalogued_books(tmp_path: Path) -> None:
    """İlk kez dolap atansa bile kataloğa dolapsız girmiş kitap öyle sayılır."""

    database = Database(tmp_path / "catalog.sqlite3")
    catalog = Catalog(database)
    job = database.create_import_job("Parti", [_pair(1, tmp_path), _pair(2, tmp_path)])
    record = catalog.save_book(BookInput(title="Dolapsız Kitap"), add_copy=True)
    done = database.list_job_items(job.id)[0]
    with database.transaction(immediate=True) as connection:
        connection.execute(
            "UPDATE job_item SET stage = ?, edition_id = ? WHERE id = ?",
            (JobItemStage.COMPLETED.value, record.edition_id, done.id),
        )

    database.set_job_location(job.id, "Dolap 3")

    summary = {row["name"]: row["count"] for row in database.job_location_summary(job.id)}
    # Kataloglanmış kitap gerçekte dolapsız; yalnız bekleyen kitap Dolap 3'e gider.
    assert summary == {None: 1, "Dolap 3": 1}


def test_a_paused_job_is_not_restarted_by_a_bulk_retry(tmp_path: Path) -> None:
    database = Database(tmp_path / "catalog.sqlite3")
    job = database.create_import_job("Parti", [_pair(1, tmp_path), _pair(2, tmp_path)])
    claimed = database.claim_next_item("worker", job_id=job.id)
    database.fail_item(claimed.id, "worker", "motor hatası", max_retries=0)
    database.pause_job(job.id)

    with pytest.raises(StateConflictError, match="Duraklatılmış"):
        database.retry_failed_items(job.id)

    assert database.get_import_job(job.id).status.value == "paused"


def test_render_space_gate_rejects_before_writing_pages(tmp_path: Path, monkeypatch) -> None:
    """Kapasite kapısı iş satırından önce; render kapısı yazmadan önce durur."""

    import shutil as real_shutil

    source = _pdf(tmp_path / "buyuk.pdf", ["red", "green", "blue", "yellow"])
    usage = real_shutil.disk_usage(tmp_path)
    monkeypatch.setattr(
        "kitapkatalog.documents.shutil.disk_usage",
        lambda path: type(usage)(usage.total, usage.used, 4 * 1024**2),
    )

    expanded = expand_bulk_documents([source], tmp_path / "rendered")

    assert not expanded.four_page_books
    assert "yeterli disk yok" in expanded.rejected[0][1]
    assert not (tmp_path / "rendered").exists()


# ------------------------------------------------- göreli yol temizliği


@pytest.mark.parametrize(
    ("filename", "expected"),
    [
        ("Dolap 1/kitap-1.jpg", ("Dolap 1",)),
        # ".." bileşenleri düşer; geriye yalnız düz adlar kalır.
        ("../../etc/passwd", ("etc",)),
        ("a/../../b/c.jpg", ("a", "b")),
        ("/mutlak/yol/x.jpg", ("mutlak", "yol")),
        (".gizli/x.jpg", ("gizli",)),
        ("x.jpg", ()),
        ("", ()),
    ],
)
def test_relative_upload_directories_cannot_escape_staging(
    filename: str, expected: tuple[str, ...]
) -> None:
    assert safe_relative_directory(filename) == expected


def test_relative_upload_directories_are_depth_bounded() -> None:
    deep = "/".join(f"k{index}" for index in range(20)) + "/x.jpg"
    kept = safe_relative_directory(deep, max_depth=3)
    # Kırpma EN İÇTEKİ klasörleri korur: kitabı gruplayan ve dolap adını veren
    # yaprak klasör budur; kökteki ortak ad değil.
    assert kept == ("k17", "k18", "k19")


def test_too_many_files_is_refused_in_turkish(client: TestClient) -> None:
    response = client.post(
        "/api/imports/single",
        files=[("document", (f"s{index}.png", _png_bytes(), "image/png")) for index in range(5)],
    )

    assert response.status_code == 400
    assert "en fazla 4 dosya" in response.json()["detail"]


# ------------------------------------------------------------- web uçları


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


def _pdf_bytes(colors: list[str]) -> io.BytesIO:
    buffer = io.BytesIO()
    pages = [Image.new("RGB", (180, 240), color) for color in colors]
    pages[0].save(buffer, "PDF", save_all=True, append_images=pages[1:], resolution=72)
    buffer.seek(0)
    return buffer


def _png_bytes(color: str = "red") -> io.BytesIO:
    buffer = io.BytesIO()
    Image.new("RGB", (120, 160), color).save(buffer, format="PNG")
    buffer.seek(0)
    return buffer


def test_single_book_can_arrive_as_one_four_page_document(client: TestClient) -> None:
    response = client.post(
        "/api/imports/single",
        files={"document": ("kitap.pdf", _pdf_bytes(["red", "green", "blue", "yellow"]), "application/pdf")},
        data={"shelf": "Dolap 12"},
    )

    assert response.status_code == 201, response.text
    body = response.json()
    assert body["books"] == 1
    assert body["job"]["location"] == "Dolap 12"
    assert body["shelves_created"] == ["Dolap 12"]
    assert "Dolap 12" in {shelf["name"] for shelf in client.get("/api/shelves").json()}


def test_a_single_document_with_the_wrong_page_count_is_refused(client: TestClient) -> None:
    response = client.post(
        "/api/imports/single",
        files={"document": ("kitap.pdf", _pdf_bytes(["red", "green"]), "application/pdf")},
    )

    assert response.status_code == 400
    assert "dört sayfa" in response.json()["detail"]


def test_single_still_accepts_four_separate_faces(client: TestClient) -> None:
    faces = {
        face: (f"{face}.png", _png_bytes(color), "image/png")
        for face, color in zip(
            ("front", "front_inside", "back_inside", "back"),
            ("red", "green", "blue", "yellow"),
            strict=True,
        )
    }

    response = client.post("/api/imports/single", files=faces)

    assert response.status_code == 201, response.text
    assert response.json()["job"]["location"] is None


def test_bulk_assigns_the_batch_shelf_to_every_book(client: TestClient) -> None:
    files = [
        ("files", (f"kitap-{index}.png", _png_bytes(color), "image/png"))
        for index, color in enumerate(("red", "green", "blue", "yellow"), start=1)
    ]

    response = client.post("/api/imports/bulk", files=files, data={"shelf": "Dolap 5"})

    assert response.status_code == 201, response.text
    body = response.json()
    assert body["books"] == 1
    assert body["shelf"] == "Dolap 5"
    assert body["books_without_shelf"] == 0
    detail = client.get(f"/api/imports/{body['job']['id']}").json()
    assert detail["shelves"] == [{"name": "Dolap 5", "count": 1}]


def test_bulk_can_take_the_shelf_from_each_folder(client: TestClient) -> None:
    files = []
    for shelf, color in (("Dolap 1", "red"), ("Dolap 2", "blue")):
        for index in range(1, 5):
            files.append(
                (
                    "files",
                    (f"{shelf}/kitap-{index}.png", _png_bytes(color), "image/png"),
                )
            )

    response = client.post(
        "/api/imports/bulk", files=files, data={"folder_shelf": "1"}
    )

    assert response.status_code == 201, response.text
    body = response.json()
    assert body["books"] == 2
    assert body["folder_shelves"] == ["Dolap 1", "Dolap 2"]
    assert sorted(body["shelves_created"]) == ["Dolap 1", "Dolap 2"]
    detail = client.get(f"/api/imports/{body['job']['id']}").json()
    assert sorted(row["name"] for row in detail["shelves"]) == ["Dolap 1", "Dolap 2"]


def test_bulk_splits_a_multi_book_pdf(client: TestClient) -> None:
    response = client.post(
        "/api/imports/bulk",
        files={
            "files": (
                "tarama.pdf",
                _pdf_bytes(
                    ["red", "green", "blue", "yellow", "purple", "orange", "cyan", "pink"]
                ),
                "application/pdf",
            )
        },
    )

    assert response.status_code == 201, response.text
    body = response.json()
    assert body["books"] == 2
    assert body["split_documents"] == [{"file": "tarama.pdf", "books": 2}]


def test_job_shelf_cancel_and_delete_endpoints(client: TestClient) -> None:
    created = client.post(
        "/api/imports/bulk",
        files=[
            ("files", (f"kitap-{index}.png", _png_bytes(color), "image/png"))
            for index, color in enumerate(("red", "green", "blue", "yellow"), start=1)
        ],
    ).json()
    job_id = created["job"]["id"]

    patched = client.patch(f"/api/imports/{job_id}", json={"shelf": "Dolap 9"})
    assert patched.status_code == 200, patched.text
    assert patched.json()["job"]["location"] == "Dolap 9"
    assert patched.json()["shelves_created"] == ["Dolap 9"]
    assert client.patch(f"/api/imports/{job_id}", json={}).status_code == 400

    assert client.patch(f"/api/imports/{job_id}", json={"shelf": {"ad": "A"}}).status_code == 400

    retried = client.post(f"/api/imports/{job_id}/retry-failed")
    assert retried.status_code == 200
    assert retried.json() | {"requeued": 0, "remaining": 0} == retried.json()

    assert client.post(f"/api/imports/{job_id}/cancel").json()["status"] == "cancelled"
    assert client.delete(f"/api/imports/{job_id}").status_code == 204
    assert client.get(f"/api/imports/{job_id}").status_code == 404


# --------------------------------------------------------------- kalite ön kontrolü


def test_single_upload_response_includes_quality_warnings(client: TestClient) -> None:
    # 120x160 sentetik yüzler kısa kenar eşiğinin (1000px) altında kalır;
    # ön kontrolün bunları rapora eklediğini doğrular.
    faces = {
        face: (f"{face}.png", _png_bytes(color), "image/png")
        for face, color in zip(
            ("front", "front_inside", "back_inside", "back"),
            ("red", "green", "blue", "yellow"),
            strict=True,
        )
    }

    response = client.post("/api/imports/single", files=faces)

    assert response.status_code == 201, response.text
    body = response.json()
    assert len(body["quality_warnings"]) == 4
    assert all("Ön kontrol" in w for row in body["quality_warnings"] for w in row["warnings"])


def test_preflight_reports_without_queueing_or_leaving_a_pending_job(
    client: TestClient,
) -> None:
    faces = {
        face: (f"{face}.png", _png_bytes(color), "image/png")
        for face, color in zip(
            ("front", "front_inside", "back_inside", "back"),
            ("red", "green", "blue", "yellow"),
            strict=True,
        )
    }

    response = client.post("/api/imports/single", files=faces, data={"preflight": "1"})

    assert response.status_code == 200, response.text
    body = response.json()
    assert body["preflight"] is True
    assert len(body["quality_warnings"]) == 4
    # Ön kontrol hiçbir iş kuyruğa almaz; kuyruk bomboş kalır.
    assert client.get("/api/imports").json() == []


def test_bulk_upload_response_includes_quality_warnings(client: TestClient) -> None:
    files = [
        ("files", (f"kitap-{index}.png", _png_bytes(color), "image/png"))
        for index, color in enumerate(("red", "green", "blue", "yellow"), start=1)
    ]

    response = client.post("/api/imports/bulk", files=files)

    assert response.status_code == 201, response.text
    assert len(response.json()["quality_warnings"]) == 4


# --------------------------------------------------------------------- ZIP arşivi


def _zip_bytes(entries: dict[str, bytes]) -> bytes:
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as archive:
        for name, data in entries.items():
            archive.writestr(name, data)
    return buffer.getvalue()


def test_bulk_can_expand_a_zip_with_two_folders_of_four_photos(client: TestClient) -> None:
    entries: dict[str, bytes] = {}
    for shelf, color in (("Dolap A", "red"), ("Dolap B", "blue")):
        for index in range(1, 5):
            entries[f"{shelf}/kitap-{index}.png"] = _png_bytes(color).getvalue()
    archive = io.BytesIO(_zip_bytes(entries))

    response = client.post(
        "/api/imports/bulk",
        files=[("files", ("arsiv.zip", archive, "application/zip"))],
        data={"folder_shelf": "1"},
    )

    assert response.status_code == 201, response.text
    body = response.json()
    assert body["books"] == 2
    assert sorted(body["folder_shelves"]) == ["Dolap A", "Dolap B"]
    assert sorted(body["shelves_created"]) == ["Dolap A", "Dolap B"]
    assert body["zip_expanded"] == [{"file": "arsiv.zip", "files": 8, "rejected": []}]

    detail = client.get(f"/api/imports/{body['job']['id']}").json()
    assert sorted(row["name"] for row in detail["shelves"]) == ["Dolap A", "Dolap B"]


def test_a_zip_member_that_escapes_its_folder_is_rejected_but_the_rest_still_imports(
    client: TestClient,
) -> None:
    entries: dict[str, bytes] = {
        f"Dolap A/kitap-{index}.png": _png_bytes("red").getvalue() for index in range(1, 5)
    }
    entries["../evil.png"] = _png_bytes("green").getvalue()
    archive = io.BytesIO(_zip_bytes(entries))

    response = client.post(
        "/api/imports/bulk",
        files=[("files", ("arsiv.zip", archive, "application/zip"))],
        data={"folder_shelf": "1"},
    )

    assert response.status_code == 201, response.text
    body = response.json()
    assert body["books"] == 1
    assert body["zip_expanded"] == [
        {
            "file": "arsiv.zip",
            "files": 4,
            "rejected": [{"file": "../evil.png", "reason": "Güvensiz ZIP yolu"}],
        }
    ]
