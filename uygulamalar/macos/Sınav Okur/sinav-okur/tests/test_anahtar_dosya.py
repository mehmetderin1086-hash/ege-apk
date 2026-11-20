"""Dosyadan cevap anahtarı yükleme: dört biçim + hata toleransı testleri."""

from __future__ import annotations

import json

import pytest

from sinav_okur.anahtar_dosya import dosyadan_anahtar_uret
from sinav_okur.modeller import (
    CevapAnahtari,
    RubrikKalemi,
    Sinav,
    Soru,
    SoruTipi,
)


@pytest.fixture
def sinav() -> Sinav:
    return Sinav(
        kimlik="BIYO-ANAHTAR",
        baslik="Biyoloji",
        sorular=[
            Soru(
                no=1,
                tip=SoruTipi.ACIK_UCLU,
                metin="Mitokondrinin görevi nedir?",
                puan=10,
                anahtar=CevapAnahtari(rubrik=[RubrikKalemi("eski ölçüt", 10)]),
            ),
            Soru(
                no=2,
                tip=SoruTipi.COKTAN_SECMELI,
                metin="Hücre zarı hangisidir?",
                puan=5,
                anahtar=CevapAnahtari(dogru_cevaplar=["A"]),
            ),
            Soru(
                no=3,
                tip=SoruTipi.KISA_CEVAP,
                metin="Ribozomun görevi nedir?",
                puan=5,
                anahtar=CevapAnahtari(rubrik=[RubrikKalemi("eski", 5)]),
            ),
        ],
    )


def test_csv_anahtar_uygulanir(tmp_path, sinav):
    yol = tmp_path / "anahtar.csv"
    yol.write_text(
        "soru_no,cevap,rubrik,puan\n"
        "1,,ATP üretir|Oksijenli solunum yapar,10\n"
        "2,C,,5\n",
        encoding="utf-8",
    )

    sonuc = dosyadan_anahtar_uret(yol, sinav)

    assert sonuc.uygulanabilir
    assert not sonuc.hatalar
    tip, anahtar = sonuc.sorular[1]
    assert tip == SoruTipi.ACIK_UCLU
    assert [k.metin for k in anahtar.rubrik] == [
        "ATP üretir",
        "Oksijenli solunum yapar",
    ]
    assert sum(k.puan for k in anahtar.rubrik) == pytest.approx(10)
    assert anahtar.onay_durumu == "onayli"
    assert anahtar.otomatik_uretildi is False
    assert sonuc.sorular[2][1].dogru_cevaplar == ["C"]
    # Dosyada olmayan 3. soru korunur ve öğretmene bildirilir.
    assert sonuc.degismeyen == [3]
    assert any("3" in u for u in sonuc.uyarilar)


def test_csv_noktali_virgul_ve_turkce_baslik(tmp_path, sinav):
    yol = tmp_path / "anahtar.csv"
    yol.write_text(
        "Soru No;Doğru Cevap;Puan\n2;B;5\n", encoding="utf-8-sig"
    )

    sonuc = dosyadan_anahtar_uret(yol, sinav)

    assert sonuc.uygulanabilir
    assert sonuc.sorular[2][1].dogru_cevaplar == ["B"]


def test_xlsx_anahtar_uygulanir(tmp_path, sinav):
    openpyxl = pytest.importorskip("openpyxl")

    yol = tmp_path / "anahtar.xlsx"
    kitap = openpyxl.Workbook()
    sayfa = kitap.active
    sayfa.append(["soru_no", "cevap", "rubrik", "puan"])
    sayfa.append([1, None, "ATP üretir", 10])
    sayfa.append([2, "D", None, 5])
    kitap.save(yol)

    sonuc = dosyadan_anahtar_uret(yol, sinav)

    assert sonuc.uygulanabilir
    assert [k.metin for k in sonuc.sorular[1][1].rubrik] == ["ATP üretir"]
    assert sonuc.sorular[2][1].dogru_cevaplar == ["D"]


