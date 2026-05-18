-- Idempotency-Key persistence (CLAUDE.md §9). Records retained for 24h
-- per API contract; operational retention sweep is left to a scheduled
-- job (see TODO on IdempotencyRecord entity).
CREATE TABLE idempotency_record (
    key            VARCHAR(80)  NOT NULL,
    actor_id       UUID         NOT NULL,
    request_hash   CHAR(64)     NOT NULL,
    response_body  JSONB,
    status_code    INTEGER      NOT NULL,
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    PRIMARY KEY (key, actor_id)
);
CREATE INDEX idx_idempotency_record_created_at ON idempotency_record(created_at);
