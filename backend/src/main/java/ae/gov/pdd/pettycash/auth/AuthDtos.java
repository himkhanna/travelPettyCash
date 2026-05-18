package ae.gov.pdd.pettycash.auth;

import ae.gov.pdd.pettycash.user.Role;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

import java.util.UUID;

/** Auth request/response DTOs. See CLAUDE.md §3 (DTOs as records). */
public final class AuthDtos {

    public enum Provider { UAE_PASS, PDD_SSO }

    public record LoginRequest(
        @NotNull Provider provider,
        @NotBlank String code
    ) {}

    public record RefreshRequest(@NotBlank String refreshToken) {}

    public record AuthUser(
        UUID id,
        String username,
        String displayName,
        String displayNameAr,
        String email,
        Role role,
        boolean isActive
    ) {}

    public record AuthSession(
        String accessToken,
        String refreshToken,
        AuthUser user
    ) {}

    private AuthDtos() {}
}
