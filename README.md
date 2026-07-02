# PingFederate + Spring Boot 4.1 Demo

A self-contained demo of three common PingFederate OAuth2/OIDC patterns with a Spring Boot 4.1 backend. There is no frontend — everything is tested with `curl`, or Postman.

---

## What this demonstrates

| Flow | Pattern | Endpoint | How to trigger |
|------|---------|----------|----------------|
| 1 | OIDC Authorization Code login | `GET /profile` | Browser |
| 2 | Opaque Bearer token introspection | `GET /api/secure` | `curl -H "Authorization: Bearer <token>"` |
| 3 | Client credentials (M2M) | `GET /api/m2m` | `curl` — app fetches its own token internally |

```
Browser / curl
      │
      ▼
Spring Boot App ──► PingFederate  (/as/authorization.oauth2 · /as/token.oauth2 · /as/introspect.oauth2)
```

---

## Prerequisites

- Docker Desktop or Rancher Desktop (with Compose)
- Java 25 + Maven (for running tests and building locally)
- `jq` for pretty-printing responses
- Python, in case trying to use a mocked downstream service.

Install `jq`:
```bash
brew install jq          # macOS
winget install jqlang.jq  # Windows
sudo apt-get install jq  # Ubuntu/Debian
```

---

## Quickstart

### Auto-configured Pingfederate on a docker container (quick start)

Runs `configure.sh` automatically via the `autoconfig` Docker Compose profile,
provisioning the **complete** setup (scopes, access token manager, user store,
login adapter, token mappings, OIDC policy, and all three OAuth2 clients) with
no admin-console steps:

```bash
# 1. Start PingFederate + auto-configure it
docker compose --profile autoconfig up --build
```

Wait for:
```
pingfederate-init exited with code 0
```

```bash
# 2. Run the app locally (in a second terminal)
export $(grep -v '^#' .env | xargs) # Exporting the environment variables
mvn spring-boot:run
```

Wait for: `Started PingFedDemoApplication`

---

Verify either way:
```bash
curl http://localhost:8080/ | jq .
curl http://localhost:8080/actuator/health | jq .
```
---

## Demo script

### Flow 1 — OIDC login (browser)

Open in the browser:
```
http://localhost:8080/profile
```

Spring Security redirects you to PingFederate's login page. After authenticating, PingFed returns an auth code, the app exchanges it for tokens, and `/profile` returns the decoded ID token claims.
There might be browser warnings that the page requested is unsafe, this is due to no SSL certificates for local PingFed (it has self signed certificates). One can safely proceed ahead, ignoring the warnings.

Default PingFederate user: `user1` / `Password1!`

Expected response:
```json
{
  "status": "ok",
  "flow": "oidc-authorization-code",
  "data": {
    "sub": "user1",
    "name": null,
    "email": null,
    "issuer": "https://localhost:9031",
    "audience": ["demo-oidc-client"]
  }
}
```

> `name` and `email` are `null` — the demo uses a Simple Username/Password
> Credential Validator, which only stores `username`. The `sub` claim
> (`user1`) is the identity. Populating `name`/`email` would require a real
> user store (LDAP/JDBC) and extra claims in the OIDC policy.

---

### Flow 2 — Bearer token introspection

```bash
# 1. Get an access token from PingFederate
TOKEN=$(curl -sk -X POST https://localhost:9031/as/token.oauth2 \
  -d "grant_type=client_credentials" \
  -d "client_id=demo-m2m-client" \
  -d "client_secret=M2mSecret123!" \
  -d "scope=api.read" | jq -r .access_token)

# 2. Call the protected endpoint — Spring introspects the token with PF
curl -s -H "Authorization: Bearer $TOKEN" \
  http://localhost:8080/api/secure | jq .
```

Expected response:
```json
{
  "status": "ok",
  "flow": "opaque-token-introspection",
  "data": {
    "sub": "demo-m2m-client",
    "client_id": "demo-m2m-client",
    "scope": ["api.read"],
    "active": true
  }
}
```

Try an invalid token to see the 401:
```bash
curl -s -H "Authorization: Bearer bad-token" \
  http://localhost:8080/api/secure
```

---

### Flow 3 — Client credentials / M2M

```bash
curl -s http://localhost:8080/api/m2m | jq .
```

The app fetches its own token from PingFederate and uses it to call a downstream service.  The token is cached until expiry.

Expected response:
```json
{
  "status": "ok",
  "flow": "client-credentials",
  "data": {
    "token_preview": "4bxa7wOQzi234yptxjyK...",
    "token_type": "Bearer",
    "scope": ["api.read"],
    "issued_at": "2026-06-25T08:18:44.285127Z",
    "expires_at": "2026-06-25T10:18:44.285127Z",
    "downstream_call": {
      "source": "http://localhost:8081/api/data",
      "result": "Demo data payload",
      "records": 42,
      "note": "mocked — downstream unavailable"
    }
  }
}
```

