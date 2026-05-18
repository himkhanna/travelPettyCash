-- Composite index supporting cursor pagination on the expense list.
-- See CLAUDE.md §9: lists use cursor pagination ordered by (occurred_at DESC, id DESC).
-- The V001 indexes (idx_expense_trip and idx_expense_occurred_at) work for filtering
-- but cannot efficiently support the tuple-comparison predicate
-- WHERE trip_id = ? AND (occurred_at, id) < (?, ?).
CREATE INDEX IF NOT EXISTS idx_expense_trip_occurredat_id
    ON expense (trip_id, occurred_at DESC, id DESC);
