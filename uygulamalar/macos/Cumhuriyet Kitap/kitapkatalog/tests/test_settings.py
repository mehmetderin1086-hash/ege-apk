from __future__ import annotations

from pathlib import Path

import pytest

from kitapkatalog.database import Database
from kitapkatalog.settings import AppSettings


def _settings(tmp_path: Path) -> AppSettings:
    return AppSettings(Database(tmp_path / "catalog.sqlite3"))


def test_defaults(tmp_path: Path) -> None:
    settings = _settings(tmp_path)
    assert settings.school_name == ""
    assert settings.loan_period_days == 15
    assert settings.loan_max_books == 3
    assert settings.loan_period_days_staff == 30
    assert settings.loan_max_books_staff == 5
    assert settings.overdue_block is True
    assert settings.overdue_penalty_per_day == 0
    assert settings.backup_keep == 10
    assert settings.backup_dir == ""
    assert settings.last_backup_at == ""


def test_set_and_get_roundtrip(tmp_path: Path) -> None:
    settings = _settings(tmp_path)
    settings.set("school_name", "Atatürk Anadolu Lisesi")
    settings.set("loan_period_days", "21")
    settings.set("overdue_block", "0")
    assert settings.school_name == "Atatürk Anadolu Lisesi"
    assert settings.loan_period_days == 21
    assert settings.overdue_block is False
    with pytest.raises(ValueError, match="tam sayı"):
        settings.set("loan_max_books", "bozuk")
    assert settings.loan_max_books == 3


def test_member_type_rules(tmp_path: Path) -> None:
    settings = _settings(tmp_path)
    assert settings.loan_period_for("student") == 15
    assert settings.loan_period_for("staff") == 30
    assert settings.loan_limit_for("student") == 3
    assert settings.loan_limit_for("staff") == 5


def test_as_dict_and_bulk_update(tmp_path: Path) -> None:
    settings = _settings(tmp_path)
    updated = settings.update({"school_name": "Cumhuriyet Ortaokulu", "loan_max_books": 4})
    assert updated["school_name"] == "Cumhuriyet Ortaokulu"
    assert updated["loan_max_books"] == 4
    assert settings.as_dict()["loan_period_days"] == 15


@pytest.mark.parametrize(
    ("key", "value"),
    [
        ("loan_period_days", 0),
        ("loan_max_books", 21),
        ("loan_period_days_staff", 366),
        ("loan_max_books_staff", 51),
        ("overdue_penalty_per_day", -1),
        ("loan_max_renewals", 11),
        ("backup_keep", 0),
    ],
)
def test_numeric_ranges_are_enforced(tmp_path: Path, key: str, value: int) -> None:
    settings = _settings(tmp_path)
    with pytest.raises(ValueError, match="aralığında"):
        settings.set(key, value)


def test_bulk_update_is_atomic_when_one_value_is_invalid(tmp_path: Path) -> None:
    settings = _settings(tmp_path)
    with pytest.raises(ValueError, match="loan_max_books"):
        settings.update({"school_name": "Yazılmamalı", "loan_max_books": 0})
    assert settings.school_name == ""
    assert settings.loan_max_books == 3


def test_boolean_and_internal_timestamp_validation(tmp_path: Path) -> None:
    settings = _settings(tmp_path)
    settings.set("overdue_block", "hayır")
    assert settings.overdue_block is False
    settings.set("last_backup_at", "2026-08-08T13:45:00+00:00")
    with pytest.raises(ValueError, match="ISO-8601"):
        settings.set("last_backup_at", "dün")


def test_voice_defaults(tmp_path: Path) -> None:
    settings = _settings(tmp_path)
    assert settings.voice_language == "tr"
    assert settings.voice_second_pass is True
    assert settings.voice_second_pass_language == "auto"
    assert settings.voice_prompt_bias is True
    assert settings.voice_prompt_extra == ""


def test_voice_language_accepts_whitelisted_values(tmp_path: Path) -> None:
    settings = _settings(tmp_path)
    settings.set("voice_language", "en")
    assert settings.voice_language == "en"
    with pytest.raises(ValueError, match="şunlardan biri olmalıdır"):
        settings.set("voice_language", "fr")  # ana dil listesinde yok


def test_voice_second_pass_language_accepts_whitelisted_values(tmp_path: Path) -> None:
    settings = _settings(tmp_path)
    for value in ("auto", "en", "de", "fr", "ar"):
        settings.set("voice_second_pass_language", value)
        assert settings.voice_second_pass_language == value
    with pytest.raises(ValueError, match="şunlardan biri olmalıdır"):
        settings.set("voice_second_pass_language", "tr")


def test_voice_bool_keys_toggle(tmp_path: Path) -> None:
    settings = _settings(tmp_path)
    settings.set("voice_second_pass", "0")
    assert settings.voice_second_pass is False
    settings.set("voice_prompt_bias", "hayır")
    assert settings.voice_prompt_bias is False


def test_voice_prompt_extra_free_text(tmp_path: Path) -> None:
    settings = _settings(tmp_path)
    settings.set("voice_prompt_extra", "Nutuk, Safahat")
    assert settings.voice_prompt_extra == "Nutuk, Safahat"
