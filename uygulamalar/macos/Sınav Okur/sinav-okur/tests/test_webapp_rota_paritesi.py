"""Webapp bölünürken hiçbir rotanın sessizce kaybolmadığını garanti eden emniyet ağı.

Router taşıması sırasında bir rota düşer veya yolu değişirse bu test kırmızı yanar.
Bilerek rota ekleme/çıkarma yapılıyorsa BEKLENEN_ROTALAR güncellenmelidir.
"""
from __future__ import annotations

import pytest

fastapi = pytest.importorskip("fastapi")

from sinav_okur.webapp import uygulama_kur

CERCEVE_YOLLARI = {"/docs", "/docs/oauth2-redirect", "/redoc", "/openapi.json"}

BEKLENEN_ROTALAR = {
    ("GET", "/"),
    ("GET", "/api/v1/capabilities"),
    ("GET", "/api/v1/exams/{kimlik}/results"),
    ("GET", "/api/v1/health"),
    ("GET", "/disaaktar.zip"),
    ("GET", "/gelisim"),
    ("GET", "/gizlilik"),
    ("GET", "/healthz"),
    ("GET", "/kagit/{kagit_id}"),
    ("GET", "/kagit/{kagit_id}/geri-bildirim"),
    ("GET", "/kapi"),
    ("GET", "/ogrenci/{ogrenci_kimlik}"),
    ("GET", "/referans"),
    ("GET", "/serbest-yukle"),
    ("GET", "/serbest/{token}"),
    ("GET", "/serbest/{token}/sayfa/{sayfa_no}.png"),
    ("GET", "/sinav/{kimlik}"),
    ("GET", "/sinav/{kimlik}/anahtar"),
    ("GET", "/sinav/{kimlik}/anahtar/yukle"),
    ("GET", "/sinav/{kimlik}/analiz"),
    ("GET", "/sinav/{kimlik}/geri-bildirimler"),
    ("GET", "/sinav/{kimlik}/inceleme"),
    ("GET", "/sinav/{kimlik}/itirazlar"),
    ("GET", "/sinav/{kimlik}/kaynak"),
    ("GET", "/sinav/{kimlik}/puanlama-motoru"),
    ("GET", "/sinav/{kimlik}/rapor.xlsx"),
    ("GET", "/sinav/{kimlik}/soru/{soru_no}"),
    ("GET", "/sinav/{kimlik}/soru/{soru_no}/tezgah"),
    ("GET", "/sinav/{kimlik}/tutarlilik"),
    ("GET", "/toplu-sonuc/{token}"),
    ("GET", "/toplu-sonuc/{token}/durum.json"),
    ("GET", "/yardim"),
    ("GET", "/yukle"),
    ("POST", "/api/v1/exams/import"),
    ("POST", "/gelisim/esle"),
    ("POST", "/gizlilik/anonimlestir"),
    ("POST", "/itiraz/{itiraz_id}/karar"),
    ("POST", "/kabul-yazimi/{kabul_id}"),
    ("POST", "/kagit/{kagit_id}/goruntu-analizi"),
    ("POST", "/kagit/{kagit_id}/itiraz"),
    ("POST", "/kagit/{kagit_id}/kimlik"),
    ("POST", "/kagit/{kagit_id}/kutulari-onayla"),
    ("POST", "/kagit/{kagit_id}/onayla"),
    ("POST", "/kagit/{kagit_id}/yeniden-puanla"),
    ("POST", "/kalibrasyon/guncelle"),
    ("POST", "/kutu/{kutu_id}"),
    ("POST", "/referans"),
    ("POST", "/serbest-yukle"),
    ("POST", "/serbest/{token}"),
    ("POST", "/serbest/{token}/yapay-zeka-cevaplari"),
    ("POST", "/serbest/{token}/yerel-rag-cevaplari"),
    ("POST", "/sinav/{kimlik}/akran-uzlasmasi"),
    ("POST", "/sinav/{kimlik}/anahtar"),
    ("POST", "/sinav/{kimlik}/anahtar-onayla"),
    ("POST", "/sinav/{kimlik}/anahtar/onizle"),
    ("POST", "/sinav/{kimlik}/anahtar/yukle/belge"),
    ("POST", "/sinav/{kimlik}/anahtar/yukle/dosya"),
    ("POST", "/sinav/{kimlik}/anahtar/yukle/uygula"),
    ("POST", "/sinav/{kimlik}/esneklik"),
    ("POST", "/sinav/{kimlik}/kabul-yazimlari-tara"),
    ("POST", "/sinav/{kimlik}/ogrenci-listesi"),
    ("POST", "/sinav/{kimlik}/rag-anahtar-yenile"),
    ("POST", "/sinav/{kimlik}/soru/{soru_no}/toplu-puan"),
    ("POST", "/sinav/{kimlik}/toplu-islem"),
    ("POST", "/yukle"),
}


def _rotalari_ac(rotalar):
    """app.routes içindeki sarmalanmış router'ları (fastapi._IncludedRouter) da açar."""
    for rota in rotalar:
        ic_router = getattr(rota, "original_router", None)
        if ic_router is not None:
            yield from _rotalari_ac(ic_router.routes)
        else:
            yield rota


def test_rota_paritesi(tmp_path) -> None:
    app = uygulama_kur(
        str(tmp_path / "s.db"), str(tmp_path / "kirp"), str(tmp_path / "veri")
    )
    mevcut = {
        (m, r.path)
        for r in _rotalari_ac(app.routes)
        if getattr(r, "methods", None) and r.path not in CERCEVE_YOLLARI
        for m in r.methods
        if m != "HEAD"
    }
    eksik = BEKLENEN_ROTALAR - mevcut
    fazla = mevcut - BEKLENEN_ROTALAR
    assert not eksik, f"Kaybolan rotalar: {sorted(eksik)}"
    assert not fazla, f"Listeye eklenmemiş yeni rotalar: {sorted(fazla)}"
