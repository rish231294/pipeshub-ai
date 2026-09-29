"""Unit tests for app.connectors.sources.web.egress_proxy (real sockets on 127.0.0.1)."""

import asyncio
import ipaddress
from collections.abc import AsyncIterator
from urllib.parse import urlparse

import pytest

from app.connectors.sources.web import egress_proxy
from app.connectors.sources.web.egress_proxy import EgressProxy
from app.connectors.sources.web.fetch_strategy import resolve_public_target
from app.utils.url_fetcher import PublicTarget

PUBLIC = "public.test"  # resolves, for these tests, to the local upstream below
_client_open = asyncio.open_connection  # the test client's own connections, not the proxy's


class Upstream:
    """A local server standing in for a public site: records what it receives, answers 200."""

    def __init__(self) -> None:
        self.received: list[bytes] = []
        self.port = 0
        self._server: asyncio.Server | None = None

    async def start(self) -> None:
        self._server = await asyncio.start_server(self._serve, "127.0.0.1", 0)
        self.port = self._server.sockets[0].getsockname()[1]

    async def _serve(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
        data = await reader.read(65536)
        self.received.append(data)
        if data.startswith(b"PING"):
            writer.write(b"PONG")
        else:
            writer.write(b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok")
        await writer.drain()
        writer.close()

    async def close(self) -> None:
        assert self._server is not None
        self._server.close()
        await self._server.wait_closed()


@pytest.fixture
async def upstream() -> AsyncIterator[Upstream]:
    server = Upstream()
    await server.start()
    yield server
    await server.close()


@pytest.fixture
async def proxy(monkeypatch: pytest.MonkeyPatch) -> AsyncIterator[tuple[str, int, list[str]]]:
    """The proxy, with public.test resolving to 127.0.0.1 and everything else through the real policy."""
    connected: list[str] = []

    async def resolve(url: str) -> PublicTarget:
        parsed = urlparse(url)
        if parsed.hostname == PUBLIC:
            return PublicTarget("http", PUBLIC, parsed.port or 80, (ipaddress.ip_address("127.0.0.1"),))
        return await resolve_public_target(url)

    async def open_connection(host: str, port: int) -> tuple[asyncio.StreamReader, asyncio.StreamWriter]:
        connected.append(host)
        return await _client_open(host, port)

    monkeypatch.setattr(egress_proxy, "resolve_public_target", resolve)
    monkeypatch.setattr(egress_proxy.asyncio, "open_connection", open_connection)
    server = EgressProxy()
    url = await server.start()
    parsed = urlparse(url)
    yield parsed.hostname, parsed.port, connected
    await server.close()


async def _send(proxy: tuple[str, int, list[str]], request: bytes) -> bytes:
    reader, writer = await _client_open(proxy[0], proxy[1])
    writer.write(request)
    await writer.drain()
    data = await asyncio.wait_for(reader.read(65536), 5)
    writer.close()
    return data


@pytest.mark.asyncio
@pytest.mark.parametrize("target", [
    "127.0.0.1:80", "169.254.169.254:80", "localhost:443", "[::1]:443", "10.0.0.5:8080",
    "metadata.google.internal:80", "[::ffff:127.0.0.1]:443",
])
async def test_connect_to_an_internal_address_is_refused_without_connecting(proxy, target) -> None:
    answer = await _send(proxy, f"CONNECT {target} HTTP/1.1\r\nHost: {target}\r\n\r\n".encode())

    assert answer.startswith(b"HTTP/1.1 403")
    assert proxy[2] == []


@pytest.mark.asyncio
@pytest.mark.parametrize("url", [
    "http://169.254.169.254/latest/meta-data/", "http://127.0.0.1:9911/", "http://localhost/admin",
])
async def test_a_plain_http_request_to_an_internal_address_is_refused(proxy, url) -> None:
    answer = await _send(proxy, f"GET {url} HTTP/1.1\r\nHost: x\r\n\r\n".encode())

    assert answer.startswith(b"HTTP/1.1 403")
    assert proxy[2] == []


@pytest.mark.asyncio
async def test_a_plain_http_request_is_forwarded_in_origin_form_to_the_checked_address(proxy, upstream) -> None:
    answer = await _send(proxy, (
        f"GET http://{PUBLIC}:{upstream.port}/page?q=1 HTTP/1.1\r\n"
        f"Host: {PUBLIC}:{upstream.port}\r\nProxy-Connection: keep-alive\r\nProxy-Authorization: x\r\n"
        "Connection: keep-alive\r\nAccept: text/html\r\n\r\n"
    ).encode())

    assert answer.endswith(b"ok")
    sent = upstream.received[0].decode()
    assert sent.startswith("GET /page?q=1 HTTP/1.1\r\n")
    assert "Proxy-" not in sent and "keep-alive" not in sent
    assert "Connection: close\r\n" in sent and "Accept: text/html\r\n" in sent
    assert proxy[2] == ["127.0.0.1"]


@pytest.mark.asyncio
async def test_a_websocket_handshake_keeps_its_upgrade(proxy, upstream) -> None:
    await _send(proxy, (
        f"GET http://{PUBLIC}:{upstream.port}/ws HTTP/1.1\r\nHost: {PUBLIC}\r\n"
        "Connection: Upgrade\r\nUpgrade: websocket\r\n\r\n"
    ).encode())

    assert "Connection: Upgrade\r\n" in upstream.received[0].decode()


@pytest.mark.asyncio
async def test_connect_to_an_allowed_host_tunnels_bytes_both_ways(proxy, upstream) -> None:
    reader, writer = await _client_open(proxy[0], proxy[1])
    writer.write(f"CONNECT {PUBLIC}:{upstream.port} HTTP/1.1\r\nHost: {PUBLIC}\r\n\r\n".encode())
    await writer.drain()
    established = await asyncio.wait_for(reader.readuntil(b"\r\n\r\n"), 5)
    writer.write(b"PING")
    await writer.drain()
    echoed = await asyncio.wait_for(reader.read(4), 5)
    writer.close()

    assert established.startswith(b"HTTP/1.1 200")
    assert echoed == b"PONG"
    assert proxy[2] == ["127.0.0.1"]


@pytest.mark.asyncio
@pytest.mark.parametrize("request_bytes", [
    b"NONSENSE\r\n\r\n", b"GET ftp://example.com/ HTTP/1.1\r\n\r\n", b"GET /relative HTTP/1.1\r\n\r\n",
])
async def test_a_request_the_proxy_cannot_read_is_a_bad_request(proxy, request_bytes) -> None:
    assert (await _send(proxy, request_bytes)).startswith(b"HTTP/1.1 400")


@pytest.mark.asyncio
async def test_a_host_that_does_not_resolve_is_a_bad_gateway(proxy, monkeypatch) -> None:
    async def unresolvable(url: str) -> PublicTarget:
        raise OSError("Could not resolve hostname")
    monkeypatch.setattr(egress_proxy, "resolve_public_target", unresolvable)

    assert (await _send(proxy, b"CONNECT nowhere.test:443 HTTP/1.1\r\n\r\n")).startswith(b"HTTP/1.1 502")
