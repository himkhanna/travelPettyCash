-- Missions
--
-- A Mission groups multiple Trips under a single diplomatic / operational
-- objective. One Mission has many Trips; one Trip has zero-or-one Mission
-- (mission_id is nullable so existing trips don't break, and the trip-
-- create flow can offer "No mission" for ad-hoc work).
--
-- Missions can nest (`parent_mission_id`) — a top-level "State Visits Q1"
-- mission could have child missions like "Riyadh Engagement" that itself
-- has multiple trips. Nesting is left flat in the v1 UI; the column is here
-- so the data shape doesn't have to change later.

CREATE TABLE IF NOT EXISTS missions (
    id                  UUID         PRIMARY KEY,
    name                VARCHAR(160) NOT NULL,
    name_ar             VARCHAR(160),
    code                VARCHAR(32)  NOT NULL UNIQUE,
    description         VARCHAR(500),
    parent_mission_id   UUID         REFERENCES missions(id),
    status              VARCHAR(16)  NOT NULL DEFAULT 'ACTIVE',
    created_by_id       UUID         NOT NULL,
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    closed_at           TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS missions_parent_idx
    ON missions(parent_mission_id)
    WHERE parent_mission_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS missions_status_idx ON missions(status);

-- Trips ←→ Mission. Nullable to preserve existing rows; the create-trip
-- flow on the CMS now offers a required picker, but legacy trips remain
-- "(no mission)".
ALTER TABLE trips
    ADD COLUMN IF NOT EXISTS mission_id UUID REFERENCES missions(id);

CREATE INDEX IF NOT EXISTS trips_mission_idx
    ON trips(mission_id)
    WHERE mission_id IS NOT NULL;
