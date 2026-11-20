"""SQLite (WAL) — geçmiş, projeler, parçalar, işler.

Sıfır ek bağımlılık: stdlib sqlite3, çağrı başına bağlantı.
"""
from __future__ import annotations

import sqlite3

from app.config import DB_PATH, ensure_dirs

_SCHEMA = """
CREATE TABLE IF NOT EXISTS history (
  id TEXT PRIMARY KEY,
  type TEXT NOT NULL,             -- tts | vc | stt
  text TEXT,
  params TEXT,                    -- JSON
  voice_id TEXT,
  path TEXT,
  duration_s REAL,
  created_at REAL
);
CREATE TABLE IF NOT EXISTS projects (
  id TEXT PRIMARY KEY,
  title TEXT,
  text TEXT,
  voice_id TEXT,
  params TEXT,                    -- JSON
  status TEXT DEFAULT 'draft',    -- draft | running | done | error
  created_at REAL
);
CREATE TABLE IF NOT EXISTS chunks (
  project_id TEXT,
  idx INTEGER,
  text TEXT,
  status TEXT DEFAULT 'pending',  -- pending | done | error
  path TEXT,
  paragraph_break INTEGER DEFAULT 0,
  PRIMARY KEY (project_id, idx)
);
CREATE TABLE IF NOT EXISTS jobs (
  id TEXT PRIMARY KEY,
  type TEXT,
  status TEXT,                    -- queued | running | done | error | cancelled
  progress REAL DEFAULT 0,
  message TEXT,
  payload TEXT,                   -- JSON
  result TEXT,                    -- JSON
  created_at REAL,
  updated_at REAL
);
"""


def connect() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH, timeout=10)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=ON")
    return conn


def init_db() -> None:
    ensure_dirs()
    with connect() as conn:
        conn.executescript(_SCHEMA)
