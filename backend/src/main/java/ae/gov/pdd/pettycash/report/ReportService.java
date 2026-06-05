package ae.gov.pdd.pettycash.report;

import ae.gov.pdd.pettycash.auth.AuthenticatedUser;
import ae.gov.pdd.pettycash.common.error.ApiException;
import ae.gov.pdd.pettycash.expense.ExpenseCategory;
import ae.gov.pdd.pettycash.expense.ExpenseCategoryRepository;
import ae.gov.pdd.pettycash.expense.ExpenseService;
import ae.gov.pdd.pettycash.expense.dto.ExpenseDto;
import ae.gov.pdd.pettycash.fund.Allocation;
import ae.gov.pdd.pettycash.fund.AllocationRepository;
import ae.gov.pdd.pettycash.fund.FundsStatus;
import ae.gov.pdd.pettycash.fund.Source;
import ae.gov.pdd.pettycash.fund.SourceRepository;
import ae.gov.pdd.pettycash.mission.Mission;
import ae.gov.pdd.pettycash.mission.MissionRepository;
import ae.gov.pdd.pettycash.trip.Trip;
import ae.gov.pdd.pettycash.trip.TripRepository;
import ae.gov.pdd.pettycash.trip.dto.TripDto;
import ae.gov.pdd.pettycash.user.User;
import ae.gov.pdd.pettycash.user.UserRepository;
import ae.gov.pdd.pettycash.user.UserRole;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;

import java.time.LocalDate;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.stream.Collectors;

/**
 * Loads the data each report kind needs, enforces access, then delegates to
 * the format-specific renderer ({@link PdfReportRenderer} or
 * {@link XlsxReportRenderer}). Digital signature is a downstream step the
 * Admin invokes separately on the returned PDF (CLAUDE.md §10) — this
 * service produces unsigned bytes only.
 */
@Service
public class ReportService {

    private final ExpenseService expenses;
    private final TripRepository trips;
    private final UserRepository users;
    private final SourceRepository sources;
    private final ExpenseCategoryRepository categories;
    private final MissionRepository missions;
    private final AllocationRepository allocations;
    private final PdfReportRenderer pdfRenderer;
    private final XlsxReportRenderer xlsxRenderer;

    ReportService(
        ExpenseService expenses,
        TripRepository trips,
        UserRepository users,
        SourceRepository sources,
        ExpenseCategoryRepository categories,
        MissionRepository missions,
        AllocationRepository allocations,
        PdfReportRenderer pdfRenderer,
        XlsxReportRenderer xlsxRenderer
    ) {
        this.expenses = expenses;
        this.trips = trips;
        this.users = users;
        this.sources = sources;
        this.categories = categories;
        this.missions = missions;
        this.allocations = allocations;
        this.pdfRenderer = pdfRenderer;
        this.xlsxRenderer = xlsxRenderer;
    }

    /** Bytes + filename + content-type, ready for a streaming response. */
    public record Rendered(byte[] bytes, String filename, String contentType) {}

    // ---- public API --------------------------------------------------

    public Rendered userReport(UUID tripId, UUID userId, String format, AuthenticatedUser caller) {
        ReportContext ctx = loadContext(tripId, caller);
        // Members can only generate their own user report; Admin/Leader can pick anyone.
        if (caller.role() == UserRole.MEMBER && !caller.userId().equals(userId)) {
            throw forbidden();
        }
        User target = users.findById(userId)
            .orElseThrow(() -> notFound("User", userId));
        ReportData data = ctx.forUser(userId);
        String fname = "user-report-" + slug(target.getDisplayName()) + "-" + slug(ctx.trip.name());
        if ("xlsx".equalsIgnoreCase(format)) {
            return new Rendered(
                xlsxRenderer.userReport(ctx, target, data),
                fname + ".xlsx",
                xlsxRenderer.contentType()
            );
        }
        return new Rendered(
            pdfRenderer.userReport(ctx, target, data),
            fname + ".pdf",
            pdfRenderer.contentType()
        );
    }

    public Rendered tripFullReport(UUID tripId, String format, AuthenticatedUser caller) {
        if (caller.role() == UserRole.MEMBER) {
            throw forbidden();
        }
        ReportContext ctx = loadContext(tripId, caller);
        String fname = "trip-full-" + slug(ctx.trip.name());
        if ("pdf".equalsIgnoreCase(format)) {
            return new Rendered(
                pdfRenderer.tripFull(ctx),
                fname + ".pdf",
                pdfRenderer.contentType()
            );
        }
        return new Rendered(
            xlsxRenderer.tripFull(ctx),
            fname + ".xlsx",
            xlsxRenderer.contentType()
        );
    }

    public Rendered financeLetter(UUID tripId, AuthenticatedUser caller) {
        if (caller.role() != UserRole.ADMIN && caller.role() != UserRole.SUPER_ADMIN) {
            throw forbidden();
        }
        ReportContext ctx = loadContext(tripId, caller);
        return new Rendered(
            pdfRenderer.financeLetter(ctx),
            "finance-letter-" + slug(ctx.trip.name()) + ".pdf",
            pdfRenderer.contentType()
        );
    }

