"""Web arayüzü API testleri.

Model paketi gerektirmeyen uçlar gerçek (geçici) veritabanıyla test edilir;
OCR işleme gibi model isteyen uçların yalnız hata sözleşmesi doğrulanır.
"""

from __future__ import annotations

import io
import sqlite3
from pathlib import Path

import pytest

fastapi = pytest.importorskip("fastapi")

from fastapi.testclient import TestClient  # noqa: E402

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
    context = open_application(paths, enforce_offline=False)
    app = create_app(context)
    with TestClient(app, base_url="http://127.0.0.1") as test_client:
        # Oturum çerezini ilk açılış akışıyla al.
        test_client.get(f"/?token={app.state.web.token}", follow_redirects=False)
        yield test_client


def _add_book(client: TestClient, **overrides) -> dict:
    payload = {
        "title": "Beyaz Gemi",
        "authors": "Cengiz Aytmatov",
        "isbn": "9789750718533",
        "publisher": "İletişim",
        "language": "Türkçe",
        "category": "Roman",
        "location": "Dolap A",
        "copy_count": 1,
    }
    payload.update(overrides)
    response = client.post("/api/books", json=payload)
    assert response.status_code == 201, response.text
    return response.json()


def _inject_pending_voice(
    client: TestClient, pending_id: str, *, title: str = "Kar", author: str = "Orhan Pamuk"
) -> None:
    """Whisper'a dokunmadan `/api/voice/save`'i test edebilmek için sahte bekleyen kayıt kur."""

    from kitapkatalog.voice_controller import PendingUtterance
    from kitapkatalog.voice_extractor import FieldClaim, VoiceParseResult

    state = client.app.state.web
    result = VoiceParseResult()
    result.claims.append(
        FieldClaim(field_path="title", value=title, raw_text=title, start_char=0, end_char=0, source="rule")
    )
    result.claims.append(
        FieldClaim(field_path="author", value=author, raw_text=author, start_char=0, end_char=0, source="rule")
    )
    wav_path = state.paths.voice_assets / "utterances" / f"{pending_id}.wav"
    wav_path.parent.mkdir(parents=True, exist_ok=True)
    wav_path.write_bytes(b"RIFF sahte kanonik ses")
    pending = PendingUtterance(
        wav_path=wav_path,
        wav_sha256="deadbeef",
        transcript=f"başlık {title} yazar {author}",
        result_json=result.to_json(),
    )
    with state.pending_lock:
        state.pending_utterances[pending_id] = pending


def _setup_span_evidence(
    client: TestClient, edition_id: int, *, source_path: Path | None = None
) -> dict:
    """Bir baskıya kaynak fotoğrafla bağlı consensus_span + field_observation kanıtı ekler."""

    from PIL import Image

    from kitapkatalog.domain import (
        CoverRole,
        FieldObservation,
        ImagePair,
        OcrEngine,
        PersistedConsensusSpan,
    )

    state = client.app.state.web
    photo = source_path
    if photo is None:
        photo = state.paths.assets / f"kanit-{edition_id}.jpg"
        photo.parent.mkdir(parents=True, exist_ok=True)
        Image.new("RGB", (400, 600), "white").save(photo, format="JPEG")
    job = state.database.create_import_job(
        "Kanıt İşi",
        [ImagePair(front=Path(photo), back=Path(str(photo) + ".back"), pair_key=f"kanit-{edition_id}")],
    )
    item = state.database.list_job_items(job.id)[0]
    asset_id = state.database.register_image_asset(
        item.id, "front", source_path=str(photo), edition_id=edition_id
    )
    polygon = ((10.0, 10.0), (110.0, 10.0), (110.0, 60.0), (10.0, 60.0))
    state.database.replace_consensus_spans(
        asset_id,
        [
            PersistedConsensusSpan(
                text="düşük güvenli okuma",
                normalized_text="düşük güvenli okuma",
                confidence=0.4,
                source_token_ids=(),
                polygon=polygon,
                source_polygon=polygon,
                engine_support=(OcrEngine.EASYOCR,),
            )
        ],
    )
    state.catalog.add_observation(
        FieldObservation(
            field_path="edition.publisher",
            raw_value="Alternatif Yayınevi",
            normalized_value="Alternatif Yayınevi",
            cover_role=CoverRole.FRONT,
            confidence=0.62,
            engine_evidence=(OcrEngine.EASYOCR, OcrEngine.TESSERACT),
            source_polygon=polygon,
        ),
        edition_id=edition_id,
        item_id=item.id,
    )
    return {"photo": Path(photo), "item_id": item.id, "asset_id": asset_id}


# ------------------------------------------------------------ güvenlik


class TestSecurity:
    def test_health_is_public_and_signed(self, client: TestClient) -> None:
        response = client.get("/health")
        assert response.status_code == 200
        body = response.json()
        assert body["app"] == "kitapkatalog"
        assert body["nonce"]

    def test_api_requires_session(self, paths: AppPaths) -> None:
        context = open_application(paths, enforce_offline=False)
        app = create_app(context)
        with TestClient(app, base_url="http://127.0.0.1") as anonymous:
            assert anonymous.get("/api/stats").status_code == 401

    def test_wrong_token_rejected(self, paths: AppPaths) -> None:
        context = open_application(paths, enforce_offline=False)
        app = create_app(context)
        with TestClient(app, base_url="http://127.0.0.1") as anonymous:
            response = anonymous.get("/?token=yanlis", follow_redirects=False)
            assert response.status_code == 403

    def test_foreign_origin_rejected(self, client: TestClient) -> None:
        response = client.get("/api/stats", headers={"Origin": "https://kotu.example"})
        assert response.status_code == 403

    def test_foreign_host_rejected(self, paths: AppPaths) -> None:
        context = open_application(paths, enforce_offline=False)
        app = create_app(context)
        with TestClient(app, base_url="http://disaridan.example") as outsider:
            assert outsider.get("/api/stats").status_code == 403


# ------------------------------------------------------------- kütüphane


class TestBooks:
    def test_create_search_detail(self, client: TestClient) -> None:
        book = _add_book(client)
        assert book["isbn"] == "9789750718533"
        assert book["authors"] == "Cengiz Aytmatov"
        assert book["review_status"] == "completed"

        page = client.get("/api/books", params={"q": "Beyaz"}).json()
        assert page["total"] == 1
        assert page["items"][0]["location"] == "Dolap A"

    def test_copy_count_on_create(self, client: TestClient) -> None:
        book = _add_book(client, copy_count=3)
        assert book["copy_count"] == 3

    def test_isbn_conflict_is_409(self, client: TestClient) -> None:
        _add_book(client)
        response = client.post("/api/books", json={"title": "Kopya", "isbn": "9789750718533"})
        assert response.status_code == 409

    def test_update_fields_and_authors(self, client: TestClient) -> None:
        book = _add_book(client)
        response = client.patch(
            f"/api/books/{book['edition_id']}",
            json={
                "changes": {"category": "Klasik", "page_count": "160"},
                "authors": "Cengiz Aytmatov; Çevirmen Kişi",
                "location": "Dolap B",
                "copy_count": 2,
            },
        )
        assert response.status_code == 200
        updated = response.json()
        assert updated["category"] == "Klasik"
        assert updated["page_count"] == 160
        assert updated["location"] == "Dolap B"
        assert updated["copy_count"] == 2

    def test_bulk_actions(self, client: TestClient) -> None:
        first = _add_book(client)
        second = _add_book(client, title="İnce Memed", isbn="", copy_count=1)
        ids = [first["edition_id"], second["edition_id"]]
        response = client.post(
            "/api/books/bulk", json={"ids": ids, "action": "location", "value": "Dolap Z"}
        )
        assert response.json()["done"] == 2
        for edition_id in ids:
            assert client.get(f"/api/books/{edition_id}").json()["location"] == "Dolap Z"

    def test_delete_book(self, client: TestClient) -> None:
        book = _add_book(client)
        assert client.delete(f"/api/books/{book['edition_id']}").status_code == 200
        assert client.get(f"/api/books/{book['edition_id']}").status_code == 404

    def test_unknown_book_404(self, client: TestClient) -> None:
        assert client.get("/api/books/9999").status_code == 404

    def test_distinct_values(self, client: TestClient) -> None:
        _add_book(client)
        values = client.get("/api/meta/distinct/publisher").json()
        assert "İletişim" in values

    def test_distinct_author_lists_catalog_contributors(self, client: TestClient) -> None:
        _add_book(client, authors="Orhan Pamuk; Ahmet Ümit", isbn="", title="Kar")
        _add_book(client, authors="Ahmet Ümit", isbn="", title="Bab-ı Esrar")
        values = client.get("/api/meta/distinct/author").json()
        assert set(values) == {"Orhan Pamuk", "Ahmet Ümit"}

    def test_stats(self, client: TestClient) -> None:
        _add_book(client)
        stats = client.get("/api/stats").json()
        assert stats["totals"]["editions"] == 1
        categories = {row["value"] for row in stats["distributions"]["category"]}
        assert "Roman" in categories


