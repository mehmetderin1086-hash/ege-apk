from __future__ import annotations

import json

from sqlalchemy import select
from sqlalchemy.orm import Session

from bioprof.db.models import ChunkRecord, SourceRecord
from bioprof.domain.models import AnchorType, CitationAnchor


def _anchor_type(chunk: ChunkRecord) -> AnchorType:
    if chunk.timestamp_start is not None or chunk.timestamp_end is not None:
        return AnchorType.TIME
    if chunk.sequence_start is not None or chunk.sequence_end is not None:
        return AnchorType.SEQUENCE
    if chunk.slide is not None:
        return AnchorType.SLIDE
    if chunk.page is not None:
        return AnchorType.PAGE
    if chunk.section and chunk.section.casefold().startswith(("tablo", "table", "satır")):
        return AnchorType.TABLE
    return AnchorType.TEXT


def _bbox(value: str | None) -> tuple[float, float, float, float] | None:
    if not value:
        return None
    try:
        decoded = json.loads(value)
        if not isinstance(decoded, list) or len(decoded) != 4:
            return None
        return tuple(float(item) for item in decoded)  # type: ignore[return-value]
    except (TypeError, ValueError, json.JSONDecodeError):
        return None


def make_anchor(chunk: ChunkRecord, source: SourceRecord) -> CitationAnchor:
    return CitationAnchor(
        id=chunk.id,
        source_id=source.id,
        source_sha256=source.sha256,
        chunk_id=chunk.id,
        anchor_type=_anchor_type(chunk),
        page=chunk.page,
        slide=chunk.slide,
        bbox=_bbox(chunk.bbox_json),
        timestamp_start=chunk.timestamp_start,
        timestamp_end=chunk.timestamp_end,
        sequence_start=chunk.sequence_start,
        sequence_end=chunk.sequence_end,
        section=chunk.section,
        quote=chunk.text,
        source_title=source.title,
        source_uri=source.source_uri,
    )


class CitationResolver:
    def __init__(self, session: Session) -> None:
        self.session = session

    def resolve(self, citation_id: str) -> CitationAnchor | None:
        row = self.session.execute(
            select(ChunkRecord, SourceRecord)
            .join(SourceRecord, SourceRecord.id == ChunkRecord.source_id)
            .where(ChunkRecord.id == citation_id)
        ).first()
        if row is None:
            return None
        chunk, source = row
        return make_anchor(chunk, source)

    def resolve_many(self, citation_ids: list[str]) -> list[CitationAnchor]:
        if not citation_ids:
            return []
        rows = self.session.execute(
            select(ChunkRecord, SourceRecord)
            .join(SourceRecord, SourceRecord.id == ChunkRecord.source_id)
            .where(ChunkRecord.id.in_(citation_ids))
        ).all()
        by_id = {chunk.id: make_anchor(chunk, source) for chunk, source in rows}
        return [by_id[citation_id] for citation_id in citation_ids if citation_id in by_id]
