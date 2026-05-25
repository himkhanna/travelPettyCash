-- Scheduled report deliveries
--
-- Admin creates a schedule for either a trip or a mission, picks a UTC
-- hour-of-day to run at, and the platform emits a REPORT_READY
-- notification at the next due tick. Generation itself stays on-demand
-- — the notification carries enough payload (scope, scopeId, date) for
-- the existing /api/v1/reports/... download endpoints to render fresh
-- bytes when the recipient clicks through. Bytes are never persisted
-- here: the notification is the durable artifact.

CREATE TABLE IF NOT EXISTS report_schedules (
    id              UUID         PRIMARY KEY,
    -- Owning scope. TRIP fires /reports/trip/{id}/daily, MISSION fires
    -- /reports/mission/{id}.
    scope           VARCHAR(16)  NOT NULL CHECK (scope IN ('TRIP', 'MISSION')),
    scope_id        UUID         NOT NULL,
    -- Cadence kind. Only DAILY for v1; WEEKLY / MONTHLY land later.
    kind            VARCHAR(32)  NOT NULL CHECK (kind IN ('DAILY')),
    -- Hour-of-day to fire at, expressed in UTC so DST never shifts
    -- when the report lands.
    utc_hour        SMALLINT     NOT NULL CHECK (utc_hour BETWEEN 0 AND 23),
    active          BOOLEAN      NOT NULL DEFAULT TRUE,
    created_by_id   UUID         NOT NULL,
    last_run_at     TIMESTAMPTZ,
    next_run_at     TIMESTAMPTZ  NOT NULL,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- The runner polls every few minutes for due schedules; this index
-- keeps that scan fast as the schedules table grows.
CREATE INDEX IF NOT EXISTS report_schedules_due_idx
    ON report_schedules(next_run_at)
    WHERE active = TRUE;
