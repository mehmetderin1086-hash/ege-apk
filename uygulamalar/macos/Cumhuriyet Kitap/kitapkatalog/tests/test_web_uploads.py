"""Regression gates for bounded uploads and side-effect-free validation."""

from __future__ import annotations

import io
import time
from pathlib import Path

import pytest

fastapi = pytest.importorskip("fastapi")

from fastapi.testclient import TestClient  # noqa: E402
from openpyxl import Workbook  # noqa: E402
from PIL import Image  # noqa: E402

from kitapkatalog.application import open_application  # noqa: E402
from kitapkatalog.config import AppPaths  # noqa: E402
from kitapkatalog.webapp.app import create_app  # noqa: E402


@pytest.fixture()
def paths(tmp_path: Path) -> AppPaths:
    return AppPaths(
        root=tmp_path,
        database=tmp_path / "catalog.sqlite3",
        assets=tmp_path / "assets",
        derivatives=tmp_path / "derivatives",
        ocr_raw=tmp_path / "ocr-raw",
        models=tmp_path / "models",
        exports=tmp_path / "exports",
        logs=tmp_path / "logs",
    )


@pytest.fixture()
def client(paths: AppPaths):
    app = create_app(open_application(paths, enforce_offline=False))
    with TestClient(app, base_url="http://127.0.0.1") as test_client:
        test_client.get(f"/?token={app.state.web.token}", follow_redirects=False)
        yield test_client


def _book(client: TestClient) -> dict:
    response = client.post(
        "/api/books",
        json={"title": "Güvenli Kayıt", "publisher": "Deneme", "copy_count": 1},
    )
    assert response.status_code == 201, response.text
    return response.json()


def _xlsx() -> io.BytesIO:
    workbook = Workbook()
    sheet = workbook.active
    sheet.append(["T.C. MEB Örnek Okulu"])
    sheet.append([])
    sheet.append(["Okul No", "Adı", "Soyadı", "Sınıfı"])
    sheet.append(["101", "Ayşe", "Yılmaz", "9/A"])
    buffer = io.BytesIO()
    workbook.save(buffer)
    buffer.seek(0)
    return buffer


def test_invalid_create_and_patch_leave_no_partial_changes(client: TestClient) -> None:
    failed_create = client.post(
        "/api/books", json={"title": "Yazılmamalı", "copy_count": "bozuk"}
    )
    assert failed_create.status_code == 400
    assert client.get("/api/books", params={"q": "Yazılmamalı"}).json()["total"] == 0

    book = _book(client)
    failed_patch = client.patch(
        f"/api/books/{book['edition_id']}",
        json={"changes": {"title": "Değişmemeli"}, "copy_count": "bozuk"},
    )
    assert failed_patch.status_code == 400
    unchanged = client.get(f"/api/books/{book['edition_id']}").json()
    assert unchanged["title"] == "Güvenli Kayıt"


