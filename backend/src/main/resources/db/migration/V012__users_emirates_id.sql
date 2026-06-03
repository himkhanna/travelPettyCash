-- V012 — emirates_id (Emirates ID / "idn") column on users.
--
-- ADR-002 (docs/architecture/ADR-002-uaepass-sso.md). UAE Pass returns
-- the holder's Emirates ID in the `idn` claim (for citizens/residents).
-- It is a stable, unique national identifier — a stronger link key than
-- email for federating a UAE Pass identity onto a pre-provisioned PDD
-- account. Stored here so we can (a) link UAE Pass sign-ins by Emirates
-- ID first, (b) pre-provision officers by Emirates ID, (c) surface it on
-- finance reports.
--
-- Nullable: existing accounts and visitor (no-Emirates-ID) UAE Pass users
-- have none. The unique index is partial (WHERE NOT NULL) so the many
-- NULLs don't clash.

ALTER TABLE users
    ADD COLUMN emirates_id TEXT;

CREATE UNIQUE INDEX uq_users_emirates_id
    ON users(emirates_id)
    WHERE emirates_id IS NOT NULL;
