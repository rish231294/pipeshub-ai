#!/usr/bin/env python3
"""
PipesHub OAuth2 Token Generator

Uses Authorization Code flow to obtain access & refresh tokens.
Starts a local callback server, opens the browser for user consent,
captures the authorization code, and exchanges it for tokens.

Usage:
    python oauth_token_generator.py
"""

import hashlib
import http.server
import json
import os
import secrets
import sys
import threading
import urllib.parse
import webbrowser
from base64 import urlsafe_b64encode

import requests

# ─── Configuration ───────────────────────────────────────────────────────────

CLIENT_ID = "cb39f670-2b6b-4b35-90d4-e516f12e1e91"
CLIENT_SECRET = "7a6bc56605843d40c62d00d8b9e02b915719e6f3c476e2a7888aa590a761ed64"
REDIRECT_URI = "http://localhost:8888/callback"
BASE_URL = os.getenv("PIPESHUB_BASE_URL", "http://localhost:3000")

# All available scopes
ALL_SCOPES = " ".join([
    # Organization
    "org:read", "org:write", "org:admin",
    # Users
    "user:read", "user:write", "user:invite", "user:delete",
    # User Groups
    "usergroup:read", "usergroup:write",
    # Teams
    "team:read", "team:write",
    # Knowledge Base
    "kb:read", "kb:write", "kb:delete", "kb:upload",
    # Search
    "search:query", "search:semantic",
    # Conversations
    "conversation:read", "conversation:write", "conversation:chat",
    # Agents
    "agent:read", "agent:write", "agent:execute",
    # Connectors
    "connector:read", "connector:write", "connector:sync", "connector:delete",
    # Configuration
    "config:read", "config:write",
    # Documents
    "document:read", "document:write", "document:delete",
    # Crawling
    "crawl:read", "crawl:write",
    # OpenID / Identity
    "openid", "profile", "email", "offline_access",
])

# ─── PKCE Helper ─────────────────────────────────────────────────────────────

def generate_pkce():
    """Generate PKCE code_verifier and code_challenge (S256)."""
    code_verifier = secrets.token_urlsafe(64)[:128]
    digest = hashlib.sha256(code_verifier.encode("ascii")).digest()
    code_challenge = urlsafe_b64encode(digest).rstrip(b"=").decode("ascii")
    return code_verifier, code_challenge


# ─── Callback Server ─────────────────────────────────────────────────────────

class CallbackHandler(http.server.BaseHTTPRequestHandler):
    """HTTP handler that captures the OAuth callback with the authorization code."""

    authorization_code = None
    state_received = None
    error = None

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path != "/callback":
            self.send_response(404)
            self.end_headers()
            return

        params = urllib.parse.parse_qs(parsed.query)

        if "error" in params:
            CallbackHandler.error = params["error"][0]
            error_desc = params.get("error_description", ["Unknown error"])[0]
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.end_headers()
            self.wfile.write(
                f"<html><body><h1>Authorization Failed</h1>"
                f"<p>Error: {CallbackHandler.error}</p>"
                f"<p>{error_desc}</p>"
                f"<p>You can close this window.</p></body></html>".encode()
            )
            return

        CallbackHandler.authorization_code = params.get("code", [None])[0]
        CallbackHandler.state_received = params.get("state", [None])[0]

        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.end_headers()
        self.wfile.write(
            b"<html><body><h1>Authorization Successful!</h1>"
            b"<p>You can close this window and return to the terminal.</p>"
            b"</body></html>"
        )

    def log_message(self, fmt, *args):
        # Print callback debug info
        print(f"  [callback] {fmt % args}")


def start_callback_server():
    """Start the local HTTP server and return it."""
    server = http.server.HTTPServer(("localhost", 8888), CallbackHandler)
    thread = threading.Thread(target=server.handle_request, daemon=True)
    thread.start()
    return server, thread


# ─── Token Exchange ──────────────────────────────────────────────────────────

def exchange_code_for_token(code, code_verifier):
    """Exchange authorization code for access + refresh tokens."""
    token_url = f"{BASE_URL}/api/v1/oauth2/token"
    data = {
        "grant_type": "authorization_code",
        "code": code,
        "redirect_uri": REDIRECT_URI,
        "client_id": CLIENT_ID,
        "client_secret": CLIENT_SECRET,
        "code_verifier": code_verifier,
    }

    print(f"\n--- Exchanging code for token ---")
    print(f"POST {token_url}")
    resp = requests.post(token_url, data=data)
    return resp


