"""mlx-vlm öz-tutarlılık güveni — model yüklemeden mantık testi.

MlxVlmTaniyici.__init__ mlx_vlm import eder ve 7B ağırlık yükler; testler
__init__'i atlayıp (object.__new__) yalnız güven-türetme mantığını doğrular.
"""
import numpy as np
import pytest

pytest.importorskip("PIL")
pytest.importorskip("rapidfuzz")

from sinav_okur.htr.mlxvlm import MlxVlmTaniyici


def _taniyici(okumalar, oz_tutarlilik=True, sicaklik_arg="temperature",
              sabit_guven=0.8):
    """Model yüklemeden, _oku'yu sıralı sahte okumalarla değiştirir."""
    t = object.__new__(MlxVlmTaniyici)
    t.sabit_guven = sabit_guven
    t.oz_tutarlilik = oz_tutarlilik
    t.ikinci_sicaklik = 0.4
    t._sicaklik_arg = sicaklik_arg
    t.azami_kenar = 1600
    sira = iter(okumalar)
    t._oku = lambda gorsel, sicaklik, baglam=None: next(sira)
    return t


def _kirp():
    return np.full((40, 200, 3), 255, np.uint8)


def test_ozdes_okumalar_yuksek_guven():
    t = _taniyici(["mitokondri", "mitokondri"])
    sonuc = t.kutu_taniy(_kirp())
    assert sonuc.metin == "mitokondri"
    assert sonuc.guven >= 0.9


def test_ayrisan_okumalar_dusuk_guven():
    t = _taniyici(["mitokondri", "kloroplast"])
    sonuc = t.kutu_taniy(_kirp())
    assert sonuc.guven < 0.75  # puanlama incele eşiğinin altına düşer
    assert sonuc.alternatifler and sonuc.alternatifler[0]["metin"] == "kloroplast"


def test_iki_bos_okuma_sifir_guven():
    t = _taniyici(["", ""])
    sonuc = t.kutu_taniy(_kirp())
    assert sonuc.metin == ""
    assert sonuc.guven == 0.0


def test_oz_tutarlilik_kapali_sabit_guven():
    t = _taniyici(["mitokondri"], oz_tutarlilik=False)
    sonuc = t.kutu_taniy(_kirp())
    assert sonuc.guven == 0.8


def test_sicaklik_desteklenmiyorsa_sabit_guvene_duser():
    # _sicaklik_arg None → ikinci okuma yapılamaz, sabit güvene düşer
    t = _taniyici(["mitokondri"], sicaklik_arg=None)
    sonuc = t.kutu_taniy(_kirp())
    assert sonuc.guven == 0.8


def test_baglam_ipuclari_isteme_girer_ama_dayatilmaz():
    """İpuçları okumayı kolaylaştırmalı, cevabı fısıldamamalı."""
    t = _taniyici(["mitokondri", "mitokondri"])

    komut = t._komut(["mitokondri", "ribozom", "ATP sentezi"])

    assert "mitokondri" in komut
    assert "ASLA" in komut, "sızma uyarısı istemde olmalı"
    assert "bir cevap değildir" in komut


def test_kisa_ve_bos_ipuclari_elenir():
    t = _taniyici(["x", "x"])

    assert t._komut([]) == t._komut(None)
    komut = t._komut(["ab", "  ", "mitokondri"])
    assert "ab" not in komut.split("terimler")[-1] or "mitokondri" in komut


def test_buyuk_gorsel_kucultulur():
    from PIL import Image

    t = _taniyici(["x", "x"])
    t.azami_kenar = 100
    buyuk = np.full((400, 800, 3), 255, np.uint8)

    gorsel = t._gorsele_cevir(buyuk)

    assert max(gorsel.size) == 100
    assert isinstance(gorsel, Image.Image)


def test_serbest_birak_modeli_dusurur():
    t = _taniyici(["x", "x"])
    t.model = object()
    t.islemci = object()

    t.serbest_birak()

    assert t.model is None
    assert t.islemci is None


def test_asiri_dar_goruntude_uydurma_yerine_bos_doner():
    """Ölçüldü: 3889×81 (48:1) bir satır şeridinde model pi sayısı yazdı.

    Böyle bir çıktı okuma hatası değil uydurmadır; puanlamaya girmesi
    tehlikelidir. Satır şeritleri satır motorlarının (TrOCR/Vision) işidir.
    """
    t = _taniyici(["olmamalı", "olmamalı"])
    serit = np.full((80, 3900, 3), 255, np.uint8)

    sonuc = t.kutu_taniy(serit)

    assert sonuc.metin == ""
    assert sonuc.guven == 0.0
    assert "aşırı dar" in sonuc.belirsizlik_nedeni


def test_normal_oranli_goruntu_okunur():
    t = _taniyici(["mitokondri", "mitokondri"])

    sonuc = t.kutu_taniy(np.full((300, 900, 3), 255, np.uint8))

    assert sonuc.metin == "mitokondri"
