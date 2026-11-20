"""Flashcard desteleri, kartlar (SM-2 durumu kart üstünde) ve inceleme günlüğü.

Revision ID: 0003_flashcardlar
Revises: 0002_notlar
Create Date: 2026-08-07
"""

from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "0003_flashcardlar"
down_revision = "0002_notlar"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "flashcard_decks",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column(
            "notebook_id",
            sa.String(32),
            sa.ForeignKey("notebooks.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "artifact_id",
            sa.String(32),
            sa.ForeignKey("artifacts.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("title", sa.String(300), nullable=False),
        sa.Column("description", sa.Text(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
    )
    op.create_index("ix_flashcard_decks_notebook_id", "flashcard_decks", ["notebook_id"])
    op.create_table(
        "flashcards",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column(
            "deck_id",
            sa.String(32),
            sa.ForeignKey("flashcard_decks.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("front", sa.Text(), nullable=False),
        sa.Column("back", sa.Text(), nullable=False),
        sa.Column("citation_label", sa.String(16), nullable=True),
        sa.Column("citation_id", sa.String(64), nullable=True),
        sa.Column("source_title", sa.String(500), nullable=True),
        sa.Column("position", sa.Integer(), nullable=False),
        sa.Column("ease_factor", sa.Float(), nullable=False),
        sa.Column("interval_days", sa.Float(), nullable=False),
        sa.Column("repetitions", sa.Integer(), nullable=False),
        sa.Column("lapses", sa.Integer(), nullable=False),
        sa.Column("due_at", sa.DateTime(), nullable=False),
        sa.Column("suspended", sa.Boolean(), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False),
    )
    op.create_index("ix_flashcards_deck_id", "flashcards", ["deck_id"])
    op.create_index("ix_flashcards_due_at", "flashcards", ["due_at"])
    op.create_table(
        "flashcard_reviews",
        sa.Column("id", sa.String(32), primary_key=True),
        sa.Column(
            "card_id",
            sa.String(32),
            sa.ForeignKey("flashcards.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("reviewed_at", sa.DateTime(), nullable=False),
        sa.Column("grade", sa.Integer(), nullable=False),
        sa.Column("interval_before", sa.Float(), nullable=False),
        sa.Column("interval_after", sa.Float(), nullable=False),
        sa.Column("ease_before", sa.Float(), nullable=False),
        sa.Column("ease_after", sa.Float(), nullable=False),
    )
    op.create_index("ix_flashcard_reviews_card_id", "flashcard_reviews", ["card_id"])


def downgrade() -> None:
    op.drop_index("ix_flashcard_reviews_card_id", table_name="flashcard_reviews")
    op.drop_table("flashcard_reviews")
    op.drop_index("ix_flashcards_due_at", table_name="flashcards")
    op.drop_index("ix_flashcards_deck_id", table_name="flashcards")
    op.drop_table("flashcards")
    op.drop_index("ix_flashcard_decks_notebook_id", table_name="flashcard_decks")
    op.drop_table("flashcard_decks")
