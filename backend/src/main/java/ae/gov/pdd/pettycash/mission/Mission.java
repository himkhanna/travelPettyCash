package ae.gov.pdd.pettycash.mission;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.Instant;
import java.util.UUID;

/**
 * Diplomatic / operational mission grouping multiple {@code Trip}s. One
 * Mission has many Trips; Trips also optionally reference a Mission. See
 * {@code V007__missions.sql} for the table.
 */
@Entity
@Table(name = "missions")
public class Mission {

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "name", nullable = false, length = 160)
    private String name;

    @Column(name = "name_ar", length = 160)
    private String nameAr;

    @Column(name = "code", nullable = false, unique = true, length = 32)
    private String code;

    @Column(name = "description", length = 500)
    private String description;

    @Column(name = "parent_mission_id")
    private UUID parentMissionId;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 16)
    private MissionStatus status = MissionStatus.ACTIVE;

    @Column(name = "created_by_id", nullable = false)
    private UUID createdById;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt = Instant.now();

    @Column(name = "closed_at")
    private Instant closedAt;

    protected Mission() {
        // JPA
    }

    public Mission(
        UUID id,
        String name,
        String nameAr,
        String code,
        String description,
        UUID parentMissionId,
        UUID createdById
    ) {
        this.id = id;
        this.name = name;
        this.nameAr = nameAr;
        this.code = code;
        this.description = description;
        this.parentMissionId = parentMissionId;
        this.createdById = createdById;
    }

    public UUID getId() { return id; }
    public String getName() { return name; }
    public String getNameAr() { return nameAr; }
    public String getCode() { return code; }
    public String getDescription() { return description; }
    public UUID getParentMissionId() { return parentMissionId; }
    public MissionStatus getStatus() { return status; }
    public UUID getCreatedById() { return createdById; }
    public Instant getCreatedAt() { return createdAt; }
    public Instant getClosedAt() { return closedAt; }

    public void close(Instant at) {
        this.status = MissionStatus.CLOSED;
        this.closedAt = at;
    }
}
