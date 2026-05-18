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
    public List<Expense> listForTrip(UUID tripId, String scope) {
        if ("mine".equalsIgnoreCase(scope)) {
            return expenses.findByTripIdAndUserId(tripId, current.id());
        }
        return expenses.findByTripId(tripId);
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
