"""Gerçek veri adaptörü: HF datasets'i mock'layarak labels.jsonl üretimini sınar."""
import json
import sys
import types
from pathlib import Path

import pytest

pytest.importorskip("PIL")
from PIL import Image

from sinav_okur.veri.gercek import VeriSetiOnAyar, hf_labels_uret
from sinav_okur.veri.satir_paketi import satir_paketi_aktar


class SahteDS:
    """load_dataset'in döndürdüğü nesneyi taklit eder (column_names + iterasyon)."""

    def __init__(self, kayitlar, kolonlar):
        self._k = kayitlar
        self.column_names = kolonlar

    def __iter__(self):
        return iter(self._k)


def _mock_datasets(monkeypatch, kayitlar, kolonlar):
    mod = types.ModuleType("datasets")
    mod.load_dataset = lambda repo, split=None: SahteDS(kayitlar, kolonlar)
    monkeypatch.setitem(sys.modules, "datasets", mod)


def test_hf_labels_uret_otomatik_kolon(tmp_path, monkeypatch):
    g = Image.new("RGB", (40, 20), "white")
    kayitlar = [
        {"image": g, "text": "hücre"},
        {"image": g, "text": "mitokondri"},
        {"image": g, "text": ""},          # boş metin → atlanmalı
        {"image": None, "text": "boş"},     # görüntü yok → atlanmalı
    ]
    _mock_datasets(monkeypatch, kayitlar, ["image", "text"])

    sonuc = hf_labels_uret(VeriSetiOnAyar(repo_id="sahte/set"), tmp_path)
    assert sonuc["yazilan"] == 2
    assert sonuc["atlanan"] == 2

    satirlar = [json.loads(l) for l in (tmp_path / "labels.jsonl").read_text(encoding="utf-8").splitlines()]
    assert {s["text"] for s in satirlar} == {"hücre", "mitokondri"}
    for s in satirlar:
        assert (tmp_path / s["image"]).exists()


def test_hf_labels_alternatif_kolon_adi(tmp_path, monkeypatch):
    """'transcription' gibi farklı metin kolonu otomatik tespit edilmeli."""
    g = Image.new("RGB", (30, 15), "white")
    _mock_datasets(monkeypatch, [{"img": g, "transcription": "epitel doku"}], ["img", "transcription"])
    sonuc = hf_labels_uret(VeriSetiOnAyar(repo_id="x/y"), tmp_path)
    assert sonuc["yazilan"] == 1


def test_hf_labels_kolon_bulunamazsa_hata(tmp_path, monkeypatch):
    g = Image.new("RGB", (10, 10), "white")
    _mock_datasets(monkeypatch, [{"foto": g, "aciklama": "x"}], ["foto", "aciklama"])
    with pytest.raises(ValueError, match="kolonu tespit edilemedi"):
        hf_labels_uret(VeriSetiOnAyar(repo_id="x/y"), tmp_path)


def test_azami_siniri(tmp_path, monkeypatch):
    g = Image.new("RGB", (10, 10), "white")
    _mock_datasets(monkeypatch, [{"image": g, "text": f"k{i}"} for i in range(10)], ["image", "text"])
    sonuc = hf_labels_uret(VeriSetiOnAyar(repo_id="x/y"), tmp_path, azami=3)
    assert sonuc["yazilan"] == 3


def test_lisanssiz_veya_sentetik_set_egitimde_engellenir(tmp_path, monkeypatch):
    g = Image.new("RGB", (10, 10), "white")
    _mock_datasets(monkeypatch, [{"image": g, "text": "x"}], ["image", "text"])
    with pytest.raises(PermissionError, match="eğitim indirmesi engellendi"):
        hf_labels_uret(VeriSetiOnAyar(repo_id="x/y"), tmp_path, amac="egitim")


