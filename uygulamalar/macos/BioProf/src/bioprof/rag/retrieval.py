from __future__ import annotations

import math
import re
from collections import defaultdict
from dataclasses import dataclass
from typing import Protocol

from sqlalchemy import select, text
from sqlalchemy.orm import Session

from bioprof.config import Settings
from bioprof.db.models import ChunkRecord, SourceRecord
from bioprof.domain.models import Evidence, SourceStatus
from bioprof.rag.citations import make_anchor
from bioprof.rag.dense import (
    DenseBackend,
    DeterministicDenseBackend,
    Embedder,
    build_embedder,
    logistic_score,
)

_QUERY_TERM = re.compile(r"[^\W_]+(?:[-./][^\W_]+)*", re.UNICODE)


class Reranker(Protocol):
    def rerank(self, query: str, texts: list[str]) -> list[float]: ...


class CrossEncoderReranker:
    """Lazy optional bge-reranker-v2-m3 adapter."""

    def __init__(self, model_name: str = "BAAI/bge-reranker-v2-m3") -> None:
        self.model_name = model_name
        self._model: object | None = None

    def _load(self) -> object:
        if self._model is None:
            try:
                from sentence_transformers import CrossEncoder
            except ImportError as exc:
                raise RuntimeError(
                    "sentence-transformers optional dependency is not installed"
                ) from exc
            self._model = CrossEncoder(self.model_name)
        return self._model

    def rerank(self, query: str, texts: list[str]) -> list[float]:
        model = self._load()
        values = model.predict([(query, text_value) for text_value in texts])  # type: ignore[attr-defined]
        return [float(value) for value in values]


@dataclass(slots=True)
class _Candidate:
    chunk_id: str
    rrf_score: float = 0.0
    channels: set[str] | None = None
    rerank_score: float | None = None
    dense_score: float | None = None

    def __post_init__(self) -> None:
        if self.channels is None:
            self.channels = set()


def _fts_expression(query: str) -> str:
    terms: list[str] = []
    seen: set[str] = set()
    for term in _QUERY_TERM.findall(query):
        normalized = term.casefold()
        if len(normalized) == 1 and not normalized.isdigit():
            continue
        if normalized not in seen:
            terms.append('"' + normalized.replace('"', '""') + '"')
            seen.add(normalized)
        if len(terms) >= 24:
            break
    return " OR ".join(terms)


