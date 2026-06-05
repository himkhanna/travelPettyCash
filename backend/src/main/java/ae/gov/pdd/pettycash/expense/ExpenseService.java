package ae.gov.pdd.pettycash.expense;

import ae.gov.pdd.pettycash.auth.AuthenticatedUser;
import ae.gov.pdd.pettycash.common.Money;
import ae.gov.pdd.pettycash.common.MoneyDto;
import ae.gov.pdd.pettycash.common.error.ApiException;
import ae.gov.pdd.pettycash.common.storage.StorageService;
import ae.gov.pdd.pettycash.expense.dto.CreateExpenseRequest;
import ae.gov.pdd.pettycash.expense.dto.ExpenseDto;
import ae.gov.pdd.pettycash.expense.dto.ExpenseSummaryDto;
import ae.gov.pdd.pettycash.expense.dto.PatchExpenseRequest;
import ae.gov.pdd.pettycash.expense.dto.ReceiptUrlDto;
import ae.gov.pdd.pettycash.fund.Source;
import ae.gov.pdd.pettycash.fund.SourceRepository;
import ae.gov.pdd.pettycash.trip.Trip;
import ae.gov.pdd.pettycash.trip.TripRepository;
import ae.gov.pdd.pettycash.trip.TripStatus;
import ae.gov.pdd.pettycash.user.User;
import ae.gov.pdd.pettycash.user.UserRepository;
import ae.gov.pdd.pettycash.user.UserRole;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.io.IOException;
import java.io.InputStream;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.Collection;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

@Service
public class ExpenseService {

    private final ExpenseRepository expenses;
    private final ExpenseCategoryRepository categories;
    private final TripRepository trips;
    private final SourceRepository sources;
    private final UserRepository users;
    private final StorageService storage;
    private final Duration presignedTtl;
    private final Clock clock;

    @Autowired
    public ExpenseService(
        ExpenseRepository expenses,
        ExpenseCategoryRepository categories,
        TripRepository trips,
        SourceRepository sources,
        UserRepository users,
        StorageService storage,
        @Value("${pdd.storage.presigned-ttl:PT5M}") Duration presignedTtl
    ) {
        this(expenses, categories, trips, sources, users, storage, presignedTtl, Clock.systemUTC());
    }

    ExpenseService(
        ExpenseRepository expenses,
        ExpenseCategoryRepository categories,
        TripRepository trips,
        SourceRepository sources,
        UserRepository users,
        StorageService storage,
        Duration presignedTtl,
        Clock clock
    ) {
        this.expenses = expenses;
        this.categories = categories;
        this.trips = trips;
        this.sources = sources;
        this.users = users;
        this.storage = storage;
        this.presignedTtl = presignedTtl;
        this.clock = clock;
    }

    // ---- list / detail ------------------------------------------------

    @Transactional(readOnly = true)
    public List<ExpenseDto> list(
        UUID tripId,
        AuthenticatedUser caller,
        Filter filter
    ) {
        Trip trip = loadAccessibleTrip(tripId, caller);
        // Members only see their own expenses on the trip; Leader + Admin
        // see everyone's (CLAUDE.md §7).
        UUID restrictToUserId = caller.role() == UserRole.MEMBER
            ? caller.userId()
            : filter.userId();
        return expenses.search(
            trip.getId(),
            restrictToUserId,
            isEmpty(filter.categoryCodes()) ? null : filter.categoryCodes(),
            isEmpty(filter.sourceIds()) ? null : filter.sourceIds(),
            isEmpty(filter.memberIds()) ? null : filter.memberIds(),
            filter.from(),
            filter.to()
        ).stream().map(ExpenseDto::from).toList();
    }

    @Transactional(readOnly = true)
    public ExpenseDto get(UUID expenseId, AuthenticatedUser caller) {
        Expense e = loadAccessible(expenseId, caller);
        return ExpenseDto.from(e);
    }

    /**
     * Admin-only: all non-deleted expenses without an attached receipt.
     * Used by the dashboard's "Receipt triage" feed so the admin can act
     * on the missing-evidence backlog in one place.
     */
    @Transactional(readOnly = true)
    public List<ExpenseDto> missingReceipts(AuthenticatedUser caller) {
        if (caller.role() != UserRole.ADMIN
            && caller.role() != UserRole.SUPER_ADMIN) {
            throw new ApiException(
                org.springframework.http.HttpStatus.FORBIDDEN,
                "auth/forbidden", "Forbidden",
                "Admin only."
            );
        }
        return expenses
            .findByReceiptObjectKeyIsNullAndDeletedAtIsNullOrderByOccurredAtDesc()
            .stream()
            .map(ExpenseDto::from)
            .toList();
    }

    // ---- create -------------------------------------------------------

