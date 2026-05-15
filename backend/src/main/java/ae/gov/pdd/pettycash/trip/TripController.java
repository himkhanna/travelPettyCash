package ae.gov.pdd.pettycash.trip;

import ae.gov.pdd.pettycash.auth.AuthenticatedUser;
import ae.gov.pdd.pettycash.trip.dto.CreateTripRequest;
import ae.gov.pdd.pettycash.trip.dto.TripBalancesDto;
import ae.gov.pdd.pettycash.trip.dto.TripDto;
import jakarta.validation.Valid;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.UUID;

@RestController
@RequestMapping("/api/v1")
public class TripController {

    private final TripService service;

    public TripController(TripService service) {
        this.service = service;
    }

    @GetMapping("/trips")
    public List<TripDto> list(
        @AuthenticationPrincipal AuthenticatedUser caller,
        @RequestParam(name = "status", required = false) TripStatus status
    ) {
        return service.listForCaller(caller, status);
    }

    @GetMapping("/trips/{id}")
    public TripDto detail(
        @PathVariable UUID id,
        @AuthenticationPrincipal AuthenticatedUser caller
    ) {
        return service.get(id, caller);
    }

    @PostMapping("/trips")
    @PreAuthorize("hasRole('ADMIN') or hasRole('SUPER_ADMIN')")
    public TripDto create(
        @Valid @RequestBody CreateTripRequest body,
        @AuthenticationPrincipal AuthenticatedUser caller
    ) {
        return service.create(body, caller);
    }

    @PatchMapping("/trips/{id}/close")
    @PreAuthorize("hasRole('ADMIN') or hasRole('SUPER_ADMIN')")
    public TripDto close(
        @PathVariable UUID id,
        @AuthenticationPrincipal AuthenticatedUser caller
    ) {
        return service.close(id, caller);
    }

    @GetMapping("/trips/{id}/balances")
    public TripBalancesDto balances(
        @PathVariable UUID id,
        @RequestParam(name = "scope", required = false, defaultValue = "trip") String scope,
        @AuthenticationPrincipal AuthenticatedUser caller
    ) {
        return service.balances(id, caller, scope);
    }
}
