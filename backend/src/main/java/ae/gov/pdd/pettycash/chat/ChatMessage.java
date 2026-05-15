package ae.gov.pdd.pettycash.chat;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "chat_messages")
public class ChatMessage {

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "thread_id", nullable = false)
    private UUID threadId;

    @Column(name = "sender_id", nullable = false)
    private UUID senderId;

    @Column(name = "body", nullable = false, length = 2000)
    private String body;

    @Column(name = "sent_at", nullable = false, updatable = false)
    private Instant sentAt = Instant.now();

    @Column(name = "delivered_at")
    private Instant deliveredAt;

    protected ChatMessage() {
        // JPA
    }

    public ChatMessage(UUID id, UUID threadId, UUID senderId, String body) {
        this.id = id;
        this.threadId = threadId;
        this.senderId = senderId;
        this.body = body;
        // The server is the single source of truth for delivery in v1 — the
        // moment the row is committed it counts as delivered. Real push +
        // per-recipient delivered_at land later.
        this.deliveredAt = this.sentAt;
    }

    public UUID getId() { return id; }
    public UUID getThreadId() { return threadId; }
    public UUID getSenderId() { return senderId; }
    public String getBody() { return body; }
    public Instant getSentAt() { return sentAt; }
    public Instant getDeliveredAt() { return deliveredAt; }
}
