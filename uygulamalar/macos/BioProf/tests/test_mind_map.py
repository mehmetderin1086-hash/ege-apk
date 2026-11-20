"""Zihin haritası grafı: hiyerarşi, çapraz kenar ve kanıt bütünlüğü."""

from __future__ import annotations

from bioprof.studio.artifacts import StudioEngine, StudioEvidence


def _kanitlar() -> list[StudioEvidence]:
    return [
        StudioEvidence(
            label="S1",
            text=(
                "Fotosentez kloroplastlarda gerçekleşir. Işık tepkimeleri tilakoit "
                "zarlarda yürür. Kalvin döngüsü stromada ilerler."
            ),
            source_title="Campbell",
            citation_id="c1",
            section="Fotosentez",
        ),
        StudioEvidence(
            label="S2",
            text=(
                "Hücresel solunum mitokondride gerçekleşir. Krebs döngüsü matrikste "
                "yürür. Elektron taşıma sistemi iç zarda çalışır."
            ),
            source_title="Campbell",
            citation_id="c2",
            section="Solunum",
        ),
        StudioEvidence(
            label="S3",
            # "kloroplastlarda" iki bölümde de geçsin: çapraz kenar bekleriz.
            text="Enerji dönüşümü kloroplastlarda ve mitokondride ATP üzerinden ilerler.",
            source_title="Campbell",
            citation_id="c3",
            section="Enerji",
        ),
    ]


def _uret():
    return StudioEngine().generate("mind_map", title="Enerji", evidence=_kanitlar())


def test_graf_kok_kume_ve_kavram_seviyeleri() -> None:
    artifact = _uret()
    nodes = artifact.structured_data["nodes"]
    seviyeler = {node["level"] for node in nodes}
    assert seviyeler == {0, 1, 2}
    assert nodes[0]["id"] == "root"
    kume_adlari = {node["label"] for node in nodes if node["level"] == 1}
    assert {"Fotosentez", "Solunum", "Enerji"} <= kume_adlari


def test_her_kenar_gecerli_dugumlere_baglanir() -> None:
    artifact = _uret()
    kimlikler = {node["id"] for node in artifact.structured_data["nodes"]}
    for edge in artifact.structured_data["edges"]:
        assert edge["source"] in kimlikler and edge["target"] in kimlikler
        assert edge["kind"] in ("hiyerarsi", "capraz")


def test_capraz_kenar_uretilir_ve_kanitlar_birlesir() -> None:
    artifact = _uret()
    edges = artifact.structured_data["edges"]
    caprazlar = [edge for edge in edges if edge["kind"] == "capraz"]
    assert caprazlar, "iki bölümde geçen kavram çapraz kenar üretmeliydi"
    nodes = {node["id"]: node for node in artifact.structured_data["nodes"]}
    hedef = nodes[caprazlar[0]["target"]]
    assert len(hedef["evidence_chunk_ids"]) >= 2


def test_her_dugum_kanit_tasir() -> None:
    artifact = _uret()
    for node in artifact.structured_data["nodes"]:
        assert node["citation"].startswith("[S")
        assert node["citation_id"]
    assert artifact.provenance_complete


def test_mermaid_md_temsili_korunur() -> None:
    artifact = _uret()
    assert "```mermaid" in artifact.content_markdown
    assert "mindmap" in artifact.content_markdown
