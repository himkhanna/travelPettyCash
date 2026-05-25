package ae.gov.pdd.pettycash.report;

import ae.gov.pdd.pettycash.auth.AuthenticatedUser;
import org.springframework.core.io.ByteArrayResource;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.UUID;

/**
 * Server-rendered report downloads per CLAUDE.md §10. Generates real
 * PDF (OpenPDF) and Excel (Apache POI) bytes — no in-app preview, no
 * client-side rendering. Access control is enforced by {@link ReportService};
 * see role guards there.
 *
 * Four report kinds:
 * - user           : one user's spending grouped by source + category (PDF + XLSX)
 * - trip-full      : every member's expenses on the trip (XLSX)
 * - finance-letter : letterhead summary for finance (PDF; signing is a
 *                    separate step — see CLAUDE.md §10)
 * - dg             : Director General summary view (PDF, read-only)
 */
@RestController
@RequestMapping("/api/v1/reports")
class ReportController {

    private final ReportService service;

    ReportController(ReportService service) {
        this.service = service;
    }

    @GetMapping("/trip/{tripId}/user/{userId}")
    public ResponseEntity<ByteArrayResource> userReport(
        @PathVariable UUID tripId,
        @PathVariable UUID userId,
        @RequestParam(name = "format", defaultValue = "pdf") String format,
        @AuthenticationPrincipal AuthenticatedUser caller
    ) {
        ReportService.Rendered out = service.userReport(tripId, userId, format, caller);
        return respond(out);
    }

    @GetMapping("/trip/{tripId}/full")
    public ResponseEntity<ByteArrayResource> tripFullReport(
        @PathVariable UUID tripId,
        @RequestParam(name = "format", defaultValue = "xlsx") String format,
        @AuthenticationPrincipal AuthenticatedUser caller
    ) {
        ReportService.Rendered out = service.tripFullReport(tripId, format, caller);
        return respond(out);
    }

    @GetMapping("/trip/{tripId}/finance")
    public ResponseEntity<ByteArrayResource> financeLetter(
        @PathVariable UUID tripId,
        @AuthenticationPrincipal AuthenticatedUser caller
    ) {
        ReportService.Rendered out = service.financeLetter(tripId, caller);
        return respond(out);
    }

    @GetMapping("/trip/{tripId}/dg")
    public ResponseEntity<ByteArrayResource> dgReport(
        @PathVariable UUID tripId,
        @AuthenticationPrincipal AuthenticatedUser caller
    ) {
        ReportService.Rendered out = service.dgReport(tripId, caller);
        return respond(out);
    }

    /** Daily snapshot — same shape as trip-full but limited to one UTC day. */
    @GetMapping("/trip/{tripId}/daily")
    public ResponseEntity<ByteArrayResource> tripDailyReport(
        @PathVariable UUID tripId,
        @RequestParam("date") String dateIso,
        @RequestParam(name = "format", defaultValue = "xlsx") String format,
        @AuthenticationPrincipal AuthenticatedUser caller
    ) {
        ReportService.Rendered out = service.tripDailyReport(
            tripId, java.time.LocalDate.parse(dateIso), format, caller
        );
        return respond(out);
    }

    /** Mission-wide rollup XLSX — optional `date` for a one-day mission snapshot. */
    @GetMapping("/mission/{missionId}")
    public ResponseEntity<ByteArrayResource> missionReport(
        @PathVariable UUID missionId,
        @RequestParam(name = "date", required = false) String dateIso,
        @AuthenticationPrincipal AuthenticatedUser caller
    ) {
        ReportService.Rendered out = service.missionReport(
            missionId,
            dateIso == null ? null : java.time.LocalDate.parse(dateIso),
            caller
        );
        return respond(out);
    }

    private ResponseEntity<ByteArrayResource> respond(ReportService.Rendered r) {
        return ResponseEntity.ok()
            .contentType(MediaType.parseMediaType(r.contentType()))
            .header(HttpHeaders.CONTENT_DISPOSITION,
                "attachment; filename=\"" + r.filename() + "\"")
            .contentLength(r.bytes().length)
            .body(new ByteArrayResource(r.bytes()));
    }
}
