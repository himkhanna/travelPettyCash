package ae.gov.pdd.pettycash.user;

import ae.gov.pdd.pettycash.auth.AuthenticatedUser;
import ae.gov.pdd.pettycash.common.error.ApiException;
import jakarta.validation.Valid;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import org.springframework.http.HttpStatus;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.UUID;

/**
 * Directory + admin-only user management. Members and Leaders can read the
 * list (so the mobile inbox can resolve display names for the participant
 * UUIDs that appear on trips/allocations); only Admin + SuperAdmin can
 * create new users or change role / status.
 */
@RestController
@RequestMapping("/api/v1")
public class UserController {

    private final UserRepository users;
    private final PasswordEncoder passwordEncoder;

    public UserController(UserRepository users, PasswordEncoder passwordEncoder) {
        this.users = users;
        this.passwordEncoder = passwordEncoder;
    }

    @GetMapping("/users")
    public List<UserDto> list() {
        return users.findAll().stream()
            .map(UserDto::from)
            .toList();
    }

    @PostMapping("/users")
    @PreAuthorize("hasRole('ADMIN') or hasRole('SUPER_ADMIN')")
    @Transactional
    public UserDto create(@Valid @RequestBody CreateUserRequest body) {
        String username = body.username().toLowerCase().trim();
        if (users.existsByUsername(username)) {
            throw new ApiException(
                HttpStatus.CONFLICT,
                "users/duplicate-username",
                "Username already in use",
                "A user with username '" + username + "' already exists."
            );
        }
        User u = new User(
            UUID.randomUUID(),
            username,
            body.displayName().trim(),
            body.displayNameAr().trim(),
            body.email().trim().toLowerCase(),
            passwordEncoder.encode(body.password()),
            body.role()
        );
        users.save(u);
        return UserDto.from(u);
    }

    @PatchMapping("/users/{id}")
    @PreAuthorize("hasRole('ADMIN') or hasRole('SUPER_ADMIN')")
    @Transactional
    public UserDto patch(
        @PathVariable UUID id,
        @Valid @RequestBody PatchUserRequest body,
        @AuthenticationPrincipal AuthenticatedUser caller
    ) {
        User u = users.findById(id).orElseThrow(() -> notFound(id));

        // Guard rails: admins can't lock themselves out by demoting / disabling.
        if (id.equals(caller.userId())) {
            if (body.role() != null && body.role() != u.getRole()) {
                throw new ApiException(
                    HttpStatus.BAD_REQUEST,
                    "users/self-role-change",
                    "Cannot change own role",
                    "An admin may not change their own role."
                );
            }
            if (body.active() != null && !body.active()) {
                throw new ApiException(
                    HttpStatus.BAD_REQUEST,
                    "users/self-deactivate",
                    "Cannot deactivate yourself",
                    "Use another admin to deactivate your own account."
                );
            }
        }

        if (body.displayName() != null) u.setDisplayName(body.displayName().trim());
        if (body.displayNameAr() != null) u.setDisplayNameAr(body.displayNameAr().trim());
        if (body.email() != null) u.setEmail(body.email().trim().toLowerCase());
        if (body.role() != null) u.setRole(body.role());
        if (body.active() != null) u.setActive(body.active());
        if (body.password() != null && !body.password().isBlank()) {
            u.setPasswordHash(passwordEncoder.encode(body.password()));
        }
        return UserDto.from(u);
    }

    // ---- DTOs ---------------------------------------------------------

    public record UserDto(
        UUID id,
        String username,
        String displayName,
        String displayNameAr,
        String email,
        UserRole role,
        boolean active
    ) {
        public static UserDto from(User u) {
            return new UserDto(
                u.getId(),
                u.getUsername(),
                u.getDisplayName(),
                u.getDisplayNameAr(),
                u.getEmail(),
                u.getRole(),
                u.isActive()
            );
        }
    }

    public record CreateUserRequest(
        @NotBlank @Pattern(regexp = "[a-z][a-z0-9_]{2,31}") String username,
        @NotBlank @Size(max = 128) String displayName,
        @NotBlank @Size(max = 128) String displayNameAr,
        @NotBlank @Email @Size(max = 255) String email,
        @NotNull UserRole role,
        @NotBlank @Size(min = 8, max = 128) String password
    ) {}

    public record PatchUserRequest(
        @Size(max = 128) String displayName,
        @Size(max = 128) String displayNameAr,
        @Email @Size(max = 255) String email,
        UserRole role,
        Boolean active,
        @Size(min = 8, max = 128) String password
    ) {}

    private static ApiException notFound(UUID id) {
        return new ApiException(
            HttpStatus.NOT_FOUND,
            "users/not-found",
            "User not found",
            "No user with id " + id
        );
    }
}
