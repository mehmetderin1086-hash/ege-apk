"""MEB günlük ders planı: kazanım önerisi, plan bölümleri, DOCX düzeni."""

from __future__ import annotations

import re
from pathlib import Path

import pytest

from bioprof.studio.artifacts import ArtifactExporter, StudioEngine, StudioEvidence
from bioprof.studio.meb_kazanimlar import KAZANIMLAR, kazanim_oner


def _kanitlar() -> list[StudioEvidence]:
    return [
        StudioEvidence(
            label="S1",
            text=(
                "Mitoz bölünme sonucunda iki özdeş hücre oluşur. Mitoz, büyüme ve "
                "onarımın temelidir. Hücre bölünmesi canlılığın sürekliliği için gereklidir."
            ),
            source_title="Campbell",
            citation_id="c1",
            section="Mitoz",
        ),
        StudioEvidence(
            label="S2",
            text=(
                "Mayoz bölünme, eşey ana hücrelerinde görülür ve kromozom "
                "sayısını yarıya indirir."
            ),
            source_title="Campbell",
            citation_id="c2",
            section="Mayoz",
        ),
    ]


class TestKazanimTablosu:
    def test_kod_formati_tutarli(self) -> None:
        kazanim_deseni = re.compile(r"^\d{1,2}\.\d\.\d\.\d$")
        unite_deseni = re.compile(r"^\d{1,2}\.\d$")
        for kayit in KAZANIMLAR:
            assert kazanim_deseni.match(kayit.kod) or unite_deseni.match(kayit.kod), kayit.kod
            assert kayit.sinif in (9, 10, 11, 12)
            # Kazanım düzeyi kayıtta metin dolu, ünite düzeyinde boş olmalı.
            if kazanim_deseni.match(kayit.kod):
                assert kayit.metin, kayit.kod
            else:
                assert not kayit.metin, kayit.kod

    def test_kod_sinif_tutarli(self) -> None:
        for kayit in KAZANIMLAR:
            assert kayit.kod.startswith(f"{kayit.sinif}."), kayit.kod

    def test_bilinen_terim_dogru_kodu_onerir(self) -> None:
        oneriler = kazanim_oner(["Mitoz bölünme sonucunda iki özdeş hücre oluşur."])
        kodlar = [item.kod for item in oneriler]
        assert "10.1.1.2" in kodlar  # "Mitozu açıklar."

    def test_sinif_filtresi(self) -> None:
        oneriler = kazanim_oner(["Hücresel yapılar ve görevleri"], sinif=9)
        assert oneriler and all(item.sinif == 9 for item in oneriler)


class TestDersPlani:
    def _uret(self, **options):
        return StudioEngine().generate(
            "ders_plani",
            title="Hücre Bölünmeleri",
            evidence=_kanitlar(),
            options=options or None,
        )

    def test_plan_bolumleri_eksiksiz_ve_atifli(self) -> None:
        artifact = self._uret()
        plan = artifact.structured_data["ders_plani"]
        assert plan["ders"] == "Biyoloji"
        assert plan["sure_dakika"] == 40
        assert plan["kazanim_onerileri"], "kazanım önerisi boş"
        assert plan["islenis"]["giris"] and plan["islenis"]["sonuc"]
        for madde in plan["islenis"]["gelisme"]:
            assert madde["citation"].startswith("[S")
        assert plan["olcme_degerlendirme"]
        assert artifact.provenance_complete

    def test_ogretmen_dogrulama_uyarisi_kalici(self) -> None:
        artifact = self._uret()
        assert any("öğretmen doğrulamalı" in uyari.casefold() for uyari in artifact.warnings)
        assert "öğretmen doğrulamalı" in artifact.content_markdown.casefold()

    def test_secenekler_gecer(self) -> None:
        artifact = self._uret(sinif=10, sure_dakika=80, kazanim_kodlari=["10.1.1.2"])
        plan = artifact.structured_data["ders_plani"]
        assert plan["sinif"] == 10 and plan["sure_dakika"] == 80
        assert [k["kod"] for k in plan["kazanim_onerileri"]] == ["10.1.1.2"]

    def test_docx_meb_tablosuyla_uretilir(self, tmp_path: Path) -> None:
        docx = pytest.importorskip("docx")
        artifact = self._uret()
        yol = ArtifactExporter().export(artifact, tmp_path / "plan", format_name="docx")
        belge = docx.Document(str(yol))
        assert belge.tables, "üst bilgi tablosu yok"
        hucre_metinleri = [hucre.text for satir in belge.tables[0].rows for hucre in satir.cells]
        assert "Ders" in hucre_metinleri and "Biyoloji" in hucre_metinleri
        tum_metin = "\n".join(paragraf.text for paragraf in belge.paragraphs)
        assert "İşleniş" in tum_metin and "Ölçme" in tum_metin
        assert "öğretmen doğrulamalı" in tum_metin.casefold()
