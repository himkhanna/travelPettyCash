package ae.gov.pdd.pettycash.notification;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "notifications")
public class Notification {

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "user_id", nullable = false)
    private UUID userId;

    @Enumerated(EnumType.STRING)
    @Column(name = "type", nullable = false, length = 32)
    private NotificationType type;

    @Column(name = "actionable", nullable = false)
    private boolean actionable;

    @Enumerated(EnumType.STRING)
    @Column(name = "state", nullable = false, length = 16)
    private NotificationState state = NotificationState.UNREAD;

    @Enumerated(EnumType.STRING)
    @Column(name = "ref_type", length = 32)
    private NotificationRefType refType;

    @Column(name = "ref_id")
    private UUID refId;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "payload", nullable = false, columnDefinition = "jsonb")
    private String payload = "{}";

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt = Instant.now();

    @Column(name = "read_at")
    private Instant readAt;

    @Column(name = "acted_at")
    private Instant actedAt;

    protected Notification() {
        // JPA
    }

    public Notification(
        UUID id,
        UUID userId,
        NotificationType type,
        boolean actionable,
        NotificationRefType refType,
        UUID refId,
        String payloadJson
    ) {
        this.id = id;
        this.userId = userId;
        this.type = type;
        this.actionable = actionable;
        this.refType = refType;
        this.refId = refId;
        this.payload = payloadJson == null ? "{}" : payloadJson;
    }

    public UUID getId() { return id; }
    public UUID getUserId() { return userId; }
    public NotificationType getType() { return type; }
    public boolean isActionable() { return actionable; }
    public NotificationState getState() { return state; }
    public NotificationRefType getRefType() { return refType; }
    public UUID getRefId() { return refId; }
    public String getPayload() { return payload; }
    public Instant getCreatedAt() { return createdAt; }
    public Instant getReadAt() { return readAt; }
    public Instant getActedAt() { return actedAt; }

    public void markRead(Instant at) {
        if (state == NotificationState.UNREAD) {
            this.state = NotificationState.READ;
            this.readAt = at;
        }
    }

    public void markActed(Instant at) {
        if (state != NotificationState.ACTED) {
            this.state = NotificationState.ACTED;
            this.actedAt = at;
            if (this.readAt == null) this.readAt = at;
        }
    }
}
