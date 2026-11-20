from __future__ import annotations

import re
from collections.abc import Iterable

from bioprof.ingest.models import DocumentBlock, PreparedChunk

_BOUNDARY = re.compile(r"\n\s*\n|(?<=[.!?])\s+(?=[A-ZÇĞİÖŞÜ0-9])")


def approximate_token_count(text: str) -> int:
    # This is deliberately tokenizer-independent. It is metadata, never used for
    # enforcing a model's context window.
    return max(1, (len(text) + 3) // 4)


def _windows(text: str, target: int, overlap: int) -> list[str]:
    text = text.strip()
    if not text:
        return []
    if len(text) <= target:
        return [text]

    units = [unit.strip() for unit in _BOUNDARY.split(text) if unit.strip()]
    if len(units) == 1:
        step = max(1, target - overlap)
        return [text[start : start + target].strip() for start in range(0, len(text), step)]

    result: list[str] = []
    current = ""
    for unit in units:
        if len(unit) > target:
            if current:
                result.append(current)
                current = ""
            result.extend(_windows(unit, target, overlap))
            continue
        candidate = f"{current}\n\n{unit}".strip() if current else unit
        if len(candidate) <= target:
            current = candidate
            continue
        result.append(current)
        tail = current[-overlap:].lstrip() if overlap else ""
        current = f"{tail}\n\n{unit}".strip() if tail else unit
    if current:
        result.append(current)
    return result


def chunk_blocks(
    blocks: Iterable[DocumentBlock], *, target_chars: int = 2400, overlap_chars: int = 240
) -> list[PreparedChunk]:
    if target_chars < 200:
        raise ValueError("target_chars must be at least 200")
    if overlap_chars < 0 or overlap_chars >= target_chars:
        raise ValueError("overlap_chars must be non-negative and smaller than target_chars")

    prepared: list[PreparedChunk] = []
    for block in blocks:
        windows = _windows(block.text, target_chars, overlap_chars)
        for window in windows:
            sequence_start = block.sequence_start
            sequence_end = block.sequence_end
            # Parsers emit pre-segmented biological blocks. If a caller supplies a
            # long sequence-like block, keep the broad parent range rather than
            # inventing inaccurate base coordinates.
            prepared.append(
                PreparedChunk(
                    ordinal=len(prepared),
                    text=window,
                    section=block.section,
                    page=block.page,
                    slide=block.slide,
                    bbox=block.bbox,
                    timestamp_start=block.timestamp_start,
                    timestamp_end=block.timestamp_end,
                    sequence_start=sequence_start,
                    sequence_end=sequence_end,
                    token_count=approximate_token_count(window),
                )
            )
    return prepared
