package ae.gov.pdd.pettycash.report;

import ae.gov.pdd.pettycash.common.ApiException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.time.OffsetDateTime;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;

/**
 * Report endpoints. Generation is implemented; signing is still deferred —
 * see CLAUDE.md §10 and ADR-003.
 */
@RestController
@RequestMapping("/api/v1/reports")
public class ReportController {

    public record GenerateResponse(UUID reportId, String url, OffsetDateTime expiresAt, String sha256) {}

    private final ReportService service;

    public ReportController(ReportService service) {
        this.service = service;
    }

    @GetMapping("/trip/{tripId}")
    @PreAuthorize("isAuthenticated()")
    public ResponseEntity<GenerateResponse> getTripReport(
            @PathVariable UUID tripId,
            @RequestParam String type,
            @RequestParam String format,
            @RequestParam(required = false) UUID userId) {
        ReportType rt = parseType(type);
        ReportFormat rf = parseFormat(format);
        ReportService.GenerateResult result = service.generate(
            new ReportRequest(tripId, rt, rf, userId));
        return ResponseEntity.ok(new GenerateResponse(
            result.reportId(), result.url().toString(), result.expiresAt(), result.sha256()));
    }

    /**
     * Signing is deferred per ADR-003. Endpoint returns 501 with a stable error code
     * so the mobile app can show the "coming in a future release" tooltip.
     */
    @PostMapping("/{reportId}/sign")
    @PreAuthorize("isAuthenticated()")
    public ResponseEntity<Map<String, String>> sign(@PathVariable UUID reportId) {
        return ResponseEntity.status(HttpStatus.NOT_IMPLEMENTED).body(Map.of(
            "code", "SIGNING_DEFERRED",
            "detail", "Signing key custody pending — see ADR-003."
        ));
    }

    private ReportType parseType(String s) {
        try {
            return ReportType.valueOf(s.toUpperCase(Locale.ROOT));
        } catch (IllegalArgumentException e) {
            throw ApiException.badRequest("REPORT_TYPE_UNKNOWN",
                "type must be one of USER, TRIP, FINANCE, DG");
        }
    }

    private ReportFormat parseFormat(String s) {
        try {
            return ReportFormat.valueOf(s.toUpperCase(Locale.ROOT));
        } catch (IllegalArgumentException e) {
            throw ApiException.badRequest("REPORT_FORMAT_INVALID",
                "format must be xlsx or pdf");
        }
    }
}
