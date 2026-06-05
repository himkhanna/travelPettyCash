# ADR-003 — Currency conversion (manual exchange rate)

- **Status:** Accepted (2026-06-05)
- **Relates to:** Business Case §2.4; CLAUDE.md §6 (money rules) — this ADR **narrows** the
  earlier "FX out of scope" stance into a controlled, single-rate, record-only model.
- **Decision owner:** PM confirmed (2026-06-05): **manual rate entry** (no auto FX feed).

## Context

Officers on a mission whose funds are held in the trip currency (e.g. SAR) sometimes spend in
a different local currency (e.g. EUR). BRD §2.4 wants the original amount, the converted amount,
and the rate all preserved. We are **not** integrating an automatic FX feed (sovereignty +
simplicity) — the user enters the rate manually.

## Decision

1. **A trip stays single-currency.** The trip currency remains the **base** for all balances,
   allocations, transfers, and reports. Balance math is unchanged → CLAUDE.md §6 fully preserved
   (BIGINT minor units, `Money`, no floats in business logic).

2. **An expense may optionally record a foreign-currency original.** When the officer spends in
   another currency they enter:
   - the **foreign amount** (line items in the foreign currency),
   - the **foreign currency** (ISO 4217),
   - the **exchange rate** (manual) — trip-currency units per 1 foreign unit.

   The **base (trip-currency) amount** = foreign amount × rate, rounded half-up to the trip
   currency's decimals. That base amount is the canonical `amountMinor` that affects balances —
   exactly as today. The original currency / amount / rate are stored **for the record only** and
   are never used in balance arithmetic.

3. **New `Expense` fields (all nullable — set only when a conversion happened):**
   - `original_currency` `CHAR(3)` — the foreign ISO code.
   - `original_amount_minor` `BIGINT` — foreign amount in its own minor units.
   - `exchange_rate` `NUMERIC(18,6)` — manual rate, foreign → trip.

   When null, the expense was entered directly in the trip currency (the common case).

4. **Rounding is done once, client-side, into trip-currency minor units**, then sent as the
   normal `amountMinor`. The backend persists the original triplet as supplied and validates it
   (all-three-or-none; rate > 0; original_currency ≠ trip currency). No cross-currency minor-unit
   math on the server.

5. **Display & reports:** where an expense has a foreign original, show e.g.
   `SAR 410.00 (€100.00 @ 4.10)`. Reports keep totalling in the trip currency; the original is
   shown as supplementary detail.

## Consequences

- Balances, allocations, source tracking, and the audit chain are unaffected (still trip-ccy).
- The rate is a **recorded fact**, not a live conversion — re-opening an old expense shows the
  rate that was used, satisfying "both preserved, along with ex. rate."
- No external FX dependency; if an auto-rate source is ever approved, it can pre-fill the manual
  field without changing the data model.

## Slices

| # | Slice | Notes |
|---|---|---|
| A | Backend: V013 migration + `Expense` fields + `CreateExpenseRequest`/response + persistence + validation + tests | Self-contained; no behaviour change when fields are null. |
| B | Mobile Add-Expense: "spent in another currency?" toggle → currency + rate, live base-amount preview; expense detail shows the original + rate | |
| C | Reports/dashboards: surface the original amount + rate where present | |
