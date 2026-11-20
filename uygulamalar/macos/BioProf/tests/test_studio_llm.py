"""Stüdyo LLM yazarı: akıcılaştırma olgu uydurmaya dönüşmemeli."""

from __future__ import annotations

import asyncio

import pytest

from bioprof.providers.base import ProviderUnavailableError
from bioprof.studio.artifacts import StudioEngine, StudioEvidence
from bioprof.studio.llm_writer import StudioLLMWriter

_KAYNAK_METNI = (
    "Mitokondri, ökaryot hücrelerde bulunan çift zarlı bir organeldir. "
    "Hücresel solunum yoluyla ATP üretiminden sorumludur; bu nedenle hücrenin "
    "enerji santrali olarak adlandırılır."
)


def _records() -> list[StudioEvidence]:
    return [
        StudioEvidence(
            label="S1",
            text=_KAYNAK_METNI,
            source_title="Hücre Biyolojisi",
            citation_id="cit-1",
        )
    ]


def _draft() -> str:
    return StudioEngine().generate(
        "summary", title="Mitokondri", evidence=_records()
    ).content_markdown


def _writer(cevap: str | Exception) -> StudioLLMWriter:
    async def chat(messages, *, max_tokens=None):
        if isinstance(cevap, Exception):
            raise cevap
        return cevap

    return StudioLLMWriter(chat)


def _rewrite(writer: StudioLLMWriter, kind: str = "summary") -> tuple[str, list[str]]:
    return asyncio.run(writer.rewrite(kind, _draft(), _records()))


def test_akicilastirilmis_metin_kabul_edilir() -> None:
    yeni = (
        "# Mitokondri\n\n"
        "- Mitokondri, ökaryot hücrelerde bulunan çift zarlı bir organeldir [S1]."
    )
    metin, uyarilar = _rewrite(_writer(yeni))
    assert "çift zarlı bir organeldir" in metin
    assert "[S1]" in metin
    assert not uyarilar


def test_capasiz_cumle_dusurulur() -> None:
    yeni = (
        "# Mitokondri\n\n"
        "- Mitokondri çift zarlı bir organeldir [S1].\n"
        "- Mitokondri hücre bölünmesini yönetir."
    )
    metin, uyarilar = _rewrite(_writer(yeni))
    assert "hücre bölünmesini yönetir" not in metin
    assert any("çıkarıldı" in uyari for uyari in uyarilar)


def test_uydurulan_capa_reddedilir() -> None:
    # [S9] diye bir kanıt yok; etiketi uydurmak cümleyi geçerli kılmamalı.
    yeni = "# Mitokondri\n\n- Mitokondri ribozom üretir [S9]."
    metin, uyarilar = _rewrite(_writer(yeni))
    assert metin == _draft()
    assert any("kapısından geçmedi" in uyari for uyari in uyarilar)


def test_desteksiz_olgu_kanit_capasiyla_gecemez() -> None:
    # Doğru etiket + yanlış olgu: kanıt penceresi testinin asıl görevi bu.
    yeni = "# Mitokondri\n\n- Mitokondri fotosentez yapar [S1]."
    metin, _ = _rewrite(_writer(yeni))
    assert "fotosentez" not in metin
    assert metin == _draft()


def test_llm_hatasinda_taslak_korunur() -> None:
    metin, uyarilar = _rewrite(_writer(ProviderUnavailableError("model kapalı")))
    assert metin == _draft()
    assert any("taslak korundu" in uyari for uyari in uyarilar)


def test_bos_yanit_taslagi_bozmaz() -> None:
    metin, uyarilar = _rewrite(_writer("   "))
    assert metin == _draft()
    assert uyarilar


@pytest.mark.parametrize("kind", ["quiz", "flashcards", "table", "mind_map"])
def test_yapisal_turler_llm_disinda_kalir(kind: str) -> None:
    # Bu türlerde yanlış şık/hücre üretme riski kazanımdan büyük.
    assert not _writer("x").supports(kind)


def test_dipnot_korunur() -> None:
    yeni = "# Mitokondri\n\n- Mitokondri çift zarlı bir organeldir [S1]."
    metin, _ = _rewrite(_writer(yeni))
    assert "## Kaynaklar" in metin
    assert "[S1] Hücre Biyolojisi" in metin


def test_writer_yokken_cikti_degismez() -> None:
    # Altın dosya regresyonu: LLM devre dışıyken bugünkü davranış birebir aynı.
    artifact = StudioEngine().generate("summary", title="Mitokondri", evidence=_records())
    assert artifact.content_markdown == _draft()
    assert "llm_polished" not in artifact.structured_data