def refresh_access_token(refresh_token):
    """Use a refresh token to get a new access token."""
    token_url = f"{BASE_URL}/api/v1/oauth2/token"
    data = {
        "grant_type": "refresh_token",
        "refresh_token": refresh_token,
        "client_id": CLIENT_ID,
        "client_secret": CLIENT_SECRET,
    }

    print(f"\n--- Refreshing token ---")
    print(f"POST {token_url}")
    resp = requests.post(token_url, data=data)
    return resp


def client_credentials_token():
    """Get a token via client_credentials grant (no user context)."""
    token_url = f"{BASE_URL}/api/v1/oauth2/token"
    data = {
        "grant_type": "client_credentials",
        "client_id": CLIENT_ID,
        "client_secret": CLIENT_SECRET,
        "scope": ALL_SCOPES,
    }

    print(f"\n--- Client Credentials Token ---")
    print(f"POST {token_url}")
    resp = requests.post(token_url, data=data)
    return resp


# ─── cURL Commands ───────────────────────────────────────────────────────────

def print_curl_commands(code_verifier, code_challenge):
    """Print all useful cURL commands."""
    state = "random_state_value"
    scope_encoded = urllib.parse.quote(ALL_SCOPES)

    print("\n" + "=" * 80)
    print("ALL cURL COMMANDS FOR PIPESHUB OAUTH2")
    print("=" * 80)

    # 1. Authorization URL (open in browser)
    auth_url = (
        f"{BASE_URL}/api/v1/oauth2/authorize"
        f"?response_type=code"
        f"&client_id={CLIENT_ID}"
        f"&redirect_uri={urllib.parse.quote(REDIRECT_URI)}"
        f"&scope={scope_encoded}"
        f"&state={state}"
        f"&code_challenge={code_challenge}"
        f"&code_challenge_method=S256"
    )
    print(f"""
1. AUTHORIZE (open in browser):
   {auth_url}
""")

    # 2. Exchange authorization code for token
    print(f"""2. EXCHANGE CODE FOR TOKEN:
   curl -X POST '{BASE_URL}/api/v1/oauth2/token' \\
     -H 'Content-Type: application/x-www-form-urlencoded' \\
     -d 'grant_type=authorization_code' \\
     -d 'code=<AUTHORIZATION_CODE>' \\
     -d 'redirect_uri={REDIRECT_URI}' \\
     -d 'client_id={CLIENT_ID}' \\
     -d 'client_secret={CLIENT_SECRET}' \\
     -d 'code_verifier={code_verifier}'
""")

    # 3. Exchange code with Basic Auth
    import base64
    basic_auth = base64.b64encode(f"{CLIENT_ID}:{CLIENT_SECRET}".encode()).decode()
    print(f"""3. EXCHANGE CODE FOR TOKEN (Basic Auth):
   curl -X POST '{BASE_URL}/api/v1/oauth2/token' \\
     -H 'Content-Type: application/x-www-form-urlencoded' \\
     -H 'Authorization: Basic {basic_auth}' \\
     -d 'grant_type=authorization_code' \\
     -d 'code=<AUTHORIZATION_CODE>' \\
     -d 'redirect_uri={REDIRECT_URI}' \\
     -d 'code_verifier={code_verifier}'
""")

    # 4. Client Credentials
    print(f"""4. CLIENT CREDENTIALS TOKEN (server-to-server, no user context):
   curl -X POST '{BASE_URL}/api/v1/oauth2/token' \\
     -H 'Content-Type: application/x-www-form-urlencoded' \\
     -d 'grant_type=client_credentials' \\
     -d 'client_id={CLIENT_ID}' \\
     -d 'client_secret={CLIENT_SECRET}' \\
     -d 'scope={ALL_SCOPES}'
""")

    # 5. Refresh Token
    print(f"""5. REFRESH TOKEN:
   curl -X POST '{BASE_URL}/api/v1/oauth2/token' \\
     -H 'Content-Type: application/x-www-form-urlencoded' \\
     -d 'grant_type=refresh_token' \\
     -d 'refresh_token=<REFRESH_TOKEN>' \\
     -d 'client_id={CLIENT_ID}' \\
     -d 'client_secret={CLIENT_SECRET}'
""")

    # 6. Introspect Token
    print(f"""6. INTROSPECT TOKEN:
   curl -X POST '{BASE_URL}/api/v1/oauth2/introspect' \\
     -H 'Content-Type: application/x-www-form-urlencoded' \\
     -d 'token=<ACCESS_TOKEN>' \\
     -d 'client_id={CLIENT_ID}' \\
     -d 'client_secret={CLIENT_SECRET}'
""")

    # 7. Revoke Token
    print(f"""7. REVOKE TOKEN:
   curl -X POST '{BASE_URL}/api/v1/oauth2/revoke' \\
     -H 'Content-Type: application/x-www-form-urlencoded' \\
     -d 'token=<ACCESS_TOKEN>' \\
     -d 'client_id={CLIENT_ID}' \\
     -d 'client_secret={CLIENT_SECRET}'
""")

    # 8. UserInfo
    print(f"""8. USERINFO (requires 'openid' scope):
   curl -X GET '{BASE_URL}/api/v1/oauth2/userinfo' \\
     -H 'Authorization: Bearer <ACCESS_TOKEN>'
""")

    # 9. Use access token with any API
    print(f"""9. EXAMPLE: USE TOKEN WITH ANY API ENDPOINT:
   curl -X GET '{BASE_URL}/api/v1/<endpoint>' \\
     -H 'Authorization: Bearer <ACCESS_TOKEN>' \\
     -H 'Content-Type: application/json'
""")

    print("=" * 80)


