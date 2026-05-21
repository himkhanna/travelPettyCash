package ae.gov.pdd.pettycash.trip;

import jakarta.persistence.*;
import java.time.OffsetDateTime;
import java.util.HashSet;
import java.util.Set;

@Entity
@Table(name = "trips")
public class TripEntity {
    @Id
    private String id;
    @Column(nullable = false)
    private String name;
    @Column(name = "country_code", nullable = false)
    private String countryCode;
    @Column(name = "country_name", nullable = false)
    private String countryName;
    @Column(nullable = false)
    private String currency;
    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private TripStatus status;
    @Column(name = "created_by", nullable = false)
    private String createdBy;
    @Column(name = "leader_id", nullable = false)
    private String leaderId;
    @Column(name = "total_budget_minor", nullable = false)
    private long totalBudgetMinor;
    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt;
    @Column(name = "closed_at")
    private OffsetDateTime closedAt;

    @ElementCollection
    @CollectionTable(name = "trip_members", joinColumns = @JoinColumn(name = "trip_id"))
    @Column(name = "user_id")
    private Set<String> memberIds = new HashSet<>();

    protected TripEntity() {}

    public TripEntity(String id, String name, String countryCode, String countryName,
                      String currency, TripStatus status, String createdBy, String leaderId,
                      Set<String> memberIds, long totalBudgetMinor, OffsetDateTime createdAt) {
        this.id = id; this.name = name;
        this.countryCode = countryCode; this.countryName = countryName;
        this.currency = currency; this.status = status;
        this.createdBy = createdBy; this.leaderId = leaderId;
        this.memberIds = new HashSet<>(memberIds);
        this.totalBudgetMinor = totalBudgetMinor;
        this.createdAt = createdAt;
    }

    public String getId() { return id; }
    public String getName() { return name; }
    public void setName(String v) { this.name = v; }
    public String getCountryCode() { return countryCode; }
    public String getCountryName() { return countryName; }
    public String getCurrency() { return currency; }
    public TripStatus getStatus() { return status; }
    public void setStatus(TripStatus v) { this.status = v; }
    public String getCreatedBy() { return createdBy; }
    public String getLeaderId() { return leaderId; }
    public void setLeaderId(String v) { this.leaderId = v; }
    public long getTotalBudgetMinor() { return totalBudgetMinor; }
    public void setTotalBudgetMinor(long v) { this.totalBudgetMinor = v; }
    public OffsetDateTime getCreatedAt() { return createdAt; }
    public OffsetDateTime getClosedAt() { return closedAt; }
    public void setClosedAt(OffsetDateTime v) { this.closedAt = v; }
    public Set<String> getMemberIds() { return memberIds; }
    public void setMemberIds(Set<String> v) { this.memberIds = new HashSet<>(v); }
}
