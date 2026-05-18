package ae.gov.pdd.pettycash.audit;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

import java.util.Optional;
import java.util.UUID;

public interface AuditLogRepository extends JpaRepository<AuditLog, UUID> {
    @Query("select a from AuditLog a order by a.at desc limit 1")
    Optional<AuditLog> findLatest();
}
