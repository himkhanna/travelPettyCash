# PDD Delegation Expenses

*صرفيات الوفود الرسمية*

Mobile-first, multi-currency travel funds allocation and expense submission for
the Protocol Department, Government of Dubai.

> **Demo-week build (2026-05-25).** End-to-end stack is live: Spring Boot
> backend on Postgres + MinIO, Flutter mobile app (`/app`), Flutter Web
> admin portal (`/portal`), and a wired chat / notifications / reports
> pipeline. See `CLAUDE.md` for the full project contract and §17 for the
> current sprint status.

## What's running

- **Mobile (`/app`)** — Member + Leader flows: trips list with Active /
  Upcoming / Archived sections, trip dashboard, expense list, **Add
  Expense** with required invoice photo and multi-line items + Tesseract
  OCR auto-fill, peer transfers, allocation accept/decline, **inbox** (in
  trip + global), **chat** (global from Profile menu), notifications that
  deep-link into the right surface.
- **Admin portal (`/portal`)** — Dashboard with KPI strip and
  "Needs-attention" alerts, **Trips** screen with filters, **Missions**
  list + detail at `/cms/missions/:id`, **Expenses** screen with
  missing-receipt filter chip, **Expense detail** at
  `/cms/expenses/:id` (invoice viewer, breakdown, conversation thread,
  @-mention), **Reports** module (pie-chart dashboard +
  scheduled deliveries + Excel/PDF export), **Audit** feed, **Users**,
  **Settings**, top-bar global search (⌘K) and notification bell with
  per-type routing (REPORT_READY, EXPENSE_QUERY, CHAT_MESSAGE, …).
- **Backend** — REST under `/api/v1`, JWT (15-min access + 30-day
  refresh), RFC-7807 problem details on every error, idempotency keys on
  every write, MinIO presigned URLs for receipts, server-rendered PDF
  (OpenPDF) + XLSX (Apache POI) reports, scheduled report cron
  (`@Scheduled` 5-min poll), Tesseract OCR module (tess4j). Flyway
  migrations through `V010__notifications_chat_and_report_types.sql`.

## Repository layout

```
.
├── CLAUDE.md                       # Authoritative project contract (read first)
├── README.md                       # You are here
├── docs/
│   ├── api/openapi.yaml            # API contract
│   ├── architecture/
│   ├── scope/                      # Scope.docx
│   └── design/                     # Mockups + User-Tasks PDFs
├── backend/                        # Spring Boot 3.4 / Java 21
│   ├── build.gradle.kts
│   └── src/main/java/ae/gov/pdd/pettycash/
│       ├── PettyCashApplication.java
│       ├── auth/                   # JWT, login, refresh
│       ├── trip/                   # Trips + mission link
│       ├── mission/                # Missions (nestable via parent_mission_id)
│       ├── fund/                   # Sources, allocations, transfers
│       ├── expense/                # Expenses, comments, source reassignment
│       ├── chat/                   # Threads + messages (CHAT_MESSAGE fan-out)
│       ├── notification/           # Inbox + fan-out (REPORT_READY etc.)
│       ├── report/                 # PDF/XLSX gen + schedule/                 # Cron runner + delivery scheduler
│       ├── ocr/                    # Tesseract module (receipt auto-fill)
│       ├── search/                 # Global search endpoint
│       ├── audit/                  # /api/v1/audit feed
│       └── common/                 # Money, error envelope, …
│   └── src/main/resources/db/migration/   # Flyway V001..V009
├── mobile/                         # Flutter (mobile + Flutter Web CMS)
│   ├── pubspec.yaml
│   ├── lib/
│   │   ├── main.dart
│   │   ├── app/                    # Theme, router, MaterialApp shell
│   │   ├── core/
│   │   │   ├── money/              # Money value type (CLAUDE.md §6)
│   │   │   ├── api/                # dio client, error mapping, parsers
│   │   │   ├── fake/               # DemoStore + FakeConfig dev menu
│   │   │   └── sync/               # Offline queue + sync coordinator
│   │   ├── l10n/                   # intl_en.arb, intl_ar.arb
│   │   ├── features/
│   │   │   ├── auth/               # Login, role guard, signout
│   │   │   ├── trips/              # List, dashboard, /m/all-trips
│   │   │   ├── expenses/           # Add (multi-line), detail, comments
│   │   │   ├── funds/              # Allocate, transfer, manage
│   │   │   ├── chat/               # Global chat (Profile menu)
│   │   │   ├── notifications/      # Inbox + bell deep-linking
│   │   │   ├── reports/            # Per-trip report dialog
│   │   │   ├── ocr/                # Receipt auto-fill suggestion
│   │   │   ├── search/             # ⌘K global search hits
│   │   │   ├── landing/            # Role-switcher (demo)
│   │   │   └── cms/                # /portal admin screens
│   │   └── shared/                 # Primitives, theme tokens, icons
│   ├── assets/demo/                # Seed JSON for the fake repos
│   ├── test/                       # Unit + widget + golden tests
│   └── integration_test/
├── scripts/                        # PowerShell dev helpers
│   ├── dev-up.ps1                  # Brings up docker-compose + backend + mobile
│   ├── dev-down.ps1                # Tears it back down
│   └── smoke.ps1                   # 23-endpoint backend smoke
├── ops/docker-compose.yml          # Postgres + MinIO + (optionally) backend
└── .github/workflows/ci.yml
```

