package ae.gov.pdd.pettycash.expense;

import ae.gov.pdd.pettycash.audit.AuditService;
import ae.gov.pdd.pettycash.auth.CurrentUser;
import ae.gov.pdd.pettycash.common.ApiException;
import ae.gov.pdd.pettycash.common.Money;
import ae.gov.pdd.pettycash.fund.SourceRepository;
import ae.gov.pdd.pettycash.trip.Trip;
import ae.gov.pdd.pettycash.trip.TripRepository;
import ae.gov.pdd.pettycash.user.Role;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;
import java.util.UUID;

@Service
public class ExpenseService {

    private final ExpenseRepository expenses;
    private final ExpenseCategoryRepository categories;
    private final TripRepository trips;
    private final SourceRepository sources;
    private final AuditService audit;
    private final CurrentUser current;

    public ExpenseService(ExpenseRepository expenses, ExpenseCategoryRepository categories,
                          TripRepository trips, SourceRepository sources,
                          AuditService audit, CurrentUser current) {
        this.expenses = expenses;
        this.categories = categories;
        this.trips = trips;
        this.sources = sources;
        this.audit = audit;
        this.current = current;
    }

    @Transactional(readOnly = true)
    public Expense getById(UUID id) {
        return expenses.findById(id).orElseThrow(
            () -> ApiException.notFound("EXPENSE_NOT_FOUND", "Expense " + id));
    }

    @Transactional
    public Expense setReceiptObjectKey(UUID id, String objectKey) {
        Expense e = getById(id);
        e.setReceiptObjectKey(objectKey);
        e.setUpdatedAt(OffsetDateTime.now());
        return expenses.save(e);
    }

    /**
     * Authorize the caller to read/write the receipt of an expense.
     * Owner of the expense, the trip leader, or an ADMIN may proceed.
     */
    @Transactional(readOnly = true)
    public Expense authorizeReceiptAccess(UUID expenseId) {
        Expense e = getById(expenseId);
        Role role = current.role();
        if (role == Role.ADMIN || role == Role.SUPER_ADMIN) {
            return e;
        }
        if (e.getUserId().equals(current.id())) {
            return e;
        }
        if (role == Role.LEADER) {
            Trip trip = trips.findById(e.getTripId()).orElseThrow(
                () -> ApiException.notFound("TRIP_NOT_FOUND", "Trip " + e.getTripId()));
            if (trip.getLeaderId().equals(current.id())) {
                return e;
            }
        }
        throw ApiException.forbidden("FORBIDDEN", "Not authorized for this expense's receipt");
    }

    @Transactional(readOnly = true)
    public List<Expense> listForTrip(UUID tripId, String scope) {
        if ("mine".equalsIgnoreCase(scope)) {
            return expenses.findByTripIdAndUserId(tripId, current.id());
        }
        return expenses.findByTripId(tripId);
    }

    /**
     * Cursor-paginated expense list. See CLAUDE.md §9 — cursor pagination is the
     * canonical shape for the expense feed.
     *
     * <p>Page contains at most {@code limit} items, sorted by (occurredAt DESC, id DESC).
     * When more rows exist, {@link ExpenseDtos.ExpensePage#nextCursor()} encodes the
     * (occurredAt, id) of the last returned row; pass it back as {@code cursor} to
     * fetch the next page. {@code nextCursor} is null on the final page.
     *
     * @param scope "mine" filters to current user; anything else returns all trip rows.
     */
    @Transactional(readOnly = true)
    public ExpenseDtos.ExpensePage listPage(UUID tripId, String scope, String cursor, int limit) {
        int capped = Math.max(1, Math.min(limit, 100));
        // Fetch one extra row to detect whether another page exists without a second query.
        org.springframework.data.domain.Pageable pageable =
            org.springframework.data.domain.PageRequest.of(0, capped + 1);

        boolean mine = "mine".equalsIgnoreCase(scope);
        List<Expense> rows;
        if (cursor == null || cursor.isBlank()) {
            rows = mine
                ? expenses.findFirstPageByTripIdAndUserId(tripId, current.id(), pageable)
                : expenses.findFirstPageByTripId(tripId, pageable);
        } else {
            CursorCodec.Cursor c = CursorCodec.decode(cursor);
            rows = mine
                ? expenses.findPageByTripIdAndUserId(tripId, current.id(), c.occurredAt(), c.id(), pageable)
                : expenses.findPageByTripId(tripId, c.occurredAt(), c.id(), pageable);
        }

        boolean hasMore = rows.size() > capped;
        List<Expense> page = hasMore ? rows.subList(0, capped) : rows;
        String next = null;
        if (hasMore) {
            Expense last = page.get(page.size() - 1);
            next = CursorCodec.encode(last.getOccurredAt(), last.getId());
        }
        List<ExpenseDtos.ExpenseView> views = page.stream().map(ExpenseDtos.ExpenseView::from).toList();
        return new ExpenseDtos.ExpensePage(views, next);
    }

