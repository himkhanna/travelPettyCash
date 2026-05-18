package ae.gov.pdd.pettycash.audit;

import ae.gov.pdd.pettycash.auth.AuthenticatedUser;
import ae.gov.pdd.pettycash.common.error.ApiException;
import ae.gov.pdd.pettycash.user.UserRole;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

/**
 * Admin-only audit feed. Returns a unified, time-ordered list of financial
 * mutations across the system (trip creates/closes, allocations, transfers,
 * expense creates) synthesized from the existing tables.
 *
 * Not the tamper-evident hash-chained audit log CLAUDE.md §5 describes — that
 * lands in a future slice. This view gives Admins immediate "who did what,
 * when" visibility against real data without the schema migration burden.
 */
@RestController
@RequestMapping("/api/v1/audit")
class AuditController {

    private final AuditService service;

    AuditController(AuditService service) {
        this.service = service;
    }

    @GetMapping
    public List<AuditEntry> list(
        @RequestParam(name = "tripId", required = false) UUID tripId,
        @RequestParam(name = "actorId", required = false) UUID actorId,
        @RequestParam(name = "from", required = false) Instant from,
        @RequestParam(name = "to", required = false) Instant to,
        @RequestParam(name = "limit", defaultValue = "200") int limit,
        @AuthenticationPrincipal AuthenticatedUser caller
    ) {
        if (caller.role() != UserRole.ADMIN
            && caller.role() != UserRole.SUPER_ADMIN) {
            throw new ApiException(
                HttpStatus.FORBIDDEN, "auth/forbidden", "Forbidden",
                "Only Admin / Super Admin can view the audit trail."
            );
        }
        return service.list(
            tripId, actorId, from, to,
            Math.max(1, Math.min(1000, limit))
        );
    }
}
