"""Anthropic Messages API giriş adaptörü (`/v1/messages`).

Claude Code ve Anthropic SDK istemcilerinin proxy'e doğrudan bağlanmasını sağlar.
İstek/yanıt Anthropic biçimindedir; backend (model'e göre) Gemini/Claude/Codex
olabilir. `ClaudeTranslator`'ın (giden) ters yönünü uygular.
"""

from __future__ import annotations

import json
import uuid

from ...core.canonical import (
    CanonicalChunk,
    CanonicalMessage,
    CanonicalRequest,
    CanonicalResponse,
    OutputFormat,
    TextPart,
    ToolCall,
    ToolChoice,
    ToolSpec,
)
from ..base import UnsupportedTranslationCapability
from ..media import media_from_base64, media_from_file, media_from_url
from .base import StreamCtx, WireAdapter

# canonical finish_reason -> Anthropic stop_reason (ClaudeTranslator._STOP_MAP tersi).
_FINISH_TO_STOP = {
    "stop": "end_turn",
    "length": "max_tokens",
    "tool_calls": "tool_use",
}
_DEFAULT_MAX_TOKENS = 4096


def _event(event_type: str, data: dict) -> bytes:
    body = json.dumps(data, ensure_ascii=False).encode("utf-8")
    return b"event: " + event_type.encode() + b"\ndata: " + body + b"\n\n"


def _blocks_text(content) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        chunks: list[str] = []
        for block in content:
            if not isinstance(block, dict):
                raise UnsupportedTranslationCapability(
                    "anthropic", "content_part", "content blocks must be objects"
                )
            if block.get("type") != "text":
                raise UnsupportedTranslationCapability(
                    "anthropic",
                    f"content_part.{block.get('type') or 'unknown'}",
                    "only text is supported in this content position",
                )
            chunks.append(block.get("text", ""))
        return "".join(chunks)
    if content is None:
        return ""
    raise UnsupportedTranslationCapability(
        "anthropic", "content_part", "content must be a string or an array"
    )


