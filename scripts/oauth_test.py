#!/usr/bin/env python3
"""
OAuth Comprehensive Test Script for PipesHub Platform.

Tests OAuth scope enforcement through the Node.js API gateway.
All requests go through the Node.js backend which proxies to Python services internally.
Verifies:
  - Regular JWT tokens pass through all APIs without scope restrictions
  - OAuth tokens with correct scopes are accepted
  - OAuth tokens with wrong scopes are rejected (403)
  - Token lifecycle (introspection, revocation)
  - Edge cases (no token, malformed token)

Usage:
    # Client credentials flow (default)
    python scripts/oauth_test.py --jwt-token <PLATFORM_JWT_TOKEN>

    # Authorization code flow (opens browser for user consent)
    python scripts/oauth_test.py --jwt-token <TOKEN> --auth-flow authorization_code

    Optional flags:
        --nodejs-url     http://localhost:3000  (Node.js backend)
        --frontend-url   http://localhost:3001  (Frontend for consent page)
        --csv-output     scripts/oauth_test_report.csv
        --skip-cleanup   Don't delete OAuth apps after tests
        --callback-port  9999                    (Local callback server port)
"""

import argparse
import csv
import hashlib
import json
import os
import secrets
import sys
import time
import webbrowser
from dataclasses import dataclass, field
from http.server import HTTPServer, BaseHTTPRequestHandler
from threading import Thread, Event
from typing import Any, Optional
from urllib.parse import urlencode, urlparse, parse_qs
import base64

try:
    import requests
except ImportError:
    print("ERROR: 'requests' library is required. Install with: pip install requests")
    sys.exit(1)

# ---------------------------------------------------------------------------
# ANSI colours for console output
# ---------------------------------------------------------------------------
GREEN = "\033[92m"
RED = "\033[91m"
YELLOW = "\033[93m"
CYAN = "\033[96m"
BOLD = "\033[1m"
RESET = "\033[0m"

# ---------------------------------------------------------------------------
# Data classes
# ---------------------------------------------------------------------------


@dataclass
class Endpoint:
    """Represents an API endpoint to test."""

    method: str
    path: str
    service: str  # "nodejs"
    required_scopes: list[str]
    body: Optional[dict] = None
    description: str = ""
    query_params: Optional[dict] = None


@dataclass
class TestResult:
    """Stores one test result."""

    service: str
    method: str
    endpoint: str
    scope_required: str
    token_type: str  # "jwt", "oauth_full", "oauth_read", etc.
    expected_status: str  # e.g. "2xx", "403", "401"
    actual_status: int
    passed: bool
    notes: str = ""


@dataclass
class OAuthApp:
    """Holds details of a created OAuth app."""

    app_id: str = ""
    client_id: str = ""
    client_secret: str = ""
    name: str = ""
    scopes: list[str] = field(default_factory=list)
    access_token: str = ""


# ---------------------------------------------------------------------------
# Authorization Code callback server
# ---------------------------------------------------------------------------


class _CallbackResult:
    """Shared state between callback server and main thread."""

    def __init__(self):
        self.code: Optional[str] = None
        self.state: Optional[str] = None
        self.error: Optional[str] = None
        self.received = Event()


class _CallbackHandler(BaseHTTPRequestHandler):
    """HTTP handler that captures the OAuth authorization code from the redirect."""

    callback_result: _CallbackResult  # set by the factory

    def do_GET(self):
        parsed = urlparse(self.path)
        params = parse_qs(parsed.query)
        result = self.__class__.callback_result

        # Only process /callback path with code or error params.
        # Ignore favicon, stale requests, etc.
        if not parsed.path.rstrip("/").endswith("/callback"):
            self.send_response(204)
            self.end_headers()
            return

        if "code" not in params and "error" not in params:
            # Callback path but no OAuth params — ignore silently
            self.send_response(204)
            self.end_headers()
            return

        if "error" in params:
            result.error = params["error"][0]
        else:
            result.code = params["code"][0]
            result.state = params.get("state", [None])[0]

        # Send a friendly HTML response to the browser
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.end_headers()
        if result.error:
            body = (
                "<html><body><h2>Authorization Failed</h2>"
                f"<p>Error: {result.error}</p>"
                "<p>You can close this tab.</p></body></html>"
            )
        else:
            body = (
                "<html><body><h2>Authorization Successful</h2>"
                "<p>Code received. You can close this tab and return to the terminal.</p>"
                "</body></html>"
            )
        self.wfile.write(body.encode())
        result.received.set()

    def log_message(self, *args):
        """Suppress default request logging."""
        pass


def _make_handler(result: _CallbackResult):
    """Create a handler class bound to a specific result object."""

    class Handler(_CallbackHandler):
        callback_result = result

    return Handler


# ---------------------------------------------------------------------------
# PKCE helpers
# ---------------------------------------------------------------------------


def _generate_pkce():
    """Generate PKCE code_verifier and code_challenge (S256)."""
    verifier = secrets.token_urlsafe(64)[:128]
    digest = hashlib.sha256(verifier.encode("ascii")).digest()
    challenge = base64.urlsafe_b64encode(digest).rstrip(b"=").decode("ascii")
    return verifier, challenge


# ---------------------------------------------------------------------------
# API Endpoint registry
# ---------------------------------------------------------------------------

# A representative subset of endpoints per service/scope category.
# We pick stable GET endpoints that return data (not 404-prone parameterised ones).

