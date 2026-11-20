"""Oturum ve geçici dosya yönetimi.

Her tarayıcı oturumu için ``storage/sessions/<id>/`` altında bir çalışma
klasörü tutulur. Yüklenen dosyalar ``dosya_id`` ile adreslenir; üretilen
çıktılar da aynı klasöre yazılıp indirme bağlantısıyla sunulur.
"""
from __future__ import annotations

import re
import shutil
import time
import uuid
from dataclasses import dataclass
from pathlib import Path

from . import config


def _new_id() -> str:
    return uuid.uuid4().hex


_ID_RE = re.compile(r"[A-Za-z0-9]{1,128}")


def _valid_id(value: str | None) -> str | None:
    """Yalnızca uygulamanın ürettiği güvenli kimlik biçimini kabul et."""
    if value and _ID_RE.fullmatch(value):
        return value
    return None


@dataclass
class StoredFile:
    file_id: str
    name: str
    path: Path
    size: int
    kind: str  # "pdf" | "image" | "office" | "other"


def _kind_for(name: str) -> str:
    ext = Path(name).suffix.lower()
    if ext in config.PDF_EXTS:
        return "pdf"
    if ext in config.IMAGE_EXTS:
        return "image"
    if ext in config.OFFICE_EXTS:
        return "office"
    return "other"


class Session:
    def __init__(self, session_id: str):
        self.id = session_id
        self.dir = config.SESSIONS_DIR / session_id
        self.dir.mkdir(parents=True, exist_ok=True)

    def touch(self) -> None:
        try:
            self.dir.touch()
        except OSError:
            pass

    # ---- Dosya kayıt / erişim ----
    def save_upload(self, filename: str, data: bytes) -> StoredFile:
        file_id = _new_id()
        safe_name = Path(filename).name or "dosya"
        fdir = self.dir / file_id
        fdir.mkdir(parents=True, exist_ok=True)
        path = fdir / safe_name
        path.write_bytes(data)
        return StoredFile(
            file_id=file_id,
            name=safe_name,
            path=path,
            size=len(data),
            kind=_kind_for(safe_name),
        )

    def path_for(self, file_id: str) -> Path | None:
        safe_id = _valid_id(file_id)
        if safe_id is None:
            return None
        fdir = self.dir / safe_id
        if not fdir.is_dir():
            return None
        for p in fdir.iterdir():
            if p.is_file():
                return p
        return None

    def stored_file(self, file_id: str) -> StoredFile | None:
        path = self.path_for(file_id)
        if path is None:
            return None
        return StoredFile(
            file_id=file_id,
            name=path.name,
            path=path,
            size=path.stat().st_size,
            kind=_kind_for(path.name),
        )

    def new_output_path(self, filename: str) -> tuple[str, Path]:
        """Yeni bir çıktı dosyası için (file_id, path) döndürür."""
        file_id = _new_id()
        fdir = self.dir / file_id
        fdir.mkdir(parents=True, exist_ok=True)
        return file_id, fdir / Path(filename).name

    def register_output(self, filename: str, data: bytes) -> StoredFile:
        file_id, path = self.new_output_path(filename)
        path.write_bytes(data)
        return StoredFile(
            file_id=file_id,
            name=path.name,
            path=path,
            size=len(data),
            kind=_kind_for(path.name),
        )

    def list_files(self) -> list[StoredFile]:
        """Oturumdaki dosyaları en yeniden eskiye doğru döndürür."""
        files: list[tuple[float, StoredFile]] = []
        if not self.dir.is_dir():
            return []
        for fdir in self.dir.iterdir():
            if not fdir.is_dir() or _valid_id(fdir.name) is None:
                continue
            sf = self.stored_file(fdir.name)
            if sf is None:
                continue
            try:
                modified = sf.path.stat().st_mtime
            except OSError:
                modified = 0
            files.append((modified, sf))
        files.sort(key=lambda item: item[0], reverse=True)
        return [sf for _, sf in files]

    def delete_file(self, file_id: str) -> bool:
        safe_id = _valid_id(file_id)
        if safe_id is None:
            return False
        fdir = self.dir / safe_id
        if not fdir.is_dir():
            return False
        shutil.rmtree(fdir)
        self.touch()
        return True


class SessionManager:
    def __init__(self):
        config.ensure_dirs()

    def get_or_create(self, session_id: str | None) -> Session:
        sid = _valid_id(session_id)
        if sid:
            return Session(sid)
        return Session(_new_id())

    def get(self, session_id: str) -> Session | None:
        sid = _valid_id(session_id)
        if not sid:
            return None
        d = config.SESSIONS_DIR / sid
        if d.is_dir():
            return Session(sid)
        return None

    def cleanup_expired(self) -> int:
        """TTL'i geçmiş oturum klasörlerini siler. Silinen sayısını döndürür."""
        now = time.time()
        removed = 0
        if not config.SESSIONS_DIR.is_dir():
            return 0
        for d in config.SESSIONS_DIR.iterdir():
            if not d.is_dir():
                continue
            try:
                age = now - d.stat().st_mtime
            except OSError:
                continue
            if age > config.SESSION_TTL_SECONDS:
                shutil.rmtree(d, ignore_errors=True)
                removed += 1
        return removed

    def delete(self, session_id: str) -> bool:
        sid = _valid_id(session_id)
        if sid is None:
            return False
        directory = config.SESSIONS_DIR / sid
        if not directory.is_dir():
            return False
        shutil.rmtree(directory)
        return True


manager = SessionManager()
