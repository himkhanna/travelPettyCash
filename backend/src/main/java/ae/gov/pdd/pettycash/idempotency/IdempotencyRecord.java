package ae.gov.pdd.pettycash.idempotency;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EmbeddedId;
import jakarta.persistence.Embeddable;
import jakarta.persistence.Table;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

import java.io.Serializable;
import java.time.OffsetDateTime;
import java.util.Objects;
import java.util.UUID;

/**
 * Persisted Idempotency-Key record. See CLAUDE.md §9 (24h window).
 *
 * <p>TODO: nightly purge of records older than 24h (Spring @Scheduled or a DB cron job).
 */
@Entity
@Table(name = "idempotency_record")
public class IdempotencyRecord {

    @EmbeddedId
    private Pk id;

    @Column(name = "request_hash", nullable = false, length = 64)
    private String requestHash;

    @Column(name = "response_body", columnDefinition = "jsonb")
    @JdbcTypeCode(SqlTypes.JSON)
    private String responseBody;

    @Column(name = "status_code", nullable = false)
    private int statusCode;

    @Column(name = "created_at", nullable = false)
    private OffsetDateTime createdAt = OffsetDateTime.now();

    public IdempotencyRecord() {}

    public IdempotencyRecord(String key, UUID actorId, String requestHash,
                             String responseBody, int statusCode) {
        this.id = new Pk(key, actorId);
        this.requestHash = requestHash;
        this.responseBody = responseBody;
        this.statusCode = statusCode;
        this.createdAt = OffsetDateTime.now();
    }

    public Pk getId() { return id; }
    public void setId(Pk id) { this.id = id; }
    public String getRequestHash() { return requestHash; }
    public void setRequestHash(String requestHash) { this.requestHash = requestHash; }
    public String getResponseBody() { return responseBody; }
    public void setResponseBody(String responseBody) { this.responseBody = responseBody; }
    public int getStatusCode() { return statusCode; }
    public void setStatusCode(int statusCode) { this.statusCode = statusCode; }
    public OffsetDateTime getCreatedAt() { return createdAt; }
    public void setCreatedAt(OffsetDateTime createdAt) { this.createdAt = createdAt; }

    @Embeddable
    public static class Pk implements Serializable {

        @Column(name = "key", nullable = false, length = 80)
        private String key;

        @Column(name = "actor_id", nullable = false)
        private UUID actorId;

        public Pk() {}

        public Pk(String key, UUID actorId) {
            this.key = key;
            this.actorId = actorId;
        }

        public String getKey() { return key; }
        public void setKey(String key) { this.key = key; }
        public UUID getActorId() { return actorId; }
        public void setActorId(UUID actorId) { this.actorId = actorId; }

        @Override
        public boolean equals(Object o) {
            if (this == o) return true;
            if (!(o instanceof Pk pk)) return false;
            return Objects.equals(key, pk.key) && Objects.equals(actorId, pk.actorId);
        }

        @Override
        public int hashCode() { return Objects.hash(key, actorId); }
    }
}
