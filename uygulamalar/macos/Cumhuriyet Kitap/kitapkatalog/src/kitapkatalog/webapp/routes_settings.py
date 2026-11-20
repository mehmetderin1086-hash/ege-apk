"""Uygulama ayarları uçları."""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Request

from kitapkatalog.settings import DEFAULTS
from kitapkatalog.webapp.state import WebState

router = APIRouter(tags=["settings"])

# Bu anahtarlardan biri değişince açık whisper oturumu (varsa) atılır; sonraki
# çağrı yeni dil/istem ayarlarıyla yeniden kurulur (bkz. WebState.reset_voice_session).
_VOICE_SETTING_KEYS = frozenset(
    {
        "voice_language",
        "voice_second_pass",
        "voice_second_pass_language",
        "voice_prompt_bias",
        "voice_prompt_extra",
    }
)


def _state(request: Request) -> WebState:
    return request.app.state.web


@router.get("/settings")
def get_settings(request: Request) -> dict[str, Any]:
    return _state(request).settings.as_dict()


@router.put("/settings")
def put_settings(request: Request, payload: dict[str, Any]) -> dict[str, Any]:
    state = _state(request)
    settings = state.settings
    unknown = set(payload) - set(DEFAULTS)
    if unknown:
        raise ValueError(f"Bilinmeyen ayar: {', '.join(sorted(unknown))}")
    touched = _VOICE_SETTING_KEYS & set(payload)
    before = {key: settings.get(key) for key in touched}
    updated = settings.update(payload)
    if any(settings.get(key) != before[key] for key in touched):
        state.reset_voice_session()
    return updated
