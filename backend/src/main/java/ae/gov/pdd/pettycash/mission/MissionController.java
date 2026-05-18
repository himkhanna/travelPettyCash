package ae.gov.pdd.pettycash.mission;

import ae.gov.pdd.pettycash.auth.AuthenticatedUser;
import ae.gov.pdd.pettycash.common.error.ApiException;
import ae.gov.pdd.pettycash.user.UserRole;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

/**
 * Mission CRUD. List is open to all authenticated callers so the
 * mobile / CMS pickers can populate. Create is admin-only.
 */
@RestController
@RequestMapping("/api/v1/missions")
class MissionController {

    private final MissionRepository missions;

    MissionController(MissionRepository missions) {
        this.missions = missions;
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
        if (caller.role() != UserRole.ADMIN
            && caller.role() != UserRole.SUPER_ADMIN) {
            throw new ApiException(
                HttpStatus.FORBIDDEN, "auth/forbidden", "Forbidden",
                "Only Admin / Super Admin can create missions."
            );
        }
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
        Instant closedAt
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
                m.getClosedAt()
            );
        }
    }
}
