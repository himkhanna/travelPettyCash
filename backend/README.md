# PDD Petty Cash — Backend

Spring Boot 3 / Java 21 / PostgreSQL service for the Protocol Department petty-cash app.
See `../CLAUDE.md` for the locked architecture, domain model, and security baseline.

## Local development

```bash
# 1. Start Postgres
docker compose -f ../ops/docker-compose.yml up -d

# 2. Run the app (profile = local; seeds the six demo users from
#    mobile/assets/demo/users.json with password "demo1234")
gradle bootRun --args='--spring.profiles.active=local'

# 3. OpenAPI / Swagger
open http://localhost:8080/swagger-ui.html
```

### Smoke test the auth endpoint

```bash
# Login as Fatima (LEADER)
curl -s -X POST http://localhost:8080/api/v1/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"fatima","password":"demo1234"}' | jq

# Call /me with the issued access token
ACCESS=$(curl -s -X POST http://localhost:8080/api/v1/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"fatima","password":"demo1234"}' | jq -r .tokens.accessToken)
curl -s http://localhost:8080/api/v1/me -H "Authorization: Bearer $ACCESS" | jq
```

## Tests

```bash
gradle test
```

Unit tests run unconditionally. The `AuthControllerIT` integration test uses
Testcontainers to spin up a real Postgres; if Docker isn't reachable from
docker-java (e.g. Docker Desktop hardened socket mode), those tests are
**skipped** rather than failing — CI Linux runners always run them.

If you want to run the IT locally on Windows + Docker Desktop:
1. Settings → General → "Expose daemon on tcp://localhost:2375 without TLS".
2. If still blocked, disable "Use containerd for pulling and storing images"
   and "Enhanced Container Isolation" then restart Docker Desktop.

## Configuration

All secrets resolve from env vars (`application.yml`). Local defaults are
sane; **set these in every real environment**:

| Variable | Purpose |
|----------|---------|
| `PDD_DB_URL`, `PDD_DB_USER`, `PDD_DB_PASSWORD` | Postgres connection |
| `PDD_JWT_SECRET` | HS256 signing secret (≥32 bytes) |
| `PDD_CORS_ORIGINS` | CSV allowlist for the CMS web origin |
| `PDD_PORT` | HTTP port (default 8080) |
