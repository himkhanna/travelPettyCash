# ADR-002 — UAE Pass OIDC SSO integration

- **Status:** Proposed (2026-06-02)
- **Supersedes / relates to:** [[ADR-001-dda-sso]] (Dubai-Gov / Smart Dubai OIDC). UAE Pass
  is a *second, parallel* identity provider, not a replacement.
- **Closes:** the "UAE Pass integration: required for v1 or post-launch?" open question in
  CLAUDE.md §16 — now directed in.

## Context

CLAUDE.md §3 anticipates "integration with UAE Pass if PDD mandates it." UAE Pass (operated
by TDRA) is the UAE national digital identity — an OAuth2 / OIDC Authorization-Code provider.
We already built the Dubai-Gov OIDC plumbing (ADR-001); UAE Pass reuses ~80% of that shape:
`start → IdP → callback → token exchange → userinfo → upsert/link → mint our JWTs → SPA
exchange`. This ADR records the UAE-Pass-specific decisions.

## Decisions

1. **Environment: staging sandbox first.** Build + verify against UAE Pass's public staging
   sandbox; real staging/prod client credentials (issued by TDRA after onboarding) slot in via
   env vars later. Feature-flagged **off** by default (`PDD_UAEPASS_ENABLED=false`); the
   `/auth/sso/uaepass/*` endpoints 404 until flipped, exactly like Dubai-Gov.

2. **Role source: link to an existing PDD account; reject unknown.** UAE Pass returns
   *identity* (Emirates ID, name, email) but **no app role** — unlike Dubai-Gov's `groups`
   claim. So a UAE Pass sign-in must resolve to a pre-provisioned PDD user:
   - match `users.external_id == "uaepass|" + uuid` (returning federated user); else
   - match `users.email` (case-insensitive) to the UAE-Pass-asserted `email`, and on hit
     **link** (set `external_id`), keeping the user's existing PDD role; else
   - **reject** with `403 auth/sso-no-account` — UAE Pass authenticated them, but they're not
     a PDD user. (Closed set of protocol officers; we do not auto-provision.)

   The role always comes from the *local* account, never from UAE Pass.

3. **Coexists with Dubai-Gov, side by side.** The login screen shows password + "Sign in with
   Dubai Gov" + "Sign in with UAE Pass", each behind its own probe flag in `/auth/config`.

4. **PWA-only web flow (CLAUDE.md §15).** We use the web redirect flow with
   `acr_values=urn:safelayer:tws:policies:authentication:level:low`. The native app-to-app
   flow (`acr_values=urn:digitalid:authentication:flow:mobileondevice`) is deferred to the v2
   native build, same as ADR-001's native deep-link slice.

## Verified sandbox technical contract

| Item | Value |
|---|---|
| Authorize | `https://stg-id.uaepass.ae/idshub/authorize` |
| Token | `https://stg-id.uaepass.ae/idshub/token` |
| Userinfo | `https://stg-id.uaepass.ae/idshub/userinfo` |
| Logout | `https://stg-id.uaepass.ae/idshub/logout` |
| Sandbox client_id / secret | `sandbox_stage` / `sandbox_stage` |
| Scope | `urn:uae:digitalid:profile:general` |
| acr_values (web) | `urn:safelayer:tws:policies:authentication:level:low` |
| Token auth | HTTP Basic — `Authorization: Basic base64(client_id:secret)`, POST form `grant_type=authorization_code&code=…&redirect_uri=…` |
| Userinfo auth | `Authorization: Bearer <access_token>` (back-channel) |

**Userinfo claims** (SOP3 returns ~18; SOP1 a subset): `sub` (format `UAEPASS/{uuid}`),
`uuid`, `userType` (SOP1/2/3), `idn` (Emirates ID — **absent for visitors**), `email`,
`mobile`, `fullnameEN` / `fullnameAR` (SOP3), `firstnameEN`/`firstnameAR`,
`lastnameEN`/`lastnameAR`, `idType`, `nationalityEN`, `gender`, `titleEN`.

- **Stable identifier** for `external_id`: `uuid` (carried in `sub` as `UAEPASS/{uuid}`).
  `idn` is a good *secondary* link key but is absent for visitor accounts, so email is the
  primary fallback link.
- **Display name:** `fullnameEN` if present (SOP3), else `firstnameEN + ' ' + lastnameEN`.

Sources:
- [Conduct a POC — UAE PASS staging](https://docs.uaepass.ae/quick-start-guide-uae-pass-staging-environment/conduct-a-poc-with-uae-pass-authentication)
- [Attributes List — UAE PASS](https://docs.uaepass.ae/resources/attributes-list)
- [Obtaining authenticated user information](https://docs.uaepass.ae/guides/authentication/web-application/3.-obtaining-authenticated-user-information-from-the-access-token)

## Implementation plan (slices)

| # | Slice | Notes |
|---|---|---|
| A | Backend OIDC plumbing | `UaePassProperties`, `UaePassSsoService` (Auth-Code + Basic-auth token, link-or-reject), `UaePassController` (`/api/v1/auth/sso/uaepass/{start,callback,exchange,logout-url}`), `/auth/config` gains `sso.uaepass.enabled`. Feature-flagged off. |
| B | Mobile UI | "Sign in with UAE Pass" button on LoginScreen (probe-gated), `SsoCallbackScreen` parameterised by provider, callback routes `/app/auth/uaepass/callback` + `/portal/auth/uaepass/callback`. |
| C | Tests | Unit (`startUrl` shape, link-or-reject paths, disabled→404) + slice (controller) + IT. |
| D | Real-tenant onboarding | TDRA staging/prod client registration, redirect-URI whitelisting, real acr levels. **External dependency.** |

## Notes / risks

- **`external_id` collision with Dubai-Gov.** It's a single column. A user who federates via
  *both* IdPs flip-flops `external_id` (each link overwrites). The stable join is **email**, so
  re-login always works via the email fallback even after a flip. If dual-federation becomes
  common, split into a `user_external_identity(provider, external_id)` table — out of scope now.
- **Sandbox testing needs a UAE Pass staging test account** whose email is provisioned as a PDD
  user (so the link succeeds). Until one exists, the flow is verifiable up to userinfo; the
  link step is covered by unit/IT tests with stubbed claims.
- **Logout:** UAE Pass exposes `/idshub/logout`; `logout-url` returns it, same pattern as
  ADR-001's SAML SLO.
