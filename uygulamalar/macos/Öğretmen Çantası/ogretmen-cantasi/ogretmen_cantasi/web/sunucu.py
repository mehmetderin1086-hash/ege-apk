"""FastAPI sunucusu: arayüzün tüm sayfaları ve dosya çıktıları.

Sayfalar sunucuda üretilir (Jinja2), derleme adımı yoktur. İş mantığı burada
değil `servis` ve `servis_olcme` modüllerindedir; buradaki her yönlendirme
girdiyi çözer, bir servis çağırır ve sonucu şablona verir.
"""

from __future__ import annotations

import asyncio
import secrets
import sqlite3
from urllib.parse import urlsplit

from fastapi import FastAPI, Request
from fastapi.responses import PlainTextResponse
from fastapi.staticfiles import StaticFiles

from .. import ayarlar as ayar_modulu
from .. import depo, entegrasyon
from . import rotalar
from .ortak import (  # noqa: F401 - sablonlar geriye dönük uyumluluk için dışa açık tutulur
    KOK,
    sablonlar,
)

GUVENLI_HOSTLAR = {"127.0.0.1", "localhost", "::1"}


def _baglanti() -> sqlite3.Connection:
    return depo.baglan()


def uygulama_kur() -> FastAPI:
    uygulama = FastAPI(title=ayar_modulu.UYGULAMA_ADI, docs_url=None, redoc_url=None)
    uygulama.state.csrf_token = secrets.token_urlsafe(32)
    uygulama.state.api_token = entegrasyon.yerel_belirtec()
    uygulama.state.ses_kilidi = asyncio.Semaphore(1)
    uygulama.mount("/statik", StaticFiles(directory=str(KOK / "statik")), name="statik")

    @uygulama.middleware("http")
    async def baglanti_ekle(istek: Request, sonraki):
        host = (istek.url.hostname or "").casefold()
        if host not in GUVENLI_HOSTLAR:
            return PlainTextResponse("Geçersiz yerel sunucu adresi.", status_code=400)

        api_istegi = istek.url.path.startswith("/api/v1/")
        if api_istegi:
            yetki = istek.headers.get("authorization", "")
            beklenen = f"Bearer {uygulama.state.api_token}"
            # X-Api-Token: önünde basic_auth yapan bir vekil (Caddy) `Authorization`
            # başlığını kendisi kullanırken API belirteci ayrı başlıkla gelebilsin.
            ek_belirtec = istek.headers.get("x-api-token", "")
            # Baytla karşılaştırılır: ASCII dışı başlıkta str compare_digest TypeError (500) verirdi.
            gecerli = secrets.compare_digest(
                yetki.encode("utf-8"), beklenen.encode("utf-8")
            ) or (
                bool(ek_belirtec)
                and secrets.compare_digest(
                    ek_belirtec.encode("utf-8"),
                    str(uygulama.state.api_token).encode("utf-8"),
                )
            )
            if not gecerli:
                return PlainTextResponse("Yerel API yetkisi geçersiz.", status_code=401)

        if not api_istegi and istek.method.upper() not in {"GET", "HEAD", "OPTIONS"}:
            origin = istek.headers.get("origin", "")
            referer = istek.headers.get("referer", "")
            kaynak = origin or referer
            if kaynak:
                cozum = urlsplit(kaynak)
                if (cozum.hostname or "").casefold() not in GUVENLI_HOSTLAR:
                    return PlainTextResponse(
                        "Bu değişiklik isteği başka bir siteden geldiği için reddedildi.",
                        status_code=403,
                    )
                istek_portu = istek.url.port or (443 if istek.url.scheme == "https" else 80)
                kaynak_portu = cozum.port or (443 if cozum.scheme == "https" else 80)
                if kaynak_portu != istek_portu:
                    return PlainTextResponse("İstek kökeni geçersiz.", status_code=403)
            belirtec = istek.headers.get("x-csrf-token", "")
            if not secrets.compare_digest(belirtec, uygulama.state.csrf_token):
                return PlainTextResponse(
                    "Güvenlik belirteci eksik veya geçersiz. Sayfayı yenileyip tekrar deneyin.",
                    status_code=403,
                )

        istek.state.db = _baglanti()
        try:
            yanit = await sonraki(istek)
            yanit.headers["X-Frame-Options"] = "DENY"
            yanit.headers["X-Content-Type-Options"] = "nosniff"
            yanit.headers["Referrer-Policy"] = "same-origin"
            yanit.headers["Content-Security-Policy"] = (
                "default-src 'self'; style-src 'self' 'unsafe-inline'; "
                "script-src 'self' 'unsafe-inline'; img-src 'self' data:; "
                "connect-src 'self'; frame-ancestors 'none'"
            )
            return yanit
        finally:
            istek.state.db.close()

    _yonlendirmeleri_bagla(uygulama)
    return uygulama


def _yonlendirmeleri_bagla(uygulama: FastAPI) -> None:
    for modul in rotalar.HEPSI:
        modul.bagla(uygulama)


def calistir(adres: str = "127.0.0.1", port: int = ayar_modulu.PORT_BASLANGIC) -> None:
    import uvicorn

    ayar_modulu.dizinleri_hazirla()
    depo.yedekle(etiket="oturum")
    uvicorn.run(uygulama_kur(), host=adres, port=port, log_level="warning")
