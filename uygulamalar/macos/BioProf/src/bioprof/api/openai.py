"""OpenAI-compatible HTTP surface with injectable BioProf services.

Integration contract
--------------------
An application can either pass a service to ``create_openai_router(service)``
or set ``app.state.openai_service`` before including the parameterless router.
No global container is created at import time, which keeps tests and embedding
into another FastAPI app deterministic.
"""

from __future__ import annotations

import json
import re
import time
import uuid
from collections.abc import AsyncIterator, Awaitable, Callable, Mapping
from contextlib import AbstractAsyncContextManager, asynccontextmanager
from typing import Any, Literal, Protocol, runtime_checkable

from fastapi import APIRouter, Depends, File, Form, Request, UploadFile
from fastapi.responses import JSONResponse, Response, StreamingResponse
from pydantic import BaseModel, ConfigDict, Field

from bioprof.clinical_safety import is_personal_clinical_request, request_text
from bioprof.providers.base import (
    PrivacyViolationError,
    ProviderError,
    ProviderUnavailableError,
    Reranker,
    Synthesizer,
    Transcriber,
    UnsupportedCapabilityError,
)
from bioprof.providers.registry import ProviderRegistry

ProviderGuard = Callable[[str], AbstractAsyncContextManager[Any]]
NativeAsk = Callable[[str, Mapping[str, Any]], Awaitable[Mapping[str, Any]]]


@asynccontextmanager
async def _unguarded() -> AsyncIterator[None]:
    yield None


class ChatMessage(BaseModel):
    model_config = ConfigDict(extra="allow")

    role: Literal["system", "developer", "user", "assistant", "tool"]
    content: Any
    name: str | None = None
    tool_call_id: str | None = None


class ChatCompletionRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    model: str
    messages: list[ChatMessage]
    provider: str | None = None
    stream: bool = False
    temperature: float | None = None
    top_p: float | None = None
    max_tokens: int | None = Field(default=None, ge=1)
    max_completion_tokens: int | None = Field(default=None, ge=1)
    stop: str | list[str] | None = None
    tools: list[dict[str, Any]] | None = None
    tool_choice: Any = None
    response_format: dict[str, Any] | None = None
    seed: int | None = None
    user: str | None = None
    metadata: dict[str, Any] = Field(default_factory=dict)


class ResponsesRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    model: str
    input: Any
    provider: str | None = None
    instructions: str | None = None
    stream: bool = False
    max_output_tokens: int | None = Field(default=None, ge=1)
    temperature: float | None = None
    top_p: float | None = None
    tools: list[dict[str, Any]] | None = None
    tool_choice: Any = None
    text: dict[str, Any] | None = None
    previous_response_id: str | None = None
    metadata: dict[str, Any] = Field(default_factory=dict)


class EmbeddingRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    model: str
    input: str | list[str] | list[int] | list[list[int]]
    provider: str | None = None
    encoding_format: Literal["float", "base64"] = "float"
    dimensions: int | None = Field(default=None, ge=1)
    user: str | None = None


class RerankRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    model: str = "bge-reranker-v2-m3"
    query: str = Field(min_length=1)
    documents: list[str] = Field(min_length=1)
    provider: str | None = None
    top_n: int | None = Field(default=None, ge=1)
    return_documents: bool = True


class SpeechRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    model: str = "xtts-v2"
    input: str = Field(min_length=1, max_length=50_000)
    voice: str = "Murat"
    response_format: Literal["wav", "mp3", "opus", "aac", "flac", "pcm"] = "wav"
    speed: float = Field(default=1.0, ge=0.25, le=4.0)
    verify: bool = False


@runtime_checkable
class OpenAIAPIService(Protocol):
    async def list_models(self) -> list[dict[str, Any]]: ...

    async def chat(self, payload: Mapping[str, Any], *, trace_id: str) -> dict[str, Any]: ...

    def stream_chat(
        self, payload: Mapping[str, Any], *, trace_id: str
    ) -> AsyncIterator[dict[str, Any]]: ...

    async def responses(self, payload: Mapping[str, Any], *, trace_id: str) -> dict[str, Any]: ...

    def stream_responses(
        self, payload: Mapping[str, Any], *, trace_id: str
    ) -> AsyncIterator[dict[str, Any]]: ...

    async def embeddings(self, payload: Mapping[str, Any]) -> dict[str, Any]: ...

    async def rerank(self, payload: Mapping[str, Any]) -> dict[str, Any]: ...

    async def transcribe(
        self,
        data: bytes,
        *,
        filename: str,
        content_type: str | None,
        model: str | None,
        language: str | None,
        prompt: str | None,
        response_format: str,
    ) -> dict[str, Any]: ...

    async def speech(self, payload: Mapping[str, Any]) -> tuple[bytes, str]: ...


