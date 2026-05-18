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

## Receipts (Phase 3 slice 2)

Receipts live in MinIO (S3-compatible). Bucket name defaults to
`pettycash-receipts`; override with `MINIO_BUCKET`. The bucket is created
on application startup if missing.

Endpoints (all require `Authorization: Bearer <jwt>`):

- `POST /api/v1/expenses/{id}/receipt` — multipart upload, single field
  `file`. Validates `image/jpeg` or `image/png`, max 8 MB. Stores at key
  `receipts/{tripId}/{expenseId}/{uuid}.{ext}` and sets
  `expense.receiptObjectKey`. Owner of the expense, the trip leader, or
  any ADMIN may upload.
- `GET /api/v1/expenses/{id}/receipt` — returns `{ "url", "expiresAt" }`
  with a 5-minute presigned GET URL. Same auth rules as upload.
- `POST /api/v1/receipts/scan` — multipart OCR endpoint. Mocked in v1
  via `MockReceiptScanner` (deterministic 4-bucket response keyed by
  `sha256(image) mod 4`). See `docs/architecture/ADR-005-ocr.md`. Disable
  by setting `pettycash.ocr.enabled=false`.

## Idempotency

`Idempotency-Key` header is **required** on:

- `POST /api/v1/trips/{id}/expenses`
- `POST /api/v1/trips/{id}/allocations`
- `POST /api/v1/trips/{id}/transfers`

Records are stored in `idempotency_record` and replayed for 24h. Reusing
a key with a different request body yields `409 IDEMPOTENCY_KEY_CONFLICT`;
omitting the header yields `400 IDEMPOTENCY_KEY_REQUIRED`.

## Explicit deferrals — DO NOT add without scope sign-off

- **Reports** (CLAUDE.md §10): the `GET /api/v1/reports/trip/{id}` endpoint returns `501 Not Implemented` with `{ "code": "REPORT_DEFERRED" }`. Apache POI / OpenPDF / PAdES signing pipeline is not scaffolded.
- **Real OIDC** (CLAUDE.md §16): no live UAE Pass, PDD SSO, or UAE Pass JWKS yet. Mock JWT (HS256) only.
- **Real OCR** (CLAUDE.md §15, ADR-005): `POST /receipts/scan` returns canned data. Tesseract integration scheduled post-demo.
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
├── idempotency  IdempotencyRecord, interceptor, caching filter
├── notification  Notification + controller
├── receipt       ReceiptScanController + (mock) ReceiptScanner
├── report        ReportController (501 stub)
├── storage       StorageService + MinioStorageService (AWS SDK v2)
├── trip          Trip, controller + service
└── user          User, MeController, Role
```
