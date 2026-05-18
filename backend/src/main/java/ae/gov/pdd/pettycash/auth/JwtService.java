package ae.gov.pdd.pettycash.auth;

import ae.gov.pdd.pettycash.config.JwtProperties;
import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.security.Keys;
import org.springframework.stereotype.Service;

import javax.crypto.SecretKey;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Date;
import java.util.Map;

/**
 * HS256-signed JWTs for the mock OIDC flow.
 * TODO(§16): replace HMAC with RSA + JWKS once UAE Pass / PDD SSO is integrated.
 */
@Service
public class JwtService {

    private final JwtProperties props;
    private final SecretKey key;

    public JwtService(JwtProperties props) {
        this.props = props;
        byte[] keyBytes = props.secret().getBytes(StandardCharsets.UTF_8);
        if (keyBytes.length < 32) {
            throw new IllegalStateException("pettycash.jwt.secret must be at least 32 bytes");
        }
        this.key = Keys.hmacShaKeyFor(keyBytes);
    }

    public String issueAccessToken(String subjectUserId, String username, String role) {
        Instant now = Instant.now();
        Instant exp = now.plus(props.accessTtlMinutes(), ChronoUnit.MINUTES);
        return Jwts.builder()
            .issuer(props.issuer())
            .subject(subjectUserId)
            .issuedAt(Date.from(now))
            .expiration(Date.from(exp))
            .claims(Map.of(
                "username", username,
                "role", role,
                "scope", "access"
            ))
            .signWith(key)
            .compact();
    }

    public String issueRefreshToken(String subjectUserId) {
        Instant now = Instant.now();
        Instant exp = now.plus(props.refreshTtlDays(), ChronoUnit.DAYS);
        return Jwts.builder()
            .issuer(props.issuer())
            .subject(subjectUserId)
            .issuedAt(Date.from(now))
            .expiration(Date.from(exp))
            .claims(Map.of("scope", "refresh"))
            .signWith(key)
            .compact();
    }

    public Claims parse(String token) {
        return Jwts.parser()
            .verifyWith(key)
            .build()
            .parseSignedClaims(token)
            .getPayload();
    }

    public SecretKey key() {
        return key;
    }
}