# ------------------------------------------------------------- kapaklar


class TestCovers:
    def test_upload_and_serve_cover(self, client: TestClient) -> None:
        from PIL import Image

        book = _add_book(client)
        buffer = io.BytesIO()
        Image.new("RGB", (60, 90), "navy").save(buffer, format="JPEG")
        buffer.seek(0)
        response = client.post(
            f"/api/books/{book['edition_id']}/cover/front",
            files={"file": ("kapak.jpg", buffer, "image/jpeg")},
        )
        assert response.status_code == 200, response.text
        image = client.get(f"/api/books/{book['edition_id']}/cover/front")
        assert image.status_code == 200
        thumb = client.get(f"/api/books/{book['edition_id']}/cover/front?thumb=1")
        assert thumb.status_code == 200
        assert thumb.headers["content-type"] == "image/jpeg"

    def test_missing_cover_404(self, client: TestClient) -> None:
        book = _add_book(client)
        assert client.get(f"/api/books/{book['edition_id']}/cover/back").status_code == 404

    def test_invalid_role_400(self, client: TestClient) -> None:
        book = _add_book(client)
        assert client.get(f"/api/books/{book['edition_id']}/cover/yan").status_code == 400


# ------------------------------------------------------------ içe aktarma


class TestImports:
    def test_single_requires_four_faces(self, client: TestClient) -> None:
        response = client.post(
            "/api/imports/single",
            files={"front": ("on.jpg", io.BytesIO(b"x"), "image/jpeg")},
        )
        assert response.status_code == 400
        assert "Dört yüz" in response.json()["detail"]

    def test_bulk_rejects_empty(self, client: TestClient) -> None:
        response = client.post("/api/imports/bulk", files={})
        assert response.status_code == 400

    def test_bulk_unsupported_type(self, client: TestClient) -> None:
        response = client.post(
            "/api/imports/bulk",
            files={"files": ("virus.exe", io.BytesIO(b"x"), "application/octet-stream")},
        )
        assert response.status_code == 400

    def test_job_list_empty(self, client: TestClient) -> None:
        assert client.get("/api/imports").json() == []

    def test_process_start_without_models_fails_gracefully(self, client: TestClient) -> None:
        response = client.post("/api/process/start", json={})
        assert response.status_code == 202
        # Model paketi yok: iş kaydı hata durumuna düşmeli, süreç çökmemeli.
        import time

        for _ in range(50):
            status = client.get("/api/process/status").json()
            if status["status"] != "running":
                break
            time.sleep(0.1)
        assert status["status"] == "failed"
        assert status["error"]

    def test_process_stop_without_run_404(self, client: TestClient) -> None:
        assert client.post("/api/process/stop").status_code == 404


# ------------------------------------------------------------- dışa aktarım


class TestExports:
    def _wait_export(self, client: TestClient, field: str) -> dict:
        import time

        for _ in range(100):
            job = client.get("/api/exports/status").json()[field]
            if job and job["status"] != "running":
                return job
            time.sleep(0.1)
        raise AssertionError("İş zamanında bitmedi")

    def test_csv_export_and_download(self, client: TestClient) -> None:
        _add_book(client)
        response = client.post("/api/exports", json={"format": "csv"})
        assert response.status_code == 202
        job = self._wait_export(client, "export")
        assert job["status"] == "succeeded", job
        assert job["result"]["records"] >= 1
        download = client.get(f"/api/exports/download/{job['result']['download']}")
        assert download.status_code == 200
        assert "Beyaz Gemi" in download.text

    def test_unknown_format_400(self, client: TestClient) -> None:
        assert client.post("/api/exports", json={"format": "docx"}).status_code == 400

    def test_download_traversal_blocked(self, client: TestClient) -> None:
        assert client.get("/api/exports/download/..%2Fcatalog.sqlite3").status_code in (400, 404)

    def test_archive_roundtrip(self, client: TestClient) -> None:
        _add_book(client)
        assert client.post("/api/archive", json={}).status_code == 202
        job = self._wait_export(client, "archive")
        assert job["status"] == "succeeded", job
        download = client.get(f"/api/exports/download/{job['result']['download']}")
        assert download.status_code == 200

    def test_archive_includes_cover_referenced_only_by_image_asset(
        self, client: TestClient
    ) -> None:
        book = _add_book(client, title="Image Asset Kapak", isbn="")
        state = client.app.state.web
        cover = state.paths.assets / "yalniz-image-asset.jpg"
        cover.write_bytes(b"image-asset-only")
        with sqlite3.connect(state.database.path) as connection:
            connection.execute("PRAGMA foreign_keys = OFF")
            connection.execute(
                """
                INSERT INTO image_asset(
                    item_id, edition_id, cover_role, source_path, managed_path,
                    created_at, updated_at
                ) VALUES (999999, ?, 'front', 'kaynak.jpg', ?, '2026-01-01', '2026-01-01')
                """,
                (book["edition_id"], str(cover)),
            )

        assert client.post("/api/archive", json={"include_covers": True}).status_code == 202
        job = self._wait_export(client, "archive")

        assert job["status"] == "succeeded", job
        assert job["result"]["cover_count"] == 1


# ------------------------------------------------------------- inceleme


