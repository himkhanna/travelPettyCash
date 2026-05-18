-- Expense comments + @mentions. Replaces the chat-thread-based admin comment
-- flow: a thread had to exist before anyone could post into it, which broke
-- the admin's "ask a question on this expense" path for brand-new trips.
--
-- Comments live with the event (the expense). Mentioned users get a targeted
-- notification (NotificationType.EXPENSE_QUERY) with the comment + expense
-- in the payload, so they can jump straight to it from their inbox.

CREATE TABLE expense_comments (
    id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    expense_id  UUID         NOT NULL REFERENCES expenses(id) ON DELETE CASCADE,
    author_id   UUID         NOT NULL REFERENCES users(id),
    body        VARCHAR(2000) NOT NULL,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    deleted_at  TIMESTAMPTZ
);

-- Newest-first listing per expense, soft-deleted excluded.
CREATE INDEX idx_expense_comments_expense_created
    ON expense_comments(expense_id, created_at DESC)
    WHERE deleted_at IS NULL;

-- Join table for @mentions. A comment can mention many users; a user can
-- appear in many comments. Kept relational (not a JSONB array) so we can
-- ask "show me comments that mention me" cheaply and add a partial index
-- on (user_id) for that query if it ever becomes hot.
CREATE TABLE expense_comment_mentions (
    comment_id  UUID NOT NULL REFERENCES expense_comments(id) ON DELETE CASCADE,
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    PRIMARY KEY (comment_id, user_id)
);

CREATE INDEX idx_expense_comment_mentions_user
    ON expense_comment_mentions(user_id);
