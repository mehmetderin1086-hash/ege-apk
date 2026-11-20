import os

from fastapi.testclient import TestClient

from biyo_cozucu.motor.temel import SahteMotor
from biyo_cozucu.webapp import uygulama_kur


def test_yerel_api_yetki_ve_yetenekler(tmp_path, monkeypatch) -> None:
    token = tmp_path / "token"
    token.write_text("gizli-yerel-token", encoding="utf-8")
    monkeypatch.setenv("OGRETMEN_API_TOKEN_YOLU", str(token))
    app = uygulama_kur(kok=tmp_path / "veri", motor_turu="yok", gommesiz=True)
    with TestClient(app) as istemci:
        assert istemci.get("/api/v1/health").status_code == 401
        baslik = {"Authorization": "Bearer gizli-yerel-token"}
        saglik = istemci.get("/api/v1/health", headers=baslik)
        yetenek = istemci.get("/api/v1/capabilities", headers=baslik)
    assert saglik.status_code == 200
    assert saglik.json()["protocol_version"] == "v1"
    assert "sourced-suggestions" in yetenek.json()["capabilities"]


def test_launcher_healthz_kimliksiz_ama_yalniz_loopback(tmp_path, monkeypatch) -> None:
    monkeypatch.setenv("BIYO_BUILD_ID", "launcher-test-build")
    app = uygulama_kur(kok=tmp_path / "veri", motor_turu="yok", gommesiz=True)

    with TestClient(app, client=("127.0.0.1", 50123)) as istemci:
        yanit = istemci.get("/healthz")
    assert yanit.status_code == 200
    assert yanit.json() == {
        "app": "biyo-cozucu",
        "build": "launcher-test-build",
        "pid": os.getpid(),
        "status": "ready",
    }

    with TestClient(app, client=("203.0.113.8", 50124)) as istemci:
        assert istemci.get("/healthz").status_code == 403


# --- /api/v1/uret: sinav-okur gibi dış süreçlerin ham üretim ucu ---


def test_uret_ucu_mesajlari_degistirmeden_motora_iletir(tmp_path, monkeypatch) -> None:
    from biyo_cozucu import motor as motor_modulu

    sahte = SahteMotor("Merhaba, nasıl yardımcı olabilirim?")
    monkeypatch.setattr(motor_modulu, "motor_yukle", lambda *a, **k: sahte)
    app = uygulama_kur(kok=tmp_path / "veri", motor_turu="sahte", gommesiz=True)

    govde = {
        "mesajlar": [
            {"role": "system", "content": "Sen yardımcı bir asistansın."},
            {"role": "user", "content": "Selam"},
        ],
        "sicaklik": 0.1,
        "azami_token": 32,
    }
    with TestClient(app, client=("127.0.0.1", 50125)) as istemci:
        yanit = istemci.post("/api/v1/uret", json=govde)

    assert yanit.status_code == 200
    assert yanit.json() == {
        "metin": "Merhaba, nasıl yardımcı olabilirim?",
        "model": "sahte",
    }
    # Çeviri katmanı yok: motor tam olarak gönderilen mesajları görmeli.
    assert sahte.cagrilar == [govde["mesajlar"]]


def test_uret_ucu_loopback_disindan_reddedilir(tmp_path) -> None:
    app = uygulama_kur(kok=tmp_path / "veri", motor_turu="yok", gommesiz=True)
    govde = {"mesajlar": [{"role": "user", "content": "Selam"}]}
    with TestClient(app, client=("203.0.113.8", 50126)) as istemci:
        yanit = istemci.post("/api/v1/uret", json=govde)
    assert yanit.status_code == 403


def test_uret_ucu_bozuk_govdeyi_reddeder(tmp_path) -> None:
    app = uygulama_kur(kok=tmp_path / "veri", motor_turu="yok", gommesiz=True)
    with TestClient(app, client=("127.0.0.1", 50127)) as istemci:
        assert istemci.post("/api/v1/uret", json={}).status_code == 422
        assert (
            istemci.post("/api/v1/uret", json={"mesajlar": []}).status_code == 422
        )
        assert (
            istemci.post(
                "/api/v1/uret", json={"mesajlar": [{"role": "user"}]}
            ).status_code
            == 422
        )
        assert istemci.post("/api/v1/uret", content=b"gecersiz-json").status_code == 422


def test_uret_ucu_motor_yoksa_502_doner(tmp_path) -> None:
    app = uygulama_kur(kok=tmp_path / "veri", motor_turu="yok", gommesiz=True)
    govde = {"mesajlar": [{"role": "user", "content": "Selam"}]}
    with TestClient(app, client=("127.0.0.1", 50128)) as istemci:
        yanit = istemci.post("/api/v1/uret", json=govde)
    assert yanit.status_code == 502
    assert "hata" in yanit.json()


def test_uret_ucu_motor_hatasinda_502_doner(tmp_path, monkeypatch) -> None:
    from biyo_cozucu import motor as motor_modulu

    monkeypatch.setattr(motor_modulu, "motor_yukle", lambda *a, **k: SahteMotor())
    app = uygulama_kur(kok=tmp_path / "veri", motor_turu="sahte", gommesiz=True)
    govde = {"mesajlar": [{"role": "user", "content": "Selam"}]}
    with TestClient(app, client=("127.0.0.1", 50129)) as istemci:
        yanit = istemci.post("/api/v1/uret", json=govde)
    assert yanit.status_code == 502
    assert "hata" in yanit.json()