    /**
     * Replay-safe create. The client-supplied id is the row's PK; if a row
     * with that id already exists, return it as-is (offline-queue replay
     * lands on the same row). Combined with the Idempotency-Key header at
     * the controller this gives two layers of dedup.
     */
    @Transactional
    public ExpenseDto create(
        UUID tripId,
        CreateExpenseRequest req,
        AuthenticatedUser caller
    ) {
        // Idempotent replay by client-supplied id (CLAUDE.md §11).
        Optional<Expense> existing = expenses.findById(req.id());
        if (existing.isPresent()) {
            return ExpenseDto.from(existing.get());
        }

        Trip trip = loadAccessibleTrip(tripId, caller);
        if (trip.getStatus() == TripStatus.CLOSED) {
            throw badRequest("trips/closed", "Trip is closed; cannot add expenses.");
        }

        // Members + Leader can create their own expenses; Admin/SuperAdmin
        // cannot create on behalf of members per §7.
        if (caller.role() == UserRole.ADMIN || caller.role() == UserRole.SUPER_ADMIN) {
            throw forbidden("Admins cannot record expenses on behalf of members.");
        }
        // Leader allowed if they participate; Member must participate.
        if (!isParticipant(trip, caller.userId())) {
            throw notFoundTrip(tripId);
        }

        if (!req.amount().currency().equals(trip.getCurrency())) {
            throw badRequest(
                "expenses/currency-mismatch",
                "Expense currency must equal trip currency (" + trip.getCurrency() + ")"
            );
        }
        if (req.amount().amount() <= 0) {
            throw badRequest("expenses/non-positive-amount", "amount must be > 0");
        }
        if (!categories.existsByCode(req.categoryCode())) {
            throw badRequest("expenses/unknown-category", "Unknown category: " + req.categoryCode());
        }
        if (!sources.existsById(req.sourceId())) {
            throw badRequest("expenses/unknown-source", "Unknown source: " + req.sourceId());
        }

        // Currency conversion (ADR-003): all-or-none; rate > 0; foreign ≠ base.
        final boolean anyFx = req.originalCurrency() != null
            || req.originalAmountMinor() != null || req.exchangeRate() != null;
        final boolean allFx = req.originalCurrency() != null
            && req.originalAmountMinor() != null && req.exchangeRate() != null;
        if (anyFx && !allFx) {
            throw badRequest("expenses/fx-incomplete",
                "originalCurrency, originalAmountMinor and exchangeRate must be set together.");
        }
        if (allFx) {
            if (req.exchangeRate().signum() <= 0) {
                throw badRequest("expenses/fx-bad-rate", "exchangeRate must be > 0");
            }
            if (req.originalCurrency().equals(trip.getCurrency())) {
                throw badRequest("expenses/fx-same-currency",
                    "originalCurrency must differ from the trip currency for a conversion.");
            }
        }

        Expense row = new Expense(
            req.id(),
            trip.getId(),
            caller.userId(),
            req.sourceId(),
            req.categoryCode(),
            req.amount().amount(),
            req.amount().currency(),
            Math.max(1, req.quantity()),
            req.details() == null ? "" : req.details(),
            req.occurredAt(),
            req.receiptObjectKey()
        );
        if (allFx) {
            row.recordConversion(
                req.originalCurrency(), req.originalAmountMinor(), req.exchangeRate());
        }
        expenses.save(row);
        return ExpenseDto.from(row);
    }

    // ---- update / reassign -------------------------------------------

    @Transactional
    public ExpenseDto patch(UUID expenseId, PatchExpenseRequest req, AuthenticatedUser caller) {
        Expense e = loadAccessible(expenseId, caller);
        Trip trip = trips.findById(e.getTripId()).orElseThrow(() -> notFoundTrip(e.getTripId()));
        if (trip.getStatus() == TripStatus.CLOSED) {
            throw badRequest("trips/closed", "Trip is closed; expenses are read-only.");
        }
        // Owner-or-leader/admin can edit metadata.
        boolean isOwner  = e.getUserId().equals(caller.userId());
        boolean isLeader = trip.getLeaderId().equals(caller.userId());
        boolean isAdmin  = caller.role() == UserRole.ADMIN || caller.role() == UserRole.SUPER_ADMIN;
        if (!(isOwner || isLeader || isAdmin)) {
            throw forbidden("You can only edit your own expense.");
        }
        if (req.categoryCode() != null && !categories.existsByCode(req.categoryCode())) {
            throw badRequest("expenses/unknown-category", "Unknown category: " + req.categoryCode());
        }
        if (req.amount() != null) {
            if (!req.amount().currency().equals(e.getCurrency())) {
                throw badRequest(
                    "expenses/currency-mismatch",
                    "Cannot change currency on an existing expense."
                );
            }
            if (req.amount().amount() <= 0) {
                throw badRequest("expenses/non-positive-amount", "amount must be > 0");
            }
        }
        e.apply(new Expense.Patch(
            req.categoryCode(),
            req.amount() == null ? null : req.amount().amount(),
            req.quantity(),
            req.details(),
            req.occurredAt()
        ), clock.instant());
        return ExpenseDto.from(e);
    }

