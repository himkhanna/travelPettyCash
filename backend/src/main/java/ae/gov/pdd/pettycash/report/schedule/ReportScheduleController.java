package ae.gov.pdd.pettycash.report.schedule;

import ae.gov.pdd.pettycash.auth.AuthenticatedUser;
import ae.gov.pdd.pettycash.common.error.ApiException;
import ae.gov.pdd.pettycash.user.UserRole;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

/**
 * Admin CRUD for scheduled report deliveries. Each row tells the
 * {@link ReportScheduleRunner} to fan out a REPORT_READY notification at
 * its configured UTC hour-of-day; the recipient downloads on demand via
 * the existing /reports endpoints — bytes are never persisted here.
 */
@RestController
@RequestMapping("/api/v1/report-schedules")
class ReportScheduleController {

    private final ReportScheduleRepository repo;

    ReportScheduleController(ReportScheduleRepository repo) {
        this.repo = repo;
    }

    @GetMapping
    public List<ReportScheduleDto> list(
        @AuthenticationPrincipal AuthenticatedUser caller
    ) {
        requireAdmin(caller);
        return repo.findAllByOrderByCreatedAtDesc().stream()
            .map(ReportScheduleDto::from).toList();
    }

    @PostMapping
    public ReportScheduleDto create(
        @Valid @RequestBody CreateRequest req,
        @AuthenticationPrincipal AuthenticatedUser caller
    ) {
        requireAdmin(caller);
        ReportSchedule s = new ReportSchedule(
            UUID.randomUUID(),
            req.scope(),
            req.scopeId(),
            req.kind(),
            req.utcHour(),
            caller.userId()
        );
        return ReportScheduleDto.from(repo.save(s));
    }

    @PatchMapping("/{id}")
    public ReportScheduleDto update(
        @PathVariable UUID id,
        @Valid @RequestBody PatchRequest req,
        @AuthenticationPrincipal AuthenticatedUser caller
    ) {
        requireAdmin(caller);
        ReportSchedule s = repo.findById(id).orElseThrow(this::notFound);
        if (req.active() != null) s.setActive(req.active());
        if (req.utcHour() != null) s.setUtcHour(req.utcHour());
        return ReportScheduleDto.from(repo.save(s));
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<Void> delete(
        @PathVariable UUID id,
        @AuthenticationPrincipal AuthenticatedUser caller
    ) {
        requireAdmin(caller);
        ReportSchedule s = repo.findById(id).orElseThrow(this::notFound);
        repo.delete(s);
        return ResponseEntity.noContent().build();
    }

    private void requireAdmin(AuthenticatedUser caller) {
        if (caller.role() != UserRole.ADMIN
            && caller.role() != UserRole.SUPER_ADMIN) {
            throw new ApiException(
                HttpStatus.FORBIDDEN, "auth/forbidden", "Forbidden",
                "Only Admin / Super Admin can manage report schedules."
            );
        }
    }

    private ApiException notFound() {
        return new ApiException(
            HttpStatus.NOT_FOUND, "report-schedules/not-found",
            "Schedule not found", "No schedule with that id."
        );
    }

    public record CreateRequest(
        @NotNull ReportSchedule.Scope scope,
        @NotNull UUID scopeId,
        @NotNull ReportSchedule.Kind kind,
        @Min(0) @Max(23) int utcHour
    ) {}

    public record PatchRequest(
        Boolean active,
        @Min(0) @Max(23) Integer utcHour
    ) {}

    public record ReportScheduleDto(
        UUID id,
        ReportSchedule.Scope scope,
        UUID scopeId,
        ReportSchedule.Kind kind,
        int utcHour,
        boolean active,
        UUID createdById,
        Instant lastRunAt,
        Instant nextRunAt,
        Instant createdAt
    ) {
        public static ReportScheduleDto from(ReportSchedule s) {
            return new ReportScheduleDto(
                s.getId(),
                s.getScope(),
                s.getScopeId(),
                s.getKind(),
                s.getUtcHour(),
                s.isActive(),
                s.getCreatedById(),
                s.getLastRunAt(),
                s.getNextRunAt(),
                s.getCreatedAt()
            );
        }
    }
}
