package ae.gov.pdd.pettycash.trip;

import ae.gov.pdd.pettycash.auth.CurrentUser;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.UUID;

@RestController
@RequestMapping("/api/v1/trips")
public class TripController {

    private final TripService service;
    private final CurrentUser current;

    public TripController(TripService service, CurrentUser current) {
        this.service = service;
        this.current = current;
    }

    @GetMapping
    public List<TripDtos.TripView> list(@RequestParam(required = false) TripStatus status) {
        return service.list(status, current.id(), current.role())
            .stream().map(TripDtos.TripView::from).toList();
    }

    @GetMapping("/{id}")
    public TripDtos.TripView get(@PathVariable UUID id) {
        return TripDtos.TripView.from(service.get(id));
    }

    @PostMapping
    @PreAuthorize("hasRole('ADMIN')")
    public ResponseEntity<TripDtos.TripView> create(@Valid @RequestBody TripDtos.CreateTripRequest req) {
        return ResponseEntity.status(HttpStatus.CREATED).body(TripDtos.TripView.from(service.create(req)));
    }

    @PatchMapping("/{id}/close")
    @PreAuthorize("hasRole('ADMIN')")
    public TripDtos.TripView close(@PathVariable UUID id) {
        return TripDtos.TripView.from(service.close(id));
    }

    @GetMapping("/{id}/balances")
    public TripDtos.TripBalances balances(
            @PathVariable UUID id,
            @RequestParam(defaultValue = "me") String scope) {
        return service.balances(id, scope);
    }
}
