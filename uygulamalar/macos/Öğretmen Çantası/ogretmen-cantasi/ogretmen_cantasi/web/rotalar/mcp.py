"""Salt okunur MCP sunucusu (Streamable HTTP, JSON yanıt): `POST /api/v1/mcp`.

Asistan gibi MCP istemcileri günün derslerini, yoklamayı ve ders defterini
buradan okur. Yazma aracı YOKTUR. Uç `/api/v1/` altında olduğu için
middleware'in Bearer / X-Api-Token denetimi kendiliğinden geçerlidir.

Desteklenenler: `initialize` (Mcp-Session-Id üretir), `notifications/initialized`
(202), `ping`, `tools/list`, `tools/call`. Toplu (dizi) istek desteklenmez.
Oturumlar bellekte tutulur (en çok `AZAMI_OTURUM`); süreç yeniden başlarsa
bilinmeyen oturum 404 alır ve istemci yeniden `initialize` eder.
"""

from __future__ import annotations

import json
import secrets
import sqlite3
from collections import OrderedDict
from collections.abc import Callable
from typing import Any

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, Response

from ... import servis
from .bugun import gunun_ozeti_json
from .entegrasyon import api_tarihi, ders_defteri_ozeti, yoklama_ozeti

PROTOKOL = "2025-06-18"
DESTEKLENEN_PROTOKOLLER = {"2025-06-18", "2025-03-26", "2024-11-05"}
AZAMI_OTURUM = 64

# JSON-RPC hata kodları
AYRISTIRMA = -32700
GECERSIZ_ISTEK = -32600
YONTEM_YOK = -32601
GECERSIZ_PARAMETRE = -32602

_TARIH = {"type": "string", "description": "YYYY-AA-GG; boşsa bugün"}

ARACLAR: list[dict[str, Any]] = [
    {
        "name": "bugun",
        "description": "Günün ders programı: şube blokları, haftanın planı (kazanımlar), "
        "yoklama alındı mı, ders defteri kaydı, tatil ve devamsızlık uyarıları. Salt okunur.",
        "inputSchema": {"type": "object", "properties": {"tarih": _TARIH}},
    },
    {
        "name": "subeler",
        "description": "Aktif öğretim yılının şubeleri (kimlik, ad, sınıf). Salt okunur.",
        "inputSchema": {"type": "object", "properties": {}},
    },
    {
        "name": "yoklama_oku",
        "description": "Bir şubenin o günkü yoklaması (saat verilmezse günün ilk dersi) "
        "ve devamsızlık özeti. Salt okunur.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "sube_id": {"type": "integer", "description": "Şube kimliği (bugun ya da subeler aracından)"},
                "tarih": _TARIH,
                "saat": {"type": "integer", "description": "Ders saati (1-12); isteğe bağlı"},
            },
            "required": ["sube_id"],
        },
    },
    {
        "name": "ders_defteri_oku",
        "description": "Bir şubenin o günkü ders defteri kayıtları (kazanımlar, durum, açıklama). Salt okunur.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "sube_id": {"type": "integer", "description": "Şube kimliği"},
                "tarih": _TARIH,
            },
            "required": ["sube_id"],
        },
    },
]


class AracHatasi(Exception):
    """Araç çalıştı ama kullanıcıya gösterilecek bir hata verdi (isError: true)."""


def _tam_sayi(arg: dict, ad: str, zorunlu: bool = False) -> int | None:
    deger = arg.get(ad)
    if deger is None or deger == "":
        if zorunlu:
            raise AracHatasi(f"'{ad}' gerekli.")
        return None
    if isinstance(deger, bool):
        raise AracHatasi(f"'{ad}' tam sayı olmalı.")
    if isinstance(deger, float) and deger.is_integer():
        return int(deger)
    if isinstance(deger, int):
        return deger
    if isinstance(deger, str) and deger.strip().isdigit():
        return int(deger.strip())
    raise AracHatasi(f"'{ad}' tam sayı olmalı.")


def _tarih(arg: dict):
    try:
        return api_tarihi(arg.get("tarih") or None)
    except ValueError as exc:
        raise AracHatasi(str(exc)) from exc


def _bugun(baglanti: sqlite3.Connection, arg: dict) -> dict:
    return gunun_ozeti_json(baglanti, _tarih(arg))


def _subeler(baglanti: sqlite3.Connection, _arg: dict) -> dict:
    yil = servis.aktif_yil(baglanti)
    if yil is None:
        return {"kurulum_gerekli": True, "subeler": []}
    return {
        "kurulum_gerekli": False,
        "ogretim_yili": yil.ad,
        "subeler": [
            {"sube_id": s.id, "ad": s.ad, "sinif": s.sinif}
            for s in servis.subeleri_oku(baglanti, yil.id)
        ],
    }


def _yoklama(baglanti: sqlite3.Connection, arg: dict) -> dict:
    sube_id = _tam_sayi(arg, "sube_id", zorunlu=True)
    try:
        return yoklama_ozeti(baglanti, sube_id, _tarih(arg), _tam_sayi(arg, "saat"))
    except servis.Bulunamadi as exc:
        raise AracHatasi("Şube bulunamadı.") from exc


