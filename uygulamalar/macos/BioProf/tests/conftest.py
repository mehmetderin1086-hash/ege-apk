"""Paylaşılan test fixture'ları: geçici dizinde tam BioProfApplication."""

from __future__ import annotations

from pathlib import Path

import pytest

from bioprof.application import BioProfApplication
from bioprof.config import Settings
from bioprof.db.session import Database
from bioprof.domain.models import CitationAnchor, Evidence
from bioprof.providers.local import LocalEvidenceProvider
from bioprof.providers.registry import ProviderPolicy, ProviderRegistry
from bioprof.voice.seslab import SesLabAdapter


def fake_evidence(label: str = "S1", text: str | None = None) -> Evidence:
    quote = text or "Mitokondri, hücrenin enerji santrali olarak görev yapar."
    return Evidence(
        label=label,
        text=quote,
        score=1.0,
        anchor=CitationAnchor(
            id=f"cit-{label}",
            source_id="src-1",
            source_sha256="0" * 64,
            chunk_id=f"chunk-{label}",
            quote=quote,
            source_title="Test Kaynağı",
        ),
    )


class FakeRetriever:
    def __init__(self, evidence: list[Evidence]) -> None:
        self._evidence = evidence

    def search(self, *args, **kwargs) -> list[Evidence]:
        return list(self._evidence)


@pytest.fixture()
def app(tmp_path: Path) -> BioProfApplication:
    settings = Settings(
        _env_file=None,  # runtime/.env test davranışını değiştirmesin
        data_dir=tmp_path / "veri",
        model_cache_dir=tmp_path / "modeller",
        use_qdrant=False,
        local_embeddings=False,
        local_llm_python=tmp_path / "olmayan-venv" / "python",
        local_llm_idle_timeout=0.0,
    )
    settings.ensure_directories()
    database = Database(settings)
    database.initialize()
    providers = ProviderRegistry(policy=ProviderPolicy(allow_remote_egress=False))
    providers.register(LocalEvidenceProvider())
    voice = SesLabAdapter(base_url="http://127.0.0.1:8010")
    return BioProfApplication(settings, database, providers, voice)
