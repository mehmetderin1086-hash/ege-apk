from __future__ import annotations

import logging
import re
from collections.abc import Mapping
from contextvars import ContextVar

trace_context: ContextVar[str] = ContextVar("bioprof_trace_id", default="-")

_SECRET_PATTERNS = (
    re.compile(r"(?i)(authorization\s*[:=]\s*bearer\s+)[^\s,;]+"),
    re.compile(r"(?i)((?:api[_-]?key|access[_-]?token|refresh[_-]?token)\s*[:=]\s*)[^\s,;]+"),
    re.compile(r"(?i)(x-api-key\s*[:=]\s*)[^\s,;]+"),
)


def redact(value: str) -> str:
    result = value
    for pattern in _SECRET_PATTERNS:
        result = pattern.sub(r"\1[REDACTED]", result)
    return result


class RedactingFilter(logging.Filter):
    def filter(self, record: logging.LogRecord) -> bool:
        if isinstance(record.msg, str):
            record.msg = redact(record.msg)
        if isinstance(record.args, tuple):
            record.args = tuple(
                redact(value) if isinstance(value, str) else value for value in record.args
            )
        elif isinstance(record.args, Mapping):
            record.args = {
                key: redact(value) if isinstance(value, str) else value
                for key, value in record.args.items()
            }
        record.trace_id = trace_context.get()
        return True


def configure_logging(level: str = "INFO") -> None:
    handler = logging.StreamHandler()
    handler.addFilter(RedactingFilter())
    handler.setFormatter(
        logging.Formatter("%(asctime)s %(levelname)s [%(trace_id)s] %(name)s: %(message)s")
    )
    root = logging.getLogger()
    root.handlers.clear()
    root.addHandler(handler)
    root.setLevel(level.upper())
