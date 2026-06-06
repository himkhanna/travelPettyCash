package ae.gov.pdd.pettycash.insight;

import ae.gov.pdd.pettycash.auth.AuthenticatedUser;
import ae.gov.pdd.pettycash.common.error.ApiException;
import ae.gov.pdd.pettycash.expense.Expense;
import ae.gov.pdd.pettycash.expense.ExpenseCategory;
import ae.gov.pdd.pettycash.expense.ExpenseCategoryRepository;
import ae.gov.pdd.pettycash.expense.ExpenseRepository;
import ae.gov.pdd.pettycash.trip.Trip;
import ae.gov.pdd.pettycash.trip.TripRepository;
import ae.gov.pdd.pettycash.user.User;
import ae.gov.pdd.pettycash.user.UserRepository;
import ae.gov.pdd.pettycash.user.UserRole;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * Loads a trip's expenses and hands them to the deterministic
 * {@link InsightCalculator}. Access is enforced here the same way the
 * balances endpoint does it: admins/super-admins see any trip, otherwise the
 * caller must be a participant, and an inaccessible trip 404s (never 403, so
 * we don't leak which trips exist).
 */
@Service
public class InsightsService {

    /** Reporting zone for bucketing expense timestamps into calendar days. */
    private static final ZoneId REPORT_ZONE = ZoneId.of("Asia/Dubai");

    private final TripRepository trips;
    private final ExpenseRepository expenses;
    private final ExpenseCategoryRepository categories;
    private final UserRepository users;
    private final InsightCalculator calculator;

    public InsightsService(
        TripRepository trips,
        ExpenseRepository expenses,
        ExpenseCategoryRepository categories,
        UserRepository users,
        InsightCalculator calculator
    ) {
        this.trips = trips;
        this.expenses = expenses;
        this.categories = categories;
        this.users = users;
        this.calculator = calculator;
    }

    @Transactional(readOnly = true)
    public TripInsightsDto forTrip(UUID tripId, AuthenticatedUser caller) {
        Trip trip = trips.findById(tripId).orElseThrow(() -> notFound(tripId));

        boolean isAdmin = caller.role() == UserRole.ADMIN
            || caller.role() == UserRole.SUPER_ADMIN;
        boolean isParticipant = trip.getLeaderId().equals(caller.userId())
            || trip.getCreatedById().equals(caller.userId())
            || trip.getMemberIds().contains(caller.userId());
        if (!isAdmin && !isParticipant) {
            throw notFound(tripId);
        }

        List<Expense> active =
            expenses.findByTripIdAndDeletedAtIsNullOrderByOccurredAtDesc(tripId);

        Map<String, String> categoryNames = new HashMap<>();
        for (ExpenseCategory c : categories.findAll()) {
            categoryNames.put(c.getCode(), c.getNameEn());
        }
        Map<UUID, String> userNames = new HashMap<>();
        for (User u : users.findAll()) {
            userNames.put(u.getId(), u.getDisplayName());
        }

        List<ExpenseFact> facts = new ArrayList<>(active.size());
        for (Expense e : active) {
            LocalDate day = e.getOccurredAt() == null
                ? null
                : LocalDate.ofInstant(e.getOccurredAt(), REPORT_ZONE);
            facts.add(new ExpenseFact(
                e.getAmountMinor(), e.getCategoryCode(), e.getUserId(), day));
        }

        return calculator.calculate(
            trip.getName(),
            trip.getCurrency(),
            trip.getTotalBudgetMinor(),
            facts,
            categoryNames,
            userNames
        );
    }

    private ApiException notFound(UUID id) {
        return new ApiException(
            HttpStatus.NOT_FOUND, "trips/not-found", "Trip not found",
            "No trip with id " + id + " is accessible to this user.");
    }
}