    public Rendered dgReport(UUID tripId, AuthenticatedUser caller) {
        if (caller.role() == UserRole.MEMBER) {
            throw forbidden();
        }
        ReportContext ctx = loadContext(tripId, caller);
        return new Rendered(
            pdfRenderer.dgReport(ctx),
            "dg-report-" + slug(ctx.trip.name()) + ".pdf",
            pdfRenderer.contentType()
        );
    }

    /**
     * Same shape as {@link #tripFullReport} but restricted to expenses
     * that occurred on the given UTC date. Backs the "Daily expense
     * report" download — admin runs at the end of day to send a one-day
     * snapshot to finance without re-running the lifetime report.
     */
    public Rendered tripDailyReport(
        UUID tripId, LocalDate date, String format, AuthenticatedUser caller
    ) {
        if (caller.role() == UserRole.MEMBER) {
            throw forbidden();
        }
        if (date == null) {
            throw new ApiException(
                HttpStatus.BAD_REQUEST, "reports/missing-date",
                "Missing date", "Date is required for the daily report."
            );
        }
        ReportContext ctx = loadContext(tripId, caller).filterByDay(date);
        String fname = "trip-daily-" + slug(ctx.trip.name())
            + "-" + date.toString();
        if ("pdf".equalsIgnoreCase(format)) {
            return new Rendered(
                pdfRenderer.tripFull(ctx),
                fname + ".pdf",
                pdfRenderer.contentType()
            );
        }
        return new Rendered(
            xlsxRenderer.tripFull(ctx),
            fname + ".xlsx",
            xlsxRenderer.contentType()
        );
    }

    /**
     * Mission rollup — concatenates the trip-full XLSX rows of every trip
     * tagged with this mission. Filters by {@code date} when provided
     * (today's mission-wide snapshot). Trip name is added as a prefix on
     * each row's detail field so a single sheet stays readable.
     */
    public Rendered missionReport(
        UUID missionId, LocalDate date, AuthenticatedUser caller
    ) {
        if (caller.role() == UserRole.MEMBER) {
            throw forbidden();
        }
        Mission m = missions.findById(missionId)
            .orElseThrow(() -> notFound("Mission", missionId));
        // Walk every trip in this mission. Mission rollup is XLSX-only —
        // PDF mission letters can come later.
        List<Trip> missionTrips = new ArrayList<>();
        for (Trip t : trips.findAll()) {
            if (m.getId().equals(t.getMissionId())) {
                missionTrips.add(t);
            }
        }
        // Collect a flat list of expenses across all trips. Each ExpenseDto
        // carries its tripId so the renderer's trip-name lookup still works.
        List<ExpenseDto> allExp = new ArrayList<>();
        Map<UUID, TripDto> tripById = new HashMap<>();
        for (Trip t : missionTrips) {
            TripDto td = TripDto.from(t);
            tripById.put(t.getId(), td);
            List<ExpenseDto> some = expenses.list(
                t.getId(), caller,
                new ExpenseService.Filter(null, null, null, null, null, null)
            );
            for (ExpenseDto e : some) {
                if (date != null) {
                    java.time.LocalDate occ = e.occurredAt()
                        .atZone(ZoneOffset.UTC).toLocalDate();
                    if (!occ.equals(date)) continue;
                }
                allExp.add(e);
            }
        }
        // Synthesize a trip-shaped DTO that names the mission, so the
        // existing tripFull renderer can produce a sensible header without
        // a new code path.
        final String fallbackCcy =
            missionTrips.isEmpty() ? "AED" : missionTrips.get(0).getCurrency();
        TripDto syntheticTrip = new TripDto(
            m.getId(),
            "Mission · " + m.getName(),
            missionTrips.isEmpty() ? "AE" : missionTrips.get(0).getCountryCode(),
            missionTrips.isEmpty() ? "United Arab Emirates"
                : missionTrips.get(0).getCountryName(),
            fallbackCcy,
            ae.gov.pdd.pettycash.trip.TripStatus.ACTIVE,
            caller.userId(),  // createdBy
            caller.userId(),  // leaderId
            m.getId(),        // missionId
            java.util.Collections.<UUID>emptyList(),
            new ae.gov.pdd.pettycash.common.MoneyDto(0L, fallbackCcy),
            m.getCreatedAt(),
            null
        );
        Map<UUID, User> userById = new HashMap<>();
        for (User u : users.findAll()) userById.put(u.getId(), u);
        Map<UUID, Source> sourceById = new HashMap<>();
        for (Source s : sources.findAll()) sourceById.put(s.getId(), s);
        Map<String, ExpenseCategory> catByCode = new HashMap<>();
        for (ExpenseCategory c : categories.findAll()) {
            catByCode.put(c.getCode(), c);
        }
        ReportContext ctx = new ReportContext(
            syntheticTrip, allExp, userById, sourceById, catByCode, Map.of()
        );
        String fname = "mission-" + slug(m.getName())
            + (date == null ? "" : "-" + date.toString());
        return new Rendered(
            xlsxRenderer.tripFull(ctx),
            fname + ".xlsx",
            xlsxRenderer.contentType()
        );
    }

