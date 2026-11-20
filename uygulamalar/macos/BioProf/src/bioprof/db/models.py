from __future__ import annotations

import uuid
from datetime import UTC, datetime

from sqlalchemy import Boolean, DateTime, Float, ForeignKey, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship


def new_id() -> str:
    return uuid.uuid4().hex


def utc_now_naive() -> datetime:
    """SQLite-compatible UTC timestamp without using deprecated utcnow()."""
    return datetime.now(UTC).replace(tzinfo=None)


class Base(DeclarativeBase):
    pass


class NotebookRecord(Base):
    __tablename__ = "notebooks"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    name: Mapped[str] = mapped_column(String(200))
    description: Mapped[str] = mapped_column(Text, default="")
    privacy_mode: Mapped[str] = mapped_column(String(32), default="local_first")
    remote_egress_approved: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utc_now_naive)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=utc_now_naive)

    sources: Mapped[list[SourceRecord]] = relationship(
        back_populates="notebook", cascade="all, delete-orphan"
    )


class SourceRecord(Base):
    __tablename__ = "sources"
    __table_args__ = (UniqueConstraint("notebook_id", "sha256", name="uq_source_hash"),)

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    notebook_id: Mapped[str] = mapped_column(ForeignKey("notebooks.id", ondelete="CASCADE"))
    title: Mapped[str] = mapped_column(String(500))
    original_name: Mapped[str] = mapped_column(String(500))
    source_uri: Mapped[str | None] = mapped_column(Text, nullable=True)
    object_path: Mapped[str] = mapped_column(Text)
    sha256: Mapped[str] = mapped_column(String(64), index=True)
    mime_type: Mapped[str] = mapped_column(String(200), default="application/octet-stream")
    language: Mapped[str] = mapped_column(String(16), default="und")
    license: Mapped[str | None] = mapped_column(String(200), nullable=True)
    status: Mapped[str] = mapped_column(String(32), default="queued")
    parser: Mapped[str | None] = mapped_column(String(100), nullable=True)
    parser_version: Mapped[str | None] = mapped_column(String(100), nullable=True)
    doi: Mapped[str | None] = mapped_column(String(200), nullable=True)
    pmid: Mapped[str | None] = mapped_column(String(50), nullable=True)
    pmcid: Mapped[str | None] = mapped_column(String(50), nullable=True)
    metadata_json: Mapped[str] = mapped_column(Text, default="{}")
    error: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utc_now_naive)

    notebook: Mapped[NotebookRecord] = relationship(back_populates="sources")
    chunks: Mapped[list[ChunkRecord]] = relationship(
        back_populates="source", cascade="all, delete-orphan"
    )


class ChunkRecord(Base):
    __tablename__ = "chunks"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    source_id: Mapped[str] = mapped_column(ForeignKey("sources.id", ondelete="CASCADE"))
    ordinal: Mapped[int] = mapped_column(Integer)
    text: Mapped[str] = mapped_column(Text)
    section: Mapped[str | None] = mapped_column(String(500), nullable=True)
    page: Mapped[int | None] = mapped_column(Integer, nullable=True)
    slide: Mapped[int | None] = mapped_column(Integer, nullable=True)
    bbox_json: Mapped[str | None] = mapped_column(Text, nullable=True)
    timestamp_start: Mapped[float | None] = mapped_column(Float, nullable=True)
    timestamp_end: Mapped[float | None] = mapped_column(Float, nullable=True)
    sequence_start: Mapped[int | None] = mapped_column(Integer, nullable=True)
    sequence_end: Mapped[int | None] = mapped_column(Integer, nullable=True)
    token_count: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utc_now_naive)

    source: Mapped[SourceRecord] = relationship(back_populates="chunks")


class ConversationRecord(Base):
    __tablename__ = "conversations"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    notebook_id: Mapped[str] = mapped_column(ForeignKey("notebooks.id", ondelete="CASCADE"))
    title: Mapped[str] = mapped_column(String(300), default="Yeni sohbet")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utc_now_naive)


class MessageRecord(Base):
    __tablename__ = "messages"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    conversation_id: Mapped[str] = mapped_column(
        ForeignKey("conversations.id", ondelete="CASCADE")
    )
    role: Mapped[str] = mapped_column(String(32))
    content: Mapped[str] = mapped_column(Text)
    citations_json: Mapped[str] = mapped_column(Text, default="[]")
    provider: Mapped[str | None] = mapped_column(String(100), nullable=True)
    model: Mapped[str | None] = mapped_column(String(200), nullable=True)
    trace_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utc_now_naive)


