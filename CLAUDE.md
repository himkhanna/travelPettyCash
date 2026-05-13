# CLAUDE.md — PDD Petty Cash (Travel Expense Management)

> Operating instructions for Claude (and any AI coding assistant) working on this repository.
> Read this file in full before generating, editing, or reviewing code.

---

## 1. Project context

**Client:** Protocol Department, Government of Dubai (دائرة التشريفات و الضيافة – دبي), also referenced as "Ruler's Court / PDD".

**Product name:** PDD Petty Cash (working title; final Arabic name to be confirmed — current scope doc uses *تطبيق صرفيات السفر*).

**Purpose:** A mobile-first, multi-currency petty cash and per-diem management application for protocol officers travelling on official delegations. Replaces the current paper/Excel reconciliation process with an auditable, digitally signed, multi-source fund-tracking system.

**Primary users (4 roles):**

| Role | Arabic | Responsibilities |
|---|---|---|
| Team Member (منسق) | Trip coordinator | Receive funds, record expenses with receipts, transfer to peers |
| Team Leader | Lead coordinator | All Member abilities + allocate funds to members |
| Admin (مشرف) | Supervisor | Create/close trips, assign funds from sources, view all reports |
| Super Admin (DG view) | Director General | Read-only oversight: balances, expenses per person, per trip |

**Funding model:** Cash originates from **multiple sources** (currently two named: *Zabeel Office / قصر زعبيل* and *Ministry of External Affairs / The Protocol Department*). Every expense, transfer, and allocation must be tagged with the source it is drawn from. Balances are tracked **per source per holder**, never as a single pooled wallet.

**Deployment context:** Sensitive UAE government workflow. Plan for on-prem deployment at sovereign infrastructure (most likely Moro Hub). No third-party SaaS dependencies for storage, auth, or notifications without explicit approval.

---

## 2. Source of truth for requirements

Three documents define scope. If they conflict, resolve in this order:

1. `docs/scope/Scope.docx` — bilingual functional scope (EN + AR). Authoritative on features and reporting.
2. `docs/design/Petty_Cash_Final_Design.pdf` — approved UI mockups (31 screens). Authoritative on layout, copy, and flow.
3. `docs/design/User-Tasks.pdf` — role-to-task matrix and journey diagrams. Authoritative on permissions and notification triggers.

When in doubt, **ask the product owner**. Do not silently invent features or change permissions.

---

## 3. Tech stack (locked)

### Frontend — Flutter
- **Flutter:** stable channel, latest LTS-equivalent. Pin exact version in `pubspec.yaml` and CI.
- **Dart:** as bundled with Flutter SDK.
- **State management:** **Riverpod** (v2+). Do not introduce Bloc, Provider, or GetX in parallel. Pick one and keep it.
- **Routing:** **go_router**.
- **Networking:** **dio** with a typed client layer (no scattered `http.get` calls).
- **Local storage:**
  - `flutter_secure_storage` for tokens, refresh tokens, biometric-gated keys.
  - `drift` (SQLite) for offline expense queue and cached reference data.
  - `shared_preferences` only for trivial UI flags (last selected trip, locale).
- **Localization:** `flutter_localizations` + ARB files. **AR (RTL) and EN (LTR) are first-class from day one.** No hardcoded strings.
- **Forms:** `reactive_forms` or `flutter_form_builder` — pick one in the first sprint.
- **Charts:** `fl_chart` (matches the donut/pie style in the mockups).
- **Image capture:** `image_picker` + `image_cropper` for receipt photos; compress before upload.
- **Notifications:** in-app via WebSocket/polling first. Push (FCM/HMS/APNs) only after sovereignty review.

