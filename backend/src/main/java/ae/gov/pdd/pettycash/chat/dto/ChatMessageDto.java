package ae.gov.pdd.pettycash.chat.dto;

import ae.gov.pdd.pettycash.chat.ChatMessage;

import java.time.Instant;
import java.util.UUID;

public record ChatMessageDto(
    UUID id,
    UUID threadId,
    UUID senderId,
    String body,
    Instant sentAt,
    Instant deliveredAt,
    Instant readAt
) {
    public static ChatMessageDto from(ChatMessage m, Instant readAt) {
        return new ChatMessageDto(
            m.getId(),
            m.getThreadId(),
            m.getSenderId(),
            m.getBody(),
            m.getSentAt(),
            m.getDeliveredAt(),
            readAt
        );
    }
}