    /**
     * Source reassignment per CLAUDE.md §5 — its own audited event. Allowed
     * for the owning member, the trip leader, and admins. SuperAdmin (DG) is
     * read-only.
     */
    @Transactional
    public ExpenseDto reassignSource(UUID expenseId, UUID newSourceId, AuthenticatedUser caller) {
        if (caller.role() == UserRole.SUPER_ADMIN) {
            throw forbidden("DG view is read-only.");
        }
        if (!sources.existsById(newSourceId)) {
            throw badRequest("expenses/unknown-source", "Unknown source: " + newSourceId);
        }
        Expense e = loadAccessible(expenseId, caller);
        Trip trip = trips.findById(e.getTripId()).orElseThrow(() -> notFoundTrip(e.getTripId()));
        if (trip.getStatus() == TripStatus.CLOSED) {
            throw badRequest("trips/closed", "Trip is closed; source reassignment locked.");
        }
        boolean isOwner  = e.getUserId().equals(caller.userId());
        boolean isLeader = trip.getLeaderId().equals(caller.userId());
        boolean isAdmin  = caller.role() == UserRole.ADMIN;
        if (!(isOwner || isLeader || isAdmin)) {
            throw forbidden("You can only reassign your own expense.");
        }
        e.reassignSource(newSourceId, clock.instant());
        return ExpenseDto.from(e);
    }

    // ---- summary ------------------------------------------------------

    @Transactional(readOnly = true)
    public ExpenseSummaryDto summary(
        UUID tripId,
        AuthenticatedUser caller,
        String scope,
        String groupBy,
        UUID userIdFilter
    ) {
        Trip trip = loadAccessibleTrip(tripId, caller);

        UUID restrictToUserId = switch (scope) {
            case "mine" -> caller.userId();
            case "user" -> userIdFilter == null
                ? caller.userId()
                : (caller.role() == UserRole.MEMBER && !userIdFilter.equals(caller.userId())
                    ? caller.userId()
                    : userIdFilter);
            default     -> caller.role() == UserRole.MEMBER ? caller.userId() : null;
        };

        List<Expense> rows = expenses.search(
            trip.getId(), restrictToUserId,
            null, null, null, null, null
        );

        // Map<groupKey, [amount, labelEn, labelAr]>
        Map<String, long[]> totals = new LinkedHashMap<>();
        Map<String, String> labelsEn = new LinkedHashMap<>();
        Map<String, String> labelsAr = new LinkedHashMap<>();

        Map<String, ExpenseCategory> catCache = new LinkedHashMap<>();
        Map<UUID, User> userCache = new LinkedHashMap<>();
        Map<UUID, Source> sourceCache = new LinkedHashMap<>();

        for (Expense e : rows) {
            String key;
            String en;
            String ar;
            switch (groupBy) {
                case "source" -> {
                    Source s = sourceCache.computeIfAbsent(e.getSourceId(),
                        id -> sources.findById(id).orElseThrow());
                    key = s.getId().toString();
                    en = s.getName();
                    ar = s.getNameAr();
                }
                case "member" -> {
                    User u = userCache.computeIfAbsent(e.getUserId(),
                        id -> users.findById(id).orElseThrow());
                    key = u.getId().toString();
                    en = u.getDisplayName();
                    ar = u.getDisplayNameAr();
                }
                default -> { // category
                    ExpenseCategory c = catCache.computeIfAbsent(e.getCategoryCode(),
                        code -> categories.findByCode(code).orElseThrow());
                    key = c.getCode();
                    en = c.getNameEn();
                    ar = c.getNameAr();
                }
            }
            totals.merge(key, new long[] {e.getAmountMinor()}, (a, b) -> new long[] {a[0] + b[0]});
            labelsEn.put(key, en);
            labelsAr.put(key, ar);
        }

        List<ExpenseSummaryDto.Row> out = totals.entrySet().stream()
            .map(en -> new ExpenseSummaryDto.Row(
                en.getKey(),
                labelsEn.get(en.getKey()),
                labelsAr.get(en.getKey()),
                MoneyDto.from(new Money(en.getValue()[0], trip.getCurrency()))
            ))
            .toList();
        return new ExpenseSummaryDto(groupBy, scope, out);
    }

    // ---- receipts -----------------------------------------------------

