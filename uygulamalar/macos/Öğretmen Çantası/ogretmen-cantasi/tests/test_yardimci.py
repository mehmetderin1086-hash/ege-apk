"""Kaynak zorunluluğu, öğretmen kararı ve destek planı testleri."""

from __future__ import annotations

import re

import pytest

from ogretmen_cantasi import servis, yardimci


def test_mufredat_kunyesi_hash_ile_kaydedilir(baglanti) -> None:
    kimlik = yardimci.mufredat_kaynagini_kaydet(baglanti)
    assert kimlik
    satir = baglanti.execute(
        "SELECT * FROM mufredat_kaynagi WHERE id = ?", (kimlik,)
    ).fetchone()
    assert len(satir["icerik_sha256"]) == 64
    assert satir["resmi_url"].startswith("https://mufredat.meb.gov.tr/")


def test_kaynakli_oneri_onaysiz_resmi_kaydi_degistirmez(baglanti, yil) -> None:
    sube_id = servis.sube_ekle(
        baglanti, yil.id, "9-A", 9, ogretim_yili_adi=yil.ad
    )
    once = baglanti.total_changes
    kimlik = yardimci.oneri_uret(
        baglanti,
        tur="ders",
        sube_id=sube_id,
        kazanim_kodu="BİY.9.1.1",
    )
    kayit = yardimci.oneriler(baglanti)[0]
    assert kayit["id"] == kimlik
    assert kayit["durum"] == "taslak"
    assert kayit["kaynaklar"]
    assert baglanti.execute("SELECT COUNT(*) FROM gunluk_plan").fetchone()[0] == 0
    assert baglanti.total_changes > once

    yardimci.oneri_karari(
        baglanti, kimlik, durum="onaylandi", duzeltme="Öğretmenin son metni"
    )
    assert yardimci.oneriler(baglanti)[0]["durum"] == "onaylandi"


def test_yardimci_ekrani_kurulumdan_sonra_acilir(istemci) -> None:
    istemci.post(
        "/kurulum/yil",
        data={
            "ad": "2026-2027",
            "d1_baslangic": "2026-09-14",
            "d1_bitis": "2027-01-16",
            "d2_baslangic": "2027-02-02",
            "d2_bitis": "2027-06-18",
        },
    )
    istemci.post("/kurulum/sube", data={"ad": "9-A", "sinif": 9})
    yanit = istemci.get("/yardimci")
    assert yanit.status_code == 200
    assert "Kaynaklı öğretmen yardımcısı" in yanit.text


@pytest.mark.parametrize("tur", ["ders", "soru_rubrik", "telafi"])
def test_yardimci_web_taslak_ve_ogretmen_karari(istemci, tur: str) -> None:
    istemci.post(
        "/kurulum/yil",
        data={
            "ad": "2026-2027",
            "d1_baslangic": "2026-09-14",
            "d1_bitis": "2027-01-16",
            "d2_baslangic": "2027-02-02",
            "d2_bitis": "2027-06-18",
        },
    )
    istemci.post("/kurulum/sube", data={"ad": "9-A", "sinif": 9})
    sayfa = istemci.get("/yardimci")
    sube = re.search(r'<option value="(\d+)">9-A', sayfa.text)
    assert sube
    yanit = istemci.post(
        "/yardimci/uret",
        data={
            "tur": tur,
            "sube_id": sube.group(1),
            "kazanim_kodu": "BİY.9.1.1",
            "ek_istek": "Kısa ve uygulanabilir olsun.",
        },
        follow_redirects=False,
    )
    assert yanit.status_code == 303
    olustu = istemci.get("/yardimci")
    kimlik = re.search(r'action="/yardimci/(\d+)/karar"', olustu.text)
    assert kimlik
    karar = istemci.post(
        f"/yardimci/{kimlik.group(1)}/karar",
        data={"duzeltme": "Öğretmen düzenlemesi"},
        follow_redirects=False,
    )
    assert karar.status_code == 303
