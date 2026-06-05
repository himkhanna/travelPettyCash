# Business Case → Build: Gap Analysis

**Source:** *Business Case & High-Level Requirements — Mission Expenses App* (v1, 18-05-2026, S. Jain).
**Assessed against:** the developed PDD Delegation Expenses app (backend + Flutter), verified in code on 2026-06-05.

**Legend:** ✅ Built · 🟡 Partial · ❌ Gap · ⚠️ Divergence (decision needed)

## 1. Status by requirement

| BRD § | Requirement | Status | Evidence / note |
|---|---|:--:|---|
| 2.1 | Missions; multi-country; Active/Closed; Admin-only create/close | ✅ | Mission aggregate (parent/child); `Trip.countryCode` + `Trip.missionId` → one mission spans many countries via its trips. |
| 2.2 | Allocate from 2 sources; accept; member↔member transfer; Leader/Admin allocate | ✅ | Sources, Allocation (accept/decline), Transfer all present. |
| 2.2 | **Assign total budget to a *mission*, increase later** | ❌ | `Mission` has **no budget field**; budget lives only on `Trip.total_budget_minor`. No mission-level assign/top-up endpoint. |
| 2.3 | Expense fields, edit-later, OCR autofill, verify-before-post | ✅ | Full CRUD + Tesseract OCR autofill + review. |
| 2.3 | **Receipt = optional** | ⚠️ | BRD says optional. **Mobile makes the invoice mandatory** (submit blocked without it); backend API treats it as optional. Decision needed. |
| 2.4 | **Currency conversion** (capture FX rate; enter local ccy; store base + rate; preserve both) | ❌ | **Not built.** Single currency per trip; `Expense` has one `currency`, no exchange-rate/original-amount fields. (Out of scope in current design.) |
| 2.5 | Roles: Member / Leader / Admin | ✅ | Matches; app also adds Super-Admin (DG read-only) = the "Supervisor – Dashboard" stakeholder. |
| 2.6 | Summaries (individual/team/mission) + drill-down | ✅ | Per-scope reports, dashboards, expense detail. |
| 2.6 | **Allocation vs utilization** in reports | 🟡 | Mobile dashboard shows allocated-vs-spent; finance PDF has an ALLOCATED column but it's **stubbed ("—")** — allocated-per-source isn't surfaced into the report yet. |
| 2.6 | Share reports via **email, WhatsApp, download** | 🟡 | Email ✅ + download (PDF/XLSX/CSV) ✅. **WhatsApp share ❌.** |
| 2.7 | Offline add/store + auto-sync | ✅ | Offline gating + local queue + sync. (PWA: iOS background-sync limited — syncs on app reopen; full on native.) |
| 5 | Stakeholders (Admin/Users/Supervisor) | ✅ | Covered by the 4 roles. |
| 1.3 | "Identical to the present app UI/UX" | 🟡 | Built to the approved Final Design mockups — confirm these are the legacy app's design. |

## 2. Confirmed gaps to develop

| # | Item | BRD § | Type | Rough effort | Notes / dependencies |
|---|---|---|---|:--:|---|
| 1 | **Currency conversion (FX)** | 2.4 | ❌ Gap | **L** | Add `originalCurrency`, `originalAmount`, `exchangeRate`, `baseAmount` to Expense (+ migration, API, form input, reports show both). Needs an FX-rate source decision (manual entry vs on-prem/approved rate API — sovereignty per CLAUDE.md §3). Reverses the current "FX out of scope" design → warrants a short ADR. |
| 2 | **Mission-level budget** | 2.2 | ❌ Gap | **M** | Add budget to `Mission` + assign/increase endpoint + rollup vs child trips + Admin UI. |
| 3 | **Allocation-vs-utilization completeness** | 2.6 | 🟡 Partial | **S–M** | Aggregate existing Allocation data per source/trip and fill the finance-letter "ALLOCATED" column + report views (data exists; needs wiring). |
| 4 | **WhatsApp report sharing** | 2.6 | ❌ Gap | **S** | Add share alongside email/download (Web Share API on PWA / `wa.me` link with the generated report). |
| 5 | **Receipt optional vs mandatory** | 2.3 | ⚠️ Decision | **XS** | If PM agrees to BRD (optional): relax the mobile submit-guard. Else keep + note as intentional. |

## 3. Decisions needed from the product owner

1. **Currency conversion scope** — BRD marks it "under exploration." Confirm it's in-scope for this phase before building #1 (it's the largest item and reverses a design decision). If yes: manual rate entry, or an approved/on-prem rate source?
2. **Receipt mandatory vs optional** — BRD says optional; the app enforces it. Keep enforced, or relax to match the BRD?

## 4. Already covered / beyond the BRD (no action)
SSO (UAE Pass + Dubai-Gov OIDC), in-app chat, notifications, receipt OCR, server-side report generation + digital signing, audit feed, Super-Admin/DG read-only view.
