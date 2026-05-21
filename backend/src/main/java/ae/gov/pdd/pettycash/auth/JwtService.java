package ae.gov.pdd.pettycash.auth;

import ae.gov.pdd.pettycash.user.UserEntity;
import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.Instant;
import java.util.Date;
import javax.crypto.SecretKey;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

/// HS256 JWT minter / parser. The secret comes from application.yml
/// (PETTYCASH_AUTH_SECRET in any non-dev env). Production should swap to
/// asymmetric signing — abstracted behind this service intentionally.
@Service
public class JwtService {

    private final SecretKey key;
    private final long accessTtlSeconds;

    public JwtService(
            @Value("${pettycash.auth.secret}") String secret,
            @Value("${pettycash.auth.accessTtlMinutes:60}") long accessTtlMinutes
    ) {
        if (secret.getBytes(StandardCharsets.UTF_8).length < 32) {
            throw new IllegalStateException(
                    "pettycash.auth.secret must be at least 32 bytes for HS256");
        }
        this.key = Keys.hmacShaKeyFor(secret.getBytes(StandardCharsets.UTF_8));
        this.accessTtlSeconds = Duration.ofMinutes(accessTtlMinutes).toSeconds();
    }

    public String mintAccessToken(UserEntity u) {
        Instant now = Instant.now();
        return Jwts.builder()
                .subject(u.getId())
                .claim("username", u.getUsername())
                .claim("role", u.getRole().name())
                .issuedAt(Date.from(now))
                .expiration(Date.from(now.plusSeconds(accessTtlSeconds)))
                .signWith(key)
                .compact();
    }

    public long accessTtlSeconds() { return accessTtlSeconds; }

    public AuthenticatedUser parse(String token) {
        Claims c = Jwts.parser()
                .verifyWith(key).build()
                .parseSignedClaims(token).getPayload();
        return new AuthenticatedUser(
                c.getSubject(),
                c.get("username", String.class),
                ae.gov.pdd.pettycash.user.UserRole.valueOf(c.get("role", String.class))
        );
    }
}
