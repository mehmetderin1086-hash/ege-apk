"""Slayt üreteci: gerçek yapı, atıf bütünlüğü ve PPTX dışa aktarımı."""

from __future__ import annotations

from pathlib import Path

import pytest

from bioprof.studio.artifacts import ArtifactExporter, StudioEngine, StudioEvidence


def _kanitlar() -> list[StudioEvidence]:
    return [
        StudioEvidence(
            label="S1",
            text=(
                "Mitokondri, oksijenli solunumun gerçekleştiği çift zarlı organeldir. "
                "İç zar kıvrımlarına krista denir. Matriks bölümünde DNA bulunur."
            ),
            source_title="Campbell",
            citation_id="c1",
            section="Mitokondri",
        ),
        StudioEvidence(
            label="S2",
            text=(
                "Kloroplast, fotosentezin gerçekleştiği organeldir. "
                "Tilakoit zarlarda klorofil pigmenti bulunur."
            ),
            source_title="Campbell",
            citation_id="c2",
            section="Kloroplast",
        ),
        StudioEvidence(
            label="S3",
            text="Ribozomlar protein sentezinden sorumlu zarsız organellerdir.",
            source_title="Campbell",
            citation_id="c3",
            section="Ribozom",
        ),
    ]


def _uret():
    return StudioEngine().generate(
        "slides", title="Hücre Organelleri", evidence=_kanitlar()
    )


def test_slayt_yapisi_acilis_icerik_ozet() -> None:
    artifact = _uret()
    slides = artifact.structured_data["slides"]
    # Açılış + 3 küme + özet
    assert len(slides) == 5
    assert slides[0]["title"] == "Hücre Organelleri"
    assert slides[-1]["title"] == "Özet"
    assert [s["index"] for s in slides] == [1, 2, 3, 4, 5]


def test_her_bullet_atifli_ve_konusmaci_notu_var() -> None:
    artifact = _uret()
    for slide in artifact.structured_data["slides"][1:-1]:
        assert slide["bullets"], slide["title"]
        for bullet in slide["bullets"]:
            assert bullet["citation"].startswith("[S")
            assert bullet["citation_id"]
        assert slide["speaker_notes"]
        assert slide["kaynak_dipnotu"]
    assert artifact.provenance_complete


def test_markdown_slayt_basliklari_icerir() -> None:
    artifact = _uret()
    assert "## Slayt 2: Mitokondri" in artifact.content_markdown
    assert "Konuşmacı notu:" in artifact.content_markdown


def test_pptx_yapidan_uretilir_ve_yeniden_acilir(tmp_path: Path) -> None:
    pptx = pytest.importorskip("pptx")
    artifact = _uret()
    hedef = tmp_path / "cikti"
    yol = ArtifactExporter().export(artifact, hedef, format_name="pptx")
    sunum = pptx.Presentation(str(yol))
    slaytlar = list(sunum.slides)
    assert len(slaytlar) == 5
    assert slaytlar[1].shapes.title.text == "Mitokondri"
    # Konuşmacı notu gerçekten notes bölümüne yazılmış olmalı.
    assert "krista" in slaytlar[1].notes_slide.notes_text_frame.text.casefold()
    # Kaynak dipnotu son paragraf ve küçük punto.
    metin_kutusu = slaytlar[1].placeholders[1].text_frame
    assert "Campbell" in metin_kutusu.paragraphs[-1].text


def test_eski_markdown_pptx_yolu_diger_tiplerde_korunur(tmp_path: Path) -> None:
    pptx = pytest.importorskip("pptx")
    artifact = StudioEngine().generate(
        "study_guide", title="Rehber", evidence=_kanitlar()
    )
    yol = ArtifactExporter().export(artifact, tmp_path / "rehber", format_name="pptx")
    sunum = pptx.Presentation(str(yol))
    assert list(sunum.slides), "eski yol slayt üretemedi"


def test_slides_alias_artik_study_guide_degil() -> None:
    artifact = _uret()
    assert artifact.kind == "slides"
    assert "slides" in StudioEngine.supported_kinds
