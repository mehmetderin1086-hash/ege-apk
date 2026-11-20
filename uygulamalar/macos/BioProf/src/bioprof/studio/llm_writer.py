"""Deterministik Stüdyo taslağını yerel LLM ile akıcılaştıran katman.

Sözleşme tek yönlüdür: LLM yalnız *ifadeyi* değiştirebilir. Üretilen her
cümle, sohbette olduğu gibi kanıt penceresi testinden geçer ve alıntı
etiketleri korunmak zorundadır. Bir cümle desteklenmiyorsa düşer; geriye
alıntılı bir gövde kalmazsa deterministik taslak aynen kullanılır. Böylece
Stüdyo LLM'siz de, LLM bozuk çıktı verdiğinde de çalışır durumda kalır.
"""

from __future__ import annotations

import re
from collections.abc import Mapping
from typing import Any, Protocol

from bioprof.providers.base import ProviderError
from bioprof.rag.answering import _CITATION, _claim_supported, iddia_gibi
from bioprof.studio.artifacts import StudioEvidence
from bioprof.studio.prompts import (
    DESTEKLENEN_TURLER,
    kullanici_istemi,
    sistem_istemi,
)

_BASLIK = re.compile(r"^#{1,6}\s")
_MADDE = re.compile(r"^([-*]\s+|\d+[.)]\s+)")
# Deterministik motorun sonuna eklediği kaynak künyesi; LLM'e gönderilmez ve
# döndürülen metne aynen geri eklenir (künye alıntı çapalarının kaydıdır).
_DIPNOT = "\n\n## Kaynaklar\n"


class ChatCallable(Protocol):
    async def __call__(
        self, messages: list[dict[str, str]], *, max_tokens: int | None = None
    ) -> str: ...


class StudioLLMWriter:
    """Bir Stüdyo taslağını akıcılaştırır; doğrulanamayan hiçbir şeyi geçirmez."""

    def __init__(self, chat: ChatCallable, *, minimum_ratio: float = 0.5) -> None:
        self._chat = chat
        # Cümlelerin yarısından çoğu düşerse metin güvenilmez sayılır ve
        # deterministik taslak korunur.
        self.minimum_ratio = minimum_ratio

    @property
    def chat(self) -> ChatCallable:
        """Sarılan sohbet çağrılabiliri; podcast senaryosu aynı kanaldan yazılır."""
        return self._chat

    def supports(self, kind: str) -> bool:
        return kind in DESTEKLENEN_TURLER

    async def rewrite(
        self,
        kind: str,
        markdown: str,
        records: list[StudioEvidence],
        *,
        title: str = "",
    ) -> tuple[str, list[str]]:
        """(metin, uyarılar) döndürür. Başarısızlıkta taslak değişmeden döner."""
        if not self.supports(kind) or not records:
            return markdown, []
        body, footer = _split_footer(markdown)
        evidence_text = "\n\n".join(
            f'<untrusted_evidence id="{item.label}">\n[{item.label}] '
            f"{item.source_title}\n{item.text}\n</untrusted_evidence>"
            for item in records
        )
        messages = [
            {"role": "system", "content": sistem_istemi(kind)},
            {"role": "user", "content": kullanici_istemi(evidence_text, title, body)},
        ]
        try:
            generated = await self._chat(messages)
        except (ProviderError, RuntimeError, TimeoutError) as exc:
            return markdown, [f"LLM akıcılaştırma yapılamadı, taslak korundu: {exc}"]

        validated, dropped, kept = _validate(generated, records)
        if not kept or kept < self.minimum_ratio * (kept + dropped):
            return markdown, [
                "LLM metni kanıt kapısından geçmedi, deterministik taslak korundu."
            ]
        warnings = []
        if dropped:
            warnings.append(f"{dropped} cümle kanıtla desteklenmediği için çıkarıldı.")
        return validated + footer, warnings


def _split_footer(markdown: str) -> tuple[str, str]:
    index = markdown.find(_DIPNOT)
    if index < 0:
        return markdown, ""
    return markdown[:index], markdown[index:]


def _validate(generated: str, records: list[StudioEvidence]) -> tuple[str, int, int]:
    """Satır satır doğrular; başlık/boşluk korunur, olgu cümleleri sınanır."""
    allowed = {item.label.upper(): item.text for item in records}
    kept = 0
    dropped = 0
    output: list[str] = []
    for line in generated.splitlines():
        stripped = line.strip()
        if not stripped:
            output.append("")
            continue
        if _BASLIK.match(stripped):
            # Başlıklar da olgu taşıyabilir ("## İnsülin kan şekerini artırır").
            # Kısa bölüm adları serbest, iddia gibi okunan başlıklar kanıta
            # karşı sınanır; geçemezse başlık düşer, gövde kalır.
            baslik = _BASLIK.sub("", stripped).strip()
            if iddia_gibi(baslik) and not any(
                _claim_supported(baslik, text) for text in allowed.values()
            ):
                dropped += 1
                continue
            output.append(line.rstrip())
            continue
        labels = [match.group(1).upper() for match in _CITATION.finditer(stripped)]
        valid = [label for label in labels if label in allowed]
        if not valid or len(valid) != len(labels):
            dropped += 1
            continue
        claim = _CITATION.sub("", _MADDE.sub("", stripped)).strip()
        if not _claim_supported(claim, " ".join(allowed[label] for label in valid)):
            dropped += 1
            continue
        kept += 1
        output.append(line.rstrip())
    text = "\n".join(output).strip()
    return re.sub(r"\n{3,}", "\n\n", text), dropped, kept


def build_chat(provider: Any, model: str, guard_factory: Any) -> ChatCallable:
    """Sağlayıcıyı writer'ın beklediği tek fonksiyonlu arayüze indirger.

    ``guard_factory`` her çağrıda YENİ bir bağlam yöneticisi üretmeli: tek bir
    ``asynccontextmanager`` örneği yalnız bir kez girilebilir, ikinci kullanım
    AttributeError'la patlıyordu ve podcast senaryosunun ikinci denemesi bu
    yüzden her zaman çöküyordu.
    """

    async def chat(
        messages: list[dict[str, str]], *, max_tokens: int | None = None
    ) -> str:
        payload: dict[str, Any] = {
            "model": model,
            "messages": messages,
            "temperature": 0.2,
        }
        if max_tokens:
            payload["max_tokens"] = max_tokens
        async with guard_factory():
            result = await provider.chat(payload)
        return _text_of(result)

    return chat


def _text_of(result: Any) -> str:
    if isinstance(result, Mapping):
        return str(result.get("text", ""))
    return str(getattr(result, "text", ""))
