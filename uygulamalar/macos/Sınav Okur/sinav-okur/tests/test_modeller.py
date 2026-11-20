import pytest

from sinav_okur.modeller import Sinav, SoruTipi


def test_yaml_yukle_ornek(tmp_path):
    from pathlib import Path
    ornek = Path(__file__).parent.parent / "ornekler" / "biyoloji_sinav.yaml"
    sinav = Sinav.yaml_yukle(ornek)
    assert sinav.kimlik == "BIYO9-2026-01"
    assert len(sinav.sorular) == 5
    assert sinav.toplam_puan == 90
    assert sinav.soru(1).tip == SoruTipi.BOSLUK_DOLDURMA
    assert sinav.soru(4).tip == SoruTipi.ACIK_UCLU
    assert sinav.soru(3).anahtar.rubrik[0].puan == 10


def test_yaml_gidis_donus(tmp_path):
    from pathlib import Path
    ornek = Path(__file__).parent.parent / "ornekler" / "biyoloji_sinav.yaml"
    sinav = Sinav.yaml_yukle(ornek)
    yol = tmp_path / "cikti.yaml"
    sinav.yaml_kaydet(yol)
    tekrar = Sinav.yaml_yukle(yol)
    assert tekrar.toplam_puan == sinav.toplam_puan
    assert tekrar.soru(4).anahtar.ornek_cevap.strip().startswith("Difüzyon")


def test_rag_anahtari_kaynagi_yaml_gidis_donuste_korunur(tmp_path):
    from sinav_okur.modeller import CevapAnahtari, RubrikKalemi, Soru

    sinav = Sinav(
        kimlik="RAG-1",
        baslik="Kaynaklı",
        sorular=[
            Soru(
                no=1,
                tip=SoruTipi.ACIK_UCLU,
                metin="Hücre nedir?",
                puan=10,
                anahtar=CevapAnahtari(
                    rubrik=[
                        RubrikKalemi(
                            "Canlıların temel birimi hücredir.",
                            10,
                            ["hücre teorisi"],
                        )
                    ],
                    ornek_cevap="Hücre temel birimdir.",
                    kaynaklar=["biyoloji.pdf · pasaj 2"],
                    uretim_yontemi="Yerel RAG",
                    otomatik_uretildi=True,
                    otomatik_puanlama=False,
                    uyari="Soru eksik.",
                ),
            )
        ],
    )
    yol = tmp_path / "rag.yaml"
    sinav.yaml_kaydet(yol)

    tekrar = Sinav.yaml_yukle(yol)

    assert tekrar.soru(1).anahtar.kaynaklar == ["biyoloji.pdf · pasaj 2"]
    assert tekrar.soru(1).anahtar.otomatik_uretildi is True
    assert tekrar.soru(1).anahtar.otomatik_puanlama is False
    assert tekrar.soru(1).anahtar.uyari == "Soru eksik."
    assert tekrar.soru(1).anahtar.rubrik[0].esanlamlilar == ["hücre teorisi"]


def test_bosluk_dogrulama():
    with pytest.raises(ValueError):
        Sinav(kimlik="x", baslik="y", sorular=[
            {"no": 1, "tip": "bosluk_doldurma", "metin": "z", "puan": 5,
             "anahtar": {"dogru_cevaplar": []}}])


def test_tekrarli_soru_no():
    with pytest.raises(ValueError):
        Sinav(kimlik="x", baslik="y", sorular=[
            {"no": 1, "tip": "bosluk_doldurma", "metin": "a", "puan": 5,
             "anahtar": {"dogru_cevaplar": ["m"]}},
            {"no": 1, "tip": "bosluk_doldurma", "metin": "b", "puan": 5,
             "anahtar": {"dogru_cevaplar": ["n"]}}])
