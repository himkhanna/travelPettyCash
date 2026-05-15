-- Trip aggregate (CLAUDE.md §5) + funding sources reference table.
-- Expense / allocation / transfer tables follow in V003+.

-- ------------------------------------------------------------------
-- sources — reference data, seeded by DemoSourceSeeder
-- ------------------------------------------------------------------
CREATE TABLE sources (
    id        UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    name      VARCHAR(128) NOT NULL UNIQUE,
    name_ar   VARCHAR(128) NOT NULL,
    is_active BOOLEAN      NOT NULL DEFAULT TRUE
);

-- ------------------------------------------------------------------
-- trips
-- ------------------------------------------------------------------
CREATE TABLE trips (
    id                  UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    name                VARCHAR(128) NOT NULL,
    country_code        VARCHAR(2)   NOT NULL,
    country_name        VARCHAR(128) NOT NULL,
    currency            VARCHAR(3)   NOT NULL,
    status              VARCHAR(16)  NOT NULL,
    created_by_id       UUID         NOT NULL REFERENCES users(id),
    leader_id           UUID         NOT NULL REFERENCES users(id),
    -- CLAUDE.md §6: BIGINT minor units; never DOUBLE.
    total_budget_minor  BIGINT       NOT NULL,
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    closed_at           TIMESTAMPTZ,
    CONSTRAINT ck_trips_status
        CHECK (status IN ('DRAFT', 'ACTIVE', 'CLOSED'))
);

CREATE INDEX idx_trips_status     ON trips(status);
CREATE INDEX idx_trips_leader     ON trips(leader_id);

-- ------------------------------------------------------------------
-- trip_members — many-to-many between trips and users
-- ------------------------------------------------------------------
CREATE TABLE trip_members (
    trip_id UUID NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    PRIMARY KEY (trip_id, user_id)
);

CREATE INDEX idx_trip_members_user ON trip_members(user_id);
