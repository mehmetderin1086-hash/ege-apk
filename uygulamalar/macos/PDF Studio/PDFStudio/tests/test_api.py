"""HTTP katmanı testleri (FastAPI TestClient)."""
from __future__ import annotations

from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def _upload(sample_pdf: Path):
    with open(sample_pdf, "rb") as f:
        res = client.post("/api/upload", files={"files": ("ornek.pdf", f, "application/pdf")})
    assert res.status_code == 200
    data = res.json()
    return data["session_id"], data["files"][0]["file_id"]


def test_health():
    data = client.get("/health").json()
    assert data["status"] == "ok"
    assert data["app"] == "pdf-studio"  # launcher bu imzayla "gerçekten biz miyiz" bakar


def test_index_and_static():
    assert client.get("/").status_code == 200
    assert client.get("/css/styles.css").status_code == 200
    assert client.get("/js/app.js").status_code == 200


def test_upload_info_render(sample_pdf):
    sid, fid = _upload(sample_pdf)
    info = client.get(f"/api/info/{fid}", params={"session": sid}).json()
    assert info["page_count"] == 4
    r = client.get(f"/api/thumb/{fid}", params={"session": sid, "page": 0})
    assert r.status_code == 200 and r.headers["content-type"] == "image/png"


def test_merge_endpoint(sample_pdf):
    sid, fid = _upload(sample_pdf)
    _, fid2 = _upload(sample_pdf)
    # ikinci upload aynı oturumu kullanmayabilir; aynı oturumda iki kez yükle
    with open(sample_pdf, "rb") as f:
        res = client.post("/api/upload", files={"files": ("ornek.pdf", f, "application/pdf")},
                          data={"session_id": sid})
    fid2 = res.json()["files"][0]["file_id"]
    r = client.post("/api/organize/merge", json={"session": sid, "file_ids": [fid, fid2]})
    assert r.status_code == 200
    assert len(r.json()["outputs"]) == 1


def test_watermark_compress_pagenumbers(sample_pdf):
    sid, fid = _upload(sample_pdf)
    r = client.post("/api/edit/watermark-text", json={"session": sid, "file_id": fid, "text": "GİZLİ", "rotation": 45})
    assert r.status_code == 200
    r = client.post("/api/optimize/compress", json={"session": sid, "file_id": fid, "level": "orta"})
    assert r.status_code == 200 and "meta" in r.json()
    r = client.post("/api/edit/page-numbers", json={"session": sid, "file_id": fid, "position": "alt-orta", "fmt": "{n}/{total}"})
    assert r.status_code == 200


def test_convert_endpoints(sample_pdf):
    sid, fid = _upload(sample_pdf)
    assert client.post("/api/convert/pdf-to-images", json={"session": sid, "file_id": fid, "fmt": "png", "dpi": 90}).status_code == 200
    assert client.post("/api/convert/pdf-to-text", json={"session": sid, "file_id": fid}).status_code == 200
    assert client.post("/api/convert/text-to-pdf", json={"session": sid, "text": "Merhaba çğ"}).status_code == 200


def test_security_endpoints(sample_pdf):
    sid, fid = _upload(sample_pdf)
    r = client.post("/api/security/protect", json={"session": sid, "file_id": fid, "password": "sifre123"})
    assert r.status_code == 200
    enc_fid = r.json()["outputs"][0]["file_id"]
    r = client.post("/api/security/unlock", json={"session": sid, "file_id": enc_fid, "password": "sifre123"})
    assert r.status_code == 200
    # yanlış parola -> 400
    r = client.post("/api/security/unlock", json={"session": sid, "file_id": enc_fid, "password": "yanlis"})
    assert r.status_code == 400


