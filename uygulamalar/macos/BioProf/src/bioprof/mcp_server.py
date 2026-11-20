"""Optional stdio MCP server for a running, local BioProf instance.

The MCP dependency is deliberately optional.  This module keeps all HTTP
access pinned to one configured BioProf base URL, rejects redirects, and only
allows loopback by default.  The exposed tools never fetch arbitrary URLs;
``ingest_source`` is disabled until explicit import roots are configured,
then accepts only regular, non-symlink files below those roots.
"""

from __future__ import annotations

import argparse
import asyncio
import importlib
import ipaddress
import mimetypes
import os
from collections.abc import Mapping
from pathlib import Path
from typing import Any, Literal
from urllib.parse import quote, urlsplit

import httpx

DEFAULT_BASE_URL = "http://127.0.0.1:8765"
DEFAULT_MAX_IMPORT_BYTES = 250 * 1024 * 1024
_TRUE_VALUES = frozenset({"1", "true", "yes", "on"})
_SENSITIVE_COMPONENTS = frozenset(
    {
        ".aws",
        ".gnupg",
        ".ssh",
        "keychains",
    }
)
_SENSITIVE_FILENAMES = frozenset(
    {
        ".netrc",
        ".npmrc",
        ".pypirc",
        "credentials",
        "id_dsa",
        "id_ed25519",
        "id_ecdsa",
        "id_rsa",
    }
)
_SENSITIVE_SUFFIXES = frozenset({".key", ".p12", ".pfx", ".pem"})


class BioProfMCPError(RuntimeError):
    """Base error presented to an MCP client without leaking response internals."""


class BioProfAPIError(BioProfMCPError):
    """A typed error returned by the BioProf native API."""

    def __init__(self, status_code: int, code: str, message: str) -> None:
        super().__init__(f"BioProf API hatası ({status_code}, {code}): {message}")
        self.status_code = status_code
        self.code = code
        self.message = message


def _env_flag(name: str) -> bool:
    return os.getenv(name, "").strip().casefold() in _TRUE_VALUES


def validate_base_url(base_url: str, *, allow_remote: bool = False) -> str:
    """Validate and normalize the single API origin the MCP server may contact."""

    value = base_url.strip()
    parsed = urlsplit(value)
    if parsed.scheme not in {"http", "https"}:
        raise ValueError("BioProf MCP base URL şeması http veya https olmalıdır")
    if not parsed.hostname or parsed.port is None:
        raise ValueError("BioProf MCP base URL açık bir host ve port içermelidir")
    if parsed.username is not None or parsed.password is not None:
        raise ValueError("BioProf MCP base URL içinde kullanıcı bilgisi kullanılamaz")
    if parsed.query or parsed.fragment or parsed.path not in {"", "/"}:
        raise ValueError("BioProf MCP base URL yalnız origin olmalıdır; path/query kullanılamaz")

    is_loopback = _is_loopback_host(parsed.hostname)
    if not is_loopback and not allow_remote:
        raise ValueError(
            "Uzak BioProf API reddedildi. Yalnız bilinçli kullanımda "
            "--allow-remote veya BIOPROF_MCP_ALLOW_REMOTE=1 verin"
        )

    return value.rstrip("/")


def _is_loopback_host(hostname: str) -> bool:
    value = hostname.casefold().rstrip(".")
    if value == "localhost":
        return True
    try:
        return ipaddress.ip_address(value).is_loopback
    except ValueError:
        return False


def _import_roots_from_env() -> tuple[Path, ...]:
    raw = os.getenv("BIOPROF_MCP_IMPORT_ROOTS", "").strip()
    if not raw:
        return ()
    return tuple(Path(value.strip()) for value in raw.split(os.pathsep) if value.strip())


def _normalize_import_roots(values: tuple[Path, ...]) -> tuple[Path, ...]:
    roots: list[Path] = []
    for value in values:
        root = value.expanduser().absolute()
        if root.is_symlink():
            raise ValueError(f"MCP import root symlink olamaz: {root}")
        if not root.is_dir():
            raise ValueError(f"MCP import root mevcut bir dizin olmalıdır: {root}")
        roots.append(root.resolve(strict=True))
    return tuple(dict.fromkeys(roots))