class ProviderOpenAIService:
    """Default OpenAI surface backed by an explicit ``ProviderRegistry``."""

    def __init__(
        self,
        registry: ProviderRegistry,
        *,
        default_provider: str = "local_evidence",
        transcriber: Transcriber | None = None,
        synthesizer: Synthesizer | None = None,
        reranker: Reranker | None = None,
        provider_guard: ProviderGuard | None = None,
        allow_remote_egress: bool = False,
        native_ask: NativeAsk | None = None,
    ) -> None:
        self.registry = registry
        self.default_provider = default_provider
        self.transcriber = transcriber
        self.synthesizer = synthesizer
        self.reranker_service = reranker
        self.provider_guard = provider_guard
        self.allow_remote_egress = allow_remote_egress
        self.native_ask = native_ask

    def _guard(self, provider_name: str) -> AbstractAsyncContextManager[Any]:
        return self.provider_guard(provider_name) if self.provider_guard else _unguarded()

    def _resolve(self, payload: Mapping[str, Any]) -> tuple[Any, dict[str, Any]]:
        forwarded = dict(payload)
        explicit_provider = forwarded.pop("provider", None)
        model = str(forwarded.get("model") or "")
        if explicit_provider:
            provider = self.registry.get(str(explicit_provider))
            if "/" in model and model.split("/", 1)[0] == explicit_provider:
                forwarded["model"] = model.split("/", 1)[1]
        else:
            provider, provider_model = self.registry.get_for_model(
                model, default_provider=self.default_provider
            )
            forwarded["model"] = provider_model
        if provider.requires_egress and not self.allow_remote_egress:
            raise PrivacyViolationError(provider.name)
        return provider, forwarded

    @staticmethod
    def _question(payload: Mapping[str, Any]) -> str:
        messages = payload.get("messages")
        if isinstance(messages, list):
            for message in reversed(messages):
                if not isinstance(message, Mapping) or message.get("role") != "user":
                    continue
                content = message.get("content", "")
                if isinstance(content, str):
                    return content.strip()
                if isinstance(content, list):
                    return " ".join(
                        str(part.get("text", "")).strip()
                        for part in content
                        if isinstance(part, Mapping)
                        and part.get("type") in {"text", "input_text"}
                    ).strip()
        input_value = payload.get("input")
        if isinstance(input_value, str):
            return input_value.strip()
        if isinstance(input_value, list):
            texts: list[str] = []
            for item in input_value:
                if isinstance(item, str):
                    texts.append(item)
                elif isinstance(item, Mapping):
                    content = item.get("content")
                    if isinstance(content, str):
                        texts.append(content)
                    elif isinstance(content, list):
                        texts.extend(
                            str(part.get("text", ""))
                            for part in content
                            if isinstance(part, Mapping)
                        )
            return " ".join(texts).strip()
        return ""

    def _native_request(
        self, payload: Mapping[str, Any]
    ) -> tuple[str, dict[str, Any]] | None:
        metadata = payload.get("metadata")
        if not isinstance(metadata, Mapping):
            return None
        notebook_value = metadata.get("bioprof_notebook_id")
        if notebook_value is None:
            return None
        if self.native_ask is None:
            raise UnsupportedCapabilityError("notebook RAG", "bioprof")
        notebook_id = str(notebook_value).strip()
        if not notebook_id or len(notebook_id) > 64:
            raise ProviderError("BioProf notebook kimliği geçersiz.", status_code=400)
        mode = str(metadata.get("bioprof_mode", "strict"))
        if mode not in {"strict", "hybrid", "research", "raw"}:
            raise ProviderError("BioProf cevap modu geçersiz.", status_code=400)
        question = self._question(payload)
        if not question:
            raise ProviderError("BioProf notebook sorusu boş olamaz.", status_code=400)

        provider, forwarded = self._resolve(payload)
        source_ids_value = metadata.get("bioprof_source_ids")
        source_ids: list[str] | None = None
        if source_ids_value is not None:
            if not isinstance(source_ids_value, list) or not all(
                isinstance(item, str) and 0 < len(item) <= 64 for item in source_ids_value
            ):
                raise ProviderError(
                    "bioprof_source_ids bir kimlik listesi olmalıdır.", status_code=400
                )
            if len(source_ids_value) > 1_000:
                raise ProviderError("En fazla 1000 kaynak seçilebilir.", status_code=400)
            source_ids = list(source_ids_value)
        return notebook_id, {
            "question": question,
            "mode": mode,
            "source_ids": source_ids,
            "provider": provider.name,
            "model": str(forwarded.get("model") or ""),
            "speak": False,
            "strict_voice_verification": False,
        }

    @staticmethod
    def _native_metadata(answer: Mapping[str, Any]) -> dict[str, Any]:
        citations = answer.get("citations")
        citation_ids = [
            str(item.get("id"))
            for item in citations
            if isinstance(citations, list) and isinstance(item, Mapping) and item.get("id")
        ] if isinstance(citations, list) else []
        return {
            "evidence_status": answer.get("evidence_status", "insufficient"),
            "citation_ids": citation_ids,
            "conversation_id": answer.get("conversation_id"),
            "native_trace_id": answer.get("trace_id"),
        }

    async def _ask_native(self, payload: Mapping[str, Any]) -> Mapping[str, Any] | None:
        native = self._native_request(payload)
        if native is None:
            return None
        notebook_id, request = native
        assert self.native_ask is not None
        return await self.native_ask(notebook_id, request)

    async def list_models(self) -> list[dict[str, Any]]:
        result: list[dict[str, Any]] = []
        now = int(time.time())
        for provider_name in self.registry.names():
            try:
                provider = self.registry.get(provider_name)
                capabilities = await provider.probe(active=False)
            except ProviderError:
                continue
            if not capabilities.available:
                continue
            for model in capabilities.models:
                result.append(
                    {
                        "id": f"{provider_name}/{model}",
                        "object": "model",
                        "created": now,
                        "owned_by": provider_name,
                    }
                )
        return result

    async def chat(self, payload: Mapping[str, Any], *, trace_id: str) -> dict[str, Any]:
        if is_personal_clinical_request(request_text(payload)):
            raise ProviderError(
                "Kişiye özel klinik karar istekleri BioProf API kapsamında değildir.",
                status_code=403,
            )
        native = await self._ask_native(payload)
        if native is not None:
            return {
                "id": f"chatcmpl-{trace_id}",
                "object": "chat.completion",
                "created": int(time.time()),
                "model": str(native.get("model") or payload.get("model") or "unknown"),
                "choices": [
                    {
                        "index": 0,
                        "message": {
                            "role": "assistant",
                            "content": str(native.get("answer_markdown") or ""),
                        },
                        "finish_reason": "stop",
                    }
                ],
                "usage": native.get("usage") or {},
                "system_fingerprint": f"bioprof:{native.get('provider', 'unknown')}",
                "bioprof": self._native_metadata(native),
            }
        provider, forwarded = self._resolve(payload)
        async with self._guard(provider.name):
            result = await provider.chat(forwarded)
        if result.raw:
            body = dict(result.raw)
            body.setdefault("model", result.model)
            return body
        return {
            "id": f"chatcmpl-{trace_id}",
            "object": "chat.completion",
            "created": int(time.time()),
            "model": result.model,
            "choices": [
                {
                    "index": 0,
                    "message": {"role": "assistant", "content": result.text},
                    "finish_reason": result.finish_reason,
                }
            ],
            "usage": result.usage,
            "system_fingerprint": f"bioprof:{result.provider}",
        }

    def stream_chat(
        self, payload: Mapping[str, Any], *, trace_id: str
    ) -> AsyncIterator[dict[str, Any]]:
        if is_personal_clinical_request(request_text(payload)):
            raise ProviderError(
                "Kişiye özel klinik karar istekleri BioProf API kapsamında değildir.",
                status_code=403,
            )
        native_request = self._native_request(payload)
        if native_request is not None:
            notebook_id, request = native_request

            async def native_events() -> AsyncIterator[dict[str, Any]]:
                assert self.native_ask is not None
                answer = await self.native_ask(notebook_id, request)
                yield {
                    "id": f"chatcmpl-{trace_id}",
                    "object": "chat.completion.chunk",
                    "created": int(time.time()),
                    "model": str(answer.get("model") or payload.get("model") or "unknown"),
                    "choices": [
                        {
                            "index": 0,
                            "delta": {"content": str(answer.get("answer_markdown") or "")},
                            "finish_reason": None,
                        }
                    ],
                }
                yield {
                    "id": f"chatcmpl-{trace_id}",
                    "object": "chat.completion.chunk",
                    "created": int(time.time()),
                    "model": str(answer.get("model") or payload.get("model") or "unknown"),
                    "choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}],
                    "bioprof": self._native_metadata(answer),
                }

            return native_events()
        provider, forwarded = self._resolve(payload)

        async def events() -> AsyncIterator[dict[str, Any]]:
            async with self._guard(provider.name):
                async for event in provider.stream_chat(forwarded):
                    if "choices" in event:
                        yield event
                        continue
                    yield {
                        "id": f"chatcmpl-{trace_id}",
                        "object": "chat.completion.chunk",
                        "created": int(time.time()),
                        "model": str(forwarded.get("model") or "unknown"),
                        "choices": [
                            {
                                "index": 0,
                                "delta": {"content": event.get("text", "")},
                                "finish_reason": event.get("finish_reason"),
                            }
                        ],
                    }

        return events()

    async def responses(self, payload: Mapping[str, Any], *, trace_id: str) -> dict[str, Any]:
        if is_personal_clinical_request(request_text(payload)):
            raise ProviderError(
                "Kişiye özel klinik karar istekleri BioProf API kapsamında değildir.",
                status_code=403,
            )
        native = await self._ask_native(payload)
        if native is not None:
            return {
                "id": f"resp_{trace_id}",
                "object": "response",
                "created_at": int(time.time()),
                "status": "completed",
                "model": str(native.get("model") or payload.get("model") or "unknown"),
                "output": [
                    {
                        "id": f"msg_{trace_id}",
                        "type": "message",
                        "role": "assistant",
                        "status": "completed",
                        "content": [
                            {
                                "type": "output_text",
                                "text": str(native.get("answer_markdown") or ""),
                                "annotations": [],
                            }
                        ],
                    }
                ],
                "usage": native.get("usage") or {},
                "bioprof": self._native_metadata(native),
            }
        provider, forwarded = self._resolve(payload)
        async with self._guard(provider.name):
            result = await provider.responses(forwarded)
        if result.raw:
            return dict(result.raw)
        return {
            "id": f"resp_{trace_id}",
            "object": "response",
            "created_at": int(time.time()),
            "status": result.status,
            "model": result.model,
            "output": [
                {
                    "id": f"msg_{trace_id}",
                    "type": "message",
                    "role": "assistant",
                    "status": "completed",
                    "content": [{"type": "output_text", "text": result.text, "annotations": []}],
                }
            ],
            "usage": result.usage,
        }

    def stream_responses(
        self, payload: Mapping[str, Any], *, trace_id: str
    ) -> AsyncIterator[dict[str, Any]]:
        if is_personal_clinical_request(request_text(payload)):
            raise ProviderError(
                "Kişiye özel klinik karar istekleri BioProf API kapsamında değildir.",
                status_code=403,
            )
        native_request = self._native_request(payload)
        if native_request is not None:
            notebook_id, request = native_request

            async def native_events() -> AsyncIterator[dict[str, Any]]:
                assert self.native_ask is not None
                answer = await self.native_ask(notebook_id, request)
                text = str(answer.get("answer_markdown") or "")
                yield {
                    "type": "response.output_text.delta",
                    "item_id": f"msg_{trace_id}",
                    "output_index": 0,
                    "content_index": 0,
                    "delta": text,
                }
                yield {
                    "type": "response.completed",
                    "response": {
                        "id": f"resp_{trace_id}",
                        "object": "response",
                        "status": "completed",
                        "model": str(answer.get("model") or payload.get("model") or "unknown"),
                        "bioprof": self._native_metadata(answer),
                    },
                }

            return native_events()
        provider, forwarded = self._resolve(payload)

        async def events() -> AsyncIterator[dict[str, Any]]:
            async with self._guard(provider.name):
                async for event in provider.stream_responses(forwarded):
                    yield event

        return events()

    async def embeddings(self, payload: Mapping[str, Any]) -> dict[str, Any]:
        provider, forwarded = self._resolve(payload)
        async with self._guard(provider.name):
            result = await provider.embeddings(forwarded)
        if result.raw:
            return dict(result.raw)
        return {
            "object": "list",
            "model": result.model,
            "data": [
                {"object": "embedding", "index": index, "embedding": vector}
                for index, vector in enumerate(result.vectors)
            ],
            "usage": result.usage,
        }

    async def rerank(self, payload: Mapping[str, Any]) -> dict[str, Any]:
        reranker = self.reranker_service
        if reranker is None:
            provider, _ = self._resolve(payload)
            if not isinstance(provider, Reranker):
                raise UnsupportedCapabilityError("rerank", provider.name)
            reranker = provider
        documents = [str(item) for item in payload.get("documents", [])]
        top_n_value = payload.get("top_n")
        top_n = int(top_n_value) if isinstance(top_n_value, int) else None
        results = await reranker.rerank(str(payload.get("query", "")), documents, top_n=top_n)
        if not payload.get("return_documents", True):
            results = [
                {key: value for key, value in result.items() if key != "document"}
                for result in results
            ]
        return {"id": f"rerank-{uuid.uuid4().hex}", "results": results}

    async def transcribe(
        self,
        data: bytes,
        *,
        filename: str,
        content_type: str | None,
        model: str | None,
        language: str | None,
        prompt: str | None,
        response_format: str,
    ) -> dict[str, Any]:
        if self.transcriber is None:
            raise UnsupportedCapabilityError("transcription", "bioprof")
        return await self.transcriber.transcribe(
            data,
            filename=filename,
            content_type=content_type,
            model=model,
            language=language,
            prompt=prompt,
            response_format=response_format,
        )

    async def speech(self, payload: Mapping[str, Any]) -> tuple[bytes, str]:
        if self.synthesizer is None:
            raise UnsupportedCapabilityError("speech", "bioprof")
        audio = await self.synthesizer.synthesize(
            str(payload.get("input", "")),
            voice=str(payload.get("voice", "Murat")),
            model=str(payload.get("model") or "xtts-v2"),
            response_format=str(payload.get("response_format", "wav")),
            speed=float(payload.get("speed", 1.0)),
            verify=bool(payload.get("verify", False)),
        )
        return audio.data, audio.media_type


