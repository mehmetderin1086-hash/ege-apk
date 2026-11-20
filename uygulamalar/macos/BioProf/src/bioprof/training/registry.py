from __future__ import annotations

import contextlib
import hashlib
import os
import tempfile
import threading
import uuid
from datetime import UTC, datetime
from pathlib import Path
from typing import Literal

from pydantic import BaseModel, Field


class RegistryError(ValueError):
    pass


class ModelEntry(BaseModel):
    id: str = Field(default_factory=lambda: uuid.uuid4().hex)
    name: str
    base_model: str
    dataset_hash: str
    artifact_path: str
    artifact_sha256: str
    status: Literal["candidate", "champion", "archived", "failed"] = "candidate"
    evaluation_passed: bool = False
    metrics: dict[str, float] = Field(default_factory=dict)
    manifest_path: str | None = None
    created_at: datetime = Field(default_factory=lambda: datetime.now(UTC))
    promoted_at: datetime | None = None


class _RegistryDocument(BaseModel):
    schema_version: int = 1
    models: list[ModelEntry] = Field(default_factory=list)
    champion_id: str | None = None
    champion_history: list[str] = Field(default_factory=list)


def artifact_checksum(path: Path) -> str:
    if not path.exists():
        raise RegistryError(f"Model artifact not found: {path}")
    if path.is_symlink():
        raise RegistryError("Model artifact cannot be a symbolic link")
    digest = hashlib.sha256()
    if path.is_file():
        paths = [path]
    else:
        paths = []
        root = path.resolve()
        for item in sorted(path.rglob("*")):
            if item.is_symlink():
                raise RegistryError("Model artifact tree cannot contain symbolic links")
            if item.is_file():
                resolved = item.resolve()
                if not resolved.is_relative_to(root):
                    raise RegistryError("Model artifact escaped its import directory")
                paths.append(item)
    for item in paths:
        if path.is_dir():
            digest.update(str(item.relative_to(path)).encode())
            digest.update(b"\0")
        with item.open("rb") as handle:
            for block in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(block)
    return digest.hexdigest()


class ModelRegistry:
    """Atomic local registry with guarded champion promotion and rollback."""

    def __init__(self, path: Path) -> None:
        self.path = path
        self._lock = threading.RLock()
        path.parent.mkdir(parents=True, exist_ok=True)
        if not path.exists():
            self._save(_RegistryDocument())

    def _load(self) -> _RegistryDocument:
        try:
            return _RegistryDocument.model_validate_json(self.path.read_text(encoding="utf-8"))
        except (OSError, ValueError) as exc:
            raise RegistryError(f"Model registry cannot be read: {exc}") from exc

    def _save(self, document: _RegistryDocument) -> None:
        descriptor, temporary = tempfile.mkstemp(prefix=f".{self.path.name}.", dir=self.path.parent)
        try:
            with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
                handle.write(document.model_dump_json(indent=2))
                handle.flush()
                os.fsync(handle.fileno())
            os.replace(temporary, self.path)
        except Exception:
            with contextlib.suppress(FileNotFoundError):
                os.unlink(temporary)
            raise

    def list(self) -> list[ModelEntry]:
        with self._lock:
            return self._load().models

    def get(self, model_id: str) -> ModelEntry:
        for entry in self.list():
            if entry.id == model_id:
                return entry
        raise RegistryError(f"Unknown model: {model_id}")

    def register(
        self,
        *,
        name: str,
        base_model: str,
        dataset_hash: str,
        artifact_path: Path,
        manifest_path: Path | None = None,
    ) -> ModelEntry:
        entry = ModelEntry(
            name=name,
            base_model=base_model,
            dataset_hash=dataset_hash,
            artifact_path=str(artifact_path.resolve()),
            artifact_sha256=artifact_checksum(artifact_path),
            manifest_path=str(manifest_path.resolve()) if manifest_path else None,
        )
        with self._lock:
            document = self._load()
            document.models.append(entry)
            self._save(document)
        return entry

    def record_evaluation(
        self,
        model_id: str,
        *,
        passed: bool,
        metrics: dict[str, float],
    ) -> ModelEntry:
        with self._lock:
            document = self._load()
            entry = self._find(document, model_id)
            entry.evaluation_passed = passed
            entry.metrics = metrics
            if not passed:
                entry.status = "failed"
            self._save(document)
            return entry

    def promote(self, model_id: str) -> ModelEntry:
        with self._lock:
            document = self._load()
            entry = self._find(document, model_id)
            if entry.status not in {"candidate", "archived"}:
                raise RegistryError(f"Model status cannot be promoted: {entry.status}")
            if not entry.evaluation_passed:
                raise RegistryError("Candidate must pass evaluation before promotion")
            artifact = Path(entry.artifact_path)
            if artifact_checksum(artifact) != entry.artifact_sha256:
                raise RegistryError("Model artifact checksum changed after registration")
            if document.champion_id and document.champion_id != model_id:
                previous = self._find(document, document.champion_id)
                previous.status = "archived"
                document.champion_history.append(previous.id)
            entry.status = "champion"
            entry.promoted_at = datetime.now(UTC)
            document.champion_id = entry.id
            self._save(document)
            return entry

    def rollback(self, *, expected_model_id: str | None = None) -> ModelEntry:
        with self._lock:
            document = self._load()
            if not document.champion_id or not document.champion_history:
                raise RegistryError("No previous champion is available for rollback")
            if expected_model_id is not None and document.champion_id != expected_model_id:
                raise RegistryError(
                    "Rollback target does not match the current champion; refresh model state"
                )
            current = self._find(document, document.champion_id)
            previous_id = document.champion_history.pop()
            previous = self._find(document, previous_id)
            if not previous.evaluation_passed:
                raise RegistryError("Previous champion no longer has a passing evaluation")
            if artifact_checksum(Path(previous.artifact_path)) != previous.artifact_sha256:
                raise RegistryError("Previous champion artifact checksum is invalid")
            current.status = "archived"
            previous.status = "champion"
            previous.promoted_at = datetime.now(UTC)
            document.champion_id = previous.id
            self._save(document)
            return previous

    @staticmethod
    def _find(document: _RegistryDocument, model_id: str) -> ModelEntry:
        for entry in document.models:
            if entry.id == model_id:
                return entry
        raise RegistryError(f"Unknown model: {model_id}")
