package ae.gov.pdd.pettycash.expense;

import ae.gov.pdd.pettycash.common.NotFoundException;
import ae.gov.pdd.pettycash.expense.ExpenseDtos.CreateExpenseRequest;
import ae.gov.pdd.pettycash.expense.ExpenseDtos.ExpenseView;
import ae.gov.pdd.pettycash.expense.ExpenseDtos.PatchExpenseRequest;
import ae.gov.pdd.pettycash.trip.TripEntity;
import ae.gov.pdd.pettycash.trip.TripRepository;
import jakarta.validation.Valid;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/v1")
public class ExpenseController {

    private final ExpenseRepository expenses;
    private final TripRepository trips;

    public ExpenseController(ExpenseRepository expenses, TripRepository trips) {
        this.expenses = expenses;
        this.trips = trips;
    }

    @GetMapping("/trips/{tripId}/expenses")
    public List<ExpenseView> listForTrip(@PathVariable String tripId) {
        if (!trips.existsById(tripId)) throw new NotFoundException("trip");
        return expenses.findByTripIdAndDeletedAtIsNullOrderByOccurredAtDesc(tripId)
                .stream().map(ExpenseView::of).toList();
    }

    @PostMapping("/trips/{tripId}/expenses")
    public ResponseEntity<ExpenseView> create(
            @PathVariable String tripId,
            @Valid @RequestBody CreateExpenseRequest req
    ) {
        TripEntity trip = trips.findById(tripId).orElseThrow(NotFoundException::new);
        if (!trip.getCurrency().equals(req.amount().currency())) {
            throw new IllegalArgumentException(
                    "Expense currency must match trip currency " + trip.getCurrency());
        }
        ExpenseEntity e = new ExpenseEntity(
                req.id() != null && !req.id().isBlank()
                        ? req.id()
                        : "exp-" + UUID.randomUUID().toString().substring(0, 8),
                tripId, req.userId(), req.sourceId(), req.categoryCode(),
                req.amount().amount(), req.amount().currency(),
                req.quantity(), req.details() == null ? "" : req.details(),
                req.occurredAt(), req.receiptObjectKey(), OffsetDateTime.now()
        );
        return ResponseEntity.ok(ExpenseView.of(expenses.save(e)));
    }

    @PatchMapping("/expenses/{id}")
    public ExpenseView patch(@PathVariable String id, @RequestBody PatchExpenseRequest req) {
        ExpenseEntity e = expenses.findById(id).orElseThrow(NotFoundException::new);
        if (req.sourceId() != null) e.setSourceId(req.sourceId());
        if (req.categoryCode() != null) e.setCategoryCode(req.categoryCode());
        if (req.amount() != null) {
            if (!e.getCurrency().equals(req.amount().currency())) {
                throw new IllegalArgumentException("Cannot change expense currency");
            }
            e.setAmountMinor(req.amount().amount());
        }
        if (req.quantity() != null) e.setQuantity(req.quantity());
        if (req.details() != null) e.setDetails(req.details());
        if (req.occurredAt() != null) e.setOccurredAt(req.occurredAt());
        e.setUpdatedAt(OffsetDateTime.now());
        return ExpenseView.of(expenses.save(e));
    }
}
