-- Expense aggregate (CLAUDE.md §5) + reference categories.

-- ------------------------------------------------------------------
-- expense_categories — reference data, soft-deletable.
-- Codes are stable (FOOD / TRANSPORT / etc.) so reports + analytics
-- can group across renames. New categories addable by Admin.
-- ------------------------------------------------------------------
CREATE TABLE expense_categories (
    id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    code        VARCHAR(32)  NOT NULL UNIQUE,
    name_en     VARCHAR(64)  NOT NULL,
    name_ar     VARCHAR(64)  NOT NULL,
    icon_key    VARCHAR(32)  NOT NULL,
    is_active   BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    deleted_at  TIMESTAMPTZ
);

CREATE INDEX idx_categories_active ON expense_categories(code) WHERE is_active = TRUE;

-- ------------------------------------------------------------------
-- expenses — CLAUDE.md §5. Client supplies UUID per §11 offline rules
-- (so the local Drift queue's row id IS the canonical id once it lands).
-- ------------------------------------------------------------------
CREATE TABLE expenses (
    id                  UUID         PRIMARY KEY,  -- supplied by client
    trip_id             UUID         NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
    user_id             UUID         NOT NULL REFERENCES users(id),
    source_id           UUID         NOT NULL REFERENCES sources(id),
    category_code       VARCHAR(32)  NOT NULL REFERENCES expense_categories(code),
    amount_minor        BIGINT       NOT NULL,
    -- Currency denormalised from trip per CLAUDE.md §5/§6.
    currency            VARCHAR(3)   NOT NULL,
    quantity            INTEGER      NOT NULL DEFAULT 1 CHECK (quantity >= 1),
    details             VARCHAR(500) NOT NULL DEFAULT '',
    occurred_at         TIMESTAMPTZ  NOT NULL,
    receipt_object_key  VARCHAR(256),
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ,
    deleted_at          TIMESTAMPTZ
);

-- Hot read path: list expenses for a trip (optionally filtered by user) in
-- chronological order. Partial index excludes soft-deleted rows so the
-- common "list active expenses" query touches fewer pages.
CREATE INDEX idx_expenses_trip_user
    ON expenses(trip_id, user_id, occurred_at DESC)
    WHERE deleted_at IS NULL;
CREATE INDEX idx_expenses_trip_source
    ON expenses(trip_id, source_id)
    WHERE deleted_at IS NULL;
CREATE INDEX idx_expenses_trip_category
    ON expenses(trip_id, category_code)
    WHERE deleted_at IS NULL;