def test_late_service_failure_rolls_back_whole_book_mutation(
    client: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    from kitapkatalog.catalog import Catalog

    original_update = Catalog.update_book
    with monkeypatch.context() as scoped:
        scoped.setattr(
            Catalog,
            "update_book",
            lambda *_args, **_kwargs: (_ for _ in ()).throw(RuntimeError("geç hata")),
        )
        with pytest.raises(RuntimeError, match="geç hata"):
            client.post("/api/books", json={"title": "Atomik Oluşturma"})
    assert client.get("/api/books", params={"q": "Atomik Oluşturma"}).json()["total"] == 0

    book = _book(client)
    with monkeypatch.context() as scoped:
        scoped.setattr(
            Catalog,
            "set_copy_count",
            lambda *_args, **_kwargs: (_ for _ in ()).throw(RuntimeError("son adım")),
        )
        with pytest.raises(RuntimeError, match="son adım"):
            client.patch(
                f"/api/books/{book['edition_id']}",
                json={"changes": {"publisher": "Yazılmamalı"}, "copy_count": 2},
            )
    unchanged = client.get(f"/api/books/{book['edition_id']}").json()
    assert unchanged["publisher"] == "Deneme"
    assert unchanged["copy_count"] == 1
    # Referansı kullanmak lint'in yanlışlıkla 'unused' sanmasını da önler ve
    # monkeypatch bağlamının gerçek metodu geri getirdiğini doğrular.
    assert Catalog.update_book is original_update


def test_copy_count_has_a_hard_server_limit(client: TestClient) -> None:
    response = client.post(
        "/api/books", json={"title": "Çok Fazla", "copy_count": 1_001}
    )
    assert response.status_code == 400
    assert client.get("/api/books", params={"q": "Çok Fazla"}).json()["total"] == 0


def test_cover_rejects_spoofed_image_and_never_serves_outside_assets(
    client: TestClient,
) -> None:
    book = _book(client)
    spoofed = client.post(
        f"/api/books/{book['edition_id']}/cover/front",
        files={"file": ("kapak.jpg", io.BytesIO(b"not-an-image"), "image/jpeg")},
    )
    assert spoofed.status_code == 400

    database = client.app.state.web.database
    with database.transaction(immediate=True) as connection:
        connection.execute(
            "UPDATE edition SET front_path = ? WHERE id = ?",
            ("/etc/hosts", book["edition_id"]),
        )
    assert client.get(f"/api/books/{book['edition_id']}/cover/front").status_code == 404
    assert client.get(f"/api/opac/cover/{book['edition_id']}").status_code == 404


def test_authenticated_admin_gets_only_sanitized_derivative_for_reference_cover(
    client: TestClient, tmp_path: Path
) -> None:
    book = _book(client)
    reference = tmp_path.parent / f"reference-{tmp_path.name}.png"
    Image.new("RGB", (120, 180), "navy").save(reference, format="PNG")
    try:
        client.app.state.web.catalog.set_cover_paths(
            book["edition_id"], front_path=reference
        )

        admin = client.get(f"/api/books/{book['edition_id']}/cover/front")
        public = client.get(f"/api/opac/cover/{book['edition_id']}")

        assert admin.status_code == 200
        assert admin.headers["content-type"].startswith("image/jpeg")
        assert admin.content.startswith(b"\xff\xd8")
        assert public.status_code == 404
        assert str(reference).encode() not in admin.content
    finally:
        reference.unlink(missing_ok=True)


def test_import_review_never_serves_job_paths_outside_data_root(client: TestClient) -> None:
    from kitapkatalog.domain import ImagePair

    job = client.app.state.web.database.create_import_job(
        "Kötü Yol",
        [ImagePair(front=Path("/etc/hosts"), back=Path("/etc/passwd"), pair_key="x")],
    )
    item = client.app.state.web.database.list_job_items(job.id)[0]

    assert client.get(f"/api/items/{item.id}/image/front").status_code == 404
    assert client.get(f"/api/items/{item.id}/image/front?thumb=1").status_code == 404


def test_oversize_cover_cleans_partial_file(
    client: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    from kitapkatalog.webapp import routes_books

    monkeypatch.setattr(routes_books, "_MAX_COVER_BYTES", 32)
    book = _book(client)
    image = io.BytesIO()
    Image.new("RGB", (80, 120), "navy").save(image, format="JPEG")
    image.seek(0)
    response = client.post(
        f"/api/books/{book['edition_id']}/cover/front",
        files={"file": ("buyuk.jpg", image, "image/jpeg")},
    )
    assert response.status_code == 413
    cover_root = client.app.state.web.paths.assets / "web_covers"
    assert not list(cover_root.glob("*.part"))
    assert not list(cover_root.glob(".*.part"))
    assert not list(cover_root.glob("*.jpg"))


def test_xlsx_signature_is_checked_and_preview_can_be_cancelled(client: TestClient) -> None:
    invalid = client.post(
        "/api/members/import",
        files={"file": ("liste.xlsx", io.BytesIO(b"fake zip"), "application/octet-stream")},
    )
    assert invalid.status_code == 400

    preview = client.post(
        "/api/members/promote/preview",
        files={
            "file": (
                "liste.xlsx",
                _xlsx(),
                "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            )
        },
    )
    assert preview.status_code == 200, preview.text
    staged_id = preview.json()["staged_id"]
    staged = client.app.state.web.upload_root / "members" / f"{staged_id}.xlsx"
    assert staged.is_file()
    cancelled = client.delete(f"/api/members/promote/staged/{staged_id}")
    assert cancelled.status_code == 204
    assert not staged.exists()


def test_document_and_audio_content_signatures_are_checked(client: TestClient) -> None:
    document = client.post(
        "/api/imports/bulk",
        files={"files": ("kitap-1.jpg", io.BytesIO(b"fake image"), "image/jpeg")},
    )
    assert document.status_code == 400
    # Ret gerekçesi de doğrulanır: dosyanın hiç görülmediği bir regresyon da
    # 400 döndürürdü ve bu test onu sessizce geçirirdi.
    assert "geçerli bir görsel değil" in document.json()["detail"]
    upload_root = client.app.state.web.upload_root
    assert not [path for path in upload_root.iterdir() if path.is_dir() and path.name != "members"]

    audio = client.post(
        "/api/voice/analyze",
        files={"file": ("kayit.webm", io.BytesIO(b"fake audio"), "audio/webm")},
    )
    assert audio.status_code == 400
    assert not list((upload_root / "voice").glob("*.part"))


def test_oversize_restore_archive_is_never_published(
    client: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    from kitapkatalog import restore

    monkeypatch.setattr(restore, "MAX_UPLOAD_BYTES", 32)
    response = client.post(
        "/api/restore/upload",
        files={
            "file": (
                "buyuk.kitaparsiv",
                io.BytesIO(b"x" * 64),
                "application/octet-stream",
            )
        },
    )

    assert response.status_code == 413
    restore_root = client.app.state.web.paths.root / restore.RESTORE_DIRNAME
    assert not list(restore_root.glob("yukleme-*.kitaparsiv"))
    assert not list(restore_root.glob("*.part"))
    assert not list(restore_root.glob(".*.part"))


def test_cancelled_pending_voice_removes_unapproved_audio(client: TestClient) -> None:
    from kitapkatalog.voice_controller import PendingUtterance

    audio = client.app.state.web.paths.voice_assets / "utterances" / "pending.wav"
    audio.parent.mkdir(parents=True, exist_ok=True)
    audio.write_bytes(b"RIFF pending")
    pending_id = "abcdef123456"
    client.app.state.web.pending_utterances[pending_id] = PendingUtterance(
        wav_path=audio,
        wav_sha256="0" * 64,
        transcript="deneme",
        result_json='{"claims": [], "review_reasons": [], "copy_count": 1}',
    )

    response = client.delete(f"/api/voice/pending/{pending_id}")

    assert response.status_code == 204
    assert not audio.exists()


def test_transcode_failure_removes_partial_canonical_audio(
    client: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    from kitapkatalog.webapp import routes_voice

    def broken_transcode(_source: Path, target: Path) -> None:
        target.write_bytes(b"RIFF partial personal audio")
        raise RuntimeError("transcode failed after partial write")

    monkeypatch.setattr(routes_voice, "transcode_to_wav16k", broken_transcode)
    response = client.post(
        "/api/voice/analyze",
        files={
            "file": (
                "kayit.wav",
                io.BytesIO(b"RIFF valid-enough-container"),
                "audio/wav",
            )
        },
    )
    assert response.status_code == 202

    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        status = client.get("/api/voice/analyze/status").json()
        if status.get("status") == "failed":
            break
        time.sleep(0.02)
    assert status.get("status") == "failed", status
    voice_staging = client.app.state.web.upload_root / "voice"
    assert list(voice_staging.iterdir()) == []
