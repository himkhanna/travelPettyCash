-- V011 — external_id column on users for Dubai-Gov OIDC SSO.
--
-- ADR-001 (docs/architecture/ADR-001-dda-sso.md). New users
-- federated from Smart Dubai's OIDC IdP are keyed on the `sub`
-- claim from their ID token. Existing demo / local-login accounts
-- (khalid, fatima, layla, ahmed) keep external_id NULL — they sign
-- in with username + password, which stays available behind the
-- `pdd.auth.local-login.enabled` flag in dev.
--
-- The unique index is partial (WHERE NOT NULL) so multiple local
-- accounts can coexist with NULL external_id without clashing on
-- the constraint.

ALTER TABLE users
    ADD COLUMN external_id TEXT;

CREATE UNIQUE INDEX uq_users_external_id
    ON users(external_id)
    WHERE external_id IS NOT NULL;
