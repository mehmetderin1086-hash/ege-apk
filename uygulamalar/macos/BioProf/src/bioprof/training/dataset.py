from __future__ import annotations

import contextlib
import hashlib
import json
import os
import random
import tempfile
import unicodedata
import uuid
from collections import defaultdict
from datetime import UTC, datetime
from pathlib import Path
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator


class DatasetError(ValueError):
    pass


class TrainingExample(BaseModel):
    """A reviewable, source-bound behaviour example.

    `document_family` is the leakage boundary.  Examples from one paper,
    recording, dataset version or derived document family are never split
    across train/validation/test.
    """

    model_config = ConfigDict(extra="forbid")

    id: str = Field(default_factory=lambda: uuid.uuid4().hex)
    instruction: str = Field(min_length=3, max_length=50_000)
    response: str = Field(min_length=1, max_length=200_000)
    system_prompt: str | None = Field(default=None, max_length=20_000)
    rejected_response: str | None = Field(default=None, max_length=200_000)
    source_id: str
    source_version: str
    document_family: str
    citation_ids: list[str] = Field(default_factory=list)
    license: str
    rights_approved: bool = False
    review_status: Literal["pending", "approved", "rejected"] = "pending"
    reviewed_by: str | None = None
    reviewed_at: datetime | None = None
    metadata: dict[str, str | int | float | bool | None] = Field(default_factory=dict)

    @model_validator(mode="after")
    def approved_examples_have_auditor(self) -> TrainingExample:
        if self.review_status == "approved" and not self.reviewed_by:
            raise ValueError("Approved examples require reviewed_by")
        return self

    @property
    def content_hash(self) -> str:
        normalised = "\n".join(
            [
                _normalise(self.instruction),
                _normalise(self.response),
                _normalise(self.system_prompt or ""),
            ]
        )
        return hashlib.sha256(normalised.encode("utf-8")).hexdigest()

    def chat_record(self) -> dict[str, object]:
        messages: list[dict[str, str]] = []
        if self.system_prompt:
            messages.append({"role": "system", "content": self.system_prompt.strip()})
        messages.extend(
            [
                {"role": "user", "content": self.instruction.strip()},
                {"role": "assistant", "content": self.response.strip()},
            ]
        )
        record: dict[str, object] = {
            "id": self.id,
            "messages": messages,
            "provenance": {
                "source_id": self.source_id,
                "source_version": self.source_version,
                "document_family": self.document_family,
                "citation_ids": self.citation_ids,
                "license": self.license,
                "reviewed_by": self.reviewed_by,
                "reviewed_at": self.reviewed_at.isoformat() if self.reviewed_at else None,
                "content_hash": self.content_hash,
            },
        }
        if self.rejected_response:
            record["rejected_response"] = self.rejected_response.strip()
        return record


class DatasetManifest(BaseModel):
    id: str
    name: str
    dataset_hash: str
    created_at: datetime
    total_candidates: int
    accepted: int
    rejected_or_pending: int
    duplicates_removed: int
    split_counts: dict[str, int]
    split_families: dict[str, list[str]]
    source_ids: list[str]
    licenses: list[str]
    files: dict[str, str]
    seed: int
    schema_version: str = "bioprof.chat.v1"


def _normalise(value: str) -> str:
    return " ".join(unicodedata.normalize("NFKC", value).casefold().split())


def _atomic_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    except Exception:
        with contextlib.suppress(FileNotFoundError):
            os.unlink(temporary)
        raise


