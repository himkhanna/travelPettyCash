# ADR-004 — CMS in the same Flutter codebase, responsive layout

**Status:** Accepted.
**Date:** 2026-05-18.

## Context

`CLAUDE.md §15` listed the CMS as "a separate Flutter Web build
sharing the same backend." Milestone D shipped the CMS *inside* the
mobile codebase as `lib/features/cms/`, on the assumption that
Flutter renders the same code across phone, tablet, and desktop web
and that role-gated routes are enough separation.

The product owner has now confirmed: keep CMS in the same codebase,
make every CMS screen responsive.

## Decision

1. CMS stays under `mobile/lib/features/cms/`.
2. Layout is driven off a `Breakpoint` helper (phone `< 600 px`,
   tablet `600-960 px`, desktop `> 960 px`).
3. Phone view: stacked list. Tablet/desktop view: multi-column with
   detail panel.
4. One Flutter build, one deploy. The CMS surface is reachable at
   `/cms` and is route-gated by role (`ADMIN`, `SUPER_ADMIN`); the
   mobile surface at `/m/...` is reachable by any authenticated user.

## Consequences

- The Milestone D commit `8a5e4e7` does not need refactoring.
- The phone-frame viewport (`PhoneViewport`) is bypassed for `/cms`
  routes — already true today.
- A single CI pipeline builds and tests both surfaces.

## Rejected alternative

- Separate Flutter Web app. Would have required extracting `core/`
  and `domain/` into a shared package, two deploys, two auth flows.
  No real benefit for the team size and the audit boundaries.