# ─── Main Flow ───────────────────────────────────────────────────────────────

def main():
    print("=" * 60)
    print("  PipesHub OAuth2 Token Generator")
    print("=" * 60)
    print(f"\nClient ID:    {CLIENT_ID}")
    print(f"Redirect URI: {REDIRECT_URI}")
    print(f"Base URL:     {BASE_URL}")
    print(f"Scopes:       (all scopes)")

    # Generate PKCE
    code_verifier, code_challenge = generate_pkce()
    state = secrets.token_urlsafe(32)

    # Print all curl commands first
    print_curl_commands(code_verifier, code_challenge)

    # Ask user what they want to do
    print("\nChoose a flow:")
    print("  1. Authorization Code flow (opens browser, requires user login)")
    print("  2. Client Credentials flow (server-to-server, no user)")
    print("  3. Just show cURL commands (already printed above)")
    choice = input("\nEnter choice [1/2/3]: ").strip()

    if choice == "3":
        print("\nDone! Use the cURL commands above.")
        return

    if choice == "2":
        resp = client_credentials_token()
        print(f"\nStatus: {resp.status_code}")
        try:
            token_data = resp.json()
            print(json.dumps(token_data, indent=2))
            if "access_token" in token_data:
                print(f"\n--- ACCESS TOKEN ---")
                print(token_data["access_token"])
        except Exception:
            print(resp.text)
        return

    # --- Authorization Code Flow ---
    print("\nStarting callback server on http://localhost:8888 ...")
    server, thread = start_callback_server()

    # Build authorization URL
    auth_params = {
        "response_type": "code",
        "client_id": CLIENT_ID,
        "redirect_uri": REDIRECT_URI,
        "scope": ALL_SCOPES,
        "state": state,
        "code_challenge": code_challenge,
        "code_challenge_method": "S256",
    }
    auth_url = f"{BASE_URL}/api/v1/oauth2/authorize?{urllib.parse.urlencode(auth_params)}"

    print(f"\nOpening browser for authorization...")
    print(f"If the browser doesn't open, visit:\n{auth_url}\n")
    webbrowser.open(auth_url)

    # Wait for callback
    print("Waiting for authorization callback...")
    thread.join(timeout=300)  # 5 min timeout
    server.server_close()

    if CallbackHandler.error:
        print(f"\nAuthorization error: {CallbackHandler.error}")
        sys.exit(1)

    if not CallbackHandler.authorization_code:
        print("\nTimeout or no authorization code received.")
        sys.exit(1)

    code = CallbackHandler.authorization_code
    print(f"\nAuthorization code received: {code[:20]}...")

    # Verify state
    print(f"State sent:     {state}")
    print(f"State received: {CallbackHandler.state_received}")
    if CallbackHandler.state_received != state:
        print("WARNING: State mismatch (possible encoding issue in dev).")
        print("Continuing anyway for local development...")

    # Exchange code for tokens
    resp = exchange_code_for_token(code, code_verifier)
    print(f"Status: {resp.status_code}")

    try:
        token_data = resp.json()
        print(json.dumps(token_data, indent=2))

        if "access_token" in token_data:
            print(f"\n{'=' * 60}")
            print("ACCESS TOKEN:")
            print(f"{'=' * 60}")
            print(token_data["access_token"])

        if "refresh_token" in token_data:
            print(f"\n{'=' * 60}")
            print("REFRESH TOKEN:")
            print(f"{'=' * 60}")
            print(token_data["refresh_token"])

            # Ask if user wants to test refresh
            test_refresh = input("\nTest refresh token? [y/N]: ").strip().lower()
            if test_refresh == "y":
                resp2 = refresh_access_token(token_data["refresh_token"])
                print(f"Status: {resp2.status_code}")
                print(json.dumps(resp2.json(), indent=2))

    except Exception:
        print(resp.text)


if __name__ == "__main__":
    main()
