# DownloadHub migrations

Alembic uses `downloadhub.models.Base.metadata` and the same database URL as the
application. The application data directory is prepared before an online migration.

Create the first revision only after the ORM model set is stable:

```bash
uv run alembic revision --autogenerate -m "initial schema"
uv run alembic upgrade head
```

Every generated revision must be reviewed. In particular, verify SQLite batch
operations, foreign-key cascade behavior, indexes, uniqueness constraints and JSON
defaults. Never run `downgrade` against a user's only database copy; make a backup
first.
