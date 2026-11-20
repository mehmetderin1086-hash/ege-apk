from __future__ import annotations

import re
from typing import Any

import httpx

from bioprof.connectors.base import OfficialAPIConnector
from bioprof.connectors.models import ConnectorError, ConnectorPage, Provenance, RemoteRecord


class ClinicalTrialsConnector(OfficialAPIConnector):
    def __init__(self, *, client: httpx.AsyncClient | None = None) -> None:
        super().__init__(
            base_url="https://clinicaltrials.gov/api/v2/",
            provider_name="ClinicalTrials.gov",
            requests_per_second=3,
            client=client,
        )

    async def search(
        self,
        query: str,
        *,
        limit: int = 20,
        cursor: str | None = None,
    ) -> ConnectorPage:
        query = query.strip()
        if not query or len(query) > 2_000:
            raise ConnectorError("Sorgu 1-2000 karakter olmalıdır")
        params: dict[str, Any] = {
            "query.term": query,
            "pageSize": max(1, min(limit, 100)),
            "format": "json",
            "countTotal": "true",
        }
        if cursor:
            if len(cursor) > 4_000 or not re.fullmatch(r"[A-Za-z0-9_.~=-]+", cursor):
                raise ConnectorError("Geçersiz ClinicalTrials sayfa belirteci")
            params["pageToken"] = cursor
        payload = (await self._get("studies", params=params)).json()
        records = [self._record(study) for study in payload.get("studies", [])]
        return ConnectorPage(
            records=records,
            next_cursor=payload.get("nextPageToken"),
            total=payload.get("totalCount"),
            provider="ClinicalTrials.gov",
        )

    async def fetch(self, nct_id: str) -> RemoteRecord:
        nct_id = nct_id.upper()
        if not re.fullmatch(r"NCT\d{8}", nct_id):
            raise ConnectorError("Çalışma kimliği NCT ve sekiz rakamdan oluşmalıdır")
        payload = (await self._get(f"studies/{nct_id}", params={"format": "json"})).json()
        return self._record(payload)

    @staticmethod
    def _record(study: dict[str, Any]) -> RemoteRecord:
        protocol = study.get("protocolSection", {})
        identification = protocol.get("identificationModule", {})
        status = protocol.get("statusModule", {})
        description = protocol.get("descriptionModule", {})
        design = protocol.get("designModule", {})
        nct_id = str(identification.get("nctId", ""))
        title = str(
            identification.get("briefTitle") or identification.get("officialTitle") or nct_id
        )
        text = "\n\n".join(
            filter(
                None,
                [
                    description.get("briefSummary"),
                    description.get("detailedDescription"),
                ],
            )
        )
        canonical = f"https://clinicaltrials.gov/study/{nct_id}"
        return RemoteRecord(
            id=nct_id,
            title=title,
            text=text,
            url=canonical,
            record_type="clinical_trial",
            published_at=(status.get("studyFirstPostDateStruct") or {}).get("date"),
            identifiers={"nct_id": nct_id},
            metadata={
                "overall_status": status.get("overallStatus"),
                "study_type": design.get("studyType"),
                "phases": design.get("phases", []),
                "has_results": bool(study.get("hasResults")),
            },
            provenance=Provenance(
                provider="ClinicalTrials.gov",
                canonical_url=canonical,
                record_id=nct_id,
                database="clinicaltrials.gov",
                license="ClinicalTrials.gov Terms and Conditions",
                license_url="https://clinicaltrials.gov/about-site/terms-conditions",
                rights_status="metadata_only",
                api_version="v2",
            ),
        )
