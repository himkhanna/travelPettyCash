package ae.gov.pdd.pettycash.fund;

import ae.gov.pdd.pettycash.auth.AuthenticatedUser;
import ae.gov.pdd.pettycash.common.idempotency.IdempotencyService;
import ae.gov.pdd.pettycash.fund.dto.CreateTransferRequest;
import ae.gov.pdd.pettycash.fund.dto.RespondRequest;
import ae.gov.pdd.pettycash.fund.dto.TransferDto;
import jakarta.validation.Valid;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.UUID;

@RestController
@RequestMapping("/api/v1")
public class TransferController {

    private final TransferService service;
    private final IdempotencyService idempotency;

    public TransferController(TransferService service, IdempotencyService idempotency) {
        this.service = service;
        this.idempotency = idempotency;
    }

    @GetMapping("/trips/{tripId}/transfers")
    public List<TransferDto> list(
        @PathVariable UUID tripId,
        @AuthenticationPrincipal AuthenticatedUser caller
    ) {
        return service.list(tripId, caller);
    }

    @PostMapping("/trips/{tripId}/transfers")
    public TransferDto create(
        @PathVariable UUID tripId,
        @Valid @RequestBody CreateTransferRequest body,
        @RequestHeader(name = "Idempotency-Key", required = false) String idempotencyKey,
        @AuthenticationPrincipal AuthenticatedUser caller
    ) {
        String key = IdempotencyService.require(idempotencyKey);
        return idempotency.runOrReplay(
            key, caller.userId(), "POST /trips/transfers", TransferDto.class,
            () -> service.create(tripId, body, caller)
        );
    }

    @PostMapping("/transfers/{id}/respond")
    public TransferDto respond(
        @PathVariable UUID id,
        @Valid @RequestBody RespondRequest body,
        @AuthenticationPrincipal AuthenticatedUser caller
    ) {
        return service.respond(id, body.response(), caller);
    }
}
