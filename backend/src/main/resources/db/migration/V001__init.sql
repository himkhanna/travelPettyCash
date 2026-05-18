-- PDD Petty Cash — initial schema. See CLAUDE.md §5.
-- Money columns are BIGINT minor units; never DOUBLE / NUMERIC for amounts.

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================================
-- USERS
-- ============================================================================
CREATE TABLE app_user (
    id              UUID PRIMARY KEY,
    username        VARCHAR(64)  NOT NULL UNIQUE,
    display_name    VARCHAR(128) NOT NULL,
    display_name_ar VARCHAR(128) NOT NULL,
    email           VARCHAR(255) NOT NULL,
    role            VARCHAR(32)  NOT NULL,
    is_active       BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- ============================================================================
-- FUNDING SOURCES
-- ============================================================================
CREATE TABLE fund_source (
    id         UUID PRIMARY KEY,
    name       VARCHAR(128) NOT NULL,
    name_ar    VARCHAR(128) NOT NULL,
    is_active  BOOLEAN      NOT NULL DEFAULT TRUE
);

-- ============================================================================
-- EXPENSE CATEGORIES
-- ============================================================================
CREATE TABLE expense_category (
    id         UUID PRIMARY KEY,
    code       VARCHAR(32)  NOT NULL UNIQUE,
    name_en    VARCHAR(128) NOT NULL,
    name_ar    VARCHAR(128) NOT NULL,
    icon_key   VARCHAR(64)  NOT NULL,
    is_active  BOOLEAN      NOT NULL DEFAULT TRUE
);

-- ============================================================================
-- TRIPS
-- ============================================================================
CREATE TABLE trip (
    id                       UUID PRIMARY KEY,
    name                     VARCHAR(256) NOT NULL,
    country_code             VARCHAR(2)   NOT NULL,
    country_name             VARCHAR(128),
    currency                 VARCHAR(3)   NOT NULL,
    status                   VARCHAR(16)  NOT NULL,
    created_by               UUID         NOT NULL REFERENCES app_user(id),
    leader_id                UUID         NOT NULL REFERENCES app_user(id),
    total_budget_amount      BIGINT       NOT NULL,
    total_budget_currency    VARCHAR(3)   NOT NULL,
    image_url                VARCHAR(1024),
    created_at               TIMESTAMPTZ  NOT NULL DEFAULT now(),
    closed_at                TIMESTAMPTZ
);
CREATE INDEX idx_trip_status ON trip(status);
CREATE INDEX idx_trip_leader ON trip(leader_id);

CREATE TABLE trip_member (
    trip_id  UUID NOT NULL REFERENCES trip(id) ON DELETE CASCADE,
    user_id  UUID NOT NULL REFERENCES app_user(id),
    PRIMARY KEY (trip_id, user_id)
);
CREATE INDEX idx_trip_member_trip ON trip_member(trip_id);
CREATE INDEX idx_trip_member_user ON trip_member(user_id);

-- ============================================================================
-- EXPENSES
-- ============================================================================
CREATE TABLE expense (
    id                  UUID PRIMARY KEY,
    trip_id             UUID         NOT NULL REFERENCES trip(id),
    user_id             UUID         NOT NULL REFERENCES app_user(id),
    source_id           UUID         NOT NULL REFERENCES fund_source(id),
    category_id         UUID         NOT NULL REFERENCES expense_category(id),
    category_code       VARCHAR(32)  NOT NULL,
    amount              BIGINT       NOT NULL,
    currency            VARCHAR(3)   NOT NULL,
    quantity            INTEGER      NOT NULL DEFAULT 1,
    unit_cost_amount    BIGINT,
    details             VARCHAR(1024),
    occurred_at         TIMESTAMPTZ  NOT NULL,
    receipt_object_key  VARCHAR(512),
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    deleted_at          TIMESTAMPTZ
);
CREATE INDEX idx_expense_trip ON expense(trip_id);
CREATE INDEX idx_expense_user ON expense(user_id);
CREATE INDEX idx_expense_source ON expense(source_id);
CREATE INDEX idx_expense_occurred_at ON expense(occurred_at);

-- ============================================================================
-- ALLOCATIONS  (Admin → Trip pool OR Leader → Member)
-- ============================================================================
CREATE TABLE allocation (
    id            UUID PRIMARY KEY,
    trip_id       UUID         NOT NULL REFERENCES trip(id),
    from_user_id  UUID         REFERENCES app_user(id),  -- NULL for admin pool allocations
    to_user_id    UUID         NOT NULL REFERENCES app_user(id),
    source_id     UUID         NOT NULL REFERENCES fund_source(id),
    amount        BIGINT       NOT NULL,
    currency      VARCHAR(3)   NOT NULL,
    status        VARCHAR(16)  NOT NULL DEFAULT 'PENDING',
    note          VARCHAR(512),
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    responded_at  TIMESTAMPTZ
);
CREATE INDEX idx_allocation_trip ON allocation(trip_id);
CREATE INDEX idx_allocation_to_user ON allocation(to_user_id);
CREATE INDEX idx_allocation_source ON allocation(source_id);

-- ============================================================================
-- TRANSFERS  (peer-to-peer within a trip)
-- ============================================================================
CREATE TABLE fund_transfer (
    id            UUID PRIMARY KEY,
    trip_id       UUID         NOT NULL REFERENCES trip(id),
    from_user_id  UUID         NOT NULL REFERENCES app_user(id),
    to_user_id    UUID         NOT NULL REFERENCES app_user(id),
    source_id     UUID         NOT NULL REFERENCES fund_source(id),
    amount        BIGINT       NOT NULL,
    currency      VARCHAR(3)   NOT NULL,
    status        VARCHAR(16)  NOT NULL DEFAULT 'PENDING',
    note          VARCHAR(512),
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    responded_at  TIMESTAMPTZ
);
CREATE INDEX idx_transfer_trip ON fund_transfer(trip_id);
CREATE INDEX idx_transfer_from ON fund_transfer(from_user_id);
CREATE INDEX idx_transfer_to ON fund_transfer(to_user_id);
CREATE INDEX idx_transfer_source ON fund_transfer(source_id);

-- ============================================================================
-- CHAT
-- ============================================================================
CREATE TABLE chat_thread (
    id                   UUID PRIMARY KEY,
    trip_id              UUID         NOT NULL REFERENCES trip(id),
    title                VARCHAR(256),
    title_ar             VARCHAR(256),
    last_message_preview VARCHAR(512),
    last_message_at      TIMESTAMPTZ,
    created_at           TIMESTAMPTZ  NOT NULL DEFAULT now()
);
CREATE INDEX idx_chat_thread_trip ON chat_thread(trip_id);

CREATE TABLE chat_thread_participant (
    thread_id  UUID NOT NULL REFERENCES chat_thread(id) ON DELETE CASCADE,
    user_id    UUID NOT NULL REFERENCES app_user(id),
    PRIMARY KEY (thread_id, user_id)
);

CREATE TABLE chat_message (
    id            UUID PRIMARY KEY,
    thread_id     UUID         NOT NULL REFERENCES chat_thread(id) ON DELETE CASCADE,
    sender_id     UUID         NOT NULL REFERENCES app_user(id),
    body          VARCHAR(4096) NOT NULL,
    sent_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    delivered_at  TIMESTAMPTZ,
    read_at       TIMESTAMPTZ
);
CREATE INDEX idx_chat_message_thread ON chat_message(thread_id);
CREATE INDEX idx_chat_message_sent_at ON chat_message(sent_at);

-- ============================================================================
-- NOTIFICATIONS
-- ============================================================================
CREATE TABLE notification (
    id          UUID PRIMARY KEY,
    user_id     UUID         NOT NULL REFERENCES app_user(id),
    type        VARCHAR(32)  NOT NULL,
    payload     JSONB,
    actionable  BOOLEAN      NOT NULL DEFAULT FALSE,
    state       VARCHAR(16)  NOT NULL DEFAULT 'UNREAD',
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);
CREATE INDEX idx_notification_user ON notification(user_id);
CREATE INDEX idx_notification_created_at ON notification(created_at);

-- ============================================================================
-- AUDIT LOG  (append-only; hash-chained)
-- ============================================================================
CREATE TABLE audit_log (
    id            UUID PRIMARY KEY,
    entity_type   VARCHAR(64)  NOT NULL,
    entity_id     VARCHAR(64)  NOT NULL,
    actor_id      UUID,
    action        VARCHAR(64)  NOT NULL,
    before_state  JSONB,
    after_state   JSONB,
    at            TIMESTAMPTZ  NOT NULL DEFAULT now(),
    request_id    VARCHAR(64),
    hash_prev     VARCHAR(64)  NOT NULL,
    hash_self     VARCHAR(64)  NOT NULL
);
CREATE INDEX idx_audit_entity ON audit_log(entity_type, entity_id);
CREATE INDEX idx_audit_actor  ON audit_log(actor_id);
CREATE INDEX idx_audit_at     ON audit_log(at);

-- Production-only hardening — uncomment in the prod-only migration once an app DB role exists:
-- REVOKE UPDATE, DELETE ON audit_log FROM app_role;
