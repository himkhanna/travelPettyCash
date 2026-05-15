package ae.gov.pdd.pettycash.fund;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.Instant;
import java.util.UUID;

/**
 * Peer-to-peer transfer between trip participants (CLAUDE.md §5). Same shape
 * as {@link Allocation} but {@code fromUserId} is never null.
 */
@Entity
@Table(name = "transfers")
public class Transfer {

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "trip_id", nullable = false)
    private UUID tripId;

    @Column(name = "from_user_id", nullable = false)
    private UUID fromUserId;

    @Column(name = "to_user_id", nullable = false)
    private UUID toUserId;

    @Column(name = "source_id", nullable = false)
    private UUID sourceId;

    @Column(name = "amount_minor", nullable = false)
    private long amountMinor;

    @Column(name = "currency", nullable = false, length = 3)
    private String currency;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 16)
    private FundsStatus status;

    @Column(name = "note", length = 500)
    private String note;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt = Instant.now();

    @Column(name = "responded_at")
    private Instant respondedAt;

    protected Transfer() {
        // JPA
    }

    public Transfer(
        UUID id,
        UUID tripId,
        UUID fromUserId,
        UUID toUserId,
        UUID sourceId,
        long amountMinor,
        String currency,
        FundsStatus status,
        String note
    ) {
        this.id = id;
        this.tripId = tripId;
        this.fromUserId = fromUserId;
        this.toUserId = toUserId;
        this.sourceId = sourceId;
        this.amountMinor = amountMinor;
        this.currency = currency;
        this.status = status;
        this.note = note;
    }

    public UUID getId() { return id; }
    public UUID getTripId() { return tripId; }
    public UUID getFromUserId() { return fromUserId; }
    public UUID getToUserId() { return toUserId; }
    public UUID getSourceId() { return sourceId; }
    public long getAmountMinor() { return amountMinor; }
    public String getCurrency() { return currency; }
    public FundsStatus getStatus() { return status; }
    public String getNote() { return note; }
    public Instant getCreatedAt() { return createdAt; }
    public Instant getRespondedAt() { return respondedAt; }

    public void respond(FundsStatus status, Instant at) {
        if (this.status != FundsStatus.PENDING) {
            throw new IllegalStateException(
                "Cannot respond to transfer " + id + " — already " + this.status
            );
        }
        if (status != FundsStatus.ACCEPTED && status != FundsStatus.DECLINED) {
            throw new IllegalArgumentException("respond status must be ACCEPTED or DECLINED");
        }
        this.status = status;
        this.respondedAt = at;
    }
}
