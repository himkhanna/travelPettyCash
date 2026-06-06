package ae.gov.pdd.pettycash.insight;

import java.time.LocalDate;
import java.util.UUID;

/**
 * The minimal slice of an expense the {@link InsightCalculator} needs. Kept
 * separate from the JPA {@code Expense} entity so the calculator stays a pure,
 * easily-unit-tested function with no persistence dependency.
 *
 * @param amountMinor  amount in the trip (base) currency's minor units
 * @param categoryCode expense category code (may be null)
 * @param userId       who logged it (may be null)
 * @param day          the calendar day it occurred, in the reporting zone
 *                     (may be null)
 */
public record ExpenseFact(
    long amountMinor,
    String categoryCode,
    UUID userId,
    LocalDate day
) {}
