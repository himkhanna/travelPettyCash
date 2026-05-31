package ae.gov.pdd.pettycash.auth;

import ae.gov.pdd.pettycash.auth.dto.AuthTokens;
import ae.gov.pdd.pettycash.common.error.ApiException;
import ae.gov.pdd.pettycash.user.User;
import ae.gov.pdd.pettycash.user.UserRepository;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.Base64;
import java.util.HexFormat;
import java.util.Optional;
import java.util.UUID;

/**
 * Authentication entry point. Handles login (username/password → tokens) and
 * refresh-token rotation with reuse detection per CLAUDE.md §12.
 *
 * <p>On every {@code /auth/refresh} the presented refresh token is marked
 * {@code rotated_at} and a fresh one is issued with {@code replaces_id}
 * pointing at the prior row. If a rotated token is ever presented again,
 * the chain has been replayed (token leak); the entire user's refresh-token
 * inventory is revoked and the caller is forced back to {@code /auth/login}.
 */
@Service
public class AuthService {

    private final UserRepository users;
    private final RefreshTokenRepository refreshTokens;
    private final PasswordEncoder passwordEncoder;
    private final JwtService jwtService;
    private final Duration refreshTtl;
    private final Clock clock;
    private final SecureRandom random = new SecureRandom();

    @Autowired
    public AuthService(
        UserRepository users,
        RefreshTokenRepository refreshTokens,
        PasswordEncoder passwordEncoder,
        JwtService jwtService,
        @Value("${pdd.auth.refresh.ttl:P30D}") Duration refreshTtl
    ) {
        this(users, refreshTokens, passwordEncoder, jwtService, refreshTtl, Clock.systemUTC());
    }

    AuthService(
        UserRepository users,
        RefreshTokenRepository refreshTokens,
        PasswordEncoder passwordEncoder,
        JwtService jwtService,
        Duration refreshTtl,
        Clock clock
    ) {
        this.users = users;
        this.refreshTokens = refreshTokens;
        this.passwordEncoder = passwordEncoder;
        this.jwtService = jwtService;
        this.refreshTtl = refreshTtl;
        this.clock = clock;
    }

    @Transactional
    public LoginResult login(String username, String rawPassword) {
        User user = users.findByUsername(username)
            .orElseThrow(AuthService::invalidCredentials);

        if (!user.isActive() || !passwordEncoder.matches(rawPassword, user.getPasswordHash())) {
            throw invalidCredentials();
        }

        String access = jwtService.issueAccessToken(user);
        IssuedRefresh refresh = issueRefreshToken(user.getId(), null);

        return new LoginResult(
            user,
            new AuthTokens(
                access,
                refresh.raw(),
                jwtService.getAccessTtl().toSeconds(),
                refreshTtl.toSeconds()
            )
        );
    }

    /**
     * Mint an access + refresh pair for a user without going through the
     * password check. Used by the SSO flow once the IdP has confirmed
     * the user's identity. The minted tokens are indistinguishable from
     * password-login tokens — same TTL, same shape — so every
     * downstream consumer (JwtAuthenticationFilter, /me, refresh) keeps
     * working unchanged.
     */
    @Transactional
    public LoginResult mintForUser(User user) {
        if (!user.isActive()) {
            throw invalidCredentials();
        }
        String access = jwtService.issueAccessToken(user);
        IssuedRefresh refresh = issueRefreshToken(user.getId(), null);
        return new LoginResult(
            user,
            new AuthTokens(
                access,
                refresh.raw(),
                jwtService.getAccessTtl().toSeconds(),
                refreshTtl.toSeconds()
            )
        );
    }

    @Transactional
    public LoginResult refresh(String rawRefreshToken) {
        String hash = sha256Hex(rawRefreshToken);
        RefreshToken stored = refreshTokens.findByTokenHash(hash)
            .orElseThrow(AuthService::invalidRefresh);

        Instant now = clock.instant();

        // Replay: a token that was already rotated is being presented again.
        // Treat as a compromise and revoke every refresh token for this user.
        if (stored.getRotatedAt() != null) {
            refreshTokens.revokeAllForUser(stored.getUserId(), now);
            throw invalidRefresh();
        }

        if (stored.getRevokedAt() != null || !stored.isActive(now)) {
            throw invalidRefresh();
        }

        User user = users.findById(stored.getUserId())
            .filter(User::isActive)
            .orElseThrow(AuthService::invalidRefresh);

        stored.markRotated(now);
        IssuedRefresh next = issueRefreshToken(user.getId(), stored.getId());

        String access = jwtService.issueAccessToken(user);
        return new LoginResult(
            user,
            new AuthTokens(
                access,
                next.raw(),
                jwtService.getAccessTtl().toSeconds(),
                refreshTtl.toSeconds()
            )
        );
    }

    public Optional<User> findActive(UUID userId) {
        return users.findById(userId).filter(User::isActive);
    }

    // ---- internals ----------------------------------------------------

    private IssuedRefresh issueRefreshToken(UUID userId, UUID replacesId) {
        Instant now = clock.instant();
        byte[] raw = new byte[48];
        random.nextBytes(raw);
        String rawEncoded = Base64.getUrlEncoder().withoutPadding().encodeToString(raw);
        String hash = sha256Hex(rawEncoded);
        RefreshToken row = new RefreshToken(
            UUID.randomUUID(),
            userId,
            hash,
            now,
            now.plus(refreshTtl),
            replacesId
        );
        refreshTokens.save(row);
        return new IssuedRefresh(rawEncoded);
    }

    private static String sha256Hex(String input) {
        try {
            MessageDigest md = MessageDigest.getInstance("SHA-256");
            byte[] digest = md.digest(input.getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(digest);
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("SHA-256 missing from JCE", e);
        }
    }

    private static ApiException invalidCredentials() {
        return new ApiException(
            HttpStatus.UNAUTHORIZED,
            "auth/invalid-credentials",
            "Invalid username or password",
            "The provided credentials are not valid."
        );
    }

    private static ApiException invalidRefresh() {
        return new ApiException(
            HttpStatus.UNAUTHORIZED,
            "auth/invalid-refresh",
            "Invalid refresh token",
            "The refresh token is expired, revoked, or unknown. Please log in again."
        );
    }

    public record LoginResult(User user, AuthTokens tokens) {}

    private record IssuedRefresh(String raw) {}
}
