"""Uygulama ayarları: app_setting tablosu üzerinde tipli erişim katmanı."""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

from kitapkatalog.database import Database

DEFAULTS: dict[str, str] = {
    "school_name": "",
    "loan_period_days": "15",
    "loan_max_books": "3",
    "loan_period_days_staff": "30",
    "loan_max_books_staff": "5",
    "overdue_block": "1",
    "overdue_penalty_per_day": "0",
    "loan_max_renewals": "2",
    "backup_dir": "",
    "backup_keep": "10",
    "last_backup_at": "",
    "last_maintenance_at": "",
    "hold_enabled": "1",
    "hold_pickup_days": "3",
    "hold_max_per_member": "2",
    "voice_language": "tr",
    "voice_second_pass": "1",
    "voice_second_pass_language": "auto",
    "voice_prompt_bias": "1",
    "voice_prompt_extra": "",
}

_INT_KEYS = {
    "loan_period_days",
    "loan_max_books",
    "loan_period_days_staff",
    "loan_max_books_staff",
    "overdue_penalty_per_day",
    "loan_max_renewals",
    "backup_keep",
    "hold_pickup_days",
    "hold_max_per_member",
}
_BOOL_KEYS = {"overdue_block", "voice_second_pass", "voice_prompt_bias", "hold_enabled"}
_INT_RANGES: dict[str, tuple[int, int]] = {
    "loan_period_days": (1, 120),
    "loan_max_books": (1, 20),
    "loan_period_days_staff": (1, 365),
    "loan_max_books_staff": (1, 50),
    "overdue_penalty_per_day": (0, 10),
    "loan_max_renewals": (0, 10),
    "backup_keep": (1, 100),
    "hold_pickup_days": (1, 30),
    "hold_max_per_member": (1, 10),
}
_CHOICE_KEYS: dict[str, frozenset[str]] = {
    "voice_language": frozenset({"tr", "auto", "en"}),
    "voice_second_pass_language": frozenset({"auto", "en", "de", "fr", "ar"}),
}


