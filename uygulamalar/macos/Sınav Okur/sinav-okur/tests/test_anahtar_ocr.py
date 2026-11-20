"""Fotoğraf/PDF anahtar ayrıştırma: dayanak denetimi ve taslak sözleşmesi."""

from __future__ import annotations

import json

import pytest

from sinav_okur.anahtar_ocr import (
    _dayanak_denetle,
    anahtar_belgesinden_metin,
    metinden_anahtar_ayristir,
)
from sinav_okur.modeller import (
    CevapAnahtari,
    RubrikKalemi,
    Sinav,
    Soru,
    SoruTipi,
)

OCR_METNI = (
    "BIYOLOJI CEVAP ANAHTARI\n"
    "1) Mitokondri ATP uretir. Oksijenli solunumun son asamasi burada gecer.\n"
    "2) C\n"
)


@pytest.fixture
def sinav() -> Sinav:
    return Sinav(
        kimlik="OCR-ANAHTAR",
        baslik="Biyoloji",
        sorular=[
            Soru(
                no=1,
                tip=SoruTipi.ACIK_UCLU,
                metin="Mitokondrinin görevi nedir?",
                puan=10,
                anahtar=CevapAnahtari(rubrik=[RubrikKalemi("eski", 10)]),
            ),
            Soru(
                no=2,
                tip=SoruTipi.COKTAN_SECMELI,
                metin="Hücre zarı hangisidir?",
                puan=5,
                anahtar=CevapAnahtari(dogru_cevaplar=["A"]),
            ),
        ],
    )


def _sahte_uret(cevap: dict):
    def uret(mesajlar, **_ayar):
        assert mesajlar[0]["role"] == "system"
        return json.dumps(cevap, ensure_ascii=False)

    return uret


def test_dayanak_denetimi_aksan_ve_gurultuye_dayanikli():
    assert _dayanak_denetle("Mitokondri ATP üretir", OCR_METNI)
    # OCR'da "uretir" yazıyor; aksanlı yazım da eşleşmeli.
    assert _dayanak_denetle("oksijenli solunumun son aşaması", OCR_METNI)
    assert not _dayanak_denetle(
        "Ribozomlar protein sentezi yapar ve zarsız organeldir", OCR_METNI
    )
    assert not _dayanak_denetle("   ", OCR_METNI)


def test_belgeden_cikan_anahtar_hep_taslaktir(sinav):
    uret = _sahte_uret(
        {
            "sorular": [
                {
                    "no": 1,
                    "cevap_satirlari": [],
                    "rubrik_satirlari": [
                        "Mitokondri ATP üretir",
                        "Oksijenli solunumun son aşaması burada geçer",
                    ],
                },
                {"no": 2, "cevap_satirlari": ["C"], "rubrik_satirlari": []},
            ]
        }
    )

    sonuc = metinden_anahtar_ayristir(OCR_METNI, sinav, uret)

    assert not sonuc.hatalar
    tip, anahtar = sonuc.sorular[1]
    assert tip == SoruTipi.ACIK_UCLU
    assert anahtar.onay_durumu == "taslak"
    assert anahtar.otomatik_uretildi is True
    assert anahtar.otomatik_puanlama is True
    assert anahtar.uretim_yontemi == "Fotoğraf/PDF · OCR + yerel model"
    assert [k.metin for k in anahtar.rubrik] == [
        "Mitokondri ATP üretir",
        "Oksijenli solunumun son aşaması burada geçer",
    ]
    assert sonuc.sorular[2][1].dogru_cevaplar == ["C"]


def test_uydurulan_satir_otomatik_puanlamayi_kapatir(sinav):
    uret = _sahte_uret(
        {
            "sorular": [
                {
                    "no": 1,
                    "cevap_satirlari": [],
                    "rubrik_satirlari": [
                        "Mitokondri ATP üretir",
                        "Kloroplast fotosentezle glikoz sentezler",
                    ],
                }
            ]
        }
    )

    sonuc = metinden_anahtar_ayristir(OCR_METNI, sinav, uret)

    _tip, anahtar = sonuc.sorular[1]
    assert anahtar.otomatik_puanlama is False
    assert "otomatik puanlama kapalı" in anahtar.uyari
    assert any("karşılığı bulunamayan" in u for u in sonuc.uyarilar)


def test_bos_ocr_metni_model_cagirmadan_reddedilir(sinav):
    def cagrilmamali(*_a, **_k):
        raise AssertionError("boş metinde model çağrılmamalı")

    sonuc = metinden_anahtar_ayristir("   ", sinav, cagrilmamali)

    assert not sonuc.uygulanabilir
    assert any("metin okunamadı" in h for h in sonuc.hatalar)


