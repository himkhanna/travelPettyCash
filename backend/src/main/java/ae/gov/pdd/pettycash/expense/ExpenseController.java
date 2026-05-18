package ae.gov.pdd.pettycash.expense;

import ae.gov.pdd.pettycash.idempotency.Idempotent;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

import java.util.UUID;

@RestController
@RequestMapping("/api/v1")
public class ExpenseController {

    private final ExpenseService service;

    public ExpenseController(ExpenseService service) {
        this.service = service;
    }

    @GetMapping("/trips/{tripId}/expenses")
    public ExpenseDtos.ExpensePage list(
            @PathVariable UUID tripId,
            @RequestParam(required = false, defaultValue = "all") String scope,
            @RequestParam(required = false) String cursor,
            @RequestParam(required = false, defaultValue = "20") int limit) {
        // Phase-3 stub: simple list, no real cursor pagination yet.
        var items = service.listForTrip(tripId, scope).stream()
            .map(ExpenseDtos.ExpenseView::from).toList();
        return new ExpenseDtos.ExpensePage(items, null);
    }

    @PostMapping("/trips/{tripId}/expenses")
    @PreAuthorize("hasAnyRole('MEMBER','LEADER')")
    @Idempotent
    public ResponseEntity<ExpenseDtos.ExpenseView> create(
            @PathVariable UUID tripId,
            @RequestHeader(value = "Idempotency-Key") String idempotencyKey,
            @Valid @RequestBody ExpenseDtos.CreateExpenseRequest req) {
        // Idempotency-Key is persisted for 24h by IdempotencyInterceptor.
        // The client-supplied expense id (UUID) gives a second layer of dedup
        // matching CLAUDE.md §11 (server accepts client UUID as canonical).
        ExpenseDtos.ExpenseView view = ExpenseDtos.ExpenseView.from(service.create(tripId, req));
        return ResponseEntity.status(HttpStatus.CREATED).body(view);
    }

    @PatchMapping("/expenses/{id}")
    public ExpenseDtos.ExpenseView patch(@PathVariable UUID id,
                                         @Valid @RequestBody ExpenseDtos.ExpensePatch p) {
        return ExpenseDtos.ExpenseView.from(service.patch(id, p));
    }

    @PatchMapping("/expenses/{id}/source")
    public ExpenseDtos.ExpenseView reassign(@PathVariable UUID id,
                                            @Valid @RequestBody ExpenseDtos.SourceReassign req) {
        return ExpenseDtos.ExpenseView.from(service.reassignSource(id, req.sourceId()));
    }

    @GetMapping("/categories")
    public java.util.List<ExpenseDtos.CategoryView> categories() {
        return service.listCategories().stream().map(ExpenseDtos.CategoryView::from).toList();
    }

    @PostMapping("/categories")
    @PreAuthorize("hasRole('ADMIN')")
    public ResponseEntity<ExpenseDtos.CategoryView> createCategory(
            @Valid @RequestBody ExpenseDtos.CreateCategoryRequest req) {
        return ResponseEntity.status(HttpStatus.CREATED)
            .body(ExpenseDtos.CategoryView.from(service.createCategory(req)));
    }
}
