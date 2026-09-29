"""GHSA-p6qp-x5q4-jvx3: a crawl never requests a private, loopback, link-local or metadata address,
whether it is the configured URL, a link, or a redirect, with any fetch strategy or the browser.

Follow External Links is on in these tests, so only the SSRF policy stands between the crawl and
the internal address; crawl scope would otherwise refuse most of them first.
"""

import socket
from collections.abc import Callable

import pytest
from web_behaviour_fakes import START_URL, FakeRecordsDb, FakeWeb, MakeConnector, Page

from app.config.constants.arangodb import ProgressStatus
from app.connectors.core.base.connector.connector_service import ConnectorInitError
from app.connectors.sources.web.fetch_strategy import BLOCKED_URL_MESSAGE

STRATEGIES = ["aiohttp", "curl_cffi", "cloudscraper"]
METADATA = "http://169.254.169.254/latest/meta-data/iam/security-credentials/"
INTRANET = "http://intranet.test/admin"  # a name whose DNS answer is a private address


@pytest.fixture(autouse=True)
def intranet_resolves_privately(monkeypatch: pytest.MonkeyPatch) -> None:
    public_answer = socket.getaddrinfo

    def getaddrinfo(host: object, *args: object, **kwargs: object) -> list:
        if host == "intranet.test":
            return [(socket.AF_INET, socket.SOCK_STREAM, 6, "", ("10.0.0.5", 0))]
        return public_answer(host, *args, **kwargs)  # type: ignore[arg-type]

    monkeypatch.setattr(socket, "getaddrinfo", getaddrinfo)


def _internal_pages(site: FakeWeb) -> None:
    site.html(METADATA, "AKIA-SECRET")
    site.html(INTRANET, "Intranet admin")


def _requested(site: FakeWeb, url: str) -> bool:
    return any(requested == url for _, requested in site.requests) or url in site.browser_loaded


@pytest.mark.parametrize(
    "url", [METADATA, "http://127.0.0.1:9911/", "http://localhost/", "http://[::ffff:127.0.0.1]/", INTRANET],
)
async def test_an_internal_start_url_is_rejected_when_the_connector_is_set_up(
    url: str, site: FakeWeb, make_connector: MakeConnector,
) -> None:
    _internal_pages(site)

    with pytest.raises(ConnectorInitError, match="private, internal or reserved"):
        await make_connector(url)

    assert not _requested(site, url)


@pytest.mark.parametrize("strategy", STRATEGIES)
@pytest.mark.parametrize("target", [METADATA, INTRANET])
async def test_a_redirect_to_an_internal_address_is_never_requested(
    strategy: str, target: str, site: FakeWeb, db: FakeRecordsDb, use_strategy: Callable[[str], None],
    make_connector: MakeConnector,
) -> None:
    use_strategy(strategy)
    _internal_pages(site)
    site.html(START_URL, "Home", "/harmless-looking-page")
    site.add("http://site.test/harmless-looking-page", Page(status=302, location=target, content_type=None))

    await (await make_connector(follow_external=True)).run_sync()

    assert not _requested(site, target)
    assert target not in db.pages()
    failed = db.pages()["http://site.test/harmless-looking-page"]
    assert failed.indexing_status == ProgressStatus.FAILED.value
    assert failed.reason == BLOCKED_URL_MESSAGE


@pytest.mark.parametrize("strategy", STRATEGIES)
async def test_a_link_to_an_internal_address_is_never_requested(
    strategy: str, site: FakeWeb, db: FakeRecordsDb, use_strategy: Callable[[str], None],
    make_connector: MakeConnector,
) -> None:
    use_strategy(strategy)
    _internal_pages(site)
    site.html(START_URL, "Home", METADATA, INTRANET)

    await (await make_connector(follow_external=True)).run_sync()

    assert not _requested(site, METADATA)
    assert not _requested(site, INTRANET)
    assert START_URL in db.pages()


@pytest.mark.parametrize("target", [METADATA, INTRANET])
async def test_in_robust_mode_the_browser_never_loads_a_redirect_to_an_internal_address(
    target: str, site: FakeWeb, db: FakeRecordsDb, make_connector: MakeConnector,
) -> None:
    _internal_pages(site)
    site.html(START_URL, "Home", "/harmless-looking-page")
    site.add("http://site.test/harmless-looking-page", Page(status=302, location=target, content_type=None))

    await (await make_connector(follow_external=True, use_headless_browser=True)).run_sync()

    assert not _requested(site, target)
    assert target not in db.pages()


async def test_the_connection_test_reports_a_redirect_to_an_internal_address_as_not_reachable(
    site: FakeWeb, make_connector: MakeConnector,
) -> None:
    _internal_pages(site)
    site.add(START_URL, Page(status=302, location=METADATA, content_type=None))
    connector = await make_connector(follow_external=True)

    assert await connector.test_connection_and_access() is False
    assert not _requested(site, METADATA)


async def test_in_robust_mode_a_page_s_own_requests_to_internal_addresses_never_leave_the_browser(
    site: FakeWeb, db: FakeRecordsDb, make_connector: MakeConnector,
) -> None:
    """Images, iframes and fetch() calls the page makes itself go through the egress proxy."""
    _internal_pages(site)
    site.add("http://site.test/logo.png", Page(body=b"PNG", content_type="image/png"))
    site.add(START_URL, Page(
        body=b"<html><body><h1>Home</h1><p>Welcome to the site.</p></body></html>",
        subresources=("/logo.png", METADATA, INTRANET, "http://127.0.0.1:9911/"),
    ))

    await (await make_connector(crawl_type="single", use_headless_browser=True)).run_sync()

    assert START_URL in db.pages()
    assert dict(site.browser_subresources) == {
        "http://site.test/logo.png": 200,
        METADATA: 403,
        INTRANET: 403,
        "http://127.0.0.1:9911/": 403,
    }
    assert not _requested(site, METADATA)
    assert not _requested(site, INTRANET)
