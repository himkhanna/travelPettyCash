package ae.gov.pdd.pettycash.fund;

import ae.gov.pdd.pettycash.auth.AuthenticatedUser;
import ae.gov.pdd.pettycash.common.idempotency.IdempotencyService;
import ae.gov.pdd.pettycash.fund.dto.AllocationDto;
import ae.gov.pdd.pettycash.fund.dto.CreateAllocationsRequest;
import ae.gov.pdd.pettycash.fund.dto.RespondRequest;
import jakarta.validation.Valid;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.UUID;

@RestController
@RequestMapping("/api/v1")
public class AllocationController {

    private final AllocationService service;
    private final IdempotencyService idempotency;

    public AllocationController(AllocationService service, IdempotencyService idempotency) {
        this.service = service;
        this.idempotency = idempotency;
    }

    @GetMapping("/trips/{tripId}/allocations")
    public List<AllocationDto> list(
        @PathVariable UUID tripId,
        @RequestParam(name = "memberId", required = false) UUID memberId,
        @AuthenticationPrincipal AuthenticatedUser caller
    ) {
        return service.list(tripId, memberId, caller);
    }

    @PostMapping("/trips/{tripId}/allocations")
    public AllocationDto[] create(
        @PathVariable UUID tripId,
        @Valid @RequestBody CreateAllocationsRequest body,
        @RequestHeader(name = "Idempotency-Key", required = false) String idempotencyKey,
        @AuthenticationPrincipal AuthenticatedUser caller
    ) {
        String key = IdempotencyService.require(idempotencyKey);
        return idempotency.runOrReplay(
            key, caller.userId(), "POST /trips/allocations", AllocationDto[].class,
            () -> service.create(tripId, body, caller).toArray(new AllocationDto[0])
        );
    }

    @PostMapping("/allocations/{id}/respond")
    public AllocationDto respond(
        @PathVariable UUID id,
        @Valid @RequestBody RespondRequest body,
        @AuthenticationPrincipal AuthenticatedUser caller
    ) {
        return service.respond(id, body.response(), caller);
    }
}