class HybridRetriever:
    def __init__(
        self,
        settings: Settings,
        session: Session,
        *,
        dense_backend: DenseBackend | None = None,
        reranker: Reranker | None = None,
        rrf_k: int = 60,
        max_per_source: int = 3,
        embedder: Embedder | None = None,
    ) -> None:
        self.settings = settings
        self.session = session
        # The configured embedder must survive the Qdrant fallback. Building
        # ``DeterministicDenseBackend(session)`` with no embedder silently
        # downgraded a BGE-M3 deployment to the 384-dim hashing stand-in: the
        # answers got worse and nothing anywhere said so.
        self.dense_backend = dense_backend or DeterministicDenseBackend(
            session, embedder=embedder or build_embedder(settings)
        )
        self.reranker = reranker
        self.rrf_k = rrf_k
        self.max_per_source = max_per_source

    def _lexical(
        self,
        notebook_id: str,
        query: str,
        *,
        source_ids: set[str] | None,
        limit: int,
    ) -> list[tuple[str, float]]:
        expression = _fts_expression(query)
        if not expression or source_ids == set():
            return []
        rows = self.session.execute(
            text(
                """
                SELECT chunk_id, bm25(chunk_fts, 0.0, 0.0, 0.0, 3.0, 1.0, 5.0) AS rank
                FROM chunk_fts
                WHERE chunk_fts MATCH :query AND notebook_id = :notebook_id
                ORDER BY rank ASC
                LIMIT :scan_limit
                """
            ),
            {
                "query": expression,
                "notebook_id": notebook_id,
                "scan_limit": max(limit * 5, limit),
            },
        ).all()
        if source_ids is None:
            return [(row.chunk_id, float(row.rank)) for row in rows[:limit]]
        if not rows:
            return []
        source_rows = self.session.execute(
            select(ChunkRecord.id, ChunkRecord.source_id).where(
                ChunkRecord.id.in_([row.chunk_id for row in rows])
            )
        ).all()
        chunk_sources: dict[str, str] = {str(row.id): str(row.source_id) for row in source_rows}
        return [
            (row.chunk_id, float(row.rank))
            for row in rows
            if chunk_sources.get(row.chunk_id) in source_ids
        ][:limit]

    def search(
        self,
        notebook_id: str,
        query: str,
        *,
        source_ids: list[str] | set[str] | None = None,
        limit: int | None = None,
    ) -> list[Evidence]:
        query = query.strip()
        if not query:
            return []
        selected_sources = set(source_ids) if source_ids is not None else None
        if selected_sources == set():
            return []
        candidate_limit = max(1, self.settings.retrieval_candidates)
        lexical = self._lexical(
            notebook_id,
            query,
            source_ids=selected_sources,
            limit=candidate_limit,
        )
        dense = self.dense_backend.search(
            query,
            notebook_id=notebook_id,
            source_ids=selected_sources,
            limit=candidate_limit,
        )
        candidates: dict[str, _Candidate] = {}
        dense = [item for item in dense if item.score >= self.settings.minimum_dense_score]
        for channel, ranked_ids in (
            ("bm25", [item[0] for item in lexical]),
            ("dense", [item.chunk_id for item in dense]),
        ):
            for rank, chunk_id in enumerate(ranked_ids, start=1):
                candidate = candidates.setdefault(chunk_id, _Candidate(chunk_id=chunk_id))
                candidate.rrf_score += 1.0 / (self.rrf_k + rank)
                assert candidate.channels is not None
                candidate.channels.add(channel)
        for hit in dense:
            candidates[hit.chunk_id].dense_score = hit.score
        if not candidates:
            return []

        ordered = sorted(candidates.values(), key=lambda item: (-item.rrf_score, item.chunk_id))
        rerank_limit = min(max(1, self.settings.rerank_candidates), len(ordered))
        ordered = ordered[:rerank_limit]
        rows = self.session.execute(
            select(ChunkRecord, SourceRecord)
            .join(SourceRecord, SourceRecord.id == ChunkRecord.source_id)
            .where(
                ChunkRecord.id.in_([candidate.chunk_id for candidate in ordered]),
                SourceRecord.notebook_id == notebook_id,
                SourceRecord.status == SourceStatus.READY.value,
            )
        ).all()
        by_id = {chunk.id: (chunk, source) for chunk, source in rows}
        ordered = [candidate for candidate in ordered if candidate.chunk_id in by_id]
        reranker_used = False
        if self.reranker is not None and ordered:
            try:
                scores = self.reranker.rerank(
                    query, [by_id[candidate.chunk_id][0].text for candidate in ordered]
                )
                if len(scores) != len(ordered):
                    raise ValueError("reranker returned an unexpected score count")
                for candidate, score in zip(ordered, scores, strict=True):
                    candidate.rerank_score = score
                    assert candidate.channels is not None
                    candidate.channels.add("reranker")
                ordered.sort(
                    key=lambda item: (
                        -(item.rerank_score if item.rerank_score is not None else -math.inf),
                        -item.rrf_score,
                        item.chunk_id,
                    )
                )
                reranker_used = True
            except Exception:
                # Optional model failures must leave a deterministic, inspectable RRF
                # path rather than taking down source-grounded answering.
                ordered.sort(key=lambda item: (-item.rrf_score, item.chunk_id))

        requested = (
            self.settings.max_evidence
            if limit is None
            else min(max(1, limit), self.settings.rerank_candidates)
        )
        # Kaynak başına tavan çeşitlilik içindir: bir kaynak tüm yanıtı
        # doldurmasın. Ama sabit bir tavan, tek kaynaklı bir defterde kanıt
        # sayısını 3'te kilitliyordu — istenen limit ne olursa olsun. Tavan
        # aday havuzundaki kaynak sayısına göre ölçeklenir: çok kaynak varsa
        # denge korunur, tek kaynak varsa istenen kadar kanıt gelir.
        distinct_sources = len({by_id[candidate.chunk_id][1].id for candidate in ordered})
        per_source_cap = max(
            self.max_per_source, math.ceil(requested / max(1, distinct_sources))
        )
        source_counts: dict[str, int] = defaultdict(int)
        selected: list[_Candidate] = []
        for candidate in ordered:
            _chunk, source = by_id[candidate.chunk_id]
            if source_counts[source.id] >= per_source_cap:
                continue
            source_counts[source.id] += 1
            selected.append(candidate)
            if len(selected) >= requested:
                break
        top_rrf = max((candidate.rrf_score for candidate in selected), default=1.0)
        evidence: list[Evidence] = []
        for index, candidate in enumerate(selected, start=1):
            chunk, source = by_id[candidate.chunk_id]
            if reranker_used and candidate.rerank_score is not None:
                score = logistic_score(candidate.rerank_score)
            else:
                score = candidate.rrf_score / top_rrf if top_rrf else 0.0
            evidence.append(
                Evidence(
                    label=f"S{index}",
                    text=chunk.text,
                    score=max(0.0, min(1.0, score)),
                    anchor=make_anchor(chunk, source),
                    retrieval_channels=sorted(candidate.channels or ()),
                )
            )
        return evidence
