"""Gerçek tarayıcıda uçtan uca testler.

Kapsam BİLİNÇLİ olarak dar: `test_webapp.py`'deki 67 TestClient testi rota
davranışını zaten kapsıyor. Buraya yalnız **JavaScript gerektiren** ve
TestClient'ın hiç göremeyeceği akışlar giriyor — SSE'nin DOM'a yazması,
JS kapalıyken klasik POST'a düşen ilerlemeli geri düşüş ve yıkıcı işlem
onayı. Aynı şeyi iki kez test etmek, testi değil bakım yükünü çoğaltır.

Tarayıcı indirmesi ve süre nedeniyle bu dosyanın tamamı `yavas` işaretli;
varsayılan koşuya girmez (`pytest -m ""` ile ya da `make tam-test` ile koşar).
"""

from __future__ import annotations

import json
import socket
import threading

import pytest

pytest.importorskip("playwright")
pytest.importorskip("fastapi")

from playwright.sync_api import sync_playwright

from biyo_cozucu.cozucu import Ayarlar
from biyo_cozucu.motor.temel import SahteMotor
from biyo_cozucu.webapp import uygulama_kur

pytestmark = pytest.mark.yavas


def _bos_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


@pytest.fixture
def sunucu(tmp_path, ornekler, sahte_gomlemci, monkeypatch):
    """Gerçek uvicorn sunucusu — TestClient JavaScript çalıştırmaz."""
    uvicorn = pytest.importorskip("uvicorn")
    from biyo_cozucu import gomme as gomme_modulu
    from biyo_cozucu import motor as motor_modulu

    monkeypatch.setattr(gomme_modulu, "gomlemci_yukle", lambda *a, **k: sahte_gomlemci)
    # parca_boyu: yanıtı dilimleyerek gerçek akışı taklit eder; tek parça
    # gelseydi "parça parça DOM'a yazılıyor mu" sorusu sınanmamış olurdu.
    monkeypatch.setattr(
        motor_modulu,
        "motor_yukle",
        lambda *a, **k: SahteMotor(
            json.dumps(
                {"adimlar": ["Mitokondri solunumun merkezidir", "Krebs orada olur"],
                 "cevap": "B", "guven": 0.9, "uyari": ""},
                ensure_ascii=False,
            ),
            parca_boyu=12,
        ),
    )

    uygulama = uygulama_kur(tmp_path, motor_turu="sahte", ayarlar=Ayarlar())
    durum = uygulama.state.durum
    for ornek in ornekler:
        durum.depo.ornek_ekle(ornek)
    durum.indeksi_yenile()

    port = _bos_port()
    yapilandirma = uvicorn.Config(
        uygulama, host="127.0.0.1", port=port, log_level="error"
    )
    hizmet = uvicorn.Server(yapilandirma)
    is_parcacigi = threading.Thread(target=hizmet.run, daemon=True)
    is_parcacigi.start()
    while not hizmet.started:
        if not is_parcacigi.is_alive():
            pytest.fail("sunucu başlatılamadı")
    try:
        yield f"http://127.0.0.1:{port}", durum
    finally:
        hizmet.should_exit = True
        is_parcacigi.join(timeout=5)


@pytest.fixture
def tarayici():
    with sync_playwright() as p:
        tarayici = p.chromium.launch()
        try:
            yield tarayici
        finally:
            tarayici.close()


def test_canli_akis_cozumu_sayfayi_yenilemeden_yazar(sunucu, tarayici):
    """SSE'nin asıl işi: çözümü sayfa yeniden yüklenmeden DOM'a yazmak.

    Akış panelinin GÖRÜNÜR olduğu an geçicidir — sahte motor hızlı bittiğinde
    panel Playwright yoklamadan önce kapanabiliyor ve test kararsızlaşıyordu.
    Bu yüzden kalıcı iki olguya bakılıyor: (1) sayfa hiç yeniden yüklenmedi
    (JS'siz yol tam da bunu yapardı), (2) çözüm kartı DOM'a girdi.
    """
    adres, _durum = sunucu
    sayfa = tarayici.new_page()
    sayfa.goto(f"{adres}/coz")

    # Gezinme olursa bu işaret kaybolur; klasik POST'un ayırt edici izi budur.
    sayfa.evaluate("window.__akisIsareti = 'duruyor'")

    sayfa.fill("textarea[name=soru]", "Krebs döngüsü nerede gerçekleşir?")
    sayfa.click("form[data-akis-formu] button[type=submit]")

    sayfa.wait_for_function(
        "document.getElementById('cozum-alani').textContent.includes('Mitokondri')",
        timeout=20000,
    )
    assert sayfa.evaluate("window.__akisIsareti") == "duruyor", (
        "sayfa yeniden yüklendi — akış yolu değil klasik POST çalışmış"
    )
    sayfa.close()


def test_javascript_kapaliyken_klasik_post_calisir(sunucu, tarayici):
    """İlerlemeli geri düşüş: JS yoksa form normal POST'a dönmeli.

    Arayüzün bağımlılıksız tasarımının tek gerçek kanıtı bu; TestClient
    zaten JS çalıştırmadığı için bu ayrımı gösteremez.
    """
    adres, _durum = sunucu
    baglam = tarayici.new_context(java_script_enabled=False)
    sayfa = baglam.new_page()
    sayfa.goto(f"{adres}/coz")

    sayfa.fill("textarea[name=soru]", "Krebs döngüsü nerede gerçekleşir?")
    sayfa.click("form button[type=submit]")
    sayfa.wait_for_load_state()

    assert "Mitokondri" in sayfa.content(), "JS'siz yolda da çözüm basılmalı"
    baglam.close()


