package ae.gov.pdd.pettycash.report.schedule;

import ae.gov.pdd.pettycash.mission.Mission;
import ae.gov.pdd.pettycash.mission.MissionRepository;
import ae.gov.pdd.pettycash.notification.NotificationRefType;
import ae.gov.pdd.pettycash.notification.NotificationService;
import ae.gov.pdd.pettycash.notification.NotificationType;
import ae.gov.pdd.pettycash.trip.Trip;
import ae.gov.pdd.pettycash.trip.TripRepository;
import ae.gov.pdd.pettycash.user.User;
import ae.gov.pdd.pettycash.user.UserRepository;
import ae.gov.pdd.pettycash.user.UserRole;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

/**
 * Cron-style runner for scheduled report deliveries. Polls every five
 * minutes for active schedules whose {@code next_run_at} has passed and
 * fans out a REPORT_READY notification to every admin / super-admin.
 *
 * <p>Generation is deliberately NOT done here — the notification payload
 * carries enough metadata ({scope, scopeId, kind, date, scopeName}) for
 * the existing /api/v1/reports/... endpoints to render fresh bytes when
 * the recipient clicks through. This keeps the runner cheap, idempotent,
 * and free of MinIO writes.
 */
@Component
public class ReportScheduleRunner {

    private static final Logger LOG =
        LoggerFactory.getLogger(ReportScheduleRunner.class);

    private final ReportScheduleRepository schedules;
    private final NotificationService notifications;
    private final UserRepository users;
    private final TripRepository trips;
    private final MissionRepository missions;

    ReportScheduleRunner(
        ReportScheduleRepository schedules,
        NotificationService notifications,
        UserRepository users,
        TripRepository trips,
        MissionRepository missions
    ) {
        this.schedules = schedules;
        this.notifications = notifications;
        this.users = users;
        this.trips = trips;
        this.missions = missions;
    }

    /**
     * Fires every five minutes. Cheap query against the partial index
     * on (active, next_run_at). Initial delay avoids running at boot
     * before the DB is fully warm.
     */
    @Scheduled(fixedDelay = 5 * 60 * 1000L, initialDelay = 60 * 1000L)
    @Transactional
    public void runDue() {
        final Instant now = Instant.now();
        List<ReportSchedule> due =
            schedules.findByActiveTrueAndNextRunAtLessThanEqual(now);
        if (due.isEmpty()) return;
        LOG.info("Report schedules: firing {} due delivery(ies).", due.size());

        // Cache admin recipients once per tick — same set fans out to all.
        Set<UUID> adminRecipients = new LinkedHashSet<>();
        for (User u : users.findAll()) {
            if (u.getRole() == UserRole.ADMIN
                || u.getRole() == UserRole.SUPER_ADMIN) {
                adminRecipients.add(u.getId());
            }
        }
        if (adminRecipients.isEmpty()) {
            LOG.warn("Report schedules: no admins to notify; skipping {} due.",
                due.size());
            return;
        }

        final LocalDate today = now.atZone(ZoneOffset.UTC).toLocalDate();

        for (ReportSchedule s : due) {
            try {
                fire(s, today, adminRecipients);
                s.markFired(now);
                schedules.save(s);
            } catch (Exception e) {
                LOG.warn("Report schedule {} fire failed; will retry next tick.",
                    s.getId(), e);
                // Intentionally do NOT advance nextRunAt — retry next poll.
            }
        }
    }

    private void fire(ReportSchedule s, LocalDate today, Set<UUID> recipients) {
        String scopeName = resolveScopeName(s);
        Map<String, Object> payload = new LinkedHashMap<>();
        payload.put("scope", s.getScope().name().toLowerCase());
        payload.put("scopeId", s.getScopeId().toString());
        payload.put("kind", s.getKind().name().toLowerCase());
        payload.put("date", today.toString());
        payload.put("scopeName", scopeName);
        // tripName / missionName keeps the existing payload contract used
        // by the trip-close fan-out so mobile rendering can be uniform.
        if (s.getScope() == ReportSchedule.Scope.TRIP) {
            payload.put("tripName", scopeName);
        } else {
            payload.put("missionName", scopeName);
        }
        payload.put("reason", "schedule");
        notifications.fanOut(
            NotificationType.REPORT_READY,
            false,
            s.getScope() == ReportSchedule.Scope.TRIP
                ? NotificationRefType.TRIP
                : NotificationRefType.TRIP, // No MISSION ref type yet — reuse TRIP.
            s.getScopeId(),
            payload,
            recipients
        );
    }

    private String resolveScopeName(ReportSchedule s) {
        if (s.getScope() == ReportSchedule.Scope.TRIP) {
            return trips.findById(s.getScopeId())
                .map(Trip::getName).orElse("Trip");
        }
        return missions.findById(s.getScopeId())
            .map(Mission::getName).orElse("Mission");
    }
}
