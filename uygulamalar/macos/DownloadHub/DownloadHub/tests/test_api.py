from __future__ import annotations

import json
import time
from pathlib import Path

from fastapi.testclient import TestClient

from downloadhub.app import create_app

from .conftest import PAYLOAD


def test_health_inspect_download_and_settings(app_settings, file_server: str) -> None:
    app = create_app(app_settings)
    with TestClient(app, base_url="http://127.0.0.1:8765") as client:
        health = client.get("/health")
        assert health.status_code == 200
        assert health.json()["status"] in {"ready", "degraded"}

        inspected = client.post("/api/v1/inspect", json={"url": file_server})
        assert inspected.status_code == 200, inspected.text
        inspection = inspected.json()
        assert inspection["engine"] == "direct"
        assert inspection["title"] == "payload.bin"
        assert inspection["filesize"] == len(PAYLOAD)

        created = client.post(
            "/api/v1/jobs",
            headers={"Idempotency-Key": "integration-direct-download"},
            json={
                "url": file_server,
                "engine": "direct",
                "inspection_id": inspection["inspection_id"],
            },
        )
        assert created.status_code == 200, created.text
        job_id = created.json()["id"]

        duplicate = client.post(
            "/api/v1/jobs",
            headers={"Idempotency-Key": "integration-direct-download"},
            json={"url": file_server, "engine": "direct"},
        )
        assert duplicate.status_code == 200
        assert duplicate.json()["id"] == job_id

        deadline = time.monotonic() + 8
        detail = None
        while time.monotonic() < deadline:
            response = client.get(f"/api/v1/jobs/{job_id}")
            assert response.status_code == 200
            detail = response.json()
            if detail["job"]["status"] in {"completed", "failed"}:
                break
            time.sleep(0.1)
        assert detail is not None
        assert detail["job"]["status"] == "completed", detail
        output = Path(detail["job"]["output_path"])
        assert output.read_bytes() == PAYLOAD
        assert detail["artifacts"][0]["size_bytes"] == len(PAYLOAD)
        assert any(event["type"] == "job.completed" for event in detail["events"])

        settings = client.put(
            "/api/v1/settings",
            json={"theme": "dark", "split_count": 4, "daily_window_start": "00:00"},
        )
        assert settings.status_code == 200
        assert settings.json()["theme"] == "dark"
        assert settings.json()["split_count"] == 4


def test_extension_pairing_and_origin_binding(app_settings) -> None:
    app = create_app(app_settings)
    origin = "chrome-extension://abcdefghijklmnop"
    other_origin = "chrome-extension://otherextension"
    with TestClient(app, base_url="http://127.0.0.1:8765") as client:
        extension_start = client.post("/api/v1/pair/start", headers={"Origin": origin})
        assert extension_start.status_code == 403

        start = client.post("/api/v1/pair/start")
        assert start.status_code == 200
        code = start.json()["code"]
        complete = client.post(
            "/api/v1/pair/complete",
            headers={"Origin": origin},
            json={"code": code, "name": "Chrome Test"},
        )
        assert complete.status_code == 200, complete.text
        token = complete.json()["token"]

        authorized = client.get(
            "/api/v1/jobs",
            headers={"Origin": origin, "Authorization": f"Bearer {token}"},
        )
        assert authorized.status_code == 200

        wrong_origin = client.get(
            "/api/v1/jobs",
            headers={"Origin": other_origin, "Authorization": f"Bearer {token}"},
        )
        assert wrong_origin.status_code == 401

        missing_token = client.get("/api/v1/jobs", headers={"Origin": origin})
        assert missing_token.status_code == 401

        missing_token_settings = client.get("/api/v1/settings", headers={"Origin": origin})
        assert missing_token_settings.status_code == 401

        authorized_settings = client.get(
            "/api/v1/settings",
            headers={"Origin": origin, "Authorization": f"Bearer {token}"},
        )
        assert authorized_settings.status_code == 200

        extension_client_list = client.get(
            "/api/v1/pair/clients",
            headers={"Origin": origin, "Authorization": f"Bearer {token}"},
        )
        assert extension_client_list.status_code == 403

        web_client_list = client.get("/api/v1/pair/clients")
        assert web_client_list.status_code == 200
        assert web_client_list.json()[0]["id"] == complete.json()["client_id"]

        for _ in range(5):
            rejected_code = client.post(
                "/api/v1/pair/complete",
                headers={"Origin": other_origin},
                json={"code": "000000", "client_name": "Kötü istemci"},
            )
            assert rejected_code.status_code == 400
        rate_limited = client.post(
            "/api/v1/pair/complete",
            headers={"Origin": other_origin},
            json={"code": "000000", "client_name": "Kötü istemci"},
        )
        assert rate_limited.status_code == 429

        revoked = client.post(
            "/api/v1/pair/revoke",
            headers={"Origin": origin, "Authorization": f"Bearer {token}"},
            json={},
        )
        assert revoked.status_code == 204
        assert client.get("/api/v1/pair/clients").json() == []
        after_revoke = client.get(
            "/api/v1/jobs",
            headers={"Origin": origin, "Authorization": f"Bearer {token}"},
        )
        assert after_revoke.status_code == 401