### Backend — Java
- **Language:** Java 21 LTS.
- **Framework:** Spring Boot 3.x (Web, Security, Data JPA, Validation, Actuator).
- **Build:** Gradle (Kotlin DSL) or Maven — pick one in the first commit. Default: **Gradle KTS**.
- **Database:** PostgreSQL 15+. Migrations via **Flyway**. No Hibernate auto-DDL in any environment.
- **Auth:** OAuth2 / OIDC. Initial implementation: Spring Authorization Server self-hosted, or integration with UAE Pass if PDD mandates it. JWT access tokens (short TTL, 15 min) + opaque refresh tokens.
- **API style:** REST + JSON, versioned at `/api/v1/...`. OpenAPI 3 spec generated via springdoc; spec file checked into repo at `backend/openapi/openapi.yaml`.
- **File storage:** S3-compatible object store (MinIO on-prem). Receipts and signed PDF reports go here; **never** stored in the relational DB as BLOBs.
- **Reports:** server-side generation. Excel via **Apache POI**, PDF via **OpenPDF** or **iText 7 Community** (license-check before use). Digital signature via PKCS#11 / PAdES.
- **Async:** Spring `@Async` for emails and report generation; queue-backed (RabbitMQ or Postgres-LISTEN/NOTIFY) once volume justifies it. Do not introduce Kafka prematurely.
- **Observability:** Micrometer + Prometheus, structured JSON logs via Logback. Correlation IDs on every request.

### Things we explicitly do NOT use unless explicitly approved
- Firebase (data residency).
- Node.js services (single backend language).
- NoSQL primary stores (financial data → relational, with FK constraints).
- AI/LLMs in core workflow. OCR for receipts may be added later as an **opt-in** enhancement and must be deterministic-first (Tesseract or on-prem Document AI) before any LLM is considered.

---

## 4. Repository layout

```
/
├── CLAUDE.md                       ← this file
├── README.md                       ← human-facing setup
├── docs/
│   ├── scope/Scope.docx
│   ├── design/Petty_Cash_Final_Design.pdf
│   ├── design/User-Tasks.pdf
│   ├── architecture/               ← ADRs, diagrams (PlantUML / mermaid)
│   └── api/                        ← exported OpenAPI HTML
├── backend/
│   ├── build.gradle.kts
│   ├── src/main/java/ae/gov/pdd/pettycash/
│   │   ├── PettyCashApplication.java
│   │   ├── config/                 ← Security, CORS, Jackson, OpenAPI
│   │   ├── trip/                   ← Trip aggregate (entity, repo, service, controller, dto)
│   │   ├── expense/                ← Expense aggregate
│   │   ├── fund/                   ← Source, Allocation, Transfer
│   │   ├── user/                   ← User, Role, Permission
│   │   ├── notification/
│   │   ├── chat/
│   │   ├── report/                 ← Excel, PDF, signing
│   │   ├── audit/                  ← AuditLog, hash-chain
│   │   ├── common/                 ← Money, Currency, error model
│   │   └── ApiV1Controller.java    ← (slice per aggregate; see below)
│   ├── src/main/resources/
│   │   ├── application.yml
│   │   ├── application-local.yml
│   │   ├── application-prod.yml
│   │   └── db/migration/           ← Flyway V001__init.sql, …
│   └── src/test/java/...
├── mobile/
│   ├── pubspec.yaml
│   ├── lib/
│   │   ├── main.dart
│   │   ├── app/                    ← App widget, router, theme
│   │   ├── core/                   ← env, dio client, error mapping, money
│   │   ├── l10n/                   ← ARB files + generated
│   │   ├── features/
│   │   │   ├── auth/
│   │   │   ├── trips/
│   │   │   ├── expenses/
│   │   │   ├── funds/              ← allocate, transfer, manage
│   │   │   ├── chat/
│   │   │   ├── notifications/
│   │   │   └── reports/
│   │   └── shared/                 ← widgets, formatters, theme tokens
│   ├── test/
│   └── integration_test/
├── ops/
│   ├── docker-compose.yml          ← Postgres + MinIO + backend for local dev
│   └── helm/                       ← (if k8s on Moro Hub)
└── .github/workflows/              ← or GitLab CI, mirror as needed
```

**Rule:** code is organised **by feature/aggregate**, not by technical layer. No `controllers/`, `services/`, `repositories/` top-level packages.

---

## 5. Domain model (read this before writing code)

These are the core entities. Names are normative — use them exactly.

