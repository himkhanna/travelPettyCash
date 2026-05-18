package ae.gov.pdd.pettycash.report;

import ae.gov.pdd.pettycash.expense.Expense;
import ae.gov.pdd.pettycash.expense.ExpenseCategory;
import ae.gov.pdd.pettycash.fund.Allocation;
import ae.gov.pdd.pettycash.fund.Source;
import ae.gov.pdd.pettycash.trip.Trip;
import ae.gov.pdd.pettycash.user.User;

import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * Pre-loaded data passed to a {@link ReportGenerator}.
 * Keeping I/O out of generators makes them pure render functions and trivially testable.
 */
public record ReportContext(
    Trip trip,
    List<Expense> expenses,
    Map<UUID, User> usersById,
    Map<UUID, Source> sourcesById,
    Map<String, ExpenseCategory> categoriesByCode,
    List<Allocation> allocations
) {}
