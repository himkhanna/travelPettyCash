package ae.gov.pdd.pettycash.fund;

import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.UUID;

@RestController
@RequestMapping("/api/v1")
public class FundController {

    private final FundService service;
    private final SourceRepository sources;

    public FundController(FundService service, SourceRepository sources) {
        this.service = service;
        this.sources = sources;
    }

    @GetMapping("/sources")
    public List<FundDtos.SourceView> listSources() {
        return sources.findAll().stream().map(FundDtos.SourceView::from).toList();
    }

    @GetMapping("/trips/{tripId}/allocations")
    public List<FundDtos.AllocationView> listAllocations(@PathVariable UUID tripId) {
        return service.listForTrip(tripId).stream().map(FundDtos.AllocationView::from).toList();
    }

    @PostMapping("/trips/{tripId}/allocations")
    @PreAuthorize("hasAnyRole('ADMIN','LEADER')")
    public ResponseEntity<List<FundDtos.AllocationView>> createAllocations(
            @PathVariable UUID tripId,
            @RequestHeader(value = "Idempotency-Key", required = false) String idempotencyKey,
            @Valid @RequestBody FundDtos.CreateAllocationsRequest req) {
        var created = service.createAllocations(tripId, req).stream()
            .map(FundDtos.AllocationView::from).toList();
        return ResponseEntity.status(HttpStatus.CREATED).body(created);
    }

    @PostMapping("/allocations/{id}/respond")
    @PreAuthorize("hasAnyRole('MEMBER','LEADER')")
    public FundDtos.AllocationView respond(@PathVariable UUID id,
                                           @Valid @RequestBody FundDtos.RespondRequest req) {
        return FundDtos.AllocationView.from(service.respond(id, req.action()));
    }

    @PostMapping("/trips/{tripId}/transfers")
    @PreAuthorize("hasAnyRole('MEMBER','LEADER')")
    public ResponseEntity<FundDtos.TransferView> createTransfer(
            @PathVariable UUID tripId,
            @RequestHeader(value = "Idempotency-Key", required = false) String idempotencyKey,
            @Valid @RequestBody FundDtos.CreateTransferRequest req) {
        return ResponseEntity.status(HttpStatus.CREATED)
            .body(FundDtos.TransferView.from(service.createTransfer(tripId, req)));
    }
}
