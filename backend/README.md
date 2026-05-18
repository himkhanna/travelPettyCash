# PDD Petty Cash — Backend

Spring Boot 3.3 / Java 21 backend for the PDD Petty Cash app.
See repo-root `CLAUDE.md` for full project context and conventions.

## Local development

### 1. Start dependencies

```bash
docker compose -f ops/docker-compose.yml up -d
```

This runs:
- Postgres 15 on `localhost:5432` (`pettycash` / `pettycash` / db `pettycash`)
- MinIO on `localhost:9000` (S3 API) and `localhost:9001` (console), root creds `minio_admin` / `minio_admin12`

### 2. Run the backend

```bash
cd backend
./gradlew bootRun         # or: gradle bootRun  if no wrapper
```

Flyway will auto-migrate `V001__init.sql` + `V002__seed.sql` on first start.

### 3. Useful endpoints

- Public health: <http://localhost:8080/health>
- Actuator: <http://localhost:8080/actuator/health>, `/actuator/prometheus`
- OpenAPI JSON: <http://localhost:8080/v3/api-docs>
- Swagger UI: <http://localhost:8080/swagger-ui.html>

### 4. Mock auth (Phase 3 only)

Auth is a stand-in until UAE Pass / PDD SSO contracts are wired (see CLAUDE.md §16).
Two mock providers are accepted; the `code` body field is currently ignored.

```bash
# UAE Pass — returns the seeded LEADER user
curl -s -X POST http://localhost:8080/api/v1/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"provider":"UAE_PASS","code":"anything"}'

# PDD SSO — returns the seeded ADMIN user
curl -s -X POST http://localhost:8080/api/v1/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"provider":"PDD_SSO","code":"anything"}'
```

Each call returns a JSON `{ accessToken, refreshToken, user }`. Send `Authorization: Bearer <accessToken>` on subsequent calls.

Seeded users (see `db/migration/V002__seed.sql`):

| Username       | Role        | Notes                                |
|----------------|-------------|--------------------------------------|
| `member1`      | MEMBER      | Khalid Al Mansoori                   |
| `leader1`      | LEADER      | Ahmed Al Suwaidi (leader of seed trip) |
| `admin1`       | ADMIN       | Fatima Al Hashimi                    |
| `superadmin1`  | SUPER_ADMIN | Mohammed Al Falasi (DG)              |
| `uaepass-test` | LEADER      | Returned by mock `UAE_PASS` provider |
| `pddsso-test`  | ADMIN       | Returned by mock `PDD_SSO` provider  |

## Tests

```bash
./gradlew test
```

Tests use:
- **Pure JUnit** for `Money` (unit, no Spring)
- **Testcontainers Postgres** for `@SpringBootTest` (Flyway uses `pgcrypto` + JSONB, so H2 is unsuitable). Docker must be available on the host.

## Explicit deferrals — DO NOT add without scope sign-off

- **Reports** (CLAUDE.md §10): the `GET /api/v1/reports/trip/{id}` endpoint returns `501 Not Implemented` with `{ "code": "REPORT_DEFERRED" }`. Apache POI / OpenPDF / PAdES signing pipeline is not scaffolded.
- **Real OIDC** (CLAUDE.md §16): no live UAE Pass, PDD SSO, or UAE Pass JWKS yet. Mock JWT (HS256) only.
- **Receipt upload** (multipart + signed URLs): controller stub planned; `AwsSdk` is on the classpath but a `StorageService` is not yet wired.
- **Push notifications** (CLAUDE.md §15): out of scope. In-app notifications via polling only.
- **Real-time chat presence**: out of scope.

## Project layout (feature-package)

```
ae.gov.pdd.pettycash
├── auth          AuthController, JwtService, CurrentUser, DTOs
├── audit         AuditLog + AuditService (SHA-256 hash chain)
├── chat          Threads, Messages
├── common        Money (value object), ApiException, RFC-7807 handler, MoneyDto
├── config        SecurityConfig, OpenApiConfig, JwtProperties, StorageProperties
├── expense       Expense, ExpenseCategory, controller + service
├── fund          Source, Allocation, Transfer, controller + service
├── notification  Notification + controller
├── report        ReportController (501 stub)
├── trip          Trip, controller + service
└── user          User, MeController, Role
```
