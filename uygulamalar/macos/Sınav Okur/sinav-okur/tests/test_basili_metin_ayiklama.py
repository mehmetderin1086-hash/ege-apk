"""Basılı soru metnini öğrenci cevabından ayıklama.

Ölçüldü (gerçek kâğıt, work/gercek-baglamli/soru_1_parca_1.png): öğrenci
cevabını soru kâğıdının üstüne yazdığında OCR basılı metni de okuyor ve
CER 8.21 çıkıyor. Ayıklamayla 0.97'ye iniyor — ölçülen tek büyük hata
kaynağı buydu.
"""

from __future__ import annotations

from sinav_okur.serbest import (
    BASILI_KAPSAMA_ESIGI,
    _basili_metni_cikar,
    basili_metin_karisimi,
)

SORU = (
    "İlk belgede, bir hekim, gözle göremediği küçük varlıkların insanlara "
    "hastalık bulaştırabileceğini savunuyor. İkinci belgede, el yapımı bir "
    "mercek ile gördüğü küçük yapılara odacık anlamına gelen bir isim veren "
    "meraklı bir bilim insanı var."
)


def test_ocr_hatali_basili_metin_de_ayiklanir():
    """OCR basılı metni de hatalı okur; tam eşitlik aramak kalıntı bırakıyordu."""
    # "bulaştırabileceğiini" ve "göremedigi" OCR hatası içeriyor.
    ocr = (
        "İlk belgede bir hekim gözle göremedigi küçük varlıkların insanlara "
        "hastalık bulaştırabileceğiini savunuyor Hastalığın bulaşma keşfi"
    )

    kalan = _basili_metni_cikar(ocr, SORU)

    assert "Hastalığın" in kalan or "bulaşma" in kalan
    assert "hekim" not in kalan.casefold()
    assert "savunuyor" not in kalan.casefold()


def test_cevaptaki_soru_kelimeleri_korunur():
    """Öğrenci sorunun kelimelerini kullanabilir; kısa örtüşme silinmemeli."""
    ocr = "Mikroskobun keşfi"

    assert _basili_metni_cikar(ocr, SORU) == "Mikroskobun keşfi"


def test_karisim_orani_temiz_kutuda_dusuk():
    """Yalnız cevap içeren kutuda ayıklama tetiklenmemeli."""
    oran = basili_metin_karisimi("Mikroskobun keşfi ve hücre teorisi", SORU)

    assert oran < BASILI_KAPSAMA_ESIGI


def test_karisim_orani_basili_metinde_yuksek():
    """Soru metni okunmuşsa oran eşiği aşmalı."""
    oran = basili_metin_karisimi(
        "İlk belgede bir hekim gözle göremediği küçük varlıkların insanlara "
        "hastalık bulaştırabileceğini savunuyor",
        SORU,
    )

    assert oran >= BASILI_KAPSAMA_ESIGI


def test_bos_metin_sifir_karisim():
    assert basili_metin_karisimi("", SORU) == 0.0


def test_ayiklama_soru_basligini_silmez_ama_cevabi_birakir():
    ocr = "Soru 1: (20 Puan) Mikroskobun keşfi"

    kalan = _basili_metni_cikar(ocr, SORU)

    assert "Mikroskobun keşfi" in kalan


# --- Kâğıt yalıtımı (varsayılan kapalı) -------------------------------------


def test_kagit_yalitimi_varsayilan_kapali(monkeypatch):
    """Ölçüldü: CER'i düşürüyor ama bir kutuda puanı 4.67 → 0 çöktürdü.

    CER iyileşmesi tek başına yeterli kanıt değil; öğrencinin notunu bozan
    bir değişiklik iyileştirme sayılmaz. Daha çok etiketli veriyle yeniden
    ölçülecek.
    """
    import numpy as np

    from sinav_okur.kalite import kagit_bolgesini_yalit

    monkeypatch.delenv("SINAV_OKUR_KAGIT_YALITIMI", raising=False)
    # Yarısı koyu (arka plan), yarısı beyaz (kâğıt) bir görüntü.
    goruntu = np.full((100, 100, 3), 255, np.uint8)
    goruntu[:40] = 30

    sonuc, oran = kagit_bolgesini_yalit(goruntu)

    assert np.array_equal(sonuc, goruntu), "kapalıyken görüntüye dokunulmamalı"
    assert oran == 1.0


def test_kagit_yalitimi_acikken_arka_plani_beyazlatir(monkeypatch):
    import numpy as np

    from sinav_okur.kalite import kagit_bolgesini_yalit

    monkeypatch.setenv("SINAV_OKUR_KAGIT_YALITIMI", "acik")
    goruntu = np.full((100, 100, 3), 255, np.uint8)
    goruntu[:40] = 30

    sonuc, oran = kagit_bolgesini_yalit(goruntu)

    assert oran < 1.0
    assert int(sonuc[10, 50, 0]) > int(goruntu[10, 50, 0]), "arka plan beyazlamalı"


def test_kagit_baskinsa_dokunulmaz(monkeypatch):
    """Zaten temiz kırpıntıda yalıtım riski gereksizdir."""
    import numpy as np

    from sinav_okur.kalite import kagit_bolgesini_yalit

    monkeypatch.setenv("SINAV_OKUR_KAGIT_YALITIMI", "acik")
    goruntu = np.full((100, 100, 3), 250, np.uint8)
    goruntu[45:55, 45:55] = 20  # küçük bir metin lekesi

    sonuc, _oran = kagit_bolgesini_yalit(goruntu)

    assert np.array_equal(sonuc, goruntu)
