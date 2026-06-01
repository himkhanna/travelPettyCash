# ADR-001 — Integrate login with Dubai Gov OIDC (Smart Dubai IdP)

| Field | Value |
|---|---|
| **Status** | Proposed (2026-05-31). Demo-tenant credentials received; implementation green-lit for Slice A. |
| **Owner** | Eng + PDD IT. |
| **Closes** | CLAUDE.md §16 — "Production identity provider". |
| **Affects** | `backend/auth`, `mobile/lib/features/auth`, `mobile/lib/features/cms`, `ops/`. |

## Provider — Smart Dubai OIDC (demo tenant)

Internally referred to as "DDA SSO" but the actual provider name is
**Smart Dubai's `smartdubaioidcp`** running on IBM ISAM, the
Dubai-government shared identity stack.

| Endpoint | URL |
|---|---|
| Discovery (metadata) | `https://demoidp.dubai.gov.ae/mga/sps/oauth/oauth20/metadata/smartdubaioidcp` |
| Issuer | `https://demoidp.dubai.gov.ae` |
| Authorization | `https://demoidp.dubai.gov.ae/mga/sps/oauth/oauth20/authorize` |
| Token | `https://demoidp.dubai.gov.ae/mga/sps/oauth/oauth20/token` |
| Userinfo | `https://demoidp.dubai.gov.ae/mga/sps/oauth/oauth20/userinfo` |
| JWKS | `https://demoidp.dubai.gov.ae/mga/sps/oauth/oauth20/jwks/smartdubaioidcp` |
| Introspect | `https://demoidp.dubai.gov.ae/mga/sps/oauth/oauth20/introspect` |
| Revoke | `https://demoidp.dubai.gov.ae/mga/sps/oauth/oauth20/revoke` |
| Logout (SAML SLO) | `https://demoidp.dubai.gov.ae/isam/sps/idpdubaigov/saml20/sloinitial` |

Notes from the discovery doc:

- Grants: `authorization_code` + `refresh_token`. **No
  `client_credentials`**, **no implicit** (good — modern).
- Response types: `code`, `none`. Auth Code + PKCE on our side.
- ID-token signing: **RS256 only**. We cache the JWKS and validate.
- **No `end_session_endpoint`** in the OIDC discovery. The
  provider hands us a SAML 2.0 SLO URL instead. Logout therefore
  means: clear our local session, then browser-redirect to the
  SAML SLO URL. Users not already federated via SAML in the same
  browser see no visible IdP logout — that's an IdP limitation,
  documented for the support team.
- `scopes_supported` is not in the metadata. We start with the
  three standard OIDC scopes (`openid`, `profile`, `email`) and
  whatever role-claim scope DDA grants us once it's defined.

## Credentials — handling

The `client_id` and `client_secret` issued for this app **do not go
in source**. They are read at runtime from environment variables
(per CLAUDE.md §12):

| Env var | Maps to |
|---|---|
| `PDD_SMARTDUBAI_CLIENT_ID` | `spring.security.oauth2.client.registration.dubaigov.client-id` |
| `PDD_SMARTDUBAI_CLIENT_SECRET` | `spring.security.oauth2.client.registration.dubaigov.client-secret` |

For local dev: the secret sits in `backend/.env` (gitignored). For
prod / staging on Moro Hub: HashiCorp Vault or the platform's
secret manager.

## Context

The app currently authenticates via local username + password (the
demo accounts `khalid`, `fatima`, `layla`, `ahmed`). For production at
the Protocol Department, every user needs to authenticate against
**Dubai Digital Authority's SSO** (DDA) — the identity stack that
covers Dubai government employees. CLAUDE.md §16 has tracked this as
an open question since the initial scope.

## Decision

Integrate **DDA SSO via OIDC Authorization Code with PKCE**, with
roles read from a DDA claim, local username/password retained behind a
feature flag for dev, and the public token contract (15-min JWT
access + 30-day refresh) preserved so the rest of the app doesn't
change shape.

### Decisions locked