class DatasetBuilder:
    def __init__(self, examples: list[TrainingExample] | None = None) -> None:
        self.examples = list(examples or [])

    def add(self, example: TrainingExample) -> None:
        self.examples.append(example)

    def _eligible(self) -> tuple[list[TrainingExample], int, int]:
        approved = [
            example
            for example in self.examples
            if example.review_status == "approved" and example.rights_approved
        ]
        seen: set[str] = set()
        unique: list[TrainingExample] = []
        duplicates = 0
        for example in approved:
            if not example.license.strip():
                continue
            if example.content_hash in seen:
                duplicates += 1
                continue
            seen.add(example.content_hash)
            unique.append(example)
        return unique, len(self.examples) - len(approved), duplicates

    @staticmethod
    def _split_families(
        examples: list[TrainingExample],
        ratios: tuple[float, float, float],
        seed: int,
    ) -> dict[str, list[TrainingExample]]:
        if len(ratios) != 3 or any(value < 0 for value in ratios):
            raise DatasetError("Split ratios must contain three non-negative values")
        total_ratio = sum(ratios)
        if not math_isclose(total_ratio, 1.0):
            raise DatasetError("Train/validation/test ratios must sum to 1")
        by_family: dict[str, list[TrainingExample]] = defaultdict(list)
        for example in examples:
            by_family[example.document_family].append(example)
        families = sorted(by_family)
        random.Random(seed).shuffle(families)
        active = [index for index, ratio in enumerate(ratios) if ratio > 0]
        if len(families) < len(active):
            raise DatasetError(
                "Not enough independent document families for the requested non-empty splits"
            )
        counts = [int(len(families) * ratio) for ratio in ratios]
        for index in active:
            counts[index] = max(1, counts[index])
        while sum(counts) > len(families):
            removable = max(
                (index for index in active if counts[index] > 1),
                key=lambda index: counts[index] - len(families) * ratios[index],
                default=None,
            )
            if removable is None:
                break
            counts[removable] -= 1
        while sum(counts) < len(families):
            add_to = max(
                range(3),
                key=lambda index: len(families) * ratios[index] - counts[index],
            )
            counts[add_to] += 1
        names = ("train", "validation", "test")
        split: dict[str, list[TrainingExample]] = {name: [] for name in names}
        cursor = 0
        for name, count in zip(names, counts, strict=True):
            for family in families[cursor : cursor + count]:
                split[name].extend(by_family[family])
            cursor += count
        return split

    def build(
        self,
        output_dir: Path,
        *,
        name: str,
        ratios: tuple[float, float, float] = (0.8, 0.1, 0.1),
        seed: int = 42,
    ) -> DatasetManifest:
        eligible, rejected_or_pending, duplicates = self._eligible()
        if not eligible:
            raise DatasetError("No reviewed, rights-approved training examples are available")
        split = self._split_families(eligible, ratios, seed)
        output_dir.mkdir(parents=True, exist_ok=True)
        file_hashes: list[str] = []
        files: dict[str, str] = {}
        for split_name, examples in split.items():
            content = "".join(
                json.dumps(example.chat_record(), ensure_ascii=False, sort_keys=True) + "\n"
                for example in sorted(examples, key=lambda item: item.id)
            )
            path = output_dir / f"{split_name}.jsonl"
            _atomic_text(path, content)
            digest = hashlib.sha256(content.encode("utf-8")).hexdigest()
            files[split_name] = path.name
            file_hashes.append(f"{split_name}:{digest}")
        dataset_hash = hashlib.sha256("\n".join(file_hashes).encode()).hexdigest()
        manifest = DatasetManifest(
            id=uuid.uuid4().hex,
            name=name,
            dataset_hash=dataset_hash,
            created_at=datetime.now(UTC),
            total_candidates=len(self.examples),
            accepted=len(eligible),
            rejected_or_pending=rejected_or_pending,
            duplicates_removed=duplicates,
            split_counts={key: len(value) for key, value in split.items()},
            split_families={
                key: sorted({example.document_family for example in value})
                for key, value in split.items()
            },
            source_ids=sorted({example.source_id for example in eligible}),
            licenses=sorted({example.license for example in eligible}),
            files=files,
            seed=seed,
        )
        _atomic_text(
            output_dir / "dataset_manifest.json",
            manifest.model_dump_json(indent=2),
        )
        return manifest


def math_isclose(value: float, expected: float) -> bool:
    return abs(value - expected) <= 1e-9