### `User`
- `id` (UUID), `username`, `displayName`, `displayNameAr`, `email`, `role` (`MEMBER` | `LEADER` | `ADMIN` | `SUPER_ADMIN`), `isActive`, `createdAt`.
- Authentication identity is separate from this domain entity.

### `Source` (funding source)
- `id`, `name` (e.g. "Zabeel Office"), `nameAr`, `isActive`.
- Seeded; not user-creatable from the mobile app (Admin via CMS only).

### `Trip`
- `id`, `name`, `country` (ISO code + display name), `currency` (ISO 4217), `status` (`DRAFT` | `ACTIVE` | `CLOSED`), `createdBy` (admin), `leaderId`, `memberIds[]`, `totalBudget`, `createdAt`, `closedAt`.
- A trip has **one currency**. The mockups use SAR/AED etc. — do not silently support multi-currency within a single trip.

### `Allocation` (Admin → Trip, or Leader → Member, scoped to a source)
- `id`, `tripId`, `fromUserId` (nullable for Admin-level allocations from a Source pool), `toUserId`, `sourceId`, `amount`, `status` (`PENDING` | `ACCEPTED` | `DECLINED`), `note`, `createdAt`, `respondedAt`.
- Status changes are **events**; do not mutate in place without an audit row.

### `Transfer` (peer-to-peer between trip participants)
- Same shape as `Allocation` but `fromUserId` is never null. Modelled as a separate table for clarity and auditability, even though the shape overlaps.

### `Expense`
- `id`, `tripId`, `userId`, `sourceId`, `category` (FK to `ExpenseCategory`), `amount`, `currency` (denormalised from trip), `quantity` (int, default 1), `unitCost` (nullable, computed), `details`, `occurredAt`, `receiptObjectKey` (S3 key, nullable), `createdAt`, `updatedAt`, `deletedAt`.
- **Source assignment can change after creation** (scope doc explicitly calls this out: a tick-box view to re-assign source per expense). Implement source change as an audited event.
- Balance can go negative (scope: *"Check balance (if exceed can go minus)"*). Show a warning in UI, do not block.

### `ExpenseCategory`
- `id`, `code` (`FOOD`, `TRANSPORT`, `HOTEL`, `PHONE`, `ENTERTAINMENT`, `TIPS`, `TRAVEL`, `OTHERS`), `nameEn`, `nameAr`, `iconKey`, `isActive`.
- Seed list from scope and mockups. **New categories addable by Admin** (scope explicitly requires this). Categories are soft-deletable.

### `ChatThread` / `ChatMessage`
- Threads are scoped to a trip. Direct (1:1) and group threads both supported.
- Messages: `id`, `threadId`, `senderId`, `body`, `sentAt`, `deliveredAt`, `readAt`.

### `Notification`
- `id`, `userId`, `type` (enum: `ALLOCATION_RECEIVED`, `TRANSFER_RECEIVED`, `TRANSFER_ACCEPTED`, `TRIP_ASSIGNED`, `TRIP_CLOSED`, `EXPENSE_QUERY`), `payload` (JSONB), `actionable` (bool), `state` (`UNREAD` | `READ` | `ACTED`), `createdAt`.

### `AuditLog`
- Append-only. Every financial mutation writes a row. Include `entityType`, `entityId`, `actorId`, `action`, `before` (JSONB), `after` (JSONB), `at`, `requestId`, `hashPrev`, `hashSelf` (SHA-256 hash chain for tamper-evidence).
- Reports must be signable; the audit chain is the integrity backstop.

---

## 6. Money handling — non-negotiable rules

1. **All monetary amounts are stored as `BIGINT` minor units** (e.g. fils for AED, halalas for SAR). Never as `DOUBLE` or `FLOAT`. In Java, wrap in a `Money` value object backed by `long` + `Currency`. In Dart, wrap in a `Money` class backed by `int` + `currencyCode`.
2. **All arithmetic operations on money go through the `Money` type.** No raw `+`, `-`, `*` on amount fields in business code.
3. **Currency conversion is out of scope.** A trip is single-currency. If a future requirement asks for FX, raise it as a new design item — do not improvise.
4. **Negative balances are permitted** but flagged. Track `balance` per `(userId, tripId, sourceId)` tuple. Recompute from event log on demand; do not trust cached balances for reports.
5. **Rounding:** none, because we use minor units. If display-time conversion to major units is needed, round half-up to currency-defined decimals.

