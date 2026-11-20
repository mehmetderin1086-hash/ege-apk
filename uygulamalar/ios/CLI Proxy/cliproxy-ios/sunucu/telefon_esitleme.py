"""Telefon eşitleme ucu (17 Eki 2026): iPhone'daki CLI Proxy uygulaması OAuth erişim
belirteçlerini buradan çeker; yenileme yalnız sunucuda yapılır.

Neden: Claude ve OpenAI yenileme belirtecini her kullanımda döndürür (rotasyon). Aynı
hesabı telefon ve sunucu ayrı ayrı yenilerse biri düşer. Bu uç yalnız ERİŞİM belirtecini
(kısa ömürlü) verir; yenileme belirteci asla dışarı çıkmaz.

Koruma: normal istemci anahtarı (Caddy X-Api-Key ekler) + ayrı `X-Sync-Token`
(CLIPROXY_TELEFON_ESITLEME_TOKEN). Token tanımlı değilse uç 404 döner.
Geri alma: main.py'deki include satırını ve bu dosyayı sil, servisi yeniden başlat.
"""

from __future__ import annotations

import hmac
import os
from datetime import UTC, datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException, Request

from ..auth.middleware import KeyContext, require_client
from ..logging import get_logger

router = APIRouter()
log = get_logger(__name__)

_ENV = "CLIPROXY_TELEFON_ESITLEME_TOKEN"
_MIN_LIFETIME = timedelta(minutes=10)
_SAFE_META = ("account_id", "email", "label", "plan", "project_id")


@router.get("/x/oauth-access")
async def oauth_access(request: Request, ctx: KeyContext = Depends(require_client)):
    expected = os.environ.get(_ENV, "")
    given = request.headers.get("x-sync-token", "")
    if not expected or not hmac.compare_digest(given.encode(), expected.encode()):
        raise HTTPException(status_code=404, detail="Not Found")

    pool = request.app.state.pool
    rtr = request.app.state.router
    now = datetime.now(UTC)
    out = []
    for health in pool.snapshot():
        if health.kind != "oauth":
            continue
        account = pool.get_account(health.id)
        if account is None:
            continue
        cred = account.credential
        exp = cred.expires_at
        if exp is not None and exp.tzinfo is None:
            exp = exp.replace(tzinfo=UTC)
        try:
            if exp is not None and exp - now < _MIN_LIFETIME:
                cred = await rtr.ensure_fresh(account, force=True)
        except Exception as exc:  # yenilenemeyen hesap listeden düşmez, eski belirteç döner
            log.warning("telefon_esitleme_yenilenemedi", id=cred.qualified_id, error=str(exc)[:120])
        bare_id = cred.id.split(":", 1)[1] if cred.id.startswith(f"{cred.provider}:") else cred.id
        out.append({
            "provider": cred.provider,
            "id": bare_id,
            "access_token": cred.access_token,
            # Saat dilimsiz kayıtlar UTC sayılır; telefon dilimsiz ISO tarihini okuyamaz.
            "expires_at": (cred.expires_at if cred.expires_at.tzinfo else cred.expires_at.replace(tzinfo=UTC)).isoformat()
            if cred.expires_at else None,
            "metadata": {k: str(v) for k, v in (cred.metadata or {}).items() if k in _SAFE_META},
            "state": health.state,
        })
    log.info("telefon_esitleme", hesap=len(out))
    return {"accounts": out, "server_time": now.isoformat()}
