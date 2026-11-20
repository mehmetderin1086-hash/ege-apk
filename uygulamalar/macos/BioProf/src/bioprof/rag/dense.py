from __future__ import annotations

import hashlib
import importlib
import importlib.util
import math
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Protocol

import numpy as np
from sqlalchemy import select
from sqlalchemy.orm import Session

from bioprof.config import Settings
from bioprof.db.models import ChunkRecord, SourceRecord
from bioprof.domain.models import SourceStatus

_TERM = re.compile(r"[^\W_]+(?:[-./][^\W_]+)*", re.UNICODE)


@dataclass(slots=True, frozen=True)
class DenseHit:
    chunk_id: str
    score: float


class Embedder(Protocol):
    dimension: int

    def embed(self, texts: list[str]) -> list[list[float]]: ...


class DenseBackend(Protocol):
    def upsert_chunks(self, chunks: list[Any], *, notebook_id: str) -> None: ...

    def search(
        self,
        query: str,
        *,
        notebook_id: str,
        source_ids: set[str] | None,
        limit: int,
    ) -> list[DenseHit]: ...

    def delete_source(self, source_id: str) -> None: ...


class HashingEmbedder:
    """Small deterministic fallback; no model download and no data egress.

    It is intentionally an availability fallback rather than a replacement for
    BGE-M3. Word features plus character trigrams still provide useful matching for
    Turkish morphology, gene identifiers and biological sequences.
    """

    def __init__(self, dimension: int = 384) -> None:
        if dimension < 64:
            raise ValueError("dimension must be at least 64")
        self.dimension = dimension

    @staticmethod
    def _features(text: str) -> list[str]:
        normalized = text.casefold()
        terms = _TERM.findall(normalized)
        features = [f"w:{term}" for term in terms]
        compact = re.sub(r"\s+", " ", normalized)
        features.extend(
            f"c:{compact[index : index + 3]}" for index in range(max(0, len(compact) - 2))
        )
        return features

    def embed(self, texts: list[str]) -> list[list[float]]:
        result: list[list[float]] = []
        for text_value in texts:
            vector = np.zeros(self.dimension, dtype=np.float32)
            for feature in self._features(text_value):
                digest = hashlib.blake2b(feature.encode("utf-8"), digest_size=8).digest()
                number = int.from_bytes(digest, "little")
                index = number % self.dimension
                sign = 1.0 if number & (1 << 63) else -1.0
                vector[index] += sign
            norm = float(np.linalg.norm(vector))
            if norm:
                vector /= norm
            result.append(vector.tolist())
        return result


class SentenceTransformerEmbedder:
    """Lazy optional local embedder, suitable for BGE-M3 when installed."""

    def __init__(self, model_name: str = "BAAI/bge-m3") -> None:
        self.model_name = model_name
        self._model: Any | None = None
        self.dimension = 1024

    def _load(self) -> Any:
        if self._model is None:
            try:
                module = importlib.import_module("sentence_transformers")
            except ImportError as exc:
                raise RuntimeError(
                    "sentence-transformers optional dependency is not installed"
                ) from exc
            self._model = module.SentenceTransformer(self.model_name)
            self.dimension = int(self._model.get_sentence_embedding_dimension())
        return self._model

    def embed(self, texts: list[str]) -> list[list[float]]:
        model = self._load()
        values = model.encode(texts, normalize_embeddings=True, show_progress_bar=False)
        return np.asarray(values, dtype=np.float32).tolist()


_LOCAL_EMBEDDER: SentenceTransformerEmbedder | None = None


def build_embedder(settings: Settings) -> Embedder:
    """Return the configured embedder.

    When ``local_embeddings`` is enabled and sentence-transformers is installed,
    a shared BGE-M3 embedder is returned (loaded once). Otherwise the fast
    deterministic hashing fallback is used. The BGE-M3 instance is cached at
    module level so the model weights load a single time per process.
    """
    global _LOCAL_EMBEDDER
    if not settings.local_embeddings:
        return HashingEmbedder()
    if importlib.util.find_spec("sentence_transformers") is None:
        return HashingEmbedder()
    if _LOCAL_EMBEDDER is None or _LOCAL_EMBEDDER.model_name != settings.embedding_model:
        _LOCAL_EMBEDDER = SentenceTransformerEmbedder(settings.embedding_model)
    return _LOCAL_EMBEDDER


