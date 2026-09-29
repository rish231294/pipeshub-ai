"""A local forward proxy the headless browser is launched behind.

Chromium resolves hostnames and follows redirects by itself, and a page it renders can make
requests of its own (images, iframes, fetch(), navigations, service workers, WebSockets). With
this proxy configured, Chromium hands every one of those connections to it by hostname, and the
proxy resolves the host, checks every address against the SSRF policy, and connects only to an
address that passed. A DNS answer that changes after an earlier check (rebinding) never reaches
the browser.

Plain-HTTP requests are forwarded one per client connection (``Connection: close``), so a
reused connection can't carry a second request to another host; HTTPS and WebSockets over TLS
arrive as CONNECT tunnels.
"""

from __future__ import annotations

import asyncio
import contextlib
import logging
from urllib.parse import SplitResult, urlsplit

from app.connectors.sources.web.fetch_strategy import (
    BlockedUrlError,
    resolve_public_target,
)

_MAX_HEAD_BYTES = 64 * 1024
_HEAD_TIMEOUT_SECONDS = 30
_CONNECT_TIMEOUT_SECONDS = 15
_CHUNK = 64 * 1024
# Hop-by-hop headers meant for the proxy, not the origin (RFC 9110 §7.6.1).
_PROXY_ONLY_HEADERS = frozenset({"proxy-connection", "proxy-authorization", "keep-alive", "connection"})


def _answer(status: str) -> bytes:
    return f"HTTP/1.1 {status}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".encode("ascii")


_FORBIDDEN = _answer("403 Forbidden")
_BAD_GATEWAY = _answer("502 Bad Gateway")
_BAD_REQUEST = _answer("400 Bad Request")


def _split_authority(authority: str, default_port: int) -> tuple[str, int] | None:
    """``host[:port]`` or ``[v6]:port`` into host and port; None if it isn't one."""
    parts = urlsplit(f"//{authority}")
    try:
        port = parts.port or default_port
    except ValueError:
        return None
    return (parts.hostname, port) if parts.hostname else None


async def _pipe(source: asyncio.StreamReader, sink: asyncio.StreamWriter) -> None:
    try:
        while data := await source.read(_CHUNK):
            sink.write(data)
            await sink.drain()
    except (ConnectionError, OSError):
        pass
    finally:
        with contextlib.suppress(Exception):
            sink.close()


class EgressProxy:
    """Serves on 127.0.0.1 on a free port; ``start`` returns the URL to give the browser."""

    def __init__(self, logger: logging.Logger | None = None) -> None:
        self._logger = logger or logging.getLogger(__name__)
        self._server: asyncio.Server | None = None
        self._connections: set[asyncio.StreamWriter] = set()

    async def start(self) -> str:
        self._server = await asyncio.start_server(self._serve, host="127.0.0.1", port=0, limit=_MAX_HEAD_BYTES)
        port = self._server.sockets[0].getsockname()[1]
        return f"http://127.0.0.1:{port}"

    async def close(self) -> None:
        if self._server is None:
            return
        self._server.close()
        for writer in list(self._connections):
            with contextlib.suppress(Exception):
                writer.close()
        await self._server.wait_closed()
        self._server = None

    async def _serve(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        self._connections.add(writer)
        try:
            await self._handle(reader, writer)
        except (asyncio.IncompleteReadError, asyncio.LimitOverrunError, asyncio.TimeoutError, ConnectionError, OSError):
            pass
        finally:
            self._connections.discard(writer)
            with contextlib.suppress(Exception):
                writer.close()

    async def _handle(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        head = await asyncio.wait_for(reader.readuntil(b"\r\n\r\n"), _HEAD_TIMEOUT_SECONDS)
        request_line, *header_lines = head.decode("latin-1").split("\r\n")
        try:
            method, target, version = request_line.split(" ")
        except ValueError:
            writer.write(_BAD_REQUEST)
            return

        if method.upper() == "CONNECT":
            authority = _split_authority(target, 443)
            if authority is None:
                writer.write(_BAD_REQUEST)
                return
            upstream = await self._open(*authority, writer)
            if upstream is None:
                return
            writer.write(b"HTTP/1.1 200 Connection Established\r\n\r\n")
            await writer.drain()
            await self._relay(reader, writer, *upstream)
            return

        # A proxied plain-HTTP request carries the absolute URL: GET http://host/path HTTP/1.1
        url = urlsplit(target)
        authority = _split_authority(url.netloc, 80) if url.scheme.lower() == "http" else None
        if authority is None:
            writer.write(_BAD_REQUEST)
            return
        upstream = await self._open(*authority, writer)
        if upstream is None:
            return
        upstream_reader, upstream_writer = upstream
        upstream_writer.write(self._origin_form(method, url, version, header_lines))
        await upstream_writer.drain()
        await self._relay(reader, writer, upstream_reader, upstream_writer)

    @staticmethod
    def _origin_form(method: str, url: SplitResult, version: str, header_lines: list[str]) -> bytes:
        path = url.path or "/"
        if url.query:
            path = f"{path}?{url.query}"
        upgrade = any(
            line.split(":", 1)[0].strip().lower() == "connection" and "upgrade" in line.lower()
            for line in header_lines
        )
        kept = [
            line for line in header_lines
            if line and line.split(":", 1)[0].strip().lower() not in _PROXY_ONLY_HEADERS
        ]
        # One request per connection; a WebSocket handshake keeps its Upgrade.
        kept.append("Connection: Upgrade" if upgrade else "Connection: close")
        return (f"{method} {path} {version}\r\n" + "\r\n".join(kept) + "\r\n\r\n").encode("latin-1")

    async def _open(
        self, host: str, port: int, client: asyncio.StreamWriter
    ) -> tuple[asyncio.StreamReader, asyncio.StreamWriter] | None:
        """Connect to ``host``'s checked address, or answer the browser and return None."""
        literal = f"[{host}]" if ":" in host else host
        try:
            target = await resolve_public_target(f"http://{literal}:{port}/")
        except BlockedUrlError as e:
            self._logger.warning("🚫 Browser request to %s:%s refused by the SSRF policy: %s", host, port, e)
            client.write(_FORBIDDEN)
            return None
        except OSError as e:
            self._logger.debug("Browser request to %s:%s did not resolve: %s", host, port, e)
            client.write(_BAD_GATEWAY)
            return None
        for address in target.addresses:
            try:
                return await asyncio.wait_for(asyncio.open_connection(str(address), port), _CONNECT_TIMEOUT_SECONDS)
            except (asyncio.TimeoutError, OSError):
                continue
        client.write(_BAD_GATEWAY)
        return None

    async def _relay(
        self,
        reader: asyncio.StreamReader,
        writer: asyncio.StreamWriter,
        upstream_reader: asyncio.StreamReader,
        upstream_writer: asyncio.StreamWriter,
    ) -> None:
        self._connections.add(upstream_writer)
        try:
            await asyncio.gather(_pipe(reader, upstream_writer), _pipe(upstream_reader, writer))
        finally:
            self._connections.discard(upstream_writer)
