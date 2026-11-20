"""Notlar tablosu — tarayıcı localStorage'ından DB'ye taşınan kullanıcı notları.

Revision ID: 0002_notlar
Revises: 0001_baseline
Create Date: 2026-08-07
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "0002_notlar"
down_revision = "0001_baseline"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "notes",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column(
            "notebook_id",
            sa.String(32),
            sa.ForeignKey("notebooks.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("title", sa.String(300), nullable=False),
        sa.Column("content", sa.Text(), nullable=False),
        sa.Column("pinned", sa.Boolean(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
        sa.Column("updated_at", sa.DateTime(), nullable=False),
    )
    op.create_index("ix_notes_notebook_id", "notes", ["notebook_id"])


def downgrade() -> None:
    op.drop_index("ix_notes_notebook_id", table_name="notes")
    op.drop_table("notes")
