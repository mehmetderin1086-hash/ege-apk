"""Create the initial DownloadHub schema.

Revision ID: 0001_initial
Revises:
Create Date: 2026-07-19
"""

from __future__ import annotations

from alembic import op

from downloadhub.models import Base

revision = "0001_initial"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    Base.metadata.create_all(bind=op.get_bind(), checkfirst=True)


def downgrade() -> None:
    Base.metadata.drop_all(bind=op.get_bind(), checkfirst=True)
