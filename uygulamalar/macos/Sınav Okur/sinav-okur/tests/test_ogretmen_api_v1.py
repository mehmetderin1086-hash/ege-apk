import io
import json
import zipfile

from fastapi.testclient import TestClient

from sinav_okur.depo import Depo
from sinav_okur.modeller import PuanSonucu, TanimaSonucu
from sinav_okur.sonuclar import KagitSonucu, KutuSonucu
from sinav_okur.webapp import uygulama_kur


def _paket() -> bytes:
    manifest = {
        "schema_version": 1,
        "protocol_version": "v1",
        "source_app": "ogretmen-cantasi",
        "export_id": "exam:3",
        "type": "exam",
        "exam": {
            "external_id": "exam:3",
            "name": "1. Yazılı",
            "grade": 9,
            "class_name": "9-A",
        },
        "questions": [
            {
                "external_id": "question:11",
                "order": 1,
                "text": "Canlıların ortak özelliklerini açıklayınız.",
                "max_score": 100,
                "rubric": "Doğru biyolojik açıklama",
                "outcome_code": "BİY.9.1.1",
            }
        ],
        "students": [
            {
                "external_id": "student:5",
                "school_number": "101",
                "name": "Ayşe Yılmaz",
            }
        ],
    }
    tampon = io.BytesIO()
    with zipfile.ZipFile(tampon, "w", zipfile.ZIP_DEFLATED) as paket:
        paket.writestr("manifest.json", json.dumps(manifest, ensure_ascii=False))
    return tampon.getvalue()


def test_api_yetki_ve_sinav_paketi(tmp_path, monkeypatch) -> None:
    token = tmp_path / "token"
    token.write_text("gizli-yerel-token", encoding="utf-8")
    monkeypatch.setenv("OGRETMEN_API_TOKEN_YOLU", str(token))
    db = tmp_path / "sinav.db"
    app = uygulama_kur(
        str(db), str(tmp_path / "kirp"), str(tmp_path / "veri")
    )
    with TestClient(app) as istemci:
        assert istemci.get("/api/v1/health").status_code == 401
        baslik = {"Authorization": "Bearer gizli-yerel-token"}
        assert istemci.get("/api/v1/health", headers=baslik).status_code == 200
        yanit = istemci.post(
            "/api/v1/exams/import",
            headers=baslik,
            files={"package": ("sinav.zip", _paket(), "application/zip")},
        )
    assert yanit.status_code == 200
    assert yanit.json()["exam_id"] == "oc-exam-3"
    assert Depo(db).sinav_yukle("oc-exam-3").sorular[0].puan == 100


def _uygulama(tmp_path, monkeypatch):
    token = tmp_path / "token"
    token.write_text("gizli-yerel-token", encoding="utf-8")
    monkeypatch.setenv("OGRETMEN_API_TOKEN_YOLU", str(token))
    db = tmp_path / "sinav.db"
    app = uygulama_kur(str(db), str(tmp_path / "kirp"), str(tmp_path / "veri"))
    return app, db


def test_yanlis_token_reddedilir(tmp_path, monkeypatch) -> None:
    app, _ = _uygulama(tmp_path, monkeypatch)
    with TestClient(app) as istemci:
        yanit = istemci.get(
            "/api/v1/health", headers={"Authorization": "Bearer yanlis-token"}
        )
    assert yanit.status_code == 401


def test_sisik_manifest_reddedilir(tmp_path, monkeypatch) -> None:
    """Küçük sıkışan ama 10 MiB üstü açılan manifest (zip bombası) 413 alır."""
    app, _ = _uygulama(tmp_path, monkeypatch)
    tampon = io.BytesIO()
    with zipfile.ZipFile(tampon, "w", zipfile.ZIP_DEFLATED) as paket:
        paket.writestr("manifest.json", " " * (11 * 1024 * 1024))
    with TestClient(app) as istemci:
        yanit = istemci.post(
            "/api/v1/exams/import",
            headers={"Authorization": "Bearer gizli-yerel-token"},
            files={"package": ("sinav.zip", tampon.getvalue(), "application/zip")},
        )
    assert yanit.status_code == 413


def test_ayni_dis_kimlik_yeniden_aktarim(tmp_path, monkeypatch) -> None:
    """Kâğıt okunmadan yeniden içe aktarma günceller; okunmuş kâğıt varsa 409."""
    app, db = _uygulama(tmp_path, monkeypatch)
    baslik = {"Authorization": "Bearer gizli-yerel-token"}
    dosya = {"package": ("sinav.zip", _paket(), "application/zip")}
    with TestClient(app) as istemci:
        assert istemci.post(
            "/api/v1/exams/import", headers=baslik, files=dosya
        ).status_code == 200
        # Henüz kâğıt yok: yeniden aktarma güncelleme sayılır.
        assert istemci.post(
            "/api/v1/exams/import", headers=baslik, files=dosya
        ).status_code == 200
        Depo(db).kagit_kaydet(
            KagitSonucu(
                sinav_kimlik="oc-exam-3",
                islenen_sayfalar=[1],
                kutular=[
                    KutuSonucu(
                        soru_no=1,
                        tanima=TanimaSonucu(metin="cevap", guven=0.9),
                        puan=PuanSonucu(puan=50, max_puan=100, guven=0.9),
                    )
                ],
            ),
            ogrenci_ad="Öğrenci",
        )
        yanit = istemci.post("/api/v1/exams/import", headers=baslik, files=dosya)
    assert yanit.status_code == 409


def test_farkli_dis_kimlik_ayni_ic_kimlige_carpismaz(tmp_path, monkeypatch) -> None:
    """Kayıplı normalizasyonda 'exam:3' ile 'exam/3' aynı iç kimliğe düşer;
    ikincisi ilkini sessizce ezmemeli."""
    app, _ = _uygulama(tmp_path, monkeypatch)
    baslik = {"Authorization": "Bearer gizli-yerel-token"}

    def paket(dis_kimlik: str) -> bytes:
        manifest = json.loads(
            zipfile.ZipFile(io.BytesIO(_paket())).read("manifest.json")
        )
        manifest["exam"]["external_id"] = dis_kimlik
        tampon = io.BytesIO()
        with zipfile.ZipFile(tampon, "w") as z:
            z.writestr("manifest.json", json.dumps(manifest, ensure_ascii=False))
        return tampon.getvalue()

    with TestClient(app) as istemci:
        assert istemci.post(
            "/api/v1/exams/import", headers=baslik,
            files={"package": ("a.zip", paket("exam:3"), "application/zip")},
        ).status_code == 200
        yanit = istemci.post(
            "/api/v1/exams/import", headers=baslik,
            files={"package": ("b.zip", paket("exam/3"), "application/zip")},
        )
    assert yanit.status_code == 409
    assert "çakışması" in yanit.json()["detail"]
