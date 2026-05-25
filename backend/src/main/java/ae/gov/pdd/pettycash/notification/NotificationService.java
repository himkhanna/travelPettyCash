package ae.gov.pdd.pettycash.notification;

import ae.gov.pdd.pettycash.auth.AuthenticatedUser;
import ae.gov.pdd.pettycash.common.error.ApiException;
import ae.gov.pdd.pettycash.notification.dto.NotificationDto;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Clock;
import java.util.List;
import java.util.Map;
import java.util.UUID;

/**
 * Owns the {@code notifications} table. The other services (allocation,
 * transfer, trip) call {@link #fanOut} when an event happens to insert
 * one row per recipient. Recipients see their inbox via
 * {@link #listForCaller} and flip state via {@link #markRead} /
 * {@link #markActedByRef}.
 */
@Service
public class NotificationService {

    private final NotificationRepository repo;
    private final ObjectMapper json;
    private final Clock clock;

    @Autowired
    public NotificationService(NotificationRepository repo, ObjectMapper json) {
        this(repo, json, Clock.systemUTC());
    }

    NotificationService(NotificationRepository repo, ObjectMapper json, Clock clock) {
        this.repo = repo;
        this.json = json;
        this.clock = clock;
    }

    /**
     * Inserts one row per recipient. All rows share the same {@code type},
     * {@code refType/refId}, {@code payload}, and {@code actionable} flag;
     * only {@code userId} differs.
     */
    @Transactional
    public void fanOut(
        NotificationType type,
        boolean actionable,
        NotificationRefType refType,
        UUID refId,
        Map<String, Object> payload,
        Iterable<UUID> recipients
    ) {
        String payloadJson = serialize(payload);
        for (UUID recipient : recipients) {
            if (recipient == null) continue;
            repo.save(new Notification(
                UUID.randomUUID(),
                recipient,
                type,
                actionable,
                refType,
                refId,
                payloadJson
            ));
        }
    }

    /**
     * Marks every notification that pointed at the given (refType, refId)
     * as ACTED — invoked by AllocationService / TransferService when a
     * pending row gets responded to via its own endpoint. Returns count.
     */
    @Transactional
    public int markActedByRef(NotificationRefType refType, UUID refId) {
        List<Notification> rows = repo.findByRefTypeAndRefId(refType, refId);
        var now = clock.instant();
        int n = 0;
        for (Notification row : rows) {
            if (row.getState() != NotificationState.ACTED) {
                row.markActed(now);
                n++;
            }
        }
        return n;
    }

    /**
     * Flip every UNREAD notification this user has for the given
     * (refType, refId) tuple to READ. Used by chat-thread read so the
     * "open the chat" gesture also clears the CHAT_MESSAGE rows in the
     * activity feed and inbox without forcing the client to mark each
     * one individually. Returns the count flipped.
     */
    @Transactional
    public int markReadByUserAndRef(
        UUID userId, NotificationRefType refType, UUID refId
    ) {
        List<Notification> rows =
            repo.findByUserIdAndRefTypeAndRefId(userId, refType, refId);
        var now = clock.instant();
        int n = 0;
        for (Notification row : rows) {
            if (row.getState() == NotificationState.UNREAD) {
                row.markRead(now);
                n++;
            }
        }
        return n;
    }

    @Transactional(readOnly = true)
    public List<NotificationDto> listForCaller(AuthenticatedUser caller) {
        return repo.findByUserIdOrderByCreatedAtDesc(caller.userId()).stream()
            .map(NotificationDto::from)
            .toList();
    }

    @Transactional(readOnly = true)
    public long unreadCount(AuthenticatedUser caller) {
        return repo.countByUserIdAndState(caller.userId(), NotificationState.UNREAD);
    }

    @Transactional
    public NotificationDto markRead(UUID notificationId, AuthenticatedUser caller) {
        Notification n = load(notificationId, caller);
        n.markRead(clock.instant());
        return NotificationDto.from(n);
    }

    private Notification load(UUID id, AuthenticatedUser caller) {
        Notification n = repo.findById(id).orElseThrow(this::notFound);
        if (!n.getUserId().equals(caller.userId())) {
            // 404 not 403 — don't leak that someone else's row exists.
            throw notFound();
        }
        return n;
    }

    private ApiException notFound() {
        return new ApiException(
            HttpStatus.NOT_FOUND,
            "notifications/not-found",
            "Notification not found",
            "No notification with that id is accessible to this user."
        );
    }

    private String serialize(Map<String, Object> payload) {
        if (payload == null || payload.isEmpty()) return "{}";
        try {
            return json.writeValueAsString(payload);
        } catch (JsonProcessingException e) {
            throw new IllegalStateException("Failed to serialize notification payload", e);
        }
    }
}
