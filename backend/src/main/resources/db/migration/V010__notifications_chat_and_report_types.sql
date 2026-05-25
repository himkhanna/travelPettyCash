-- V010 — widen `ck_notifications_type` to cover REPORT_READY + CHAT_MESSAGE.
--
-- V005 baked the constraint with the original 6 enum values. Two
-- notification types were added in later code (REPORT_READY in slice 9,
-- CHAT_MESSAGE in the demo-week sprint) but the Postgres CHECK was
-- never updated, so inserts threw `ck_notifications_type` violations
-- and the chat fan-out + scheduled-report delivery silently 500'd.

ALTER TABLE notifications
    DROP CONSTRAINT IF EXISTS ck_notifications_type;

ALTER TABLE notifications
    ADD CONSTRAINT ck_notifications_type
        CHECK (type IN (
            'ALLOCATION_RECEIVED',
            'TRANSFER_RECEIVED',
            'TRANSFER_ACCEPTED',
            'TRIP_ASSIGNED',
            'TRIP_CLOSED',
            'EXPENSE_QUERY',
            'REPORT_READY',
            'CHAT_MESSAGE'
        ));