def _ders_defteri(baglanti: sqlite3.Connection, arg: dict) -> dict:
    sube_id = _tam_sayi(arg, "sube_id", zorunlu=True)
    try:
        return ders_defteri_ozeti(baglanti, sube_id, _tarih(arg))
    except servis.Bulunamadi as exc:
        raise AracHatasi("Şube bulunamadı.") from exc


CALISTIRICILAR: dict[str, Callable[[sqlite3.Connection, dict], dict]] = {
    "bugun": _bugun,
    "subeler": _subeler,
    "yoklama_oku": _yoklama,
    "ders_defteri_oku": _ders_defteri,
}


def _hata(kimlik: Any, kod: int, mesaj: str, durum: int = 200) -> JSONResponse:
    return JSONResponse(
        {"jsonrpc": "2.0", "id": kimlik, "error": {"code": kod, "message": mesaj}},
        status_code=durum,
    )


def _sonuc(kimlik: Any, sonuc: dict, basliklar: dict[str, str] | None = None) -> JSONResponse:
    return JSONResponse({"jsonrpc": "2.0", "id": kimlik, "result": sonuc}, headers=basliklar)


def arac_cagir(baglanti: sqlite3.Connection, ad: str, argumanlar: dict) -> dict:
    """`tools/call` sonucu (MCP CallToolResult). Bilinmeyen araç KeyError fırlatır."""
    calistir = CALISTIRICILAR[ad]
    try:
        veri = calistir(baglanti, argumanlar)
    except AracHatasi as exc:
        return {"content": [{"type": "text", "text": str(exc)}], "isError": True}
    return {
        "content": [{"type": "text", "text": json.dumps(veri, ensure_ascii=False)}],
        "structuredContent": veri,
        "isError": False,
    }


def bagla(uygulama: FastAPI) -> None:
    oturumlar: OrderedDict[str, bool] = OrderedDict()
    uygulama.state.mcp_oturumlari = oturumlar

    @uygulama.post("/api/v1/mcp")
    async def mcp(istek: Request):
        try:
            govde = json.loads(await istek.body() or b"null")
        except (ValueError, UnicodeDecodeError):
            return _hata(None, AYRISTIRMA, "JSON çözülemedi.", 400)
        if isinstance(govde, list):
            return _hata(None, GECERSIZ_ISTEK, "Toplu istek desteklenmiyor.", 400)
        if not isinstance(govde, dict) or govde.get("jsonrpc") != "2.0" or not isinstance(
            govde.get("method"), str
        ):
            return _hata(None, GECERSIZ_ISTEK, "Geçersiz JSON-RPC isteği.", 400)

        yontem: str = govde["method"]
        kimlik = govde.get("id")
        parametre = govde.get("params") or {}
        if not isinstance(parametre, dict):
            return _hata(kimlik, GECERSIZ_PARAMETRE, "params nesne olmalı.")

        if yontem == "initialize":
            istenen = parametre.get("protocolVersion")
            surum = istenen if istenen in DESTEKLENEN_PROTOKOLLER else PROTOKOL
            oturum = secrets.token_urlsafe(24)
            oturumlar[oturum] = True
            while len(oturumlar) > AZAMI_OTURUM:
                oturumlar.popitem(last=False)
            return _sonuc(
                kimlik,
                {
                    "protocolVersion": surum,
                    "capabilities": {"tools": {"listChanged": False}},
                    "serverInfo": {"name": "ogretmen-cantasi", "version": "0.3.0"},
                    "instructions": "Öğretmen Çantası salt okunur verisi: günün dersleri, yoklama, ders defteri.",
                },
                {"Mcp-Session-Id": oturum},
            )

        oturum = istek.headers.get("mcp-session-id", "")
        if not oturum:
            return _hata(kimlik, GECERSIZ_ISTEK, "Mcp-Session-Id gerekli; önce initialize.", 400)
        if oturum not in oturumlar:
            return _hata(kimlik, GECERSIZ_ISTEK, "Oturum bulunamadı; yeniden initialize.", 404)
        oturumlar.move_to_end(oturum)

        if kimlik is None:
            # Bildirim (notifications/initialized vb.): yanıt gövdesi yok.
            return Response(status_code=202)
        if yontem == "ping":
            return _sonuc(kimlik, {})
        if yontem == "tools/list":
            return _sonuc(kimlik, {"tools": ARACLAR})
        if yontem == "tools/call":
            ad = parametre.get("name")
            argumanlar = parametre.get("arguments") or {}
            if not isinstance(argumanlar, dict):
                return _hata(kimlik, GECERSIZ_PARAMETRE, "arguments nesne olmalı.")
            if ad not in CALISTIRICILAR:
                return _hata(kimlik, GECERSIZ_PARAMETRE, f"Bilinmeyen araç: {ad}")
            return _sonuc(kimlik, arac_cagir(istek.state.db, ad, argumanlar))
        return _hata(kimlik, YONTEM_YOK, f"Desteklenmeyen yöntem: {yontem}")

    @uygulama.delete("/api/v1/mcp")
    def mcp_kapat(istek: Request):
        oturumlar.pop(istek.headers.get("mcp-session-id", ""), None)
        return Response(status_code=204)

    @uygulama.get("/api/v1/mcp")
    def mcp_akis_yok():
        # Sunucudan istemciye SSE akışı sunulmaz (spec: 405 ile bildirilir).
        return Response(status_code=405, headers={"Allow": "POST, DELETE"})