def test_yikici_islem_onay_ister_ve_iptal_edilebilir(sunucu, tarayici):
    """Silme onayı yalnız JS'te var; iptal edilince kayıt durmalı."""
    adres, durum = sunucu
    onceki = durum.depo.ornek_sayisi()
    sayfa = tarayici.new_page()
    sayfa.goto(f"{adres}/ornek/2")

    sayfa.on("dialog", lambda d: d.dismiss())
    sayfa.click("[data-onay]")
    sayfa.wait_for_timeout(300)

    assert durum.depo.ornek_sayisi() == onceki, "iptal edilen silme uygulanmamalı"
    sayfa.close()


def test_tema_secimi_yeniden_yuklemede_korunur(sunucu, tarayici):
    """Tema yalnız JS ile değişiyor ve localStorage'da yaşıyor.

    Düğme tek: "sistem → açık → koyu" sırasını dolaşıyor. Sistemden sonraki
    ilk tıklama "açık"; iki tıklama "koyu" yapar.
    """
    adres, _durum = sunucu
    sayfa = tarayici.new_page()
    sayfa.goto(f"{adres}/pano")

    sayfa.click("[data-tema-anahtari]")
    sayfa.click("[data-tema-anahtari]")
    assert sayfa.evaluate("document.documentElement.dataset.tema") == "koyu"

    sayfa.reload()
    sayfa.wait_for_selector("[data-tema-anahtari]")
    assert sayfa.evaluate("document.documentElement.dataset.tema") == "koyu", (
        "seçim yeniden yüklemede kaybolmamalı"
    )
    sayfa.close()


def test_bos_form_sunucuya_gitmeden_anlasilir_hata_gosterir(sunucu, tarayici):
    adres, durum = sunucu
    onceki = len(durum.depo.cozumler(limit=100))
    sayfa = tarayici.new_page()
    sayfa.goto(f"{adres}/coz")

    sayfa.click("form[data-akis-formu] button[type=submit]")

    hata = sayfa.locator("#coz-form-hatasi")
    assert hata.is_visible()
    assert "bir soru yaz" in hata.text_content()
    assert len(durum.depo.cozumler(limit=100)) == onceki
    assert sayfa.url.endswith("/coz")
    sayfa.close()


def test_hazir_kalitim_ornegi_soru_ve_siklari_doldurur(sunucu, tarayici):
    adres, _durum = sunucu
    sayfa = tarayici.new_page()
    sayfa.goto(f"{adres}/coz")

    sayfa.click("form[data-akis-formu] button[type=submit]")
    assert sayfa.locator("#coz-form-hatasi").is_visible()
    sayfa.click('[data-ornek-soru*="Aa"]')

    assert "Aa × Aa" in sayfa.input_value("#soru")
    assert "B) %25" in sayfa.input_value("#secenekler")
    assert sayfa.locator(".gelismis-ayarlar").get_attribute("open") is not None
    assert not sayfa.locator("#coz-form-hatasi").is_visible()
    assert sayfa.locator("#coz-durum-bildirimi").text_content() == ""
    sayfa.close()


def test_javascript_kapaliyken_dosya_secici_ve_cozum_calisir(sunucu, tarayici):
    adres, _durum = sunucu
    baglam = tarayici.new_context(java_script_enabled=False)
    sayfa = baglam.new_page()
    sayfa.goto(f"{adres}/coz")

    sayfa.set_input_files(
        "#soru-dosyalari",
        {
            "name": "soru.txt",
            "mimeType": "text/plain",
            "buffer": b"Krebs dongusu nerede gerceklesir?",
        },
    )
    sayfa.click("form button[type=submit]")
    sayfa.wait_for_load_state()

    assert "Mitokondri" in sayfa.content()
    baglam.close()


def test_coklu_dosya_secimi_listelenir_ve_tumu_temizlenir(sunucu, tarayici):
    adres, _durum = sunucu
    sayfa = tarayici.new_page()
    sayfa.goto(f"{adres}/coz")

    sayfa.set_input_files(
        "#soru-dosyalari",
        [
            {"name": "bir.txt", "mimeType": "text/plain", "buffer": b"Birinci soru?"},
            {"name": "iki.md", "mimeType": "text/markdown", "buffer": b"Ikinci soru?"},
        ],
    )

    assert sayfa.locator("#dosya-sayisi").text_content() == "2 dosya seçildi"
    assert sayfa.locator("#dosya-listesi .dosya-satiri").count() == 2
    sayfa.click("#tum-dosyalari-kaldir")
    assert sayfa.locator("#dosya-listesi .dosya-satiri").count() == 0
    assert sayfa.locator("#dosya-ozeti").is_hidden()
    assert sayfa.locator("#soru-dosyalari").evaluate("el => el.files.length") == 0
    sayfa.close()


def test_mobilde_gezinti_kompakt_menuye_donusur(sunucu, tarayici):
    adres, _durum = sunucu
    sayfa = tarayici.new_page(viewport={"width": 390, "height": 844})
    sayfa.goto(f"{adres}/coz")

    assert not sayfa.locator(".yan-panel").is_visible()
    assert sayfa.locator(".mobil-gezinme").is_visible()
    sayfa.click(".mobil-gezinme summary")
    assert sayfa.locator(".mobil-nav").is_visible()
    assert sayfa.locator(".ust-cubuk").bounding_box()["height"] < 90
    sayfa.close()
