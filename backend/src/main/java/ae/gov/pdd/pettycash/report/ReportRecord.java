package ae.gov.pdd.pettycash.report;

import jakarta.persistence.*;

import java.time.OffsetDateTime;
import java.util.Objects;
import java.util.UUID;

/**
 * Persistence row for a generated report. See CLAUDE.md §10. Bytes live in
 * MinIO at {@link #objectKey}; this table records the metadata for audit and
 * for the eventual signing step (ADR-003).
 */
@Entity
@Table(name = "report_record")
public class ReportRecord {

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Column(name = "trip_id", nullable = false)
    private UUID tripId;

    @Enumerated(EnumType.STRING)
    @Column(name = "type", nullable = false, length = 16)
    private ReportType type;

    @Enumerated(EnumType.STRING)
    @Column(name = "format", nullable = false, length = 8)
    private ReportFormat format;

    @Column(name = "scope_user_id")
    private UUID scopeUserId;

    @Column(name = "object_key", nullable = false, length = 512)
    private String objectKey;

    @Column(name = "sha256", nullable = false, length = 64, columnDefinition = "CHAR(64)")
    private String sha256;

    @Column(name = "created_by", nullable = false)
    private UUID createdBy;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt = OffsetDateTime.now();

    public ReportRecord() {}

    public UUID getId() { return id; }
    public void setId(UUID id) { this.id = id; }
    public UUID getTripId() { return tripId; }
    public void setTripId(UUID tripId) { this.tripId = tripId; }
    public ReportType getType() { return type; }
    public void setType(ReportType type) { this.type = type; }
    public ReportFormat getFormat() { return format; }
    public void setFormat(ReportFormat format) { this.format = format; }
    public UUID getScopeUserId() { return scopeUserId; }
    public void setScopeUserId(UUID scopeUserId) { this.scopeUserId = scopeUserId; }
    public String getObjectKey() { return objectKey; }
    public void setObjectKey(String objectKey) { this.objectKey = objectKey; }
    public String getSha256() { return sha256; }
    public void setSha256(String sha256) { this.sha256 = sha256; }
    public UUID getCreatedBy() { return createdBy; }
    public void setCreatedBy(UUID createdBy) { this.createdBy = createdBy; }
    public OffsetDateTime getCreatedAt() { return createdAt; }
    public void setCreatedAt(OffsetDateTime createdAt) { this.createdAt = createdAt; }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (!(o instanceof ReportRecord r)) return false;
        return Objects.equals(id, r.id);
    }

    @Override
    public int hashCode() { return Objects.hash(id); }
}