def test_izinli_gercek_set_egitime_alinir(tmp_path, monkeypatch):
    g = Image.new("RGB", (10, 10), "white")
    _mock_datasets(monkeypatch, [{"image": g, "text": "hücre"}], ["image", "text"])
    ayar = VeriSetiOnAyar(
        repo_id="izinli/gercek",
        lisans="CC-BY-4.0",
        gercek_el_yazisi=True,
        egitim_izni=True,
    )
    sonuc = hf_labels_uret(ayar, tmp_path, amac="egitim")
    assert sonuc["yazilan"] == 1
    assert sonuc["amac"] == "egitim"


def test_sentetik_cli_varsayilan_olarak_engelli(tmp_path):
    from sinav_okur.cli import main

    assert main(["veri", "-f", str(tmp_path)]) == 2


def _satir_paketi_yaz(tmp_path, kayitlar):
    for i in range(len(kayitlar)):
        Image.new("L", (80, 24), "white").save(tmp_path / f"{i}.png")
        kayitlar[i]["image"] = f"{i}.png"
    labels = tmp_path / "kaynak.jsonl"
    labels.write_text(
        "".join(json.dumps(k, ensure_ascii=False) + "\n" for k in kayitlar),
        encoding="utf-8",
    )
    izin = tmp_path / "IZIN.txt"
    izin.write_text("Araştırma amaçlı model eğitimi izni.", encoding="utf-8")
    return labels, izin


def test_satir_paketi_yazar_ayrik_aktarilir(tmp_path):
    kayitlar = [
        {
            "text": f"Çalışma {i} şüphe ölçüm",
            "writer_id": f"w-{i}",
            "split": "train" if i < 4 else "test",
        }
        for i in range(5)
    ]
    labels, izin = _satir_paketi_yaz(tmp_path, kayitlar)
    sonuc = satir_paketi_aktar(
        labels,
        tmp_path / "out",
        lisans="Yazılı akademik kullanım izni",
        izin_belgesi=izin,
        kaynak_url="https://example.org/dataset",
    )
    assert sonuc["satir"] == 5
    assert sonuc["yazar"] == 5
    assert sonuc["bolmeler_dogrulandi"] is True
    manifest = json.loads((tmp_path / "out/manifest.json").read_text(encoding="utf-8"))
    assert manifest["writer_disjoint_splits_verified"] is True
    assert manifest["turkish_special_character_counts"]["Ç"] == 5
    assert manifest["turkish_special_character_counts"]["ş"] == 10
    assert len(manifest["image_sha256"]) == 5


def test_satir_paketi_yazar_sizintisini_reddeder(tmp_path):
    kayitlar = [
        {"text": f"satır {i}", "writer_id": f"w-{i}", "split": "train"}
        for i in range(5)
    ]
    kayitlar.append({"text": "sızıntı", "writer_id": "w-0", "split": "test"})
    labels, izin = _satir_paketi_yaz(tmp_path, kayitlar)
    with pytest.raises(ValueError, match="Yazar sızıntısı"):
        satir_paketi_aktar(
            labels,
            tmp_path / "out",
            lisans="izin",
            izin_belgesi=izin,
            kaynak_url="https://example.org",
        )


def test_satir_paketi_paket_disindaki_goruntuyu_reddeder(tmp_path):
    dis = tmp_path.parent / "dis.png"
    Image.new("L", (10, 10), "white").save(dis)
    kayitlar = [
        {"image": str(dis), "text": "satır", "writer_id": f"w-{i}"}
        for i in range(5)
    ]
    labels = tmp_path / "kaynak.jsonl"
    labels.write_text(
        "".join(json.dumps(k) + "\n" for k in kayitlar),
        encoding="utf-8",
    )
    izin = tmp_path / "izin.txt"
    izin.write_text("izin", encoding="utf-8")
    with pytest.raises(ValueError, match="paket dizini dışında"):
        satir_paketi_aktar(
            labels,
            tmp_path / "out",
            lisans="izin",
            izin_belgesi=izin,
            kaynak_url="https://example.org",
        )
