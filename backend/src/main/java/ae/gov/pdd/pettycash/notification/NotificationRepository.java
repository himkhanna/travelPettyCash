package ae.gov.pdd.pettycash.notification;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface NotificationRepository extends JpaRepository<Notification, UUID> {
    List<Notification> findByUserIdOrderByCreatedAtDesc(UUID userId);
    long countByUserIdAndState(UUID userId, NotificationState state);
    List<Notification> findByRefTypeAndRefId(NotificationRefType refType, UUID refId);
}