class BioProfMCPClient:
    """Small independently-testable client for BioProf's native API."""

    def __init__(
        self,
        base_url: str = DEFAULT_BASE_URL,
        *,
        allow_remote: bool = False,
        timeout: float = 60.0,
        http_client: httpx.AsyncClient | None = None,
        import_roots: tuple[Path, ...] | None = None,
        max_import_bytes: int = DEFAULT_MAX_IMPORT_BYTES,
    ) -> None:
        if timeout <= 0:
            raise ValueError("timeout sıfırdan büyük olmalıdır")
        if max_import_bytes <= 0:
            raise ValueError("max_import_bytes sıfırdan büyük olmalıdır")
        self.base_url = validate_base_url(base_url, allow_remote=allow_remote)
        hostname = urlsplit(self.base_url).hostname
        if hostname is None:  # pragma: no cover - validate_base_url already guarantees it
            raise ValueError("BioProf MCP base URL host içermelidir")
        self.is_remote = not _is_loopback_host(hostname)
        self.import_roots = _normalize_import_roots(
            _import_roots_from_env() if import_roots is None else import_roots
        )
        self.max_import_bytes = max_import_bytes
        self._owns_client = http_client is None
        self._client = http_client or httpx.AsyncClient(
            timeout=timeout,
            follow_redirects=False,
            trust_env=False,
            headers={"Accept": "application/json", "User-Agent": "BioProf-MCP/0.1"},
        )

    async def aclose(self) -> None:
        if self._owns_client:
            await self._client.aclose()

    async def _request(self, method: str, path: str, **kwargs: Any) -> Any:
        try:
            response = await self._client.request(
                method,
                f"{self.base_url}{path}",
                follow_redirects=False,
                **kwargs,
            )
        except httpx.RequestError as exc:
            raise BioProfMCPError(
                f"BioProf API'ye bağlanılamadı ({self.base_url}). "
                "Önce `bioprof serve` ile yerel sunucuyu başlatın."
            ) from exc

        if response.status_code >= 300:
            code, message = _api_error(response)
            raise BioProfAPIError(response.status_code, code, message)
        if response.status_code == 204 or not response.content:
            return {}
        try:
            return response.json()
        except ValueError as exc:
            raise BioProfMCPError(
                f"BioProf API JSON olmayan bir yanıt döndürdü ({response.status_code})"
            ) from exc

    async def search_sources(
        self,
        notebook_id: str,
        query: str,
        *,
        source_ids: list[str] | None = None,
        limit: int = 20,
    ) -> Any:
        return await self._request(
            "POST",
            f"/api/v1/notebooks/{_segment(notebook_id)}/search",
            json={
                "query": query,
                "source_ids": source_ids,
                "limit": limit,
                "include_trace": True,
            },
        )

    async def ask_notebook(
        self,
        notebook_id: str,
        question: str,
        *,
        mode: Literal["strict", "hybrid", "research", "raw"] = "strict",
        source_ids: list[str] | None = None,
        provider: str | None = None,
        model: str | None = None,
    ) -> Any:
        return await self._request(
            "POST",
            f"/api/v1/notebooks/{_segment(notebook_id)}/ask",
            json={
                "question": question,
                "mode": mode,
                "source_ids": source_ids,
                "provider": provider,
                "model": model,
                "speak": False,
            },
        )

    async def resolve_citation(self, citation_id: str) -> Any:
        return await self._request("GET", f"/api/v1/citations/{_segment(citation_id)}")

    async def run_calculator(self, name: str, arguments: dict[str, Any]) -> Any:
        return await self._request(
            "POST", "/api/v1/tools/run", json={"name": name, "arguments": arguments}
        )

    async def ingest_source(
        self,
        notebook_id: str,
        file_path: str,
        *,
        title: str | None = None,
        license_name: str | None = None,
    ) -> Any:
        if self.is_remote:
            raise ValueError("ingest_source uzak BioProf API kullanılırken güvenlik için kapalıdır")
        if not self.import_roots:
            raise ValueError(
                "ingest_source varsayılan olarak kapalıdır. İzin verilen dizinleri "
                "BIOPROF_MCP_IMPORT_ROOTS ile açıkça tanımlayın"
            )
        if "://" in file_path or file_path.casefold().startswith("file:"):
            raise ValueError("ingest_source yalnız açıkça seçilmiş yerel dosya yolu kabul eder")
        candidate = Path(file_path).expanduser().absolute()
        root = next((item for item in self.import_roots if candidate.is_relative_to(item)), None)
        if root is None:
            raise ValueError("Dosya BIOPROF_MCP_IMPORT_ROOTS allowlist'i dışında")
        relative = candidate.relative_to(root)
        current = root
        for component in relative.parts:
            current /= component
            if current.is_symlink():
                raise ValueError("Symlink üzerinden kaynak içe aktarılamaz")
        path = candidate.resolve(strict=True)
        if not path.is_relative_to(root):
            raise ValueError("Dosya allowlist kökü dışına çözümleniyor")
        if not path.is_file():
            raise ValueError("ingest_source yolu normal bir dosya olmalıdır")
        size = path.stat().st_size
        if size == 0:
            raise ValueError("Boş dosya içe aktarılamaz")
        if size > self.max_import_bytes:
            raise ValueError(
                f"Dosya MCP içe aktarma sınırını aşıyor ({self.max_import_bytes} bayt)"
            )
        if _looks_sensitive(path):
            raise ValueError("Hassas anahtar/kimlik bilgisi dosyaları içe aktarılamaz")

        media_type = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
        form = {
            key: value for key, value in {"title": title, "license": license_name}.items() if value
        }
        with path.open("rb") as handle:
            return await self._request(
                "POST",
                f"/api/v1/notebooks/{_segment(notebook_id)}/sources",
                data=form,
                files={"file": (path.name, handle, media_type)},
            )


