-- V014 — mission-level budget (BRD §2.2).
--
-- Admin assigns a total budget to a mission and can increase it later.
-- Currency is set on first assignment (a mission may span trips of
-- different currencies, so the budget carries its own currency).
-- budget_minor defaults to 0 / currency NULL = "not yet assigned".

ALTER TABLE missions
    ADD COLUMN budget_minor    BIGINT NOT NULL DEFAULT 0,
    ADD COLUMN budget_currency CHAR(3);
