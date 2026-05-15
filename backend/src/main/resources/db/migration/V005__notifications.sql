-- Notifications inbox (CLAUDE.md §5). Append-write-only from the perspective
-- of fan-out callers; state column flips through UNREAD → READ → ACTED.

CREATE TABLE notifications (
    id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type        VARCHAR(32)  NOT NULL,
    actionable  BOOLEAN      NOT NULL DEFAULT FALSE,
    state       VARCHAR(16)  NOT NULL DEFAULT 'UNREAD',
    -- ref_type + ref_id link this row to the entity it announces (an
    -- allocation, a transfer, …). Used to flip the notification ACTED
    -- when that entity is responded to via its own endpoint.
    ref_type    VARCHAR(32),
    ref_id      UUID,
    payload     JSONB        NOT NULL DEFAULT '{}'::jsonb,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    read_at     TIMESTAMPTZ,
    acted_at    TIMESTAMPTZ,
    CONSTRAINT ck_notifications_type
        CHECK (type IN (
            'ALLOCATION_RECEIVED', 'TRANSFER_RECEIVED', 'TRANSFER_ACCEPTED',
            'TRIP_ASSIGNED', 'TRIP_CLOSED', 'EXPENSE_QUERY'
        )),
    CONSTRAINT ck_notifications_state
        CHECK (state IN ('UNREAD', 'READ', 'ACTED'))
);

-- The hot read path on the mobile drawer badge: count my unread, newest first.
CREATE INDEX idx_notifications_user_state_created
    ON notifications(user_id, state, created_at DESC);

-- Fast lookup when an allocation / transfer respond fans state out to the
-- notifications that pointed at it.
CREATE INDEX idx_notifications_ref
    ON notifications(ref_type, ref_id)
    WHERE ref_id IS NOT NULL;