def test_annotate_and_redact(sample_pdf):
    sid, fid = _upload(sample_pdf)
    annos = [{"page": 0, "type": "text", "text": "x", "x": 50, "y": 50, "w": 100, "h": 30, "fontsize": 14}]
    assert client.post("/api/edit/annotate", json={"session": sid, "file_id": fid, "annotations": annos, "image_refs": {}}).status_code == 200
    boxes = [{"page": 0, "x0": 70, "y0": 80, "x1": 320, "y1": 100}]
    assert client.post("/api/edit/redact", json={"session": sid, "file_id": fid, "boxes": boxes}).status_code == 200


def test_download(sample_pdf):
    sid, fid = _upload(sample_pdf)
    r = client.post("/api/edit/page-numbers", json={"session": sid, "file_id": fid})
    out = r.json()["outputs"][0]
    d = client.get(out["download_url"])
    assert d.status_code == 200 and d.content[:4] == b"%PDF"


def test_bad_session():
    r = client.get("/api/info/xxx", params={"session": "nonexistent"})
    assert r.status_code == 404


def test_session_file_management(sample_pdf):
    sid, fid = _upload(sample_pdf)
    listing = client.get("/api/session/files", params={"session": sid})
    assert listing.status_code == 200
    data = listing.json()
    assert data["total_size"] > 0
    assert [item["file_id"] for item in data["files"]] == [fid]

    deleted = client.delete(f"/api/session/files/{fid}", params={"session": sid})
    assert deleted.status_code == 200
    assert client.get(f"/api/info/{fid}", params={"session": sid}).status_code == 404


def test_clear_session_and_reject_unsafe_ids(sample_pdf):
    sid, fid = _upload(sample_pdf)
    assert client.get("/api/session/files", params={"session": "../" + sid}).status_code == 404
    assert client.delete("/api/session/files/not-valid", params={"session": sid}).status_code == 404

    cleared = client.delete("/api/session", params={"session": sid})
    assert cleared.status_code == 200
    assert client.get("/api/session/files", params={"session": sid}).status_code == 404


# ---------------- Toplu işlem ----------------
def _upload_two(sample_pdf):
    sid, fid1 = _upload(sample_pdf)
    with open(sample_pdf, "rb") as f:
        res = client.post("/api/upload", files={"files": ("ornek2.pdf", f, "application/pdf")},
                          data={"session_id": sid})
    fid2 = res.json()["files"][0]["file_id"]
    return sid, fid1, fid2


def test_batch_compress_two_files(sample_pdf):
    sid, fid1, fid2 = _upload_two(sample_pdf)
    r = client.post("/api/batch/apply", json={
        "session": sid, "file_ids": [fid1, fid2],
        "operation": "compress", "params": {"level": "orta"},
    })
    assert r.status_code == 200
    data = r.json()
    assert len(data["outputs"]) == 3  # zip + 2 PDF
    assert any(o["kind"] == "zip" for o in data["outputs"])
    assert data["meta"] is None  # hiçbir dosya atlanmadı


def test_batch_invalid_operation(sample_pdf):
    sid, fid = _upload(sample_pdf)
    r = client.post("/api/batch/apply", json={
        "session": sid, "file_ids": [fid], "operation": "olmayan-islem",
    })
    assert r.status_code == 400


def test_batch_partial_failure_reported(sample_pdf):
    sid, fid1, _ = _upload_two(sample_pdf)
    r = client.post("/api/batch/apply", json={
        "session": sid, "file_ids": [fid1, "gecersizid1234"],
        "operation": "rotate", "params": {"degrees": 90},
    })
    assert r.status_code == 200
    data = r.json()
    assert len(data["outputs"]) == 1  # tek çıktı, zip yok
    assert data["meta"]["failed"][0]["error"]


# ---------------- Karşılaştırma ----------------
def test_compare_text_identical(sample_pdf):
    sid, fid1, fid2 = _upload_two(sample_pdf)
    r = client.post("/api/compare/text", json={
        "session": sid, "file_id_a": fid1, "file_id_b": fid2,
    })
    assert r.status_code == 200
    rep = r.json()
    assert rep["summary"]["identical"] is True
    assert all(p["similarity"] == 1.0 for p in rep["page_pairs"])
