from __future__ import annotations

import asyncio
import contextlib
from collections.abc import Iterable
from urllib.parse import urlsplit

from fastapi import HTTPException

from .config import AppSettings
from .security import resolve_http_target

MAX_HEADER_BYTES = 64 * 1024


class SafeOutboundProxy:
    """Loopback forward proxy that pins every outbound connection to a validated IP."""

    def __init__(self, settings: AppSettings):
        self.settings = settings
        self.server: asyncio.Server | None = None
        self._client_tasks: set[asyncio.Task[object]] = set()

    async def start(self) -> None:
        if self.server is not None:
            return
        self.server = await asyncio.start_server(self._handle_client, "127.0.0.1", 0)
        socket = self.server.sockets[0]
        port = int(socket.getsockname()[1])
        self.settings.safe_proxy_url = f"http://127.0.0.1:{port}"

    async def stop(self) -> None:
        self.settings.safe_proxy_url = None
        if self.server is None:
            return
        self.server.close()
        await self.server.wait_closed()
        self.server = None
        pending = {task for task in self._client_tasks if not task.done()}
        if pending:
            _done, pending = await asyncio.wait(pending, timeout=2)
        for task in pending:
            task.cancel()
        if pending:
            await asyncio.gather(*pending, return_exceptions=True)

    async def _handle_client(
        self,
        reader: asyncio.StreamReader,
        writer: asyncio.StreamWriter,
    ) -> None:
        task = asyncio.current_task()
        if task is not None:
            self._client_tasks.add(task)
        try:
            header_block = await asyncio.wait_for(reader.readuntil(b"\r\n\r\n"), timeout=15)
            if len(header_block) > MAX_HEADER_BYTES:
                await self._respond(writer, 431, "İstek başlıkları çok büyük")
                return
            request_line, headers = self._parse_headers(header_block)
            method, target, version = request_line.split(" ", 2)
            if method.upper() == "CONNECT":
                await self._connect_tunnel(target, reader, writer)
                return
            await self._forward_http(method, target, version, headers, reader, writer)
        except (asyncio.IncompleteReadError, asyncio.LimitOverrunError, TimeoutError, ValueError):
            await self._respond(writer, 400, "Geçersiz proxy isteği")
        except HTTPException as exc:
            await self._respond(writer, exc.status_code, str(exc.detail))
        except (OSError, ConnectionError):
            await self._respond(writer, 502, "Uzak sunucuya bağlanılamadı")
        finally:
            writer.close()
            with contextlib.suppress(OSError):
                await writer.wait_closed()
            if task is not None:
                self._client_tasks.discard(task)

    async def _connect_tunnel(
        self,
        target: str,
        client_reader: asyncio.StreamReader,
        client_writer: asyncio.StreamWriter,
    ) -> None:
        parsed = urlsplit(f"//{target}")
        if not parsed.hostname:
            raise ValueError("CONNECT hedefi yok")
        port = parsed.port or 443
        _, addresses = await resolve_http_target(
            f"https://{self._authority(parsed.hostname, port)}/",
            allow_private=self.settings.allow_private_networks,
        )
        upstream_reader, upstream_writer = await self._open_pinned(addresses, port)
        client_writer.write(b"HTTP/1.1 200 Connection Established\r\n\r\n")
        await client_writer.drain()
        await self._relay_bidirectional(client_reader, client_writer, upstream_reader, upstream_writer)

    async def _forward_http(
        self,
        method: str,
        target: str,
        version: str,
        headers: list[tuple[str, str]],
        client_reader: asyncio.StreamReader,
        client_writer: asyncio.StreamWriter,
    ) -> None:
        if method.upper() not in {"GET", "HEAD"}:
            await self._respond(client_writer, 405, "Yalnız GET ve HEAD desteklenir")
            return
        parsed = urlsplit(target)
        if parsed.scheme != "http" or not parsed.hostname:
            await self._respond(client_writer, 400, "HTTP proxy hedefi mutlak bir URL olmalıdır")
            return
        normalized, addresses = await resolve_http_target(
            target,
            allow_private=self.settings.allow_private_networks,
        )
        parsed = urlsplit(normalized)
        port = parsed.port or 80
        upstream_reader, upstream_writer = await self._open_pinned(addresses, port)
        path = parsed.path or "/"
        if parsed.query:
            path += f"?{parsed.query}"
        forwarded = [
            (name, value)
            for name, value in headers
            if name.lower()
            not in {
                "connection",
                "host",
                "proxy-authorization",
                "proxy-connection",
            }
        ]
        forwarded.extend(
            [
                ("Host", self._authority(parsed.hostname, port, default_port=80)),
                ("Connection", "close"),
            ]
        )
        request = [f"{method} {path} {version}", *(f"{name}: {value}" for name, value in forwarded), "", ""]
        upstream_writer.write("\r\n".join(request).encode("iso-8859-1"))
        await upstream_writer.drain()
        while chunk := await upstream_reader.read(256 * 1024):
            client_writer.write(chunk)
            await client_writer.drain()
        upstream_writer.close()
        with contextlib.suppress(OSError):
            await upstream_writer.wait_closed()
        if not client_reader.at_eof():
            await asyncio.sleep(0)

    @staticmethod
    async def _open_pinned(
        addresses: Iterable[str],
        port: int,
    ) -> tuple[asyncio.StreamReader, asyncio.StreamWriter]:
        last_error: OSError | None = None
        for address in addresses:
            try:
                return await asyncio.wait_for(asyncio.open_connection(address, port), timeout=15)
            except OSError as exc:
                last_error = exc
        raise last_error or ConnectionError("Çözümlenmiş hedef yok")

    @staticmethod
    async def _relay_bidirectional(
        client_reader: asyncio.StreamReader,
        client_writer: asyncio.StreamWriter,
        upstream_reader: asyncio.StreamReader,
        upstream_writer: asyncio.StreamWriter,
    ) -> None:
        async def pipe(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
            try:
                while chunk := await reader.read(256 * 1024):
                    writer.write(chunk)
                    await writer.drain()
            except (ConnectionError, OSError):
                pass

        tasks = {
            asyncio.create_task(pipe(client_reader, upstream_writer)),
            asyncio.create_task(pipe(upstream_reader, client_writer)),
        }
        done, pending = await asyncio.wait(tasks, return_when=asyncio.FIRST_COMPLETED)
        for task in pending:
            task.cancel()
        await asyncio.gather(*done, *pending, return_exceptions=True)
        upstream_writer.close()
        with contextlib.suppress(OSError):
            await upstream_writer.wait_closed()

    @staticmethod
    def _parse_headers(data: bytes) -> tuple[str, list[tuple[str, str]]]:
        lines = data.decode("iso-8859-1").split("\r\n")
        if not lines or len(lines[0].split(" ", 2)) != 3:
            raise ValueError("Geçersiz istek satırı")
        headers: list[tuple[str, str]] = []
        for line in lines[1:]:
            if not line:
                break
            name, separator, value = line.partition(":")
            if not separator or not name:
                raise ValueError("Geçersiz başlık")
            headers.append((name.strip(), value.strip()))
        return lines[0], headers

    @staticmethod
    async def _respond(writer: asyncio.StreamWriter, status: int, message: str) -> None:
        if writer.is_closing():
            return
        reason = {
            400: "Bad Request",
            403: "Forbidden",
            405: "Method Not Allowed",
            422: "Unprocessable Content",
            431: "Request Header Fields Too Large",
            502: "Bad Gateway",
        }.get(status, "Error")
        body = message.encode("utf-8", "replace")[:1000]
        writer.write(
            f"HTTP/1.1 {status} {reason}\r\nContent-Type: text/plain; charset=utf-8\r\n"
            f"Content-Length: {len(body)}\r\nConnection: close\r\n\r\n".encode("ascii")
            + body
        )
        with contextlib.suppress(ConnectionError, OSError):
            await writer.drain()

    @staticmethod
    def _authority(hostname: str, port: int, *, default_port: int | None = None) -> str:
        host = f"[{hostname}]" if ":" in hostname else hostname
        return host if default_port == port else f"{host}:{port}"