---

## 7. Permissions matrix (enforce on backend; mirror on mobile for UX only)

| Action | Member | Leader | Admin | Super Admin |
|---|:---:|:---:|:---:|:---:|
| View own active trips | ✅ | ✅ | ✅ | ✅ (all) |
| Accept/decline allocation | ✅ | ✅ | — | — |
| Add expense (own) | ✅ | ✅ | — | — |
| Edit own expense (before trip close) | ✅ | ✅ | — | — |
| Reassign expense source | ✅ | ✅ | ✅ | — |
| View own expense list | ✅ | ✅ | ✅ | ✅ |
| View team expense list | — | ✅ (own trip) | ✅ | ✅ |
| Allocate funds to members | — | ✅ (own trip) | — | — |
| Transfer to peer | ✅ | ✅ | — | — |
| Create trip | — | — | ✅ | — |
| Close trip | — | — | ✅ | — |
| Assign funds from Source pool | — | — | ✅ | — |
| Assign additional funds to active trip | — | — | ✅ | — |
| Add new expense category | — | — | ✅ | — |
| Generate reports | ✅ (own) | ✅ (trip) | ✅ (all) | ✅ (read) |
| Digitally sign report | ✅ | ✅ | ✅ | — |
| Chat in trip thread | ✅ | ✅ | ✅ | — |

Enforce at the controller layer with method security (`@PreAuthorize`) **and** at the service layer with a re-check. Never trust the client.

---

## 8. UI / UX rules from the mockups

