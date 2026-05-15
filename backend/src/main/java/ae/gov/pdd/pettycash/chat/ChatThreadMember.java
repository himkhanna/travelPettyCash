package ae.gov.pdd.pettycash.chat;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.IdClass;
import jakarta.persistence.Table;

import java.io.Serializable;
import java.time.Instant;
import java.util.Objects;
import java.util.UUID;

/**
 * Per-user thread membership row. The {@code participantIds} ElementCollection
 * on {@link ChatThread} drives the M:N join for "who's in this thread"; this
 * entity exists to hang the per-user {@code last_read_at} timestamp off the
 * same row so unread counts can be computed without a side table.
 */
@Entity
@Table(name = "chat_thread_members")
@IdClass(ChatThreadMember.Key.class)
public class ChatThreadMember {

    @Id
    @Column(name = "thread_id", nullable = false)
    private UUID threadId;

    @Id
    @Column(name = "user_id", nullable = false)
    private UUID userId;

    @Column(name = "joined_at", nullable = false, updatable = false)
    private Instant joinedAt = Instant.now();

    @Column(name = "last_read_at")
    private Instant lastReadAt;

    protected ChatThreadMember() {
        // JPA
    }

    public ChatThreadMember(UUID threadId, UUID userId) {
        this.threadId = threadId;
        this.userId = userId;
    }

    public UUID getThreadId() { return threadId; }
    public UUID getUserId() { return userId; }
    public Instant getJoinedAt() { return joinedAt; }
    public Instant getLastReadAt() { return lastReadAt; }

    public void markRead(Instant at) {
        this.lastReadAt = at;
    }

    /** Composite key for {@code @IdClass}. */
    public static class Key implements Serializable {
        private UUID threadId;
        private UUID userId;

        public Key() {}

        public Key(UUID threadId, UUID userId) {
            this.threadId = threadId;
            this.userId = userId;
        }

        @Override
        public boolean equals(Object o) {
            if (this == o) return true;
            if (!(o instanceof Key k)) return false;
            return Objects.equals(threadId, k.threadId)
                && Objects.equals(userId, k.userId);
        }

        @Override
        public int hashCode() {
            return Objects.hash(threadId, userId);
        }
    }
}
