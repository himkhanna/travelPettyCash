package ae.gov.pdd.pettycash.insight;

import ae.gov.pdd.pettycash.auth.AuthenticatedUser;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.UUID;

/**
 * Read-only Smart Insights for a trip. Access control lives in
 * {@link InsightsService} (mirrors the balances endpoint), so there is no
 * method-level {@code @PreAuthorize} here — an inaccessible trip 404s.
 */
@RestController
@RequestMapping("/api/v1")
class InsightsController {

    private final InsightsService service;

    InsightsController(InsightsService service) {
        this.service = service;
    }

    @GetMapping("/trips/{id}/insights")
    public TripInsightsDto insights(
        @PathVariable UUID id,
        @AuthenticationPrincipal AuthenticatedUser caller
    ) {
        return service.forTrip(id, caller);
    }
}
