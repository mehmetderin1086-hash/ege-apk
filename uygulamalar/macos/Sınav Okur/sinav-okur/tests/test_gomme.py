"""puanlama/gomme: sbert'siz test edilebilir kısımlar (kosinüs + zarif düşüş)."""
import numpy as np

from sinav_okur.puanlama.gomme import gomlemci_yukle, kosinus


def test_kosinus_ayni_vektor_bir():
    a = np.array([[1.0, 2.0, 3.0]])
    m = kosinus(a, a)
    assert np.isclose(m[0, 0], 1.0)


def test_kosinus_dik_vektor_sifir():
    a = np.array([[1.0, 0.0]])
    b = np.array([[0.0, 1.0]])
    assert np.isclose(kosinus(a, b)[0, 0], 0.0)


def test_kosinus_sifir_vektor_coker_mez():
    a = np.array([[0.0, 0.0]])
    b = np.array([[1.0, 1.0]])
    # 1e-9 tabanı sıfıra bölmeyi engeller
    assert np.isfinite(kosinus(a, b)[0, 0])


def test_kosinus_matris_boyutu():
    a = np.random.RandomState(0).rand(3, 8)
    b = np.random.RandomState(1).rand(5, 8)
    assert kosinus(a, b).shape == (3, 5)


def test_gomlemci_yukle_sbert_yoksa_none(monkeypatch):
    # SbertGomlemci import'u ImportError verirse yükleyici None döner
    import sinav_okur.puanlama.gomme as g

    def _patla(*a, **k):
        raise ImportError("sentence-transformers yok")

    monkeypatch.setattr(g, "SbertGomlemci", _patla)
    assert g.gomlemci_yukle() is None