    @Transactional
    public Expense create(UUID tripId, ExpenseDtos.CreateExpenseRequest req) {
        Trip trip = trips.findById(tripId).orElseThrow(
            () -> ApiException.notFound("TRIP_NOT_FOUND", "Trip " + tripId));
        if (!trip.getMemberIds().contains(current.id()) && !trip.getLeaderId().equals(current.id())) {
            throw ApiException.forbidden("NOT_TRIP_MEMBER", "Caller is not a member of this trip");
        }
        if (req.id() == null) throw ApiException.badRequest("MISSING_ID", "Client-supplied UUID required");
        if (expenses.existsById(req.id())) {
            // Idempotent — return existing.
            return expenses.findById(req.id()).orElseThrow();
        }
        ExpenseCategory cat = categories.findByCode(req.categoryCode()).orElseThrow(
            () -> ApiException.notFound("CATEGORY_NOT_FOUND", "Category " + req.categoryCode()));
        if (!sources.existsById(req.sourceId())) {
            throw ApiException.notFound("SOURCE_NOT_FOUND", "Source " + req.sourceId());
        }
        if (!req.amount().currency().equalsIgnoreCase(trip.getCurrency())) {
            throw ApiException.badRequest("CURRENCY_MISMATCH",
                "Expense currency must match trip currency " + trip.getCurrency());
        }

        Expense e = new Expense();
        e.setId(req.id());
        e.setTripId(tripId);
        e.setUserId(current.id());
        e.setSourceId(req.sourceId());
        e.setCategoryId(cat.getId());
        e.setCategoryCode(cat.getCode());
        Money amount = Money.of(req.amount().amount(), req.amount().currency());
        e.setAmount(amount);
        int qty = req.quantity() == null ? 1 : Math.max(1, req.quantity());
        e.setQuantity(qty);
        e.setUnitCostAmount(amount.amount() / qty);
        e.setDetails(req.details());
        e.setVendor(req.vendor());
        e.setOccurredAt(req.occurredAt() == null ? OffsetDateTime.now() : req.occurredAt());
        e.setReceiptObjectKey(req.receiptObjectKey());
        e.setCreatedAt(OffsetDateTime.now());
        e.setUpdatedAt(OffsetDateTime.now());

        Expense saved = expenses.save(e);
        audit.recordEvent("Expense", saved.getId().toString(), current.id(), "CREATE",
            null,
            Map.of(
                "tripId", tripId.toString(),
                "userId", current.id().toString(),
                "sourceId", saved.getSourceId().toString(),
                "amount", saved.getAmount().amount(),
                "currency", saved.getAmount().currency(),
                "categoryCode", saved.getCategoryCode()
            ));
        return saved;
    }

    @Transactional
    public Expense patch(UUID id, ExpenseDtos.ExpensePatch p) {
        Expense e = expenses.findById(id).orElseThrow(
            () -> ApiException.notFound("EXPENSE_NOT_FOUND", "Expense " + id));
        if (!e.getUserId().equals(current.id()) && current.role() == Role.MEMBER) {
            throw ApiException.forbidden("FORBIDDEN", "Cannot edit another user's expense");
        }
        if (p.sourceId() != null) e.setSourceId(p.sourceId());
        if (p.categoryCode() != null) {
            ExpenseCategory cat = categories.findByCode(p.categoryCode()).orElseThrow(
                () -> ApiException.notFound("CATEGORY_NOT_FOUND", "Category " + p.categoryCode()));
            e.setCategoryId(cat.getId());
            e.setCategoryCode(cat.getCode());
        }
        if (p.amount() != null) {
            e.setAmount(Money.of(p.amount().amount(), p.amount().currency()));
        }
        if (p.details() != null) e.setDetails(p.details());
        if (p.vendor() != null) e.setVendor(p.vendor());
        if (p.occurredAt() != null) e.setOccurredAt(p.occurredAt());
        e.setUpdatedAt(OffsetDateTime.now());
        return expenses.save(e);
    }

    @Transactional
    public Expense reassignSource(UUID id, UUID newSourceId) {
        Expense e = expenses.findById(id).orElseThrow(
            () -> ApiException.notFound("EXPENSE_NOT_FOUND", "Expense " + id));
        if (!sources.existsById(newSourceId)) {
            throw ApiException.notFound("SOURCE_NOT_FOUND", "Source " + newSourceId);
        }
        UUID before = e.getSourceId();
        e.setSourceId(newSourceId);
        e.setUpdatedAt(OffsetDateTime.now());
        Expense saved = expenses.save(e);
        audit.recordEvent("Expense", id.toString(), current.id(), "REASSIGN_SOURCE",
            Map.of("sourceId", before.toString()),
            Map.of("sourceId", newSourceId.toString()));
        return saved;
    }

    @Transactional(readOnly = true)
    public List<ExpenseCategory> listCategories() {
        return categories.findAll();
    }

    @Transactional
    public ExpenseCategory createCategory(ExpenseDtos.CreateCategoryRequest req) {
        if (current.role() != Role.ADMIN) {
            throw ApiException.forbidden("FORBIDDEN", "Only ADMIN may add categories");
        }
        if (categories.existsByCode(req.code())) {
            throw ApiException.conflict("CATEGORY_EXISTS", "Category code already exists: " + req.code());
        }
        ExpenseCategory c = new ExpenseCategory(
            UUID.randomUUID(), req.code().toUpperCase(), req.nameEn(), req.nameAr(), req.iconKey(), true);
        return categories.save(c);
    }
}
