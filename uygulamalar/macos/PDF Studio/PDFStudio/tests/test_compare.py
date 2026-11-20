"""compare servisi testleri: metin ve görsel fark."""
from __future__ import annotations

from pathlib import Path

import fitz

from app.services import compare


def _variant(sample_pdf: Path, tmp_path: Path) -> Path:
    """3. sayfasına satır eklenmiş kopya üretir."""
    doc = fitz.open(sample_pdf)
    doc[2].insert_text((72, 300), "EKLENEN YENİ SATIR", fontsize=14)
    p = tmp_path / "degisik.pdf"
    doc.save(p)
    doc.close()
    return p


def test_compare_identical(sample_pdf):
    rep = compare.compare_text(sample_pdf, sample_pdf)
    assert rep["summary"]["identical"] is True
    assert rep["summary"]["overall_similarity"] == 1.0
    assert all(p["similarity"] == 1.0 for p in rep["page_pairs"])
    assert all(not p["added"] and not p["removed"] for p in rep["page_pairs"])


def test_compare_modified_page(sample_pdf, tmp_path):
    rep = compare.compare_text(sample_pdf, _variant(sample_pdf, tmp_path))
    assert rep["summary"]["identical"] is False
    assert rep["summary"]["overall_similarity"] < 1.0
    p3 = rep["page_pairs"][2]
    assert p3["similarity"] < 1.0
    assert any("EKLENEN" in ln for ln in p3["added"])
    assert rep["page_pairs"][0]["similarity"] == 1.0  # dokunulmayan sayfa özdeş


def test_compare_page_count_difference(sample_pdf, tmp_path):
    doc = fitz.open(sample_pdf)
    doc.delete_page(3)
    p = tmp_path / "kisa.pdf"
    doc.save(p)
    doc.close()
    rep = compare.compare_text(sample_pdf, p)
    assert rep["summary"]["page_count_a"] == 4
    assert rep["summary"]["page_count_b"] == 3
    assert rep["summary"]["identical"] is False
    assert rep["page_pairs"][3]["missing_in"] == "b"


def test_compare_visual_diff(sample_pdf, tmp_path):
    outs = compare.compare_visual(sample_pdf, _variant(sample_pdf, tmp_path))
    names = [n for n, _ in outs]
    assert "fark_sayfa_3.png" in names
    # PNG imzası
    assert outs[0][1][:8] == b"\x89PNG\r\n\x1a\n"


def test_compare_visual_identical_empty(sample_pdf):
    assert compare.compare_visual(sample_pdf, sample_pdf) == []
