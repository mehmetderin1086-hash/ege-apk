"""Yerel protokol, paket güvenliği ve idempotent aktarım testleri."""

from __future__ import annotations

import io
import json
import re
import urllib.error
import zipfile
from pathlib import Path
from unittest.mock import patch

import pytest

from ogretmen_cantasi import entegrasyon, servis
from ogretmen_cantasi import servis_olcme as so


def _zip(manifest: dict, dosyalar: dict[str, bytes] | None = None) -> bytes:
    tampon = io.BytesIO()
    with zipfile.ZipFile(tampon, "w", zipfile.ZIP_DEFLATED) as paket:
        paket.writestr("manifest.json", json.dumps(manifest, ensure_ascii=False))
        for ad, icerik in (dosyalar or {}).items():
            paket.writestr(ad, icerik)
    return tampon.getvalue()


def _soru_paketi() -> bytes:
    return _zip(
        {
            "schema_version": 1,
            "protocol_version": "v1",
            "source_app": "soru-kesici",
            "export_id": "paket-1",
            "type": "questions",
            "questions": [
                {
                    "external_id": "bank:42:abc",
                    "text": "Hücre zarının seçici geçirgenliğini açıklayınız.",
                    "grade": 9,
                    "outcome_code": "BİY.9.1.1",
                    "difficulty": "orta",
                    "rubric": "Açıklama ve örnek",
                    "image": "",
                }
            ],
        }
    )


def test_soru_paketi_onizlenir_ve_yinelenmez(baglanti) -> None:
    icerik = _soru_paketi()
    onizleme = entegrasyon.soru_paketi_onizle(baglanti, icerik)
    assert len(onizleme.eklenecek) == 1
    assert entegrasyon.soru_paketi_uygula(baglanti, icerik, onizleme) == 1
    assert entegrasyon.soru_paketi_uygula(baglanti, icerik, onizleme) == 0
    assert baglanti.execute("SELECT COUNT(*) FROM soru").fetchone()[0] == 1


def test_soru_paketi_yol_kacisini_reddeder(baglanti) -> None:
    manifest = {
        "schema_version": 1,
        "source_app": "soru-kesici",
        "export_id": "kotu",
        "questions": [{"external_id": "1", "text": "Soru", "image": "../veri.db"}],
    }
    with pytest.raises(ValueError, match="güvensiz"):
        entegrasyon.soru_paketi_onizle(
            baglanti, _zip(manifest, {"../veri.db": b"x"})
        )


def test_sinav_paketi_ve_onayli_sonuc_aktarimi(baglanti, yil) -> None:
    sube_id = servis.sube_ekle(
        baglanti, yil.id, "9-A", 9, ogretim_yili_adi=yil.ad
    )
    servis.ogrenci_ekle(baglanti, sube_id, [("101", "Ayşe Yılmaz")])
    soru_id = so.soru_ekle(
        baglanti,
        mufredat_surumu="maarif_2024",
        kazanim_kodu="BİY.9.1.1",
        sinif=9,
        metin="Canlıların ortak özelliklerini açıklayınız.",
        rubrik="Doğru açıklama",
    )
    sinav_id, _sinav, _uyarilar = so.sinav_uret_ve_kaydet(
        baglanti,
        sube_id=sube_id,
        sube_adi="9-A",
        sinif=9,
        mufredat_surumu="maarif_2024",
        ad="Yazılı",
        dagilim={"BİY.9.1": 100},
        soru_sayisi=1,
    )
    paket = entegrasyon.sinav_paketi_uret(baglanti, sinav_id)
    with zipfile.ZipFile(io.BytesIO(paket)) as z:
        dis = json.loads(z.read("manifest.json"))
    ogrenci_dis = dis["students"][0]["external_id"]
    soru_dis = dis["questions"][0]["external_id"]
    sonuc = _zip(
        {
            "schema_version": 1,
            "protocol_version": "v1",
            "source_app": "sinav-okur",
            "export_id": "sonuc-1",
            "type": "exam_results",
            "exam_external_id": f"exam:{sinav_id}",
            "results": [
                {
                    "student_external_id": ogrenci_dis,
                    "question_external_id": soru_dis,
                    "final_score": 80,
                    "approved": True,
                    "confidence": 0.92,
                }
            ],
        }
    )
    onizleme = entegrasyon.sinav_sonucu_onizle(baglanti, sonuc, sinav_id)
    assert onizleme.eklenecek[0]["question_id"] == soru_id
    assert entegrasyon.sinav_sonucu_uygula(
        baglanti, sonuc, sinav_id, onizleme
    ) == 1
    assert so.sinav_puanlari(baglanti, sinav_id)


