from __future__ import annotations

import re
import xml.etree.ElementTree as ET
from typing import Any

import httpx

from bioprof.connectors.base import OfficialAPIConnector
from bioprof.connectors.models import (
    ConnectorError,
    ConnectorPage,
    Provenance,
    RemoteRecord,
    RightsError,
)

EUTILS_BASE = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/"
ALLOWED_DATABASES = {"pubmed", "gene", "protein", "taxonomy", "clinvar", "pmc"}
OPEN_LICENSE_MARKERS = (
    "creative commons",
    "cc by",
    "cc0",
    "public domain",
)


def _safe_xml(content: bytes) -> ET.Element:
    lowered = content[:100_000].lower()
    if b"<!doctype" in lowered or b"<!entity" in lowered:
        raise ConnectorError("Güvenli olmayan XML bildirimi reddedildi")
    try:
        return ET.fromstring(content)
    except ET.ParseError as exc:
        raise ConnectorError(f"NCBI XML yanıtı ayrıştırılamadı: {exc}") from exc


def _text(element: ET.Element | None) -> str:
    return " ".join("".join(element.itertext()).split()) if element is not None else ""


class NCBIConnector(OfficialAPIConnector):
    """NCBI E-utilities connector for metadata and openly fetched records."""

    def __init__(
        self,
        *,
        api_key: str | None = None,
        email: str | None = None,
        tool: str = "bioprof",
        client: httpx.AsyncClient | None = None,
    ) -> None:
        super().__init__(
            base_url=EUTILS_BASE,
            provider_name="NCBI",
            requests_per_second=10 if api_key else 3,
            client=client,
        )
        self.api_key = api_key
        self.email = email
        self.tool = tool

    def _common(self) -> dict[str, str]:
        values = {"tool": self.tool}
        if self.api_key:
            values["api_key"] = self.api_key
        if self.email:
            values["email"] = self.email
        return values

    @staticmethod
    def _database(database: str) -> str:
        value = database.casefold()
        if value not in ALLOWED_DATABASES:
            raise ConnectorError(f"NCBI veritabanı izinli değil: {database}")
        return value

    async def search(
        self,
        query: str,
        *,
        database: str = "pubmed",
        limit: int = 20,
        cursor: int = 0,
    ) -> ConnectorPage:
        database = self._database(database)
        query = query.strip()
        if not query or len(query) > 2_000:
            raise ConnectorError("Sorgu 1-2000 karakter olmalıdır")
        limit = max(1, min(limit, 100))
        params: dict[str, Any] = {
            **self._common(),
            "db": database,
            "term": query,
            "retmode": "json",
            "retmax": limit,
            "retstart": max(0, cursor),
            "usehistory": "n",
        }
        response = await self._get("esearch.fcgi", params=params)
        payload = response.json().get("esearchresult", {})
        ids = [str(item) for item in payload.get("idlist", [])]
        records = await self.summaries(ids, database=database) if ids else []
        total = int(payload.get("count", 0))
        next_cursor = str(cursor + len(ids)) if cursor + len(ids) < total else None
        return ConnectorPage(
            records=records,
            next_cursor=next_cursor,
            total=total,
            provider="NCBI",
        )

    async def summaries(self, ids: list[str], *, database: str) -> list[RemoteRecord]:
        database = self._database(database)
        safe_ids = [item for item in ids if re.fullmatch(r"[A-Za-z0-9_.-]+", item)][:100]
        if not safe_ids:
            return []
        response = await self._get(
            "esummary.fcgi",
            params={
                **self._common(),
                "db": database,
                "id": ",".join(safe_ids),
                "retmode": "json",
            },
        )
        result = response.json().get("result", {})
        records: list[RemoteRecord] = []
        for record_id in result.get("uids", safe_ids):
            item = result.get(str(record_id), {})
            title = str(item.get("title") or item.get("caption") or f"{database}:{record_id}")
            authors = [
                str(author.get("name"))
                for author in item.get("authors", [])
                if isinstance(author, dict) and author.get("name")
            ]
            canonical = self._canonical_url(database, str(record_id))
            records.append(
                RemoteRecord(
                    id=str(record_id),
                    title=title,
                    url=canonical,
                    record_type=database,
                    authors=authors,
                    published_at=item.get("pubdate"),
                    identifiers={database: str(record_id)},
                    metadata={
                        key: item[key]
                        for key in ("source", "volume", "issue", "pages", "lang", "sortpubdate")
                        if key in item
                    },
                    provenance=Provenance(
                        provider="NCBI E-utilities",
                        canonical_url=canonical,
                        record_id=str(record_id),
                        database=database,
                        rights_status="metadata_only",
                        api_version="E-utilities",
                    ),
                )
            )
        return records

    async def fetch_pubmed_abstract(self, pmid: str) -> RemoteRecord:
        if not re.fullmatch(r"\d+", pmid):
            raise ConnectorError("PMID yalnız rakamlardan oluşmalıdır")
        response = await self._get(
            "efetch.fcgi",
            params={**self._common(), "db": "pubmed", "id": pmid, "retmode": "xml"},
            accept="application/xml",
        )
        root = _safe_xml(response.content)
        article = root.find(".//PubmedArticle")
        if article is None:
            raise ConnectorError(f"PubMed kaydı bulunamadı: {pmid}")
        title = _text(article.find(".//ArticleTitle")) or f"PubMed {pmid}"
        abstract = "\n\n".join(
            filter(None, (_text(node) for node in article.findall(".//Abstract/AbstractText")))
        )
        authors = []
        for author in article.findall(".//Author"):
            name = " ".join(
                filter(None, [_text(author.find("ForeName")), _text(author.find("LastName"))])
            )
            if name:
                authors.append(name)
        canonical = f"https://pubmed.ncbi.nlm.nih.gov/{pmid}/"
        return RemoteRecord(
            id=pmid,
            title=title,
            text=abstract,
            url=canonical,
            record_type="pubmed_abstract",
            authors=authors,
            identifiers={"pmid": pmid},
            provenance=Provenance(
                provider="NCBI PubMed",
                canonical_url=canonical,
                record_id=pmid,
                database="pubmed",
                rights_status="metadata_only",
                api_version="E-utilities",
            ),
        )

    @staticmethod
    def _canonical_url(database: str, record_id: str) -> str:
        routes = {
            "pubmed": f"https://pubmed.ncbi.nlm.nih.gov/{record_id}/",
            "pmc": f"https://pmc.ncbi.nlm.nih.gov/articles/PMC{record_id.removeprefix('PMC')}/",
            "gene": f"https://www.ncbi.nlm.nih.gov/gene/{record_id}",
            "protein": f"https://www.ncbi.nlm.nih.gov/protein/{record_id}",
            "taxonomy": f"https://www.ncbi.nlm.nih.gov/Taxonomy/Browser/wwwtax.cgi?id={record_id}",
            "clinvar": f"https://www.ncbi.nlm.nih.gov/clinvar/variation/{record_id}/",
        }
        return routes[database]


