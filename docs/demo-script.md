# PDD Petty Cash — Demo Script

> Twenty-minute walk-through for the Protocol Department review.
> Keep narration short. Let the screens carry the story.

**Build:** Flutter Web (Chrome). For an in-room demo, run locally
(`cd mobile && flutter run -d chrome`). For remote review, share the
Vercel preview URL.

**Pre-flight (do once before the meeting):**
1. `git pull origin main` and `flutter pub get`.
2. `flutter run -d chrome` — wait for the landing page.
3. Open Demo Controls (tune icon top bar). Confirm:
   - Latency: **400 ms** (visible but not painful)
   - Failure rate: **0 %**
   - Offline: **off**
4. Make sure the browser window is at least 1280 × 800 so the phone
   frame renders next to the docs panel.

## Story arc (≈ 20 min)

### 1. Frame the problem (1 min)

> "Today every trip ends with someone hand-reconciling a spreadsheet
> against paper receipts in two currencies and two funding sources.
> We're replacing that with a phone-first app the protocol officer
> uses in the field, plus an admin console for finance."

Skip the slide deck. Go straight to the prototype.

### 2. Member happy path (5 min)

Roles dropdown → **Team Member** → "Mobile UI".

1. **Trip Dashboard** — point at the dual-arc donut (balance vs spent)
   and the per-source cards. Note: balances are tracked per source.
2. Tap **+** → **Add Expense**.
   - Pick Food, type 1500 (SAR 15.00), pick Zabeel Office, add a
     line of detail.
   - Submit → success modal. Dashboard updates.
3. Open Demo Controls → toggle **Offline on**. Add another expense.
   - Point at the "Pending sync" chip on My Expenses.
   - Toggle Offline off → row clears to "Synced".
4. **My Expenses** → filter funnel → filter by Food → chart toggle
   → category breakdown donut.
5. **Transfer** → pick a teammate, pick Zabeel Office, 500 SAR.
   - Success modal. Switch to recipient role to show the
     `TRANSFER_RECEIVED` notification with Accept / Decline.

### 3. Leader add-ons (4 min)

Switch role → **Team Leader**.

1. Drawer → **Manage Funds**. Show per-member allocation grid.
2. **Allocate Funds** → assign 1000 SAR to one member from Zabeel
   Office, 500 SAR from Protocol Dept. Review → Confirm.
3. **Trip View** tab on the dashboard — note the larger numbers
   (full trip rollup, not just self).
4. **Trip Expenses** → all members' expenses, filter By Members,
   chart By Member.

### 4. Admin (3 min)

Back to landing → **Admin** → **Admin Console (Web)**.

1. **Create Trip** dialog — pick country, currency, leader, members,
   initial budget per source.
2. **Add Category** dialog — show that the category list is admin-managed.
3. **Reports** dialog — show the four report types. Acknowledge that
   server-side generation and digital signature are deferred to Phase 3.
4. **Close Trip** action — show the confirmation flow.

### 5. DG read-only view (1 min)

Landing → **Director General** → **DG Dashboard**.

Show per-user spend, per-category spend, current balances across
active trips. Read-only.

### 6. Bilingual + offline note (1 min)

Open browser dev tools → set system locale to Arabic, refresh.

Every screen renders RTL. Currency formatting stays AR-friendly.

### 7. What's next (2 min — discussion, not slides)

> "What you saw is the mobile UI against mocked data. The next
> milestone is the Spring Boot backend on Moro Hub. Before we wire
> the real backend in, we need three decisions from PDD:"

1. **Identity:** UAE Pass + PDD SSO — both buttons are stubbed.
   Need OIDC client credentials for both.
2. **Signing:** report digital signature is out of v1 scope until
   PDD designates a signing key custodian (PDD HSM vs Moro Hub HSM).
3. **Hosting:** confirm Moro Hub sovereign cluster + the Postgres
   and MinIO buckets we should target.

End on a hand-off question, not a status update.

## Failure recovery

- **Flutter hot-reload broke a screen:** stop the run, `flutter clean`,
  re-run. Use the recorded preview URL as the live fallback.
- **Browser zoomed too far in:** Ctrl + 0.
- **Audience asks for something not in the demo:** capture verbatim
  in `docs/feedback/YYYY-MM-DD_session-N.md`. Don't try to build it
  live.

## Closing

Two questions to ask before the meeting ends:

1. *"What did you expect to see that wasn't here?"*
2. *"What did you see that you didn't expect to need?"*

The answers go straight into the next session's scope.
