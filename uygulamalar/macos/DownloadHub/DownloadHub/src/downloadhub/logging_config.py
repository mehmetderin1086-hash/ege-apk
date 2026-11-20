from __future__ import annotations

import logging
from logging.handlers import TimedRotatingFileHandler
from pathlib import Path

from .security import redact_url


class SecretFilter(logging.Filter):
    def filter(self, record: logging.LogRecord) -> bool:
        message = record.getMessage()
        if "http://" in message or "https://" in message:
            words = [
                redact_url(word) if word.startswith(("http://", "https://")) else word
                for word in message.split()
            ]
            record.msg = " ".join(words)
            record.args = ()
        return True


def configure_logging(log_dir: Path) -> None:
    log_dir.mkdir(parents=True, exist_ok=True)
    root = logging.getLogger()
    root.setLevel(logging.INFO)
    if any(isinstance(handler, TimedRotatingFileHandler) for handler in root.handlers):
        return
    formatter = logging.Formatter("%(asctime)s %(levelname)s %(name)s %(message)s", "%Y-%m-%dT%H:%M:%S%z")
    handler = TimedRotatingFileHandler(
        log_dir / "downloadhub.log",
        when="midnight",
        backupCount=7,
        encoding="utf-8",
    )
    handler.setFormatter(formatter)
    handler.addFilter(SecretFilter())
    root.addHandler(handler)
