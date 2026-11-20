"""API duman testleri — model gerektirmeyen uçlar."""
import io

import numpy as np
import pytest
import soundfile as sf
from fastapi.testclient import TestClient

from app.main import app
from app.api.tts import TTSRequest


@pytest.fixture()
def client():
    with TestClient(app) as c:
        yield c


def test_system_status(client):
    r = client.get("/api/system/status")
    assert r.status_code == 200
    data = r.json()
    assert set(data["engines"]) == {"tts", "vc", "stt", "xtts"}
    assert "models_present" in data
    # xtts opsiyoneldir; available bayrağı venv varlığını yansıtır
    assert isinstance(data["engines"]["xtts"]["available"], bool)


def test_normalize_preview(client):
    r = client.post(
        "/api/normalize/preview",
        json={"text": "Saat 09:05 vapuru %50 doluydu."},
    )
    assert r.status_code == 200
    data = r.json()
    assert "dokuz sıfır beş" in data["normalized"]
    assert "yüzde elli" in data["normalized"]
    assert len(data["chunks"]) == 1


def test_engines_endpoint(client):
    r = client.get("/api/engines")
    assert r.status_code == 200
    data = r.json()
    assert data["default"] in ("chatterbox", "xtts")
    assert data["engines"]["chatterbox"]["available"] is True
    # Varsayılan motor her zaman kullanılabilir olmalı
    assert data["engines"][data["default"]]["available"] is True


def test_languages(client):
    r = client.get("/api/languages")
    data = r.json()
    assert data["default"] == "tr"
    assert "tr" in data["languages"]
    assert len(data["languages"]) == 23


def test_voices_bos_liste(client):
    r = client.get("/api/voices")
    assert r.status_code == 200
    assert isinstance(r.json()["voices"], list)


def test_voice_create_ve_sil(client):
    # 5 saniyelik test tonu — klon örneği olarak geçerli
    sr = 24000
    tone = (0.4 * np.sin(2 * np.pi * 220 * np.arange(sr * 5) / sr)).astype("float32")
    buf = io.BytesIO()
    sf.write(buf, tone, sr, format="WAV")
    buf.seek(0)

    r = client.post(
        "/api/voices",
        data={"name": "Test Sesi"},
        files={"file": ("ornek.wav", buf, "audio/wav")},
    )
    assert r.status_code == 200, r.text
    voice = r.json()
    assert voice["name"] == "Test Sesi"
    assert 4.5 < voice["duration_s"] < 5.5

    # listede görünür
    voices = client.get("/api/voices").json()["voices"]
    assert any(v["id"] == voice["id"] for v in voices)

    # yeniden adlandır
    r = client.patch(f"/api/voices/{voice['id']}", json={"name": "Yeni Ad"})
    assert r.json()["name"] == "Yeni Ad"

    # sil
    assert client.delete(f"/api/voices/{voice['id']}").status_code == 200
    voices = client.get("/api/voices").json()["voices"]
    assert not any(v["id"] == voice["id"] for v in voices)


def test_voice_cok_kisa_reddedilir(client):
    sr = 24000
    tone = (0.4 * np.sin(2 * np.pi * 220 * np.arange(sr) / sr)).astype("float32")
    buf = io.BytesIO()
    sf.write(buf, tone, sr, format="WAV")
    buf.seek(0)
    r = client.post(
        "/api/voices",
        data={"name": "Kısa"},
        files={"file": ("kisa.wav", buf, "audio/wav")},
    )
    assert r.status_code == 400
    assert "kısa" in r.json()["detail"].lower()


def test_project_olustur_parcala_sil(client):
    text = "\n\n".join(
        " ".join(f"Bu {i} numaralı paragrafın {j} numaralı cümlesidir." for j in range(8))
        for i in range(3)
    )
    r = client.post(
        "/api/projects",
        json={"title": "Test Projesi", "text": text, "normalize": True},
    )
    assert r.status_code == 200, r.text
    project = r.json()
    assert project["chunk_count"] > 1
    assert all(c["status"] == "pending" for c in project["chunks"])
    # normalizasyon: rakamlar yazıya dökülmüş olmalı
    assert "numaralı" in project["chunks"][0]["text"]
    assert not any(ch.isdigit() for ch in project["chunks"][0]["text"])

    # getir + sil
    assert client.get(f"/api/projects/{project['id']}").status_code == 200
    assert client.delete(f"/api/projects/{project['id']}").status_code == 200
    assert client.get(f"/api/projects/{project['id']}").status_code == 404


def test_voice_path_traversal_engellenir(client):
    # Kimlik doğrulaması: uuid-hex dışındaki her şey dosya sistemine
    # dokunmadan KeyError/404 almalı
    import pytest as _pytest

    from app.core import voices as voices_core

    for bad in ("..", "../outputs", ".", "x" * 12, "AB12", ""):
        with _pytest.raises(KeyError):
            voices_core.delete_voice(bad)
    # API düzeyi: geçerli biçimli ama var olmayan kimlik → 404
    assert client.delete("/api/voices/aaaaaaaaaaaa").status_code == 404


def test_project_gecersiz_dil_reddedilir(client):
    r = client.post(
        "/api/projects",
        json={"title": "X", "text": "Merhaba dünya.", "language": "xx"},
    )
    assert r.status_code == 400


def test_history_negatif_limit(client):
    r = client.get("/api/history?limit=-5")
    assert r.status_code == 200  # sınırsız SELECT değil, sıkıştırılmış limit


def test_project_extract_txt(client):
    content = "Kitap metni burada.\n\nİkinci bölüm paragrafı."
    r = client.post(
        "/api/projects/extract",
        files={"file": ("kitap.txt", io.BytesIO(content.encode()), "text/plain")},
    )
    assert r.status_code == 200, r.text
    data = r.json()
    assert data["chars"] == len(content)
    assert "İkinci bölüm" in data["text"]


def test_project_verify_parametresi(client):
    r = client.post(
        "/api/projects",
        json={"title": "Hızlı", "text": "Deneme cümlesi.", "verify": False},
    )
    assert r.status_code == 200
    project = r.json()
    assert project["params"]["verify"] is False
    client.delete(f"/api/projects/{project['id']}")


def test_history_bos(client):
    r = client.get("/api/history")
    assert r.status_code == 200
    assert isinstance(r.json()["items"], list)


def test_statik_arayuz(client):
    r = client.get("/")
    assert r.status_code == 200
    assert "SesLab" in r.text


def test_tts_1500_karakter_siniri_yok():
    req = TTSRequest(text="a" * 50_000)
    assert len(req.text) == 50_000
    assert req.verify is False
