# ADR-002 — Dual OIDC (UAE Pass + PDD SSO), mock for v1

**Status:** Accepted (provisional — pending PDD IT confirmation).
**Date:** 2026-05-18.

## Context

`CLAUDE.md §16` flags the production IdP choice as open. The product
team has now confirmed the login screen will offer **two buttons**:
*Sign in with UAE Pass* and *Sign in with PDD SSO*. Both are real
login options at launch.

Real UAE Pass integration requires sandbox credentials, redirect URI
registration, and a signed agreement — none of which are available
in the timeframe of the customer-demo phase.

## Decision

For v1 of the demo and backend scaffold:

1. The login screen shows both SSO buttons.
2. Both buttons hit `POST /api/v1/auth/login` with a `provider`
   discriminator (`UAE_PASS` or `PDD_SSO`).
3. The backend mocks both: any submission for a seeded test user
   returns a fresh JWT. The actual OIDC dance is stubbed.
4. The endpoint is implemented behind an `AuthProvider` interface so
   the mock can be swapped for real OIDC clients without touching
   the controller.
5. A clearly-labelled `TODO(§16)` sits in `AuthController` with a
   pointer to this ADR.

## Consequences

- Demo is unblocked. Backend ships without waiting on UAE Pass
  paperwork.
- Mobile login flow is real and end-to-end; only the IdP behind it
  is fake.
- When credentials arrive, swap the mock provider for a real one in
  one PR. Mobile changes: zero.

## Open

- UAE Pass sandbox credentials — **PDD IT**.
- PDD SSO endpoint (Azure AD? On-prem AD?) — **PDD IT**.
- Token TTLs once we know the IdP — currently 15 min access,
  24 h refresh.

## Rejected alternatives

- Building only UAE Pass — would block on credentials.
- Building only PDD SSO — would force a re-design when UAE Pass
  arrives (login flow looks different).
- Skipping auth entirely for the demo — every reviewer asks about it.