    /**
     * Stores the uploaded bytes under {@code receipts/{expenseId}/{uuid}} and
     * points the expense at the new object. Replacing a receipt orphans the
     * previous object — that's intentional for v1; the audit-log slice will
     * track every key the row has ever held.
     */
    @Transactional
    public ExpenseDto uploadReceipt(
        UUID expenseId,
        AuthenticatedUser caller,
        String contentType,
        long contentLength,
        InputStream bytes
    ) {
        Expense e = loadAccessible(expenseId, caller);
        Trip trip = trips.findById(e.getTripId()).orElseThrow(() -> notFoundTrip(e.getTripId()));
        if (trip.getStatus() == TripStatus.CLOSED) {
            throw badRequest("trips/closed", "Trip is closed; receipts are read-only.");
        }
        // Only the expense owner can upload; admins record their own audit
        // events differently (out of scope here).
        if (!e.getUserId().equals(caller.userId())) {
            throw forbidden("Only the expense owner can attach a receipt.");
        }
        String extension = guessExtension(contentType);
        String objectKey = "receipts/" + expenseId + "/" + UUID.randomUUID() + extension;
        storage.putObject(objectKey, contentType, contentLength, bytes);
        e.attachReceipt(objectKey, clock.instant());
        return ExpenseDto.from(e);
    }

    @Transactional(readOnly = true)
    public ReceiptUrlDto receiptUrl(UUID expenseId, AuthenticatedUser caller) {
        Expense e = loadAccessible(expenseId, caller);
        if (e.getReceiptObjectKey() == null) {
            throw new ApiException(
                HttpStatus.NOT_FOUND,
                "expenses/no-receipt",
                "No receipt attached",
                "This expense has no receipt object yet."
            );
        }
        String url = storage.presignedGetUrl(e.getReceiptObjectKey(), presignedTtl);
        return new ReceiptUrlDto(url, clock.instant().plus(presignedTtl));
    }

    private static String guessExtension(String contentType) {
        if (contentType == null) return "";
        return switch (contentType.toLowerCase()) {
            case "image/jpeg", "image/jpg" -> ".jpg";
            case "image/png"               -> ".png";
            case "image/webp"              -> ".webp";
            case "image/heic"              -> ".heic";
            case "application/pdf"         -> ".pdf";
            default                        -> "";
        };
    }

    // ---- helpers ------------------------------------------------------

    private Trip loadAccessibleTrip(UUID tripId, AuthenticatedUser caller) {
        Trip t = trips.findById(tripId).orElseThrow(() -> notFoundTrip(tripId));
        if (caller.role() == UserRole.ADMIN || caller.role() == UserRole.SUPER_ADMIN) {
            return t;
        }
        if (!isParticipant(t, caller.userId())) {
            throw notFoundTrip(tripId);
        }
        return t;
    }

    private Expense loadAccessible(UUID expenseId, AuthenticatedUser caller) {
        Expense e = expenses.findById(expenseId)
            .filter(x -> x.getDeletedAt() == null)
            .orElseThrow(() -> notFoundExpense(expenseId));
        // Reuse trip-level access check.
        loadAccessibleTrip(e.getTripId(), caller);
        // Members may only see their own expense.
        if (caller.role() == UserRole.MEMBER && !e.getUserId().equals(caller.userId())) {
            throw notFoundExpense(expenseId);
        }
        return e;
    }

    /**
     * Public access-controlled load for sibling services (e.g.
     * {@code ExpenseCommentService}). Mirrors {@link #loadAccessible} but
     * returns the row instead of being a private helper.
     */
    @Transactional(readOnly = true)
    public Expense loadAccessibleExpense(UUID expenseId, AuthenticatedUser caller) {
        return loadAccessible(expenseId, caller);
    }

    private static boolean isParticipant(Trip t, UUID userId) {
        return t.getLeaderId().equals(userId)
            || t.getCreatedById().equals(userId)
            || t.getMemberIds().contains(userId);
    }

    private static <T> boolean isEmpty(Collection<T> c) { return c == null || c.isEmpty(); }

    private static ApiException notFoundTrip(UUID tripId) {
        return new ApiException(
            HttpStatus.NOT_FOUND,
            "trips/not-found",
            "Trip not found",
            "No trip with id " + tripId + " is accessible to this user."
        );
    }

    private static ApiException notFoundExpense(UUID id) {
        return new ApiException(
            HttpStatus.NOT_FOUND,
            "expenses/not-found",
            "Expense not found",
            "No expense with id " + id
        );
    }

    private static ApiException badRequest(String code, String detail) {
        return new ApiException(HttpStatus.BAD_REQUEST, code, "Bad request", detail);
    }

    private static ApiException forbidden(String detail) {
        return new ApiException(HttpStatus.FORBIDDEN, "auth/forbidden", "Forbidden", detail);
    }

    public record Filter(
        UUID userId,
        Collection<String> categoryCodes,
        Collection<UUID> sourceIds,
        Collection<UUID> memberIds,
        Instant from,
        Instant to
    ) {}
}
