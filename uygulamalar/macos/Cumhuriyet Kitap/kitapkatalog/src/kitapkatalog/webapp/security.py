"""Yerel API koruması: açılışa özgü token + Origin/Host denetimi.

127.0.0.1 tek başına güvenlik sınırı değildir: tarayıcıdaki herhangi bir
site localhost'a istek gönderebilir (CSRF). Sunucu her açılışta rastgele bir
token üretir; tarayıcı `/?token=...` ile açılır, token HttpOnly çereze
yazılır ve sonraki tüm `/api/` istekleri çerezle doğrulanır.
"""

from __future__ import annotations

import hmac
import secrets
from urllib.parse import urlsplit

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse, RedirectResponse, Response

COOKIE_NAME = "kitapkatalog_token"

_ALLOWED_HOSTS = {"127.0.0.1", "localhost", "::1"}
_DEFAULT_PORTS = {"http": 80, "https": 443}


def new_token() -> str:
    return secrets.token_urlsafe(32)


def _host_and_port(header: str | None, scheme: str) -> tuple[str, int] | None:
    if not header:
        return None
    try:
        parsed = urlsplit(f"{scheme}://{header}")
        if (
            parsed.username is not None
            or parsed.password is not None
            or parsed.path
            or parsed.query
            or parsed.fragment
        ):
            return None
        host = (parsed.hostname or "").lower()
        port = parsed.port
    except ValueError:
        return None
    if host not in _ALLOWED_HOSTS:
        return None
    if port is None:
        port = _DEFAULT_PORTS.get(scheme.lower())
    if port is None:
        return None
    return host, port


def _host_allowed(header: str | None) -> bool:
    # Host davranışı geriye uyumlu kalır: izin verilen loopback adlarının
    # herhangi bir geçerli portu kabul edilir. Origin ise aşağıda bu Host'un
    # portu ve şemasıyla birebir eşleştirilir.
    return _host_and_port(header, "http") is not None


def _origin_allowed(origin: str, request: Request) -> bool:
    try:
        parsed = urlsplit(origin)
        if (
            parsed.scheme.lower() not in _DEFAULT_PORTS
            or not parsed.netloc
            or parsed.username is not None
            or parsed.password is not None
            or parsed.path
            or parsed.query
            or parsed.fragment
        ):
            return False
        origin_host = (parsed.hostname or "").lower()
        origin_port = parsed.port or _DEFAULT_PORTS[parsed.scheme.lower()]
    except ValueError:
        return False

    request_scheme = request.url.scheme.lower()
    request_origin = _host_and_port(request.headers.get("host"), request_scheme)
    return request_origin == (origin_host, origin_port) and parsed.scheme.lower() == request_scheme


class LocalAuthMiddleware(BaseHTTPMiddleware):
    def __init__(self, app, token: str) -> None:  # type: ignore[no-untyped-def]
        super().__init__(app)
        self._token = token

    async def dispatch(self, request: Request, call_next) -> Response:  # type: ignore[no-untyped-def]
        # Sağlık ucu imza keşfi için açık; state değiştirmez, veri sızdırmaz.
        if request.url.path == "/health":
            return await call_next(request)

        if not _host_allowed(request.headers.get("host")):
            return JSONResponse({"detail": "Yalnız yerel erişim"}, status_code=403)
        origin = request.headers.get("origin")
        if origin is not None and not _origin_allowed(origin, request):
            return JSONResponse({"detail": "Origin reddedildi"}, status_code=403)

        # OPAC (öğrenci arama ekranı) ve statik dosyalar oturum istemez:
        # salt-okunur, sınırlı alan döner, üye verisi içermez. Host/Origin
        # denetimleri yukarıda uygulanmış durumda (yalnız yerel erişim).
        path = request.url.path
        if path == "/opac" or path.startswith("/api/opac/") or path.startswith("/static/"):
            return await call_next(request)

        # İlk açılış: ?token=... doğruysa çereze yaz ve URL'yi temizle.
        query_token = request.query_params.get("token")
        if query_token is not None and request.url.path == "/":
            if not hmac.compare_digest(query_token, self._token):
                return JSONResponse({"detail": "Geçersiz oturum anahtarı"}, status_code=403)
            response: Response = RedirectResponse(url="/", status_code=303)
            # Max-Age: PWA/standalone pencere yeniden açıldığında oturum çerezi
            # kaybolmasın (aynı sunucu koşusu içinde). Sunucu yeniden başlarsa
            # token zaten değişir ve kullanıcı başlatıcıya yönlendirilir.
            response.set_cookie(
                COOKIE_NAME,
                query_token,
                max_age=30 * 24 * 3600,
                httponly=True,
                samesite="strict",
                path="/",
            )
            return response

        cookie = request.cookies.get(COOKIE_NAME, "")
        if not hmac.compare_digest(cookie, self._token):
            if request.url.path.startswith("/api/"):
                return JSONResponse({"detail": "Oturum doğrulanamadı"}, status_code=401)
            return JSONResponse(
                {
                    "detail": (
                        "Oturum doğrulanamadı. Uygulamayı başlatıcıdan (Cumhuriyet Kitap) "
                        "yeniden açın; adres çubuğundaki bağlantı oturum anahtarı içerir."
                    )
                },
                status_code=401,
            )
        return await call_next(request)
