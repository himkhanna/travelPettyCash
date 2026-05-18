package ae.gov.pdd.pettycash.trip;

import ae.gov.pdd.pettycash.common.Money;
import jakarta.persistence.*;

import java.time.OffsetDateTime;
import java.util.LinkedHashSet;
import java.util.Objects;
import java.util.Set;
import java.util.UUID;

/**
 * Trip aggregate. See CLAUDE.md §5.
 * Single-currency by design — no FX within a trip.
 */
@Entity
@Table(name = "trip")
public class Trip {

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "name", nullable = false, length = 256)
    private String name;

    @Column(name = "country_code", nullable = false, length = 2)
    private String countryCode;

    @Column(name = "country_name", length = 128)
    private String countryName;

    @Column(name = "currency", nullable = false, length = 3)
    private String currency;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 16)
    private TripStatus status = TripStatus.DRAFT;

    @Column(name = "created_by", nullable = false)
    private UUID createdBy;

    @Column(name = "leader_id", nullable = false)
    private UUID leaderId;

    @Embedded
    @AttributeOverrides({
        @AttributeOverride(name = "amount", column = @Column(name = "total_budget_amount", nullable = false)),
        @AttributeOverride(name = "currency", column = @Column(name = "total_budget_currency", nullable = false, length = 3))
    })
    private Money totalBudget;

    @Column(name = "image_url", length = 1024)
    private String imageUrl;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt = OffsetDateTime.now();

    @Column(name = "closed_at")
    private OffsetDateTime closedAt;

    @ElementCollection(fetch = FetchType.EAGER)
    @CollectionTable(name = "trip_member", joinColumns = @JoinColumn(name = "trip_id"),
        indexes = @Index(name = "idx_trip_member_trip", columnList = "trip_id"))
    @Column(name = "user_id", nullable = false)
    private Set<UUID> memberIds = new LinkedHashSet<>();

    public Trip() {}

    public UUID getId() { return id; }
    public void setId(UUID id) { this.id = id; }
    public String getName() { return name; }
    public void setName(String name) { this.name = name; }
    public String getCountryCode() { return countryCode; }
    public void setCountryCode(String countryCode) { this.countryCode = countryCode; }
    public String getCountryName() { return countryName; }
    public void setCountryName(String countryName) { this.countryName = countryName; }
    public String getCurrency() { return currency; }
    public void setCurrency(String currency) { this.currency = currency; }
    public TripStatus getStatus() { return status; }
    public void setStatus(TripStatus status) { this.status = status; }
    public UUID getCreatedBy() { return createdBy; }
    public void setCreatedBy(UUID createdBy) { this.createdBy = createdBy; }
    public UUID getLeaderId() { return leaderId; }
    public void setLeaderId(UUID leaderId) { this.leaderId = leaderId; }
    public Money getTotalBudget() { return totalBudget; }
    public void setTotalBudget(Money totalBudget) { this.totalBudget = totalBudget; }
    public String getImageUrl() { return imageUrl; }
    public void setImageUrl(String imageUrl) { this.imageUrl = imageUrl; }
    public OffsetDateTime getCreatedAt() { return createdAt; }
    public void setCreatedAt(OffsetDateTime createdAt) { this.createdAt = createdAt; }
    public OffsetDateTime getClosedAt() { return closedAt; }
    public void setClosedAt(OffsetDateTime closedAt) { this.closedAt = closedAt; }
    public Set<UUID> getMemberIds() { return memberIds; }
    public void setMemberIds(Set<UUID> memberIds) { this.memberIds = memberIds; }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (!(o instanceof Trip t)) return false;
        return Objects.equals(id, t.id);
    }

    @Override
    public int hashCode() { return Objects.hash(id); }
}
