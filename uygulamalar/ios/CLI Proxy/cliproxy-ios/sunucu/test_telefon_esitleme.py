"""telefon_esitleme ucu: koruma, yenileme eşiği ve yenileme belirtecinin sızmaması."""
from __future__ import annotations

from datetime import UTC, datetime, timedelta
from types import SimpleNamespace

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from cliproxy.api import telefon_esitleme as mod
from cliproxy.auth.middleware import KeyContext, require_client
from cliproxy.credentials.store import Credential


class _Pool:
    def __init__(self, accounts):
        self.accounts = accounts

    def snapshot(self):
        return [SimpleNamespace(id=a.credential.qualified_id, kind=a.credential.kind, state="available") for a in self.accounts]

    def get_account(self, account_id):
        return next(a for a in self.accounts if a.credential.qualified_id == account_id)


class _Router:
    def __init__(self):
        self.calls = []

    async def ensure_fresh(self, account, *, force=False):
        self.calls.append((account.credential.qualified_id, force))
        account.credential = account.credential.model_copy(update={
            "access_token": "yeni-at", "expires_at": datetime.now(UTC) + timedelta(hours=8)})
        return account.credential


def _app(accounts, router):
    app = FastAPI()
    app.state.pool = _Pool(accounts)
    app.state.router = router
    app.include_router(mod.router, prefix="/v1")
    app.dependency_overrides[require_client] = lambda: KeyContext()
    return app


def _acc(provider, cid, minutes, kind="oauth"):
    cred = Credential(id=cid, provider=provider, kind=kind, access_token="eski-at", refresh_token="GIZLI-RT",
                      expires_at=datetime.now(UTC) + timedelta(minutes=minutes),
                      api_key="k" if kind == "apikey" else None, metadata={"account_id": "acc", "secret": "x"})
    return SimpleNamespace(credential=cred)


def test_token_yoksa_404(monkeypatch):
    monkeypatch.delenv(mod._ENV, raising=False)
    c = TestClient(_app([], _Router()))
    assert c.get("/v1/x/oauth-access", headers={"x-sync-token": "x"}).status_code == 404


def test_yanlis_token_404(monkeypatch):
    monkeypatch.setenv(mod._ENV, "dogru")
    c = TestClient(_app([], _Router()))
    assert c.get("/v1/x/oauth-access", headers={"x-sync-token": "yanlis"}).status_code == 404


def test_esitleme(monkeypatch):
    monkeypatch.setenv(mod._ENV, "dogru")
    r = _Router()
    accs = [_acc("claude", "claude-default", 5), _acc("codex", "abc", 600), _acc("gemini", "g", 600, kind="apikey")]
    c = TestClient(_app(accs, r))
    resp = c.get("/v1/x/oauth-access", headers={"x-sync-token": "dogru"})
    assert resp.status_code == 200
    body = resp.json()
    assert "GIZLI-RT" not in resp.text            # yenileme belirteci asla çıkmaz
    assert "secret" not in resp.text               # yalnız güvenli meta alanları
    ids = {(a["provider"], a["id"]): a for a in body["accounts"]}
    assert set(ids) == {("claude", "claude-default"), ("codex", "abc")}   # apikey hesapları yok
    assert ids[("claude", "claude-default")]["access_token"] == "yeni-at"  # 10 dk altı → yenilendi
    assert ids[("codex", "abc")]["access_token"] == "eski-at"              # uzun ömürlü → dokunulmadı
    assert r.calls == [("claude:claude-default", True)]
    assert all(a["expires_at"].endswith("+00:00") for a in body["accounts"])


def test_dilimsiz_tarih_utc(monkeypatch):
    monkeypatch.setenv(mod._ENV, "dogru")
    acc = _acc("codex", "n", 600)
    acc.credential = acc.credential.model_copy(update={"expires_at": datetime(2026, 10, 24, 23, 13, 55)})
    body = TestClient(_app([acc], _Router())).get("/v1/x/oauth-access", headers={"x-sync-token": "dogru"}).json()
    assert body["accounts"][0]["expires_at"] == "2026-10-24T23:13:55+00:00"
