package ae.gov.pdd.pettycash.user;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

public final class UserDtos {
    private UserDtos() {}

    public record UserView(
            String id,
            String username,
            String displayName,
            String displayNameAr,
            String email,
            UserRole role,
            boolean active
    ) {
        public static UserView of(UserEntity u) {
            return new UserView(
                    u.getId(), u.getUsername(), u.getDisplayName(),
                    u.getDisplayNameAr(), u.getEmail(), u.getRole(), u.isActive()
            );
        }
    }

    public record CreateUserRequest(
            @NotBlank String username,
            @NotBlank String displayName,
            @NotBlank String displayNameAr,
            @Email @NotBlank String email,
            @NotNull UserRole role,
            boolean active
    ) {}

    public record UpdateUserRequest(
            @NotBlank String displayName,
            @NotBlank String displayNameAr,
            @Email @NotBlank String email,
            @NotNull UserRole role,
            boolean active
    ) {}
}
