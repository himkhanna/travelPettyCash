package ae.gov.pdd.pettycash.auth;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.Instant;
import java.util.Optional;
import java.util.UUID;

public interface RefreshTokenRepository extends JpaRepository<RefreshToken, UUID> {

    Optional<RefreshToken> findByTokenHash(String tokenHash);

    /** Revoke every still-valid refresh token for a user (replay-detection response). */
    @Modifying
    @Query("""
        UPDATE RefreshToken r
           SET r.revokedAt = :at
         WHERE r.userId    = :userId
           AND r.revokedAt IS NULL
        """)
    int revokeAllForUser(@Param("userId") UUID userId, @Param("at") Instant at);
}