class TestReview:
    def test_review_flow(self, client: TestClient) -> None:
        book = _add_book(client)
        # Kaydı incelemeye düşür, akışı uçtan uca doğrula.
        client.patch(
            f"/api/books/{book['edition_id']}",
            json={"changes": {"review_status": "review"}},
        )
        listing = client.get("/api/review/books").json()
        assert listing["count"] == 1
        assert listing["items"][0]["source"] == "Foto"

        response = client.post(
            f"/api/review/{book['edition_id']}/save",
            json={"changes": {"publisher": "Can"}, "approve": True},
        )
        assert response.status_code == 200
        saved = response.json()
        assert saved["publisher"] == "Can"
        assert saved["review_status"] == "completed"
        assert client.get("/api/review/books").json()["count"] == 0

    def test_review_list_is_paginated(self, client: TestClient) -> None:
        for index in range(60):
            book = _add_book(client, title=f"Kitap {index:02d}", isbn="", copy_count=1)
            client.patch(
                f"/api/books/{book['edition_id']}",
                json={"changes": {"review_status": "review"}},
            )
        first = client.get("/api/review/books?limit=50").json()
        assert first["total"] == 60
        assert len(first["items"]) == 50
        second = client.get("/api/review/books?limit=50&offset=50").json()
        assert second["total"] == 60
        assert len(second["items"]) == 10
        # limit sınırı: 200 üstü reddedilir.
        assert client.get("/api/review/books?limit=500").status_code == 422

    def test_badges_counts(self, client: TestClient) -> None:
        book = _add_book(client)
        client.patch(
            f"/api/books/{book['edition_id']}",
            json={"changes": {"review_status": "review"}},
        )
        badges = client.get("/api/badges").json()
        assert badges["review"] == 1
        assert badges["pairs"] == 0

    @pytest.mark.parametrize("bad_isbn", ["gecersiz-isbn", "9999999999999"])
    def test_patch_invalid_isbn_applies_nothing(self, client: TestClient, bad_isbn: str) -> None:
        book = _add_book(client)
        response = client.patch(
            f"/api/books/{book['edition_id']}",
            json={"changes": {"publisher": "Değişmemeli"}, "isbn": bad_isbn},
        )
        assert response.status_code in (400, 409)
        unchanged = client.get(f"/api/books/{book['edition_id']}").json()
        assert unchanged["publisher"] == "İletişim"
        assert unchanged["isbn"] == "9789750718533"  # mevcut ISBN silinmedi

    def test_calibration_status(self, client: TestClient) -> None:
        status = client.get("/api/calibration/status").json()
        assert status["label_count"] == 0
        assert status["minimum_samples"] == 200
        assert status["profile_exists"] is False

    def test_review_detail_has_empty_evidence_by_default(self, client: TestClient) -> None:
        book = _add_book(client, isbn="")
        detail = client.get(f"/api/review/{book['edition_id']}").json()
        assert detail["review_reasons"] == []
        assert detail["spans"] == []
        assert detail["field_alternatives"] == {}
        assert "isbn_evidence" not in detail

    def test_review_detail_surfaces_span_and_field_evidence(self, client: TestClient) -> None:
        book = _add_book(client, isbn="", publisher="Mevcut Yayınevi")
        _setup_span_evidence(client, book["edition_id"])

        detail = client.get(f"/api/review/{book['edition_id']}").json()

        assert len(detail["spans"]) == 1
        span = detail["spans"][0]
        assert span["confidence"] == pytest.approx(0.4)
        assert span["engine_evidence"] == ["easyocr"]
        assert span["has_polygon"] is True
        assert span["span_id"].startswith("cs:")
        assert any("düşük güven" in reason for reason in detail["review_reasons"])

        alternatives = detail["field_alternatives"]["publisher"]
        assert alternatives[0]["value"] == "Alternatif Yayınevi"
        assert alternatives[0]["engine_evidence"] == ["easyocr", "tesseract"]
        assert alternatives[0]["has_polygon"] is True
        assert alternatives[0]["span_id"].startswith("fo:")

    def test_review_detail_flags_isbn_conflict(self, client: TestClient) -> None:
        book = _add_book(client, isbn="")
        with client.app.state.web.database.transaction(immediate=True) as connection:
            connection.execute(
                """
                INSERT INTO identifier(
                    edition_id, scheme, value, normalized_value, source, confidence, created_at
                ) VALUES (?, 'ISBN13', '9789750718533', '9789750718533', 'ocr_corroborated', 0.80,
                          '2026-01-01T00:00:00Z')
                """,
                (book["edition_id"],),
            )
        detail = client.get(f"/api/review/{book['edition_id']}").json()
        assert any(entry["conflict"] for entry in detail["isbn_evidence"])
        assert any("ISBN" in reason for reason in detail["review_reasons"])

    def test_review_save_updates_isbn(self, client: TestClient) -> None:
        book = _add_book(client, isbn="")
        response = client.post(
            f"/api/review/{book['edition_id']}/save",
            json={"changes": {}, "isbn": "9786053601203", "approve": False},
        )
        assert response.status_code == 200
        assert response.json()["isbn"] == "9786053601203"

    def test_span_crop_returns_jpeg_and_rejects_missing_or_degenerate_polygon(
        self, client: TestClient
    ) -> None:
        book = _add_book(client, isbn="")
        _setup_span_evidence(client, book["edition_id"])
        detail = client.get(f"/api/review/{book['edition_id']}").json()
        span_id = detail["spans"][0]["span_id"]

        response = client.get(f"/api/review/{book['edition_id']}/span-crop/{span_id}")
        assert response.status_code == 200
        assert response.headers["content-type"] == "image/jpeg"
        assert response.content.startswith(b"\xff\xd8")

        assert client.get(f"/api/review/{book['edition_id']}/span-crop/cs:999999").status_code == 404
        assert client.get(f"/api/review/{book['edition_id']}/span-crop/bozuk-id").status_code == 404
        assert client.get(f"/api/review/{book['edition_id']}/span-crop/fo:999999").status_code == 404

    def test_span_crop_never_serves_outside_data_root(self, client: TestClient) -> None:
        book = _add_book(client, isbn="")
        _setup_span_evidence(client, book["edition_id"], source_path=Path("/etc/hosts"))
        detail = client.get(f"/api/review/{book['edition_id']}").json()
        span_id = detail["spans"][0]["span_id"]

        response = client.get(f"/api/review/{book['edition_id']}/span-crop/{span_id}")
        assert response.status_code == 404


# ------------------------------------------------------------- ses


