package ae.gov.pdd.pettycash.fund;

import jakarta.persistence.*;
import java.time.OffsetDateTime;

@Entity
@Table(name = "allocations")
public class AllocationEntity {
    @Id private String id;
    @Column(name = "trip_id", nullable = false) private String tripId;
    @Column(name = "from_user_id") private String fromUserId;
    @Column(name = "to_user_id", nullable = false) private String toUserId;
    @Column(name = "source_id", nullable = false) private String sourceId;
    @Column(name = "amount_minor", nullable = false) private long amountMinor;
    @Column(nullable = false) private String currency;
    @Enumerated(EnumType.STRING)
    @Column(nullable = false) private TransferStatus status;
    private String note;
    @Column(name = "created_at", nullable = false) private OffsetDateTime createdAt;
    @Column(name = "responded_at") private OffsetDateTime respondedAt;

    protected AllocationEntity() {}

    public AllocationEntity(String id, String tripId, String fromUserId, String toUserId,
                            String sourceId, long amountMinor, String currency,
                            TransferStatus status, String note,
                            OffsetDateTime createdAt, OffsetDateTime respondedAt) {
        this.id = id; this.tripId = tripId; this.fromUserId = fromUserId;
        this.toUserId = toUserId; this.sourceId = sourceId; this.amountMinor = amountMinor;
        this.currency = currency; this.status = status; this.note = note;
        this.createdAt = createdAt; this.respondedAt = respondedAt;
    }

    public String getId() { return id; }
    public String getTripId() { return tripId; }
    public String getFromUserId() { return fromUserId; }
    public String getToUserId() { return toUserId; }
    public String getSourceId() { return sourceId; }
    public long getAmountMinor() { return amountMinor; }
    public String getCurrency() { return currency; }
    public TransferStatus getStatus() { return status; }
    public String getNote() { return note; }
    public OffsetDateTime getCreatedAt() { return createdAt; }
    public OffsetDateTime getRespondedAt() { return respondedAt; }
}
