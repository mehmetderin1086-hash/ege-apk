"""A safe deterministic placeholder for source-only local answers."""

from __future__ import annotations

from collections.abc import AsyncIterator, Mapping, Sequence
from typing import Any

from bioprof.domain.models import ProviderCapabilities
from bioprof.providers.base import (
    ChatResult,
    EmbeddingResult,
    ProviderError,
    ResponseResult,
)
from bioprof.rag.dense import HashingEmbedder


def _last_user_text(messages: Sequence[Mapping[str, Any]]) -> str:
    for message in reversed(messages):
        if message.get("role") != "user":
            continue
        content = message.get("content", "")
        if isinstance(content, str):
            return content
        if isinstance(content, list):
            return " ".join(
                str(part.get("text", ""))
                for part in content
                if isinstance(part, Mapping) and part.get("type") in {"text", "input_text"}
            )
    return ""


class LocalEvidenceProvider:
    """Never invents medical content; it renders evidence supplied by the RAG core.

    The parent application may replace this with an MLX/llama.cpp provider while
    keeping it as the strict-mode failure-safe.
    """

    name = "local_evidence"
    requires_egress = False

    def __init__(self) -> None:
        self._embedder = HashingEmbedder()

    async def probe(self, *, active: bool = False) -> ProviderCapabilities:
        del active
        return ProviderCapabilities(
            name=self.name,
            available=True,
            models=["bioprof-evidence", "bioprof-hashing-384"],
            chat=True,
            responses=True,
            streaming=True,
            embeddings=True,
            details={"mode": "deterministic-source-only"},
        )

    def _answer(self, payload: Mapping[str, Any]) -> str:
        evidence = payload.get("evidence") or payload.get("metadata", {}).get("evidence", [])
        question = _last_user_text(payload.get("messages", []))
        if not evidence:
            return (
                "Bu soruyu seçili kaynaklarda destekleyecek yeterli kanıt bulamadım. "
                "Yeni bir kaynak ekleyin veya kaynak seçimini genişletin."
            )
        snippets: list[str] = []
        for index, item in enumerate(evidence[:10], 1):
            if isinstance(item, Mapping):
                text = str(item.get("text", "")).strip()
                label = str(item.get("label", f"S{index}"))
            else:
                text = str(item).strip()
                label = f"S{index}"
            if text:
                snippets.append(f"{text} [{label}]")
        if not snippets:
            return "Seçili kaynaklarda kullanılabilir bir kanıt metni bulunamadı."
        prefix = f"Soru: {question}\n\n" if question else ""
        return prefix + "\n\n".join(snippets)

    async def chat(self, payload: Mapping[str, Any]) -> ChatResult:
        model = str(payload.get("model") or "bioprof-evidence")
        text = self._answer(payload)
        return ChatResult(text=text, model=model, provider=self.name)

    async def responses(self, payload: Mapping[str, Any]) -> ResponseResult:
        chat_payload = dict(payload)
        if "messages" not in chat_payload:
            input_value = payload.get("input", "")
            chat_payload["messages"] = [{"role": "user", "content": input_value}]
        result = await self.chat(chat_payload)
        return ResponseResult(text=result.text, model=result.model, provider=self.name)

    async def embeddings(self, payload: Mapping[str, Any]) -> EmbeddingResult:
        input_value = payload.get("input")
        if isinstance(input_value, str):
            texts = [input_value]
        elif isinstance(input_value, Sequence) and not isinstance(
            input_value, (str, bytes, bytearray)
        ):
            texts = [str(item) for item in input_value]
        else:
            raise ProviderError(
                "Embedding girdisi metin veya metin listesi olmalıdır.", status_code=400
            )
        if not texts or any(not text.strip() for text in texts):
            raise ProviderError("Embedding girdisi boş olamaz.", status_code=400)
        vectors = self._embedder.embed(texts)
        prompt_tokens = sum(len(text.split()) for text in texts)
        return EmbeddingResult(
            vectors=vectors,
            model="bioprof-hashing-384",
            provider=self.name,
            usage={"prompt_tokens": prompt_tokens, "total_tokens": prompt_tokens},
        )

    async def _chat_events(self, payload: Mapping[str, Any]) -> AsyncIterator[dict[str, Any]]:
        result = await self.chat(payload)
        yield {"text": result.text, "finish_reason": None}
        yield {"text": "", "finish_reason": result.finish_reason}

    def stream_chat(self, payload: Mapping[str, Any]) -> AsyncIterator[dict[str, Any]]:
        return self._chat_events(payload)

    async def _response_events(self, payload: Mapping[str, Any]) -> AsyncIterator[dict[str, Any]]:
        result = await self.responses(payload)
        yield {"type": "response.output_text.delta", "delta": result.text}
        yield {"type": "response.completed", "response": result.raw}

    def stream_responses(self, payload: Mapping[str, Any]) -> AsyncIterator[dict[str, Any]]:
        return self._response_events(payload)

    async def rerank(
        self, query: str, documents: Sequence[str], *, top_n: int | None = None
    ) -> list[dict[str, Any]]:
        # A transparent lexical fallback for bootstrapping/tests, not a claim that
        # the BGE reranker is loaded.
        terms = {term.casefold() for term in query.split() if term.strip()}
        scored: list[dict[str, Any]] = []
        for index, document in enumerate(documents):
            words = {term.casefold() for term in document.split()}
            score = len(terms & words) / max(len(terms), 1)
            scored.append({"index": index, "relevance_score": score, "document": document})
        scored.sort(
            key=lambda item: (-float(item["relevance_score"]), int(item["index"]))
        )
        return scored[: top_n or len(scored)]
