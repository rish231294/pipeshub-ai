"""Fixtures for the Web connector behaviour tests (fakes live in web_behaviour_fakes)."""

import asyncio
import logging
import shutil
import socket
import sys
import tempfile
from collections.abc import AsyncIterator, Callable
from types import SimpleNamespace
from typing import Any

import aiohttp
import pytest
from aiohttp import web
from web_behaviour_fakes import (
    CONNECTOR_ID,
    FAKE_PUBLIC_ADDRESS,
    START_URL,
    FakeCheckpointStore,
    FakeConfigService,
    FakeRecordsDb,
    FakeRequestsClient,
    FakeScraper,
    FakeWeb,
    MakeConnector,
    RecordingNotifications,
    VirtualClock,
    browser_crawler_class,
)

from app.connectors.sources.web import connector as connector_module
from app.connectors.sources.web import crawl4ai_fetcher, egress_proxy, fetch_strategy
from app.connectors.sources.web.connector import WebConnector


@pytest.fixture(autouse=True)
def no_real_network(monkeypatch: pytest.MonkeyPatch) -> None:
    """Only Unix sockets (the fake websites) and the browser's own egress proxy may be connected to."""
    real_connect = socket.socket.connect
    real_connect_ex = socket.socket.connect_ex
    proxy_ports: set[int] = set()
    real_proxy_start = egress_proxy.EgressProxy.start

    async def proxy_start(self: egress_proxy.EgressProxy) -> str:
        url = await real_proxy_start(self)
        proxy_ports.add(int(url.rsplit(":", 1)[1]))
        return url

    monkeypatch.setattr(egress_proxy.EgressProxy, "start", proxy_start)

    def _guard(sock: socket.socket, address: object) -> None:
        if sock.family == socket.AF_UNIX:
            return
        if isinstance(address, tuple) and address[0] == "127.0.0.1" and address[1] in proxy_ports:
            return
        raise AssertionError(f"test tried to reach the network: {address!r}")

    def connect(sock: socket.socket, address: object) -> None:
        _guard(sock, address)
        return real_connect(sock, address)

    def connect_ex(sock: socket.socket, address: object) -> int:
        _guard(sock, address)
        return real_connect_ex(sock, address)

    monkeypatch.setattr(socket.socket, "connect", connect)
    monkeypatch.setattr(socket.socket, "connect_ex", connect_ex)
    # The fake websites' .test hosts resolve to a public address, so the SSRF policy runs for real.
    real_getaddrinfo = socket.getaddrinfo

    def getaddrinfo(host: object, *args: object, **kwargs: object) -> list:
        if isinstance(host, str) and host.endswith(".test"):
            return [(socket.AF_INET, socket.SOCK_STREAM, 6, "", (FAKE_PUBLIC_ADDRESS, 0))]
        return real_getaddrinfo(host, *args, **kwargs)  # type: ignore[arg-type]

    monkeypatch.setattr(socket, "getaddrinfo", getaddrinfo)
    # As if curl_cffi and cloudscraper were not installed: the aiohttp strategy serves every fetch.
    monkeypatch.setattr(fetch_strategy, "_CURL_PROFILES", [])
    monkeypatch.setitem(sys.modules, "cloudscraper", None)


@pytest.fixture
def clock(monkeypatch: pytest.MonkeyPatch) -> VirtualClock:
    virtual = VirtualClock()
    monkeypatch.setattr(connector_module, "asyncio", virtual)
    monkeypatch.setattr(fetch_strategy, "asyncio", virtual)
    return virtual


