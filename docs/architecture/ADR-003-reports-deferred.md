# ADR-003 — Report generation and digital signature deferred

**Status:** Accepted.
**Date:** 2026-05-18.

## Context

`CLAUDE.md §10` defines four report types and mandates PAdES digital
signature for the finance letter. Implementing this requires:

- A signing key custodian (PDD HSM vs Moro Hub HSM vs software
  keystore for pilot) — **open in `CLAUDE.md §16`**.
- Apache POI / OpenPDF licence review for OpenPDF (LGPL).
- A `SignatureService` abstraction with a PKCS#11 implementation.
- Audit-log integration for signed-report hashes.

None of these are blocking the demo.

## Decision

1. The `GET /api/v1/reports/trip/{id}` endpoint exists and returns
   `501 Not Implemented` with body
   `{ "code": "REPORT_DEFERRED", "detail": "..." }`.
2. The `POST /api/v1/reports/{reportId}/sign` endpoint is not
   implemented at all in v1.
3. The CMS Reports dialog in the mobile app surfaces the four report
   types but disables the "Generate" button with a "Coming in a
   future release" tooltip.
4. The audit log hash-chain *is* implemented now (since financial
   events already write audit rows) so signed reports can land
   later without retrofitting.

## Consequences

- We don't block on the PDD HSM decision.
- The OpenAPI spec carries the report endpoint shape so the mobile
  client can be written against the final contract.
- A future ADR (ADR-004) will record the signing-key decision.

## Trigger to revisit

When **any** of:
- PDD confirms a signing key custodian.
- The finance team blocks on receiving a signed PDF.
- The Moro Hub deployment is firm enough to provision an HSM slot.
