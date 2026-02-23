# OAuth Comprehensive Test Suite

Standalone Python test script that validates OAuth scope enforcement across the PipesHub platform. All requests go through the Node.js API gateway, which proxies to Python services internally.

## What It Tests

### 8 Test Phases

| Phase | Description | Tests |
|-------|-------------|-------|
| 1 | **Health Check** | Verifies the Node.js backend is reachable |
| 2 | **Regular JWT** | JWT tokens pass all endpoints without scope enforcement |
| 3 | **OAuth App Creation** | Creates 5 OAuth apps with different scope combinations |
| 4 | **Token Generation** | Acquires tokens via client_credentials or authorization_code |
| 5 | **Positive Scope Tests** | Correct scopes grant access (non-403) |
| 6 | **Negative Scope Tests** | Wrong scopes are rejected (403) |
| 7 | **Token Lifecycle** | Introspection, revocation, and revoked token rejection |
| 8 | **Edge Cases** | No token (401), malformed tokens (401) |

### OAuth Apps Created

| App | Scopes | Purpose |
|-----|--------|---------|
| A - Full Access | All 34 scopes | Positive tests against every endpoint |
| B - Read Only | 14 read scopes | Positive tests against read endpoints |
| C - Connector Read | `connector:read` only | Positive for connector endpoints, negative for everything else |
| D - Write Only | 11 write scopes | Negative tests against read endpoints |
| E - Wrong Scopes | `crawl:read`, `crawl:write` | Negative tests against all endpoints |

### Endpoint Coverage (23 endpoints)

All tested through the Node.js backend (port 3000):

- **User Management:** userGroups, teams, users/teams, users/teams/created
- **Knowledge Base:** knowledgeBase, records, knowledge-hub/nodes
- **Conversations:** list, create (chat)
- **Connectors:** registry, list, active, configured
- **OAuth Config:** registry, list
- **Search:** semantic search
- **Agents:** list, templates
- **Documents:** get by ID
- **Toolsets:** registry, configured

## Prerequisites

- Node.js backend running (port 3000)
- Python services running (connectors port 8088, query port 8000) — called internally by Node.js
- An **admin JWT token** from the platform
- Python with `requests` library (available in `backend/python/venv`)

## Usage

### Activate the Python virtual environment

```bash
source backend/python/venv/bin/activate
```

### Client Credentials Flow (default, no browser)

```bash
python scripts/oauth_test.py --jwt-token <ADMIN_JWT_TOKEN>
```

Tokens are obtained programmatically via the `client_credentials` grant. No user interaction needed after launch.

### Authorization Code Flow (browser-based consent)

```bash
python scripts/oauth_test.py --jwt-token <ADMIN_JWT_TOKEN> --auth-flow authorization_code
```

The browser will open 6 times (5 apps + 1 lifecycle app). For each:
1. The consent page loads at `http://localhost:3001/oauth/authorize`
2. Review the requested scopes
3. Click **Allow**
4. The tab shows "Authorization Successful" — close it and wait for the next one

**Important:** Log into the frontend at `http://localhost:3001` before running.

## CLI Options

| Flag | Default | Description |
|------|---------|-------------|
| `--jwt-token` | *(required)* | Platform admin JWT token |
| `--auth-flow` | `client_credentials` | `client_credentials` or `authorization_code` |
| `--nodejs-url` | `http://localhost:3000` | Node.js backend URL |
| `--frontend-url` | `http://localhost:3001` | Frontend URL (auth code flow consent page) |
| `--csv-output` | `scripts/oauth_test_report.csv` | CSV report output path |
| `--callback-port` | `9999` | Local port for auth code callback server |
| `--timeout` | `30` | HTTP request timeout in seconds |
| `--skip-cleanup` | off | Keep test OAuth apps after the run |

## Output

### Console

Colored pass/fail output for every test:

```
[PASS] GET    nodejs       /api/v1/connectors/registry     expected=non-403 actual=200
[PASS] GET    nodejs       /api/v1/connectors              expected=403     actual=403
[FAIL] GET    nodejs       /api/v1/agents                  expected=403     actual=200
```

Summary at the end:

```
Test Report
======================================================================
  Auth flow:    client_credentials
  Total tests:  N
  Passed:       N
  Failed:       0
  Pass rate:    100.0%

  Category               Passed   Failed
  --------------------------------------
  jwt                        23        0
  lifecycle                   5        0
  malformed                   3        0
  none                        3        0
  oauth                       N        0
```

### CSV Report

Written to `scripts/oauth_test_report.csv` with columns:

```
Service, Method, Endpoint, Scope Required, Token Type, Expected Status, Actual Status, Pass/Fail, Notes
```

## How OAuth Scope Enforcement Works

- **Regular JWT tokens** (`isOAuth=false`): Skip scope middleware entirely — all endpoints accessible.
- **OAuth tokens** (`tokenType: 'oauth'`): Must have **at least one** of the required scopes (OR logic). Missing scopes return `403 Forbidden`.
- Node.js (`requireScopes` middleware) and Python (`require_scopes` dependency) implement identical logic.
- All API calls go through the Node.js backend, which handles OAuth token resolution and proxies to Python services with the resolved user identity.

## Examples

```bash
# Quick smoke test with client credentials
python scripts/oauth_test.py --jwt-token eyJhbG...

# Full browser-based authorization code test
python scripts/oauth_test.py --jwt-token eyJhbG... --auth-flow authorization_code

# Custom backend URL (e.g., Docker or remote)
python scripts/oauth_test.py \
  --jwt-token eyJhbG... \
  --nodejs-url http://api:3000

# Keep apps for manual inspection after test
python scripts/oauth_test.py --jwt-token eyJhbG... --skip-cleanup
```

## Cleanup

By default, all test OAuth apps are deleted after the run. Use `--skip-cleanup` to keep them for debugging. To manually delete leftover apps, use the admin API:

```bash
# List OAuth apps
curl http://localhost:3000/api/v1/oauth-clients \
  -H "Authorization: Bearer <JWT>"

# Delete a specific app
curl -X DELETE http://localhost:3000/api/v1/oauth-clients/<APP_ID> \
  -H "Authorization: Bearer <JWT>"
```

## Troubleshooting

| Issue | Fix |
|-------|-----|
| `Connection refused` | Ensure the Node.js backend is running on the expected port |
| `401` on all JWT tests | JWT token may be expired — get a fresh one |
| Auth code flow times out | Make sure you're logged into the frontend and click Allow within 120s |
| `Port 9999 already in use` | Use `--callback-port 9998` or kill the process on 9999 |
| `requests` not found | Run `source backend/python/venv/bin/activate` first |
| `500` on proxied endpoints | Ensure Python services (connectors/query) are running |
