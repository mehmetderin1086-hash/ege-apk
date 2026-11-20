"""Kes ve Çöz sayfasının bağımsız arayüz sözleşmesi."""

from __future__ import annotations

from pathlib import Path

import pytest

KOK = Path(__file__).parents[1] / "biyo_cozucu" / "webapp"
SABLON = (KOK / "sablonlar" / "kes_ve_coz.html").read_text(encoding="utf-8")
TEMEL = (KOK / "sablonlar" / "temel.html").read_text(encoding="utf-8")
BETIK = (KOK / "statik" / "kes_ve_coz.js").read_text(encoding="utf-8")
STIL = (KOK / "statik" / "kes_ve_coz.css").read_text(encoding="utf-8")


def test_kes_ve_coz_sablonu_derlenir():
    pytest.importorskip("jinja2")
    from biyo_cozucu.webapp import sablonlar_kur

    sablonlar_kur().env.get_template("kes_ve_coz.html")


def test_yukleme_tek_belge_ve_desteklenen_turlerle_sinirlidir():
    assert 'action="/kes-ve-coz/is"' in SABLON
    assert 'name="dosyalar"' in SABLON
    assert "multiple" not in SABLON
    for uzanti in (".pdf", ".docx", ".png", ".jpg", ".tiff", ".bmp", ".webp", ".gif"):
        assert uzanti in SABLON
    assert 'data-azami-bayt="419430400"' in SABLON
    assert "En fazla 400 MB" in SABLON


def test_islem_durumu_erisilebilir_ve_iptal_edilebilir():
    assert 'role="status"' in SABLON
    assert 'aria-live="polite"' in SABLON
    assert "<progress" in SABLON
    assert "data-kvc-durdur" in SABLON
    assert "data-kvc-toplam" in SABLON
    assert "data-kvc-kesilen" in SABLON
    assert "data-kvc-cozulen" in SABLON
    assert "data-kvc-inceleme" in SABLON
    assert "data-kvc-karsilastirilan" in SABLON
    assert "data-kvc-anahtarli" in SABLON
    assert "data-kvc-dogru" in SABLON
    assert "data-kvc-yanlis" in SABLON


def test_istemci_is_baslatma_durum_ve_durdurma_uclarini_kullanir():
    assert 'fetch(form.action' in BETIK
    assert '"/kes-ve-coz/api/is/" + encodeURIComponent(isKimligi)' in BETIK
    assert 'encodeURIComponent(isKimligi) + "/durdur"' in BETIK
    assert "setTimeout(durumuSorgula" in BETIK
    assert "TERMINAL_TAMAM" in BETIK
    assert "TERMINAL_KISMI" in BETIK
    assert "TERMINAL_HATA" in BETIK
    assert "TERMINAL_IPTAL" in BETIK
    assert 'bitir("kismi", sonuc.veri)' in BETIK
    assert "Durdurma isteği alındı" in BETIK
    assert "sonrakiSorguyuKur(400)" in BETIK


def test_dosya_form_kilitlenmeden_once_istege_alinir():
    """Disabled file alaninin FormData'dan dusmesine izin verme."""
    form_verisi = BETIK.index("var formVerisi = new FormData(form);")
    form_kilidi = BETIK.index("formuEtkinlestir(true);", form_verisi)
    assert form_verisi < form_kilidi
    assert "body: formVerisi" in BETIK


def test_istemci_eksik_alanlari_varsayilanlarla_karsilar_ve_guvenli_cizer():
    assert "function ilk()" in BETIK
    assert "function sorulariAl(veri)" in BETIK
    assert "Soru metni hazırlanıyor" in BETIK
    assert "Çözüm bekleniyor" in BETIK
    assert "textContent" in BETIK
    assert "innerHTML" not in BETIK


def test_kismi_sonuc_inceleme_ve_kirpim_gorseli_sozlesmesi():
    assert '"kismi", "kısmi", "partial"' in BETIK
    assert "bazı sorularda hata var" in BETIK
    assert "review_required" in BETIK
    assert "function guvenliGorselYolu(deger)" in BETIK
    assert 'deger.indexOf("/kes-ve-coz/") !== 0' in BETIK
    assert 'gorsel.alt = "Kesilen soru " + goruntulenenSira' in BETIK
    assert 'gorsel.loading = "lazy"' in BETIK
    assert 'gorsel.alt = "Kesilen soru " + goruntulenenSira' in BETIK
    assert 'oge("figcaption", "", "Kesilen soru " + goruntulenenSira)' in BETIK
    assert ".kvc-kesim-gorseli img" in STIL
    assert ".kvc-hata.kvc-kismi-uyari" in STIL


def test_resmi_anahtar_karsilastirmasi_acikca_gosterilir():
    assert "referansla_eslesiyor === true" in BETIK
    assert "referansla_eslesiyor === false" in BETIK
    assert "soru.referans_var === true" in BETIK
    assert "referansDuyurusu()" in BETIK
    assert "Anahtar kontrolü" in SABLON
    assert "Anahtarla eşleşti" in BETIK
    assert "Anahtarla uyuşmadı" in BETIK
    assert "data-kvc-referans-sayaci" in SABLON
    assert ".kvc-rozet.dogru" in STIL
    assert 'soru.cozum.uretim_yontemi === "tam_referans"' in BETIK
    assert "Yerel arşivde birebir" in BETIK
    assert ".kvc-rozet.kaynakli" in STIL


def test_anahtarla_celisen_model_ciktisi_dogru_cevap_gibi_sunulmaz():
    assert '"Model önerisi — doğrulanmadı"' in BETIK
    assert '"Belgedeki cevap anahtarı"' in BETIK
    assert '"Model önerisi: "' in BETIK
    assert ".kvc-model-onerisi" in STIL
    assert "Model açıklaması cevap anahtarıyla çelişiyor" in BETIK
    assert "doğrulanması gereken cevaplar var" in BETIK
    assert '"İncele"' in BETIK
    assert '"Kesimi incele"' not in BETIK


def test_buyuk_sonuc_kumesinde_uyusmayanlar_ayri_filtrelenir_ve_canli_liste_sismez():
    assert 'data-kvc-filtre="uyusmayan"' in SABLON
    assert "Anahtarla uyuşmayanlar" in SABLON
    assert 'kart.dataset.kvcReferansUyusmuyor === "1"' in BETIK
    assert 'aria-label="Kesme ve çözme ilerlemesi"' in SABLON
    assert 'data-kvc-soru-listesi aria-live=' not in SABLON
    assert 'aria-label="İşlenen soru sonuçları"' in SABLON


def test_sayfa_mobil_ve_azaltilmis_hareket_duzenine_sahiptir():
    assert "@media (max-width: 48rem)" in STIL
    assert "@media (max-width: 32rem)" in STIL
    assert "@media (prefers-reduced-motion: reduce)" in STIL
    assert ".kvc-asamalar" in STIL
    assert ".kvc-soru-karti.inceleme" in STIL


def test_ortak_kabuk_kes_ve_cozu_ana_akis_olarak_gosterir():
    # Stüdyo çatısında marka bağlantısı Merkez'e gider; Kes ve Çöz gezinmede kalır.
    assert 'href="/merkez"' in TEMEL
    assert "Biyoloji Stüdyosu merkezi" in TEMEL
    assert "{% block sayfa_stilleri %}" in TEMEL
    assert "{% block sayfa_betikleri %}" in TEMEL
    assert TEMEL.count("nav_ogesi('/kes-ve-coz'") == 2
    assert TEMEL.count("nav_ogesi('/merkez'") == 2