def test_api_bearer_zorunlu(istemci) -> None:
    assert istemci.get("/api/v1/health").status_code == 401
    yanit = istemci.get(
        "/api/v1/health",
        headers={"Authorization": f"Bearer {entegrasyon.yerel_belirtec()}"},
    )
    assert yanit.status_code == 200
    assert yanit.json()["protocol_version"] == "v1"


def test_entegrasyon_ekrani_acilir(istemci) -> None:
    yanit = istemci.get("/entegrasyonlar")
    assert yanit.status_code == 200
    assert "Soru Kesici" in yanit.text
    assert "Sınav Okur" in yanit.text


def test_entegrasyon_web_ayar_onizleme_ve_uygulama(istemci, monkeypatch) -> None:
    yanit = istemci.post(
        "/entegrasyonlar/soru_kesici/ayar",
        data={"adres": "http://127.0.0.1:18756", "etkin": "1"},
        follow_redirects=False,
    )
    assert yanit.status_code == 303
    kotu = istemci.post(
        "/entegrasyonlar/soru_kesici/ayar",
        data={"adres": "https://example.com", "etkin": "1"},
    )
    assert kotu.status_code == 400
    monkeypatch.setattr(
        entegrasyon,
        "saglik_kontrolu",
        lambda *_args, **_kwargs: {"durum": "hazir", "hata": ""},
    )
    assert (
        istemci.post(
            "/entegrasyonlar/soru_kesici/kontrol", follow_redirects=False
        ).status_code
        == 303
    )

    onizleme = istemci.post(
        "/entegrasyonlar/soru-paketi/onizle",
        files={"dosya": ("sorular.zip", _soru_paketi(), "application/zip")},
    )
    assert onizleme.status_code == 200
    assert "henüz veri yazılmadı" in onizleme.text
    eslesme = re.search(r'name="paket" value="([^"]+)"', onizleme.text)
    assert eslesme
    uygula = istemci.post(
        "/entegrasyonlar/soru-paketi/uygula",
        data={"paket": eslesme.group(1)},
        follow_redirects=False,
    )
    assert uygula.status_code == 303
    assert "1+soru" in uygula.headers["location"]
    assert istemci.get("/api/v1/capabilities").status_code == 401
    yetki = {"Authorization": f"Bearer {entegrasyon.yerel_belirtec()}"}
    assert (
        "exam-results-import"
        in istemci.get("/api/v1/capabilities", headers=yetki).json()["capabilities"]
    )


class _Yanit:
    def __init__(self, icerik: bytes):
        self.icerik = icerik

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False

    def read(self, _sinir: int = -1) -> bytes:
        return self.icerik


def test_baglanti_yalniz_loopback_ve_saglik_durumu(baglanti) -> None:
    entegrasyon.varsayilan_baglantilari_kur(baglanti)
    assert len(entegrasyon.baglantilar(baglanti)) == 3
    with pytest.raises(ValueError, match="Bilinmeyen"):
        entegrasyon.baglanti_guncelle(
            baglanti, "yabanci", adres="http://127.0.0.1:1", etkin=True
        )
    with pytest.raises(ValueError, match="yerel"):
        entegrasyon.baglanti_guncelle(
            baglanti, "soru_kesici", adres="https://example.com", etkin=True
        )
    entegrasyon.baglanti_guncelle(
        baglanti, "soru_kesici", adres="http://localhost:18756/", etkin=False
    )
    assert entegrasyon.saglik_kontrolu(baglanti, "soru_kesici")["durum"] == "kapali"
    entegrasyon.baglanti_guncelle(
        baglanti, "soru_kesici", adres="http://localhost:18756", etkin=True
    )
    with patch(
        "urllib.request.urlopen",
        return_value=_Yanit(b'{"protocol_version":"v1","status":"ok"}'),
    ):
        assert entegrasyon.saglik_kontrolu(baglanti, "soru_kesici")["durum"] == "hazir"
    with patch(
        "urllib.request.urlopen",
        return_value=_Yanit(b'{"protocol_version":"v2"}'),
    ):
        sonuc = entegrasyon.saglik_kontrolu(baglanti, "soru_kesici")
        assert sonuc["durum"] == "hata"
        assert "Uyumsuz" in sonuc["hata"]
    with patch(
        "urllib.request.urlopen",
        side_effect=urllib.error.URLError("erişim yok"),
    ):
        assert entegrasyon.saglik_kontrolu(baglanti, "soru_kesici")["durum"] == "hata"


