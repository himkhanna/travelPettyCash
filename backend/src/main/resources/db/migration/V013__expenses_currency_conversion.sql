-- V013 — currency conversion on expenses (ADR-003).
--
-- An expense may be spent in a currency other than the trip currency.
-- amount_minor + currency remain the canonical TRIP-currency (base) values
-- that drive balances; these columns record the original foreign amount and
-- the manually-entered exchange rate. All NULL for same-currency expenses
-- (the common case), so this is additive and changes no existing behaviour.

ALTER TABLE expenses
    ADD COLUMN original_currency     CHAR(3),
    ADD COLUMN original_amount_minor BIGINT,
    ADD COLUMN exchange_rate         NUMERIC(18, 6);

-- Either all three are present (a converted expense) or all NULL.
ALTER TABLE expenses
    ADD CONSTRAINT ck_expenses_fx_all_or_none CHECK (
        (original_currency IS NULL AND original_amount_minor IS NULL AND exchange_rate IS NULL)
        OR
        (original_currency IS NOT NULL AND original_amount_minor IS NOT NULL AND exchange_rate IS NOT NULL)
    );