    // ---- internals ---------------------------------------------------

    /** Loads everything a report renderer needs, in one shot. */
    private ReportContext loadContext(UUID tripId, AuthenticatedUser caller) {
        Trip tripEntity = trips.findById(tripId)
            .orElseThrow(() -> notFound("Trip", tripId));
        TripDto trip = TripDto.from(tripEntity);
        // ExpenseService.list enforces access (member-only sees own, etc.).
        // For reports we want the full list when caller can see it — pass an
        // empty filter, ExpenseService will scope it correctly.
        List<ExpenseDto> all = expenses.list(
            tripId, caller,
            new ExpenseService.Filter(null, null, null, null, null, null)
        );
        Map<UUID, User> userById = new HashMap<>();
        for (User u : users.findAll()) userById.put(u.getId(), u);
        Map<UUID, Source> sourceById = new HashMap<>();
        for (Source s : sources.findAll()) sourceById.put(s.getId(), s);
        Map<String, ExpenseCategory> catByCode = new HashMap<>();
        for (ExpenseCategory c : categories.findAll()) catByCode.put(c.getCode(), c);
        return new ReportContext(
            trip, all, userById, sourceById, catByCode, allocatedBySource(tripId));
    }

    /** Funds allocated into the trip from each source = accepted admin-pool
     *  allocations (fromUserId == null) grouped by source. Leader→member
     *  allocations are re-distributions of already-sourced funds, so they're
     *  excluded to avoid double-counting. Used for the finance letter's
     *  ALLOCATED column (BRD §2.6). */
    private Map<UUID, Long> allocatedBySource(UUID tripId) {
        Map<UUID, Long> out = new HashMap<>();
        for (Allocation a : allocations.findByTripIdOrderByCreatedAtAsc(tripId)) {
            if (a.getFromUserId() != null || a.getStatus() != FundsStatus.ACCEPTED) continue;
            out.merge(a.getSourceId(), a.getAmountMinor(), Long::sum);
        }
        return out;
    }

    private static ApiException forbidden() {
        return new ApiException(
            HttpStatus.FORBIDDEN, "auth/forbidden", "Forbidden",
            "You do not have permission to generate this report."
        );
    }

    private static ApiException notFound(String kind, UUID id) {
        return new ApiException(
            HttpStatus.NOT_FOUND, "common/not-found", "Not found",
            kind + " not found: " + id
        );
    }

    private static String slug(String s) {
        if (s == null) return "untitled";
        return s.toLowerCase().replaceAll("[^a-z0-9]+", "-").replaceAll("^-|-$", "");
    }

    /** Aggregate view passed to each renderer. Immutable. */
    static final class ReportContext {
        final TripDto trip;
        final List<ExpenseDto> expenses;
        final Map<UUID, User> userById;
        final Map<UUID, Source> sourceById;
        final Map<String, ExpenseCategory> catByCode;
        /** Funds allocated into the trip per source (minor units). See
         *  ReportService.allocatedBySource. Empty when not computed. */
        final Map<UUID, Long> allocatedBySource;

        ReportContext(
            TripDto trip,
            List<ExpenseDto> expenses,
            Map<UUID, User> userById,
            Map<UUID, Source> sourceById,
            Map<String, ExpenseCategory> catByCode,
            Map<UUID, Long> allocatedBySource
        ) {
            this.trip = trip;
            this.expenses = Collections.unmodifiableList(expenses);
            this.userById = Collections.unmodifiableMap(userById);
            this.sourceById = Collections.unmodifiableMap(sourceById);
            this.catByCode = Collections.unmodifiableMap(catByCode);
            this.allocatedBySource =
                Collections.unmodifiableMap(allocatedBySource);
        }

        ReportData forUser(UUID userId) {
            List<ExpenseDto> mine = expenses.stream()
                .filter(e -> e.userId().equals(userId))
                .toList();
            long totalMinor = mine.stream().mapToLong(e -> e.amount().amount()).sum();
            Map<UUID, List<ExpenseDto>> bySource = mine.stream()
                .collect(Collectors.groupingBy(ExpenseDto::sourceId));
            return new ReportData(mine, totalMinor, bySource);
        }

        /// Returns a new context with the expenses list restricted to those
        /// that occurred on the given UTC date. Lookup maps are shared.
        ReportContext filterByDay(LocalDate day) {
            List<ExpenseDto> filtered = expenses.stream()
                .filter(e -> e.occurredAt()
                    .atZone(ZoneOffset.UTC).toLocalDate().equals(day))
                .toList();
            return new ReportContext(
                trip, filtered, userById, sourceById, catByCode, allocatedBySource
            );
        }
    }

    /** Per-user / per-trip slice prepared for rendering. */
    record ReportData(
        List<ExpenseDto> rows,
        long totalMinor,
        Map<UUID, List<ExpenseDto>> bySource
    ) {}
}