def test_guvenli_zip_ve_soru_gorseli_davranislari(
    baglanti, monkeypatch, tmp_path: Path
) -> None:
    monkeypatch.setattr(entegrasyon.ayarlar, "materyal_dizini", lambda: tmp_path)
    with pytest.raises(ValueError, match="ZIP"):
        entegrasyon.soru_paketi_onizle(baglanti, _zip({}, {"x.txt": b"x"})[:-5])
    gecersizler = [
        {"schema_version": 2, "source_app": "soru-kesici", "export_id": "x", "questions": [{}]},
        {"schema_version": 1, "source_app": "diger", "export_id": "x", "questions": [{}]},
        {"schema_version": 1, "source_app": "soru-kesici", "export_id": "", "questions": [{}]},
        {"schema_version": 1, "source_app": "soru-kesici", "export_id": "x", "questions": []},
    ]
    for manifest in gecersizler:
        with pytest.raises(ValueError):
            entegrasyon.soru_paketi_onizle(baglanti, _zip(manifest))

    manifest = {
        "schema_version": 1,
        "source_app": "soru-kesici",
        "export_id": "gorselli",
        "questions": [
            "bozuk",
            {"external_id": "", "text": ""},
            {"external_id": "7", "text": "Görselli soru", "image": "soru.png"},
        ],
    }
    icerik = _zip(manifest, {"soru.png": b"PNG"})
    onizleme = entegrasyon.soru_paketi_onizle(baglanti, icerik)
    assert len(onizleme.uyarilar) == 2
    assert entegrasyon.soru_paketi_uygula(baglanti, icerik, onizleme) == 1
    gorsel = baglanti.execute("SELECT gorsel_yolu FROM soru").fetchone()[0]
    assert Path(gorsel).read_bytes() == b"PNG"
    assert entegrasyon.aktarimlari_oku(baglanti)


def test_dogrudan_soru_alma_hatalari_ve_basari(baglanti) -> None:
    with pytest.raises(ValueError, match="1 ile 500"):
        entegrasyon.soru_kesiciden_paket_al(baglanti, [])
    entegrasyon.varsayilan_baglantilari_kur(baglanti)
    with patch("urllib.request.urlopen", return_value=_Yanit(b"paket")):
        assert entegrasyon.soru_kesiciden_paket_al(baglanti, [1, 2]) == b"paket"
    with patch(
        "urllib.request.urlopen", side_effect=urllib.error.URLError("kapalı")
    ), pytest.raises(ConnectionError, match="bağlanılamadı"):
        entegrasyon.soru_kesiciden_paket_al(baglanti, [1])


def test_sinav_okur_dogrudan_gonderme_ve_sonuc_alma(
    baglanti, yil
) -> None:
    sube_id = servis.sube_ekle(
        baglanti, yil.id, "9-A", 9, ogretim_yili_adi=yil.ad
    )
    servis.ogrenci_ekle(baglanti, sube_id, [("101", "Ayşe Yılmaz")])
    so.soru_ekle(
        baglanti,
        mufredat_surumu="maarif_2024",
        kazanim_kodu="BİY.9.1.1",
        sinif=9,
        metin="Canlı nedir?",
        rubrik="Açıklama",
    )
    sinav_id, *_ = so.sinav_uret_ve_kaydet(
        baglanti,
        sube_id=sube_id,
        sube_adi="9-A",
        sinif=9,
        mufredat_surumu="maarif_2024",
        ad="Yazılı",
        dagilim={"BİY.9.1": 100},
        soru_sayisi=1,
    )
    entegrasyon.varsayilan_baglantilari_kur(baglanti)
    with patch(
        "urllib.request.urlopen",
        return_value=_Yanit(b'{"exam_id":17,"status":"draft"}'),
    ):
        assert entegrasyon.sinav_okura_gonder(baglanti, sinav_id)["exam_id"] == 17
    sonuc_paketi = _zip({"schema_version": 1})
    with patch("urllib.request.urlopen", return_value=_Yanit(sonuc_paketi)):
        assert entegrasyon.sinav_okurdan_sonuc_al(baglanti, sinav_id) == sonuc_paketi

    baglanti.execute("DELETE FROM aktarim_islemi")
    with pytest.raises(LookupError, match="önce"):
        entegrasyon.sinav_okurdan_sonuc_al(baglanti, sinav_id)


# --- P4.5: salt okunur günlük JSON uçları ve X-Api-Token -----------------------


