"""``Crawl4AIFetcher`` over a fake browser: its own thread and event loop,
status resolution, failure isolation and the process-wide shared instance.
"""

import asyncio
from collections.abc import Awaitable, Callable
from types import SimpleNamespace

import pytest
from web_behaviour_fakes import FakeWeb, Page, browser_crawler_class, html_page

from app.connectors.sources.web import crawl4ai_fetcher
from app.connectors.sources.web.crawl4ai_fetcher import (
    Crawl4AIFetcher,
    get_shared_fetcher,
    release_shared_fetcher,
)
from app.connectors.sources.web.fetch_strategy import BLOCKED_URL_MESSAGE


def _with_crawler(monkeypatch: pytest.MonkeyPatch, arun: Callable[[str], Awaitable[object]], site: FakeWeb) -> None:
    """Replace the fake browser's ``arun`` with a scripted one."""
    base = browser_crawler_class(site)

    class Scripted(base):  # type: ignore[misc,valid-type]
        async def arun(self, url: str, config: object = None, **kw: object) -> object:
            return await arun(url)

    monkeypatch.setattr(crawl4ai_fetcher, "AsyncWebCrawler", Scripted)


def _crawl_result(url: str, **kw: object) -> SimpleNamespace:
    fields = {"url": url, "redirected_url": url, "html": "", "success": False, "status_code": None,
              "error_message": None, "crawl_stats": None, "js_execution_result": None}
    fields.update(kw)
    return SimpleNamespace(**fields)


async def test_fetch_returns_the_rendered_page_from_the_browser_thread(browser: FakeWeb) -> None:
    browser.html("http://site.test/", "Home", text="Hello from the browser")

    async with Crawl4AIFetcher(concurrency=2) as fetcher:
        result = await fetcher.fetch("http://site.test/")

    assert result.success is True
    assert result.status_code == 200
    assert "Hello from the browser" in (result.html or "")


async def test_fetch_before_start_says_how_to_start_the_fetcher(browser: FakeWeb) -> None:
    fetcher = Crawl4AIFetcher()

    with pytest.raises(RuntimeError, match="call start"):
        await fetcher.fetch("http://site.test/")
    with pytest.raises(RuntimeError, match="call start"):
        await fetcher.fetch_many(["http://site.test/"])


@pytest.mark.parametrize(
    ("scripted", "expected_status"),
    [
        pytest.param({"error_message": "Failed on navigating ACS-GOTO: HTTP 403"}, 403, id="status-in-error"),
        pytest.param({"crawl_stats": {"proxies_used": [{"status_code": 502}, {"status_code": None}]}}, 502,
                     id="status-from-proxy-attempts"),
        pytest.param({"error_message": "net::ERR_NAME_NOT_RESOLVED"}, None, id="no-status-anywhere"),
    ],
)
async def test_a_missing_status_is_recovered_from_whatever_the_browser_reported(
    scripted: dict, expected_status: int | None, browser: FakeWeb, monkeypatch: pytest.MonkeyPatch
) -> None:
    async def arun(url: str) -> SimpleNamespace:
        return _crawl_result(url, **scripted)

    _with_crawler(monkeypatch, arun, browser)

    async with Crawl4AIFetcher() as fetcher:
        result = await fetcher.fetch("http://site.test/")

    assert result.success is False
    assert result.status_code == expected_status


@pytest.mark.parametrize(
    ("failure", "message"),
    [
        pytest.param(RuntimeError("Target page, context or browser has been closed"), "browser has been closed",
                     id="browser-crash"),
        pytest.param(asyncio.TimeoutError(), "Timed out after", id="timeout"),
    ],
)
async def test_a_browser_failure_comes_back_as_a_failed_result_not_an_exception(
    failure: BaseException, message: str, browser: FakeWeb, monkeypatch: pytest.MonkeyPatch
) -> None:
    async def arun(url: str) -> SimpleNamespace:
        raise failure

    _with_crawler(monkeypatch, arun, browser)

    async with Crawl4AIFetcher() as fetcher:
        result = await fetcher.fetch("http://site.test/")

    assert result.success is False
    assert message in (result.error or "")


async def test_fetch_many_returns_one_result_per_url_and_isolates_failures(
    browser: FakeWeb, monkeypatch: pytest.MonkeyPatch
) -> None:
    browser.html("http://site.test/a", "A")
    browser.html("http://site.test/c", "C")
    base = browser_crawler_class(browser)

    async def arun(url: str) -> object:
        if url.endswith("/b"):
            raise RuntimeError("tab crashed")
        return await base().arun(url)

    _with_crawler(monkeypatch, arun, browser)
    urls = ["http://site.test/a", "http://site.test/b", "http://site.test/c"]

    async with Crawl4AIFetcher(concurrency=2) as fetcher:
        results = await fetcher.fetch_many(urls)

    assert [r.success for r in results] == [True, False, True]
    assert "tab crashed" in (results[1].error or "")
    assert "<title>C</title>" in (results[2].html or "")


