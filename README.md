# PDD Petty Cash

Mobile-first, multi-currency petty cash and per-diem management for the
Protocol Department, Government of Dubai.

> **Phase 0 scaffold.** The mobile app boots, the role-switcher lands you in
> a phone-frame on web (or full-screen on a device), and the Demo Controls
> menu lets you simulate offline mode, latency, and failure injection. The
> real screens land in **Milestone A**.
>
> Build order is **UI-first with mocked APIs** for the customer demo —
> backend (Spring Boot, Postgres, MinIO) is deferred. See `CLAUDE.md` for the
> full project contract.

## Repository layout

```
.
├── CLAUDE.md                       # Authoritative project contract
├── screen-inventory.md             # Per-screen wiring (31 mockup screens)
├── README.md                       # You are here
├── mobile/                         # Flutter app (mobile + Flutter Web CMS)
│   ├── pubspec.yaml
│   ├── analysis_options.yaml
│   ├── l10n.yaml
│   ├── lib/
│   │   ├── main.dart
│   │   ├── app/                    # MaterialApp shell, theme, router
│   │   ├── core/
│   │   │   ├── money/              # Money value type (CLAUDE.md §6)
│   │   │   ├── fake/               # FakeConfig + dev menu
│   │   │   ├── api/                # Generated OpenAPI types (Milestone A)
│   │   │   ├── storage/            # Drift offline queue (Milestone A)
│   │   │   └── error/
│   │   ├── l10n/                   # intl_en.arb, intl_ar.arb
│   │   ├── features/
│   │   │   ├── auth/
│   │   │   ├── trips/
│   │   │   ├── expenses/
│   │   │   ├── funds/
│   │   │   ├── chat/
│   │   │   ├── notifications/
│   │   │   ├── reports/
│   │   │   ├── landing/            # Demo role-switcher (Phase 0)
│   │   │   └── cms/                # Admin Console (Web)
│   │   └── shared/                 # PhoneViewport, formatters, icons
│   ├── assets/demo/                # Seed JSON for the fake repos
│   ├── test/                       # Unit + widget + golden tests
│   └── integration_test/
├── docs/
│   ├── api/openapi.yaml            # API contract (used by both fake & real)
│   ├── architecture/               # ADRs
│   ├── feedback/                   # Demo notes from PDD reviews
│   ├── scope/                      # Scope.docx
│   └── design/                     # Mockups + User-Tasks PDFs
├── ops/                            # docker-compose for backend phase
└── .github/workflows/ci.yml
```

## Prerequisites

You need:

- **Flutter SDK** 3.22+ on the `stable` channel
  ([install guide](https://docs.flutter.dev/get-started/install/windows)).
- **Dart 3.4+** (bundled with Flutter).
- **Git** 2.40+.
- **Node 20+** (only required for the OpenAPI Redocly lint job in CI).

Once Flutter is on `PATH`, sanity-check:

```powershell
flutter --version
flutter doctor
```

`flutter doctor` will tell you which target SDKs (Android, iOS, Web, Desktop)
are missing. The Phase 0 demo only needs **Web** — Chrome is sufficient.

## First run

```powershell
cd mobile
flutter pub get
flutter run -d chrome
```

Chrome opens at `http://localhost:<port>/`. You should see the dark-brown
landing page with role-switcher cards.

### Demo controls

Inside the app, tap the **tune icon** in the top app bar to open the Demo
Controls bottom sheet. You can:

- Adjust artificial network **latency** (0–2000 ms) — exercise loading states.
- Set a **failure injection rate** for write calls — exercise error states.
- Toggle **offline mode** — writes queue locally, sync resumes when you
  toggle back on.
- Switch the demo **role** without returning to the landing page.

## Running tests

```powershell
cd mobile
flutter test
```

Coverage report lands in `mobile/coverage/lcov.info` when run with
`flutter test --coverage`.

## Phase plan at a glance

| Phase | Status | Deliverable |
|---|---|---|
| **Phase 0** Foundations | ✅ Scaffolded | Flutter app boots, theme + l10n + Money + FakeConfig, OpenAPI spec, CI |
| **Phase 1 — Milestone A** | ⏳ Next | Member happy path with offline-queue demo |
| **Phase 1 — Milestone B** | ⏳ | Filter, edit, transfer, chat, notifications |
| **Phase 1 — Milestone C** | ⏳ | Leader views — allocate, manage funds, trip charts |
| **Phase 1 — Milestone D** | ⏳ | Admin / Super Admin CMS shell |
| **Phase 2** Customer demo | ⏳ | Vercel preview, demo script, feedback capture |
| **Phase 3** Backend | ⏳ | Spring Boot, Postgres, MinIO; one feature at a time |

## Conventions

Read `CLAUDE.md` end-to-end before contributing. Hard rules:

1. **Money is `int` minor units.** Never `double`, never `BigDecimal`. Use
   `lib/core/money/money.dart`.
2. **Bilingual or no string.** Every user-visible string must exist in both
   `intl_en.arb` and `intl_ar.arb`.
3. **Repository interfaces are the seam.** UI talks to abstract repositories.
   Fake and real implementations live side-by-side; a single override in
   `main.dart` chooses which one is wired in.
4. **OpenAPI is the contract.** When you change an endpoint, update
   `docs/api/openapi.yaml` in the same PR.
5. **One responsibility per PR.** No mixing a Flyway migration with a UI
   redesign with a new dependency.

## License

Copyright (c) 2026 Protocol Department, Government of Dubai. All rights reserved.
