package ae.gov.pdd.pettycash.chat.dto;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

public record ChatThreadDto(
    UUID id,
    UUID tripId,
    String title,
    String titleAr,
    List<UUID> participantIds,
    int unreadCount,
    String lastMessagePreview,
    Instant lastMessageAt
) {}