def test_sinavda_olmayan_soru_atlanir(sinav):
    uret = _sahte_uret(
        {
            "sorular": [
                {"no": 99, "cevap_satirlari": ["X"], "rubrik_satirlari": []},
                {"no": 2, "cevap_satirlari": ["C"], "rubrik_satirlari": []},
            ]
        }
    )

    sonuc = metinden_anahtar_ayristir(OCR_METNI, sinav, uret)

    assert set(sonuc.sorular) == {2}
    assert any("99" in u for u in sonuc.uyarilar)
    assert sonuc.degismeyen == [1]


def test_bozuk_model_yaniti_hata_dondurur(sinav):
    sonuc = metinden_anahtar_ayristir(
        OCR_METNI, sinav, lambda mesajlar, **_a: "JSON değil"
    )

    assert not sonuc.uygulanabilir
    assert any("ayrıştıramadı" in h for h in sonuc.hatalar)


def test_bos_soru_listesi_hata_dondurur(sinav):
    sonuc = metinden_anahtar_ayristir(
        OCR_METNI, sinav, _sahte_uret({"sorular": []})
    )

    assert not sonuc.uygulanabilir
    assert any("çıkaramadı" in h for h in sonuc.hatalar)


def test_belgeden_metin_sayfalari_birlestirir(tmp_path):
    cv2 = pytest.importorskip("cv2")
    np = pytest.importorskip("numpy")
    from sinav_okur.htr import YapayTaniyici

    yol = tmp_path / "anahtar.png"
    cv2.imwrite(str(yol), np.full((80, 200, 3), 255, dtype=np.uint8))

    metin = anahtar_belgesinden_metin([yol], YapayTaniyici("1) Mitokondri"))

    assert metin == "1) Mitokondri"


def test_baska_sorunun_cevabi_dayanak_sayilmaz(sinav):
    """1. sorunun metni 2. soruya dayanak olarak kabul edilmemeli."""
    uret = _sahte_uret(
        {
            "sorular": [
                {
                    "no": 2,
                    "cevap_satirlari": ["Mitokondri ATP üretir"],
                    "rubrik_satirlari": [],
                }
            ]
        }
    )

    sonuc = metinden_anahtar_ayristir(OCR_METNI, sinav, uret)

    assert sonuc.sorular[2][1].otomatik_puanlama is False


def test_kisa_cevap_belgede_gecmiyorsa_puanlama_kapanir(sinav):
    """"D" şıkkı belgede yok; bulanık eşleşme onu geçirmemeli."""
    uret = _sahte_uret(
        {"sorular": [{"no": 2, "cevap_satirlari": ["D"], "rubrik_satirlari": []}]}
    )

    sonuc = metinden_anahtar_ayristir(OCR_METNI, sinav, uret)

    assert sonuc.sorular[2][1].otomatik_puanlama is False


def test_belgede_gecen_kisa_cevap_kabul_edilir(sinav):
    uret = _sahte_uret(
        {"sorular": [{"no": 2, "cevap_satirlari": ["C"], "rubrik_satirlari": []}]}
    )

    sonuc = metinden_anahtar_ayristir(OCR_METNI, sinav, uret)

    assert sonuc.sorular[2][1].otomatik_puanlama is True


def test_soru_bolumu_bulunamazsa_puanlama_kapanir(sinav):
    """Numarasız bir anahtar metninde hangi satırın hangi soruya ait olduğu
    doğrulanamaz; bu durumda otomatik puanlama açılmamalı."""
    uret = _sahte_uret(
        {
            "sorular": [
                {
                    "no": 1,
                    "cevap_satirlari": [],
                    "rubrik_satirlari": ["Mitokondri ATP üretir"],
                }
            ]
        }
    )

    sonuc = metinden_anahtar_ayristir("Mitokondri ATP üretir", sinav, uret)

    assert sonuc.sorular[1][1].otomatik_puanlama is False


def test_liste_yerine_metin_donen_alan_soruyu_atlar(sinav):
    uret = _sahte_uret(
        {"sorular": [{"no": 1, "rubrik_satirlari": "Mitokondri ATP üretir"}]}
    )

    sonuc = metinden_anahtar_ayristir(OCR_METNI, sinav, uret)

    assert not sonuc.uygulanabilir
    assert any("liste yapısını döndürmedi" in u for u in sonuc.uyarilar)
