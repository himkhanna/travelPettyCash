# ADR-005 — Receipt OCR: mocked endpoint for v1, on-prem Tesseract later

**Status:** Accepted.
**Date:** 2026-05-18.

## Context

The Add Expense flow now leads with **Scan Receipt** as the primary
action: the user photographs a receipt, the app extracts vendor,
amount, quantity, and a category hint, pre-fills the form, and shows
a "please verify before submitting" disclaimer. The remaining flow
(receipt attaches to the expense, manual edit always allowed)
matches the prior UX.

`CLAUDE.md §15` explicitly lists OCR as out of scope for v1 and
states that any future implementation must be **deterministic-first
(Tesseract or on-prem Document AI) before any LLM is considered**,
and §1 prohibits third-party SaaS for storage / processing without
explicit approval.

The product owner has now requested OCR be present in the demo. Two
things are in tension: the requested UX (working scan flow) and the
non-negotiable sovereignty / determinism constraints.

## Decision

For v1:

1. The OCR **UX is real and visible**. Scan Receipt button is the
   primary action at the top of Add Expense; gallery upload is the
   secondary action.
2. The OCR **extraction is mocked end-to-end**. The backend exposes
   `POST /api/v1/receipts/scan` returning a deterministic canned
   response keyed by `sha256(image) mod 4`. The mobile fake provider
   mirrors the same four canned results so demos without a backend
   still behave plausibly.
3. The yellow disclaimer banner ("OCR result — please verify all
   fields before submitting") is always shown after a scan,
   regardless of confidence. The user always edits before submit.
4. The `ReceiptScanner` interface on the backend has a clear
   `TODO(§15 ADR-005)` marker pointing to this ADR. Swapping in real
   Tesseract is one new implementation class plus configuration.

For v2 (post-demo):

1. The real implementation will be **Tesseract OCR on the backend**,
   running inside the Moro Hub cluster. No external API calls.
2. Confidence threshold below which the suggestion is *not* shown
   needs to be set empirically once Tesseract is wired and we have
   real receipt samples. Tracked as an open item below.
3. An LLM-based extraction layer (e.g. Claude on a sovereign tenancy
   or an on-prem model) may be evaluated *only* after deterministic
   OCR is in production and only if PDD approves the data flow.

## Why not Google ML Kit on-device

- Pulls Google Play Services as a dependency on Android. Sovereignty
  question is unresolved.
- iOS variant uses Apple Vision, which is fine on-device but creates
  a per-platform extraction quality gap.
- The team's bandwidth is better spent on a single backend Tesseract
  pipeline that handles RTL/Arabic receipts uniformly.

## Why mocked, not nothing

Removing the OCR UX entirely would force a demo storyline of "this
is coming but you can't see it," which buys nothing. A mocked
endpoint exercises the full UX surface — mobile capture, upload,
pre-fill, disclaimer, edit-before-submit — so the only thing that
changes when real Tesseract lands is the bytes coming back from
`/receipts/scan`. Mobile changes: zero.

## Consequences

- The disclaimer banner is permanent UX furniture. It must remain
  even when real OCR achieves >0.9 confidence, until the product
  owner explicitly approves removing it. Users always re-check.
- Reports and audit logs treat the final submitted values as
  user-authored, not OCR-extracted. We do not store the OCR
  suggestion separately. (Open: should we? See below.)
- The contract `POST /receipts/scan` is now part of the API surface
  and shape-stable — mobile builds against it for both fake and
  real implementations.

## Open

- **Confidence threshold** below which the pre-fill is skipped
  silently. Default for v1 mock: fill regardless. Revisit with
  real Tesseract data.
- **Suggestion vs ground truth** — do we audit-log the OCR
  suggestion alongside the user's final values, to study
  extraction quality? Defer until v2.
- **Arabic receipt handling** — Tesseract `ara` traineddata exists
  but quality varies. Will need a curated training pass on real
  PDD receipts.

## Trigger to revisit

After the Phase 3 hosting decision lands (Moro Hub bucket + compute
slots confirmed), schedule the Tesseract spike. Until then this
mock stays.
