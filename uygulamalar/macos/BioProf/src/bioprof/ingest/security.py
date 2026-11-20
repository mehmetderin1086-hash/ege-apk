from __future__ import annotations

import re
from collections.abc import Iterable

from bioprof.ingest.models import PIIFinding

_EMAIL = re.compile(r"(?<![\w.+-])[\w.+-]+@[\w-]+(?:\.[\w-]+)+", re.IGNORECASE)
_PHONE = re.compile(
    r"(?<!\d)(?:\+?90\s*)?(?:\(?0?5\d{2}\)?)[\s.-]*\d{3}[\s.-]*\d{2}[\s.-]*\d{2}(?!\d)"
)
_LABELED_IDENTIFIER = re.compile(
    r"\b(?:t\.?\s*c\.?\s*kimlik(?:\s*no)?|tc\s*no|hasta\s*(?:no|id)|patient\s*id|"
    r"subject\s*id|sample\s*id|katılımcı\s*(?:no|id)|örnek\s*(?:no|id)|"
    r"medical\s*record(?:\s*number)?|mrn|protokol\s*no)\s*[:#-]?\s*([A-Z0-9-]{5,32})",
    re.IGNORECASE,
)
_LABELED_DOB = re.compile(
    r"\b(?:do[ğg]um\s*tarihi|date\s*of\s*birth|dob)\s*[:#-]?\s*"
    r"(?:\d{1,2}[./-]\d{1,2}[./-]\d{2,4}|\d{4}-\d{2}-\d{2})",
    re.IGNORECASE,
)
_LABELED_ADDRESS = re.compile(r"\b(?:adres(?:i)?|address)\s*[:#-]\s*[^\n]{12,160}", re.IGNORECASE)
_LABELED_PERSON = re.compile(
    r"\b(?:hasta|patient|katılımcı|participant|subject)\s*"
    r"(?:adı(?:\s*soyadı)?|ad[ıi]?\s*soyad[ıi]?|name)?\s*[:#-]\s*"
    r"[A-ZÇĞİÖŞÜ][A-Za-zÇĞİÖŞÜçğıöşü'-]{1,40}"
    r"(?:\s+[A-ZÇĞİÖŞÜ][A-Za-zÇĞİÖŞÜçğıöşü'-]{1,40}){1,3}",
    re.IGNORECASE,
)
_SENSITIVE_FILENAME = re.compile(
    r"(?:^|[/\\])(?:hasta|patient|subject)[_ -]+[A-Za-zÇĞİÖŞÜçğıöşü'-]{2,}"
    r"(?:[_ -]+[A-Za-zÇĞİÖŞÜçğıöşü'-]{2,})+",
    re.IGNORECASE,
)
_VCF_SAMPLE_HEADER = re.compile(
    r"(?m)^#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\t[^\r\n]+$"
)
_IP_ADDRESS = re.compile(
    r"\b(?:25[0-5]|2[0-4]\d|1?\d?\d)(?:\."
    r"(?:25[0-5]|2[0-4]\d|1?\d?\d)){3}\b"
)


def _valid_turkish_identity_number(value: str) -> bool:
    """Validate a T.C. identity number without retaining or returning it."""

    if len(value) != 11 or not value.isdigit() or value[0] == "0":
        return False
    digits = [int(char) for char in value]
    tenth = ((sum(digits[0:9:2]) * 7) - sum(digits[1:8:2])) % 10
    eleventh = sum(digits[:10]) % 10
    return digits[9] == tenth and digits[10] == eleventh


def _redact(value: str) -> str:
    value = " ".join(value.split())
    if len(value) <= 8:
        return "[REDACTED]"
    return f"{value[:3]}…{value[-2:]}"


class SensitiveDataScanner:
    """Conservative offline screen for directly identifying health data.

    It intentionally does not classify ordinary biomedical prose as PHI. A source
    is quarantined only when a direct identifier is present (or when a caller adds
    another explicit pattern), avoiding the common failure where every paper that
    mentions a patient is rejected.
    """

    def __init__(self, extra_patterns: Iterable[tuple[str, re.Pattern[str]]] = ()) -> None:
        self._patterns: list[tuple[str, re.Pattern[str]]] = [
            ("email", _EMAIL),
            ("phone", _PHONE),
            ("labeled_identifier", _LABELED_IDENTIFIER),
            ("date_of_birth", _LABELED_DOB),
            ("address", _LABELED_ADDRESS),
            ("labeled_person", _LABELED_PERSON),
            ("sensitive_filename", _SENSITIVE_FILENAME),
            ("genetic_sample_columns", _VCF_SAMPLE_HEADER),
        ]
        self._patterns.extend(extra_patterns)

    def scan(self, text: str) -> list[PIIFinding]:
        findings: list[PIIFinding] = []
        seen: set[tuple[str, str]] = set()
        patient_context = bool(
            re.search(
                r"\b(?:patient|hasta|subject|katılımcı|clinical\s+record|klinik\s+kayıt)\b",
                text,
                re.IGNORECASE,
            )
        )
        for kind, pattern in self._patterns:
            for match in pattern.finditer(text):
                value = match.group(0)
                key = (kind, value.casefold())
                if key in seen:
                    continue
                seen.add(key)
                severity = "high"
                if kind in {"email", "phone"} and not patient_context:
                    severity = "medium"
                findings.append(PIIFinding(kind=kind, excerpt=_redact(value), severity=severity))

        for match in re.finditer(r"(?<!\d)\d{11}(?!\d)", text):
            if _valid_turkish_identity_number(match.group(0)):
                findings.append(PIIFinding(kind="turkish_identity_number", excerpt="[REDACTED]"))

        # IPs are low severity by themselves and do not cause quarantine. They are
        # still surfaced to callers when combined with explicit patient wording.
        if patient_context:
            for match in _IP_ADDRESS.finditer(text):
                findings.append(
                    PIIFinding(
                        kind="patient_network_identifier",
                        excerpt=_redact(match.group(0)),
                        severity="high",
                    )
                )
        return findings

    @staticmethod
    def should_quarantine(findings: Iterable[PIIFinding]) -> bool:
        return any(finding.severity == "high" for finding in findings)
