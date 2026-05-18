-- Report record — see CLAUDE.md §10. One row per generated report; the actual
-- bytes live in MinIO under the object_key. SHA-256 is captured for audit /
-- future signature verification.
CREATE TABLE report_record (
    id            UUID         PRIMARY KEY,
    trip_id       UUID         NOT NULL REFERENCES trip(id),
    type          VARCHAR(16)  NOT NULL,
    format        VARCHAR(8)   NOT NULL,
    scope_user_id UUID         REFERENCES app_user(id),
    object_key    VARCHAR(512) NOT NULL,
    sha256        VARCHAR(64)  NOT NULL,
    created_by    UUID         NOT NULL REFERENCES app_user(id),
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now()
);
CREATE INDEX idx_report_record_trip    ON report_record(trip_id);
CREATE INDEX idx_report_record_creator ON report_record(created_by);
