package ae.gov.pdd.pettycash.auth;

import ae.gov.pdd.pettycash.user.User;
import ae.gov.pdd.pettycash.user.UserRole;
import io.jsonwebtoken.Claims;
import io.jsonwebtoken.JwtException;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import jakarta.annotation.PostConstruct;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import javax.crypto.SecretKey;
import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.Date;
import java.util.UUID;

/**
 * Issues + verifies short-lived JWT access tokens (HS256).
 *
 * <p>HS256 is acceptable for Phase 1 because the backend is a single
 * monolith. When the architecture splits (services + edge proxy) we swap
 * to RS256 with keys from Vault per CLAUDE.md §12; the controller contract
 * (Bearer token in the Authorization header) does not change.
 */
@Service
public class JwtService {

    private static final String CLAIM_USERNAME = "username";
    private static final String CLAIM_ROLE     = "role";

    private final String secret;
    private final Duration accessTtl;
    private final String issuer;
    private final Clock clock;

    private SecretKey signingKey;

    @Autowired
    public JwtService(
        @Value("${pdd.auth.jwt.secret}") String secret,
        @Value("${pdd.auth.jwt.access-ttl:PT15M}") Duration accessTtl,
        @Value("${pdd.auth.jwt.issuer:pdd-petty-cash}") String issuer
    ) {
        this(secret, accessTtl, issuer, Clock.systemUTC());
    }

    // Package-visible for tests that need a deterministic clock.
    JwtService(String secret, Duration accessTtl, String issuer, Clock clock) {
        this.secret = secret;
        this.accessTtl = accessTtl;
        this.issuer = issuer;
        this.clock = clock;
    }

    @PostConstruct
    void initKey() {
        byte[] bytes = secret.getBytes(StandardCharsets.UTF_8);
        if (bytes.length < 32) {
            throw new IllegalStateException(
                "pdd.auth.jwt.secret must be at least 32 bytes for HS256 (got "
                    + bytes.length + ")."
            );
        }
        this.signingKey = Keys.hmacShaKeyFor(bytes);
    }

    public String issueAccessToken(User user) {
        Instant now = clock.instant();
        Instant exp = now.plus(accessTtl);
        return Jwts.builder()
            .issuer(issuer)
            .subject(user.getId().toString())
            .issuedAt(Date.from(now))
            .expiration(Date.from(exp))
            .claim(CLAIM_USERNAME, user.getUsername())
            .claim(CLAIM_ROLE, user.getRole().name())
            .signWith(signingKey)
            .compact();
    }

    public Duration getAccessTtl() {
        return accessTtl;
    }

    /** Throws {@link JwtException} when the token is invalid or expired. */
    public Parsed parse(String token) {
        Claims c = Jwts.parser()
            .verifyWith(signingKey)
            .requireIssuer(issuer)
            // Bind the injected Clock so expiry is evaluated against the same
            // time source the issuer used — important for deterministic tests.
            .clock(() -> Date.from(clock.instant()))
            .build()
            .parseSignedClaims(token)
            .getPayload();
        return new Parsed(
            UUID.fromString(c.getSubject()),
            c.get(CLAIM_USERNAME, String.class),
            UserRole.valueOf(c.get(CLAIM_ROLE, String.class)),
            c.getExpiration().toInstant()
        );
    }

    public record Parsed(UUID userId, String username, UserRole role, Instant expiresAt) {}
}
