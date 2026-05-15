-- PDD Petty Cash — Phase 1 schema (auth slice only).
-- Subsequent migrations add trip / expense / fund / category tables.
--
-- Conventions per CLAUDE.md:
--   §5  Names from the domain model are used verbatim.
--   §6  Money columns will live on later tables as BIGINT minor units.
--   §12 The audit_log table is added in V0xx before any financial mutation
--       endpoint is exposed.

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ------------------------------------------------------------------
-- users
-- ------------------------------------------------------------------
CREATE TABLE users (
    id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    username        VARCHAR(64)  NOT NULL UNIQUE,
    display_name    VARCHAR(128) NOT NULL,
    display_name_ar VARCHAR(128) NOT NULL,
    email           VARCHAR(255) NOT NULL UNIQUE,
    password_hash   VARCHAR(255) NOT NULL,
    role            VARCHAR(16)  NOT NULL,
    is_active       BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT ck_users_role
        CHECK (role IN ('MEMBER', 'LEADER', 'ADMIN', 'SUPER_ADMIN'))
);

CREATE INDEX idx_users_active_role ON users(role) WHERE is_active = TRUE;

-- ------------------------------------------------------------------
-- refresh_tokens (opaque, hashed)
-- ------------------------------------------------------------------
-- token_hash is sha256(opaque_token) — we never store the raw token.
-- Rotation policy: on every /auth/refresh the row is marked rotated_at and a
-- replaces_id pointer is created. Re-using a rotated token is treated as a
-- compromise and revokes the whole chain (handled in AuthService).
CREATE TABLE refresh_tokens (
    id           UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash   VARCHAR(128) NOT NULL UNIQUE,
    issued_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    expires_at   TIMESTAMPTZ  NOT NULL,
    rotated_at   TIMESTAMPTZ,
    revoked_at   TIMESTAMPTZ,
    replaces_id  UUID         REFERENCES refresh_tokens(id) ON DELETE SET NULL,
    user_agent   VARCHAR(255),
    ip           INET
);

CREATE INDEX idx_refresh_tokens_user_id  ON refresh_tokens(user_id);
CREATE INDEX idx_refresh_tokens_expires  ON refresh_tokens(expires_at);
