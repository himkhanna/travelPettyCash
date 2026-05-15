package ae.gov.pdd.pettycash.expense;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "expenses")
public class Expense {

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "trip_id", nullable = false)
    private UUID tripId;

    @Column(name = "user_id", nullable = false)
    private UUID userId;

    @Column(name = "source_id", nullable = false)
    private UUID sourceId;

    @Column(name = "category_code", nullable = false, length = 32)
    private String categoryCode;

    @Column(name = "amount_minor", nullable = false)
    private long amountMinor;

    @Column(name = "currency", nullable = false, length = 3)
    private String currency;

    @Column(name = "quantity", nullable = false)
    private int quantity = 1;

    @Column(name = "details", nullable = false, length = 500)
    private String details = "";

    @Column(name = "occurred_at", nullable = false)
    private Instant occurredAt;

    @Column(name = "receipt_object_key", length = 256)
    private String receiptObjectKey;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt = Instant.now();

    @Column(name = "updated_at")
    private Instant updatedAt;

    @Column(name = "deleted_at")
    private Instant deletedAt;

    protected Expense() {
        // JPA
    }

    public Expense(
        UUID id,
        UUID tripId,
        UUID userId,
        UUID sourceId,
        String categoryCode,
        long amountMinor,
        String currency,
        int quantity,
        String details,
        Instant occurredAt,
        String receiptObjectKey
    ) {
        this.id = id;
        this.tripId = tripId;
        this.userId = userId;
        this.sourceId = sourceId;
        this.categoryCode = categoryCode;
        this.amountMinor = amountMinor;
        this.currency = currency;
        this.quantity = quantity;
        this.details = details == null ? "" : details;
        this.occurredAt = occurredAt;
        this.receiptObjectKey = receiptObjectKey;
    }

    public UUID getId() { return id; }
    public UUID getTripId() { return tripId; }
    public UUID getUserId() { return userId; }
    public UUID getSourceId() { return sourceId; }
    public String getCategoryCode() { return categoryCode; }
    public long getAmountMinor() { return amountMinor; }
    public String getCurrency() { return currency; }
    public int getQuantity() { return quantity; }
    public String getDetails() { return details; }
    public Instant getOccurredAt() { return occurredAt; }
    public String getReceiptObjectKey() { return receiptObjectKey; }
    public Instant getCreatedAt() { return createdAt; }
    public Instant getUpdatedAt() { return updatedAt; }
    public Instant getDeletedAt() { return deletedAt; }

    public void reassignSource(UUID newSourceId, Instant at) {
        // CLAUDE.md §5 — source reassignment is an audited event. The audit
        // log table lands in its own slice; for now we just update + bump
        // updatedAt so reports can detect the change via the timestamp.
        this.sourceId = newSourceId;
        this.updatedAt = at;
    }

    public void apply(Patch patch, Instant at) {
        if (patch.categoryCode() != null) this.categoryCode = patch.categoryCode();
        if (patch.amountMinor() != null) this.amountMinor = patch.amountMinor();
        if (patch.details() != null) this.details = patch.details();
        if (patch.occurredAt() != null) this.occurredAt = patch.occurredAt();
        if (patch.quantity() != null) this.quantity = patch.quantity();
        this.updatedAt = at;
    }

    public record Patch(
        String categoryCode,
        Long amountMinor,
        Integer quantity,
        String details,
        Instant occurredAt
    ) {}
}
