package ae.gov.pdd.pettycash.auth.dto;

import ae.gov.pdd.pettycash.user.User;
import ae.gov.pdd.pettycash.user.UserRole;

import java.util.UUID;

public record MeResponse(
    UUID id,
    String username,
    String displayName,
    String displayNameAr,
    String email,
    UserRole role
) {
    public static MeResponse from(User user) {
        return new MeResponse(
            user.getId(),
            user.getUsername(),
            user.getDisplayName(),
            user.getDisplayNameAr(),
            user.getEmail(),
            user.getRole()
        );
    }
}
