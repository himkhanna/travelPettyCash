package ae.gov.pdd.pettycash.expense;

import jakarta.persistence.*;
import java.time.OffsetDateTime;

@Entity
@Table(name = "expenses")
public class ExpenseEntity {
    @Id
    private String id;
    @Column(name = "trip_id", nullable = false)
    private String tripId;
    @Column(name = "user_id", nullable = false)
    private String userId;
    @Column(name = "source_id", nullable = false)
    private String sourceId;
    @Column(name = "category_code", nullable = false)
    private String categoryCode;
    @Column(name = "amount_minor", nullable = false)
    private long amountMinor;
    @Column(nullable = false)
    private String currency;
    @Column(nullable = false)
    private int quantity;
    @Column(nullable = false)
    private String details;
    @Column(name = "occurred_at", nullable = false)
    private OffsetDateTime occurredAt;
    @Column(name = "receipt_object_key")
    private String receiptObjectKey;
    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt;
    @Column(name = "updated_at", nullable = false)
    private OffsetDateTime updatedAt;
    @Column(name = "deleted_at")
    private OffsetDateTime deletedAt;

    protected ExpenseEntity() {}

    public ExpenseEntity(String id, String tripId, String userId, String sourceId,
                         String categoryCode, long amountMinor, String currency,
                         int quantity, String details, OffsetDateTime occurredAt,
                         String receiptObjectKey, OffsetDateTime createdAt) {
        this.id = id; this.tripId = tripId; this.userId = userId; this.sourceId = sourceId;
        this.categoryCode = categoryCode; this.amountMinor = amountMinor; this.currency = currency;
        this.quantity = quantity; this.details = details; this.occurredAt = occurredAt;
        this.receiptObjectKey = receiptObjectKey;
        this.createdAt = createdAt; this.updatedAt = createdAt;
    }

    public String getId() { return id; }
    public String getTripId() { return tripId; }
    public String getUserId() { return userId; }
    public String getSourceId() { return sourceId; }
    public void setSourceId(String v) { this.sourceId = v; }
    public String getCategoryCode() { return categoryCode; }
    public void setCategoryCode(String v) { this.categoryCode = v; }
    public long getAmountMinor() { return amountMinor; }
    public void setAmountMinor(long v) { this.amountMinor = v; }
    public String getCurrency() { return currency; }
    public int getQuantity() { return quantity; }
    public void setQuantity(int v) { this.quantity = v; }
    public String getDetails() { return details; }
    public void setDetails(String v) { this.details = v; }
    public OffsetDateTime getOccurredAt() { return occurredAt; }
    public void setOccurredAt(OffsetDateTime v) { this.occurredAt = v; }
    public String getReceiptObjectKey() { return receiptObjectKey; }
    public void setReceiptObjectKey(String v) { this.receiptObjectKey = v; }
    public OffsetDateTime getCreatedAt() { return createdAt; }
    public OffsetDateTime getUpdatedAt() { return updatedAt; }
    public void setUpdatedAt(OffsetDateTime v) { this.updatedAt = v; }
    public OffsetDateTime getDeletedAt() { return deletedAt; }
    public void setDeletedAt(OffsetDateTime v) { this.deletedAt = v; }
}
