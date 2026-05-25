package ae.gov.pdd.pettycash.report.schedule;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalTime;
import java.time.ZoneOffset;
import java.util.UUID;

/**
 * One scheduled report delivery. Each tick of the runner finds active
 * schedules with {@code nextRunAt <= now}, generates / fan-outs the
 * report, then advances {@code nextRunAt} by one cadence step.
 */
@Entity
@Table(name = "report_schedules")
public class ReportSchedule {

    public enum Scope { TRIP, MISSION }
    public enum Kind { DAILY }

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @Enumerated(EnumType.STRING)
    @Column(name = "scope", nullable = false, length = 16)
    private Scope scope;

    @Column(name = "scope_id", nullable = false)
    private UUID scopeId;

    @Enumerated(EnumType.STRING)
    @Column(name = "kind", nullable = false, length = 32)
    private Kind kind;

    @Column(name = "utc_hour", nullable = false)
    private short utcHour;

    @Column(name = "active", nullable = false)
    private boolean active = true;

    @Column(name = "created_by_id", nullable = false)
    private UUID createdById;

    @Column(name = "last_run_at")
    private Instant lastRunAt;

    @Column(name = "next_run_at", nullable = false)
    private Instant nextRunAt;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt = Instant.now();

    protected ReportSchedule() { /* JPA */ }

    public ReportSchedule(
        UUID id, Scope scope, UUID scopeId, Kind kind,
        int utcHour, UUID createdById
    ) {
        this.id = id;
        this.scope = scope;
        this.scopeId = scopeId;
        this.kind = kind;
        this.utcHour = (short) utcHour;
        this.createdById = createdById;
        this.nextRunAt = computeNext(Instant.now(), utcHour);
    }

    public UUID getId() { return id; }
    public Scope getScope() { return scope; }
    public UUID getScopeId() { return scopeId; }
    public Kind getKind() { return kind; }
    public short getUtcHour() { return utcHour; }
    public boolean isActive() { return active; }
    public UUID getCreatedById() { return createdById; }
    public Instant getLastRunAt() { return lastRunAt; }
    public Instant getNextRunAt() { return nextRunAt; }
    public Instant getCreatedAt() { return createdAt; }

    public void setActive(boolean v) { this.active = v; }
    public void setUtcHour(int v) {
        this.utcHour = (short) v;
        this.nextRunAt = computeNext(Instant.now(), v);
    }

    /**
     * Mark this schedule as just-fired and advance {@code nextRunAt} to
     * the next cadence boundary. For DAILY that's "the configured UTC
     * hour, tomorrow." Cron-style cadences would slot in here.
     */
    public void markFired(Instant at) {
        this.lastRunAt = at;
        this.nextRunAt = computeNext(at, utcHour);
    }

    private static Instant computeNext(Instant now, int utcHour) {
        // Pick today's run time; if that's already past, roll to tomorrow.
        LocalDate today = now.atZone(ZoneOffset.UTC).toLocalDate();
        Instant todayRun = today.atTime(LocalTime.of(utcHour, 0))
            .toInstant(ZoneOffset.UTC);
        if (now.isBefore(todayRun)) return todayRun;
        return today.plusDays(1).atTime(LocalTime.of(utcHour, 0))
            .toInstant(ZoneOffset.UTC);
    }
}
