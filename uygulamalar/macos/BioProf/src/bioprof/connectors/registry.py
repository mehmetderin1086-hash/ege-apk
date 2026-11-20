from __future__ import annotations

from collections.abc import Mapping

from bioprof.connectors.clinical_trials import ClinicalTrialsConnector
from bioprof.connectors.models import ConnectorError, ConnectorPage, RemoteRecord
from bioprof.connectors.ncbi import NCBIConnector, PMCConnector


class BiomedicalConnectorRegistry:
    """Explicit routing over official connectors; arbitrary URL fetches are absent."""

    def __init__(
        self,
        *,
        ncbi: NCBIConnector | None = None,
        pmc: PMCConnector | None = None,
        clinical_trials: ClinicalTrialsConnector | None = None,
    ) -> None:
        self.ncbi = ncbi or NCBIConnector()
        self.pmc = pmc or PMCConnector()
        self.clinical_trials = clinical_trials or ClinicalTrialsConnector()

    @staticmethod
    def providers() -> Mapping[str, str]:
        return {
            "pubmed": "NCBI PubMed metadata and abstracts",
            "gene": "NCBI Gene",
            "protein": "NCBI Protein",
            "taxonomy": "NCBI Taxonomy",
            "clinvar": "NCBI ClinVar",
            "pmc": "PMC Open Access full text",
            "clinical_trials": "ClinicalTrials.gov API v2",
        }

    async def search(
        self,
        provider: str,
        query: str,
        *,
        limit: int = 20,
        cursor: str | None = None,
    ) -> ConnectorPage:
        if provider == "pmc":
            if cursor not in (None, "0"):
                raise ConnectorError("PMC connector currently accepts only the first page")
            return await self.pmc.search_open_access(query, limit=limit)
        if provider == "clinical_trials":
            return await self.clinical_trials.search(query, limit=limit, cursor=cursor)
        if provider in {"pubmed", "gene", "protein", "taxonomy", "clinvar"}:
            numeric_cursor = int(cursor or 0) if (cursor or "0").isdigit() else 0
            return await self.ncbi.search(
                query, database=provider, limit=limit, cursor=numeric_cursor
            )
        raise ConnectorError(f"Araştırma sağlayıcısı izinli değil: {provider}")

    async def fetch(self, provider: str, record_id: str) -> RemoteRecord:
        if provider == "pubmed":
            return await self.ncbi.fetch_pubmed_abstract(record_id)
        if provider == "pmc":
            return await self.pmc.fetch_open_access_article(record_id)
        if provider == "clinical_trials":
            return await self.clinical_trials.fetch(record_id)
        raise ConnectorError(f"Tam kayıt içe aktarma desteklenmiyor: {provider}")

    async def aclose(self) -> None:
        await self.ncbi.aclose()
        await self.pmc.aclose()
        await self.clinical_trials.aclose()