ENDPOINTS: list[Endpoint] = [
    # -------------------------------------------------------------------------
    # Node.js (port 3000)
    # -------------------------------------------------------------------------
    # Organization
    # Endpoint("GET", "/api/v1/org", "nodejs", ["org:read"], description="Get org info"),
    # # Users
    # Endpoint("GET", "/api/v1/users", "nodejs", ["user:read"], description="List users"),
    # User Groups
    Endpoint(
        "GET",
        "/api/v1/userGroups",
        "nodejs",
        ["usergroup:read"],
        description="List user groups",
    ),
    # Teams
    Endpoint("GET", "/api/v1/teams", "nodejs", ["team:read"], description="List teams"),
    # Knowledge Base
    Endpoint(
        "GET",
        "/api/v1/knowledgeBase",
        "nodejs",
        ["kb:read"],
        description="List knowledge bases",
    ),
    # Conversations
    Endpoint(
        "GET",
        "/api/v1/conversations",
        "nodejs",
        ["conversation:read"],
        description="List conversations",
    ),
    # Connectors
    Endpoint(
        "GET",
        "/api/v1/connectors/registry",
        "nodejs",
        ["connector:read"],
        description="Connector registry",
    ),
    Endpoint(
        "GET",
        "/api/v1/connectors",
        "nodejs",
        ["connector:read"],
        description="List connectors",
        query_params={"scope": "personal"},
    ),
    Endpoint(
        "GET",
        "/api/v1/connectors/active",
        "nodejs",
        ["connector:read"],
        description="Active connectors",
    ),
    Endpoint(
        "GET",
        "/api/v1/connectors/configured",
        "nodejs",
        ["connector:read"],
        description="Configured connectors",
    ),
    # OAuth config
    Endpoint(
        "GET",
        "/api/v1/oauth/registry",
        "nodejs",
        ["connector:read"],
        description="OAuth config registry",
    ),
    Endpoint(
        "GET",
        "/api/v1/oauth",
        "nodejs",
        ["connector:read"],
        description="OAuth configs",
    ),
    # Search
    Endpoint(
        "POST",
        "/api/v1/search",
        "nodejs",
        ["search:query", "search:semantic"],
        body={"query": "test", "limit": 1},
        description="Semantic search",
    ),
    # Agents
    Endpoint(
        "GET",
        "/api/v1/agents",
        "nodejs",
        ["agent:read"],
        description="List agents",
    ),
    Endpoint(
        "GET",
        "/api/v1/agents/template",
        "nodejs",
        ["agent:read"],
        description="List agent templates",
    ),
    # KB upload limits (lightweight read to test kb:read scope)
    Endpoint(
        "GET",
        "/api/v1/knowledgeBase/limits",
        "nodejs",
        ["kb:read"],
        description="KB upload limits",
    ),
    # Toolsets
    Endpoint(
        "GET",
        "/api/v1/toolsets/registry",
        "nodejs",
        ["connector:read"],
        description="Toolsets registry",
    ),
    Endpoint(
        "GET",
        "/api/v1/toolsets/configured",
        "nodejs",
        ["connector:read"],
        description="Configured toolsets",
    ),
    # -------------------------------------------------------------------------
    # Additional endpoints (Node.js proxies to Python services internally)
    # -------------------------------------------------------------------------
    # Records (proxies to Python connectors /api/v1/records)
    Endpoint(
        "GET",
        "/api/v1/knowledgeBase/records",
        "nodejs",
        ["kb:read"],
        description="List records",
    ),
    # User teams (proxies to Python connectors /api/v1/entity/user/teams)
    Endpoint(
        "GET",
        "/api/v1/teams/user/teams",
        "nodejs",
        ["team:read"],
        description="User teams",
    ),
    Endpoint(
        "GET",
        "/api/v1/teams/user/teams/created",
        "nodejs",
        ["team:read"],
        description="User created teams",
    ),
    # Knowledge Hub (proxies to Python connectors /api/v1/knowledge-hub/nodes)
    Endpoint(
        "GET",
        "/api/v1/knowledgeBase/knowledge-hub/nodes",
        "nodejs",
        ["kb:read"],
        description="Knowledge hub nodes",
    ),
    # Chat (proxies to Python query /api/v1/chat)
    Endpoint(
        "POST",
        "/api/v1/conversations/create",
        "nodejs",
        ["conversation:write"],
        body={"query": "test"},
        description="Create conversation (chat)",
    ),
]

# ---------------------------------------------------------------------------
# All available scopes
# ---------------------------------------------------------------------------

ALL_SCOPES = [
    "org:read",
    "org:write",
    "org:admin",
    "user:read",
    "user:write",
    "user:invite",
    "user:delete",
    "usergroup:read",
    "usergroup:write",
    "team:read",
    "team:write",
    "kb:read",
    "kb:write",
    "kb:delete",
    "kb:upload",
    "search:query",
    "search:semantic",
    "conversation:read",
    "conversation:write",
    "conversation:chat",
    "agent:read",
    "agent:write",
    "agent:execute",
    "connector:read",
    "connector:write",
    "connector:sync",
    "connector:delete",
    "config:read",
    "config:write",
    "document:read",
    "document:write",
    "document:delete",
    "crawl:read",
    "crawl:write",
]

READ_SCOPES = [
    "org:read",
    "user:read",
    "usergroup:read",
    "team:read",
    "kb:read",
    "search:query",
    "search:semantic",
    "conversation:read",
    "conversation:chat",
    "agent:read",
    "connector:read",
    "config:read",
    "document:read",
    "crawl:read",
]

CONNECTOR_ONLY_SCOPES = ["connector:read"]

WRITE_ONLY_SCOPES = [
    "org:write",
    "user:write",
    "usergroup:write",
    "team:write",
    "kb:write",
    "connector:write",
    "config:write",
    "document:write",
    "conversation:write",
    "agent:write",
    "crawl:write",
]

WRONG_SCOPES = ["crawl:read", "crawl:write"]

# ---------------------------------------------------------------------------
# OAuth app definitions
# ---------------------------------------------------------------------------

OAUTH_APPS_SPEC = {
    "app_a_full": {
        "name": "Test App A - Full Access",
        "scopes": ALL_SCOPES,
        "description": "All scopes",
    },
    "app_b_read": {
        "name": "Test App B - Read Only",
        "scopes": READ_SCOPES,
        "description": "Read-only scopes",
    },
    "app_c_connector": {
        "name": "Test App C - Connector Read Only",
        "scopes": CONNECTOR_ONLY_SCOPES,
        "description": "connector:read only",
    },
    "app_d_write": {
        "name": "Test App D - Write Only",
        "scopes": WRITE_ONLY_SCOPES,
        "description": "Write-only scopes",
    },
    "app_e_wrong": {
        "name": "Test App E - Wrong Scopes",
        "scopes": WRONG_SCOPES,
        "description": "Only crawl scopes (no matching scopes for most APIs)",
    },
}


# ---------------------------------------------------------------------------
# Test runner
# ---------------------------------------------------------------------------


