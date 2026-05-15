package ae.gov.pdd.pettycash.auth;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "refresh_tokens")
public class RefreshToken {

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "user_id", nullable = false)
    private UUID userId;

    @Column(name = "token_hash", nullable = false, unique = true, length = 128)
    private String tokenHash;

    @Column(name = "issued_at", nullable = false, updatable = false)
    private Instant issuedAt;

    @Column(name = "expires_at", nullable = false)
    private Instant expiresAt;

    @Column(name = "rotated_at")
    private Instant rotatedAt;

    @Column(name = "revoked_at")
    private Instant revokedAt;

    @Column(name = "replaces_id")
    private UUID replacesId;

    protected RefreshToken() {
        // JPA
    }

    public RefreshToken(
        UUID id,
        UUID userId,
        String tokenHash,
        Instant issuedAt,
        Instant expiresAt,
        UUID replacesId
    ) {
        this.id = id;
        this.userId = userId;
        this.tokenHash = tokenHash;
        this.issuedAt = issuedAt;
        this.expiresAt = expiresAt;
        this.replacesId = replacesId;
    }

    public UUID getId() { return id; }
    public UUID getUserId() { return userId; }
    public String getTokenHash() { return tokenHash; }
    public Instant getIssuedAt() { return issuedAt; }
    public Instant getExpiresAt() { return expiresAt; }
    public Instant getRotatedAt() { return rotatedAt; }
    public Instant getRevokedAt() { return revokedAt; }
    public UUID getReplacesId() { return replacesId; }

    public boolean isActive(Instant now) {
        return rotatedAt == null
            && revokedAt == null
            && now.isBefore(expiresAt);
    }

    public void markRotated(Instant at) {
        this.rotatedAt = at;
    }

    public void markRevoked(Instant at) {
        this.revokedAt = at;
    }
}
