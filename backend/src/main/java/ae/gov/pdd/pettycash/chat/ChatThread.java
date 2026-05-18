package ae.gov.pdd.pettycash.chat;

import jakarta.persistence.*;

import java.time.OffsetDateTime;
import java.util.LinkedHashSet;
import java.util.Objects;
import java.util.Set;
import java.util.UUID;

/**
 * Chat thread scoped to a trip. 1:1 or group. See CLAUDE.md §5.
 */
@Entity
@Table(name = "chat_thread", indexes = {
    @Index(name = "idx_chat_thread_trip", columnList = "trip_id")
})
public class ChatThread {

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "trip_id", nullable = false)
    private UUID tripId;

    @Column(name = "title", length = 256)
    private String title;

    @Column(name = "title_ar", length = 256)
    private String titleAr;

    @ElementCollection
    @CollectionTable(name = "chat_thread_participant",
        joinColumns = @JoinColumn(name = "thread_id"))
    @Column(name = "user_id", nullable = false)
    private Set<UUID> participantIds = new LinkedHashSet<>();

    @Column(name = "last_message_preview", length = 512)
    private String lastMessagePreview;

    @Column(name = "last_message_at")
    private OffsetDateTime lastMessageAt;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt = OffsetDateTime.now();

    public ChatThread() {}

    public UUID getId() { return id; }
    public void setId(UUID id) { this.id = id; }
    public UUID getTripId() { return tripId; }
    public void setTripId(UUID tripId) { this.tripId = tripId; }
    public String getTitle() { return title; }
    public void setTitle(String title) { this.title = title; }
    public String getTitleAr() { return titleAr; }
    public void setTitleAr(String titleAr) { this.titleAr = titleAr; }
    public Set<UUID> getParticipantIds() { return participantIds; }
    public void setParticipantIds(Set<UUID> participantIds) { this.participantIds = participantIds; }
    public String getLastMessagePreview() { return lastMessagePreview; }
    public void setLastMessagePreview(String lastMessagePreview) { this.lastMessagePreview = lastMessagePreview; }
    public OffsetDateTime getLastMessageAt() { return lastMessageAt; }
    public void setLastMessageAt(OffsetDateTime lastMessageAt) { this.lastMessageAt = lastMessageAt; }
    public OffsetDateTime getCreatedAt() { return createdAt; }
    public void setCreatedAt(OffsetDateTime createdAt) { this.createdAt = createdAt; }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (!(o instanceof ChatThread t)) return false;
        return Objects.equals(id, t.id);
    }

    @Override
    public int hashCode() { return Objects.hash(id); }
}