class DeterministicDenseBackend:
    """Database-scanning dense fallback used when Qdrant is not installed."""

    def __init__(self, session: Session, embedder: Embedder | None = None) -> None:
        self.session = session
        self.embedder = embedder or HashingEmbedder()

    def upsert_chunks(self, chunks: list[Any], *, notebook_id: str) -> None:
        # Embeddings are calculated on demand. This keeps the mandatory install
        # compact and makes the fallback reproducible across machines.
        del chunks, notebook_id

    def search(
        self,
        query: str,
        *,
        notebook_id: str,
        source_ids: set[str] | None,
        limit: int,
    ) -> list[DenseHit]:
        if not query.strip() or limit <= 0 or source_ids == set():
            return []
        statement = (
            select(ChunkRecord.id, ChunkRecord.text)
            .join(SourceRecord, SourceRecord.id == ChunkRecord.source_id)
            .where(
                SourceRecord.notebook_id == notebook_id,
                SourceRecord.status == SourceStatus.READY.value,
            )
        )
        if source_ids is not None:
            statement = statement.where(SourceRecord.id.in_(source_ids))
        rows = self.session.execute(statement).all()
        if not rows:
            return []
        query_vector = np.asarray(self.embedder.embed([query])[0], dtype=np.float32)
        text_vectors = np.asarray(self.embedder.embed([row.text for row in rows]), dtype=np.float32)
        scores = text_vectors @ query_vector
        count = min(limit, len(rows))
        best = (
            np.argpartition(-scores, count - 1)[:count]
            if count < len(rows)
            else np.arange(len(rows))
        )
        ordered = sorted(best.tolist(), key=lambda index: (-float(scores[index]), rows[index].id))
        return [DenseHit(chunk_id=rows[index].id, score=float(scores[index])) for index in ordered]

    def delete_source(self, source_id: str) -> None:
        del source_id


class QdrantDenseBackend:
    """Embedded Qdrant backend with an injected local embedding implementation."""

    collection_name = "bioprof_chunks"

    def __init__(
        self,
        settings: Settings,
        *,
        embedder: Embedder | None = None,
        path: Path | None = None,
    ) -> None:
        try:
            from qdrant_client import QdrantClient
            from qdrant_client.models import (
                Distance,
                VectorParams,
            )
        except ImportError as exc:
            raise RuntimeError("Qdrant için 'bioprof[rag]' kurulmalıdır.") from exc
        self.embedder = embedder or HashingEmbedder()
        vector_path = path or settings.vector_dir
        vector_path.mkdir(parents=True, exist_ok=True)
        self.client = QdrantClient(path=str(vector_path))
        if not self.client.collection_exists(self.collection_name):
            self.client.create_collection(
                collection_name=self.collection_name,
                vectors_config=VectorParams(size=self.embedder.dimension, distance=Distance.COSINE),
            )

    def upsert_chunks(self, chunks: list[Any], *, notebook_id: str) -> None:
        if not chunks:
            return
        from qdrant_client.models import PointStruct

        vectors = self.embedder.embed([chunk.text for chunk in chunks])
        points = [
            PointStruct(
                id=chunk.id,
                vector=vector,
                payload={
                    "chunk_id": chunk.id,
                    "source_id": chunk.source_id,
                    "notebook_id": notebook_id,
                },
            )
            for chunk, vector in zip(chunks, vectors, strict=True)
        ]
        self.client.upsert(collection_name=self.collection_name, points=points, wait=True)

    def search(
        self,
        query: str,
        *,
        notebook_id: str,
        source_ids: set[str] | None,
        limit: int,
    ) -> list[DenseHit]:
        if not query.strip() or limit <= 0 or source_ids == set():
            return []
        from qdrant_client.models import (
            FieldCondition,
            Filter,
            MatchAny,
            MatchValue,
        )

        conditions = [FieldCondition(key="notebook_id", match=MatchValue(value=notebook_id))]
        if source_ids is not None:
            conditions.append(
                FieldCondition(key="source_id", match=MatchAny(any=sorted(source_ids)))
            )
        query_vector = self.embedder.embed([query])[0]
        result = self.client.query_points(
            collection_name=self.collection_name,
            query=query_vector,
            query_filter=Filter(must=conditions),
            limit=limit,
            with_payload=True,
        )
        points = result.points if hasattr(result, "points") else result
        hits: list[DenseHit] = []
        for point in points:
            # query_points bazı istemci sürümlerinde (id, skor) çifti de dönebilir;
            # payload'sız nokta atlanır, tip güvenliği isinstance'a bağlanır.
            payload = getattr(point, "payload", None) or {}
            kimlik = payload.get("chunk_id", getattr(point, "id", None))
            skor = getattr(point, "score", None)
            if kimlik is None or skor is None:
                continue
            hits.append(DenseHit(chunk_id=str(kimlik), score=float(skor)))
        return hits

    def delete_source(self, source_id: str) -> None:
        from qdrant_client.models import (
            FieldCondition,
            Filter,
            FilterSelector,
            MatchValue,
        )

        self.client.delete(
            collection_name=self.collection_name,
            points_selector=FilterSelector(
                filter=Filter(
                    must=[FieldCondition(key="source_id", match=MatchValue(value=source_id))]
                )
            ),
            wait=True,
        )

    def close(self) -> None:
        self.client.close()


def logistic_score(value: float) -> float:
    if value >= 0:
        factor = math.exp(-min(value, 80.0))
        return 1.0 / (1.0 + factor)
    factor = math.exp(max(value, -80.0))
    return factor / (1.0 + factor)