class JobRecord(Base):
    __tablename__ = "jobs"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    kind: Mapped[str] = mapped_column(String(100))
    status: Mapped[str] = mapped_column(String(32), default="queued")
    progress: Mapped[float] = mapped_column(Float, default=0.0)
    payload_json: Mapped[str] = mapped_column(Text, default="{}")
    result_json: Mapped[str] = mapped_column(Text, default="{}")
    error: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utc_now_naive)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=utc_now_naive)


class ArtifactRecord(Base):
    __tablename__ = "artifacts"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    notebook_id: Mapped[str] = mapped_column(ForeignKey("notebooks.id", ondelete="CASCADE"))
    kind: Mapped[str] = mapped_column(String(100))
    title: Mapped[str] = mapped_column(String(300))
    path: Mapped[str] = mapped_column(Text)
    mime_type: Mapped[str] = mapped_column(String(200))
    metadata_json: Mapped[str] = mapped_column(Text, default="{}")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utc_now_naive)


class NoteRecord(Base):
    __tablename__ = "notes"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    notebook_id: Mapped[str] = mapped_column(
        ForeignKey("notebooks.id", ondelete="CASCADE"), index=True
    )
    title: Mapped[str] = mapped_column(String(300), default="")
    content: Mapped[str] = mapped_column(Text, default="")
    pinned: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utc_now_naive)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=utc_now_naive)


class FlashcardDeckRecord(Base):
    __tablename__ = "flashcard_decks"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    notebook_id: Mapped[str] = mapped_column(
        ForeignKey("notebooks.id", ondelete="CASCADE"), index=True
    )
    # Deste, kaynağı olan artifact silinse de yaşamalı.
    artifact_id: Mapped[str | None] = mapped_column(
        ForeignKey("artifacts.id", ondelete="SET NULL"), nullable=True
    )
    title: Mapped[str] = mapped_column(String(300))
    description: Mapped[str] = mapped_column(Text, default="")
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utc_now_naive)

    cards: Mapped[list[FlashcardRecord]] = relationship(
        back_populates="deck", cascade="all, delete-orphan"
    )


class FlashcardRecord(Base):
    __tablename__ = "flashcards"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    deck_id: Mapped[str] = mapped_column(
        ForeignKey("flashcard_decks.id", ondelete="CASCADE"), index=True
    )
    front: Mapped[str] = mapped_column(Text)
    back: Mapped[str] = mapped_column(Text)
    citation_label: Mapped[str | None] = mapped_column(String(16), nullable=True)
    # Chunk id; FK bilerek yok — chunk/kaynak silinse kart yaşar.
    citation_id: Mapped[str | None] = mapped_column(String(64), nullable=True)
    source_title: Mapped[str | None] = mapped_column(String(500), nullable=True)
    position: Mapped[int] = mapped_column(Integer, default=0)
    # SM-2 durumu kartın üstünde: "vadesi gelenler" tek tablodan sorgulanır.
    ease_factor: Mapped[float] = mapped_column(Float, default=2.5)
    interval_days: Mapped[float] = mapped_column(Float, default=0.0)
    repetitions: Mapped[int] = mapped_column(Integer, default=0)
    lapses: Mapped[int] = mapped_column(Integer, default=0)
    due_at: Mapped[datetime] = mapped_column(DateTime, default=utc_now_naive, index=True)
    suspended: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utc_now_naive)

    deck: Mapped[FlashcardDeckRecord] = relationship(back_populates="cards")


class FlashcardReviewRecord(Base):
    __tablename__ = "flashcard_reviews"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    card_id: Mapped[str] = mapped_column(
        ForeignKey("flashcards.id", ondelete="CASCADE"), index=True
    )
    reviewed_at: Mapped[datetime] = mapped_column(DateTime, default=utc_now_naive)
    grade: Mapped[int] = mapped_column(Integer)
    interval_before: Mapped[float] = mapped_column(Float, default=0.0)
    interval_after: Mapped[float] = mapped_column(Float, default=0.0)
    ease_before: Mapped[float] = mapped_column(Float, default=2.5)
    ease_after: Mapped[float] = mapped_column(Float, default=2.5)


class TrainingRunRecord(Base):
    __tablename__ = "training_runs"

    id: Mapped[str] = mapped_column(String(32), primary_key=True, default=new_id)
    notebook_id: Mapped[str | None] = mapped_column(
        ForeignKey("notebooks.id", ondelete="SET NULL"), nullable=True
    )
    name: Mapped[str] = mapped_column(String(300))
    status: Mapped[str] = mapped_column(String(32), default="draft")
    base_model: Mapped[str] = mapped_column(String(300))
    dataset_hash: Mapped[str] = mapped_column(String(64))
    manifest_json: Mapped[str] = mapped_column(Text)
    metrics_json: Mapped[str] = mapped_column(Text, default="{}")
    artifact_path: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utc_now_naive)