class TestVoice:
    def test_save_without_pending_404(self, client: TestClient) -> None:
        response = client.post(
            "/api/voice/save",
            json={"pending_id": "yok", "values": {"title": "X"}, "copy_count": 1},
        )
        assert response.status_code == 404

    def test_voice_jobs_empty(self, client: TestClient) -> None:
        assert client.get("/api/voice/jobs").json() == []

    def test_batch_upload_rejects_unsupported_language(self, client: TestClient) -> None:
        response = client.post(
            "/api/voice/jobs",
            data={"language": "de"},
            files={"files": ("kayit.m4a", io.BytesIO(b"RIFF sahte ses"), "audio/mp4")},
        )
        assert response.status_code == 400

    def test_batch_upload_stores_language_on_the_job(self, client: TestClient) -> None:
        response = client.post(
            "/api/voice/jobs",
            data={"language": "en"},
            files={"files": ("kayit.m4a", io.BytesIO(b"RIFF sahte ses"), "audio/mp4")},
        )
        assert response.status_code == 201, response.text
        jobs = response.json()["jobs"]
        assert len(jobs) == 1
        assert jobs[0]["language"] == "en"

    def test_recent_empty(self, client: TestClient) -> None:
        assert client.get("/api/voice/recent").json() == []

    def test_analyze_rejects_bad_type(self, client: TestClient) -> None:
        response = client.post(
            "/api/voice/analyze",
            files={"file": ("not.txt", io.BytesIO(b"abc"), "text/plain")},
        )
        assert response.status_code == 400

    def test_result_to_form_carries_suggestions_to_the_response(self) -> None:
        # routes_voice._result_to_form eskiden result.suggestions'ı sabit alan
        # listesine hiç koymuyordu; öneriler arayüze hiç ulaşmıyordu (regresyon kilidi).
        from kitapkatalog.voice_extractor import VoiceParseResult
        from kitapkatalog.webapp.routes_voice import _result_to_form

        result = VoiceParseResult()
        result.suggestions.append(
            {"field_path": "title", "value": "The Great Gatsby", "origin": "second_pass",
             "language": "en", "score": 0.9}
        )
        form = _result_to_form(result)
        assert form["suggestions"] == result.suggestions

    def test_save_reports_learnable_corrections_without_auto_writing_them(
        self, client: TestClient
    ) -> None:
        pending_id = "abc123def456"
        _inject_pending_voice(client, pending_id, title="Kar", author="Orhan Pamuk")

        response = client.post(
            "/api/voice/save",
            json={
                "pending_id": pending_id,
                "values": {"title": "Kar (Roman)", "author": "Orhan Pamuk"},
                "copy_count": 1,
            },
        )
        assert response.status_code == 200, response.text
        body = response.json()
        assert body["learnable"] == [
            {"field": "title", "heard": "kar", "canonical": "Kar (Roman)"}
        ]
        # Sözlük yalnız kullanıcı onayıyla yazılır; save() otomatik yazmaz.
        assert client.get("/api/voice/aliases").json() == []

    def test_save_reports_no_learnable_when_value_unchanged(self, client: TestClient) -> None:
        pending_id = "aaa111bbb222"
        _inject_pending_voice(client, pending_id, title="Kar", author="Orhan Pamuk")

        response = client.post(
            "/api/voice/save",
            json={
                "pending_id": pending_id,
                "values": {"title": "Kar", "author": "Orhan Pamuk"},
                "copy_count": 1,
            },
        )
        assert response.status_code == 200, response.text
        assert response.json()["learnable"] == []

    def test_refield_transcribes_a_single_field_via_shared_job_slot(
        self, client: TestClient, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        import time

        from kitapkatalog.webapp import routes_voice

        def fake_transcode(source: Path, target: Path) -> None:
            Path(target).write_bytes(b"RIFF sahte kanonik ses")

        monkeypatch.setattr(routes_voice, "transcode_to_wav16k", fake_transcode)

        class _FakeRefieldSession:
            def transcribe_field(self, wav_path, field, *, language, prompt=None):
                assert field == "title"
                return "The Great Gatsby", "tam transkript"

            def close(self) -> None:
                pass

        state = client.app.state.web
        state._voice_session = _FakeRefieldSession()

        response = client.post(
            "/api/voice/refield",
            params={"field": "title"},
            files={"file": ("kayit.wav", io.BytesIO(b"RIFF valid-enough-container"), "audio/wav")},
        )
        assert response.status_code == 202, response.text

        job = None
        for _ in range(50):
            job = client.get("/api/voice/analyze/status").json()
            if job.get("status") != "running":
                break
            time.sleep(0.05)
        assert job is not None and job["status"] == "succeeded", job
        assert job["result"] == {
            "field": "title", "value": "The Great Gatsby", "transcript": "tam transkript"
        }

    def test_refield_rejects_unsupported_field(self, client: TestClient) -> None:
        response = client.post(
            "/api/voice/refield",
            params={"field": "isbn"},
            files={"file": ("kayit.wav", io.BytesIO(b"RIFF valid-enough-container"), "audio/wav")},
        )
        assert response.status_code == 400


class TestVoiceAliasesApi:
    def test_crud_flow_folds_heard_and_upserts_on_conflict(self, client: TestClient) -> None:
        created = client.post(
            "/api/voice/aliases",
            json={"heard": "Dı Greyt Gatsbi", "canonical": "The Great Gatsby", "field_scope": "title"},
        )
        assert created.status_code == 201, created.text
        body = created.json()
        assert body["heard"] == "di greyt gatsbi"  # fold_text uygulanmış
        assert body["canonical"] == "The Great Gatsby"
        assert body["field_scope"] == "title"

        assert len(client.get("/api/voice/aliases").json()) == 1

        # Aynı (heard, field_scope) çifti kanonik değeri günceller, çoğaltmaz.
        updated = client.post(
            "/api/voice/aliases",
            json={"heard": "dı greyt gatsbi", "canonical": "The Great Gatsby (1925)", "field_scope": "title"},
        )
        assert updated.status_code == 201
        assert updated.json()["id"] == body["id"]
        listed = client.get("/api/voice/aliases").json()
        assert len(listed) == 1
        assert listed[0]["canonical"] == "The Great Gatsby (1925)"

        deleted = client.delete(f"/api/voice/aliases/{body['id']}")
        assert deleted.status_code == 204
        assert client.get("/api/voice/aliases").json() == []
        assert client.delete(f"/api/voice/aliases/{body['id']}").status_code == 404

    def test_rejects_unknown_field_scope(self, client: TestClient) -> None:
        response = client.post(
            "/api/voice/aliases",
            json={"heard": "x", "canonical": "y", "field_scope": "bilinmeyen"},
        )
        assert response.status_code == 400

    def test_rejects_empty_heard_or_canonical(self, client: TestClient) -> None:
        assert client.post(
            "/api/voice/aliases", json={"heard": "", "canonical": "y"}
        ).status_code == 400
        assert client.post(
            "/api/voice/aliases", json={"heard": "x", "canonical": ""}
        ).status_code == 400


class TestSettingsApi:
    def test_put_resets_cached_voice_session_when_a_voice_setting_changes(
        self, client: TestClient
    ) -> None:
        state = client.app.state.web
        before = state.voice_session()

        response = client.put("/api/settings", json={"voice_language": "en"})

        assert response.status_code == 200, response.text
        assert state.voice_session() is not before

    def test_put_keeps_cached_voice_session_when_unrelated_setting_changes(
        self, client: TestClient
    ) -> None:
        state = client.app.state.web
        before = state.voice_session()

        response = client.put("/api/settings", json={"school_name": "Yeni Okul"})

        assert response.status_code == 200, response.text
        assert state.voice_session() is before

    def test_put_does_not_reset_session_when_voice_setting_value_is_unchanged(
        self, client: TestClient
    ) -> None:
        state = client.app.state.web
        client.put("/api/settings", json={"voice_language": "en"})
        before = state.voice_session()

        response = client.put("/api/settings", json={"voice_language": "en"})

        assert response.status_code == 200, response.text
        assert state.voice_session() is before


# ------------------------------------------------------------- eşleştirme


class TestPairs:
    def test_empty_pair_reviews(self, client: TestClient) -> None:
        assert client.get("/api/pair-reviews").json() == []

    def test_unknown_item_404(self, client: TestClient) -> None:
        assert client.get("/api/items/123/image/front").status_code == 404


# ------------------------------------------------------------- üyeler


def _eokul_bytes(rows: list[list[object]]) -> io.BytesIO:
    from openpyxl import Workbook

    workbook = Workbook()
    sheet = workbook.active
    sheet.append(["T.C. MEB Örnek Okulu"])
    sheet.append([])
    sheet.append(["Okul No", "Adı", "Soyadı", "Sınıfı"])
    for row in rows:
        sheet.append(row)
    buffer = io.BytesIO()
    workbook.save(buffer)
    buffer.seek(0)
    return buffer


class TestMembers:
    def test_member_crud_flow(self, client: TestClient) -> None:
        created = client.post(
            "/api/members",
            json={
                "member_type": "student",
                "school_number": "101",
                "first_name": "Işıl",
                "last_name": "Yılmaz",
                "class_name": "9-A",
            },
        )
        assert created.status_code == 201, created.text
        member = created.json()
        assert member["full_name"] == "Işıl Yılmaz"

        duplicate = client.post(
            "/api/members",
            json={
                "member_type": "student",
                "school_number": "101",
                "first_name": "Başka",
                "last_name": "Kişi",
            },
        )
        assert duplicate.status_code == 409

        patched = client.patch(
            f"/api/members/{member['id']}", json={"class_name": "10-A", "is_active": False}
        )
        assert patched.json()["class_name"] == "10-A"
        listing = client.get("/api/members?active=false").json()
        assert listing["total"] == 1

    def test_eokul_import_and_classes(self, client: TestClient) -> None:
        response = client.post(
            "/api/members/import",
            files={
                "file": (
                    "liste.xlsx",
                    _eokul_bytes([["101", "Ali", "Kaya", "9/A"], ["102", "Ayşe", "Ak", "9/B"]]),
                    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                )
            },
        )
        assert response.status_code == 200, response.text
        assert response.json()["imported"] == 2
        assert client.get("/api/meta/classes").json() == ["9-A", "9-B"]

    def test_promote_preview_then_apply(self, client: TestClient) -> None:
        client.post(
            "/api/members",
            json={
                "member_type": "student",
                "school_number": "101",
                "first_name": "Ali",
                "last_name": "Kaya",
                "class_name": "9-A",
            },
        )
        preview = client.post(
            "/api/members/promote/preview",
            files={"file": ("liste.xlsx", _eokul_bytes([["101", "Ali", "Kaya", "10/A"]]), "x")},
        ).json()
        assert len(preview["update"]) == 1
        # Önizleme veri değiştirmedi.
        assert client.get("/api/members?q=101").json()["items"][0]["class_name"] == "9-A"
        applied = client.post(
            "/api/members/promote/apply", json={"staged_id": preview["staged_id"]}
        )
        assert applied.status_code == 200
        assert client.get("/api/members?q=101").json()["items"][0]["class_name"] == "10-A"
        # Aynı kimlikle ikinci uygulama 404 (dosya tüketildi).
        again = client.post("/api/members/promote/apply", json={"staged_id": preview["staged_id"]})
        assert again.status_code == 404

    def test_loan_flow_over_api(self, client: TestClient) -> None:
        book = _add_book(client)
        member = client.post(
            "/api/members",
            json={
                "member_type": "student",
                "school_number": "301",
                "first_name": "Deniz",
                "last_name": "Kaya",
                "class_name": "10-C",
            },
        ).json()
        created = client.post(
            "/api/loans", json={"member_id": member["id"], "isbn": "9789750718533"}
        )
        assert created.status_code == 201, created.text
        loan = created.json()
        assert loan["member_name"] == "Deniz Kaya"
        # Tek nüsha ödünçteyken kitap silinemez (409), ikinci ödünç de 409.
        assert client.delete(f"/api/books/{book['edition_id']}").status_code == 409
        second = client.post(
            "/api/loans", json={"member_id": member["id"], "isbn": "9789750718533"}
        )
        assert second.status_code == 409
        listing = client.get("/api/loans?status=active").json()
        assert listing["total"] == 1
        returned = client.post("/api/loans/return-by-code", json={"code": "9789750718533"})
        assert returned.status_code == 200
        assert client.get("/api/loans/stats").json()["active"] == 0
        badges = client.get("/api/badges").json()
        assert badges["overdue"] == 0

    def test_loan_api_is_strict_and_idempotent(self, client: TestClient) -> None:
        book = _add_book(client)
        member = client.post(
            "/api/members",
            json={
                "member_type": "student",
                "school_number": "302",
                "first_name": "Ada",
                "last_name": "Yılmaz",
            },
        ).json()
        payload = {
            "member_id": member["id"],
            "isbn": "9789750718533",
            "request_id": "api-checkout-retry-001",
        }
        first = client.post("/api/loans", json=payload)
        replay = client.post("/api/loans", json=payload)
        assert first.status_code == replay.status_code == 201
        assert first.json()["id"] == replay.json()["id"]

        database = client.app.state.web.database
        assert database.fetchone("SELECT COUNT(*) FROM loan")[0] == 1
        assert database.fetchone("SELECT COUNT(*) FROM circulation_event")[0] == 1

        unknown = client.post(
            "/api/loans",
            json={**payload, "beklenmeyen_alan": True},
        )
        assert unknown.status_code == 422
        no_book_selector = client.post(
            "/api/loans",
            json={"member_id": member["id"], "request_id": "api-selector-none-001"},
        )
        conflicting_selectors = client.post(
            "/api/loans",
            json={
                "member_id": member["id"],
                "edition_id": book["edition_id"],
                "isbn": "9789750718533",
                "request_id": "api-selector-many-001",
            },
        )
        assert no_book_selector.status_code == 422
        assert conflicting_selectors.status_code == 422

    def test_late_return_api_reports_delay_after_closing_loan(self, client: TestClient) -> None:
        _add_book(client)
        member = client.post(
            "/api/members",
            json={
                "member_type": "student",
                "school_number": "303",
                "first_name": "Geç",
                "last_name": "İade",
            },
        ).json()
        created = client.post(
            "/api/loans",
            json={"member_id": member["id"], "isbn": "9789750718533"},
        ).json()
        database = client.app.state.web.database
        with database.transaction() as connection:
            connection.execute(
                "UPDATE loan SET due_at = '2000-01-01' WHERE id = ?",
                (created["id"],),
            )

        returned = client.post("/api/loans/return-by-code", json={"code": "9789750718533"})
        assert returned.status_code == 200
        assert returned.json()["returned_at"] is not None
        assert returned.json()["overdue"] is False
        assert returned.json()["days_overdue"] > 0

    def test_shelf_map_flow(self, client: TestClient) -> None:
        book = _add_book(client)  # location: Dolap A
        # Başta dolap kaydı yok → eşleşmemiş listesinde.
        summary = client.get("/api/shelves/map").json()
        assert summary["shelves"] == []
        assert summary["unmatched"][0]["name"] == "Dolap A"

        created = client.post(
            "/api/shelves",
            json={"name": "Dolap A", "grid_row": 0, "grid_col": 0, "capacity": 20},
        )
        assert created.status_code == 201, created.text
        shelf = created.json()
        summary = client.get("/api/shelves/map").json()
        assert summary["unmatched"] == []
        assert summary["shelves"][0]["copies"] == 1

        # Hücre çakışması 409; ad değişince nüsha konumu taşınır.
        conflict = client.post(
            "/api/shelves", json={"name": "Dolap B", "grid_row": 0, "grid_col": 0}
        )
        assert conflict.status_code == 409
        client.patch(f"/api/shelves/{shelf['id']}", json={"name": "Ana Dolap"})
        detail = client.get(f"/api/books/{book['edition_id']}").json()
        assert detail["copies"][0]["location"] == "Ana Dolap"

        # Varyant evlatlığı: adopt nüshaları dolabın adına toplar.
        _add_book(client, title="Varyant", isbn="", location="ana dolap")
        moved = client.post(f"/api/shelves/{shelf['id']}/adopt", json={"location": "ana dolap"})
        assert moved.json()["moved"] == 1

        deleted = client.delete(f"/api/shelves/{shelf['id']}")
        assert deleted.status_code == 204
        assert client.get("/api/shelves").json() == []

    def test_copy_location_patch(self, client: TestClient) -> None:
        book = _add_book(client, copy_count=2)
        # Ek nüshalar formdaki dolabı devralır (raf haritası düzeltmesi).
        locations = sorted(copy["location"] for copy in book["copies"])
        assert locations == ["Dolap A", "Dolap A"]
        copy_id = book["copies"][1]["id"]
        response = client.patch(f"/api/copies/{copy_id}", json={"location": "Dolap Z"})
        assert response.status_code == 200
        detail = client.get(f"/api/books/{book['edition_id']}").json()
        locations = sorted(copy["location"] for copy in detail["copies"])
        assert locations == ["Dolap A", "Dolap Z"]
        assert client.patch("/api/copies/9999", json={"location": "X"}).status_code == 404
        assert client.patch(f"/api/copies/{copy_id}", json={}).status_code == 400

    def test_member_update_with_full_ui_payload(self, client: TestClient) -> None:
        # Üye formu her kayıtta member_type dahil TÜM alanları gönderir;
        # servis bunu reddedince UI'dan hiçbir düzenleme kaydedilemiyordu.
        member = client.post(
            "/api/members",
            json={
                "member_type": "student",
                "school_number": "901",
                "first_name": "Düzen",
                "last_name": "Lenen",
                "class_name": "9-A",
            },
        ).json()
        patched = client.patch(
            f"/api/members/{member['id']}",
            json={
                "member_type": "student",
                "school_number": "901",
                "first_name": "Düzen",
                "last_name": "Lenen",
                "class_name": "9-B",
                "notes": "kulüp",
            },
        )
        assert patched.status_code == 200, patched.text
        assert patched.json()["class_name"] == "9-B"
        # Tip geçişi: öğrenci → personel serbest; öğrenciye dönüşte numara şart.
        to_staff = client.patch(f"/api/members/{member['id']}", json={"member_type": "staff"})
        assert to_staff.status_code == 200
        invalid = client.patch(
            f"/api/members/{member['id']}",
            json={"member_type": "student", "school_number": ""},
        )
        assert invalid.status_code == 400

    def test_member_delete_endpoint(self, client: TestClient) -> None:
        clean = client.post(
            "/api/members",
            json={"member_type": "staff", "first_name": "Temiz", "last_name": "Üye"},
        ).json()
        assert client.delete(f"/api/members/{clean['id']}").status_code == 204
        assert client.get(f"/api/members/{clean['id']}").status_code == 404
        # Ödünç geçmişli üye 409 alır.
        _add_book(client)
        reader = client.post(
            "/api/members",
            json={
                "member_type": "student",
                "school_number": "710",
                "first_name": "Okur",
                "last_name": "Üye",
            },
        ).json()
        client.post("/api/loans", json={"member_id": reader["id"], "isbn": "9789750718533"})
        blocked = client.delete(f"/api/members/{reader['id']}")
        assert blocked.status_code == 409
        assert client.delete("/api/members/9999").status_code == 404

    def test_books_list_includes_loan_counts(self, client: TestClient) -> None:
        book = _add_book(client, copy_count=2)
        member = client.post(
            "/api/members",
            json={
                "member_type": "student",
                "school_number": "711",
                "first_name": "Sayaç",
                "last_name": "Test",
            },
        ).json()
        client.post("/api/loans", json={"member_id": member["id"], "isbn": "9789750718533"})
        listing = client.get("/api/books?q=beyaz").json()["items"][0]
        assert listing["on_loan"] == 1
        assert listing["active_copies"] == 2
        detail = client.get(f"/api/books/{book['edition_id']}").json()
        assert detail["on_loan"] == 1

    def test_member_by_number_lookup(self, client: TestClient) -> None:
        member = client.post(
            "/api/members",
            json={
                "member_type": "student",
                "school_number": "0042",
                "first_name": "Ece",
                "last_name": "Demir",
                "class_name": "11-B",
            },
        ).json()
        found = client.get("/api/members/by-number/0042")
        assert found.status_code == 200
        assert found.json()["id"] == member["id"]
        assert client.get("/api/members/by-number/9999").status_code == 404

    def test_checkout_by_school_number(self, client: TestClient) -> None:
        _add_book(client)
        member = client.post(
            "/api/members",
            json={
                "member_type": "student",
                "school_number": "555",
                "first_name": "Umut",
                "last_name": "Şahin",
                "class_name": "9-C",
            },
        ).json()
        created = client.post("/api/loans", json={"school_number": "555", "isbn": "9789750718533"})
        assert created.status_code == 201, created.text
        assert created.json()["member_id"] == member["id"]
        # Bilinmeyen numara 404; member_id + school_number çelişkisi 400.
        unknown = client.post("/api/loans", json={"school_number": "777", "isbn": "9789750718533"})
        assert unknown.status_code == 404
        both = client.post(
            "/api/loans",
            json={
                "member_id": member["id"],
                "school_number": "555",
                "isbn": "9789750718533",
            },
        )
        assert both.status_code == 400
        neither = client.post("/api/loans", json={"isbn": "9789750718533"})
        assert neither.status_code == 400

    def test_checkout_by_school_number_respects_rules(self, client: TestClient) -> None:
        # Pasif üye school_number yoluyla da reddedilir.
        _add_book(client)
        member = client.post(
            "/api/members",
            json={
                "member_type": "student",
                "school_number": "808",
                "first_name": "Pasif",
                "last_name": "Üye",
            },
        ).json()
        client.patch(f"/api/members/{member['id']}", json={"is_active": False})
        blocked = client.post("/api/loans", json={"school_number": "808", "isbn": "9789750718533"})
        assert blocked.status_code == 409

    def test_stocktake_flow_over_api(self, client: TestClient) -> None:
        _add_book(client, copy_count=2)
        session = client.post("/api/stocktake/sessions", json={"name": "API Sayımı"}).json()
        scan = client.post(
            f"/api/stocktake/sessions/{session['id']}/scans", json={"code": "9789750718533"}
        ).json()
        assert scan["code_type"] == "isbn"
        assert scan["progress"]["scanned"] == 1
        report = client.get(f"/api/stocktake/sessions/{session['id']}/report").json()
        assert report["totals"]["missing"] == 1  # 2 nüsha, 1 okutma
        closed = client.post(f"/api/stocktake/sessions/{session['id']}/close")
        assert closed.status_code == 200
        blocked = client.post(
            f"/api/stocktake/sessions/{session['id']}/scans", json={"code": "9789750718533"}
        )
        assert blocked.status_code == 409

    def test_discard_flow_over_api(self, client: TestClient) -> None:
        book = _add_book(client)
        copy_id = client.get(f"/api/books/{book['edition_id']}").json()["copies"][0]["id"]
        created = client.post(
            "/api/discards", json={"copy_id": copy_id, "reason": "yipranma", "note": "Test"}
        )
        assert created.status_code == 201, created.text
        record = created.json()
        assert record["reason_label"] == "Yıpranma"
        # İkinci düşüm 409, geçersiz gerekçe 400.
        assert (
            client.post("/api/discards", json={"copy_id": copy_id, "reason": "kayip"}).status_code
            == 409
        )
        listing = client.get("/api/discards").json()
        assert listing["total"] == 1
        restored = client.post(f"/api/discards/{record['id']}/restore")
        assert restored.status_code == 200
        assert client.get("/api/discards").json()["total"] == 0

    def test_quick_entry_flow(self, client: TestClient) -> None:
        # Bilinmeyen ISBN: found=False.
        probe = client.get("/api/quick/isbn/9789750718533").json()
        assert probe == {"found": False, "valid": True, "isbn": "9789750718533"}
        # Yeni kayıt auto_inventory ile: demirbaş kodları atanır.
        book = client.post(
            "/api/books",
            json={
                "title": "Hızlı Kitap",
                "isbn": "9789750718533",
                "copy_count": 2,
                "auto_inventory": True,
            },
        ).json()
        codes = [copy["inventory_code"] for copy in book["copies"]]
        assert all(code and "-" in code for code in codes)
        assert len(set(codes)) == 2
        # Artık found=True + nüsha ekleme kod atar.
        probe = client.get("/api/quick/isbn/9789750718533").json()
        assert probe["found"] is True and probe["active_copies"] == 2
        added = client.post(
            f"/api/books/{book['edition_id']}/copies",
            json={"count": 1, "auto_inventory": True},
        ).json()
        assert len(added["inventory_codes"]) == 1
        assert added["copy_count"] == 3
        # Geçersiz kod: valid=False.
        assert client.get("/api/quick/isbn/12345").json()["valid"] is False

    def test_reports_over_api(self, client: TestClient) -> None:
        _add_book(client, copy_count=2)
        member = client.post(
            "/api/members",
            json={
                "member_type": "student",
                "school_number": "401",
                "first_name": "Okur",
                "last_name": "Öğrenci",
                "class_name": "11-A",
            },
        ).json()
        client.post("/api/loans", json={"member_id": member["id"], "isbn": "9789750718533"})
        readers = client.get("/api/reports/top-readers").json()
        assert readers[0]["member_name"] == "Okur Öğrenci"
        assert readers[0]["loan_count"] == 1
        classes = client.get("/api/reports/by-class").json()
        assert classes[0]["class_name"] == "11-A"
        books = client.get("/api/reports/popular-books").json()
        assert books[0]["title"] == "Beyaz Gemi"
        monthly = client.get("/api/reports/monthly").json()
        assert monthly[-1]["loans"] == 1
        # Dönem süzgeci: gelecekten başlayan aralık boş döner.
        empty = client.get("/api/reports/top-readers?start=2099-01-01").json()
        assert empty == []

    def test_opac_is_public_but_admin_stays_locked(self, paths: AppPaths) -> None:
        context = open_application(paths, enforce_offline=False)
        app = create_app(context)
        with TestClient(app, base_url="http://127.0.0.1") as anon:
            # Oturum çerezi YOK: OPAC açık, yönetim uçları kilitli.
            response = anon.get("/api/opac/search?q=gemi")
            assert response.status_code == 200
            assert anon.get("/opac").status_code == 200
            assert anon.get("/api/books").status_code == 401
            assert anon.get("/api/members").status_code == 401
            assert anon.get("/api/loans").status_code == 401

    def test_opac_response_leaks_no_member_data(self, client: TestClient) -> None:
        _add_book(client)
        member = client.post(
            "/api/members",
            json={
                "member_type": "student",
                "school_number": "501",
                "first_name": "Gizli",
                "last_name": "Öğrenci",
            },
        ).json()
        client.post("/api/loans", json={"member_id": member["id"], "isbn": "9789750718533"})
        data = client.get("/api/opac/search?q=Beyaz").json()
        assert data["total"] == 1
        item = data["items"][0]
        assert item["available"] == 0 and item["total_copies"] == 1
        assert "Gizli" not in str(data)
        # edition_id + has_cover yalnız katalog kimliğidir (kapak ucu için).
        assert set(item) <= {
            "edition_id",
            "has_cover",
            "title",
            "subtitle",
            "authors",
            "publisher",
            "publication_date",
            "category",
            "locations",
            "total_copies",
            "available",
            "holds_waiting",
        }
        # Yeni filtre/sıralama paramları da aynı daraltılmış sözlüğü döndürür.
        for query in (
            "q=Beyaz&category=Roman",
            "q=Beyaz&available=true",
            "sort=new",
            "sort=popular",
        ):
            filtered = client.get(f"/api/opac/search?{query}").json()
            for entry in filtered["items"]:
                assert set(entry) <= set(item), query
                assert "member" not in str(entry) and "loan" not in str(entry)
        # "Rafta olanlar" süzgeci ödünçteki tek nüshalı kitabı gizler.
        assert client.get("/api/opac/search?q=Beyaz&available=true").json()["total"] == 0

    def test_opac_cover_endpoint(self, client: TestClient, paths: AppPaths) -> None:
        book = _add_book(client)
        edition_id = book["edition_id"]
        # Kapak yokken 404.
        assert client.get(f"/api/opac/cover/{edition_id}").status_code == 404
        # Veri kökü İÇİNDE gerçek bir kapak → 200 (thumb üretimi PIL ister).
        from PIL import Image

        cover = paths.assets / "kapak.jpg"
        Image.new("RGB", (40, 60), "red").save(cover)
        with_cover = paths.database  # ham SQL ile front_path yaz
        import sqlite3 as _sqlite

        with _sqlite.connect(with_cover) as connection:
            connection.execute(
                "UPDATE edition SET front_path = ? WHERE id = ?", (str(cover), edition_id)
            )
        ok = client.get(f"/api/opac/cover/{edition_id}")
        assert ok.status_code == 200
        assert "image" in ok.headers["content-type"]
        # Varlık kökü DIŞINI gösteren yollar → 404 (mutlak sistem yolu da,
        # veri kökü altındaki assets-dışı dosya da).
        outside = paths.root / "root-alti.jpg"
        outside.write_bytes(b"veri")
        for bad in ("/etc/hosts", str(outside)):
            with _sqlite.connect(with_cover) as connection:
                connection.execute(
                    "UPDATE edition SET front_path = ? WHERE id = ?", (bad, edition_id)
                )
            assert client.get(f"/api/opac/cover/{edition_id}").status_code == 404, bad

    def test_opac_categories_only_names(self, paths: AppPaths) -> None:
        context = open_application(paths, enforce_offline=False)
        app = create_app(context)
        with TestClient(app, base_url="http://127.0.0.1") as anon:
            with TestClient(app, base_url="http://127.0.0.1") as admin:
                admin.get(f"/?token={app.state.web.token}")
                _add_book(admin)
            # Oturumsuz istemci yalnız kategori adlarını görür.
            assert anon.get("/api/opac/categories").json() == ["Roman"]

    def test_member_summary(self, client: TestClient) -> None:
        _add_book(client)
        member = client.post(
            "/api/members",
            json={
                "member_type": "student",
                "school_number": "606",
                "first_name": "Özet",
                "last_name": "Öğrenci",
                "class_name": "10-A",
            },
        ).json()
        other = client.post(
            "/api/members",
            json={
                "member_type": "student",
                "school_number": "607",
                "first_name": "Başka",
                "last_name": "Kişi",
            },
        ).json()
        client.post("/api/loans", json={"member_id": member["id"], "isbn": "9789750718533"})
        summary = client.get(f"/api/members/{member['id']}/summary").json()
        assert summary["member"]["id"] == member["id"]
        assert summary["totals"] == {"total": 1, "returned": 0, "late": 0}
        assert len(summary["active"]) == 1
        assert summary["overdue_count"] == 0
        assert summary["penalty_end"] is None
        # Başka üyenin özeti karışmaz.
        empty = client.get(f"/api/members/{other['id']}/summary").json()
        assert empty["totals"]["total"] == 0 and empty["active"] == []
        assert client.get("/api/members/9999/summary").status_code == 404

    def test_print_pages_require_session(self, paths: AppPaths) -> None:
        context = open_application(paths, enforce_offline=False)
        app = create_app(context)
        with TestClient(app, base_url="http://127.0.0.1") as anon:
            for path in ("/print/labels", "/print/member-cards", "/print/overdue"):
                assert anon.get(path).status_code == 401, path

    def test_print_labels_and_cards(self, client: TestClient) -> None:
        book = _add_book(client)
        client.post(
            "/api/members",
            json={
                "member_type": "student",
                "school_number": "1086",
                "first_name": "Kartlı",
                "last_name": "Öğrenci",
                "class_name": "9-A",
            },
        )
        # Kod ver → etiketle akışı.
        assigned = client.post("/api/copies/assign-codes", json={"scope": "all"})
        assert assigned.json()["assigned"] == 1
        labels = client.get(f"/print/labels?scope=edition&edition_id={book['edition_id']}")
        assert labels.status_code == 200
        assert "text/html" in labels.headers["content-type"]
        assert labels.headers["cache-control"] == "no-store"
        assert "<svg" in labels.text and "Beyaz Gemi" in labels.text

        cards = client.get("/print/member-cards?class_name=9-A")
        assert cards.status_code == 200
        assert "Kartlı Öğrenci" in cards.text and "<svg" in cards.text

        overdue = client.get("/print/overdue")
        assert overdue.status_code == 200
        assert "Gecikmiş kitap yok" in overdue.text

    def test_print_labels_escape_html(self, client: TestClient) -> None:
        book = _add_book(client, title="<script>alert(1)</script>", isbn="")
        client.post("/api/copies/assign-codes", json={"scope": "all"})
        labels = client.get(f"/print/labels?scope=edition&edition_id={book['edition_id']}")
        assert "<script>alert" not in labels.text
        assert "&lt;script&gt;" in labels.text

    def test_print_skips_unencodable_codes(self, client: TestClient) -> None:
        # ASCII dışı tek kod bütün etiket sayfasını 500'e düşürmemeli.
        book = _add_book(client)
        client.post("/api/copies/assign-codes", json={"scope": "all"})
        client.post(
            "/api/members",
            json={
                "member_type": "staff",
                "school_number": "Ö-12",  # barkoda çevrilemez
                "first_name": "Türkçe",
                "last_name": "Numara",
            },
        )
        cards = client.get("/print/member-cards")
        assert cards.status_code == 200
        assert "atlandı" in cards.text
        labels = client.get(f"/print/labels?scope=edition&edition_id={book['edition_id']}")
        assert labels.status_code == 200

    def test_assign_codes_by_location(self, client: TestClient) -> None:
        _add_book(client, location="Dolap K", isbn="")
        _add_book(client, title="Başka", location="Dolap L", isbn="")
        result = client.post(
            "/api/copies/assign-codes", json={"scope": "location", "location": "Dolap K"}
        )
        assert result.json()["assigned"] == 1
        # İkinci çağrı boş döner (idempotent).
        again = client.post(
            "/api/copies/assign-codes", json={"scope": "location", "location": "Dolap K"}
        )
        assert again.json()["assigned"] == 0

    def test_restore_flow_over_api(self, client: TestClient, tmp_path) -> None:
        import time

        from kitapkatalog.archive import create_archive
        from kitapkatalog.catalog import Catalog
        from kitapkatalog.database import Database
        from kitapkatalog.domain import BookInput

        source = tmp_path / "kaynak-web"
        source.mkdir()
        db = Database(source / "catalog.sqlite3")
        Catalog(db).save_book(BookInput(title="Web Yedek Kitabı"))
        db.close()
        info = create_archive(source / "catalog.sqlite3", tmp_path / "web.kitaparsiv")

        bad = client.post(
            "/api/restore/upload",
            files={"file": ("kotu.zip", b"veri", "application/zip")},
        )
        assert bad.status_code == 400

        upload = client.post(
            "/api/restore/upload",
            files={"file": ("web.kitaparsiv", info.path.read_bytes(), "application/zip")},
        )
        assert upload.status_code == 202, upload.text
        for _ in range(50):
            job = client.get("/api/restore/status").json()["job"]
            if job and job["status"] in ("succeeded", "failed"):
                break
            time.sleep(0.1)
        assert job["status"] == "succeeded", job
        assert job["result"]["counts"]["edition"] == 1

        confirmed = client.post(
            "/api/restore/confirm", json={"staging_id": job["result"]["staging_id"]}
        )
        assert confirmed.status_code == 200, confirmed.text
        status = client.get("/api/restore/status").json()
        assert status["pending"] is not None
        cancelled = client.delete("/api/restore/pending").json()
        assert cancelled["cancelled"] is True
        assert client.get("/api/restore/status").json()["pending"] is None

    def test_stats_includes_dashboard_blocks(self, client: TestClient) -> None:
        _add_book(client, copy_count=3)
        stats = client.get("/api/stats").json()
        assert stats["loans"] == {
            "active": 0,
            "overdue": 0,
            "this_month": 0,
            "today_out": 0,
            "today_in": 0,
        }
        assert stats["discards"] == 0
        assert stats["last_stocktake"] is None
        assert stats["growth"][-1]["total"] == 3

    def test_settings_roundtrip(self, client: TestClient) -> None:
        defaults = client.get("/api/settings").json()
        assert defaults["loan_period_days"] == 15
        updated = client.put(
            "/api/settings", json={"school_name": "Örnek Lisesi", "loan_period_days": 21}
        ).json()
        assert updated["school_name"] == "Örnek Lisesi"
        assert updated["loan_period_days"] == 21


# ------------------------------------------------------------- Faz 3: gösterge paneli


class TestDashboard:
    def test_empty_database_returns_zeroed_shape(self, client: TestClient) -> None:
        data = client.get("/api/dashboard").json()
        assert data["totals"] == {"works": 0, "editions": 0, "copies": 0}
        assert data["active_loans"] == 0
        assert data["overdue"] == 0
        assert data["today_events"] == 0
        assert data["unread_notifications"] == 0
        assert data["pending_holds"] == 0
        assert data["readers_this_month"] == 0
        assert data["collection_status"] == {"on_shelf": 0, "on_loan": 0}
        assert data["category_distribution"] == []
        assert data["monthly_loans"] == []
        assert data["active_challenge"] is None

    def test_reflects_books_and_active_loan(self, client: TestClient) -> None:
        _add_book(client, copy_count=2)
        member = client.post(
            "/api/members",
            json={
                "member_type": "student",
                "school_number": "401",
                "first_name": "Ada",
                "last_name": "Yıldız",
                "class_name": "11-A",
            },
        ).json()
        checkout = client.post(
            "/api/loans", json={"member_id": member["id"], "isbn": "9789750718533"}
        )
        assert checkout.status_code == 201, checkout.text

        data = client.get("/api/dashboard").json()
        assert data["totals"] == {"works": 1, "editions": 1, "copies": 2}
        assert data["active_loans"] == 1
        assert data["collection_status"] == {"on_shelf": 1, "on_loan": 1}
        assert data["readers_this_month"] == 1
        assert {"value": "Roman", "count": 1} in data["category_distribution"]
        assert sum(row["total"] for row in data["monthly_loans"]) == 1


# ------------------------------------------------------------- Faz 3: dış öneriler


class TestExternalSuggestions:
    def _insert_suggestion(
        self,
        client: TestClient,
        *,
        isbn13: str = "9789750718533",
        source: str = "openlibrary",
        status: str = "pending",
        edition_id: int | None = None,
    ) -> int:
        state = client.app.state.web
        with state.database.transaction(immediate=True) as connection:
            cursor = connection.execute(
                """
                INSERT INTO external_suggestion
                    (isbn13, source, payload_json, fetched_at, edition_id, status)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                (isbn13, source, '{"title": "Deneme"}', "2026-08-01T00:00:00Z", edition_id, status),
            )
        return int(cursor.lastrowid)

    def test_list_and_dismiss_roundtrip(self, client: TestClient) -> None:
        book = _add_book(client)
        suggestion_id = self._insert_suggestion(
            client, edition_id=book["edition_id"]
        )
        pending = client.get("/api/external-suggestions", params={"status": "pending"}).json()
        assert len(pending) == 1
        assert pending[0]["id"] == suggestion_id
        assert pending[0]["payload"] == {"title": "Deneme"}
        assert pending[0]["matched_title"] and "Beyaz Gemi" in pending[0]["matched_title"]

        dismissed = client.post(f"/api/external-suggestions/{suggestion_id}/dismiss")
        assert dismissed.status_code == 200
        assert dismissed.json() == {"id": suggestion_id, "status": "dismissed"}

        assert client.get(
            "/api/external-suggestions", params={"status": "pending"}
        ).json() == []
        assert client.post("/api/external-suggestions/9999/dismiss").status_code == 404


# ------------------------------------------------------------- Faz 3: nüsha edinme alanları


class TestCopyAcquisition:
    def test_roundtrip_via_create_and_add_copy(self, client: TestClient) -> None:
        book = _add_book(
            client,
            copy={
                "acquisition_method": "satin_alma",
                "acquisition_date": "2026-08-01",
                "acquisition_price": "125.50",
            },
        )
        first_copy = book["copies"][0]
        assert first_copy["acquisition_method"] == "satin_alma"
        assert first_copy["acquisition_date"] == "2026-08-01"
        assert first_copy["acquisition_price"] == "125.50"

        added = client.post(
            f"/api/books/{book['edition_id']}/copies",
            json={
                "acquisition_method": "bagis",
                "acquisition_date": "2026-08-05",
                "acquisition_price": "0",
            },
        )
        assert added.status_code == 201, added.text
        detail = client.get(f"/api/books/{book['edition_id']}").json()
        new_copy = next(c for c in detail["copies"] if c["id"] == added.json()["copy_id"])
        assert new_copy["acquisition_method"] == "bagis"
        assert new_copy["acquisition_date"] == "2026-08-05"
        assert new_copy["acquisition_price"] == "0"

    def test_patch_updates_acquisition_fields(self, client: TestClient) -> None:
        book = _add_book(client)
        copy_id = book["copies"][0]["id"]
        response = client.patch(
            f"/api/copies/{copy_id}",
            json={
                "acquisition_method": "devir",
                "acquisition_date": "2026-01-15",
                "acquisition_price": "0",
            },
        )
        assert response.status_code == 200, response.text
        detail = client.get(f"/api/books/{book['edition_id']}").json()
        copy = next(c for c in detail["copies"] if c["id"] == copy_id)
        assert copy["acquisition_method"] == "devir"
        assert copy["acquisition_date"] == "2026-01-15"
        assert copy["acquisition_price"] == "0"
        assert copy["location"] == "Dolap A"  # PATCH yalnız verilen alanları değiştirir

        assert client.patch(f"/api/copies/{copy_id}", json={}).status_code == 400
        assert client.patch("/api/copies/9999", json={"location": "X"}).status_code == 404
