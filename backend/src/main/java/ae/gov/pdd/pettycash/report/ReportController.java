package ae.gov.pdd.pettycash.report;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;
import java.util.UUID;

/**
 * Reports are deferred — see CLAUDE.md §10. Apache POI / OpenPDF + PAdES signing
 * are NOT scaffolded in Phase 3 by design. This endpoint advertises the deferral.
 */
@RestController
@RequestMapping("/api/v1/reports")
public class ReportController {

    @GetMapping("/trip/{tripId}")
    public ResponseEntity<Map<String, String>> getTripReport(@PathVariable UUID tripId) {
        return ResponseEntity.status(HttpStatus.NOT_IMPLEMENTED).body(Map.of(
            "code", "REPORT_DEFERRED",
            "detail", "Server-side report generation pending — see CLAUDE.md §10."
        ));
    }
}