## Prerequisites

- **Java 21** (Temurin or equivalent) — backend.
- **Gradle 8+** — backend builds via `gradle bootRun` (no wrapper checked
  in; install Gradle or use IntelliJ's bundled one).
- **PostgreSQL 15** + **MinIO** — brought up via `ops/docker-compose.yml`.
- **Flutter SDK 3.22+** on `stable` channel — frontend
  ([install](https://docs.flutter.dev/get-started/install/windows)).
- **Tesseract OCR 5.x** on `PATH` if you want receipt auto-fill (set
  `TESSDATA_PREFIX` to your `tessdata` dir; the backend's `ocr` module
  resolves `tesseract` via `JNA`).

Sanity-check:

```powershell
java --version       # 21+
gradle --version     # 8+
flutter --version    # 3.22+
flutter doctor
```

## Running locally

The easiest path uses the PowerShell helpers under `scripts/`:

```powershell
.\scripts\dev-up.ps1      # docker-compose up postgres + minio, gradle bootRun, flutter run
.\scripts\smoke.ps1       # hits 23 backend endpoints against the test fixture
.\scripts\dev-down.ps1    # tears everything down
```

Manual equivalents:

```powershell
# Postgres + MinIO
docker compose -f ops/docker-compose.yml up -d postgres minio

# Backend (Flyway V001..V010 runs on boot; seeders auto-populate demo data)
cd backend
gradle bootRun

# Mobile / portal (web-server mode keeps Chrome out of the way)
cd ../mobile
flutter pub get
flutter run -d web-server --web-port 5173 --web-hostname 127.0.0.1
```

- **Mobile app**: <http://127.0.0.1:5173/app>
- **Admin portal**: <http://127.0.0.1:5173/portal>
- **Backend API**: <http://localhost:8080/api/v1>
- **MinIO console**: <http://localhost:9001> (creds in
  `ops/docker-compose.yml`)

All four demo accounts (`khalid` / admin, `fatima` / leader,
`layla` + `ahmed` / members) use password `demo1234`.

### Demo controls

Inside the mobile app, tap the **tune icon** in the top app bar to open
the Demo Controls bottom sheet:

- Adjust artificial network **latency** (0–2000 ms) — exercise loading states.
- Set a **failure injection rate** for write calls — exercise error states.
- Toggle **offline mode** — every non-Add-Expense mobile route swaps to
  the offline screen; Add Expense submits queue as drafts and sync when
  you toggle back online. Real OS-level connectivity loss triggers the
  same gate on native iOS/Android (via `connectivity_plus`).
- Switch the demo **role** without returning to the landing page.

### Testing on a real iPhone over Wi-Fi

1. Both devices on the same Wi-Fi. Find the laptop LAN IP via
   `ipconfig` (e.g. `192.168.1.46`).
2. Allow the LAN-bound origin in `application-local.yml` if your IP
   differs from the committed `192.168.1.46` — `pdd.cors.allowed-origins`
   already lists both `5173` and `8080` for that host. Restart backend
   if you change this.
3. Allow Windows Firewall inbound for ports `5173` and `8080` (Private
   profile is enough on a home network).
4. Run Flutter bound to all interfaces with the LAN IP baked into the
   API base:
   ```powershell
   flutter run -d web-server --web-port 5173 --web-hostname 0.0.0.0 `
     --dart-define=PDD_API_BASE=http://192.168.1.46:8080
   ```
5. On iPhone Safari, open `http://192.168.1.46:5173/app` and sign in.
   Share → Add to Home Screen for a fullscreen launcher icon.

Notes:

- **JWT storage is `localStorage` on web**, not `flutter_secure_storage`.
  Browsers gate `window.crypto.subtle` (which secure-storage uses) to
  HTTPS/`localhost` origins, so a plain-HTTP LAN URL would otherwise
  crash the bundle on init. Production deployments serve over HTTPS so
  `SecureTokenStore` kicks back in.
- Native iOS install (TestFlight) needs a Mac + Apple Developer
  account; on Windows alone the PWA-via-Safari path is the only option.
- If admin-elevation for the firewall rule is locked down on your
  laptop, **ngrok** (`ngrok http 8080`) gives the iPhone an HTTPS
  tunnel to the backend without any host change — pass the ngrok URL
  via `--dart-define=PDD_API_BASE=https://abc.ngrok-free.app`.

## Demo-day cold-start

1. `.\scripts\dev-up.ps1` — Postgres, MinIO, backend, mobile.
2. Hard-refresh both browser tabs (Ctrl+Shift+R) after pulling the latest
   bundle — Flutter Web caches aggressively. If the page still looks
   stale after a hard refresh, open Chrome DevTools → Application tab →
   Storage → **Clear site data**.
3. Demo path (see `CLAUDE.md` §17 for the up-to-date version):
   - Admin (`khalid`) creates a trip under an existing mission → assigns
     funds from a source.
   - Leader (`fatima`) accepts → allocates to member.
   - Member (`layla` / `ahmed`) accepts → opens **Add Expense**, attaches
     an invoice photo (required), adds one or more line items, optionally
     lets OCR auto-fill the first line.
   - Admin opens the expense from `/cms/expenses/:id` → 💬 → @-mentions
     the member → posts comment.
   - Member opens **Inbox** → taps the EXPENSE_QUERY notification → lands
     on expense detail → replies in the thread.
   - Admin opens **/cms/reports**, picks a dimension + scope, downloads
     Excel/PDF, or schedules a daily delivery.

## Running tests

```powershell
# Backend
cd backend
gradle test                    # JUnit 5, slice + integration via Testcontainers

# Mobile
cd ../mobile
flutter test                   # unit + widget + golden
```

Mobile coverage report lands in `mobile/coverage/lcov.info` when run with
`flutter test --coverage`.

## Conventions

Read `CLAUDE.md` end-to-end before contributing. Hard rules:

1. **Money is `BIGINT` minor units.** Never `double`, never
   `BigDecimal`. Use `ae.gov.pdd.pettycash.common.Money` on the backend
   and `lib/core/money/money.dart` on the mobile side.
2. **Bilingual or no string.** Every user-visible string must exist in
   both `intl_en.arb` and `intl_ar.arb`.
3. **Repository interfaces are the seam.** UI talks to abstract
   repositories. `api` and `fake` implementations live side-by-side; the
   `backendModeProvider` chooses which one is wired in.
4. **OpenAPI is the contract.** When you change an endpoint, update
   `docs/api/openapi.yaml` in the same PR.
5. **One responsibility per PR.** No mixing a Flyway migration with a UI
   redesign with a new dependency.

## License

Copyright (c) 2026 Protocol Department, Government of Dubai. All rights reserved.