@pytest.fixture
async def site(monkeypatch: pytest.MonkeyPatch) -> AsyncIterator[FakeWeb]:
    fake = FakeWeb()
    app = web.Application()
    app.router.add_route("*", "/{tail:.*}", fake.handle)
    runner = web.AppRunner(app, access_log=None)
    await runner.setup()
    sock_dir = tempfile.mkdtemp(prefix="webfake-")
    sock_path = f"{sock_dir}/site.sock"
    await web.UnixSite(runner, sock_path).start()

    real_session = aiohttp.ClientSession

    def session_on_fake_web(*args: object, **kwargs: object) -> aiohttp.ClientSession:
        kwargs["connector"] = aiohttp.UnixConnector(path=sock_path)
        return real_session(*args, **kwargs)  # type: ignore[arg-type]

    monkeypatch.setattr(aiohttp, "ClientSession", session_on_fake_web)

    async def upstream_on_fake_web(*_: object, **__: object) -> tuple[asyncio.StreamReader, asyncio.StreamWriter]:
        return await asyncio.open_unix_connection(sock_path)

    # The egress proxy connects to the checked address; on the fake web every address is the site.
    fake_asyncio = SimpleNamespace(**{name: getattr(asyncio, name) for name in dir(asyncio) if not name.startswith("_")})
    fake_asyncio.open_connection = upstream_on_fake_web
    monkeypatch.setattr(egress_proxy, "asyncio", fake_asyncio)
    try:
        yield fake
    finally:
        await runner.cleanup()
        shutil.rmtree(sock_dir, ignore_errors=True)


@pytest.fixture
async def browser(site: FakeWeb, monkeypatch: pytest.MonkeyPatch) -> AsyncIterator[FakeWeb]:
    """crawl4ai's browser renders from the fake websites; the shared fetcher starts fresh."""
    monkeypatch.setattr(crawl4ai_fetcher, "AsyncWebCrawler", browser_crawler_class(site))
    monkeypatch.setattr(crawl4ai_fetcher, "AsyncPlaywrightCrawlerStrategy", lambda **kw: SimpleNamespace(**kw))
    monkeypatch.setattr(crawl4ai_fetcher, "UndetectedAdapter", lambda: SimpleNamespace())
    monkeypatch.setattr(crawl4ai_fetcher, "_shared_instance", None)
    monkeypatch.setattr(crawl4ai_fetcher, "_ref_count", 0)
    monkeypatch.setattr(crawl4ai_fetcher, "_shared_lock", None)
    try:
        yield site
    finally:
        leftover = crawl4ai_fetcher._shared_instance
        if leftover is not None:
            await leftover.close()


@pytest.fixture
def use_strategy(site: FakeWeb, monkeypatch: pytest.MonkeyPatch) -> Callable[[str], None]:
    """Serve page fetches with one of the fetcher's strategies (aiohttp is the default)."""
    def _use(name: str) -> None:
        if name == "curl_cffi":
            import curl_cffi.requests

            monkeypatch.setattr(fetch_strategy, "_CURL_PROFILES", ["chrome"])
            monkeypatch.setattr(curl_cffi.requests, "Session", lambda **_: FakeRequestsClient(site, "curl_cffi"))
        elif name == "cloudscraper":
            fake = SimpleNamespace(create_scraper=lambda **_: FakeScraper(site, "cloudscraper"))
            monkeypatch.setitem(sys.modules, "cloudscraper", fake)
    return _use


@pytest.fixture
def db() -> FakeRecordsDb:
    return FakeRecordsDb()


@pytest.fixture
def checkpoints() -> FakeCheckpointStore:
    return FakeCheckpointStore()


@pytest.fixture
def notifications() -> RecordingNotifications:
    return RecordingNotifications()


@pytest.fixture
async def make_connector(
    browser: FakeWeb,
    clock: VirtualClock,
    db: FakeRecordsDb,
    checkpoints: FakeCheckpointStore,
    notifications: RecordingNotifications,
) -> AsyncIterator[MakeConnector]:
    built: list[WebConnector] = []

    async def _make(
        url: str = START_URL,
        *,
        crawl_type: str = "recursive",
        depth: int = 3,
        max_pages: int = 100,
        filters: dict[str, Any] | None = None,
        scope: str = "team",
        expect_init: bool = True,
        **sync: object,
    ) -> WebConnector:
        config = FakeConfigService(
            CONNECTOR_ID,
            {"url": url, "type": crawl_type, "depth": depth, "max_pages": max_pages, **sync},
            filters,
        )
        connector = WebConnector(
            logging.getLogger("web-behaviour"),
            db,  # type: ignore[arg-type]
            SimpleNamespace(transaction=checkpoints.transaction),  # type: ignore[arg-type]
            config,  # type: ignore[arg-type]
            CONNECTOR_ID,
            scope,
            "user-1",
        )
        connector._notification_service = notifications
        built.append(connector)
        assert await connector.init() is expect_init
        return connector

    yield _make
    for connector in built:
        await connector.cleanup()