class AppSettings:
    """app_setting tablosunu okuyup yazan hafif servis."""

    def __init__(self, database: Database) -> None:
        self._database = database

    def get(self, key: str) -> str:
        if key not in DEFAULTS:
            raise KeyError(f"Bilinmeyen ayar: {key}")
        row = self._database.fetchone("SELECT value FROM app_setting WHERE key = ?", (key,))
        return str(row[0]) if row is not None else DEFAULTS[key]

    def set(self, key: str, value: str) -> None:
        if key not in DEFAULTS:
            raise KeyError(f"Bilinmeyen ayar: {key}")
        normalized = self._normalize(key, value)
        now = datetime.now(UTC).isoformat(timespec="microseconds")
        with self._database.transaction() as connection:
            connection.execute(
                """
                INSERT INTO app_setting(key, value, updated_at) VALUES (?, ?, ?)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value,
                                               updated_at = excluded.updated_at
                """,
                (key, normalized, now),
            )

    def update(self, values: dict[str, Any]) -> dict[str, Any]:
        unknown = set(values) - set(DEFAULTS)
        if unknown:
            raise KeyError(f"Bilinmeyen ayar: {', '.join(sorted(unknown))}")
        # Validate every field before the first write. One malformed value must
        # not leave an otherwise rejected settings form half-applied.
        normalized = {key: self._normalize(key, value) for key, value in values.items()}
        now = datetime.now(UTC).isoformat(timespec="microseconds")
        with self._database.transaction(immediate=True) as connection:
            connection.executemany(
                """
                INSERT INTO app_setting(key, value, updated_at) VALUES (?, ?, ?)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value,
                                                   updated_at = excluded.updated_at
                """,
                [(key, value, now) for key, value in normalized.items()],
            )
        return self.as_dict()

    @staticmethod
    def _normalize(key: str, value: Any) -> str:
        if key in _INT_KEYS:
            try:
                number = int(value)
            except (TypeError, ValueError) as exc:
                raise ValueError(f"{key} tam sayı olmalıdır") from exc
            minimum, maximum = _INT_RANGES[key]
            if not minimum <= number <= maximum:
                raise ValueError(f"{key} {minimum}-{maximum} aralığında olmalıdır")
            return str(number)
        if key in _BOOL_KEYS:
            if isinstance(value, bool):
                return "1" if value else "0"
            text = str(value).strip().casefold()
            if text in {"1", "true", "on", "evet"}:
                return "1"
            if text in {"0", "false", "off", "hayır", "hayir", ""}:
                return "0"
            raise ValueError(f"{key} doğru/yanlış değeri olmalıdır")
        if key in _CHOICE_KEYS:
            text = str(value).strip()
            if text not in _CHOICE_KEYS[key]:
                allowed = ", ".join(sorted(_CHOICE_KEYS[key]))
                raise ValueError(f"{key} şunlardan biri olmalıdır: {allowed}")
            return text
        text = str(value or "")
        if "\x00" in text:
            raise ValueError(f"{key} NUL karakteri içeremez")
        maximum = 200 if key == "school_name" else 4096
        if len(text) > maximum:
            raise ValueError(f"{key} en fazla {maximum} karakter olabilir")
        if key in {"last_backup_at", "last_maintenance_at"} and text:
            try:
                datetime.fromisoformat(text.replace("Z", "+00:00"))
            except ValueError as exc:
                raise ValueError(f"{key} ISO-8601 tarih-saat olmalıdır") from exc
        return text

    def as_dict(self) -> dict[str, Any]:
        return {key: self._typed(key) for key in DEFAULTS}

    def _typed(self, key: str) -> Any:
        raw = self.get(key)
        if key in _INT_KEYS:
            return self._to_int(raw, key)
        if key in _BOOL_KEYS:
            return raw not in ("0", "", "false", "False")
        return raw

    @staticmethod
    def _to_int(raw: str, key: str) -> int:
        try:
            return int(raw)
        except ValueError:
            return int(DEFAULTS[key])

    # Tipli erişimciler -------------------------------------------------

    @property
    def school_name(self) -> str:
        return self.get("school_name")

    @property
    def loan_period_days(self) -> int:
        return self._to_int(self.get("loan_period_days"), "loan_period_days")

    @property
    def loan_max_books(self) -> int:
        return self._to_int(self.get("loan_max_books"), "loan_max_books")

    @property
    def loan_period_days_staff(self) -> int:
        return self._to_int(self.get("loan_period_days_staff"), "loan_period_days_staff")

    @property
    def loan_max_books_staff(self) -> int:
        return self._to_int(self.get("loan_max_books_staff"), "loan_max_books_staff")

    @property
    def overdue_block(self) -> bool:
        return self._typed("overdue_block")

    @property
    def overdue_penalty_per_day(self) -> int:
        return self._to_int(self.get("overdue_penalty_per_day"), "overdue_penalty_per_day")

    @property
    def loan_max_renewals(self) -> int:
        """Azami uzatma sayısı; 0 = sınırsız."""

        return self._to_int(self.get("loan_max_renewals"), "loan_max_renewals")

    @property
    def backup_dir(self) -> str:
        return self.get("backup_dir")

    @property
    def backup_keep(self) -> int:
        return self._to_int(self.get("backup_keep"), "backup_keep")

    @property
    def last_backup_at(self) -> str:
        return self.get("last_backup_at")

    @property
    def last_maintenance_at(self) -> str:
        return self.get("last_maintenance_at")

    @property
    def hold_enabled(self) -> bool:
        return self._typed("hold_enabled")

    @property
    def hold_pickup_days(self) -> int:
        return self._to_int(self.get("hold_pickup_days"), "hold_pickup_days")

    @property
    def hold_max_per_member(self) -> int:
        return self._to_int(self.get("hold_max_per_member"), "hold_max_per_member")

    def loan_period_for(self, member_type: str) -> int:
        return self.loan_period_days_staff if member_type == "staff" else self.loan_period_days

    def loan_limit_for(self, member_type: str) -> int:
        return self.loan_max_books_staff if member_type == "staff" else self.loan_max_books

    @property
    def voice_language(self) -> str:
        return self.get("voice_language")

    @property
    def voice_second_pass(self) -> bool:
        return self._typed("voice_second_pass")

    @property
    def voice_second_pass_language(self) -> str:
        return self.get("voice_second_pass_language")

    @property
    def voice_prompt_bias(self) -> bool:
        return self._typed("voice_prompt_bias")

    @property
    def voice_prompt_extra(self) -> str:
        return self.get("voice_prompt_extra")
