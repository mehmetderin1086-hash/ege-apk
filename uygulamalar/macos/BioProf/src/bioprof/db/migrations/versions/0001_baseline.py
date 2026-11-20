"""Mevcut şemanın başlangıç revizyonu.

2026-08-07 itibarıyla canlı DB'deki 8 tablonun birebir dökümü. `create_all` ile
kurulmuş eski kurulumlar bu revizyona `stamp` edilir (bkz. Database.initialize).
FTS5 tabloları burada YOK — onlar Database._initialize_fts'in işi.

Revision ID: 0001_baseline
Revises:
Create Date: 2026-08-07
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "0001_baseline"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "notebooks",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column("name", sa.String(200), nullable=False),
        sa.Column("description", sa.Text(), nullable=False),
        sa.Column("privacy_mode", sa.String(32), nullable=False),
        sa.Column("remote_egress_approved", sa.Boolean(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
    )
    op.create_table(
        "sources",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column(
            "notebook_id",
            sa.String(32),
            sa.ForeignKey("notebooks.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("title", sa.String(500), nullable=False),
        sa.Column("original_name", sa.String(500), nullable=False),
        sa.Column("source_uri", sa.Text(), nullable=True),
        sa.Column("object_path", sa.Text(), nullable=False),
        sa.Column("sha256", sa.String(64), nullable=False),
        sa.Column("mime_type", sa.String(200), nullable=False),
        sa.Column("language", sa.String(16), nullable=False),
        sa.Column("license", sa.String(200), nullable=True),
        sa.Column("status", sa.String(32), nullable=False),
        sa.Column("parser", sa.String(100), nullable=True),
        sa.Column("parser_version", sa.String(100), nullable=True),
        sa.Column("doi", sa.String(200), nullable=True),
        sa.Column("pmid", sa.String(50), nullable=True),
        sa.Column("pmcid", sa.String(50), nullable=True),
        sa.Column("metadata_json", sa.Text(), nullable=False),
        sa.Column("error", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.UniqueConstraint("notebook_id", "sha256", name="uq_source_hash"),
    )
    op.create_index("ix_sources_sha256", "sources", ["sha256"])
    op.create_table(
        "chunks",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column(
            "source_id",
            sa.String(32),
            sa.ForeignKey("sources.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("ordinal", sa.Integer(), nullable=False),
        sa.Column("text", sa.Text(), nullable=False),
        sa.Column("section", sa.String(500), nullable=True),
        sa.Column("page", sa.Integer(), nullable=True),
        sa.Column("slide", sa.Integer(), nullable=True),
        sa.Column("bbox_json", sa.Text(), nullable=True),
        sa.Column("timestamp_start", sa.Float(), nullable=True),
        sa.Column("timestamp_end", sa.Float(), nullable=True),
        sa.Column("sequence_start", sa.Integer(), nullable=True),
        sa.Column("sequence_end", sa.Integer(), nullable=True),
        sa.Column("token_count", sa.Integer(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
    )
    op.create_table(
        "conversations",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column(
            "notebook_id",
            sa.String(32),
            sa.ForeignKey("notebooks.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("title", sa.String(300), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
    )
    op.create_table(
        "messages",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column(
            "conversation_id",
            sa.String(32),
            sa.ForeignKey("conversations.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("role", sa.String(32), nullable=False),
        sa.Column("content", sa.Text(), nullable=False),
        sa.Column("citations_json", sa.Text(), nullable=False),
        sa.Column("provider", sa.String(100), nullable=True),
        sa.Column("model", sa.String(200), nullable=True),
        sa.Column("trace_id", sa.String(64), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
    )
    op.create_table(
        "jobs",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column("kind", sa.String(100), nullable=False),
        sa.Column("status", sa.String(32), nullable=False),
        sa.Column("progress", sa.Float(), nullable=False),
        sa.Column("payload_json", sa.Text(), nullable=False),
        sa.Column("result_json", sa.Text(), nullable=False),
        sa.Column("error", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
    )
    op.create_table(
        "artifacts",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column(
            "notebook_id",
            sa.String(32),
            sa.ForeignKey("notebooks.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("kind", sa.String(100), nullable=False),
        sa.Column("title", sa.String(300), nullable=False),
        sa.Column("path", sa.Text(), nullable=False),
        sa.Column("mime_type", sa.String(200), nullable=False),
        sa.Column("metadata_json", sa.Text(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
    )
    op.create_table(
        "training_runs",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column(
            "notebook_id",
            sa.String(32),
            sa.ForeignKey("notebooks.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("name", sa.String(300), nullable=False),
        sa.Column("status", sa.String(32), nullable=False),
        sa.Column("base_model", sa.String(300), nullable=False),
        sa.Column("dataset_hash", sa.String(64), nullable=False),
        sa.Column("manifest_json", sa.Text(), nullable=False),
        sa.Column("metrics_json", sa.Text(), nullable=False),
        sa.Column("artifact_path", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False),
    )


def downgrade() -> None:
    for tablo in (
        "training_runs",
        "artifacts",
        "jobs",
        "messages",
        "conversations",
        "chunks",
        "sources",
        "notebooks",
    ):
        op.drop_table(tablo)
