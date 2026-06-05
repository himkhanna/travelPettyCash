# Business Case → Build: Gap Analysis

**Source:** *Business Case & High-Level Requirements — Mission Expenses App* (v1, 18-05-2026, S. Jain).
**Assessed against:** the developed PDD Delegation Expenses app (backend + Flutter), verified in code on 2026-06-05.

> **Update 2026-06-05:** all five confirmed gaps below have since been **built and merged**
> (PR #6 + follow-ups). The original assessment is preserved for the record; the
> "Confirmed gaps" table now carries a ✅ Resolved status column. See CLAUDE.md §17
> (2026-06-05 entry) and ADR-003 for the as-built detail.

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

| # | Item | BRD § | Type | Rough effort | Status | Notes / dependencies |
|---|---|---|---|:--:|:--:|---|
| 1 | **Currency conversion (FX)** | 2.4 | ❌ Gap | **L** | ✅ Resolved | Manual-rate, record-only model — ADR-003. `V013` adds `original_currency` / `original_amount_minor` / `exchange_rate`; base (trip-ccy) amount stays canonical. Mobile "spent in another currency?" toggle + live preview. |
| 2 | **Mission-level budget** | 2.2 | ❌ Gap | **M** | ✅ Resolved | `V014` adds `missions.budget_minor` + `budget_currency`; `PATCH /api/v1/missions/{id}/budget` (admin, assign/increase); CMS mission-detail set/edit dialog. |
| 3 | **Allocation-vs-utilization completeness** | 2.6 | 🟡 Partial | **S–M** | ✅ Resolved | `ReportService.allocatedBySource` aggregates accepted admin-pool allocations; finance-letter PDF ALLOCATED/RETURNED columns now computed. |
| 4 | **WhatsApp report sharing** | 2.6 | ❌ Gap | **S** | ✅ Resolved | `save_to_disk.shareBytes` via Web Share API (device share sheet → WhatsApp) with download fallback; Share button on the Reports dashboard. |
| 5 | **Receipt optional vs mandatory** | 2.3 | ⚠️ Decision | **XS** | ✅ Resolved | PM confirmed BRD (optional); mobile submit-guard relaxed — receipt no longer required to post. |

## 3. Decisions needed from the product owner

1. **Currency conversion scope** — BRD marks it "under exploration." Confirm it's in-scope for this phase before building #1 (it's the largest item and reverses a design decision). If yes: manual rate entry, or an approved/on-prem rate source?
2. **Receipt mandatory vs optional** — BRD says optional; the app enforces it. Keep enforced, or relax to match the BRD?

## 4. Already covered / beyond the BRD (no action)
SSO (UAE Pass + Dubai-Gov OIDC), in-app chat, notifications, receipt OCR, server-side report generation + digital signing, audit feed, Super-Admin/DG read-only view.
