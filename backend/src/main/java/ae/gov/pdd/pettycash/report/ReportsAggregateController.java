package ae.gov.pdd.pettycash.report;

import ae.gov.pdd.pettycash.auth.AuthenticatedUser;
import ae.gov.pdd.pettycash.common.error.ApiException;
import ae.gov.pdd.pettycash.expense.ExpenseRepository;
import ae.gov.pdd.pettycash.user.UserRole;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.math.BigInteger;
import java.sql.Date;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Pre-aggregated read endpoints powering the admin dashboard's KPI cards
 * and the right-rail spend chart. Sits alongside the file-rendering
 * {@link ReportController} but returns JSON for live charts rather than
 * downloadable bytes.
 */
@RestController
@RequestMapping("/api/v1/reports")
class ReportsAggregateController {

    private final ExpenseRepository expenses;

    ReportsAggregateController(ExpenseRepository expenses) {
        this.expenses = expenses;
    }

    /**
     * Time-bucketed spend for a single currency.
     *
     * <p>The dashboard's KPI sparkline and 30-day bar chart previously
     * iterated every expense in the browser and bucketed by day — fine
     * for the seed dataset, painful past a few thousand expenses. This
     * endpoint pushes that into Postgres via a single GROUP BY.
     *
     * <p>Days inside the [from, to) range that have no expenses are
     * filled with a zero bucket so the chart's x-axis stays continuous.
     */
    @GetMapping("/spend-by-day")
    public SpendByDayResponse spendByDay(
        @RequestParam("from") String fromIso,
        @RequestParam("to") String toIso,
        @RequestParam("currency") String currency,
        @AuthenticationPrincipal AuthenticatedUser caller
    ) {
        requireAdmin(caller);
        final LocalDate from = LocalDate.parse(fromIso);
        final LocalDate to = LocalDate.parse(toIso);
        if (!to.isAfter(from)) {
            throw new ApiException(
                HttpStatus.BAD_REQUEST, "reports/bad-range",
                "Bad range", "`to` must be after `from`."
            );
        }
        final Instant fromTs = from.atStartOfDay(ZoneOffset.UTC).toInstant();
        final Instant toTs = to.plusDays(1)
            .atStartOfDay(ZoneOffset.UTC).toInstant();

        final List<Object[]> rows =
            expenses.sumByDayInCurrency(fromTs, toTs, currency);

        // Index the SQL result for fast lookup, then iterate the calendar
        // so empty days produce explicit zero buckets.
        final Map<LocalDate, Long> byDay = new HashMap<>();
        for (Object[] row : rows) {
            final LocalDate day = ((Date) row[0]).toLocalDate();
            final long total = ((BigInteger) row[1]).longValueExact();
            byDay.put(day, total);
        }
        final DateTimeFormatter fmt = DateTimeFormatter.ISO_LOCAL_DATE;
        final List<SpendBucket> buckets = new ArrayList<>();
        for (LocalDate d = from; !d.isAfter(to); d = d.plusDays(1)) {
            buckets.add(new SpendBucket(
                fmt.format(d),
                byDay.getOrDefault(d, 0L)
            ));
        }
        return new SpendByDayResponse(currency, fromIso, toIso, buckets);
    }

    private static void requireAdmin(AuthenticatedUser caller) {
        if (caller.role() != UserRole.ADMIN
            && caller.role() != UserRole.SUPER_ADMIN) {
            throw new ApiException(
                HttpStatus.FORBIDDEN, "auth/forbidden", "Forbidden",
                "Admin only."
            );
        }
    }

    public record SpendByDayResponse(
        String currency,
        String from,
        String to,
        List<SpendBucket> buckets
    ) {}

    public record SpendBucket(String date, long amountMinor) {}
}
