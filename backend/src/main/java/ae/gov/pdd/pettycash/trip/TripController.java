package ae.gov.pdd.pettycash.trip;

import ae.gov.pdd.pettycash.common.NotFoundException;
import ae.gov.pdd.pettycash.trip.TripDtos.CreateTripRequest;
import ae.gov.pdd.pettycash.trip.TripDtos.TripView;
import ae.gov.pdd.pettycash.trip.TripDtos.UpdateTripRequest;
import jakarta.validation.Valid;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.UUID;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/v1/trips")
public class TripController {

    private final TripRepository trips;

    public TripController(TripRepository trips) { this.trips = trips; }

    @GetMapping
    public List<TripView> list(@RequestParam(required = false) TripStatus status) {
        return trips.findAll().stream()
                .filter(t -> status == null || t.getStatus() == status)
                .map(TripView::of).toList();
    }

    @GetMapping("/{id}")
    public TripView one(@PathVariable String id) {
        return TripView.of(trips.findById(id).orElseThrow(NotFoundException::new));
    }

    @PostMapping
    @PreAuthorize("hasRole('ADMIN')")
    public ResponseEntity<TripView> create(@Valid @RequestBody CreateTripRequest req) {
        TripEntity t = new TripEntity(
                "trip-" + UUID.randomUUID().toString().substring(0, 8),
                req.name(), req.countryCode(), req.countryName(), req.currency(),
                TripStatus.ACTIVE, req.leaderId(), req.leaderId(),
                req.memberIds(), req.totalBudget().amount(), OffsetDateTime.now()
        );
        return ResponseEntity.ok(TripView.of(trips.save(t)));
    }

    @PutMapping("/{id}")
    @PreAuthorize("hasRole('ADMIN')")
    public TripView update(@PathVariable String id, @Valid @RequestBody UpdateTripRequest req) {
        TripEntity t = trips.findById(id).orElseThrow(NotFoundException::new);
        t.setName(req.name());
        t.setLeaderId(req.leaderId());
        t.setMemberIds(req.memberIds());
        return TripView.of(trips.save(t));
    }

    @PostMapping("/{id}/close")
    @PreAuthorize("hasRole('ADMIN')")
    public TripView close(@PathVariable String id) {
        TripEntity t = trips.findById(id).orElseThrow(NotFoundException::new);
        t.setStatus(TripStatus.CLOSED);
        t.setClosedAt(OffsetDateTime.now());
        return TripView.of(trips.save(t));
    }
}