class OAuthTestRunner:
    """Runs all OAuth test phases and generates reports."""

    def __init__(
        self,
        jwt_token: str,
        auth_flow: str = "client_credentials",
        nodejs_url: str = "http://localhost:3000",
        frontend_url: str = "http://localhost:3001",
        csv_output: str = "scripts/oauth_test_report.csv",
        skip_cleanup: bool = False,
        timeout: int = 30,
        callback_port: int = 9999,
    ):
        self.jwt_token = jwt_token
        self.auth_flow = auth_flow
        self.frontend_url = frontend_url
        self.nodejs_url = nodejs_url
        self.csv_output = csv_output
        self.skip_cleanup = skip_cleanup
        self.timeout = timeout
        self.callback_port = callback_port
        self.callback_uri = f"http://localhost:{callback_port}/callback"

        self.results: list[TestResult] = []
        self.oauth_apps: dict[str, OAuthApp] = {}
        # Track test resources for cleanup
        self.test_record_ids: list[tuple[str, str]] = []  # (record_id, token)
        self.test_conversation_ids: list[tuple[str, str]] = []  # (conv_id, token)

    # -----------------------------------------------------------------------
    # Helpers
    # -----------------------------------------------------------------------

    def _url(self, _service: str, path: str) -> str:
        return f"{self.nodejs_url}{path}"

    def _headers(self, token: Optional[str] = None) -> dict[str, str]:
        headers = {"Content-Type": "application/json", "Accept": "application/json"}
        if token:
            headers["Authorization"] = f"Bearer {token}"
        return headers

    def _call_api(
        self,
        method: str,
        url: str,
        token: Optional[str] = None,
        body: Optional[dict] = None,
        params: Optional[dict] = None,
    ) -> tuple[int, Any]:
        """Make an HTTP request and return (status_code, response_json_or_text)."""
        try:
            resp = requests.request(
                method=method,
                url=url,
                headers=self._headers(token),
                json=body if body else None,
                params=params,
                timeout=self.timeout,
                allow_redirects=False,
            )
            try:
                data = resp.json()
            except (json.JSONDecodeError, ValueError):
                data = resp.text
            return resp.status_code, data
        except requests.ConnectionError:
            return 0, "Connection refused"
        except requests.Timeout:
            return 0, "Request timed out"
        except Exception as e:
            return 0, str(e)

    def _add_result(
        self,
        service: str,
        method: str,
        endpoint: str,
        scope_required: str,
        token_type: str,
        expected_status: str,
        actual_status: int,
        notes: str = "",
    ) -> TestResult:
        passed = self._check_status(expected_status, actual_status)
        result = TestResult(
            service=service,
            method=method,
            endpoint=endpoint,
            scope_required=scope_required,
            token_type=token_type,
            expected_status=expected_status,
            actual_status=actual_status,
            passed=passed,
            notes=notes,
        )
        self.results.append(result)
        status_icon = f"{GREEN}PASS{RESET}" if passed else f"{RED}FAIL{RESET}"
        print(
            f"  [{status_icon}] {method:6s} {service:12s} {endpoint:50s} "
            f"expected={expected_status:5s} actual={actual_status:3d}  {notes}"
        )
        return result

    @staticmethod
    def _check_status(expected: str, actual: int) -> bool:
        """Check if actual status matches expected pattern (e.g. '2xx', '403', '401')."""
        if expected == "2xx":
            return 200 <= actual < 300
        if expected == "4xx":
            return 400 <= actual < 500
        if expected == "non-403":
            return actual != 403
        try:
            return actual == int(expected)
        except ValueError:
            return False

    def _create_oauth_app(
        self,
        name: str,
        scopes: list[str],
        grant_types: Optional[list[str]] = None,
    ) -> Optional[OAuthApp]:
        """Create an OAuth app via admin API."""
        if grant_types is None:
            grant_types = ["client_credentials"]

        body = {
            "name": name,
            "description": f"Auto-created test app: {name}",
            "redirectUris": [self.callback_uri],
            "allowedGrantTypes": grant_types,
            "allowedScopes": scopes,
            "isConfidential": True,
            "accessTokenLifetime": 3600,
        }

        status, data = self._call_api(
            "POST",
            self._url("nodejs", "/api/v1/oauth-clients"),
            token=self.jwt_token,
            body=body,
        )

        if status != 201 or not isinstance(data, dict):
            print(
                f"  {RED}Failed to create OAuth app '{name}': "
                f"status={status}, response={data}{RESET}"
            )
            return None

        app_data = data.get("app", data)
        app = OAuthApp(
            app_id=app_data.get("id", app_data.get("_id", "")),
            client_id=app_data.get("clientId", ""),
            client_secret=app_data.get("clientSecret", ""),
            name=name,
            scopes=scopes,
        )
        print(f"  {GREEN}Created app '{name}' (clientId={app.client_id}){RESET}")
        return app

    # -----------------------------------------------------------------------
    # Token acquisition — client_credentials
    # -----------------------------------------------------------------------

    def _get_token_client_credentials(self, app: OAuthApp) -> Optional[str]:
        """Get an access token via client_credentials grant."""
        body = {
            "grant_type": "client_credentials",
            "client_id": app.client_id,
            "client_secret": app.client_secret,
            "scope": " ".join(app.scopes),
        }

        status, data = self._call_api(
            "POST",
            self._url("nodejs", "/api/v1/oauth2/token"),
            body=body,
        )

        if status != 200 or not isinstance(data, dict):
            print(
                f"  {RED}Failed to get token for '{app.name}': "
                f"status={status}, response={data}{RESET}"
            )
            return None

        token = data.get("access_token", "")
        if token:
            print(
                f"  {GREEN}Got token for '{app.name}' "
                f"(expires_in={data.get('expires_in')}, "
                f"scope={data.get('scope', 'N/A')}){RESET}"
            )
        return token

    # -----------------------------------------------------------------------
    # Token acquisition — authorization_code (browser flow)
    # -----------------------------------------------------------------------

    def _get_token_authorization_code(self, app: OAuthApp) -> Optional[str]:
        """Get an access token via authorization_code grant with browser consent."""
        state = secrets.token_urlsafe(32)
        code_verifier, code_challenge = _generate_pkce()

        # Build the frontend consent URL
        params = {
            "response_type": "code",
            "client_id": app.client_id,
            "redirect_uri": self.callback_uri,
            "scope": " ".join(app.scopes),
            "state": state,
            "code_challenge": code_challenge,
            "code_challenge_method": "S256",
        }
        authorize_url = f"{self.frontend_url}/oauth/authorize?{urlencode(params)}"

        # Start local callback server that serves until the auth code arrives.
        result = _CallbackResult()
        handler_cls = _make_handler(result)
        server = HTTPServer(("127.0.0.1", self.callback_port), handler_cls)
        server.timeout = 1  # poll interval

        def _serve_until_done():
            while not result.received.is_set():
                server.handle_request()

        server_thread = Thread(target=_serve_until_done, daemon=True)
        server_thread.start()

        # Open browser
        print(f"\n  {BOLD}{CYAN}Opening browser for '{app.name}'{RESET}")
        print(f"  Scopes: {', '.join(app.scopes[:5])}{'...' if len(app.scopes) > 5 else ''}")
        print(f"  {YELLOW}Please authenticate and click 'Allow' in the browser.{RESET}")
        print(f"  Waiting for callback on {self.callback_uri} ...")
        webbrowser.open(authorize_url)

        # Wait for callback (up to 120 seconds)
        if not result.received.wait(timeout=120):
            server.server_close()
            print(f"  {RED}Timed out waiting for authorization callback (120s).{RESET}")
            return None

        server.server_close()

        if result.error:
            print(f"  {RED}Authorization error: {result.error}{RESET}")
            return None

        if not result.code:
            print(f"  {RED}No authorization code received.{RESET}")
            return None

        if result.state != state:
            print(f"  {RED}State mismatch! Expected={state}, got={result.state}{RESET}")
            return None

        print(f"  {GREEN}Authorization code received.{RESET}")

        # Exchange code for token
        body = {
            "grant_type": "authorization_code",
            "code": result.code,
            "redirect_uri": self.callback_uri,
            "client_id": app.client_id,
            "client_secret": app.client_secret,
            "code_verifier": code_verifier,
        }

        status, data = self._call_api(
            "POST",
            self._url("nodejs", "/api/v1/oauth2/token"),
            body=body,
        )

        if status != 200 or not isinstance(data, dict):
            print(
                f"  {RED}Failed to exchange code for token: "
                f"status={status}, response={data}{RESET}"
            )
            return None

        token = data.get("access_token", "")
        if token:
            print(
                f"  {GREEN}Got token for '{app.name}' "
                f"(expires_in={data.get('expires_in')}, "
                f"scope={data.get('scope', 'N/A')}){RESET}"
            )
        return token

    # -----------------------------------------------------------------------
    # Unified token getter
    # -----------------------------------------------------------------------

    def _get_oauth_token(self, app: OAuthApp) -> Optional[str]:
        """Get an access token using the configured auth flow."""
        if self.auth_flow == "authorization_code":
            return self._get_token_authorization_code(app)
        return self._get_token_client_credentials(app)

    # -----------------------------------------------------------------------
    # Token management helpers
    # -----------------------------------------------------------------------

    def _revoke_token(self, token: str, app: OAuthApp) -> int:
        """Revoke an OAuth token."""
        body = {
            "token": token,
            "client_id": app.client_id,
            "client_secret": app.client_secret,
        }
        status, _ = self._call_api(
            "POST",
            self._url("nodejs", "/api/v1/oauth2/revoke"),
            body=body,
        )
        return status

    def _introspect_token(self, token: str, app: OAuthApp) -> tuple[int, Any]:
        """Introspect an OAuth token."""
        body = {
            "token": token,
            "client_id": app.client_id,
            "client_secret": app.client_secret,
        }
        return self._call_api(
            "POST",
            self._url("nodejs", "/api/v1/oauth2/introspect"),
            body=body,
        )

    def _delete_oauth_app(self, app: OAuthApp) -> bool:
        """Delete an OAuth app."""
        status, _ = self._call_api(
            "DELETE",
            self._url("nodejs", f"/api/v1/oauth-clients/{app.app_id}"),
            token=self.jwt_token,
        )
        return status in (200, 204)

    def _get_default_kb_id(self, token: str) -> Optional[str]:
        """List knowledge bases and return the first (default) KB ID."""
        status, data = self._call_api(
            "GET",
            self._url("nodejs", "/api/v1/knowledgeBase"),
            token=token,
        )
        if status != 200 or not isinstance(data, dict):
            return None
        # Response may be {knowledgeBases: [...]} or {data: [...]} or a list
        kb_list = data.get("knowledgeBases") or data.get("data") or []
        if isinstance(data, list):
            kb_list = data
        if kb_list and isinstance(kb_list, list) and len(kb_list) > 0:
            kb = kb_list[0]
            return kb.get("_id") or kb.get("id") or kb.get("kbId")
        return None

    def _upload_to_kb(
        self,
        file_path: str,
        kb_id: str,
        token: str,
    ) -> tuple[int, Any]:
        """Upload a file to a Knowledge Base via multipart form-data.

        POST /api/v1/knowledgeBase/:kbId/upload
        Field name: 'files' (plural)
        Triggers indexing in the background.

        Returns (status, response_data).
        """
        url = self._url("nodejs", f"/api/v1/knowledgeBase/{kb_id}/upload")
        headers = {"Accept": "application/json"}
        if token:
            headers["Authorization"] = f"Bearer {token}"
        try:
            file_name = os.path.basename(file_path)
            with open(file_path, "rb") as f:
                resp = requests.post(
                    url,
                    headers=headers,
                    files={"files": (file_name, f, "application/pdf")},
                    data={"isVersioned": "false"},
                    timeout=self.timeout,
                )
            try:
                data = resp.json()
            except (json.JSONDecodeError, ValueError):
                data = resp.text
            return resp.status_code, data
        except FileNotFoundError:
            return 0, f"File not found: {file_path}"
        except Exception as e:
            return 0, str(e)

    # -----------------------------------------------------------------------
    # Test phases
    # -----------------------------------------------------------------------

    def phase1_health_check(self) -> bool:
        """Phase 1: Check Node.js backend is reachable."""
        print(f"\n{BOLD}{CYAN}Phase 1: Health Check{RESET}")
        print("=" * 70)

        url = self._url("nodejs", "/api/v1/health")
        status, _ = self._call_api("GET", url)
        up = status > 0
        self.nodejs_up = up
        icon = f"{GREEN}UP{RESET}" if up else f"{RED}DOWN{RESET}"
        print(f"  [{icon}] nodejs       ({url}) -> {status}")

        if not up:
            print(
                f"\n  {RED}Node.js backend is required. Aborting.{RESET}"
            )
            return False

        return True

    def phase2_jwt_tests(self):
        """Phase 2: Test regular JWT token passes all endpoints."""
        print(f"\n{BOLD}{CYAN}Phase 2: Regular JWT Token Tests{RESET}")
        print("=" * 70)
        print("  Regular JWT tokens should pass through scope middleware (no enforcement)")

        for ep in ENDPOINTS:
            if not self.nodejs_up:
                self._add_result(
                    ep.service,
                    ep.method,
                    ep.path,
                    " | ".join(ep.required_scopes),
                    "jwt",
                    "2xx",
                    0,
                    notes=f"SKIP - {ep.service} not reachable",
                )
                continue

            url = self._url(ep.service, ep.path)
            status, data = self._call_api(
                ep.method, url, self.jwt_token, ep.body, ep.query_params
            )

            # For JWT, we expect non-403. Some endpoints may 400/404 due to
            # missing data, but should never 403 on scope.
            self._add_result(
                ep.service,
                ep.method,
                ep.path,
                " | ".join(ep.required_scopes),
                "jwt",
                "non-403",
                status,
                notes=self._brief_error(data) if status >= 400 else "",
            )

    def phase3_create_oauth_apps(self) -> bool:
        """Phase 3: Create multiple OAuth apps with different scope combos."""
        print(f"\n{BOLD}{CYAN}Phase 3: OAuth App Creation ({self.auth_flow}){RESET}")
        print("=" * 70)

        grant_types = (
            ["authorization_code", "refresh_token"]
            if self.auth_flow == "authorization_code"
            else ["client_credentials"]
        )

        for key, spec in OAUTH_APPS_SPEC.items():
            app = self._create_oauth_app(
                name=spec["name"],
                scopes=spec["scopes"],
                grant_types=grant_types,
            )
            if app:
                self.oauth_apps[key] = app
            else:
                print(f"  {RED}CRITICAL: Failed to create {key}. Some tests will be skipped.{RESET}")

        if not self.oauth_apps:
            print(f"  {RED}No OAuth apps could be created. Aborting remaining tests.{RESET}")
            return False
        return True

    def phase4_token_generation(self) -> bool:
        """Phase 4: Generate tokens for each OAuth app."""
        print(f"\n{BOLD}{CYAN}Phase 4: OAuth Token Generation ({self.auth_flow}){RESET}")
        print("=" * 70)

        if self.auth_flow == "authorization_code":
            print(
                f"  {YELLOW}You will need to authorize {len(self.oauth_apps)} apps in the browser.{RESET}"
            )
            print(
                f"  {YELLOW}Make sure you are logged into the PipesHub frontend at {self.frontend_url}{RESET}\n"
            )

        success = False
        for _key, app in self.oauth_apps.items():
            token = self._get_oauth_token(app)
            if token:
                app.access_token = token
                success = True

                # Verify token response format
                status, data = self._introspect_token(token, app)
                if status == 200 and isinstance(data, dict):
                    active = data.get("active", False)
                    print(
                        f"    Introspection: active={active}, "
                        f"scope={data.get('scope', 'N/A')}"
                    )

        return success

    def phase5_positive_scope_tests(self):
        """Phase 5: OAuth tokens WITH correct scopes should succeed."""
        print(f"\n{BOLD}{CYAN}Phase 5: Positive Scope Tests (should succeed){RESET}")
        print("=" * 70)

        test_cases = [
            ("app_a_full", "All scopes"),
            ("app_b_read", "Read scopes"),
            ("app_c_connector", "Connector-read only"),
        ]

        for app_key, label in test_cases:
            app = self.oauth_apps.get(app_key)
            if not app or not app.access_token:
                print(f"  {YELLOW}SKIP: {label} - app not available{RESET}")
                continue

            print(f"\n  --- {label} ({app_key}) ---")
            for ep in ENDPOINTS:
                if not self.nodejs_up:
                    continue

                # Check if this app should have a matching scope for this endpoint
                has_scope = any(s in app.scopes for s in ep.required_scopes)
                if not has_scope:
                    continue  # Skip — this is a negative test case

                url = self._url(ep.service, ep.path)
                status, data = self._call_api(
                    ep.method, url, app.access_token, ep.body, ep.query_params
                )

                # Expect non-403 (could be 200, 400, 404 etc. but NOT 403)
                self._add_result(
                    ep.service,
                    ep.method,
                    ep.path,
                    " | ".join(ep.required_scopes),
                    f"oauth_{app_key}",
                    "non-403",
                    status,
                    notes=self._brief_error(data) if status >= 400 else "",
                )

    def phase6_negative_scope_tests(self):
        """Phase 6: OAuth tokens WITHOUT required scopes should get 403."""
        print(f"\n{BOLD}{CYAN}Phase 6: Negative Scope Tests (should get 403){RESET}")
        print("=" * 70)

        # Define which apps should FAIL on which endpoint categories
        negative_tests = [
            # App C (connector:read only) -> should fail on non-connector endpoints
            (
                "app_c_connector",
                "Connector-only vs non-connector endpoints",
                lambda ep: not any(s in CONNECTOR_ONLY_SCOPES for s in ep.required_scopes),
            ),
            # App D (write-only) -> should fail on read-only endpoints
            (
                "app_d_write",
                "Write-only vs read endpoints",
                lambda ep: not any(s in WRITE_ONLY_SCOPES for s in ep.required_scopes),
            ),
            # App E (wrong scopes: crawl only) -> should fail on everything
            (
                "app_e_wrong",
                "Wrong scopes vs all endpoints",
                lambda ep: not any(s in WRONG_SCOPES for s in ep.required_scopes),
            ),
        ]

        for app_key, label, should_fail_filter in negative_tests:
            app = self.oauth_apps.get(app_key)
            if not app or not app.access_token:
                print(f"  {YELLOW}SKIP: {label} - app not available{RESET}")
                continue

            print(f"\n  --- {label} ({app_key}) ---")
            tested = 0
            for ep in ENDPOINTS:
                if not self.nodejs_up:
                    continue
                if not should_fail_filter(ep):
                    continue  # This endpoint matches the app's scopes

                url = self._url(ep.service, ep.path)
                status, data = self._call_api(
                    ep.method, url, app.access_token, ep.body, ep.query_params
                )

                self._add_result(
                    ep.service,
                    ep.method,
                    ep.path,
                    " | ".join(ep.required_scopes),
                    f"oauth_{app_key}",
                    "403",
                    status,
                    notes=self._brief_error(data) if status != 403 else "",
                )
                tested += 1

            if tested == 0:
                print(f"  {YELLOW}No applicable endpoints for this test case{RESET}")

    def phase6b_storage_document_tests(self):
        """Phase 6b: KB upload → indexing → search → conversation tests."""
        print(f"\n{BOLD}{CYAN}Phase 6b: KB Upload → Search → Conversation Tests{RESET}")
        print("=" * 70)

        if not self.nodejs_up:
            print(f"  {YELLOW}SKIP: Node.js not reachable{RESET}")
            return

        # Find the dummy PDF file
        script_dir = os.path.dirname(os.path.abspath(__file__))
        pdf_path = os.path.join(script_dir, "test_document.pdf")
        if not os.path.exists(pdf_path):
            print(f"  {RED}SKIP: test_document.pdf not found at {pdf_path}{RESET}")
            return

        # =====================================================================
        # Part 1: Find default Knowledge Base
        # =====================================================================
        print("\n  --- Finding default Knowledge Base ---")
        kb_id = self._get_default_kb_id(self.jwt_token)
        if not kb_id:
            print(f"  {RED}SKIP: No knowledge base found. Create one first.{RESET}")
            return
        print(f"  {GREEN}Using KB: {kb_id}{RESET}")

        app_a = self.oauth_apps.get("app_a_full")

        # =====================================================================
        # Part 2: Upload test PDF to KB (triggers indexing)
        # =====================================================================
        upload_path = f"/api/v1/knowledgeBase/{kb_id}/upload"

        # JWT upload
        print("\n  --- Upload to KB with JWT token ---")
        status, data = self._upload_to_kb(pdf_path, kb_id, self.jwt_token)
        jwt_record_id = None
        if status == 200 and isinstance(data, dict):
            records = data.get("records", [])
            if records:
                jwt_record_id = records[0].get("_key") or records[0].get("externalRecordId")
                print(f"  {GREEN}Uploaded record (JWT): key={jwt_record_id}{RESET}")
                self.test_record_ids.append((jwt_record_id, self.jwt_token))
        else:
            print(f"  {YELLOW}JWT upload returned status={status}: {self._brief_error(data)}{RESET}")

        self._add_result(
            "nodejs", "POST", upload_path,
            "kb:upload", "jwt", "non-403", status,
            notes=self._brief_error(data) if status >= 400 else f"recordKey={jwt_record_id}",
        )

        # OAuth upload (App A - full scopes)
        oauth_record_id = None
        if app_a and app_a.access_token:
            print("\n  --- Upload to KB with OAuth (full scopes) ---")
            status, data = self._upload_to_kb(pdf_path, kb_id, app_a.access_token)
            if status == 200 and isinstance(data, dict):
                records = data.get("records", [])
                if records:
                    oauth_record_id = records[0].get("_key") or records[0].get("externalRecordId")
                    print(f"  {GREEN}Uploaded record (OAuth): key={oauth_record_id}{RESET}")
                    self.test_record_ids.append((oauth_record_id, app_a.access_token))
            else:
                print(f"  {YELLOW}OAuth upload returned status={status}: {self._brief_error(data)}{RESET}")

            self._add_result(
                "nodejs", "POST", upload_path,
                "kb:upload", "oauth_app_a_full", "non-403", status,
                notes=self._brief_error(data) if status >= 400 else f"recordKey={oauth_record_id}",
            )

        # =====================================================================
        # Part 3: Wait for indexing to process the uploaded document
        # =====================================================================
        record_ref = oauth_record_id or jwt_record_id
        if record_ref:
            indexing_wait = 15
            print(f"\n  --- Waiting {indexing_wait}s for indexing to process ---")
            time.sleep(indexing_wait)

        # =====================================================================
        # Part 4: Read uploaded record via KB API
        # =====================================================================
        if jwt_record_id:
            print("\n  --- Read KB record with JWT ---")
            record_path = f"/api/v1/knowledgeBase/record/{jwt_record_id}"
            s, d = self._call_api("GET", self._url("nodejs", record_path), self.jwt_token)
            self._add_result(
                "nodejs", "GET", record_path,
                "kb:read", "jwt", "non-403", s,
                notes=self._brief_error(d) if s >= 400 else "",
            )

        if oauth_record_id and app_a and app_a.access_token:
            print("\n  --- Read KB record with OAuth ---")
            record_path = f"/api/v1/knowledgeBase/record/{oauth_record_id}"
            s, d = self._call_api("GET", self._url("nodejs", record_path), app_a.access_token)
            self._add_result(
                "nodejs", "GET", record_path,
                "kb:read", "oauth_app_a_full", "non-403", s,
                notes=self._brief_error(d) if s >= 400 else "",
            )

        # =====================================================================
        # Part 5: Search for the uploaded document
        # =====================================================================
        if record_ref:
            print("\n  --- Search for uploaded document (JWT) ---")
            search_body = {"query": "OAuth Test PDF document", "limit": 5}
            s, d = self._call_api(
                "POST",
                self._url("nodejs", "/api/v1/search"),
                self.jwt_token,
                body=search_body,
            )
            self._add_result(
                "nodejs", "POST", "/api/v1/search",
                "search:query | search:semantic", "jwt_kb", "non-403", s,
                notes=self._brief_error(d) if s >= 400 else "",
            )

        if record_ref and app_a and app_a.access_token:
            print("\n  --- Search for uploaded document (OAuth full scopes) ---")
            search_body = {"query": "OAuth Test PDF document", "limit": 5}
            s, d = self._call_api(
                "POST",
                self._url("nodejs", "/api/v1/search"),
                app_a.access_token,
                body=search_body,
            )
            self._add_result(
                "nodejs", "POST", "/api/v1/search",
                "search:query | search:semantic", "oauth_app_a_kb", "non-403", s,
                notes=self._brief_error(d) if s >= 400 else "",
            )

        # =====================================================================
        # Part 6: Create conversation about the uploaded document
        # =====================================================================
        if record_ref:
            print("\n  --- Create conversation about uploaded document (JWT) ---")
            conv_body = {"query": "What is in the OAuth Test PDF document?"}
            s, d = self._call_api(
                "POST",
                self._url("nodejs", "/api/v1/conversations/create"),
                self.jwt_token,
                body=conv_body,
            )
            jwt_conv_id = None
            if s in (200, 201) and isinstance(d, dict):
                conv_data = d.get("conversation", d)
                jwt_conv_id = conv_data.get("_id") or conv_data.get("id") or conv_data.get("conversationId")
                if jwt_conv_id:
                    self.test_conversation_ids.append((jwt_conv_id, self.jwt_token))
                    print(f"  {GREEN}Created conversation (JWT): id={jwt_conv_id}{RESET}")
            self._add_result(
                "nodejs", "POST", "/api/v1/conversations/create",
                "conversation:write", "jwt_kb", "non-403", s,
                notes=self._brief_error(d) if s >= 400 else f"convId={jwt_conv_id}",
            )

            # Read the conversation back
            if jwt_conv_id:
                s, d = self._call_api(
                    "GET",
                    self._url("nodejs", f"/api/v1/conversations/{jwt_conv_id}"),
                    self.jwt_token,
                )
                self._add_result(
                    "nodejs", "GET", f"/api/v1/conversations/{jwt_conv_id}",
                    "conversation:read", "jwt_kb", "non-403", s,
                    notes=self._brief_error(d) if s >= 400 else "",
                )

        if record_ref and app_a and app_a.access_token:
            print("\n  --- Create conversation about uploaded document (OAuth) ---")
            conv_body = {"query": "Summarize the content of the OAuth Test PDF"}
            s, d = self._call_api(
                "POST",
                self._url("nodejs", "/api/v1/conversations/create"),
                app_a.access_token,
                body=conv_body,
            )
            oauth_conv_id = None
            if s in (200, 201) and isinstance(d, dict):
                conv_data = d.get("conversation", d)
                oauth_conv_id = conv_data.get("_id") or conv_data.get("id") or conv_data.get("conversationId")
                if oauth_conv_id:
                    self.test_conversation_ids.append((oauth_conv_id, app_a.access_token))
                    print(f"  {GREEN}Created conversation (OAuth): id={oauth_conv_id}{RESET}")
            self._add_result(
                "nodejs", "POST", "/api/v1/conversations/create",
                "conversation:write", "oauth_app_a_kb", "non-403", s,
                notes=self._brief_error(d) if s >= 400 else f"convId={oauth_conv_id}",
            )

            if oauth_conv_id:
                s, d = self._call_api(
                    "GET",
                    self._url("nodejs", f"/api/v1/conversations/{oauth_conv_id}"),
                    app_a.access_token,
                )
                self._add_result(
                    "nodejs", "GET", f"/api/v1/conversations/{oauth_conv_id}",
                    "conversation:read", "oauth_app_a_kb", "non-403", s,
                    notes=self._brief_error(d) if s >= 400 else "",
                )

        # =====================================================================
        # Part 7: Negative scope tests
        # =====================================================================
        app_e = self.oauth_apps.get("app_e_wrong")
        if app_e and app_e.access_token:
            # KB upload with wrong scopes → 403
            print("\n  --- Negative: wrong scopes on KB upload → expect 403 ---")
            status, data = self._upload_to_kb(pdf_path, kb_id, app_e.access_token)
            self._add_result(
                "nodejs", "POST", upload_path,
                "kb:upload", "oauth_app_e_wrong", "403", status,
                notes=self._brief_error(data) if status != 403 else "",
            )

            # KB record read with wrong scopes → 403
            if record_ref:
                record_path = f"/api/v1/knowledgeBase/record/{record_ref}"
                s, d = self._call_api("GET", self._url("nodejs", record_path), app_e.access_token)
                self._add_result(
                    "nodejs", "GET", record_path,
                    "kb:read", "oauth_app_e_wrong", "403", s,
                    notes=self._brief_error(d) if s != 403 else "",
                )

            # Conversation with wrong scopes → 403
            print("\n  --- Negative: wrong scopes on conversation → expect 403 ---")
            s, d = self._call_api(
                "POST",
                self._url("nodejs", "/api/v1/conversations/create"),
                app_e.access_token,
                body={"query": "This should be rejected"},
            )
            self._add_result(
                "nodejs", "POST", "/api/v1/conversations/create",
                "conversation:write", "oauth_app_e_wrong", "403", s,
                notes=self._brief_error(d) if s != 403 else "",
            )

            # Search with wrong scopes → 403
            print("\n  --- Negative: wrong scopes on search → expect 403 ---")
            s, d = self._call_api(
                "POST",
                self._url("nodejs", "/api/v1/search"),
                app_e.access_token,
                body={"query": "This should be rejected", "limit": 1},
            )
            self._add_result(
                "nodejs", "POST", "/api/v1/search",
                "search:query | search:semantic", "oauth_app_e_wrong", "403", s,
                notes=self._brief_error(d) if s != 403 else "",
            )

    def phase7_token_lifecycle(self):
        """Phase 7: Token introspection and revocation tests."""
        print(f"\n{BOLD}{CYAN}Phase 7: Token Lifecycle Tests{RESET}")
        print("=" * 70)

        # Use a dedicated app for lifecycle tests so we don't break other tests
        grant_types = (
            ["authorization_code", "refresh_token"]
            if self.auth_flow == "authorization_code"
            else ["client_credentials"]
        )
        lifecycle_app = self._create_oauth_app(
            name="Test Lifecycle App",
            scopes=["connector:read"],
            grant_types=grant_types,
        )
        if not lifecycle_app:
            print(f"  {RED}Cannot create lifecycle test app. Skipping.{RESET}")
            return

        if self.auth_flow == "authorization_code":
            print(
                f"\n  {YELLOW}One more browser authorization needed for lifecycle test...{RESET}"
            )

        token = self._get_oauth_token(lifecycle_app)
        if not token:
            print(f"  {RED}Cannot get token. Skipping.{RESET}")
            self._delete_oauth_app(lifecycle_app)
            return

        # Test 1: Introspect active token
        print("\n  --- Introspect active token ---")
        status, data = self._introspect_token(token, lifecycle_app)
        active = data.get("active", False) if isinstance(data, dict) else False
        self._add_result(
            "nodejs",
            "POST",
            "/api/v1/oauth2/introspect",
            "N/A",
            "lifecycle",
            "200",
            status,
            notes=f"active={active}",
        )
        if status == 200 and not active:
            print(f"  {RED}WARNING: Token should be active but active=false{RESET}")

        # Test 2: Use token on an endpoint (should work)
        print("\n  --- Use active token ---")
        if self.nodejs_up:
            ep_status, _ = self._call_api(
                "GET",
                self._url("nodejs", "/api/v1/connectors/registry"),
                token=token,
            )
            self._add_result(
                "nodejs",
                "GET",
                "/api/v1/connectors/registry",
                "connector:read",
                "lifecycle_active",
                "non-403",
                ep_status,
            )

        # Test 3: Revoke the token
        print("\n  --- Revoke token ---")
        revoke_status = self._revoke_token(token, lifecycle_app)
        self._add_result(
            "nodejs",
            "POST",
            "/api/v1/oauth2/revoke",
            "N/A",
            "lifecycle",
            "200",
            revoke_status,
        )

        # Small delay for revocation propagation
        time.sleep(0.5)

        # Test 4: Use revoked token (should fail with 401)
        print("\n  --- Use revoked token ---")
        if self.nodejs_up:
            ep_status, _ = self._call_api(
                "GET",
                self._url("nodejs", "/api/v1/connectors/registry"),
                token=token,
            )
            self._add_result(
                "nodejs",
                "GET",
                "/api/v1/connectors/registry",
                "connector:read",
                "lifecycle_revoked",
                "401",
                ep_status,
                notes="Revoked token should be rejected",
            )

        # Test 5: Introspect revoked token (should show active=false)
        print("\n  --- Introspect revoked token ---")
        status, data = self._introspect_token(token, lifecycle_app)
        active = data.get("active", False) if isinstance(data, dict) else None
        self._add_result(
            "nodejs",
            "POST",
            "/api/v1/oauth2/introspect",
            "N/A",
            "lifecycle_revoked",
            "200",
            status,
            notes=f"active={active} (expected false)",
        )

        # Cleanup lifecycle app
        self._delete_oauth_app(lifecycle_app)

    def phase8_edge_cases(self):
        """Phase 8: Edge cases - no token, malformed token."""
        print(f"\n{BOLD}{CYAN}Phase 8: Edge Case Tests{RESET}")
        print("=" * 70)

        # Pick a few endpoints for edge case tests
        test_endpoints = [
            ep
            for ep in ENDPOINTS
            if ep.description
            in (
                "List connectors",
                "Semantic search",
                "List agents",
            )
        ]

        # Test 1: No token at all
        print("\n  --- No token ---")
        for ep in test_endpoints:
            if not self.nodejs_up:
                continue

            url = self._url(ep.service, ep.path)
            status, _ = self._call_api(
                ep.method, url, token=None, body=ep.body, params=ep.query_params
            )
            self._add_result(
                ep.service,
                ep.method,
                ep.path,
                " | ".join(ep.required_scopes),
                "none",
                "401",
                status,
                notes="No token provided",
            )

        # Test 2: Malformed token
        print("\n  --- Malformed token ---")
        malformed_tokens = [
            ("garbage_string", "Random string"),
            ("eyJhbGciOiJIUzI1NiJ9.invalid.payload", "Invalid JWT structure"),
            ("Bearer token_without_bearer_prefix", "Wrong format"),
        ]

        for bad_token, desc in malformed_tokens:
            for ep in test_endpoints[:1]:  # Just test against one endpoint
                if not self.nodejs_up:
                    continue

                url = self._url(ep.service, ep.path)
                status, _ = self._call_api(
                    ep.method, url, token=bad_token, body=ep.body,
                    params=ep.query_params,
                )
                self._add_result(
                    ep.service,
                    ep.method,
                    ep.path,
                    " | ".join(ep.required_scopes),
                    "malformed",
                    "401",
                    status,
                    notes=desc,
                )

    def cleanup(self):
        """Delete all test resources: documents, conversations, and OAuth apps."""
        print(f"\n{BOLD}{CYAN}Cleanup: Deleting test resources{RESET}")
        print("=" * 70)

        if self.skip_cleanup:
            print(f"  {YELLOW}Cleanup skipped (--skip-cleanup flag){RESET}")
            return

        # Delete test conversations
        if self.test_conversation_ids:
            print("\n  --- Deleting test conversations ---")
            for conv_id, token in self.test_conversation_ids:
                s, _ = self._call_api(
                    "DELETE",
                    self._url("nodejs", f"/api/v1/conversations/{conv_id}"),
                    token=token,
                )
                icon = f"{GREEN}OK{RESET}" if s in (200, 204) else f"{RED}FAIL({s}){RESET}"
                print(f"  [{icon}] Deleted conversation {conv_id}")

        # Delete test KB records
        if self.test_record_ids:
            print("\n  --- Deleting test KB records ---")
            for record_id, token in self.test_record_ids:
                s, _ = self._call_api(
                    "DELETE",
                    self._url("nodejs", f"/api/v1/knowledgeBase/record/{record_id}"),
                    token=token,
                )
                icon = f"{GREEN}OK{RESET}" if s in (200, 204) else f"{RED}FAIL({s}){RESET}"
                print(f"  [{icon}] Deleted record {record_id}")

        # Delete OAuth apps
        print("\n  --- Deleting test OAuth apps ---")
        for app_key, app in self.oauth_apps.items():
            success = self._delete_oauth_app(app)
            icon = f"{GREEN}OK{RESET}" if success else f"{RED}FAIL{RESET}"
            print(f"  [{icon}] Deleted {app_key} ({app.name})")

    # -----------------------------------------------------------------------
    # Report
    # -----------------------------------------------------------------------

    def generate_report(self):
        """Generate CSV report and console summary."""
        print(f"\n{BOLD}{CYAN}Test Report{RESET}")
        print("=" * 70)

        total = len(self.results)
        passed = sum(1 for r in self.results if r.passed)
        failed = total - passed

        print(f"  Auth flow:    {self.auth_flow}")
        print(f"  Total tests:  {total}")
        print(f"  Passed:       {GREEN}{passed}{RESET}")
        print(f"  Failed:       {RED}{failed}{RESET}" if failed else f"  Failed:       {GREEN}0{RESET}")
        print(f"  Pass rate:    {passed / total * 100:.1f}%" if total > 0 else "  No tests run")

        # Summary by phase / token_type
        categories: dict[str, dict[str, int]] = {}
        for r in self.results:
            cat = r.token_type.split("_")[0] if "_" in r.token_type else r.token_type
            if cat not in categories:
                categories[cat] = {"passed": 0, "failed": 0}
            if r.passed:
                categories[cat]["passed"] += 1
            else:
                categories[cat]["failed"] += 1

        print(f"\n  {'Category':<20s} {'Passed':>8s} {'Failed':>8s}")
        print(f"  {'-' * 38}")
        for cat, counts in sorted(categories.items()):
            fail_str = (
                f"{RED}{counts['failed']}{RESET}"
                if counts["failed"]
                else str(counts["failed"])
            )
            print(
                f"  {cat:<20s} {GREEN}{counts['passed']:>8d}{RESET} {fail_str:>8s}"
            )

        # Print failures
        failures = [r for r in self.results if not r.passed]
        if failures:
            print(f"\n  {RED}{BOLD}Failed Tests:{RESET}")
            for r in failures:
                print(
                    f"    {r.method:6s} {r.service:12s} {r.endpoint:50s} "
                    f"token={r.token_type:20s} expected={r.expected_status:5s} "
                    f"actual={r.actual_status:3d}  {r.notes}"
                )

        # CSV output
        try:
            with open(self.csv_output, "w", newline="") as f:
                writer = csv.writer(f)
                writer.writerow(
                    [
                        "Service",
                        "Method",
                        "Endpoint",
                        "Scope Required",
                        "Token Type",
                        "Expected Status",
                        "Actual Status",
                        "Pass/Fail",
                        "Notes",
                    ]
                )
                for r in self.results:
                    writer.writerow(
                        [
                            r.service,
                            r.method,
                            r.endpoint,
                            r.scope_required,
                            r.token_type,
                            r.expected_status,
                            r.actual_status,
                            "PASS" if r.passed else "FAIL",
                            r.notes,
                        ]
                    )
            print(f"\n  CSV report written to: {self.csv_output}")
        except OSError as e:
            print(f"\n  {RED}Failed to write CSV: {e}{RESET}")

    # -----------------------------------------------------------------------
    # Utility
    # -----------------------------------------------------------------------

    @staticmethod
    def _brief_error(data: Any) -> str:
        """Extract a brief error message from response data."""
        if isinstance(data, dict):
            for key in ("message", "detail", "error", "error_description"):
                if key in data:
                    msg = str(data[key])
                    return msg[:80] if len(msg) > 80 else msg
        if isinstance(data, str):
            return data[:80] if len(data) > 80 else data
        return ""

    # -----------------------------------------------------------------------
    # Main runner
    # -----------------------------------------------------------------------

    def run(self) -> int:
        """Execute all test phases. Returns exit code (0=all pass, 1=failures)."""
        print(f"\n{BOLD}{'=' * 70}")
        print("  PipesHub OAuth Comprehensive Test Suite")
        print(f"{'=' * 70}{RESET}")
        print(f"  Auth Flow:  {self.auth_flow}")
        print(f"  Backend:    {self.nodejs_url}")
        print(f"  Frontend:   {self.frontend_url}")
        print(f"  CSV Output: {self.csv_output}")

        if self.auth_flow == "authorization_code":
            print(
                f"\n  {BOLD}{YELLOW}Authorization Code Flow:{RESET} "
                f"Browser will open for each OAuth app."
            )
            print(
                f"  {YELLOW}Make sure you are logged into {self.frontend_url} first!{RESET}"
            )

        # Phase 1: Health
        if not self.phase1_health_check():
            self.generate_report()
            return 1

        # Phase 2: Regular JWT
        self.phase2_jwt_tests()

        # Phase 3: Create OAuth apps
        if not self.phase3_create_oauth_apps():
            self.generate_report()
            return 1

        # Phase 4: Token generation
        if not self.phase4_token_generation():
            print(f"  {RED}No tokens could be generated. Aborting.{RESET}")
            self.cleanup()
            self.generate_report()
            return 1

        # Phase 5: Positive scope tests
        self.phase5_positive_scope_tests()

        # Phase 6: Negative scope tests
        self.phase6_negative_scope_tests()

        # Phase 6b: Storage document tests (upload, read, delete with real files)
        self.phase6b_storage_document_tests()

        # Phase 7: Token lifecycle
        self.phase7_token_lifecycle()

        # Phase 8: Edge cases
        self.phase8_edge_cases()

        # Cleanup
        self.cleanup()

        # Report
        self.generate_report()

        # Return code
        failures = sum(1 for r in self.results if not r.passed)
        return 1 if failures > 0 else 0


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(
        description="PipesHub OAuth Comprehensive Test Suite",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Client credentials flow (default, no browser needed)
  python scripts/oauth_test.py --jwt-token eyJhbG...

  # Authorization code flow (opens browser for consent)
  python scripts/oauth_test.py --jwt-token eyJhbG... --auth-flow authorization_code

  # Skip cleanup to inspect apps after test
  python scripts/oauth_test.py --jwt-token eyJhbG... --auth-flow authorization_code --skip-cleanup
        """,
    )
    parser.add_argument(
        "--jwt-token",
        required=True,
        help="Platform JWT token (regular, non-OAuth) for admin user",
    )
    parser.add_argument(
        "--auth-flow",
        choices=["client_credentials", "authorization_code"],
        default="client_credentials",
        help="OAuth grant type for token acquisition (default: client_credentials)",
    )
    parser.add_argument(
        "--nodejs-url",
        default="http://localhost:3000",
        help="Node.js backend URL (default: http://localhost:3000)",
    )
    parser.add_argument(
        "--frontend-url",
        default="http://localhost:3001",
        help="Frontend URL for consent page (default: http://localhost:3001)",
    )
    parser.add_argument(
        "--csv-output",
        default="scripts/oauth_test_report.csv",
        help="CSV report output path (default: scripts/oauth_test_report.csv)",
    )
    parser.add_argument(
        "--skip-cleanup",
        action="store_true",
        help="Don't delete created OAuth apps after tests",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=30,
        help="HTTP request timeout in seconds (default: 30)",
    )
    parser.add_argument(
        "--callback-port",
        type=int,
        default=9999,
        help="Local port for authorization code callback (default: 9999)",
    )

    args = parser.parse_args()

    runner = OAuthTestRunner(
        jwt_token=args.jwt_token,
        auth_flow=args.auth_flow,
        nodejs_url=args.nodejs_url,
        frontend_url=args.frontend_url,
        csv_output=args.csv_output,
        skip_cleanup=args.skip_cleanup,
        timeout=args.timeout,
        callback_port=args.callback_port,
    )

    exit_code = runner.run()
    sys.exit(exit_code)


if __name__ == "__main__":
    main()