def test_csrf_rejects_mismatch_after_web_session(app_settings) -> None:
    app = create_app(app_settings)
    with TestClient(app, base_url="http://127.0.0.1:8765") as client:
        page = client.get("/")
        assert page.status_code == 200
        response = client.post(
            "/api/v1/pair/start",
            headers={"X-CSRF-Token": "wrong"},
        )
        assert response.status_code == 403

        rebound = client.get("/health", headers={"Host": "downloadhub.attacker.invalid"})
        assert rebound.status_code == 400


def test_settings_survive_a_fresh_application_instance(app_settings) -> None:
    with TestClient(create_app(app_settings), base_url="http://127.0.0.1:8765") as client:
        updated = client.put(
            "/api/v1/settings",
            json={
                "split_count": 6,
                "max_concurrent_jobs": 4,
                "global_speed_limit": "2M",
                "timezone": "Europe/Istanbul",
            },
        )
        assert updated.status_code == 200

    fresh_settings = type(app_settings)(
        data_dir=app_settings.data_dir,
        cache_dir=app_settings.cache_dir,
        log_dir=app_settings.log_dir,
        download_dir=app_settings.download_dir,
        database_url=app_settings.database_url,
        allow_private_networks=True,
        split_count=8,
        max_concurrent_jobs=2,
    )
    with TestClient(create_app(fresh_settings), base_url="http://127.0.0.1:8765") as client:
        persisted = client.get("/api/v1/settings")
        assert persisted.status_code == 200
        assert persisted.json()["split_count"] == 6
        assert persisted.json()["max_concurrent_jobs"] == 4
        assert persisted.json()["global_speed_limit"] == "2M"

        invalid = client.put("/api/v1/settings", json={"global_speed_limit": "$(unsafe)"})
        assert invalid.status_code == 422

        invalid_time = client.put("/api/v1/settings", json={"daily_window_start": "25:99"})
        assert invalid_time.status_code == 422

        default_profile = client.put("/api/v1/settings", json={"browser_profile": None})
        assert default_profile.status_code == 200
        assert default_profile.json()["browser_profile"] == "Default"


def test_scheduled_job_priority_cancel_and_safe_validation(app_settings, file_server: str) -> None:
    app = create_app(app_settings)
    with TestClient(app, base_url="http://127.0.0.1:8765") as client:
        created = client.post(
            "/api/v1/jobs",
            headers={"Idempotency-Key": "scheduled-controls"},
            json={
                "url": file_server,
                "engine": "direct",
                "scheduled_at": "2099-01-01T00:00:00+03:00",
            },
        )
        assert created.status_code == 200, created.text
        job_id = created.json()["id"]
        assert created.json()["status"] == "scheduled"

        prioritized = client.post(f"/api/v1/jobs/{job_id}/priority", json={"priority": 7})
        assert prioritized.status_code == 200, prioritized.text
        assert prioritized.json()["priority"] == 7

        cancelled = client.post(f"/api/v1/jobs/{job_id}/cancel")
        assert cancelled.status_code == 200, cancelled.text
        assert cancelled.json()["status"] == "cancelled"

        bad_category = client.post(
            "/api/v1/jobs",
            json={"url": file_server, "engine": "direct", "category": "../../kaçış"},
        )
        assert bad_category.status_code == 422

        uninspected_format = client.post(
            "/api/v1/jobs",
            json={"url": file_server, "engine": "media", "format_id": "best[unsafe]"},
        )
        assert uninspected_format.status_code == 422


def test_category_symlink_cannot_escape_download_root(app_settings, file_server: str) -> None:
    outside = app_settings.data_dir.parent / "outside"
    outside.mkdir(parents=True)
    app_settings.download_dir.mkdir(parents=True)
    (app_settings.download_dir / "Diğer").symlink_to(outside, target_is_directory=True)

    app = create_app(app_settings)
    with TestClient(app, base_url="http://127.0.0.1:8765") as client:
        response = client.post(
            "/api/v1/jobs",
            json={
                "url": file_server,
                "engine": "direct",
                "category": "Diğer",
                "scheduled_at": "2099-01-01T00:00:00+03:00",
            },
        )
        assert response.status_code == 403
        assert not any(outside.iterdir())


def test_sensitive_query_is_used_ephemerally_but_never_persisted(
    app_settings,
    file_server: str,
) -> None:
    secret = "çok-gizli-imza"
    signed_url = f"{file_server}?X-Amz-Signature={secret}&part=1"
    app = create_app(app_settings)
    with TestClient(app, base_url="http://127.0.0.1:8765") as client:
        created = client.post(
            "/api/v1/jobs",
            json={"url": signed_url, "engine": "direct"},
        )
        assert created.status_code == 200, created.text
        job_id = created.json()["id"]

        deadline = time.monotonic() + 8
        detail = None
        while time.monotonic() < deadline:
            detail = client.get(f"/api/v1/jobs/{job_id}").json()
            if detail["job"]["status"] in {"completed", "failed"}:
                break
            time.sleep(0.1)

        assert detail is not None
        assert detail["job"]["status"] == "completed", detail
        assert secret not in json.dumps(detail, ensure_ascii=False)
        assert "[GİZLİ]" in detail["job"]["source_url"]
