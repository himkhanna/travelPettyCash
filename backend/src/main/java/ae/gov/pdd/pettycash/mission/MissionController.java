package ae.gov.pdd.pettycash.mission;

import ae.gov.pdd.pettycash.auth.AuthenticatedUser;
import ae.gov.pdd.pettycash.common.MoneyDto;
import ae.gov.pdd.pettycash.common.error.ApiException;
import ae.gov.pdd.pettycash.trip.TripRepository;
import ae.gov.pdd.pettycash.user.UserRole;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

/**
 * Mission CRUD. List is open to all authenticated callers so the
 * mobile / CMS pickers can populate. Mutations are admin-only.
 */
@RestController
@RequestMapping("/api/v1/missions")
class MissionController {

    private final MissionRepository missions;
    private final TripRepository trips;

    MissionController(MissionRepository missions, TripRepository trips) {
        this.missions = missions;
        this.trips = trips;
    }

    private void requireAdmin(AuthenticatedUser caller) {
        if (caller.role() != UserRole.ADMIN
            && caller.role() != UserRole.SUPER_ADMIN) {
            throw new ApiException(
                HttpStatus.FORBIDDEN, "auth/forbidden", "Forbidden",
                "Only Admin / Super Admin can modify missions."
            );
        }
    }

    private Mission load(UUID id) {
        return missions.findById(id).orElseThrow(() -> new ApiException(
            HttpStatus.NOT_FOUND, "missions/not-found", "Mission not found",
            "No mission with id " + id + "."
        ));
    }

    @GetMapping
    public List<MissionDto> list() {
        return missions.findAll().stream()
            .sorted((a, b) -> b.getCreatedAt().compareTo(a.getCreatedAt()))
            .map(MissionDto::from)
            .toList();
    }

    @PostMapping
    public MissionDto create(
        @Valid @RequestBody CreateMissionRequest req,
        @AuthenticationPrincipal AuthenticatedUser caller
    ) {
        requireAdmin(caller);
        String code = req.code() != null && !req.code().isBlank()
            ? req.code().trim().toUpperCase()
            : _genCode(req.name());
        if (missions.existsByCode(code)) {
            throw new ApiException(
                HttpStatus.CONFLICT, "missions/duplicate-code",
                "Duplicate code",
                "Mission code '" + code + "' is already in use."
            );
        }
        Mission m = new Mission(
            UUID.randomUUID(),
            req.name().trim(),
            req.nameAr() == null ? null : req.nameAr().trim(),
            code,
            req.description(),
            req.parentMissionId(),
            caller.userId()
        );
        return MissionDto.from(missions.save(m));
    }

    @PutMapping("/{id}")
    public MissionDto update(
        @PathVariable UUID id,
        @Valid @RequestBody UpdateMissionRequest req,
        @AuthenticationPrincipal AuthenticatedUser caller
    ) {
        requireAdmin(caller);
        Mission m = load(id);

        // Parent change: reject self-parent and immediate cycles. Deeper
        // cycle detection is overkill for the v1 UI which keeps nesting flat.
        if (req.parentMissionId() != null) {
            if (req.parentMissionId().equals(id)) {
                throw new ApiException(
                    HttpStatus.BAD_REQUEST, "missions/parent-cycle",
                    "Invalid parent", "A mission cannot be its own parent."
                );
            }
            if (!missions.existsById(req.parentMissionId())) {
                throw new ApiException(
                    HttpStatus.BAD_REQUEST, "missions/parent-missing",
                    "Parent mission not found",
                    "Parent mission " + req.parentMissionId() + " does not exist."
                );
            }
        }

        m.rename(req.name().trim(),
            req.nameAr() == null ? null : req.nameAr().trim());
        m.setDescription(req.description());
        m.setParentMissionId(req.parentMissionId());

        // Status transition: ACTIVE → CLOSED records `closed_at`, CLOSED →
        // ACTIVE re-opens. No-op when status matches current.
        if (req.status() != null && req.status() != m.getStatus()) {
            if (req.status() == MissionStatus.CLOSED) {
                m.close(Instant.now());
            } else {
                m.reopen();
            }
        }

        return MissionDto.from(missions.save(m));
    }

    /** Assign or increase the mission's total budget (Admin only). Setting
     *  a higher amount is how a budget is "increased later" (BRD §2.2). */
    @PatchMapping("/{id}/budget")
    public MissionDto setBudget(
        @PathVariable UUID id,
        @Valid @RequestBody SetBudgetRequest req,
        @AuthenticationPrincipal AuthenticatedUser caller
    ) {
        requireAdmin(caller);
        Mission m = load(id);
        m.setBudget(req.amount(), req.currency().toUpperCase());
        return MissionDto.from(missions.save(m));
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<Void> delete(
        @PathVariable UUID id,
        @AuthenticationPrincipal AuthenticatedUser caller
    ) {
        requireAdmin(caller);
        Mission m = load(id);

        long trips = this.trips.countByMissionId(id);
        if (trips > 0) {
            throw new ApiException(
                HttpStatus.CONFLICT, "missions/has-trips",
                "Mission has trips",
                "Cannot delete: " + trips + " trip(s) are attached. "
                    + "Reassign or delete them first."
            );
        }
        long children = missions.countByParentMissionId(id);
        if (children > 0) {
            throw new ApiException(
                HttpStatus.CONFLICT, "missions/has-children",
                "Mission has children",
                "Cannot delete: " + children + " child mission(s) exist. "
                    + "Reassign or delete them first."
            );
        }

        missions.delete(m);
        return ResponseEntity.noContent().build();
    }

    private static String _genCode(String name) {
        String slug = name.toUpperCase().replaceAll("[^A-Z0-9]+", "-");
        if (slug.length() > 16) slug = slug.substring(0, 16);
        return slug + "-" + Integer.toHexString(
            (int) (Instant.now().getEpochSecond() & 0xffff)
        ).toUpperCase();
    }

    public record CreateMissionRequest(
        @NotBlank String name,
        String nameAr,
        String code,
        String description,
        UUID parentMissionId
    ) {}

    public record UpdateMissionRequest(
        @NotBlank String name,
        String nameAr,
        String description,
        UUID parentMissionId,
        MissionStatus status
    ) {}

    public record SetBudgetRequest(
        @Min(0) long amount,
        @NotBlank @Pattern(regexp = "[A-Za-z]{3}") String currency
    ) {}

    public record MissionDto(
        UUID id,
        String name,
        String nameAr,
        String code,
        String description,
        UUID parentMissionId,
        MissionStatus status,
        UUID createdById,
        Instant createdAt,
        Instant closedAt,
        // Mission-level budget (BRD §2.2); null until assigned by an Admin.
        MoneyDto budget
    ) {
        public static MissionDto from(Mission m) {
            return new MissionDto(
                m.getId(),
                m.getName(),
                m.getNameAr(),
                m.getCode(),
                m.getDescription(),
                m.getParentMissionId(),
                m.getStatus(),
                m.getCreatedById(),
                m.getCreatedAt(),
                m.getClosedAt(),
                m.getBudgetCurrency() == null
                    ? null
                    : new MoneyDto(m.getBudgetMinor(), m.getBudgetCurrency())
            );
        }
    }
}
