from __future__ import annotations

import httpx
import pytest

from downloadhub.safe_proxy import SafeOutboundProxy

from .conftest import PAYLOAD


@pytest.mark.asyncio
async def test_safe_proxy_blocks_private_target_by_default(app_settings, file_server: str) -> None:
    app_settings.allow_private_networks = False
    proxy = SafeOutboundProxy(app_settings)
    await proxy.start()
    try:
        async with httpx.AsyncClient(proxy=app_settings.safe_proxy_url, trust_env=False) as client:
            response = await client.get(file_server)
        assert response.status_code == 403
    finally:
        await proxy.stop()


@pytest.mark.asyncio
async def test_safe_proxy_relays_range_source_when_explicitly_allowed(
    app_settings,
    file_server: str,
) -> None:
    app_settings.allow_private_networks = True
    proxy = SafeOutboundProxy(app_settings)
    await proxy.start()
    try:
        async with httpx.AsyncClient(proxy=app_settings.safe_proxy_url, trust_env=False) as client:
            response = await client.get(file_server, headers={"Range": "bytes=10-"})
        assert response.status_code == 206
        assert response.content == PAYLOAD[10:]
    finally:
        await proxy.stop()