class AnthropicAdapter(WireAdapter):
    name = "anthropic"

    # --- istek: Anthropic -> canonical ---

    def parse_request(
        self, body: dict, *, path_model: str | None = None, stream: bool = False
    ) -> CanonicalRequest:
        messages: list[CanonicalMessage] = []

        system = body.get("system")
        if system:
            messages.append(
                CanonicalMessage(role="system", content=[TextPart(text=_blocks_text(system))])
            )

        for m in body.get("messages", []):
            role = m.get("role", "user")
            content = m.get("content")
            if isinstance(content, str):
                if content:
                    messages.append(
                        CanonicalMessage(role=role, content=[TextPart(text=content)])
                    )
                continue

            parts: list = []
            tool_calls = []
            for block in content or []:
                if not isinstance(block, dict):
                    raise UnsupportedTranslationCapability(
                        "anthropic", "content_part", "content blocks must be objects"
                    )
                btype = block.get("type")
                if btype == "text":
                    parts.append(TextPart(text=block.get("text", "")))
                elif btype == "image":
                    src = block.get("source")
                    if not isinstance(src, dict):
                        raise UnsupportedTranslationCapability(
                            "anthropic", "image", "image source must be an object"
                        )
                    if src.get("type") == "base64":
                        parts.append(
                            media_from_base64(
                                src.get("data"),
                                src.get("media_type"),
                                target="anthropic",
                            )
                        )
                    elif src.get("type") == "url":
                        parts.append(
                            media_from_url(src.get("url"), target="anthropic")
                        )
                    elif src.get("type") == "file":
                        parts.append(
                            media_from_file(
                                src.get("file_id"),
                                provider="anthropic",
                                mime_type=src.get("media_type"),
                                target="anthropic",
                            )
                        )
                    else:
                        raise UnsupportedTranslationCapability(
                            "anthropic",
                            "image",
                            f"unsupported image source: {src.get('type')}",
                        )
                elif btype == "tool_use":
                    tool_calls.append(
                        ToolCall(
                            id=block.get("id", ""),
                            name=block.get("name", ""),
                            arguments=json.dumps(block.get("input", {}), ensure_ascii=False),
                            extra_content=(
                                block.get("extra_content")
                                if isinstance(block.get("extra_content"), dict)
                                else {}
                            ),
                        )
                    )
                elif btype == "tool_result":
                    # Ayrı bir canonical "tool" mesajı olarak eklenir.
                    messages.append(
                        CanonicalMessage(
                            role="tool",
                            tool_call_id=block.get("tool_use_id"),
                            content=[TextPart(text=_blocks_text(block.get("content")))],
                        )
                    )
                else:
                    raise UnsupportedTranslationCapability(
                        "anthropic",
                        f"content_part.{btype or 'unknown'}",
                        "content block type is not supported",
                    )
            if parts or tool_calls:
                messages.append(
                    CanonicalMessage(role=role, content=parts, tool_calls=tool_calls)
                )

        tools = [
            ToolSpec(
                name=t.get("name", ""),
                description=t.get("description"),
                parameters=t.get("input_schema", {}) or {},
                strict=t.get("strict"),
            )
            for t in body.get("tools", []) or []
        ]

        stop = body.get("stop_sequences")
        raw_choice = body.get("tool_choice")
        tool_choice: ToolChoice | None = None
        parallel_tool_calls: bool | None = None
        if raw_choice is not None:
            if not isinstance(raw_choice, dict):
                raise ValueError("Anthropic tool_choice must be an object")
            choice_type = raw_choice.get("type", "auto")
            mode = "required" if choice_type == "any" else choice_type
            tool_choice = ToolChoice(mode=mode, name=raw_choice.get("name"))
            if "disable_parallel_tool_use" in raw_choice:
                parallel_tool_calls = not bool(raw_choice["disable_parallel_tool_use"])

        output_format: OutputFormat | None = None
        raw_format = (body.get("output_config") or {}).get("format")
        if raw_format is not None:
            if not isinstance(raw_format, dict) or raw_format.get("type") != "json_schema":
                raise ValueError("Anthropic output_config.format must be json_schema")
            output_format = OutputFormat(
                type="json_schema",
                json_schema=raw_format.get("schema") or {},
                strict=True,
            )
        return CanonicalRequest(
            model=body.get("model", ""),
            messages=messages,
            tools=tools,
            tool_choice=tool_choice,
            parallel_tool_calls=parallel_tool_calls,
            output_format=output_format,
            temperature=body.get("temperature"),
            top_p=body.get("top_p"),
            max_tokens=body.get("max_tokens", _DEFAULT_MAX_TOKENS),
            stop=stop,
            stream=bool(body.get("stream", stream)),
        )

    # --- yanıt: canonical -> Anthropic ---

    def build_response(self, resp: CanonicalResponse, *, client_model: str) -> dict:
        content: list[dict] = []
        text = resp.message.text()
        if text:
            content.append({"type": "text", "text": text})
        for tc in resp.message.tool_calls:
            try:
                inp = json.loads(tc.arguments) if tc.arguments else {}
            except json.JSONDecodeError:
                inp = {}
            block = {"type": "tool_use", "id": tc.id, "name": tc.name, "input": inp}
            if tc.extra_content:
                block["extra_content"] = tc.extra_content
            content.append(block)
        return {
            "id": _msg_id(resp.id),
            "type": "message",
            "role": "assistant",
            "model": client_model,
            "content": content,
            "stop_reason": _FINISH_TO_STOP.get(resp.finish_reason, "end_turn"),
            "stop_sequence": None,
            "usage": {
                "input_tokens": resp.usage.prompt_tokens,
                "output_tokens": resp.usage.completion_tokens,
            },
        }

    # --- streaming: Anthropic olay dizisi (durum makinesi) ---

    def stream_prelude(self, ctx: StreamCtx) -> list[bytes]:
        ctx.state.update(next_index=0, open_index=None, open_kind=None, tool_map={})
        msg = {
            "type": "message_start",
            "message": {
                "id": _msg_id(ctx.resp_id),
                "type": "message",
                "role": "assistant",
                "model": ctx.client_model,
                "content": [],
                "stop_reason": None,
                "stop_sequence": None,
                "usage": {"input_tokens": 0, "output_tokens": 0},
            },
        }
        return [_event("message_start", msg)]

    def stream_chunk(self, chunk: CanonicalChunk, ctx: StreamCtx) -> list[bytes]:
        frames: list[bytes] = []

        if chunk.delta_text:
            if ctx.state.get("open_kind") != "text":
                frames += self._close_open(ctx)
                idx = ctx.state["next_index"]
                ctx.state["next_index"] += 1
                ctx.state["open_index"] = idx
                ctx.state["open_kind"] = "text"
                frames.append(
                    _event(
                        "content_block_start",
                        {
                            "type": "content_block_start",
                            "index": idx,
                            "content_block": {"type": "text", "text": ""},
                        },
                    )
                )
            frames.append(
                _event(
                    "content_block_delta",
                    {
                        "type": "content_block_delta",
                        "index": ctx.state["open_index"],
                        "delta": {"type": "text_delta", "text": chunk.delta_text},
                    },
                )
            )

        if chunk.delta_tool_call is not None:
            tc = chunk.delta_tool_call
            tool_map = ctx.state["tool_map"]
            if tc.index not in tool_map:
                frames += self._close_open(ctx)
                idx = ctx.state["next_index"]
                ctx.state["next_index"] += 1
                tool_map[tc.index] = idx
                ctx.state["open_index"] = idx
                ctx.state["open_kind"] = "tool"
                content_block = {
                    "type": "tool_use",
                    "id": tc.id or "",
                    "name": tc.name or "",
                    "input": {},
                }
                if tc.extra_content:
                    content_block["extra_content"] = tc.extra_content
                frames.append(
                    _event(
                        "content_block_start",
                        {
                            "type": "content_block_start",
                            "index": idx,
                            "content_block": content_block,
                        },
                    )
                )
            if tc.arguments:
                frames.append(
                    _event(
                        "content_block_delta",
                        {
                            "type": "content_block_delta",
                            "index": tool_map[tc.index],
                            "delta": {"type": "input_json_delta", "partial_json": tc.arguments},
                        },
                    )
                )

        if chunk.usage is not None:
            if chunk.usage.prompt_tokens:
                ctx.state["input_tokens"] = chunk.usage.prompt_tokens
            if chunk.usage.completion_tokens:
                ctx.state["output_tokens"] = chunk.usage.completion_tokens
        if chunk.finish_reason is not None:
            ctx.state["stop_reason"] = _FINISH_TO_STOP.get(chunk.finish_reason, "end_turn")

        return frames

    def stream_finalize(self, ctx: StreamCtx) -> list[bytes]:
        frames = self._close_open(ctx)
        frames.append(
            _event(
                "message_delta",
                {
                    "type": "message_delta",
                    "delta": {
                        "stop_reason": ctx.state.get("stop_reason", "end_turn"),
                        "stop_sequence": None,
                    },
                    "usage": {"output_tokens": ctx.state.get("output_tokens", 0)},
                },
            )
        )
        frames.append(_event("message_stop", {"type": "message_stop"}))
        return frames

    def stream_error(self, message: str, err_type: str, ctx: StreamCtx) -> list[bytes]:
        return [
            _event(
                "error",
                {
                    "type": "error",
                    "error": {"type": "api_error", "message": message},
                    "request_id": ctx.request_id,
                },
            )
        ]

    def _close_open(self, ctx: StreamCtx) -> list[bytes]:
        oi = ctx.state.get("open_index")
        if oi is None:
            return []
        ctx.state["open_index"] = None
        ctx.state["open_kind"] = None
        return [_event("content_block_stop", {"type": "content_block_stop", "index": oi})]


def _msg_id(rid: str) -> str:
    if rid.startswith("msg_"):
        return rid
    return "msg_" + uuid.uuid4().hex
