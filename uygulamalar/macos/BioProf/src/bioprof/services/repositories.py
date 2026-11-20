from __future__ import annotations

import json
from collections.abc import Sequence
from typing import Any

from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from bioprof.db.models import (
    ArtifactRecord,
    ChunkRecord,
    ConversationRecord,
    JobRecord,
    MessageRecord,
    NotebookRecord,
    NoteRecord,
    SourceRecord,
    TrainingRunRecord,
    utc_now_naive,
)


def _json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), default=str)


def _loads(value: str | None, default: Any) -> Any:
    if not value:
        return default
    try:
        return json.loads(value)
    except json.JSONDecodeError:
        return default


class Repository:
    """Small explicit repository used by API, CLI and background jobs."""

    def __init__(self, session: Session) -> None:
        self.session = session

    def create_notebook(
        self,
        name: str,
        description: str = "",
        privacy_mode: str = "local_first",
        remote_egress_approved: bool = False,
    ) -> NotebookRecord:
        record = NotebookRecord(
            name=name.strip() or "Adsız notebook",
            description=description.strip(),
            privacy_mode=privacy_mode,
            remote_egress_approved=remote_egress_approved,
        )
        self.session.add(record)
        self.session.commit()
        self.session.refresh(record)
        return record

    def list_notebooks(self) -> Sequence[NotebookRecord]:
        statement = select(NotebookRecord).order_by(NotebookRecord.updated_at.desc())
        return self.session.scalars(statement).all()

    def get_notebook(self, notebook_id: str) -> NotebookRecord | None:
        return self.session.get(NotebookRecord, notebook_id)

    def update_notebook(self, notebook_id: str, **updates: Any) -> NotebookRecord | None:
        record = self.get_notebook(notebook_id)
        if record is None:
            return None
        allowed = {
            "name",
            "description",
            "privacy_mode",
            "remote_egress_approved",
        }
        for key, value in updates.items():
            if key in allowed and value is not None:
                setattr(record, key, value)
        record.updated_at = utc_now_naive()
        self.session.commit()
        self.session.refresh(record)
        return record

    def delete_notebook(self, notebook_id: str) -> bool:
        record = self.get_notebook(notebook_id)
        if record is None:
            return False
        self.session.delete(record)
        self.session.commit()
        return True

    def list_sources(self, notebook_id: str) -> Sequence[SourceRecord]:
        statement = (
            select(SourceRecord)
            .where(SourceRecord.notebook_id == notebook_id)
            .order_by(SourceRecord.created_at.desc())
        )
        return self.session.scalars(statement).all()

    def get_source(self, source_id: str) -> SourceRecord | None:
        return self.session.get(SourceRecord, source_id)

    def delete_source(self, source_id: str) -> bool:
        source = self.get_source(source_id)
        if source is None:
            return False
        self.session.execute(delete(ChunkRecord).where(ChunkRecord.source_id == source_id))
        self.session.execute(
            delete(SourceRecord).where(SourceRecord.id == source_id)
        )
        if self.session.bind is not None and self.session.bind.dialect.name == "sqlite":
            self.session.execute(
                # FTS tables are managed manually and deliberately receive a literal-free query.
                __import__("sqlalchemy").text("DELETE FROM chunk_fts WHERE source_id = :source_id"),
                {"source_id": source_id},
            )
        self.session.commit()
        return True

    def list_chunks(self, source_id: str) -> Sequence[ChunkRecord]:
        statement = (
            select(ChunkRecord)
            .where(ChunkRecord.source_id == source_id)
            .order_by(ChunkRecord.ordinal)
        )
        return self.session.scalars(statement).all()

    def create_conversation(
        self, notebook_id: str, title: str = "Yeni sohbet"
    ) -> ConversationRecord:
        record = ConversationRecord(notebook_id=notebook_id, title=title)
        self.session.add(record)
        self.session.commit()
        self.session.refresh(record)
        return record

    def add_message(
        self,
        conversation_id: str,
        role: str,
        content: str,
        *,
        citations: list[dict[str, Any]] | None = None,
        provider: str | None = None,
        model: str | None = None,
        trace_id: str | None = None,
    ) -> MessageRecord:
        record = MessageRecord(
            conversation_id=conversation_id,
            role=role,
            content=content,
            citations_json=_json(citations or []),
            provider=provider,
            model=model,
            trace_id=trace_id,
        )
        self.session.add(record)
        self.session.commit()
        self.session.refresh(record)
        return record

    def list_conversations(self, notebook_id: str) -> Sequence[ConversationRecord]:
        statement = (
            select(ConversationRecord)
            .where(ConversationRecord.notebook_id == notebook_id)
            .order_by(ConversationRecord.created_at.desc())
        )
        return self.session.scalars(statement).all()

    def delete_conversation(self, conversation_id: str) -> bool:
        record = self.session.get(ConversationRecord, conversation_id)
        if record is None:
            return False
        # Mesajlar FK CASCADE ile gider; ORM cascade tanımlı olmadığı için
        # silme SQL düzeyinde yapılır.
        self.session.execute(
            delete(MessageRecord).where(MessageRecord.conversation_id == conversation_id)
        )
        self.session.delete(record)
        self.session.commit()
        return True

    @staticmethod
    def serialize_conversation(record: ConversationRecord) -> dict[str, Any]:
        return {
            "id": record.id,
            "notebook_id": record.notebook_id,
            "title": record.title,
            "created_at": record.created_at.isoformat(),
        }

    @staticmethod
    def serialize_message(record: MessageRecord) -> dict[str, Any]:
        return {
            "id": record.id,
            "conversation_id": record.conversation_id,
            "role": record.role,
            "content": record.content,
            "citations": _loads(record.citations_json, []),
            "provider": record.provider,
            "model": record.model,
            "created_at": record.created_at.isoformat(),
        }

    def list_messages(self, conversation_id: str) -> Sequence[MessageRecord]:
        statement = (
            select(MessageRecord)
            .where(MessageRecord.conversation_id == conversation_id)
            .order_by(MessageRecord.created_at)
        )
        return self.session.scalars(statement).all()

    def create_job(self, kind: str, payload: dict[str, Any]) -> JobRecord:
        record = JobRecord(kind=kind, status="queued", payload_json=_json(payload))
        self.session.add(record)
        self.session.commit()
        self.session.refresh(record)
        return record

    def get_job(self, job_id: str) -> JobRecord | None:
        return self.session.get(JobRecord, job_id)

    def list_jobs(self, limit: int = 100) -> Sequence[JobRecord]:
        statement = select(JobRecord).order_by(JobRecord.created_at.desc()).limit(limit)
        return self.session.scalars(statement).all()

    def update_job(
        self,
        job_id: str,
        *,
        status: str | None = None,
        progress: float | None = None,
        result: dict[str, Any] | None = None,
        error: str | None = None,
    ) -> JobRecord | None:
        record = self.get_job(job_id)
        if record is None:
            return None
        if status is not None:
            record.status = status
        if progress is not None:
            record.progress = max(0.0, min(1.0, progress))
        if result is not None:
            record.result_json = _json(result)
        if error is not None:
            record.error = error[:4000]
        record.updated_at = utc_now_naive()
        self.session.commit()
        self.session.refresh(record)
        return record

    def create_artifact(
        self,
        notebook_id: str,
        kind: str,
        title: str,
        path: str,
        mime_type: str,
        metadata: dict[str, Any] | None = None,
    ) -> ArtifactRecord:
        record = ArtifactRecord(
            notebook_id=notebook_id,
            kind=kind,
            title=title,
            path=path,
            mime_type=mime_type,
            metadata_json=_json(metadata or {}),
        )
        self.session.add(record)
        self.session.commit()
        self.session.refresh(record)
        return record

    def get_artifact(self, artifact_id: str) -> ArtifactRecord | None:
        return self.session.get(ArtifactRecord, artifact_id)

    def delete_artifact(self, artifact_id: str) -> bool:
        record = self.get_artifact(artifact_id)
        if record is None:
            return False
        self.session.delete(record)
        self.session.commit()
        return True

    def list_artifacts(self, notebook_id: str) -> Sequence[ArtifactRecord]:
        statement = (
            select(ArtifactRecord)
            .where(ArtifactRecord.notebook_id == notebook_id)
            .order_by(ArtifactRecord.created_at.desc())
        )
        return self.session.scalars(statement).all()

    def create_note(
        self, notebook_id: str, title: str = "", content: str = "", pinned: bool = False
    ) -> NoteRecord:
        record = NoteRecord(
            notebook_id=notebook_id,
            title=title.strip()[:300],
            content=content,
            pinned=pinned,
        )
        self.session.add(record)
        self.session.commit()
        self.session.refresh(record)
        return record

    def list_notes(self, notebook_id: str) -> Sequence[NoteRecord]:
        statement = (
            select(NoteRecord)
            .where(NoteRecord.notebook_id == notebook_id)
            .order_by(NoteRecord.pinned.desc(), NoteRecord.updated_at.desc())
        )
        return self.session.scalars(statement).all()

    def get_note(self, note_id: str) -> NoteRecord | None:
        return self.session.get(NoteRecord, note_id)

    def update_note(self, note_id: str, **updates: Any) -> NoteRecord | None:
        record = self.get_note(note_id)
        if record is None:
            return None
        allowed = {"title", "content", "pinned"}
        for key, value in updates.items():
            if key in allowed and value is not None:
                if key == "title":
                    value = str(value).strip()[:300]
                setattr(record, key, value)
        record.updated_at = utc_now_naive()
        self.session.commit()
        self.session.refresh(record)
        return record

    def delete_note(self, note_id: str) -> bool:
        record = self.get_note(note_id)
        if record is None:
            return False
        self.session.delete(record)
        self.session.commit()
        return True

    @staticmethod
    def serialize_note(record: NoteRecord) -> dict[str, Any]:
        return {
            "id": record.id,
            "notebook_id": record.notebook_id,
            "title": record.title,
            "content": record.content,
            "pinned": record.pinned,
            "created_at": record.created_at.isoformat(),
            "updated_at": record.updated_at.isoformat(),
        }

    def list_training_runs(self) -> Sequence[TrainingRunRecord]:
        statement = select(TrainingRunRecord).order_by(TrainingRunRecord.created_at.desc())
        return self.session.scalars(statement).all()

    @staticmethod
    def serialize_notebook(record: NotebookRecord) -> dict[str, Any]:
        return {
            "id": record.id,
            "name": record.name,
            "description": record.description,
            "privacy_mode": record.privacy_mode,
            "remote_egress_approved": record.remote_egress_approved,
            "created_at": record.created_at.isoformat(),
            "updated_at": record.updated_at.isoformat(),
        }

    @staticmethod
    def serialize_source(record: SourceRecord) -> dict[str, Any]:
        return {
            "id": record.id,
            "notebook_id": record.notebook_id,
            "title": record.title,
            "original_name": record.original_name,
            "source_uri": record.source_uri,
            "sha256": record.sha256,
            "mime_type": record.mime_type,
            "language": record.language,
            "license": record.license,
            "status": record.status,
            "parser": record.parser,
            "doi": record.doi,
            "pmid": record.pmid,
            "pmcid": record.pmcid,
            "metadata": _loads(record.metadata_json, {}),
            "error": record.error,
            "created_at": record.created_at.isoformat(),
        }

    @staticmethod
    def serialize_job(record: JobRecord) -> dict[str, Any]:
        return {
            "id": record.id,
            "kind": record.kind,
            "status": record.status,
            "progress": record.progress,
            "payload": _loads(record.payload_json, {}),
            "result": _loads(record.result_json, {}),
            "error": record.error,
            "created_at": record.created_at.isoformat(),
            "updated_at": record.updated_at.isoformat(),
        }
