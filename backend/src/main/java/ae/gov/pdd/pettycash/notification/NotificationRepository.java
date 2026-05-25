package ae.gov.pdd.pettycash.notification;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface NotificationRepository extends JpaRepository<Notification, UUID> {
    List<Notification> findByUserIdOrderByCreatedAtDesc(UUID userId);
    long countByUserIdAndState(UUID userId, NotificationState state);
    List<Notification> findByRefTypeAndRefId(NotificationRefType refType, UUID refId);
    /** Used by chat-thread read to flip every CHAT_MESSAGE for this user
     *  pointing at the thread from UNREAD → READ. */
    List<Notification> findByUserIdAndRefTypeAndRefId(
        UUID userId, NotificationRefType refType, UUID refId);
}