- **Palette:** dark brown (#5C4A2F / approximate), cream/beige background, gold/olive accents for active balance arcs, red for outflow indicators, green for inflow / success. Match the approved PDF — do not improvise colours.
- **Logo:** UAE Protocol Department wordmark + falcon emblem on login, home, and report headers. Both EN and AR variants present together.
- **Iconography:** custom flat icons for Food (cutlery), Transport (car), Hotel (bed), Phone (handset). Keep the set in `mobile/lib/shared/icons/`.
- **Donut charts** are the primary data visualisation. Balance arc (green) vs spent arc (brown) in the main dashboard. Multi-segment donut for category breakdown.
- **Bottom navigation (5 items):** Dashboard · Expenses · Add (+) · Transfer · Profile/Trips (avatar with notification badge).
- **Right-side slide-out menu** from the profile icon: Logout, All Trips, Manage Funds (Admin/Leader only), Notifications, Chat.
- **Currency display:** code first ("SAR 6,400") to match the mockups. Use `intl` NumberFormat with the trip's currency.
- **RTL:** every screen must work in Arabic. Test with the system locale set to AR. Direction-aware paddings (`EdgeInsetsDirectional`), no hardcoded `left`/`right`.
- **No emojis** in production strings. Government-grade tone.

---

## 9. API conventions

- Base path: `/api/v1`.
- All endpoints require auth except `/auth/login`, `/auth/refresh`, `/health`, `/openapi`.
- Request and response bodies are JSON. Field names: `camelCase`.
- Money in API responses: `{ "amount": 640000, "currency": "SAR" }` (minor units + ISO code). Never a formatted string.
- Dates: ISO 8601 with timezone (`2026-05-13T10:15:30+04:00`).
- Pagination: cursor-based for lists (`?cursor=...&limit=20`). Avoid offset pagination for expense feeds.
- Errors: RFC 7807 Problem Details. Always include `type`, `title`, `status`, `detail`, `instance`, and a stable `code` field for client logic.
- Idempotency: `Idempotency-Key` header required on POST `/expenses`, `/transfers`, `/allocations`. Stored for 24h.

Example endpoints (not exhaustive):

```
POST   /api/v1/auth/login
POST   /api/v1/auth/refresh
GET    /api/v1/me
GET    /api/v1/trips?status=ACTIVE
GET    /api/v1/trips/{id}
POST   /api/v1/trips                          (Admin)
PATCH  /api/v1/trips/{id}/close               (Admin)
GET    /api/v1/trips/{id}/balances
GET    /api/v1/trips/{id}/expenses
POST   /api/v1/trips/{id}/expenses
PATCH  /api/v1/expenses/{id}
PATCH  /api/v1/expenses/{id}/source           (reassign source)
POST   /api/v1/expenses/{id}/receipt          (multipart)
GET    /api/v1/expenses/{id}/receipt          (signed URL)
POST   /api/v1/trips/{id}/allocations         (Admin or Leader)
POST   /api/v1/allocations/{id}/respond       (ACCEPT|DECLINE)
POST   /api/v1/trips/{id}/transfers
GET    /api/v1/notifications
PATCH  /api/v1/notifications/{id}/read
GET    /api/v1/chat/threads
POST   /api/v1/chat/threads/{id}/messages
GET    /api/v1/reports/trip/{id}?format=xlsx|pdf&scope=user|team|finance|dg
POST   /api/v1/reports/{reportId}/sign
GET    /api/v1/categories
POST   /api/v1/categories                     (Admin)
```

---

## 10. Reports (this is half the value of the product — get it right)

Four report types per the scope doc:

1. **User report** — single user's expenses for finance. Group by source, then by category. Include receipt thumbnails. **Excel + PDF**.
2. **Trip full report** — every expense by every member, with photos. Excel.
3. **Finance department letter** — letterhead PDF summarising sources used, totals per source, net balance returned. PDF, **digitally signed by Admin**.
4. **DG report** — per-user spend, per-category spend, current balances. Read-only summary. PDF.

Implementation rules:

- Generation is **server-side**. Mobile triggers and downloads via signed URL.
- Templates live in `backend/src/main/resources/report-templates/`. Use Apache POI's `XSSFWorkbook` with a starter `.xlsx` template per type.
- PDFs are generated, then **signed** in a separate step via PAdES. Signature uses a hardware-backed key (HSM or PKCS#11 token at Moro Hub) — abstract behind a `SignatureService` interface so local dev can use a software keystore.
- Email delivery: SMTP relay configurable per environment. Reports attached as files; do not inline.
- Every report generation writes an `AuditLog` row with the file's SHA-256.

---

## 11. Offline & sync behaviour (mobile)

Field staff in foreign countries with patchy connectivity is the norm.

- **Expense creation must work offline.** Queue to local Drift DB, sync when online. Show a clear "Pending sync" badge.
- **Receipt photos:** stored locally first, uploaded on sync. Compress to ≤ 1 MB before upload.
- **Balance display:** show last-known server balance + a "Pending local changes" delta. Never let the user think a queued expense has been accepted.
- **Conflict resolution:** server wins for balances and trip metadata. Client-created entities (expenses, transfers) keep their local UUID, which the server accepts as the canonical ID — eliminates merge conflicts.
- **Auth:** access token refresh must work in the background; failure boots the user to login but preserves the local queue.

---

## 12. Security baseline

- TLS 1.3 only, externally and between services.
- HSTS on, with preload.
- Mobile pinning: certificate pinning to the production hostname.
- Refresh token rotation on every refresh.
- Biometric unlock for the app (FaceID / TouchID / fingerprint) — gate access to the local DB encryption key.
- Secrets in `application.yml`: **none**. Use env vars + Spring Config + (in prod) HashiCorp Vault or the equivalent on Moro Hub.
- CORS: closed by default; allowlist the admin CMS origin only.
- Rate limiting on auth endpoints (5/min/IP) and on expense creation (60/min/user).
- All PII in logs is redacted by Logback patterns. No request bodies in INFO logs.
- Audit logs are append-only; revoke `UPDATE`/`DELETE` on the audit table at the DB-role level in prod.
- Backups: daily encrypted snapshot to a separate bucket, 90-day retention.

---

## 13. Testing expectations

**Backend:**
- Unit tests for every service method touching money (target: 90%+ branch coverage on `Money`, balance calculation, source-reassignment).
- Slice tests (`@WebMvcTest`, `@DataJpaTest`) for controllers and repositories.
- Integration tests with Testcontainers (real PostgreSQL, real MinIO).
- Contract tests against the OpenAPI spec.
- Ratio target: roughly 70 unit / 20 slice / 10 integration.

**Mobile:**
- Widget tests for every screen with non-trivial state.
- Golden tests for both LTR and RTL on key dashboards.
- Integration test (`integration_test/`) for the critical path: login → select trip → add expense with receipt → see updated balance.
- Mock the backend with a versioned fake; do not call real services from CI.

**CI:** any PR must run lint + tests for both apps. Coverage report posted as a comment.

---

## 14. How Claude should work in this repo

1. **Read before writing.** Before generating code in a feature folder, read the existing files in that folder. Match the patterns; do not introduce parallel styles.
2. **Cite the scope or design source for any new feature.** If a feature is not in `docs/scope/Scope.docx` or the mockups, flag it as out-of-scope and stop.
3. **Prefer deterministic logic.** Validation, parsing, and balance arithmetic are pure Java/Dart. No AI in the hot path.
4. **Domain-first naming.** Use the entity names from §5 verbatim. No abbreviations like `Exp`, `Alloc`, `Tx`.
5. **One responsibility per PR.** Don't bundle a Flyway migration with a UI redesign with a new dependency.
6. **No new dependencies without justification.** Adding a library to `pubspec.yaml` or `build.gradle.kts` requires a one-paragraph note in the PR description: what problem, what alternatives considered.
7. **Write tests in the same PR as the code.** Backend code without a test is incomplete.
8. **Update OpenAPI when you change the API.** The spec file is the contract; mobile reads from it.
9. **Bilingual strings or no strings.** Every user-visible string ships with both EN and AR ARB entries. PRs that add EN-only strings will fail review.
10. **Money objects, always.** A PR that introduces a `double amount` field will be rejected on sight.
11. **Ask, don't assume.** If the mockups and scope conflict, or a permission edge case isn't covered, write the question in the PR and stop. Do not pick a side silently.

### When generating code, default to:

- **Java:** records for DTOs, immutable entities where feasible, constructor injection, package-private visibility for internal classes, `Optional` only as return type.
- **Dart:** `freezed` for DTOs and state classes, `sealed` classes for unions (Riverpod async values, action results), `const` constructors everywhere possible.

### When reviewing code, flag:

- Any `double` or `BigDecimal` on a monetary field.
- Any English string in a `Text(...)` widget without an ARB key.
- Any controller method without `@PreAuthorize`.
- Any service method that mutates two aggregates without a transaction boundary.
- Any new dependency without a justification note.
- Any catch-all `try/catch (Exception)` that swallows the error.

---

## 15. Out of scope (don't build this unless asked)

- FX / multi-currency within a single trip.
- OCR of receipt photos (deferred enhancement).
- Real-time presence / typing indicators in chat.
- Push notifications via Firebase (sovereignty review pending).
- A web app for end-users. The CMS for Admin and Super Admin **is** in scope but is a separate Flutter Web build sharing the same backend.
- Integration with Odoo / SAP / Oracle finance — under discussion but not contracted.

---

## 16. Open questions (track here until resolved)

- [ ] UAE Pass integration: required for v1, or post-launch? **Owner:** PM.
- [ ] Production identity provider: Spring Authorization Server self-hosted vs UAE Pass vs PDD AD. **Owner:** PDD IT.
- [ ] Signature key custody: PDD HSM, Moro Hub HSM, or software keystore for pilot? **Owner:** Security.
- [ ] Final Arabic product name. **Owner:** PDD.
- [ ] CMS UI: separate Flutter Web app vs a slimmed-down view in the same mobile codebase. **Owner:** Eng + PM.
- [ ] Push notification channel for iOS (APNs direct vs a UAE-hosted relay). **Owner:** Eng.
- [ ] Default currency rules per country (auto-select SAR for KSA trip, etc.) — confirm with PDD operations.

---

*Last updated: 2026-05-13. Update this file in the same PR as any architectural change.*