def _okul_verisi(tmp_path: Path) -> int:
    """İstemcinin veritabanına bir yıl, şube, öğrenci, program, yoklama ve defter yazar; şube kimliğini döndürür."""
    from datetime import date

    from ogretmen_cantasi import depo
    from ogretmen_cantasi import takvim as tk

    b = depo.baglan(tmp_path / "veri.db")
    try:
        ad, d1, d2 = tk.varsayilan_ogretim_yili(2026)
        yil = servis.ogretim_yili_kur(b, ad, d1, d2)
        sube_id = servis.sube_ekle(b, yil.id, "9-A", 9, ogretim_yili_adi=yil.ad)
        servis.ogrenci_ekle(b, sube_id, [("101", "Ayşe Yılmaz"), ("102", "Ali Kaya")])
        gun = date(2026, 9, 15)  # Salı
        servis.ders_programi_yaz(b, [(sube_id, gun.isoweekday(), 3), (sube_id, gun.isoweekday(), 4)])
        ogrenciler = {o["numara"]: o["id"] for o in servis.ogrencileri_oku(b, sube_id)}
        servis.yoklama_kaydet(b, sube_id, gun, 3, {ogrenciler["101"]: "var", ogrenciler["102"]: "yok"})
        servis.ders_kaydi_yaz(
            b, sube_id, gun, ders_saatleri=[3, 4], kazanim_kodlari=["BİY.9.1.1"], aciklama="Hücre"
        )
        return sube_id
    finally:
        b.close()


def test_api_x_api_token_kabul_yanlisi_401(istemci) -> None:
    dogru = {"X-Api-Token": entegrasyon.yerel_belirtec()}
    assert istemci.get("/api/v1/health", headers=dogru).status_code == 200
    assert istemci.get("/api/v1/health", headers={"X-Api-Token": "yanlis"}).status_code == 401
    # Caddy basic_auth `Authorization`'ı tutarken ayrı başlıkla doğrulama sürer.
    karisik = {"Authorization": "Basic eDp5", **dogru}
    assert istemci.get("/api/v1/health", headers=karisik).status_code == 200
    # ASCII dışı başlık 500 değil 401 vermeli.
    assert (
        istemci.get("/api/v1/health", headers={"X-Api-Token": "ç".encode()}).status_code
        == 401
    )
    yetenekler = istemci.get("/api/v1/capabilities", headers=dogru).json()["capabilities"]
    assert "daily-json" in yetenekler and "mcp" in yetenekler


def test_api_bugun_bearer_olmadan_401_ve_sema(istemci, tmp_path) -> None:
    assert istemci.get("/api/v1/bugun").status_code == 401
    yetki = {"Authorization": f"Bearer {entegrasyon.yerel_belirtec()}"}
    bos = istemci.get("/api/v1/bugun?tarih=2026-09-15", headers=yetki).json()
    assert bos["kurulum_gerekli"] is True and bos["bloklar"] == []

    sube_id = _okul_verisi(tmp_path)
    veri = istemci.get("/api/v1/bugun?tarih=2026-09-15", headers=yetki).json()
    assert veri["tarih"] == "2026-09-15" and veri["kurulum_gerekli"] is False
    assert set(veri) >= {"gun_adi", "tatil", "bloklar", "uyarilar"}
    assert len(veri["bloklar"]) == 1
    blok = veri["bloklar"][0]
    assert blok["sube_id"] == sube_id and blok["saatler"] == [3, 4]
    assert blok["yoklama_alindi"] is True
    assert blok["ders_kaydi"]["kazanim_kodlari"] == ["BİY.9.1.1"]
    assert blok["ders_kaydi"]["ders_saatleri"] == [3, 4]
    assert "plan" in blok
    assert istemci.get("/api/v1/bugun?tarih=bozuk", headers=yetki).status_code == 400
    # HTML ana sayfa aynı ortak hesabı kullanmaya devam eder.
    assert istemci.get("/?tarih=2026-09-15").status_code == 200


def test_api_yoklama_ve_ders_defteri(istemci, tmp_path) -> None:
    sube_id = _okul_verisi(tmp_path)
    yetki = {"Authorization": f"Bearer {entegrasyon.yerel_belirtec()}"}
    yoklama = istemci.get(f"/api/v1/yoklama/{sube_id}?tarih=2026-09-15", headers=yetki).json()
    assert yoklama["ders_saati"] == 3 and yoklama["alindi"] is True
    assert yoklama["sayilar"] == {"var": 1, "yok": 1}
    assert [g["numara"] for g in yoklama["gelmeyenler"]] == ["102"]
    assert any(d["numara"] == "102" for d in yoklama["devamsizlik"])
    assert istemci.get("/api/v1/yoklama/9999?tarih=2026-09-15", headers=yetki).status_code == 404

    defter = istemci.get(
        f"/api/v1/ders-defteri?sube_id={sube_id}&tarih=2026-09-15", headers=yetki
    ).json()
    assert defter["sube_adi"] == "9-A"
    assert defter["kayitlar"][0]["aciklama"] == "Hücre"
    assert istemci.get("/api/v1/ders-defteri?sube_id=9999", headers=yetki).status_code == 404