def _looks_sensitive(path: Path) -> bool:
    lowered_parts = {part.casefold() for part in path.parts}
    name = path.name.casefold()
    return (
        bool(lowered_parts & _SENSITIVE_COMPONENTS)
        or name in _SENSITIVE_FILENAMES
        or name == ".env"
        or name.startswith(".env.")
        or path.suffix.casefold() in _SENSITIVE_SUFFIXES
    )


def _segment(value: str) -> str:
    value = value.strip()
    if not value:
        raise ValueError("Kimlik boş olamaz")
    return quote(value, safe="")


def _api_error(response: httpx.Response) -> tuple[str, str]:
    code = "http_error"
    message = f"HTTP {response.status_code}"
    try:
        payload = response.json()
    except ValueError:
        return code, message
    if not isinstance(payload, Mapping):
        return code, message
    detail = payload.get("detail", payload.get("error"))
    if isinstance(detail, Mapping):
        code = str(detail.get("code") or code)
        message = str(detail.get("message") or message)
    elif isinstance(detail, str):
        message = detail
    elif isinstance(detail, list):
        message = "İstek doğrulanamadı"
        code = "validation_error"
    return code, message


def _load_fastmcp() -> Any:
    try:
        module = importlib.import_module("mcp.server.fastmcp")
    except ModuleNotFoundError as exc:
        raise RuntimeError(
            "BioProf MCP desteği kurulu değil. `uv sync --extra mcp` ile "
            "isteğe bağlı MCP bağımlılıklarını kurun."
        ) from exc
    return module.FastMCP


def create_mcp_server(
    client: BioProfMCPClient | None = None,
    *,
    fastmcp_class: Any | None = None,
) -> Any:
    """Create a FastMCP stdio server and register the five BioProf tools."""

    api = client or BioProfMCPClient()
    server_class = fastmcp_class or _load_fastmcp()
    server = server_class(
        "BioProf",
        instructions=(
            "Yerel BioProf notebooklarında kanıta dayalı biyoloji ve tıp araştırması. "
            "Tanı, tedavi, reçete veya kişiselleştirilmiş doz aracı değildir."
        ),
    )

    @server.tool()
    async def search_sources(
        notebook_id: str,
        query: str,
        source_ids: list[str] | None = None,
        limit: int = 20,
    ) -> Any:
        """Search selected BioProf notebook sources and return anchored evidence."""

        return await api.search_sources(notebook_id, query, source_ids=source_ids, limit=limit)

    @server.tool()
    async def ask_notebook(
        notebook_id: str,
        question: str,
        mode: Literal["strict", "hybrid", "research", "raw"] = "strict",
        source_ids: list[str] | None = None,
        provider: str | None = None,
        model: str | None = None,
    ) -> Any:
        """Ask a BioProf notebook; strict mode only answers from cited evidence."""

        return await api.ask_notebook(
            notebook_id,
            question,
            mode=mode,
            source_ids=source_ids,
            provider=provider,
            model=model,
        )

    @server.tool()
    async def resolve_citation(citation_id: str) -> Any:
        """Resolve a BioProf citation to its immutable source anchor and quote."""

        return await api.resolve_citation(citation_id)

    @server.tool()
    async def run_calculator(name: str, arguments: dict[str, Any]) -> Any:
        """Run one allowlisted BioProf biology/scientific calculator."""

        return await api.run_calculator(name, arguments)

    @server.tool()
    async def ingest_source(
        notebook_id: str,
        file_path: str,
        title: str | None = None,
        license_name: str | None = None,
    ) -> Any:
        """Upload one user-approved local file to a BioProf notebook for indexing."""

        return await api.ingest_source(
            notebook_id,
            file_path,
            title=title,
            license_name=license_name,
        )

    return server


def main() -> None:
    parser = argparse.ArgumentParser(description="BioProf isteğe bağlı stdio MCP sunucusu")
    parser.add_argument(
        "--base-url",
        default=os.getenv("BIOPROF_MCP_BASE_URL", DEFAULT_BASE_URL),
        help=f"Çalışan BioProf origin'i (varsayılan: {DEFAULT_BASE_URL})",
    )
    parser.add_argument(
        "--import-root",
        action="append",
        default=None,
        help=(
            "ingest_source için izinli yerel dizin (tekrarlanabilir). "
            "Alternatif: BIOPROF_MCP_IMPORT_ROOTS"
        ),
    )
    parser.add_argument(
        "--allow-remote",
        action="store_true",
        default=_env_flag("BIOPROF_MCP_ALLOW_REMOTE"),
        help="Loopback dışındaki BioProf origin'ine bilinçli olarak izin ver",
    )
    parser.add_argument("--timeout", type=float, default=60.0, help="HTTP zaman aşımı (saniye)")
    args = parser.parse_args()

    try:
        client = BioProfMCPClient(
            args.base_url,
            allow_remote=args.allow_remote,
            timeout=args.timeout,
            import_roots=(
                tuple(Path(value) for value in args.import_root)
                if args.import_root is not None
                else None
            ),
        )
        server = create_mcp_server(client)
    except (RuntimeError, ValueError) as exc:
        parser.error(str(exc))

    try:
        server.run(transport="stdio")
    finally:
        asyncio.run(client.aclose())


if __name__ == "__main__":
    main()