1. **Role mapping comes from a DDA claim** — most likely `groups` or a
   bespoke `pdd_role` claim configured by DDA's directory team. The
   backend maps the claim value to `UserRole` (MEMBER / LEADER /
   ADMIN / SUPER_ADMIN) at login time. Rejected: an internal mapping
   table managed by Admin in the CMS (more flexible but needs a UI
   slice we don't want to block on). Rejected: default-to-MEMBER
   plus manual promotion (too much manual operations toil for a 100+
   user rollout).
2. **Local username/password stays on in dev, off in prod**, gated by
   `pdd.auth.local-login.enabled`. Demo accounts keep working through
   the dev/test lifecycle. Production deployments set the flag to
   `false`, so every authentication funnels through DDA.
3. **Implementation green-lit for Slice A.** Demo-tenant
   `client_id` + `client_secret` and the discovery URL are in hand
   (2026-05-31). Code starts against the demo tenant; prod credentials
   land in env vars at deploy time without code changes.

### Out of scope for this ADR

- UAE Pass federal SSO (separate IdP, separate PR if requested).
- Multi-factor enforcement on the IdP side — DDA owns that.
- Session sharing across PDD apps (would need cross-app cookie/SSO
  session policy from DDA).

## Still to confirm with DDA

The discovery doc and credentials cover most of the wiring, but a few
items still need confirmation from DDA before prod go-live:

1. **Production tenant URL.** `demoidp.dubai.gov.ae` is the demo
   environment. The prod issuer is presumed
   `https://idp.dubai.gov.ae` (same path layout) but needs explicit
   confirmation + a separate `client_id` / `client_secret` pair for
   prod.
2. **Allowed redirect URIs registered against our client.** We need
   DDA to whitelist:
   - `http://localhost:8080/api/v1/auth/sso/callback` (dev)
   - `http://127.0.0.1:8080/api/v1/auth/sso/callback` (dev)
   - `https://<staging-portal-host>/api/v1/auth/sso/callback` (staging)
   - `https://<prod-portal-host>/api/v1/auth/sso/callback` (prod)
   - `ae.gov.pdd.pettycash://auth/callback` (mobile native)

   The native scheme one is the tricky one — some IdP teams won't
   whitelist a custom-scheme deep link and require a universal /
   app-link HTTPS URL. If they push back, we fall back to a
   webview-only flow on native.
3. **Scope name that returns the role claim.** Standard
   `openid` + `profile` + `email` are assumed available. Need DDA to
   confirm the scope that grants `groups` (or whatever they call the
   role claim — see below).
4. **Role claim name + values.** DDA must commit to either
   `groups` or a bespoke claim like `pdd_role` containing string
   values we map to UserRole. Currently planned mapping:
   `pdd.delegation-expenses.super-admin` → SUPER_ADMIN, …
   The string format will shift once we see the first ID token.
5. **Userinfo claim format.** Need DDA to confirm whether the
   user's stable identifier sits in `sub` (standard) or a custom
   claim like `emp_id`. The DB column `users.external_id` keys on
   whatever they choose.
6. **Refresh-token TTL.** Default Spring behaviour caches +
   auto-refreshes, but knowing the TTL helps us tune our own
   refresh schedule.

## Architecture

### Backend

- **Dependencies** —
  `spring-boot-starter-oauth2-client` +
  `spring-boot-starter-oauth2-resource-server` (the latter is already
  partially in for our own JWT validation).
- **Config** — `application-local.yml` (demo tenant) +
  `application-prod.yml` (prod tenant, when issued):
  ```yaml
  spring:
    security:
      oauth2:
        client:
          registration:
            dubaigov:
              client-id: ${PDD_SMARTDUBAI_CLIENT_ID}
              client-secret: ${PDD_SMARTDUBAI_CLIENT_SECRET}
              scope: openid,profile,email
              authorization-grant-type: authorization_code
              redirect-uri: '{baseUrl}/api/v1/auth/sso/callback'
              client-authentication-method: client_secret_basic
          provider:
            dubaigov:
              # Use the explicit endpoints rather than issuer-uri because
              # the IdP exposes its metadata at a non-standard path
              # (/mga/sps/oauth/oauth20/metadata/<provider>) that Spring's
              # default discovery probe won't find.
              authorization-uri: https://demoidp.dubai.gov.ae/mga/sps/oauth/oauth20/authorize
              token-uri: https://demoidp.dubai.gov.ae/mga/sps/oauth/oauth20/token
              user-info-uri: https://demoidp.dubai.gov.ae/mga/sps/oauth/oauth20/userinfo
              jwk-set-uri: https://demoidp.dubai.gov.ae/mga/sps/oauth/oauth20/jwks/smartdubaioidcp
              user-name-attribute: sub
  pdd:
    auth:
      local-login:
        enabled: false                # demo accounts off in prod
      dubaigov:
        enabled: true                 # feature flag; off by default outside dev
        saml-slo-uri: https://demoidp.dubai.gov.ae/isam/sps/idpdubaigov/saml20/sloinitial
        role-claim: groups            # configurable so DDA can change
                                      # the claim name without a redeploy
        role-mapping:
          'pdd.delegation-expenses.super-admin': SUPER_ADMIN
          'pdd.delegation-expenses.admin':       ADMIN
          'pdd.delegation-expenses.leader':      LEADER
          'pdd.delegation-expenses.member':      MEMBER
        default-role: MEMBER          # safety net if no group matches
  ```
- **New endpoints** under `backend/.../auth/SsoController.java`:
  - `GET /api/v1/auth/sso/start?audience=mobileApp|webAdmin` —
    kicks off the OIDC flow with PKCE. 302 to the Dubai-Gov
    authorize URL. `audience` is round-tripped through the OIDC
    `state` so the callback knows which client to hand the JWTs
    back to.
  - `GET /api/v1/auth/sso/callback?code=...&state=...` — exchanges
    the code, fetches userinfo, upserts the User row (keyed on
    `sub`), maps the role claim, mints our own access + refresh
    JWTs. Web audience: 302 to `/app/auth/callback?code=<one-time>`
    so the Flutter Web bundle can exchange the one-time code for
    the JWTs. Native audience: 302 to
    `ae.gov.pdd.pettycash://auth/callback?code=<one-time>` so the
    OS deep-link handler picks it up.
  - `POST /api/v1/auth/sso/exchange` — accepts the one-time code
    emitted by the callback, returns the JWT pair. Lets the
    Flutter bundle avoid handling OIDC state in-process.
  - `POST /api/v1/auth/logout` (existing endpoint) — extended to
    also issue a `302` back to the Dubai-Gov SAML SLO URL when
    the user signed in via SSO. The mobile client's
    `confirmAndSignOut` handler chases that redirect in a browser
    tab so the IdP session ends too.
- **Migration `V011__users_external_id.sql`** — new column
  `external_id TEXT UNIQUE` on `users`, indexed. Backfilled to NULL
  for demo accounts. The upsert path: `findByExternalId(sub)
  .orElseGet(() -> insertNew(claims))`.
- **Role mapping logic** — `DdaRoleMapper` reads the
  `pdd.auth.dda.role-mapping` config and resolves the highest-
  privilege match in the claim's value list (a user in both
  `pdd.delegation-expenses.admin` and `pdd.delegation-expenses.member`
  lands as ADMIN). Falls back to `default-role` on no-match.
