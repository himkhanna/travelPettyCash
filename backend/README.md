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

## Cursor pagination

`GET /api/v1/trips/{tripId}/expenses` is cursor-paginated per CLAUDE.md §9.

- Order: `(occurredAt DESC, id DESC)`. Newest first; `id` breaks ties.
- Default `limit=20`, hard cap 100. Values outside `[1, 100]` are clamped server-side.
- Response body shape: `{ items: [...], nextCursor: "<opaque base64>" | null }`. When `nextCursor` is null, the page is the last.
- To fetch the next page, send the previous response's `nextCursor` verbatim as the `?cursor=...` query param. The cursor is opaque — clients must not parse it.
- Malformed cursors yield `400 INVALID_CURSOR`.
- The composite index `idx_expense_trip_occurredat_id` (Flyway V005) backs the tuple-comparison predicate `WHERE (occurred_at, id) < (?, ?)`.

## Idempotency

`Idempotency-Key` header is **required** on:

- `POST /api/v1/trips/{id}/expenses`
- `POST /api/v1/trips/{id}/allocations`
- `POST /api/v1/trips/{id}/transfers`

Records are stored in `idempotency_record` and replayed for 24h. Reusing
a key with a different request body yields `409 IDEMPOTENCY_KEY_CONFLICT`;
omitting the header yields `400 IDEMPOTENCY_KEY_REQUIRED`.

## Long-poll notifications & chat

Per CLAUDE.md §3 ("in-app via WebSocket/polling first") the realtime transport
is long-poll, not WebSockets. Two endpoints:

- `GET /api/v1/notifications/poll?since=<iso8601>&timeoutSeconds=25`
- `GET /api/v1/chat/threads/{threadId}/poll?since=<iso8601>&timeoutSeconds=25`

Behaviour:

- Returns immediately if items exist with `createdAt > since` (for the caller's user) or `sentAt > since` (for the thread).
- Otherwise hangs as a `DeferredResult` for up to `timeoutSeconds` (default 25, max 30) and resolves when a new item is published, or with an empty `items` array on timeout.
- Response: `{ "items": [...], "serverNow": "..." }`. Clients should send `serverNow` back as the next `since` to avoid client clock skew.
- Chat poll enforces thread membership (403 for non-participants).

Fan-out is in-memory (`NotificationPublisher`, `ChatPublisher`). **Single-instance only.** Horizontal scale will require Redis Pub/Sub or Postgres LISTEN/NOTIFY — flagged in the publisher class docs, out of scope for v1.

Publishers are invoked from:

- `FundService.createAllocations` → recipient (`ALLOCATION_RECEIVED`).
- `FundService.respond`           → original sender (`TRANSFER_ACCEPTED` / `ALLOCATION_RECEIVED`).
- `FundService.createTransfer`    → recipient (`TRANSFER_RECEIVED`).
- `ChatController.send`           → all thread subscribers.

All four wire their publish into the surrounding TX via `TransactionSynchronization.afterCommit`, so a rolled-back write never leaks to long-pollers.

## Reports

`GET /api/v1/reports/trip/{tripId}?type=<TYPE>&format=<FORMAT>&userId=<uuid?>`

- `type`: `USER` | `TRIP` | `FINANCE` | `DG`. `format`: `XLSX` | `PDF`.
- Format gating per CLAUDE.md §10: TRIP → XLSX only; FINANCE/DG → PDF only; USER supports both.
- Permissions (§7) re-checked at the service layer: USER → own (LEADER may fetch a team member), TRIP → LEADER (own trip) or ADMIN, FINANCE → ADMIN, DG → SUPER_ADMIN.
- Generated bytes are uploaded to MinIO at `reports/{tripId}/{type}-{timestamp}.{ext}` and a `ReportRecord` row is written (Flyway V006). An `AuditLog` row with the SHA-256 of the file is appended.
- Response: `{ reportId, url, expiresAt, sha256 }`. `url` is a 5-minute presigned GET URL.

Report content uses bilingual EN + AR headers; category names come from `expense_category.name_en` / `name_ar`. The FINANCE letter is watermarked **"DRAFT — UNSIGNED"** until PAdES signing is unblocked.

Generation uses **Apache POI** (`org.apache.poi:poi-ooxml:5.3.0`) for XLSX and **OpenPDF** (`com.github.librepdf:openpdf:2.0.3`, LGPL) for PDF. OpenPDF was chosen over iText 7 for licence clarity in the gov-on-prem context — see ADR-003. POI's default heap footprint is fine for the row volumes expected; no `JAVA_OPTS` tuning is required for v1.

`POST /api/v1/reports/{reportId}/sign` continues to return `501 SIGNING_DEFERRED` per ADR-003.

## Explicit deferrals — DO NOT add without scope sign-off

- **Report signing** (CLAUDE.md §10, ADR-003): generation is implemented, PAdES signing is not. Endpoint returns `501 SIGNING_DEFERRED`.
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
