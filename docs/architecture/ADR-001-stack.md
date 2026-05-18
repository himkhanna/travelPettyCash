# ADR-001 — Locked tech stack

**Status:** Accepted (carried over from `CLAUDE.md §3`).
**Date:** 2026-05-13.

## Context

Government-sensitive workflow, on-prem target (Moro Hub), tight
demo cycle. We need a stack that:

- Renders an Arabic-first, RTL-correct mobile UI.
- Stores money safely (no `double`, no rounding surprises).
- Runs entirely on sovereign infra without third-party SaaS.
- Has a tractable hiring market in the GCC.

## Decision

- **Mobile:** Flutter (stable channel), Riverpod 2, go_router, dio.
- **Backend:** Spring Boot 3 on Java 21 LTS, Gradle KTS.
- **DB:** PostgreSQL 15, Flyway migrations, no Hibernate auto-DDL.
- **Object store:** MinIO (S3-compatible) on-prem.
- **Reports:** Apache POI + OpenPDF, server-side generation.
- **Signing:** PAdES via PKCS#11 — *deferred to a later ADR.*
- **Auth:** OIDC, pluggable. v1 ships with mock UAE Pass + PDD SSO
  buttons until PDD provides client credentials.

## Consequences

- Single language per layer keeps the hiring story simple.
- Flyway-only migrations mean every schema change is reviewable.
- Mock OIDC lets the backend ship before the IdP decision lands —
  there's a clear seam to swap in real providers.

## Rejected alternatives

- React Native — weaker RTL story than Flutter.
- Node/Express backend — splits the team across two ecosystems
  for no real win in this domain.
- Firebase / Firestore — data residency risk in the UAE govt context.
- MongoDB primary — financial data needs FK constraints.
