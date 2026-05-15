package ae.gov.pdd.pettycash.expense;

import ae.gov.pdd.pettycash.auth.AuthenticatedUser;
import ae.gov.pdd.pettycash.common.idempotency.IdempotencyService;
import ae.gov.pdd.pettycash.expense.dto.CreateExpenseRequest;
import ae.gov.pdd.pettycash.expense.dto.ExpenseDto;
import ae.gov.pdd.pettycash.expense.dto.ExpenseSummaryDto;
import ae.gov.pdd.pettycash.expense.dto.PatchExpenseRequest;
import ae.gov.pdd.pettycash.expense.dto.ReassignSourceRequest;
import jakarta.validation.Valid;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

@RestController
@RequestMapping("/api/v1")
public class ExpenseController {

    private final ExpenseService service;
    private final IdempotencyService idempotency;

    public ExpenseController(ExpenseService service, IdempotencyService idempotency) {
        this.service = service;
        this.idempotency = idempotency;
    }

    @GetMapping("/trips/{tripId}/expenses")
    public List<ExpenseDto> list(
        @PathVariable UUID tripId,
        @RequestParam(name = "userId", required = false) UUID userId,
        @RequestParam(name = "categoryCode", required = false) List<String> categoryCodes,
        @RequestParam(name = "sourceId", required = false) List<UUID> sourceIds,
        @RequestParam(name = "memberId", required = false) List<UUID> memberIds,
        @RequestParam(name = "from", required = false) Instant from,
        @RequestParam(name = "to",   required = false) Instant to,
        @AuthenticationPrincipal AuthenticatedUser caller
    ) {
        return service.list(tripId, caller, new ExpenseService.Filter(
            userId, categoryCodes, sourceIds, memberIds, from, to
        ));
    }

    @GetMapping("/expenses/{id}")
    public ExpenseDto detail(
        @PathVariable UUID id,
        @AuthenticationPrincipal AuthenticatedUser caller
    ) {
        return service.get(id, caller);
    }

    @PostMapping("/trips/{tripId}/expenses")
    public ExpenseDto create(
        @PathVariable UUID tripId,
        @Valid @RequestBody CreateExpenseRequest body,
        @RequestHeader(name = "Idempotency-Key", required = false) String idempotencyKey,
        @AuthenticationPrincipal AuthenticatedUser caller
    ) {
        String key = IdempotencyService.require(idempotencyKey);
        return idempotency.runOrReplay(
            key, caller.userId(), "POST /trips/expenses", ExpenseDto.class,
            () -> service.create(tripId, body, caller)
        );
    }

    @PatchMapping("/expenses/{id}")
    public ExpenseDto patch(
        @PathVariable UUID id,
        @Valid @RequestBody PatchExpenseRequest body,
        @AuthenticationPrincipal AuthenticatedUser caller
    ) {
        return service.patch(id, body, caller);
    }

    @PatchMapping("/expenses/{id}/source")
    public ExpenseDto reassignSource(
        @PathVariable UUID id,
        @Valid @RequestBody ReassignSourceRequest body,
        @AuthenticationPrincipal AuthenticatedUser caller
    ) {
        return service.reassignSource(id, body.sourceId(), caller);
    }

    @GetMapping("/trips/{tripId}/expenses/summary")
    public ExpenseSummaryDto summary(
        @PathVariable UUID tripId,
        @RequestParam(name = "scope", required = false, defaultValue = "trip") String scope,
        @RequestParam(name = "groupBy", required = false, defaultValue = "category") String groupBy,
        @RequestParam(name = "userId", required = false) UUID userId,
        @AuthenticationPrincipal AuthenticatedUser caller
    ) {
        return service.summary(tripId, caller, scope, groupBy, userId);
    }
}
