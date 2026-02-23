#!/usr/bin/env python3
"""Quick diagnostic: test GET /api/v1/teams with JWT vs OAuth token."""
import argparse
import base64
import json
import requests

BASE = "http://localhost:3000"

def call(method, path, token=None, body=None, params=None):
    headers = {"Content-Type": "application/json", "Accept": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    resp = requests.request(method, f"{BASE}{path}", headers=headers, json=body, params=params, timeout=30)
    try:
        data = resp.json()
    except Exception:
        data = resp.text
    return resp.status_code, data

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--jwt-token", required=True)
    args = parser.parse_args()
    jwt = args.jwt_token

    print("=" * 70)
    print("Test 1: GET /api/v1/teams with JWT token")
    print("=" * 70)
    status, data = call("GET", "/api/v1/teams", token=jwt)
    print(f"  Status: {status}")
    print(f"  Response: {json.dumps(data, indent=2) if isinstance(data, dict) else data}")

    print("\n" + "=" * 70)
    print("Test 2: Create OAuth app with team:read scope")
    print("=" * 70)
    app_body = {
        "name": "Teams Diagnostic App",
        "allowedGrantTypes": ["client_credentials"],
        "allowedScopes": ["team:read"],
        "redirectUris": ["http://localhost:9999/callback"],
        "accessTokenLifetime": 3600,
        "refreshTokenLifetime": 86400,
    }
    status, data = call("POST", "/api/v1/oauth-clients", token=jwt, body=app_body)
    print(f"  Status: {status}")
    if status != 201 or not isinstance(data, dict):
        print(f"  Failed to create app: {data}")
        return
    print(f"  Response keys: {list(data.keys()) if isinstance(data, dict) else 'N/A'}")
    # Handle nested response (e.g. {app: {...}})
    app = data.get("app", data)
    print(f"  App keys: {list(app.keys()) if isinstance(app, dict) else 'N/A'}")
    client_id = app.get("clientId") or app.get("client_id")
    client_secret = app.get("clientSecret") or app.get("client_secret")
    app_id = app.get("_id") or app.get("id") or app.get("appId")
    print(f"  App ID: {app_id}")
    print(f"  Client ID: {client_id}")

    print("\n" + "=" * 70)
    print("Test 3: Get OAuth token via client_credentials")
    print("=" * 70)
    token_body = {
        "grant_type": "client_credentials",
        "client_id": client_id,
        "client_secret": client_secret,
        "scope": "team:read",
    }
    status, data = call("POST", "/api/v1/oauth2/token", body=token_body)
    print(f"  Status: {status}")
    if status != 200 or not isinstance(data, dict):
        print(f"  Failed to get token: {data}")
        call("DELETE", f"/api/v1/oauth-clients/{app_id}", token=jwt)
        return
    oauth_token = data.get("access_token")
    print(f"  Token acquired (scope: {data.get('scope')})")

    print("\n" + "=" * 70)
    print("Test 4: Decode OAuth token payload")
    print("=" * 70)
    try:
        parts = oauth_token.split(".")
        payload_b64 = parts[1] + "=" * (4 - len(parts[1]) % 4)
        payload = json.loads(base64.b64decode(payload_b64))
        print(f"  userId:    {payload.get('userId')}")
        print(f"  orgId:     {payload.get('orgId')}")
        print(f"  client_id: {payload.get('client_id')}")
        print(f"  tokenType: {payload.get('tokenType')}")
        print(f"  scope:     {payload.get('scope')}")
        is_cc = payload.get("userId") == payload.get("client_id")
        print(f"  isClientCredentials (userId==client_id): {is_cc}")
    except Exception as e:
        print(f"  Failed to decode: {e}")

    print("\n" + "=" * 70)
    print("Test 5: GET /api/v1/teams with OAuth token")
    print("=" * 70)
    status, data = call("GET", "/api/v1/teams", token=oauth_token)
    print(f"  Status: {status}")
    print(f"  Response: {json.dumps(data, indent=2) if isinstance(data, dict) else data}")

    print("\n" + "=" * 70)
    print("Test 6: Call Python connectors directly with OAuth token + x-oauth-user-id header")
    print("=" * 70)
    # Manually set x-oauth-user-id to the JWT user's MongoDB ObjectId
    jwt_parts = jwt.split(".")
    jwt_payload_b64 = jwt_parts[1] + "=" * (4 - len(jwt_parts[1]) % 4)
    jwt_payload = json.loads(base64.b64decode(jwt_payload_b64))
    jwt_user_id = jwt_payload.get("userId")
    print(f"  JWT userId (MongoDB ObjectId): {jwt_user_id}")

    headers = {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "Authorization": f"Bearer {oauth_token}",
        "x-oauth-user-id": jwt_user_id,
    }
    resp = requests.get("http://localhost:8088/api/v1/entity/team/list", headers=headers, timeout=30)
    try:
        rdata = resp.json()
    except Exception:
        rdata = resp.text
    print(f"  Status: {resp.status_code}")
    print(f"  Response: {json.dumps(rdata, indent=2) if isinstance(rdata, dict) else rdata}")

    print("\n" + "=" * 70)
    print("Cleanup: Delete OAuth app")
    print("=" * 70)
    status, _ = call("DELETE", f"/api/v1/oauth-clients/{app_id}", token=jwt)
    print(f"  Status: {status}")

if __name__ == "__main__":
    main()
