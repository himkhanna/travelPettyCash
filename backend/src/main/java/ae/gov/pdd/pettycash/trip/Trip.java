package ae.gov.pdd.pettycash.trip;

import jakarta.persistence.CollectionTable;
import jakarta.persistence.Column;
import jakarta.persistence.ElementCollection;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.FetchType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.Table;

import java.time.Instant;
import java.util.HashSet;
import java.util.Set;
import java.util.UUID;

@Entity
@Table(name = "trips")
public class Trip {

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "name", nullable = false, length = 128)
    private String name;

    @Column(name = "country_code", nullable = false, length = 2)
    private String countryCode;

    @Column(name = "country_name", nullable = false, length = 128)
    private String countryName;

    @Column(name = "currency", nullable = false, length = 3)
    private String currency;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 16)
    private TripStatus status;

    @Column(name = "created_by_id", nullable = false)
    private UUID createdById;

    @Column(name = "leader_id", nullable = false)
    private UUID leaderId;

    /**
     * BIGINT minor units (CLAUDE.md §6). Currency lives on the trip — every
     * Money attached to this trip uses {@link #currency}.
     */
    @Column(name = "total_budget_minor", nullable = false)
    private long totalBudgetMinor;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt = Instant.now();

    @Column(name = "closed_at")
    private Instant closedAt;

    @ElementCollection(fetch = FetchType.EAGER)
    @CollectionTable(
        name = "trip_members",
        joinColumns = @JoinColumn(name = "trip_id")
    )
    @Column(name = "user_id")
    private Set<UUID> memberIds = new HashSet<>();

    protected Trip() {
        // JPA
    }

    public Trip(
        UUID id,
        String name,
        String countryCode,
        String countryName,
        String currency,
        TripStatus status,
        UUID createdById,
        UUID leaderId,
        long totalBudgetMinor,
        Set<UUID> memberIds
    ) {
        this.id = id;
        this.name = name;
        this.countryCode = countryCode;
        this.countryName = countryName;
        this.currency = currency;
        this.status = status;
        this.createdById = createdById;
        this.leaderId = leaderId;
        this.totalBudgetMinor = totalBudgetMinor;
        this.memberIds = new HashSet<>(memberIds);
    }

    public UUID getId() { return id; }
    public String getName() { return name; }
    public String getCountryCode() { return countryCode; }
    public String getCountryName() { return countryName; }
    public String getCurrency() { return currency; }
    public TripStatus getStatus() { return status; }
    public UUID getCreatedById() { return createdById; }
    public UUID getLeaderId() { return leaderId; }
    public long getTotalBudgetMinor() { return totalBudgetMinor; }
    public Instant getCreatedAt() { return createdAt; }
    public Instant getClosedAt() { return closedAt; }
    public Set<UUID> getMemberIds() { return memberIds; }

    public void close(Instant at) {
        this.status = TripStatus.CLOSED;
        this.closedAt = at;
    }
}
