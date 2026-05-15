package ae.gov.pdd.pettycash.notification.dto;

import ae.gov.pdd.pettycash.notification.Notification;
import ae.gov.pdd.pettycash.notification.NotificationRefType;
import ae.gov.pdd.pettycash.notification.NotificationState;
import ae.gov.pdd.pettycash.notification.NotificationType;
import com.fasterxml.jackson.annotation.JsonRawValue;

import java.time.Instant;
import java.util.UUID;

public record NotificationDto(
    UUID id,
    UUID userId,
    NotificationType type,
    boolean actionable,
    NotificationState state,
    NotificationRefType refType,
    UUID refId,
    @JsonRawValue String payload,
    Instant createdAt,
    Instant readAt,
    Instant actedAt
) {
    public static NotificationDto from(Notification n) {
        return new NotificationDto(
            n.getId(),
            n.getUserId(),
            n.getType(),
            n.isActionable(),
            n.getState(),
            n.getRefType(),
            n.getRefId(),
            n.getPayload(),
            n.getCreatedAt(),
            n.getReadAt(),
            n.getActedAt()
        );
    }
}
