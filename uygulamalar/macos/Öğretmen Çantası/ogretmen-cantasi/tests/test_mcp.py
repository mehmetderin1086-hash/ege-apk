"""P4.5: Öğretmen Çantası salt okunur MCP sunucusu (Streamable HTTP, JSON yanıt)."""

from __future__ import annotations

import json

from test_entegrasyon import _okul_verisi  # tests/ paket değil; pytest dizini sys.path'e ekler

from ogretmen_cantasi import entegrasyon

MCP = "/api/v1/mcp"


def _yetki() -> dict[str, str]:
    return {"Authorization": f"Bearer {entegrasyon.yerel_belirtec()}"}


def _baslat(istemci) -> dict[str, str]:
    yanit = istemci.post(
        MCP,
        headers=_yetki(),
        json={
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "test"}},
        },
    )
    assert yanit.status_code == 200
    sonuc = yanit.json()["result"]
    assert sonuc["protocolVersion"] == "2025-06-18"
    assert "tools" in sonuc["capabilities"]
    oturum = yanit.headers["mcp-session-id"]
    assert oturum
    basliklar = {**_yetki(), "Mcp-Session-Id": oturum}
    bildirim = istemci.post(MCP, headers=basliklar, json={"jsonrpc": "2.0", "method": "notifications/initialized"})
    assert bildirim.status_code == 202
    return basliklar


def test_mcp_yetkisiz_401(istemci) -> None:
    assert istemci.post(MCP, json={"jsonrpc": "2.0", "id": 1, "method": "initialize"}).status_code == 401


def test_mcp_initialize_tools_list_ve_bugun(istemci, tmp_path) -> None:
    sube_id = _okul_verisi(tmp_path)
    basliklar = _baslat(istemci)
    liste = istemci.post(MCP, headers=basliklar, json={"jsonrpc": "2.0", "id": 2, "method": "tools/list"}).json()
    adlar = {a["name"] for a in liste["result"]["tools"]}
    assert {"bugun", "yoklama_oku", "ders_defteri_oku"} <= adlar
    for arac in liste["result"]["tools"]:
        sema = arac["inputSchema"]
        assert sema["type"] == "object"
        # Düz şema: iç içe nesne ya da $ref yok (Asistan dinamik araca çevirebilsin).
        for ozellik in sema["properties"].values():
            assert ozellik["type"] in {"string", "integer", "number", "boolean"}
        assert "$ref" not in json.dumps(sema)

    cagri = istemci.post(
        MCP,
        headers=basliklar,
        json={"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {"name": "bugun", "arguments": {"tarih": "2026-09-15"}}},
    ).json()["result"]
    assert cagri["isError"] is False
    veri = json.loads(cagri["content"][0]["text"])
    assert veri["bloklar"][0]["sube_id"] == sube_id

    yoklama = istemci.post(
        MCP,
        headers=basliklar,
        json={
            "jsonrpc": "2.0",
            "id": 4,
            "method": "tools/call",
            "params": {"name": "yoklama_oku", "arguments": {"sube_id": sube_id, "tarih": "2026-09-15"}},
        },
    ).json()["result"]
    assert yoklama["structuredContent"]["sayilar"] == {"var": 1, "yok": 1}

    defter = istemci.post(
        MCP,
        headers=basliklar,
        json={
            "jsonrpc": "2.0",
            "id": 5,
            "method": "tools/call",
            "params": {"name": "ders_defteri_oku", "arguments": {"sube_id": str(sube_id), "tarih": "2026-09-15"}},
        },
    ).json()["result"]
    assert defter["structuredContent"]["kayitlar"][0]["kazanim_kodlari"] == ["BİY.9.1.1"]


def test_mcp_bilinmeyen_arac_ve_yontem_jsonrpc_hatasi(istemci) -> None:
    basliklar = _baslat(istemci)
    yanit = istemci.post(
        MCP,
        headers=basliklar,
        json={"jsonrpc": "2.0", "id": 7, "method": "tools/call", "params": {"name": "sil", "arguments": {}}},
    ).json()
    assert yanit["id"] == 7 and yanit["error"]["code"] == -32602
    yontem = istemci.post(MCP, headers=basliklar, json={"jsonrpc": "2.0", "id": 8, "method": "resources/list"}).json()
    assert yontem["error"]["code"] == -32601


def test_mcp_arac_hatasi_iserror_doner(istemci) -> None:
    basliklar = _baslat(istemci)
    sonuc = istemci.post(
        MCP,
        headers=basliklar,
        json={"jsonrpc": "2.0", "id": 9, "method": "tools/call", "params": {"name": "yoklama_oku", "arguments": {}}},
    ).json()["result"]
    assert sonuc["isError"] is True and "sube_id" in sonuc["content"][0]["text"]
    yok = istemci.post(
        MCP,
        headers=basliklar,
        json={"jsonrpc": "2.0", "id": 10, "method": "tools/call", "params": {"name": "yoklama_oku", "arguments": {"sube_id": 999}}},
    ).json()["result"]
    assert yok["isError"] is True


def test_mcp_oturum_denetimi(istemci) -> None:
    istek = {"jsonrpc": "2.0", "id": 2, "method": "tools/list"}
    assert istemci.post(MCP, headers=_yetki(), json=istek).status_code == 400
    assert istemci.post(MCP, headers={**_yetki(), "Mcp-Session-Id": "bilinmeyen"}, json=istek).status_code == 404
    basliklar = _baslat(istemci)
    assert istemci.delete(MCP, headers=basliklar).status_code == 204
    assert istemci.post(MCP, headers=basliklar, json=istek).status_code == 404
    assert istemci.get(MCP, headers=_yetki()).status_code == 405


def test_mcp_bozuk_govde(istemci) -> None:
    bozuk = istemci.post(MCP, headers={**_yetki(), "Content-Type": "application/json"}, content=b"{")
    assert bozuk.status_code == 400 and bozuk.json()["error"]["code"] == -32700
    toplu = istemci.post(MCP, headers=_yetki(), json=[{"jsonrpc": "2.0", "id": 1, "method": "ping"}])
    assert toplu.status_code == 400
