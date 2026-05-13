# Screen Inventory — PDD Petty Cash

> One row per screen in `Petty_Cash_Final_Design.pdf`. For each screen: the entities it touches, the API endpoint(s) behind it, the Riverpod provider(s) that own its state, and the role(s) that can reach it.
>
> Use this file when scaffolding a feature: open it, find the screen, and you'll know exactly which entities, endpoints, and providers to wire.
>
> **Notation:**
> - `M` = Team Member, `L` = Team Leader, `A` = Admin, `S` = Super Admin
> - Endpoints are relative to `/api/v1`
> - Provider names follow the pattern `<feature>(Async|State|)Provider` and live in `mobile/lib/features/<feature>/application/`

---

## Mockup page index

| # | Screen | Route | Roles |
|---|---|---|---|
| 1 | Login | `/login` | all |
| 2 | Home — Active Trips | `/trips` | all |
| 3 | Trip Dashboard (Member view) | `/trips/:id/dashboard` | M, L, A, S |
| 4 | Trip Dashboard with slide-out menu (Member) | `/trips/:id/dashboard` + drawer | M |
| 5 | Add Expense | `/trips/:id/expenses/new` | M, L |
| 6 | Add Expense — success modal | overlay on `/trips/:id/expenses/new` | M, L |
| 7 | My Expenses — list | `/trips/:id/expenses/mine` | M, L, A |
| 8 | My Expenses — filter sheet | overlay | M, L, A |
| 9 | Expense detail (read) | `/trips/:id/expenses/:expenseId` | M, L, A, S |
| 10 | Expense detail (edit) | `/trips/:id/expenses/:expenseId/edit` | M, L |
| 11 | My Expenses — category breakdown | `/trips/:id/expenses/mine?view=chart` | M, L, A |
| 12 | Transfer Amount form | `/trips/:id/transfer` | M, L |
| 13 | Transfer Amount — success modal | overlay on `/trips/:id/transfer` | M, L |
| 14 | Chats list | `/trips/:id/chat` | M, L, A |
| 15 | Chat thread | `/trips/:id/chat/:threadId` | M, L, A |
| 16 | Notifications | `/notifications` | all |
| 17 | Home — Active Trips (Leader entry, same as #2) | `/trips` | L |
| 18 | Allocate Funds — initial entry | `/trips/:id/allocate` | L |
| 19 | Allocate Funds — review & confirm | `/trips/:id/allocate/confirm` | L |
| 20 | Manage Funds — overview | `/trips/:id/manage-funds` | L |
| 21 | Manage Funds — per-member detail (Add New Allocation) | overlay on `/trips/:id/manage-funds` | L |
| 22 | Trip Dashboard — My View tab (Leader) | `/trips/:id/dashboard?tab=my` | L |
| 23 | Trip Dashboard — Trip View tab (Leader) | `/trips/:id/dashboard?tab=trip` | L |
| 24 | My Expenses tab (Leader, with Edit All) | `/trips/:id/expenses/mine` | L |
| 25 | My Expenses — bulk edit mode | `/trips/:id/expenses/mine?edit=true` | L |
| 26 | Trip Expenses list (all members) | `/trips/:id/expenses/all` | L, A, S |
| 27 | Trip Expenses — filter sheet (with By Members) | overlay | L, A, S |
| 28 | Trip Expenses — By Category chart | `/trips/:id/expenses/all?view=chart&group=category` | L, A, S |
| 29 | Trip Expenses — By Member chart | `/trips/:id/expenses/all?view=chart&group=member` | L, A, S |
| 30 | Per-member breakdown modal | overlay on #29 | L, A, S |
| 31 | Trip Dashboard with slide-out menu (Leader — adds Manage Funds) | `/trips/:id/dashboard` + drawer | L |

---

## Detailed screen specs

### 1. Login
**File:** `mobile/lib/features/auth/presentation/login_screen.dart`
**Mockup:** page 1
**Entities:** `User` (read-only on success)
**Endpoints:** `POST /auth/login` → `{ accessToken, refreshToken, user }`
**Providers:**
- `authControllerProvider` (StateNotifier<AsyncValue<AuthState>>) — owns login submission, token persistence, error mapping.
- `authRepositoryProvider` — wraps `Dio` auth calls.
**Side effects:** on success, write tokens to `flutter_secure_storage`, hydrate `currentUserProvider`, route to `/trips`.
**Form fields:** username, password. Forgot Password link (deferred — out of scope v1, link is visible but routes to a "contact admin" screen).
**RTL/L10n keys:** `auth.login.title`, `auth.login.username`, `auth.login.password`, `auth.login.forgot`, `auth.login.submit`.

---

### 2 & 17. Home — Active Trips
**File:** `mobile/lib/features/trips/presentation/trips_home_screen.dart`
**Mockup:** pages 2, 17
**Entities:** `Trip`, `User` (for greeting)
**Endpoints:** `GET /trips?status=ACTIVE`
**Providers:**
- `currentUserProvider` (Provider<User>) — for "HELLO {name}".
- `activeTripsProvider` (FutureProvider<List<Trip>>) — list of trips the user belongs to.
**UI notes:**
- Trip card shows country image, country name, and a badge with notification count for that trip.
- Tapping a card routes to `/trips/:id/dashboard`.
- The badge number (e.g. "11" on KSA) is per-trip unread notifications, not global.
**Open question:** country images — bundled assets keyed by ISO country code, or remote URLs from the trip record? Default to bundled.

---

### 3 & 4. Trip Dashboard (Member view)
**File:** `mobile/lib/features/trips/presentation/trip_dashboard_screen.dart`
**Mockup:** pages 3 (no drawer), 4 (with drawer open)
**Entities:** `Trip`, `Source`, balance aggregates per `(userId, tripId, sourceId)`
**Endpoints:**
- `GET /trips/:id` — trip metadata
- `GET /trips/:id/balances?scope=me` — returns per-source balances for current user + total spent + total budget
**Providers:**
- `tripDetailProvider(tripId)` (FutureProvider.family)
- `myTripBalancesProvider(tripId)` (FutureProvider.family) — drives the dual-arc donut and the per-source cards
**UI notes:**
- Main donut: green arc = remaining balance, brown arc = total spent. Center label: balance amount + total spent.
- Per-source cards beneath: olive-gold balance arc, green down-arrow (received total), red up-arrow (spent total) under each.
- "TOTAL TRIP BUDGET" pill at bottom is trip-level (sum across sources for the user's allocation).
- Drawer (page 4): Logout / All Trips / Notifications (badge) / Chat (badge). **No Manage Funds for Member role.**

---

### 5 & 6. Add Expense
**File:** `mobile/lib/features/expenses/presentation/add_expense_screen.dart`
**Mockup:** pages 5, 6
**Entities:** `Expense` (create), `Source` (selector), `ExpenseCategory` (selector)
**Endpoints:**
- `GET /trips/:id/balances?scope=me` — to populate the Source dropdown with current balances
- `GET /categories` — for the category tile row
- `POST /trips/:id/expenses` — multipart if receipt attached, JSON otherwise (with `Idempotency-Key` header)
- `POST /expenses/:id/receipt` — separate upload if receipt added after the fact (offline path uses this)
**Providers:**
- `expenseDraftProvider(tripId)` (StateNotifier<ExpenseDraft>) — local draft, survives keyboard close
- `addExpenseControllerProvider(tripId)` — handles submit, idempotency key generation, offline queueing
- `categoriesProvider` — cached, refreshes once per session
**Form fields:** `amount`, `sourceId`, `categoryId`, `details`, `occurredAt`, `receiptImage`
**Validation:**
- amount > 0, in minor units; if amount > current source balance, **warn but allow** (scope: balance can go minus).
- categoryId required; sourceId required; receipt optional.
**Offline behaviour:** on submit without network, write to Drift `pending_expenses` table, return the success modal anyway, sync on next online tick. Show "Pending sync" chip on the row in My Expenses until accepted.
**Success modal (page 6):** "ADD MORE EXPENSES" → reset form, stay on screen. "CLOSE" → pop to dashboard.

---

### 7 & 24. My Expenses — list
**File:** `mobile/lib/features/expenses/presentation/my_expenses_screen.dart`
**Mockup:** pages 7, 24
**Entities:** `Expense` (filtered by current user)
**Endpoints:** `GET /trips/:id/expenses?userId=me&cursor=&limit=20&category=&sourceId=&from=&to=`
**Providers:**
- `myExpensesProvider(tripId, filter)` (FutureProvider.family) — paginated list
- `expenseFilterProvider(tripId)` (StateProvider.family) — holds active filter
**UI notes:**
- Each row: large amount circle (olive-gold) on left, source + date on top right, details text below.
- Top-right icons: list/chart toggle, filter funnel.
- "EDIT ALL" link (top-left) enters bulk-edit mode (#25). **Available to all roles that can edit their own expenses.**

---

### 8 & 27. Expense Filter sheet
**File:** `mobile/lib/features/expenses/presentation/widgets/expense_filter_sheet.dart`
**Mockup:** pages 8 (My), 27 (Trip — adds By Members)
**Providers:** mutates `expenseFilterProvider(tripId)`
**Filters:**
- By Category (multi-select checkboxes from `categoriesProvider`)
- By Source (multi-select)
- By Members (multi-select, **Trip Expenses view only**, sourced from `tripDetailProvider.members`)
- By Date range (two date pickers)
**Submission:** "Apply Filters" closes the sheet and triggers a refetch on the list provider.

---

### 9. Expense detail (read)
**File:** `mobile/lib/features/expenses/presentation/expense_detail_screen.dart`
**Mockup:** page 9
**Entities:** `Expense` (single)
**Endpoints:**
- `GET /expenses/:id`
- `GET /expenses/:id/receipt` — returns signed URL for receipt object
**Providers:**
- `expenseDetailProvider(expenseId)` (FutureProvider.family)
**UI notes:**
- Header: pencil icon (edit) on left, close (×) on right. Pencil only visible if current user owns the expense and trip is not closed.
- Shows time, date, amount circle, category icon + name, source, details, "VIEW RECEIPT" button → opens receipt viewer.

---

### 10. Expense detail (edit)
**File:** `mobile/lib/features/expenses/presentation/expense_edit_screen.dart`
**Mockup:** page 10
**Entities:** `Expense` (update)
**Endpoints:**
- `PATCH /expenses/:id` — partial update (source, details, receipt key, category, amount, occurredAt)
- `POST /expenses/:id/receipt` — re-upload
**Providers:**
- `expenseEditControllerProvider(expenseId)` — handles patch, validation, optimistic update
**Editable fields per mockup:** source (dropdown), details (free text), receipt (replace). Amount, category, and date appear locked in the mockup — confirm with PM whether these should also be editable; default assumption: **editable until trip is closed**, controlled by backend.

---

### 11. My Expenses — category breakdown chart
**File:** `mobile/lib/features/expenses/presentation/expense_breakdown_screen.dart`
**Mockup:** page 11
**Entities:** aggregated `Expense` totals
**Endpoints:** `GET /trips/:id/expenses/summary?scope=mine&groupBy=category|source`
**Providers:**
- `expenseSummaryProvider(tripId, scope, groupBy)` (FutureProvider.family)
**UI notes:**
- Multi-segment donut with center "TOTAL SPEND". Legend below with color swatch + label + amount.
- Tab switcher at top: **BY CATEGORY** / **BY SOURCE** (Leader view also adds **BY MEMBER** — see #29).
- Categories color-coded: purple/Entertainment, dark blue/Hotel, green/Travel, gold/Tips, red/Others. **Lock these colors in the theme.**

---

### 12 & 13. Transfer Amount
**File:** `mobile/lib/features/funds/presentation/transfer_screen.dart`
**Mockup:** pages 12, 13
**Entities:** `Transfer` (create), `Source`, `User` (trip members)
**Endpoints:**
- `GET /trips/:id` — to populate the team member dropdown (excludes self)
- `GET /trips/:id/balances?scope=me` — for the source selector tiles with current balances
- `POST /trips/:id/transfers` — body: `{ toUserId, sourceId, amount, note, idempotencyKey }`
**Providers:**
- `transferDraftProvider(tripId)` (StateNotifier<TransferDraft>)
- `transferControllerProvider(tripId)` — submit + offline queue
**UI notes:**
- Three source tiles at top, selected one highlighted brown. Tile shows source name + balance. **Three tiles in mockup is the layout container** — actual count is dynamic from `Source` list.
- "TO?" dropdown lists trip members minus current user.
- Success modal (page 13): "TRANSFER MORE FUNDS" / "CLOSE".
**Backend behaviour:** transfer creates two `Allocation`-style events (debit fromUser, credit toUser) under the same `Transfer.id`, both tagged with `sourceId`. Recipient gets an `ALLOCATION_RECEIVED`-type notification with Accept/Decline (see #16). Until accepted, both sides' balances reflect the pending state but UI shows "Pending" on the row.

---

### 14. Chats list
**File:** `mobile/lib/features/chat/presentation/chats_list_screen.dart`
**Mockup:** page 14
**Entities:** `ChatThread`, `ChatMessage` (last message preview)
**Endpoints:** `GET /chat/threads?tripId=:id`
**Providers:**
- `chatThreadsProvider(tripId)` (StreamProvider.family if WebSocket, else FutureProvider with refresh) — list of threads with last message + unread count
**UI notes:**
- Each row: avatar, name, last message preview, time, unread badge.
- Active/highlighted thread has a darker title (e.g. "Ahmed Salem" in mockup — bold = has unread).

---

### 15. Chat thread
**File:** `mobile/lib/features/chat/presentation/chat_thread_screen.dart`
**Mockup:** page 15
**Entities:** `ChatMessage`
**Endpoints:**
- `GET /chat/threads/:threadId/messages?cursor=&limit=50` — paginated history (oldest at top)
- `POST /chat/threads/:threadId/messages` — body: `{ body }`
- WebSocket subscription on `chat.thread.:threadId` for real-time delivery (fallback: poll every 10s when WS unavailable)
**Providers:**
- `chatThreadProvider(threadId)` (StreamProvider.family) — message stream
- `chatThreadControllerProvider(threadId)` — send, mark-read
**UI notes:**
- Header: back chevron, avatar, name.
- Date separators between message clusters ("SUN 26 FEB 2017 - 09.12 AM" style).
- Outgoing messages: cream background, right-aligned (LTR) / left-aligned (RTL).
- Incoming messages: light beige, opposite alignment.
- Composer pinned to bottom with a send arrow icon.

---

### 16. Notifications
**File:** `mobile/lib/features/notifications/presentation/notifications_screen.dart`
**Mockup:** page 16
**Entities:** `Notification`
**Endpoints:**
- `GET /notifications?cursor=&limit=30`
- `PATCH /notifications/:id/read`
- `POST /notifications/:id/act` — body: `{ action: "ACCEPT" | "DECLINE" }`
- `DELETE /notifications/:id`
**Providers:**
- `notificationsProvider` (StreamProvider or FutureProvider with poll) — global, not trip-scoped
- `notificationsControllerProvider` — accept/decline/delete actions
**UI notes:**
- Time stamp on top of each card.
- Actionable notifications (allocation received, transfer received) show ACCEPT / DECLINE buttons.
- Informational notifications (e.g. "Mohammed Ali has transferred SAR 1,500 to you" — already accepted) show no buttons.
- Swipe-left reveals trash icon → DELETE confirmation.
- "DELETE ALL" link top-right.
**Notification types (per scope + mockups):**
- `ALLOCATION_RECEIVED` — actionable
- `TRANSFER_RECEIVED` — actionable
- `TRANSFER_ACCEPTED` — informational (sent to original sender when recipient accepts)
- `TRIP_ASSIGNED` — actionable (Admin adds you to a new trip)
- `TRIP_CLOSED` — informational
- `EXPENSE_QUERY` — informational (Admin asks a question on your expense; opens chat thread)

---

### 18. Allocate Funds — initial entry (Leader)
**File:** `mobile/lib/features/funds/presentation/allocate_funds_screen.dart`
**Mockup:** page 18
**Entities:** `Allocation` (create, bulk), `Source`, `User` (trip members)
**Endpoints:**
- `GET /trips/:id` — trip metadata + member list + total budget
- `GET /trips/:id/balances?scope=leader` — Leader's available balance per source
- `POST /trips/:id/allocations` — body: `{ allocations: [{ toUserId, sourceId, amount }, ...] }` (bulk)
**Providers:**
- `allocationDraftProvider(tripId)` (StateNotifier<List<AllocationRow>>) — Leader's in-progress allocation grid
- `allocateFundsControllerProvider(tripId)` — submit, validation against available balance
**UI notes:**
- Top: total trip budget pill, then three source tiles with Leader's current balance per source.
- Per-member row: name + total allocated for that member + three source-amount inputs (Zabeel / Protocol Dept / Protocol Dept). **The "three tiles" pattern repeats but is dynamic on actual `Source` count.**
- "ALLOCATE FUNDS" CTA at bottom.
**Validation:** sum per source across all rows ≤ Leader's balance for that source. Per-row total can be 0 (skip that member this round).

---

### 19. Allocate Funds — review & confirm
**File:** `mobile/lib/features/funds/presentation/allocate_funds_confirm_screen.dart`
**Mockup:** page 19
**Entities:** same as #18
**Endpoints:** none until CONFIRM tap (which posts to `POST /trips/:id/allocations`)
**Providers:** reads `allocationDraftProvider(tripId)`
**UI notes:**
- Green banner: "PLEASE REVIEW AND CONFIRM"
- Shows REMAINING TRIP BALANCE after allocation
- Same per-member rows but read-only with confirmed amounts
- BACK / CONFIRM buttons. CONFIRM fires the POST, on success returns to #20.

---

### 20. Manage Funds — overview
**File:** `mobile/lib/features/funds/presentation/manage_funds_screen.dart`
**Mockup:** page 20
**Entities:** `Allocation` (read), `User`
**Endpoints:** `GET /trips/:id/allocations?groupBy=member` — returns each member's cumulative allocation per source
**Providers:**
- `tripAllocationsProvider(tripId)` (FutureProvider.family)
**UI notes:**
- Same layout as #19 but with pencil edit icons next to each member row.
- "CURRENT TRIP BALANCE" at top (Leader's remaining unallocated funds).
- Tapping pencil → opens modal #21.
- "CONFIRM CHANGES" CTA at bottom (only enabled if changes pending).
**Important:** allocations are **append-only**. The "edit" affordance is really "add another allocation slice" — the entity has multiple Allocation rows per (member, source) and the UI sums them.

---

### 21. Manage Funds — per-member detail / Add New Allocation
**File:** `mobile/lib/features/funds/presentation/widgets/manage_member_funds_modal.dart`
**Mockup:** page 21
**Entities:** `Allocation` (read existing, append new)
**Endpoints:**
- `GET /trips/:id/allocations?userId=:memberId` — full history for this member
- `POST /trips/:id/allocations` — single-member payload `{ allocations: [{ toUserId: memberId, sourceId, amount }] }`
**Providers:**
- `memberAllocationsProvider(tripId, memberId)` (FutureProvider.family)
- `addAllocationControllerProvider(tripId, memberId)` — submit, validation
**UI notes:**
- Top: member name, big amber circle showing CURRENT ALLOCATION total.
- Middle: read-only breakdown across three source tiles.
- Bottom: "ADD FUNDS" section with three empty source input tiles.
- "ADD NEW ALLOCATION" CTA at bottom.
- Close (×) top-right.

---

### 22 & 23. Trip Dashboard — My View / Trip View tabs (Leader)
**File:** `mobile/lib/features/trips/presentation/trip_dashboard_screen.dart` (same file as #3, with tab variant)
**Mockup:** pages 22 (My View), 23 (Trip View)
**Entities:** balance aggregates at two scopes
**Endpoints:**
- `GET /trips/:id/balances?scope=me` — same as #3
- `GET /trips/:id/balances?scope=trip` — full trip rollup across all members and sources
**Providers:**
- `myTripBalancesProvider(tripId)` (reused from #3)
- `tripBalancesProvider(tripId)` (FutureProvider.family) — only fetched when Leader switches to Trip View
**UI notes:**
- Top tab switcher: **MY VIEW** | **TRIP VIEW** (Leader & Admin only; Member sees no tabs and lands on My View by default).
- Trip View donut shows much larger numbers (full trip: SAR 25,500 balance, SAR 65,600 spent in mockup) — same widget, different data scope.
- Per-source cards in Trip View show trip-wide totals (SAR 12,900 and SAR 13,500 in mockup vs SAR 2,900 / SAR 3,500 in My View).

---

### 25. My Expenses — bulk edit mode
**File:** `mobile/lib/features/expenses/presentation/my_expenses_screen.dart` (edit mode variant)
**Mockup:** page 25
**Entities:** `Expense` (bulk update, primarily source reassignment)
**Endpoints:** `PATCH /expenses:bulk` — body: `[{ id, sourceId }, ...]`
**Providers:**
- `bulkEditExpensesProvider(tripId)` (StateNotifier<Map<expenseId, partialUpdate>>)
**UI notes:**
- Each row's Source label becomes a dropdown ("Zabeel Office and..." truncated → opens picker).
- SAVE button replaces the EDIT ALL link at the top.
- Cancelling discards local edits.
**This is the "tick-box view" the scope doc explicitly calls out** for source reassignment after expense creation.

---

### 26. Trip Expenses — all members list
**File:** `mobile/lib/features/expenses/presentation/trip_expenses_screen.dart`
**Mockup:** page 26
**Entities:** `Expense` (cross-member), `User` (for name labels)
**Endpoints:** `GET /trips/:id/expenses?scope=all&cursor=&limit=20&category=&sourceId=&memberId=&from=&to=`
**Providers:**
- `tripExpensesProvider(tripId, filter)` (FutureProvider.family)
- Tab toggle stored in `expenseScopeProvider(tripId)` (StateProvider.family with values `mine` | `all`)
**UI notes:**
- Tab toggle at top: **MY EXPENSES** | **TRIP EXPENSES**
- Each row shows the **member name** above the details line (yellow/amber tint per mockup), distinguishing it from the My Expenses view.
- Filter funnel and chart toggle on top right.

---

### 28. Trip Expenses — By Category chart
**File:** `mobile/lib/features/expenses/presentation/trip_expense_breakdown_screen.dart`
**Mockup:** page 28
**Entities:** aggregated `Expense` totals
**Endpoints:** `GET /trips/:id/expenses/summary?scope=all&groupBy=category`
**Providers:**
- `expenseSummaryProvider(tripId, scope=all, groupBy=category)` (reused from #11)
**UI notes:**
- Three-tab switcher: **BY CATEGORY** | **BY MEMBER** | **BY SOURCE**
- Same donut + legend pattern as #11.

---

### 29. Trip Expenses — By Member chart
**File:** same as #28, different tab
**Mockup:** page 29
**Entities:** aggregated by user
**Endpoints:** `GET /trips/:id/expenses/summary?scope=all&groupBy=member` — returns per-member spent + allocated + balance
**Providers:**
- `expenseSummaryProvider(tripId, scope=all, groupBy=member)` (reused)
**UI notes:**
- Each member row: color-coded amount circle (matches donut segment), name, ALLOCATED total, BALANCE remaining.
- Tapping a row → opens modal #30.

---

### 30. Per-member breakdown modal
**File:** `mobile/lib/features/expenses/presentation/widgets/member_breakdown_modal.dart`
**Mockup:** page 30
**Entities:** aggregated `Expense` for a single user
**Endpoints:** `GET /trips/:id/expenses/summary?scope=user&userId=:memberId&groupBy=category`
**Providers:**
- `memberExpenseSummaryProvider(tripId, memberId)` (FutureProvider.family)
**UI notes:**
- Same donut + legend layout as #11 but in a modal with member name header and close (×) button.

---

### 31. Trip Dashboard slide-out menu (Leader)
**File:** drawer widget reused from #4
**Mockup:** page 31
**Difference from #4:** adds **MANAGE FUNDS** item between ALL TRIPS and NOTIFICATIONS. Routes to #20.
**Provider:** drawer visibility menu items computed from `currentUserProvider.role`.

---

## Out of inventory — but referenced by mockups

These appear in flows but don't have their own mockup pages. Building them is still required:

- **Forgot Password screen** — referenced from Login (#1). Default behaviour for v1: a "contact your administrator" static screen. Real reset flow waits on identity provider decision.
- **Receipt photo viewer** — opened from #9 "VIEW RECEIPT". Full-screen image viewer with pinch-zoom and a download/share affordance.
- **Receipt camera & cropper** — opened from #5 / #10 "ADD RECEIPT" / "UPDATE RECEIPT". Uses `image_picker` (camera or gallery) → `image_cropper` → compressed to ≤ 1MB before attaching to the form draft.
- **All Trips screen** — drawer item "ALL TRIPS" routes here. Same layout as #2 but shows closed trips too with a status chip.
- **Trip Closed empty state** — when a Member opens a closed trip, the dashboard should be read-only with a "CLOSED" badge replacing the Add Expense FAB.

---

## Admin & Super Admin screens (not in current mockup PDF)

The mockup PDF covers Member and Leader flows only. Admin and Super Admin flows are defined by `User-Tasks.pdf` but not yet visually designed. The CMS for these roles is a **separate Flutter Web build** sharing the backend.

Track these as a parallel deliverable; expect to need:
- Create Trip (Admin) — multi-step: trip details → assign Leader → add members → assign initial source funds
- Close Trip (Admin) — with confirmation, locks all expense edits, triggers final report generation
- Assign Funds from Source pool (Admin) — top-up source balances at the trip level
- Reports screen (Admin) — generate any of the four report types per §10 of CLAUDE.md, with email-send option
- DG Dashboard (Super Admin) — read-only summary view across all active and recent trips

---

## Conventions when adding a new screen

1. Add a row to the **Mockup page index** table above.
2. Create a `## N. Screen name` block following the same structure: File, Mockup, Entities, Endpoints, Providers, UI notes.
3. Wire the route in `mobile/lib/app/router.dart`.
4. If the screen reads a new endpoint, add it to `backend/openapi/openapi.yaml` in the same PR.
5. If the screen introduces a new entity, update §5 of CLAUDE.md.
6. Bilingual ARB keys before the screen ships. No EN-only commits.

---

*Last updated: 2026-05-13. Pair this file with CLAUDE.md when scaffolding new features.*