def test_json_tam_sema_esanlamli_ve_tolerans_tasir(tmp_path, sinav):
    yol = tmp_path / "anahtar.json"
    yol.write_text(
        json.dumps(
            {
                "sorular": [
                    {
                        "no": 1,
                        "tip": "acik_uclu",
                        "anahtar": {
                            "rubrik": [
                                {
                                    "olcut": "ATP üretir",
                                    "esanlamlilar": ["enerji üretir"],
                                    "kategori": "sonuc",
                                },
                                {"olcut": "Oksijenli solunum yapar", "puan": 4},
                            ],
                            "ornek_cevap": "Mitokondri ATP üretir.",
                            "sayisal_tolerans": 0.5,
                        },
                    }
                ]
            },
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )

    sonuc = dosyadan_anahtar_uret(yol, sinav)

    assert sonuc.uygulanabilir
    _tip, anahtar = sonuc.sorular[1]
    assert anahtar.rubrik[0].esanlamlilar == ["enerji üretir"]
    assert anahtar.rubrik[0].kategori == "sonuc"
    assert anahtar.rubrik[1].puan == pytest.approx(4)
    assert anahtar.sayisal_tolerans == pytest.approx(0.5)
    assert anahtar.uretim_yontemi == "Öğretmen · dosyadan yüklendi"


def test_yaml_no_anahtari_boolean_olmaz(tmp_path, sinav):
    yol = tmp_path / "anahtar.yaml"
    yol.write_text(
        "sorular:\n"
        "  - no: 3\n"
        "    tip: kisa_cevap\n"
        "    anahtar:\n"
        "      rubrik:\n"
        "        - olcut: Protein sentezi yapar\n",
        encoding="utf-8",
    )

    sonuc = dosyadan_anahtar_uret(yol, sinav)

    assert sonuc.uygulanabilir, sonuc.hatalar
    assert 3 in sonuc.sorular
    assert sonuc.sorular[3][1].rubrik[0].metin == "Protein sentezi yapar"


def test_otomatik_puanlama_kapatmasi_korunur(tmp_path, sinav):
    yol = tmp_path / "anahtar.json"
    yol.write_text(
        json.dumps(
            {
                "sorular": [
                    {
                        "no": 1,
                        "anahtar": {
                            "rubrik": [{"olcut": "ATP üretir"}],
                            "otomatik_puanlama": False,
                        },
                    }
                ]
            }
        ),
        encoding="utf-8",
    )

    sonuc = dosyadan_anahtar_uret(yol, sinav)

    assert sonuc.uygulanabilir
    assert sonuc.sorular[1][1].otomatik_puanlama is False
    assert any("incelemesine düşer" in u for u in sonuc.uyarilar)


def test_dosya_kendini_onayli_otomatik_ilan_edemez(tmp_path, sinav):
    yol = tmp_path / "anahtar.json"
    yol.write_text(
        json.dumps(
            {
                "sorular": [
                    {
                        "no": 1,
                        "anahtar": {
                            "rubrik": [{"olcut": "ATP üretir"}],
                            "otomatik_uretildi": True,
                            "onay_durumu": "taslak",
                        },
                    }
                ]
            }
        ),
        encoding="utf-8",
    )

    sonuc = dosyadan_anahtar_uret(yol, sinav)

    _tip, anahtar = sonuc.sorular[1]
    assert anahtar.otomatik_uretildi is False
    assert anahtar.onay_durumu == "onayli"


def test_bilinmeyen_soru_numarasi_tum_dosyayi_reddeder(tmp_path, sinav):
    yol = tmp_path / "anahtar.csv"
    yol.write_text(
        "soru_no,cevap\n1,ATP üretir\n99,Olmayan soru\n", encoding="utf-8"
    )

    sonuc = dosyadan_anahtar_uret(yol, sinav)

    assert not sonuc.uygulanabilir
    assert sonuc.sorular == {}
    assert any("99" in h for h in sonuc.hatalar)


def test_yinelenen_soru_numarasi_hatadir(tmp_path, sinav):
    yol = tmp_path / "anahtar.csv"
    yol.write_text(
        "soru_no,cevap\n1,ilk\n1,ikinci\n", encoding="utf-8"
    )

    sonuc = dosyadan_anahtar_uret(yol, sinav)

    assert not sonuc.uygulanabilir
    assert any("birden fazla" in h for h in sonuc.hatalar)


def test_bos_anahtar_hatadir(tmp_path, sinav):
    yol = tmp_path / "anahtar.csv"
    yol.write_text("soru_no,cevap\n1,\n", encoding="utf-8")

    sonuc = dosyadan_anahtar_uret(yol, sinav)

    assert not sonuc.uygulanabilir
    assert any("boş" in h for h in sonuc.hatalar)


def test_soru_no_sutunu_yoksa_acik_hata(tmp_path, sinav):
    yol = tmp_path / "anahtar.csv"
    yol.write_text("baslik,deger\nfoo,bar\n", encoding="utf-8")

    sonuc = dosyadan_anahtar_uret(yol, sinav)

    assert any("soru_no" in h for h in sonuc.hatalar)


def test_desteklenmeyen_uzanti_reddedilir(tmp_path, sinav):
    yol = tmp_path / "anahtar.docx"
    yol.write_text("veri", encoding="utf-8")

    sonuc = dosyadan_anahtar_uret(yol, sinav)

    assert any("Desteklenmeyen" in h for h in sonuc.hatalar)


def test_puan_uyusmazligi_uyari_uretir_ama_engellemez(tmp_path, sinav):
    yol = tmp_path / "anahtar.csv"
    yol.write_text("soru_no,cevap,puan\n1,ATP üretir,20\n", encoding="utf-8")

    sonuc = dosyadan_anahtar_uret(yol, sinav)

    assert sonuc.uygulanabilir
    assert any("puan" in u for u in sonuc.uyarilar)
    assert sum(k.puan for k in sonuc.sorular[1][1].rubrik) == pytest.approx(10)


def test_eslestirme_grameri_korunur(tmp_path):
    sinav = Sinav(
        kimlik="ES",
        baslik="Eşleştirme",
        sorular=[
            Soru(
                no=1,
                tip=SoruTipi.ESLESTIRME,
                metin="Organelleri görevleriyle eşleştirin.",
                puan=6,
                anahtar=CevapAnahtari(eslestirmeler={"A": "1"}),
            )
        ],
    )
    yol = tmp_path / "anahtar.csv"
    yol.write_text(
        "soru_no,cevap\n1,A = 2|B = 1|C = 3\n", encoding="utf-8"
    )

    sonuc = dosyadan_anahtar_uret(yol, sinav)

    assert sonuc.sorular[1][1].eslestirmeler == {"A": "2", "B": "1", "C": "3"}


def test_liste_yerine_metin_gelen_alan_reddedilir(tmp_path, sinav):
    """Ölçüldü: "rubrik": "ATP" karakter karakter listeye dönüşüp uygulanıyordu."""
    yol = tmp_path / "anahtar.json"
    yol.write_text(
        json.dumps({"sorular": [{"no": 1, "anahtar": {"rubrik": "ATP üretimi"}}]}),
        encoding="utf-8",
    )

    sonuc = dosyadan_anahtar_uret(yol, sinav)

    assert not sonuc.uygulanabilir
    assert any("liste olmalı" in h for h in sonuc.hatalar)


def test_eslestirmeler_nesne_degilse_reddedilir(tmp_path, sinav):
    yol = tmp_path / "anahtar.json"
    yol.write_text(
        json.dumps(
            {"sorular": [{"no": 1, "anahtar": {"eslestirmeler": ["A = 1"]}}]}
        ),
        encoding="utf-8",
    )

    sonuc = dosyadan_anahtar_uret(yol, sinav)

    assert not sonuc.uygulanabilir
    assert any("nesne olmalı" in h for h in sonuc.hatalar)


def test_kesirli_soru_numarasi_sessizce_yuvarlanmaz(tmp_path, sinav):
    yol = tmp_path / "anahtar.csv"
    yol.write_text("soru_no,cevap\n1.9,ATP üretir\n", encoding="utf-8")

    sonuc = dosyadan_anahtar_uret(yol, sinav)

    assert not sonuc.uygulanabilir
    assert any("geçerli soru numarası değil" in h for h in sonuc.hatalar)


def test_cok_satirli_tirnakli_hucre_bozulmaz(tmp_path, sinav):
    """Excel'in ürettiği tırnak içi satır sonu, rubriği bölmemeli."""
    yol = tmp_path / "anahtar.csv"
    yol.write_text(
        'soru_no,rubrik\n1,"ATP üretir\nOksijenli solunum yapar"\n',
        encoding="utf-8",
    )

    sonuc = dosyadan_anahtar_uret(yol, sinav)

    assert sonuc.uygulanabilir, sonuc.hatalar
    assert [k.metin for k in sonuc.sorular[1][1].rubrik] == [
        "ATP üretir",
        "Oksijenli solunum yapar",
    ]


def test_tipe_uymayan_anahtar_acik_hata_verir(tmp_path, sinav):
    """Açık uçlu soruya yalnız dogru_cevaplar verilirse 500 değil, hata."""
    yol = tmp_path / "anahtar.json"
    yol.write_text(
        json.dumps(
            {"sorular": [{"no": 1, "anahtar": {"dogru_cevaplar": ["ATP üretimi"]}}]}
        ),
        encoding="utf-8",
    )

    sonuc = dosyadan_anahtar_uret(yol, sinav)

    assert not sonuc.uygulanabilir
    assert any("rubrik ölçütleri gerekli" in h for h in sonuc.hatalar)


def test_coktan_secmeliye_yalniz_rubrik_verilemez(tmp_path, sinav):
    yol = tmp_path / "anahtar.json"
    yol.write_text(
        json.dumps(
            {
                "sorular": [
                    {"no": 2, "anahtar": {"rubrik": [{"olcut": "Hücre zarı"}]}}
                ]
            }
        ),
        encoding="utf-8",
    )

    sonuc = dosyadan_anahtar_uret(yol, sinav)

    assert not sonuc.uygulanabilir
    assert any("kabul edilen cevap" in h for h in sonuc.hatalar)