class PMCConnector(NCBIConnector):
    """PMC connector that only imports full text carrying an open licence."""

    async def search_open_access(self, query: str, *, limit: int = 20) -> ConnectorPage:
        return await self.search(f"({query}) AND open access[filter]", database="pmc", limit=limit)

    async def fetch_open_access_article(self, pmcid: str) -> RemoteRecord:
        normalized = pmcid.upper()
        if not re.fullmatch(r"PMC\d+", normalized):
            raise ConnectorError("PMCID 'PMC' ve rakamlardan oluşmalıdır")
        response = await self._get(
            "efetch.fcgi",
            params={**self._common(), "db": "pmc", "id": normalized, "retmode": "xml"},
            accept="application/xml",
        )
        root = _safe_xml(response.content)
        article = root.find(".//article") if root.tag != "article" else root
        if article is None:
            article = root.find(".")
        if article is None:
            raise ConnectorError(f"PMC article could not be parsed: {normalized}")
        license_element = article.find(".//license") if article is not None else None
        license_text = _text(license_element)
        license_url = None
        if license_element is not None:
            license_url = license_element.attrib.get("{http://www.w3.org/1999/xlink}href")
        marker_text = f"{license_text} {license_url or ''}".casefold()
        if not any(marker in marker_text for marker in OPEN_LICENSE_MARKERS):
            raise RightsError(
                "PMC tam metni açık bir lisans beyanı taşımıyor; yalnız metadata alınabilir"
            )
        title = _text(article.find(".//article-title")) or normalized
        body_parts: list[str] = []
        for section in article.findall(".//body/sec"):
            heading = _text(section.find("title"))
            paragraphs = [_text(node) for node in section.findall("./p")]
            text = "\n\n".join(filter(None, [heading, *paragraphs]))
            if text:
                body_parts.append(text)
        canonical = f"https://pmc.ncbi.nlm.nih.gov/articles/{normalized}/"
        return RemoteRecord(
            id=normalized,
            title=title,
            text="\n\n".join(body_parts),
            url=canonical,
            record_type="pmc_open_access_full_text",
            identifiers={"pmcid": normalized},
            metadata={"jats_xml": True},
            provenance=Provenance(
                provider="NCBI PubMed Central",
                canonical_url=canonical,
                record_id=normalized,
                database="pmc",
                license=license_text[:500] or "Open licence declared in article",
                license_url=license_url,
                rights_status="open_access",
                api_version="E-utilities/JATS",
            ),
        )