async def test_fetch_many_reports_every_url_as_failed_when_the_batch_blows_up(
    browser: FakeWeb, monkeypatch: pytest.MonkeyPatch
) -> None:
    base = browser_crawler_class(browser)

    class Broken(base):  # type: ignore[misc,valid-type]
        async def arun_many(self, *_: object, **__: object) -> list[object]:
            raise RuntimeError("browser context lost")

    monkeypatch.setattr(crawl4ai_fetcher, "AsyncWebCrawler", Broken)

    async with Crawl4AIFetcher() as fetcher:
        results = await fetcher.fetch_many(["http://site.test/a", "http://site.test/b"])

    assert [(r.url, r.success, r.error) for r in results] == [
        ("http://site.test/a", False, "browser context lost"),
        ("http://site.test/b", False, "browser context lost"),
    ]


async def test_closing_the_fetcher_stops_its_browser_thread(browser: FakeWeb) -> None:
    fetcher = Crawl4AIFetcher()
    await fetcher.start()
    thread = fetcher._thread
    assert thread is not None and thread.is_alive()

    await fetcher.close()

    assert not thread.is_alive()


async def test_the_shared_fetcher_starts_one_browser_and_closes_it_after_the_last_release(browser: FakeWeb) -> None:
    first = await get_shared_fetcher()
    second = await get_shared_fetcher()

    assert first is second
    assert browser.browser_starts == 1

    await release_shared_fetcher()
    assert crawl4ai_fetcher._shared_instance is first
    await release_shared_fetcher()
    assert crawl4ai_fetcher._shared_instance is None
    await release_shared_fetcher()
    assert crawl4ai_fetcher._ref_count == 0


async def test_a_browser_that_fails_to_start_is_tried_again_next_time(browser: FakeWeb) -> None:
    browser.browser_broken = True
    with pytest.raises(RuntimeError, match="Executable doesn't exist"):
        await get_shared_fetcher()
    assert crawl4ai_fetcher._shared_instance is None

    browser.browser_broken = False
    fetcher = await get_shared_fetcher()

    browser.html("http://site.test/", "Home")
    assert (await fetcher.fetch("http://site.test/")).success is True
    assert browser.browser_starts == 2
    await release_shared_fetcher()


@pytest.mark.parametrize("many", [False, True], ids=["fetch", "fetch_many"])
async def test_a_redirect_in_the_browser_reports_where_the_page_ended_up(many: bool, browser: FakeWeb) -> None:
    browser.redirect("http://site.test/old", "/new")
    browser.add("http://site.test/new", Page(body=html_page("New")))

    async with Crawl4AIFetcher() as fetcher:
        if many:
            [result] = await fetcher.fetch_many(["http://site.test/old"])
        else:
            result = await fetcher.fetch("http://site.test/old")

    assert result.url == "http://site.test/new"


METADATA = "http://169.254.169.254/latest/meta-data/"


async def test_the_browser_is_never_given_an_internal_address(browser: FakeWeb) -> None:
    browser.html(METADATA, "AKIA-SECRET")

    async with Crawl4AIFetcher() as fetcher:
        single = await fetcher.fetch(METADATA)
        batch = await fetcher.fetch_many(["http://site.test/", METADATA])

    assert single.success is False and single.error == BLOCKED_URL_MESSAGE and single.html is None
    assert batch[1].error == BLOCKED_URL_MESSAGE and batch[1].html is None
    assert batch[0].url == "http://site.test/"
    assert METADATA not in browser.browser_loaded


@pytest.mark.parametrize("many", [False, True])
async def test_a_render_that_lands_on_an_internal_address_is_discarded(many: bool, browser: FakeWeb) -> None:
    browser.add("http://site.test/go", Page(status=302, location=METADATA, content_type=None))
    browser.html(METADATA, "AKIA-SECRET")

    async with Crawl4AIFetcher() as fetcher:
        result = (await fetcher.fetch_many(["http://site.test/go"]))[0] if many else await fetcher.fetch("http://site.test/go")

    assert result.success is False
    assert result.error == BLOCKED_URL_MESSAGE
    assert result.html is None
    assert result.url == "http://site.test/go"


async def test_the_browser_is_launched_behind_the_egress_proxy(browser: FakeWeb) -> None:
    browser.add("http://site.test/", Page(body=html_page("Home"), subresources=(METADATA, "/logo.png")))
    browser.add("http://site.test/logo.png", Page(body=b"PNG", content_type="image/png"))

    async with Crawl4AIFetcher() as fetcher:
        result = await fetcher.fetch("http://site.test/")
        proxy = fetcher._browser_config.proxy_config.server  # noqa: SLF001

    assert result.success is True
    assert proxy.startswith("http://127.0.0.1:")
    assert dict(browser.browser_subresources) == {METADATA: 403, "http://site.test/logo.png": 200}
    assert METADATA not in [url for _, url in browser.requests]
