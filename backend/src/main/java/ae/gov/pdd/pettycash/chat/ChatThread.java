package ae.gov.pdd.pettycash.chat;

import jakarta.persistence.CollectionTable;
import jakarta.persistence.Column;
import jakarta.persistence.ElementCollection;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.Table;

import java.time.Instant;
import java.util.HashSet;
import java.util.Set;
import java.util.UUID;

@Entity
@Table(name = "chat_threads")
public class ChatThread {

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "trip_id", nullable = false)
    private UUID tripId;

    @Column(name = "title", nullable = false, length = 128)
    private String title;

    @Column(name = "title_ar", nullable = false, length = 128)
    private String titleAr;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt = Instant.now();

    @Column(name = "last_message_preview", length = 120)
    private String lastMessagePreview;

    @Column(name = "last_message_at")
    private Instant lastMessageAt;

    @ElementCollection(fetch = FetchType.EAGER)
    @CollectionTable(
        name = "chat_thread_members",
        joinColumns = @JoinColumn(name = "thread_id")
    )
    @Column(name = "user_id")
    private Set<UUID> participantIds = new HashSet<>();

    protected ChatThread() {
        // JPA
    }

    public ChatThread(
        UUID id,
        UUID tripId,
        String title,
        String titleAr,
        Set<UUID> participantIds
    ) {
        this.id = id;
        this.tripId = tripId;
        this.title = title;
        this.titleAr = titleAr;
        this.participantIds = new HashSet<>(participantIds);
    }

    public UUID getId() { return id; }
    public UUID getTripId() { return tripId; }
    public String getTitle() { return title; }
    public String getTitleAr() { return titleAr; }
    public Instant getCreatedAt() { return createdAt; }
    public String getLastMessagePreview() { return lastMessagePreview; }
    public Instant getLastMessageAt() { return lastMessageAt; }
    public Set<UUID> getParticipantIds() { return participantIds; }

    /** Updated on every send; capped at 120 chars (mobile preview chip). */
    public void touch(String preview, Instant at) {
        this.lastMessagePreview = preview == null ? null
            : preview.length() > 120 ? preview.substring(0, 117) + "…" : preview;
        this.lastMessageAt = at;
    }
}