_TRACE_PATTERN = re.compile(r"^[A-Za-z0-9._-]{1,128}$")


def _trace_id(request: Request) -> str:
    candidate = request.headers.get("X-BioProf-Trace-ID", "")
    return candidate if _TRACE_PATTERN.fullmatch(candidate) else uuid.uuid4().hex


def _error_response(error: ProviderError, trace_id: str) -> JSONResponse:
    return JSONResponse(
        status_code=error.status_code,
        content={
            "error": {
                "message": str(error),
                "type": error.code,
                "code": error.code,
                "trace_id": trace_id,
            }
        },
        headers={"X-BioProf-Trace-ID": trace_id},
    )


async def _bounded_audio(upload: UploadFile, *, maximum_bytes: int) -> bytes:
    output = bytearray()
    while True:
        chunk = await upload.read(min(1024 * 1024, maximum_bytes + 1 - len(output)))
        if not chunk:
            return bytes(output)
        output.extend(chunk)
        if len(output) > maximum_bytes:
            raise ProviderError(
                f"Ses dosyası sınırı {maximum_bytes // (1024 * 1024)} MiB.",
                status_code=413,
            )


async def _sse(events: AsyncIterator[dict[str, Any]], *, done: bool = True) -> AsyncIterator[str]:
    async for event in events:
        yield f"data: {json.dumps(event, ensure_ascii=False)}\n\n"
    if done:
        yield "data: [DONE]\n\n"


