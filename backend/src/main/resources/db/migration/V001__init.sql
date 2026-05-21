-- PDD Petty Cash — initial schema. All money is BIGINT minor units per
-- CLAUDE.md §6. UUIDs are stored as TEXT (driver-friendly across H2/PG).

CREATE TABLE users (
    id              TEXT PRIMARY KEY,
    username        TEXT NOT NULL UNIQUE,
    display_name    TEXT NOT NULL,
    display_name_ar TEXT NOT NULL,
    email           TEXT NOT NULL UNIQUE,
    role            TEXT NOT NULL CHECK (role IN ('MEMBER','LEADER','ADMIN','SUPER_ADMIN')),
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE TABLE sources (
    id        TEXT PRIMARY KEY,
    name      TEXT NOT NULL,
    name_ar   TEXT NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE expense_categories (
    id        TEXT PRIMARY KEY,
    code      TEXT NOT NULL UNIQUE,
    name_en   TEXT NOT NULL,
    name_ar   TEXT NOT NULL,
    icon_key  TEXT NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE trips (
    id            TEXT PRIMARY KEY,
    name          TEXT NOT NULL,
    country_code  TEXT NOT NULL,
    country_name  TEXT NOT NULL,
    currency      TEXT NOT NULL,
    status        TEXT NOT NULL CHECK (status IN ('DRAFT','ACTIVE','CLOSED')),
    created_by    TEXT NOT NULL REFERENCES users(id),
    leader_id     TEXT NOT NULL REFERENCES users(id),
    total_budget_minor BIGINT NOT NULL DEFAULT 0,
    created_at    TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    closed_at     TIMESTAMP WITH TIME ZONE
);

CREATE TABLE trip_members (
    trip_id TEXT NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
    user_id TEXT NOT NULL REFERENCES users(id),
    PRIMARY KEY (trip_id, user_id)
);

CREATE TABLE allocations (
    id            TEXT PRIMARY KEY,
    trip_id       TEXT NOT NULL REFERENCES trips(id),
    from_user_id  TEXT REFERENCES users(id),
    to_user_id    TEXT NOT NULL REFERENCES users(id),
    source_id     TEXT NOT NULL REFERENCES sources(id),
    amount_minor  BIGINT NOT NULL,
    currency      TEXT NOT NULL,
    status        TEXT NOT NULL CHECK (status IN ('PENDING','ACCEPTED','DECLINED')),
    note          TEXT,
    created_at    TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    responded_at  TIMESTAMP WITH TIME ZONE
);

CREATE TABLE transfers (
    id            TEXT PRIMARY KEY,
    trip_id       TEXT NOT NULL REFERENCES trips(id),
    from_user_id  TEXT NOT NULL REFERENCES users(id),
    to_user_id    TEXT NOT NULL REFERENCES users(id),
    source_id     TEXT NOT NULL REFERENCES sources(id),
    amount_minor  BIGINT NOT NULL,
    currency      TEXT NOT NULL,
    status        TEXT NOT NULL CHECK (status IN ('PENDING','ACCEPTED','DECLINED')),
    note          TEXT,
    created_at    TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    responded_at  TIMESTAMP WITH TIME ZONE
);

CREATE TABLE expenses (
    id                  TEXT PRIMARY KEY,
    trip_id             TEXT NOT NULL REFERENCES trips(id),
    user_id             TEXT NOT NULL REFERENCES users(id),
    source_id           TEXT NOT NULL REFERENCES sources(id),
    category_code       TEXT NOT NULL REFERENCES expense_categories(code),
    amount_minor        BIGINT NOT NULL,
    currency            TEXT NOT NULL,
    quantity            INTEGER NOT NULL DEFAULT 1,
    details             TEXT NOT NULL DEFAULT '',
    occurred_at         TIMESTAMP WITH TIME ZONE NOT NULL,
    receipt_object_key  TEXT,
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    deleted_at          TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_expenses_trip ON expenses (trip_id);
CREATE INDEX idx_expenses_user ON expenses (user_id);
CREATE INDEX idx_allocations_trip ON allocations (trip_id);
CREATE INDEX idx_transfers_trip ON transfers (trip_id);