- **Token contract preserved** — the rest of the backend keeps
  consuming the same JWT shape it does today. No downstream change.

### Mobile (`mobile/lib/features/auth/`)

- **`LoginScreen` gains a "Sign in with DDA" button.** Tapping it
  opens the platform browser at
  `<API_BASE>/api/v1/auth/sso/dda/start?audience=mobileApp|webAdmin`.
  The local username/password form stays visible while
  `pdd.auth.local-login.enabled` is on (the backend tells the mobile
  via a `/api/v1/auth/config` endpoint we'll add).
- **Web callback** — same origin as the bundle. The callback page
  reads the one-time code from the query, calls
  `POST /auth/sso/dda/exchange`, stores the JWTs via the existing
  `tokenStoreProvider`, and routes to `/m/trips` or `/cms` based on
  audience.
- **Native deep link** — register `ae.gov.pdd.pettycash://auth/callback`
  in `ios/Runner/Info.plist` (`CFBundleURLSchemes`) and
  `android/app/src/main/AndroidManifest.xml` (`<intent-filter>` with
  `android:scheme`). Use the `app_links` package (new pubspec dep) to
  capture the inbound URL and run the same exchange flow.

### CMS portal (`/portal`)

- Same "Sign in with DDA" button on the `/portal` login surface.
- The existing portal-mismatch guard handles the case where a DDA
  user's mapped role doesn't match the portal they hit.

## Slice plan

| # | Slice | Effort | Notes |
|---|---|---|---|
| A | Backend OIDC plumbing | 3–4 days | Config + `start` + `callback` + user upsert + role mapping. Feature flag `pdd.auth.dda.enabled` so it's off until DDA tenant lands. |
| B | V011 migration | 0.5 day | `users.external_id`. Lands with slice A. |
| C | Web SSO flow | 1–2 days | LoginScreen button + `/auth/callback` handler + exchange. Web first because no platform code. |
| D | Native deep link | 2–3 days | `app_links` dep + iOS/Android manifest entries + handler. Test on a TestFlight + Play Internal build. |
| E | Backend `/auth/config` + mobile `local-login.enabled` honouring | 0.5 day | So the username/password form hides automatically in prod. |
| F | RP-Initiated Logout | 1 day | If DDA supports it. Otherwise document the local-only logout. |
| G | Tests | 2 days | Slice + integration tests against either WireMock or a Spring Authorization Server local provider. |

Total: roughly two engineering weeks once DDA credentials arrive.

## Risks + mitigations

| Risk | Mitigation |
|---|---|
| DDA changes the claim name post-go-live | The `pdd.auth.dda.role-claim` config makes it a one-line change, no redeploy of bytecode. |
| First user lands without any role group | `default-role: MEMBER` so they at least see their own surface; admin promotes via a future internal-mapping override. |
| DDA sandbox unavailable for dev | Slice A still ships with a mock OIDC provider (Spring Authorization Server in test mode) — only the discovery URL changes for prod. |
| Demo accounts leak into prod | `pdd.auth.local-login.enabled=false` enforced in `application-prod.yml`; CI gate on the prod yaml file. |
| Mobile deep-link conflict on a shared install | `ae.gov.pdd.pettycash://` is unique to this app; no observed collisions in the Dubai-gov mobile portfolio. |

## Status update path

This ADR is the single source of truth until implementation starts.
When DDA credentials arrive, the implementer updates **Status** at the
top of the file to "Accepted (YYYY-MM-DD)", references the kickoff PR,
and §16 of CLAUDE.md flips this question from open to closed with a
pointer here.

## Implementation log

### 2026-06-01 — demo-tenant smoke test, `/start` fix, mock IdP, tests

First end-to-end attempt against the real demo tenant with the
in-hand `client_id` / `client_secret`:

- **`/start` was 500ing** — `DubaiGovSsoService.startUrl()` built the
  authorize URL with `UriComponentsBuilder.build(true)` (= "values are
  pre-encoded"), but the `scope` value carries literal spaces
  (`openid profile email`), which are illegal in an encoded URI →
  `IllegalArgumentException`. Fixed by switching to `.encode().build()`
  so the builder encodes the values (`scope=openid%20profile%20email`).
  This benefits the real-tenant path, not just the mock. Regression
  guard: `DubaiGovSsoServiceTest.startUrlPercentEncodesTheScopeSpaces`.
- **Demo tenant rejects our redirect URI** —
  `FBTOAU210E … redirection URI … invalid`. This is the
  pre-authentication `redirect_uri`-vs-registered-client check (item 2
  of "Still to confirm with DDA" above): the demo tenant has **not**
  whitelisted `http://localhost:8080/api/v1/auth/sso/callback` for our
  client, so the IdP refuses before ever prompting for credentials.
  Still blocked on DDA registering our dev/staging/prod callback URIs.

- **Interim dev mock IdP (replaces the planned WireMock / Spring
  Authorization Server in the slice plan).** Rather than stand up an
  external fake, `MockIdpController` + `MockIdpReconfig` implement an
  in-process Authorization-Code provider, gated behind
  `pdd.auth.dubaigov.mock-idp=true` (off by default, never in
  staging/prod). When on, the authorize/token/userinfo URIs are
  repointed at the local controller, so `DubaiGovSsoService` runs its
  **real** code path against the fake — the only thing faked is the
  IdP's HTTP responses. The `/authorize` endpoint renders a role
  picker (standing in for the credential prompt) so the full
  start → authorize → approve → callback → exchange → `/me` sequence
  works without DDA. Switch back to the real tenant with
  `PDD_SMARTDUBAI_MOCK_IDP=false`.

- **Slice G (tests) — done.** Closes the §13 gap for this module:
  - `DubaiGovSsoServiceTest` (unit) — authorize-URL construction +
    PKCE, scope-encoding regression, enabled/disabled gate, unknown
    state / exchange-code rejection.
  - `SsoControllerTest` + `AuthConfigControllerTest` (slice,
    standalone MockMvc) — audience mapping, redirects, exchange/JSON
    bodies, problem-detail on disabled, the boot-probe flags.
  - `DubaiGovSsoIT` (`@SpringBootTest` + Testcontainers, real port)
    — full flow through the mock IdP per role, real token/userinfo
    HTTP legs, V011 `external_id` upsert (incl. no-duplicate on
    re-login), and the minted JWT authorizing `/me`. Skips locally
    under the repo-standard `@EnabledIf(dockerReachable)` guard; runs
    on CI.

Still open before prod: items 1–6 of "Still to confirm with DDA"
(especially the redirect-URI whitelist and the real role-claim
contract), plus Slices D/E/F.
