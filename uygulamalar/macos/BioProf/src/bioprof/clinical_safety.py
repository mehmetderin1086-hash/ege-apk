from __future__ import annotations

import re
from collections.abc import Mapping, Sequence
from typing import Any

_PERSONAL_CLINICAL = (
    re.compile(
        r"\b(?:bana|benim|kendim|çocuğum|annem|babam|eşim)\b.{0,80}"
        r"\b(?:doz|ilaç|reçete|tedavi|tanı|teşhis)\b",
        re.IGNORECASE,
    ),
    re.compile(
        r"\b(?:kaç|ne\s+kadar)\s*(?:mg|mcg|µg|g|ml|tablet|kapsül|damla)\b.{0,60}"
        r"\b(?:almalı|kullanmalı|içmeli|vermeli|uygulamal)[a-zçğıöşü]*\b",
        re.IGNORECASE,
    ),
    re.compile(
        r"\b(?:what\s+dose\s+should\s+(?:i|my)|diagnose\s+me|do\s+i\s+have|"
        r"prescribe\s+(?:me|for\s+me))\b",
        re.IGNORECASE,
    ),
    re.compile(
        r"\b(?:bende|ben\s+.*mıyım|ben\s+.*miyim)\b.{0,80}"
        r"\b(?:hastalık|kanser|enfeksiyon|sendrom|tanı|teşhis)\b",
        re.IGNORECASE,
    ),
)

REFUSAL_TEXT = (
    "Bu istek kişiye özel tanı, tedavi, reçete veya doz kararı gerektiriyor. "
    "BioProf yalnız biyoloji ve tıp eğitimi/araştırması için tasarlandı ve klinik karar "
    "vermez. Kişisel durumunuz için yetkili bir sağlık profesyoneline başvurun."
)


def is_personal_clinical_request(text: str) -> bool:
    compact = " ".join(text.split())[:50_000]
    return any(pattern.search(compact) for pattern in _PERSONAL_CLINICAL)


def request_text(payload: Mapping[str, Any]) -> str:
    messages = payload.get("messages")
    if isinstance(messages, Sequence) and not isinstance(messages, (str, bytes, bytearray)):
        parts: list[str] = []
        for message in messages:
            if not isinstance(message, Mapping) or message.get("role") != "user":
                continue
            content = message.get("content")
            if isinstance(content, str):
                parts.append(content)
            elif isinstance(content, Sequence):
                parts.extend(
                    str(item.get("text", ""))
                    for item in content
                    if isinstance(item, Mapping)
                )
        return "\n".join(parts)
    input_value = payload.get("input")
    return input_value if isinstance(input_value, str) else ""
