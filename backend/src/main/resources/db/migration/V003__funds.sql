-- Funds movement: allocations + transfers + idempotency cache.
-- Expense aggregate follows in V004.

-- ------------------------------------------------------------------
-- allocations — Admin → Trip-pool, or Leader → Member, scoped to a Source.
-- from_user_id IS NULL means "from the admin pool of that source".
-- ------------------------------------------------------------------
CREATE TABLE allocations (
    id             UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    trip_id        UUID         NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
    from_user_id   UUID         REFERENCES users(id),
    to_user_id     UUID         NOT NULL REFERENCES users(id),
    source_id      UUID         NOT NULL REFERENCES sources(id),
    -- Per CLAUDE.md §6: minor units, currency denormalised from the trip.
    amount_minor   BIGINT       NOT NULL CHECK (amount_minor >= 0),
    currency       VARCHAR(3)   NOT NULL,
    status         VARCHAR(16)  NOT NULL,
    note           VARCHAR(500),
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    responded_at   TIMESTAMPTZ,
    CONSTRAINT ck_allocations_status
        CHECK (status IN ('PENDING', 'ACCEPTED', 'DECLINED'))
);

CREATE INDEX idx_alloc_trip       ON allocations(trip_id);
CREATE INDEX idx_alloc_to_user    ON allocations(to_user_id);
CREATE INDEX idx_alloc_from_user  ON allocations(from_user_id);

-- ------------------------------------------------------------------
-- transfers — peer-to-peer between trip participants. Same shape as
-- allocations but from_user_id is NOT NULL (CLAUDE.md §5).
-- ------------------------------------------------------------------
CREATE TABLE transfers (
    id            UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    trip_id       UUID         NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
    from_user_id  UUID         NOT NULL REFERENCES users(id),
    to_user_id    UUID         NOT NULL REFERENCES users(id),
    source_id     UUID         NOT NULL REFERENCES sources(id),
    amount_minor  BIGINT       NOT NULL CHECK (amount_minor > 0),
    currency      VARCHAR(3)   NOT NULL,
    status        VARCHAR(16)  NOT NULL,
    note          VARCHAR(500),
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    responded_at  TIMESTAMPTZ,
    CONSTRAINT ck_transfers_status
        CHECK (status IN ('PENDING', 'ACCEPTED', 'DECLINED')),
    CONSTRAINT ck_transfers_distinct_parties
        CHECK (from_user_id <> to_user_id)
);

CREATE INDEX idx_xfer_trip      ON transfers(trip_id);
CREATE INDEX idx_xfer_to_user   ON transfers(to_user_id);
CREATE INDEX idx_xfer_from_user ON transfers(from_user_id);

-- ------------------------------------------------------------------
-- idempotency_keys — caches the JSON response for a given
-- (Idempotency-Key, user, endpoint) tuple per CLAUDE.md §9.
-- Replays inside the 24h window return the cached body.
-- ------------------------------------------------------------------
CREATE TABLE idempotency_keys (
    id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    key             VARCHAR(128) NOT NULL,
    user_id         UUID         NOT NULL REFERENCES users(id),
    endpoint        VARCHAR(128) NOT NULL,
    response_status INTEGER      NOT NULL,
    response_body   JSONB        NOT NULL,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
    expires_at      TIMESTAMPTZ  NOT NULL,
    CONSTRAINT uq_idempotency UNIQUE (key, user_id, endpoint)
);

CREATE INDEX idx_idempotency_expires ON idempotency_keys(expires_at);
