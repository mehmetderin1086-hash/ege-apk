"""T-H-E gerçek-veri kapıları ve özgün karakter dışa aktarımı."""

import csv
import json
import random

import pytest

pytest.importorskip("PIL")

from sinav_okur.veri.the_karakter import (
    THE_HARITA,
    THE_LISANS,
    TURKCE_HARITA,
    glif_bankasi,
    the_karakter_aktar,
    the_satir_uret,
)


def _sahte_the_csv(yol, harita=TURKCE_HARITA, tekrar=4, tohum=0):
    rng = random.Random(tohum)
    with open(yol, "w", newline="") as f:
        w = csv.writer(f)
        for etiket in harita:
            for _ in range(tekrar):
                w.writerow([etiket] + [rng.randint(0, 255) for _ in range(784)])


def test_harita_58_turkce_sinif_ve_diacritikler():
    assert len(TURKCE_HARITA) == 58
    ters = {v: k for k, v in TURKCE_HARITA.items()}
    assert ters["i"] != ters["ı"]
    assert ters["I"] != ters["İ"]
    for ch in "çğıöşüÇĞİÖŞÜ":
        assert ch in ters
    for ch in "qwxQWX":
        assert ch not in ters


def test_glif_bankasi_yalniz_turkce_okur(tmp_path):
    csv_yol = tmp_path / "ornek.csv"
    _sahte_the_csv(csv_yol, THE_HARITA, tekrar=2)
    banka = glif_bankasi(csv_yol)
    assert len(banka) == 58
    assert "ş" in banka and "q" not in banka
    assert all(g.shape == (28, 28) for g in banka["a"])


def test_glif_bankasi_bozuk_satir_atlar(tmp_path):
    csv_yol = tmp_path / "v.csv"
    with open(csv_yol, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["etiket"] + [f"p{i}" for i in range(784)])
        w.writerow([1] + [10] * 784)
        w.writerow([1] + [10] * 500)
    banka = glif_bankasi(csv_yol)
    assert len(banka["a"]) == 1


def test_glif_bankasi_csv_sutun_major_eksenini_duzeltir(tmp_path):
    csv_yol = tmp_path / "v.csv"
    ham = [0] * 784
    ham[2 * 28 + 5] = 255
    with open(csv_yol, "w", newline="") as f:
        csv.writer(f).writerow([1] + ham)

    glif = glif_bankasi(csv_yol)["a"][0]

    assert glif[5, 2] == 255
    assert glif[2, 5] == 0


def test_version6_disindaki_surumu_reddeder(tmp_path):
    csv_yol = tmp_path / "version1.csv"
    _sahte_the_csv(csv_yol, tekrar=1)
    with pytest.raises(ValueError, match="yalnız T-H-E version6"):
        the_karakter_aktar(csv_yol, tmp_path / "cikti")


def test_karakter_aktar_manifest_ve_png(tmp_path):
    csv_yol = tmp_path / "version6.csv"
    _sahte_the_csv(csv_yol, tekrar=2)
    sonuc = the_karakter_aktar(csv_yol, tmp_path / "cikti", test_orani=0.5)
    assert sonuc["sinif"] == 58
    assert sonuc["yazilan"] == 116

    satirlar = [
        json.loads(l)
        for l in (tmp_path / "cikti" / "labels.jsonl").read_text(encoding="utf-8").splitlines()
    ]
    assert {s["split"] for s in satirlar} == {"train", "test"}
    assert all((tmp_path / "cikti" / s["image"]).exists() for s in satirlar)
    manifest = json.loads(
        (tmp_path / "cikti" / "veri_manifesti.json").read_text(encoding="utf-8")
    )
    assert manifest["real_handwriting"] is True
    assert manifest["augmentation_used"] is False
    assert manifest["composition_used"] is False
    assert manifest["writer_disjoint"] is False
    assert manifest["license"] == THE_LISANS
    assert "public-domain" in manifest["license_evidence_note"]


def test_kaynakta_eksik_buyuk_harfler_manifestte_raporlanir(tmp_path):
    csv_yol = tmp_path / "version6.csv"
    eksik_harita = {k: v for k, v in TURKCE_HARITA.items() if k not in {66, 69}}
    _sahte_the_csv(csv_yol, eksik_harita, tekrar=1)
    sonuc = the_karakter_aktar(csv_yol, tmp_path / "cikti")
    manifest = json.loads(
        (tmp_path / "cikti" / "veri_manifesti.json").read_text(encoding="utf-8")
    )
    assert sonuc["sinif"] == 56
    assert set(manifest["missing_turkish_characters"]) == {"Ç", "Ş"}


def test_sahte_satir_bilesimi_engellendi():
    with pytest.raises(RuntimeError, match="gerçek insan satırı"):
        the_satir_uret("version6.csv", "cikti")


def test_bos_banka_hata(tmp_path):
    csv_yol = tmp_path / "bos.csv"
    with open(csv_yol, "w", newline="") as f:
        csv.writer(f).writerow([999] + [0] * 784)
    with pytest.raises(ValueError, match="geçerli T-H-E"):
        glif_bankasi(csv_yol)