def create_openai_router(service: OpenAIAPIService | None = None) -> APIRouter:
    router = APIRouter(tags=["OpenAI compatible"])

    def resolve_service(request: Request) -> OpenAIAPIService:
        resolved = service or getattr(request.app.state, "openai_service", None)
        if resolved is None:
            raise ProviderUnavailableError("OpenAI uyumlu API servisi yapılandırılmadı.")
        return resolved

    ServiceDependency = Depends(resolve_service)

    @router.get("/v1/models")
    async def models(
        request: Request, current: OpenAIAPIService = ServiceDependency
    ) -> Response:
        trace_id = _trace_id(request)
        try:
            data = await current.list_models()
            return JSONResponse(
                {"object": "list", "data": data}, headers={"X-BioProf-Trace-ID": trace_id}
            )
        except ProviderError as error:
            return _error_response(error, trace_id)

    @router.post("/v1/chat/completions")
    async def chat_completions(
        body: ChatCompletionRequest,
        request: Request,
        current: OpenAIAPIService = ServiceDependency,
    ) -> Response:
        trace_id = _trace_id(request)
        payload = body.model_dump(exclude_none=True)
        try:
            if body.stream:
                events = current.stream_chat(payload, trace_id=trace_id)
                return StreamingResponse(
                    _sse(events),
                    media_type="text/event-stream",
                    headers={"X-BioProf-Trace-ID": trace_id, "Cache-Control": "no-cache"},
                )
            result = await current.chat(payload, trace_id=trace_id)
            return JSONResponse(result, headers={"X-BioProf-Trace-ID": trace_id})
        except ProviderError as error:
            return _error_response(error, trace_id)

    @router.post("/v1/responses")
    async def responses(
        body: ResponsesRequest,
        request: Request,
        current: OpenAIAPIService = ServiceDependency,
    ) -> Response:
        trace_id = _trace_id(request)
        payload = body.model_dump(exclude_none=True)
        try:
            if body.stream:
                events = current.stream_responses(payload, trace_id=trace_id)
                return StreamingResponse(
                    _sse(events, done=False),
                    media_type="text/event-stream",
                    headers={"X-BioProf-Trace-ID": trace_id, "Cache-Control": "no-cache"},
                )
            result = await current.responses(payload, trace_id=trace_id)
            return JSONResponse(result, headers={"X-BioProf-Trace-ID": trace_id})
        except ProviderError as error:
            return _error_response(error, trace_id)

    @router.post("/v1/embeddings")
    async def embeddings(
        body: EmbeddingRequest,
        request: Request,
        current: OpenAIAPIService = ServiceDependency,
    ) -> Response:
        trace_id = _trace_id(request)
        try:
            result = await current.embeddings(body.model_dump(exclude_none=True))
            return JSONResponse(result, headers={"X-BioProf-Trace-ID": trace_id})
        except ProviderError as error:
            return _error_response(error, trace_id)

    @router.post("/v1/rerank")
    async def rerank(
        body: RerankRequest,
        request: Request,
        current: OpenAIAPIService = ServiceDependency,
    ) -> Response:
        trace_id = _trace_id(request)
        try:
            result = await current.rerank(body.model_dump(exclude_none=True))
            return JSONResponse(result, headers={"X-BioProf-Trace-ID": trace_id})
        except ProviderError as error:
            return _error_response(error, trace_id)

    @router.post("/v1/audio/transcriptions")
    async def audio_transcriptions(
        request: Request,
        file: UploadFile = File(...),
        model: str | None = Form(default=None),
        language: str | None = Form(default=None),
        prompt: str | None = Form(default=None),
        response_format: str = Form(default="json"),
        current: OpenAIAPIService = ServiceDependency,
    ) -> Response:
        trace_id = _trace_id(request)
        if response_format not in {"json", "verbose_json", "text", "srt", "vtt"}:
            return _error_response(
                UnsupportedCapabilityError(f"transcription format: {response_format}", "bioprof"),
                trace_id,
            )
        try:
            settings = getattr(request.app.state, "settings", None)
            maximum_mb = int(getattr(settings, "max_audio_upload_mb", 100))
            data = await _bounded_audio(file, maximum_bytes=maximum_mb * 1024 * 1024)
            result = await current.transcribe(
                data,
                filename=file.filename or "audio.bin",
                content_type=file.content_type,
                model=model,
                language=language,
                prompt=prompt,
                response_format=response_format,
            )
            if response_format in {"text", "srt", "vtt"}:
                return Response(
                    content=str(result.get("text", "")),
                    media_type="text/plain; charset=utf-8",
                    headers={"X-BioProf-Trace-ID": trace_id},
                )
            return JSONResponse(result, headers={"X-BioProf-Trace-ID": trace_id})
        except ProviderError as error:
            return _error_response(error, trace_id)

    @router.post("/v1/audio/speech")
    async def audio_speech(
        body: SpeechRequest,
        request: Request,
        current: OpenAIAPIService = ServiceDependency,
    ) -> Response:
        trace_id = _trace_id(request)
        try:
            data, media_type = await current.speech(body.model_dump())
            return Response(
                content=data,
                media_type=media_type,
                headers={
                    "X-BioProf-Trace-ID": trace_id,
                    "X-AI-Generated-Voice": "true",
                },
            )
        except ProviderError as error:
            return _error_response(error, trace_id)

    return router


# Convenient import for applications that intentionally use app.state injection.
router = create_openai_router()


__all__ = [
    "OpenAIAPIService",
    "ProviderOpenAIService",
    "create_openai_router",
    "router",
]