> **`"note": "mocked — downstream unavailable"` is expected.** The demo has no
> real downstream service on `http://localhost:8081`, so after fetching the token
> (the part this flow demonstrates), the app's call to the downstream API is
> refused and `DownstreamService` returns a **mock payload** — and logs a
> `WARN ... Downstream service unreachable ... returning mock response`. That
> WARN line is normal. The flow is healthy as long as you get HTTP 200 with a
> real `token_preview` / `expires_at`.

**To see the *live* (non-mock) downstream path**, run a mock responder in a
separate terminal, then call
`/api/m2m` again:
```bash
python3 mock-downstream.py                       # listens on http://localhost:8081
curl -s http://localhost:8080/api/m2m | jq .data.downstream_call
```
You'll get `"result": "LIVE downstream data"` with `"received_bearer_token": true`
(proving the app forwarded its M2M token). Stop it with `Ctrl-C` to return to the
mock fallback. Alternatively, set `DOWNSTREAM_URL` to any API that answers on
`/api/data` with JSON.

> The token is an **opaque reference token** (~28 chars), not a JWT — the Access
> Token Manager is configured as *Internally Managed Reference Tokens*. That's
> why Flow 2 validates it by calling PF's introspection endpoint rather than
> verifying a signature locally.

---

### Bonus — PingFederate admin console

Open `https://localhost:9999/pingfederate/app` (accept the self-signed cert warning).
Login: `administrator` / `Admin1234!` (the account is always `administrator`, not `admin`).

Show the audience (PF 13.x navigation):
- **Applications → OAuth → Clients** — the three clients created automatically
- **Applications → OAuth → Access Token Management** — the `demoATM` reference-token manager
- **System → OAuth Settings → Scope Management** — the registered scopes

---

## API endpoints — full reference

| Method | Endpoint | Auth | Flow | Notes |
|--------|----------|------|------|-------|
| `GET` | `/` | none | — | Public landing JSON |
| `GET` | `/profile` | OIDC login (browser) | 1 | Redirects to PF login, then returns ID-token claims |
| `GET` | `/api/secure` | Bearer (opaque) | 2 | App introspects the token with PF |
| `GET` | `/api/echo` | Bearer (opaque) | 2 | Same Bearer auth; echoes the authenticated principal |
| `GET` | `/api/m2m` | none&nbsp;* | 3 | App fetches its own token internally |
| `GET` | `/actuator/health` | none | — | Spring Actuator health probe |

\* `/api/m2m` is intentionally public so you can trigger the Machine-2-Machine token flow with a plain `GET`.

- **App base URL:** `http://localhost:8080` — plain HTTP, no cert issues.
- **PingFederate runtime:** `https://localhost:9031` — self-signed TLS, so use `-k` (curl) / disable SSL verification (Postman) when calling it directly for a token.

---


## Testing with Postman

In Postman, **Import →**
select [`postman_collection.json`](postman_collection.json). It contains all the
requests below, grouped by flow, with `Get M2M Token` wired to save the token into
a `{{token}}` collection variable that the Bearer requests reuse.

**One-time setup:** PingFederate uses a self-signed cert, so turn off TLS checks for
the token call — **Settings → General → "SSL certificate verification" → OFF**
(or add `localhost` under Settings → Certificates). The app itself (`:8080`) is plain
HTTP and needs nothing.

After importing, run **Flow 2 → `1. Get M2M Token`** first, then the `/api/secure`
and `/api/echo` requests use the saved token automatically. The rest below is the
manual setup if you'd rather build the requests yourself.

**Public endpoints** — just `GET` them, no auth tab needed:
- `GET http://localhost:8080/`
- `GET http://localhost:8080/actuator/health`
- `GET http://localhost:8080/api/m2m`

**Flow 2 — Bearer-protected (`/api/secure`, `/api/echo`):** let Postman fetch the
token for you.
1. Open the request → **Authorization** tab → Type **OAuth 2.0**.
2. **Configure New Token:**
   - Grant Type: **Client Credentials**
   - Access Token URL: `https://localhost:9031/as/token.oauth2`
   - Client ID: `demo-m2m-client`  ·  Client Secret: `M2mSecret123!`
   - Scope: `api.read`
   - Client Authentication: **Send as Basic Auth header**
3. **Get New Token → Use Token**, then **Send**. (Or grab a token once via the curl
   above and paste it under Authorization → **Bearer Token**.)

**Flow 1 — OIDC login (`/profile`):** this is an interactive Authorization-Code flow.
Easiest in a browser (`http://localhost:8080/profile`, log in as `user1 / Password1!`).
If you want it in Postman, use Authorization → OAuth 2.0 with:
- Grant Type: **Authorization Code** (enable PKCE)
- Auth URL: `https://localhost:9031/as/authorization.oauth2`
- Access Token URL: `https://localhost:9031/as/token.oauth2`
- Client ID: `demo-oidc-client`  ·  Secret: `OidcSecret123!`
- Callback URL: `http://localhost:8080/login/oauth2/code/pingfed-oidc`  ·  Scope: `openid profile email`

---

## License**
The dev license lives at `pingfederate/PingFederate-13.0-Development.lic` — the
volume mount in `docker-compose.yml` picks it up automatically on next start. To
swap it, replace that file (or update the mount path in `docker-compose.yml`).
