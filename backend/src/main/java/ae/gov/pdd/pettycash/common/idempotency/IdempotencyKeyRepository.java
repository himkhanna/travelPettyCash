package ae.gov.pdd.pettycash.common.idempotency;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;
import java.util.UUID;

public interface IdempotencyKeyRepository extends JpaRepository<IdempotencyKey, UUID> {
    Optional<IdempotencyKey> findByKeyAndUserIdAndEndpoint(
        String key, UUID userId, String endpoint
    );
}
