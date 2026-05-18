// TODO(§16): replace mock OIDC with real UAE Pass + PDD SSO clients once PDD provides client credentials.
package ae.gov.pdd.pettycash.auth;

import ae.gov.pdd.pettycash.common.ApiException;
import ae.gov.pdd.pettycash.user.User;
import ae.gov.pdd.pettycash.user.UserRepository;
import io.jsonwebtoken.Claims;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.UUID;

/**
 * Mock OIDC auth. Two providers: UAE_PASS and PDD_SSO. Both map to seeded test users
 * regardless of the {@code code} value — sufficient for Phase 3 wire-up.
 *
 * See CLAUDE.md §16 — production identity provider is still TBD.
 */
@RestController
@RequestMapping("/api/v1/auth")
public class AuthController {

    private final UserRepository users;
    private final JwtService jwt;

    public AuthController(UserRepository users, JwtService jwt) {
        this.users = users;
        this.jwt = jwt;
    }

    @PostMapping("/login")
    public ResponseEntity<AuthDtos.AuthSession> login(@Valid @RequestBody AuthDtos.LoginRequest req) {
        String username = switch (req.provider()) {
            case UAE_PASS -> "uaepass-test";
            case PDD_SSO  -> "pddsso-test";
        };
        User user = users.findByUsername(username)
            .orElseThrow(() -> ApiException.notFound("USER_NOT_FOUND",
                "Mock provider user '" + username + "' not seeded — check V002__seed.sql"));
        return ResponseEntity.ok(buildSession(user));
    }

    @PostMapping("/refresh")
    public ResponseEntity<AuthDtos.AuthSession> refresh(@Valid @RequestBody AuthDtos.RefreshRequest req) {
        Claims claims;
        try {
            claims = jwt.parse(req.refreshToken());
        } catch (Exception e) {
            throw ApiException.forbidden("INVALID_REFRESH", "Refresh token invalid or expired");
        }
        if (!"refresh".equals(claims.get("scope", String.class))) {
            throw ApiException.forbidden("INVALID_REFRESH", "Not a refresh token");
        }
        UUID userId = UUID.fromString(claims.getSubject());
        User user = users.findById(userId).orElseThrow(
            () -> ApiException.notFound("USER_NOT_FOUND", "User no longer exists"));
        return ResponseEntity.ok(buildSession(user));
    }

    private AuthDtos.AuthSession buildSession(User user) {
        String access = jwt.issueAccessToken(user.getId().toString(), user.getUsername(), user.getRole().name());
        String refresh = jwt.issueRefreshToken(user.getId().toString());
        AuthDtos.AuthUser dto = new AuthDtos.AuthUser(
            user.getId(), user.getUsername(), user.getDisplayName(), user.getDisplayNameAr(),
            user.getEmail(), user.getRole(), user.isActive());
        return new AuthDtos.AuthSession(access, refresh, dto);
    }
}
