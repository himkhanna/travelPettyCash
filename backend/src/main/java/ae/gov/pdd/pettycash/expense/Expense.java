package ae.gov.pdd.pettycash.expense;

import ae.gov.pdd.pettycash.common.Money;
import jakarta.persistence.*;

import java.time.OffsetDateTime;
import java.util.Objects;
import java.util.UUID;

/**
 * Expense entity. See CLAUDE.md §5. Source assignment can change post-creation;
 * change must go through an audited event. Balance may go negative (UI warns only).
 */
@Entity
@Table(name = "expense", indexes = {
    @Index(name = "idx_expense_trip", columnList = "trip_id"),
    @Index(name = "idx_expense_user", columnList = "user_id"),
    @Index(name = "idx_expense_source", columnList = "source_id"),
    @Index(name = "idx_expense_occurred_at", columnList = "occurred_at")
})
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

    @Column(name = "category_id", nullable = false)
    private UUID categoryId;

    @Column(name = "category_code", nullable = false, length = 32)
    private String categoryCode;

    @Embedded
    @AttributeOverrides({
        @AttributeOverride(name = "amount", column = @Column(name = "amount", nullable = false)),
        @AttributeOverride(name = "currency", column = @Column(name = "currency", nullable = false, length = 3))
    })
    private Money amount;

    @Column(name = "quantity", nullable = false)
    private int quantity = 1;

    /** Computed = amount / quantity. Stored for reporting convenience. */
    @Column(name = "unit_cost_amount")
    private Long unitCostAmount;

    @Column(name = "details", length = 1024)
    private String details;

    @Column(name = "occurred_at", nullable = false)
    private OffsetDateTime occurredAt;

    @Column(name = "receipt_object_key", length = 512)
    private String receiptObjectKey;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt = OffsetDateTime.now();

    @Column(name = "updated_at", nullable = false)
    private OffsetDateTime updatedAt = OffsetDateTime.now();

    @Column(name = "deleted_at")
    private OffsetDateTime deletedAt;

    public Expense() {}

    public UUID getId() { return id; }
    public void setId(UUID id) { this.id = id; }
    public UUID getTripId() { return tripId; }
    public void setTripId(UUID tripId) { this.tripId = tripId; }
    public UUID getUserId() { return userId; }
    public void setUserId(UUID userId) { this.userId = userId; }
    public UUID getSourceId() { return sourceId; }
    public void setSourceId(UUID sourceId) { this.sourceId = sourceId; }
    public UUID getCategoryId() { return categoryId; }
    public void setCategoryId(UUID categoryId) { this.categoryId = categoryId; }
    public String getCategoryCode() { return categoryCode; }
    public void setCategoryCode(String categoryCode) { this.categoryCode = categoryCode; }
    public Money getAmount() { return amount; }
    public void setAmount(Money amount) { this.amount = amount; }
    public int getQuantity() { return quantity; }
    public void setQuantity(int quantity) { this.quantity = quantity; }
    public Long getUnitCostAmount() { return unitCostAmount; }
    public void setUnitCostAmount(Long unitCostAmount) { this.unitCostAmount = unitCostAmount; }
    public String getDetails() { return details; }
    public void setDetails(String details) { this.details = details; }
    public OffsetDateTime getOccurredAt() { return occurredAt; }
    public void setOccurredAt(OffsetDateTime occurredAt) { this.occurredAt = occurredAt; }
    public String getReceiptObjectKey() { return receiptObjectKey; }
    public void setReceiptObjectKey(String receiptObjectKey) { this.receiptObjectKey = receiptObjectKey; }
    public OffsetDateTime getCreatedAt() { return createdAt; }
    public void setCreatedAt(OffsetDateTime createdAt) { this.createdAt = createdAt; }
    public OffsetDateTime getUpdatedAt() { return updatedAt; }
    public void setUpdatedAt(OffsetDateTime updatedAt) { this.updatedAt = updatedAt; }
    public OffsetDateTime getDeletedAt() { return deletedAt; }
    public void setDeletedAt(OffsetDateTime deletedAt) { this.deletedAt = deletedAt; }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (!(o instanceof Expense e)) return false;
        return Objects.equals(id, e.id);
    }

    @Override
    public int hashCode() { return Objects.hash(id); }
}
