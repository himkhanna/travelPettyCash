-- Chat aggregate (CLAUDE.md §5). Real-time presence + typing indicators are
-- explicitly out of scope per §15; the mobile client polls /messages every
-- few seconds for new bodies.

-- ------------------------------------------------------------------
-- chat_threads — one row per conversation, scoped to a trip.
-- last_message_preview / last_message_at are denormalised here so the
-- "all threads for this trip" list query doesn't have to subquery the
-- last message — the send path keeps them up to date in the same tx.
-- ------------------------------------------------------------------
CREATE TABLE chat_threads (
    id                    UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    trip_id               UUID         NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
    title                 VARCHAR(128) NOT NULL,
    title_ar              VARCHAR(128) NOT NULL,
    created_at            TIMESTAMPTZ  NOT NULL DEFAULT now(),
    last_message_preview  VARCHAR(120),
    last_message_at       TIMESTAMPTZ
);

CREATE INDEX idx_chat_threads_trip ON chat_threads(trip_id, last_message_at DESC);

-- ------------------------------------------------------------------
-- chat_thread_members — M:N. last_read_at flips when the user opens the
-- thread; unread count = messages with sent_at > last_read_at.
-- ------------------------------------------------------------------
CREATE TABLE chat_thread_members (
    thread_id     UUID         NOT NULL REFERENCES chat_threads(id) ON DELETE CASCADE,
    user_id       UUID         NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    joined_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    last_read_at  TIMESTAMPTZ,
    PRIMARY KEY (thread_id, user_id)
);

CREATE INDEX idx_chat_thread_members_user ON chat_thread_members(user_id);

-- ------------------------------------------------------------------
-- chat_messages — append-only message log.
-- ------------------------------------------------------------------
CREATE TABLE chat_messages (
    id            UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    thread_id     UUID         NOT NULL REFERENCES chat_threads(id) ON DELETE CASCADE,
    sender_id     UUID         NOT NULL REFERENCES users(id),
    body          VARCHAR(2000) NOT NULL,
    sent_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    delivered_at  TIMESTAMPTZ
);

CREATE INDEX idx_chat_messages_thread_sent
    ON chat_messages(thread_id, sent_at ASC);
