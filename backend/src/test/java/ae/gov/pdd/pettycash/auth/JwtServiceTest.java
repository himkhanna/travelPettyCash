package ae.gov.pdd.pettycash.auth;

import ae.gov.pdd.pettycash.user.User;
import ae.gov.pdd.pettycash.user.UserRole;
import io.jsonwebtoken.ExpiredJwtException;
import io.jsonwebtoken.JwtException;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class JwtServiceTest {

    private static final String SECRET = "test-secret-test-secret-test-secret-32b";
    private static final UUID USER_ID = UUID.fromString("11111111-1111-1111-1111-111111111111");

    private JwtService jwt;

    @BeforeEach
    void setUp() {
        jwt = newServiceAt(Instant.parse("2026-05-15T10:00:00Z"));
    }

    private JwtService newServiceAt(Instant now) {
        Clock fixed = Clock.fixed(now, ZoneOffset.UTC);
        JwtService svc = new JwtService(SECRET, Duration.ofMinutes(15), "pdd-petty-cash", fixed);
        svc.initKey();
        return svc;
    }

    private User userOf(UserRole role) {
        return new User(USER_ID, "fatima", "Fatima", "فاطمة", "f@x.ae", "irrelevant-hash", role);
    }

    @Test
    void issuesTokenContainingSubjectAndRoleClaim() {
        String token = jwt.issueAccessToken(userOf(UserRole.LEADER));
        JwtService.Parsed parsed = jwt.parse(token);

        assertThat(parsed.userId()).isEqualTo(USER_ID);
        assertThat(parsed.username()).isEqualTo("fatima");
        assertThat(parsed.role()).isEqualTo(UserRole.LEADER);
        assertThat(parsed.expiresAt()).isEqualTo(Instant.parse("2026-05-15T10:15:00Z"));
    }

    @Test
    void parseRejectsTamperedSignature() {
        String token = jwt.issueAccessToken(userOf(UserRole.MEMBER));
        // Flip the last character of the signature segment.
        char[] chars = token.toCharArray();
        chars[chars.length - 1] = chars[chars.length - 1] == 'a' ? 'b' : 'a';
        String tampered = new String(chars);

        assertThatThrownBy(() -> jwt.parse(tampered))
            .isInstanceOf(JwtException.class);
    }

    @Test
    void parseRejectsExpiredToken() {
        JwtService issuedAt10 = newServiceAt(Instant.parse("2026-05-15T10:00:00Z"));
        String token = issuedAt10.issueAccessToken(userOf(UserRole.ADMIN));

        // Same key, different clock — token is 1h old, TTL is 15m.
        JwtService at11 = newServiceAt(Instant.parse("2026-05-15T11:00:00Z"));

        assertThatThrownBy(() -> at11.parse(token))
            .isInstanceOf(ExpiredJwtException.class);
    }

    @Test
    void parseRejectsTokenSignedByDifferentSecret() {
        Clock fixed = Clock.fixed(Instant.parse("2026-05-15T10:00:00Z"), ZoneOffset.UTC);
        JwtService other = new JwtService(
            "different-secret-different-secret-32b!", Duration.ofMinutes(15), "pdd-petty-cash", fixed
        );
        other.initKey();
        String foreign = other.issueAccessToken(userOf(UserRole.MEMBER));

        assertThatThrownBy(() -> jwt.parse(foreign))
            .isInstanceOf(JwtException.class);
    }

    @Test
    void parseRejectsTokenWithWrongIssuer() {
        Clock fixed = Clock.fixed(Instant.parse("2026-05-15T10:00:00Z"), ZoneOffset.UTC);
        JwtService strangerIssuer = new JwtService(SECRET, Duration.ofMinutes(15), "other-issuer", fixed);
        strangerIssuer.initKey();
        String foreign = strangerIssuer.issueAccessToken(userOf(UserRole.MEMBER));

        assertThatThrownBy(() -> jwt.parse(foreign))
            .isInstanceOf(JwtException.class);
    }

    @Test
    void initKeyRejectsShortSecret() {
        JwtService weak = new JwtService(
            "too-short", Duration.ofMinutes(15), "pdd-petty-cash", Clock.systemUTC()
        );
        assertThatThrownBy(weak::initKey).isInstanceOf(IllegalStateException.class);
    }
}
